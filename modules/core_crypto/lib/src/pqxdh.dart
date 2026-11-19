import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';
import 'core_crypto.dart';

/// Contrato abstrato de encapsulamento pós-quântico (KEM, ex: ML-KEM-768 / Kyber768).
abstract class PqKemProvider {
  String get algorithmName;
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
    Uint8List recipientPqPublicKey,
  );
  Future<Uint8List> decapsulate({
    required Uint8List ciphertext,
    required Uint8List recipientPqSecretKey,
  });
}

/// Combinador híbrido PQXDH conforme Fase 9:
/// IKM = K_X3DH (32B) || K_PQKEM (32B), vinculado criptograficamente ao transcript
/// das identidades Ed25519 e do ciphertext pós-quântico via HKDF-SHA256 com separação de domínio.
class PqxdhCombiner {
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const String domainLabel = 'Nix-PQXDH-Hybrid-v1';

  static Future<SecretKeyData> deriveHybridRootSecret({
    required SecretKeyData classicalX3dhSecret,
    required Uint8List pqKemSharedSecret,
    required Uint8List initiatorEd25519Public,
    required Uint8List responderEd25519Public,
    required Uint8List pqCiphertext,
  }) async {
    if (classicalX3dhSecret.bytes.length != 32) {
      throw ArgumentError('Segredo X3DH clássico deve possuir 32 bytes.');
    }
    if (pqKemSharedSecret.length < 32) {
      throw ArgumentError('Segredo PQ-KEM deve possuir ao menos 32 bytes.');
    }
    if (pqKemSharedSecret.every((b) => b == 0)) {
      throw StateError('Segredo PQ-KEM nulo rejeitado (fail-closed).');
    }

    final transcriptHash = std_crypto.sha256.convert([
      ...utf8.encode(domainLabel),
      ...initiatorEd25519Public,
      ...responderEd25519Public,
      ...pqCiphertext,
    ]).bytes;

    final ikm = BytesBuilder(copy: false)
      ..add(classicalX3dhSecret.bytes)
      ..add(pqKemSharedSecret);

    final out = await _hkdf.deriveKey(
      secretKey: SecretKey(ikm.toBytes()),
      nonce: transcriptHash,
      info: utf8.encode(domainLabel),
    );
    return out.extract();
  }
}

/// Manifesto de lançamento assinado via Ed25519 para validação de integridade off-grid/reproduzível (Fases 5 & 9).
class SignedReleaseManifest {
  final String version;
  final String artifactName;
  final String sha256Hex;
  final int byteSize;
  final int issuedAtUnix;
  final String signerEd25519Hex;
  final String signatureHex;

  const SignedReleaseManifest({
    required this.version,
    required this.artifactName,
    required this.sha256Hex,
    required this.byteSize,
    required this.issuedAtUnix,
    required this.signerEd25519Hex,
    required this.signatureHex,
  });

  static List<int> canonicalDigestBytes({
    required String version,
    required String artifactName,
    required String sha256Hex,
    required int byteSize,
    required int issuedAtUnix,
  }) {
    return utf8.encode(jsonEncode({
      'domain': 'NIX-RELEASE-MANIFEST-V1',
      'version': version,
      'artifact': artifactName,
      'sha256': sha256Hex.toLowerCase(),
      'bytes': byteSize,
      'iat': issuedAtUnix,
    }));
  }

  static Future<SignedReleaseManifest> signArtifact({
    required NixIdentity signer,
    required String version,
    required String artifactName,
    required List<int> artifactBytes,
    int? issuedAtUnix,
  }) async {
    final iat = issuedAtUnix ?? (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000);
    final digest = std_crypto.sha256.convert(artifactBytes).toString();
    final msg = canonicalDigestBytes(
      version: version,
      artifactName: artifactName,
      sha256Hex: digest,
      byteSize: artifactBytes.length,
      issuedAtUnix: iat,
    );
    final sig = await signer.sign(msg);
    return SignedReleaseManifest(
      version: version,
      artifactName: artifactName,
      sha256Hex: digest,
      byteSize: artifactBytes.length,
      issuedAtUnix: iat,
      signerEd25519Hex: signer.ed25519PublicHex,
      signatureHex: _hex(sig),
    );
  }

  Future<bool> verifyArtifactBytes(
    List<int> artifactBytes, {
    required SimplePublicKey trustedReleaseKey,
  }) async {
    if (_hex(trustedReleaseKey.bytes).toLowerCase() !=
        signerEd25519Hex.toLowerCase()) {
      return false;
    }
    if (artifactBytes.length != byteSize) return false;
    final actualSha = std_crypto.sha256.convert(artifactBytes).toString();
    if (actualSha.toLowerCase() != sha256Hex.toLowerCase()) return false;

    final msg = canonicalDigestBytes(
      version: version,
      artifactName: artifactName,
      sha256Hex: sha256Hex,
      byteSize: byteSize,
      issuedAtUnix: issuedAtUnix,
    );
    return NixIdentity.verify(
      message: msg,
      signatureBytes: _unhex(signatureHex),
      ed25519PublicKey: trustedReleaseKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'artifactName': artifactName,
        'sha256Hex': sha256Hex,
        'byteSize': byteSize,
        'issuedAtUnix': issuedAtUnix,
        'signerEd25519Hex': signerEd25519Hex,
        'signatureHex': signatureHex,
      };

  factory SignedReleaseManifest.fromJson(Map<String, dynamic> json) =>
      SignedReleaseManifest(
        version: json['version'] as String,
        artifactName: json['artifactName'] as String,
        sha256Hex: json['sha256Hex'] as String,
        byteSize: (json['byteSize'] as num).toInt(),
        issuedAtUnix: (json['issuedAtUnix'] as num).toInt(),
        signerEd25519Hex: json['signerEd25519Hex'] as String,
        signatureHex: json['signatureHex'] as String,
      );

  static String _hex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _unhex(String hex) {
    final clean = hex.trim();
    final out = Uint8List(clean.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
