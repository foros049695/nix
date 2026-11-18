import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:test/test.dart';

void main() {
  group('DoubleRatchet State Corruption Probe (CRY01 / Marco P0-1)', () {
    test('forged message is rejected and subsequent legitimate message succeeds (candidate state)', () async {
      final sharedSecret = SecretKeyData.random(length: 32);
      final spk = await X25519().newKeyPair();

      final initiator = await DoubleRatchet.initInitiator(
        sharedSecret: sharedSecret,
        responderRatchetPublicKey: await spk.extractPublicKey(),
      );
      final responder = await DoubleRatchet.initResponder(
        sharedSecret: sharedSecret,
        responderRatchetKeyPair: spk,
      );

      final legitMsg = await initiator.encrypt(utf8.encode('legitimate message'));
      final fakeKey = await (await X25519().newKeyPair()).extractPublicKey();

      // Forja um cabeçalho DH com a mesma chave de mensagem legítima
      final forged = RatchetCiphertext(
        header: RatchetHeader(
          dhPublicBytes: Uint8List.fromList(fakeKey.bytes),
          previousChainLength: 0,
          messageNumber: 0,
        ),
        body: legitMsg.body,
      );

      // 1. Mensagem forjada DEVE ser rejeitada categoricamente
      await expectLater(
        () async => await responder.decrypt(forged),
        throwsA(anything),
      );

      // 2. Com a execução em estado candidato, o estado interno NÃO foi corrompido!
      // A mensagem legítima DEVE ser decifrada perfeitamente:
      final cleartextBytes = await responder.decrypt(legitMsg);
      expect(utf8.decode(cleartextBytes), equals('legitimate message'));
    });

    test('recursive canonicalization produces identical signatures regardless of map key insertion order', () async {
      final signer = await NixIdentity.generate();
      final record1 = await SignedRecord.create(
        signer: signer,
        recordType: 'test_record',
        payload: {
          'b': 1,
          'a': {
            'z': 'last',
            'm': [1, 2, 3],
            'a': 'first',
          },
        },
      );

      expect(await record1.verify(), isTrue);
    });

    test('ReplayGuard purges out-of-order expired nonces completely', () {
      final guard = ReplayGuard(maxEntries: 10);
      final now = DateTime.now().millisecondsSinceEpoch;

      // Insere nonces com expirações fora de ordem cronológica
      guard.accept(nonceHex: 'nonce_late', expiresAtEpochMs: now + 50000, nowEpochMs: now);
      guard.accept(nonceHex: 'nonce_early', expiresAtEpochMs: now - 1000, nowEpochMs: now);

      expect(guard.accept(nonceHex: 'nonce_late', expiresAtEpochMs: now + 50000, nowEpochMs: now), isFalse);
    });
  });
}
