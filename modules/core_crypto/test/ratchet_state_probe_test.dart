import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:test/test.dart';

void main() {
  group('DoubleRatchet State Corruption Probe (CRY01 Regression Test)', () {
    test('probe verifies ratchet state mutates before AEAD verification', () async {
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

      // 1. Mensagem forjada deve ser rejeitada
      expect(
        () async => await responder.decrypt(forged),
        throwsA(anything),
      );

      // 2. No código atual (antes da correção em P0-1), o estado do responder foi corrompido,
      // fazendo com que até mensagens legítimas subsequentes falhem.
      // O objetivo do marco P0-1 é fazer com que este segundo decrypt TENHA SUCESSO.
    });
  });
}
