import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:test/test.dart';

void main() {
  group('NixIdentity', () {
    test('generates distinct identities and verifiable Ed25519 signatures', () async {
      final alice = await NixIdentity.generate();
      final bob = await NixIdentity.generate();

      expect(alice.publicId, startsWith('NIX-'));
      expect(alice.deterministicHandle, startsWith('NX-'));
      expect(alice.publicId, isNot(equals(bob.publicId)));

      final msg = utf8.encode('handshake-v4');
      final sig = await alice.sign(msg);
      expect(
        await NixIdentity.verify(
          message: msg,
          signatureBytes: sig,
          ed25519PublicKey: alice.ed25519PublicKey,
        ),
        isTrue,
      );
      expect(
        await NixIdentity.verify(
          message: utf8.encode('tampered'),
          signatureBytes: sig,
          ed25519PublicKey: alice.ed25519PublicKey,
        ),
        isFalse,
      );
    });
  });

  group('SealedEnvelope (XChaCha20-Poly1305)', () {
    test('seals and opens payload with AAD and rejects tampered ciphertext or AAD', () async {
      final key = SecretKeyData.random(length: 32);
      final plaintext = utf8.encode('Mensagem confidencial Nix v4');
      final aad = utf8.encode('room:ch_geral');

      final payload = await SealedEnvelope.seal(key: key, plaintext: plaintext, aad: aad);
      final encoded = payload.encode();
      final decoded = SealedPayload.decode(encoded);
      final opened = await SealedEnvelope.open(key: key, payload: decoded, aad: aad);

      expect(utf8.decode(opened), equals('Mensagem confidencial Nix v4'));

      // Adulteração de AAD deve falhar autenticação Poly1305
      await expectLater(
        () => SealedEnvelope.open(
          key: key,
          payload: decoded,
          aad: utf8.encode('room:outra'),
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );

      // Adulteração de 1 bit no ciphertext deve falhar
      final mutated = Uint8List.fromList(decoded.cipherText);
      mutated[0] = mutated[0] ^ 0xFF;
      final corrupted = SealedPayload(
        nonce: decoded.nonce,
        macBytes: decoded.macBytes,
        cipherText: mutated,
      );
      await expectLater(
        () => SealedEnvelope.open(key: key, payload: corrupted, aad: aad),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('PassphraseKdf (Argon2id)', () {
    test('derives deterministic 32-byte keys given identical passphrase and salt', () async {
      const kdf = PassphraseKdf(memoryKib: 4096, iterations: 1, parallelism: 1);
      final salt = PassphraseKdf.generateSalt();
      final k1 = await kdf.deriveKey(passphrase: 'soberania-nix', salt: salt);
      final k2 = await kdf.deriveKey(passphrase: 'soberania-nix', salt: salt);
      final k3 = await kdf.deriveKey(passphrase: 'outra-senha', salt: salt);

      expect(k1.bytes.length, 32);
      expect(k1.bytes, equals(k2.bytes));
      expect(k1.bytes, isNot(equals(k3.bytes)));
    });
  });

  group('X3DH + DoubleRatchet', () {
    test('establishes symmetric secret and supports forward secrecy + out-of-order decryption', () async {
      final alice = await NixIdentity.generate();
      final bob = await NixIdentity.generate();
      final bobSpk = await X25519().newKeyPair();
      final bobOpk = await X25519().newKeyPair();
      final bobBundle = await SignedPreKeyBundle.create(
        owner: bob,
        signedPreKeyPair: bobSpk,
        oneTimePreKey: await bobOpk.extractPublicKey(),
      );

      final initResult = await X3dh.initiatorDerive(
        initiatorIdentity: alice,
        responderBundle: bobBundle,
      );
      final respSecret = await X3dh.responderDerive(
        responderIdentity: bob,
        responderSignedPreKey: bobSpk,
        initiatorX25519Identity: alice.x25519PublicKey,
        initiatorEphemeralPublicKey: initResult.ephemeralKeyPair.publicKey,
        responderOneTimePreKey: bobOpk,
      );

      expect(initResult.sharedSecret.bytes, equals(respSecret.bytes));

      final bobSpkPub = await bobSpk.extractPublicKey();
      final aliceRatchet = await DoubleRatchet.initInitiator(
        sharedSecret: initResult.sharedSecret,
        responderRatchetPublicKey: bobSpkPub,
      );
      final bobRatchet = await DoubleRatchet.initResponder(
        sharedSecret: respSecret,
        responderRatchetKeyPair: bobSpk,
      );

      // Alice envia m1 e m2; Bob recebe fora de ordem (m2 antes de m1)
      final c1 = await aliceRatchet.encrypt(utf8.encode('msg-1'));
      final c2 = await aliceRatchet.encrypt(utf8.encode('msg-2'));

      // Serialização binária compacta de RatchetCiphertext (P0-5)
      final rawBytes = c1.encode();
      final decodedC1 = RatchetCiphertext.decode(rawBytes);
      expect(decodedC1.header.messageNumber, equals(c1.header.messageNumber));
      expect(decodedC1.header.previousChainLength, equals(c1.header.previousChainLength));
      expect(decodedC1.header.dhPublicBytes, equals(c1.header.dhPublicBytes));
      expect(decodedC1.body.encode(), equals(c1.body.encode()));

      final d2 = await bobRatchet.decrypt(c2);
      final d1 = await bobRatchet.decrypt(decodedC1);
      expect(utf8.decode(d2), 'msg-2');
      expect(utf8.decode(d1), 'msg-1');

      // Bob responde disparando passo DH Ratchet
      final c3 = await bobRatchet.encrypt(utf8.encode('pong-bob'));
      final d3 = await aliceRatchet.decrypt(c3);
      expect(utf8.decode(d3), 'pong-bob');
    });
  });

  group('SignedRecord & ReplayGuard', () {
    test('accepts valid signed record once, rejects replay and expiration', () async {
      final trader = await NixIdentity.generate();
      final guard = ReplayGuard(maxEntries: 64);
      final baseTime = DateTime.utc(2026, 11, 18, 12, 0);

      final record = await SignedRecord.create(
        signer: trader,
        recordType: 'monero_p2p_order',
        payload: {'priceBrl': 850.0, 'side': 'sell'},
        ttl: const Duration(hours: 2),
        now: baseTime,
      );

      // 1ª verificação aceita
      expect(
        await record.verify(now: baseTime.add(const Duration(minutes: 5)), replayGuard: guard),
        isTrue,
      );

      // 2ª verificação com mesmo nonce deve ser bloqueada (anti-replay)
      expect(
        await record.verify(now: baseTime.add(const Duration(minutes: 6)), replayGuard: guard),
        isFalse,
      );

      // Após expiração também deve falhar mesmo sem ReplayGuard
      expect(
        await record.verify(now: baseTime.add(const Duration(hours: 3))),
        isFalse,
      );
    });
  });
}
