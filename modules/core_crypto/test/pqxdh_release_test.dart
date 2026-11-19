import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 9 PQXDH Hybrid Combiner & Ed25519 Signed Release Manifest', () {
    test('PqxdhCombiner vincula segredo clássico X3DH, PQ-KEM e transcript de identidades', () async {
      final alice = await NixIdentity.generate();
      final bob = await NixIdentity.generate();
      final x3dhSecret = SecretKeyData(List<int>.generate(32, (i) => i + 1));
      final pqSecret = Uint8List.fromList(List<int>.generate(32, (i) => 200 - i));
      final pqCiphertext = Uint8List.fromList(utf8.encode('mlkem768-ct-sample'));

      final root1 = await PqxdhCombiner.deriveHybridRootSecret(
        classicalX3dhSecret: x3dhSecret,
        pqKemSharedSecret: pqSecret,
        initiatorEd25519Public: Uint8List.fromList(alice.ed25519PublicKey.bytes),
        responderEd25519Public: Uint8List.fromList(bob.ed25519PublicKey.bytes),
        pqCiphertext: pqCiphertext,
      );
      expect(root1.bytes.length, 32);

      // Troca do segredo PQ-KEM deve gerar chave híbrida completamente diferente
      final alteredPq = Uint8List.fromList(pqSecret)..[0] ^= 0x01;
      final root2 = await PqxdhCombiner.deriveHybridRootSecret(
        classicalX3dhSecret: x3dhSecret,
        pqKemSharedSecret: alteredPq,
        initiatorEd25519Public: Uint8List.fromList(alice.ed25519PublicKey.bytes),
        responderEd25519Public: Uint8List.fromList(bob.ed25519PublicKey.bytes),
        pqCiphertext: pqCiphertext,
      );
      expect(root1.bytes, isNot(equals(root2.bytes)));

      // Segredo PQ-KEM zerado deve ser recusado fail-closed
      expect(
        () => PqxdhCombiner.deriveHybridRootSecret(
          classicalX3dhSecret: x3dhSecret,
          pqKemSharedSecret: Uint8List(32),
          initiatorEd25519Public: Uint8List.fromList(alice.ed25519PublicKey.bytes),
          responderEd25519Public: Uint8List.fromList(bob.ed25519PublicKey.bytes),
          pqCiphertext: pqCiphertext,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('SignedReleaseManifest assina e valida artefato offline detectando qualquer adulteração', () async {
      final releaseAuthority = await NixIdentity.generate();
      final attacker = await NixIdentity.generate();
      final apkBytes = utf8.encode('SIMULATED_REPRODUCIBLE_NIX_RELEASE_BINARY');

      final manifest = await SignedReleaseManifest.signArtifact(
        signer: releaseAuthority,
        version: '0.4.0',
        artifactName: 'nix-client-0.4.0-linux.tar.gz',
        artifactBytes: apkBytes,
      );

      expect(
        await manifest.verifyArtifactBytes(
          apkBytes,
          trustedReleaseKey: releaseAuthority.ed25519PublicKey,
        ),
        isTrue,
      );

      // Chave de assinante não confiável é rejeitada
      expect(
        await manifest.verifyArtifactBytes(
          apkBytes,
          trustedReleaseKey: attacker.ed25519PublicKey,
        ),
        isFalse,
      );

      // Adulteração de 1 byte no binário é detectada
      final altered = List<int>.from(apkBytes)..[0] ^= 0x01;
      expect(
        await manifest.verifyArtifactBytes(
          altered,
          trustedReleaseKey: releaseAuthority.ed25519PublicKey,
        ),
        isFalse,
      );
    });
  });
}
