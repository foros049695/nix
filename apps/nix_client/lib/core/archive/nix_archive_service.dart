import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import '../database/repositories.dart';

/// Serviço oficial de publicação imutável Nix Archive v1 (`nix.archive.article.v1`, Fase 7).
/// Realiza canonicalização determinística, hash SHA-256 content-addressed, assinatura Ed25519,
/// sanitização HTML anti-XSS e grafo de alegações/refutações/substituições (`supersedes`).
class NixArchiveService {
  static const String articleSchemaV1 = 'nix.archive.article.v1';
  static const String refutationSchemaV1 = 'nix.archive.refutation.v1';

  final ArchiveRepository archiveRepo;
  NixArchiveService(this.archiveRepo);

  /// Sanitizador HTML estrito: remove scripts, iframes, objetos embebidos, SVG ativo, handlers on* e URIs javascript:/data:.
  static String sanitizeRichTextHtml(String rawHtml) {
    var s = rawHtml;
    // Remove blocos completos perigosos (case-insensitive, multiline)
    s = s.replaceAll(
      RegExp(r'<\s*(script|iframe|object|embed|svg|style|form|meta|link)\b[^>]*>.*?<\s*/\s*\1\s*>',
          caseSensitive: false, dotAll: true),
      '',
    );
    // Remove tags auto-fechadas perigosas remanescentes
    s = s.replaceAll(
      RegExp(r'<\s*/?\s*(script|iframe|object|embed|svg|style|form|meta|link)\b[^>]*>',
          caseSensitive: false),
      '',
    );
    // Remove manipuladores de evento inline (onclick=, onerror=, onload=, etc.)
    s = s.replaceAll(
      RegExp(r'''\s+on[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)''',
          caseSensitive: false),
      '',
    );
    // Bloqueia pseudoprotocolos javascript:, vbscript:, data:text/html
    s = s.replaceAll(
      RegExp(r'''(?:javascript|vbscript|data)\s*:''', caseSensitive: false),
      'blocked:',
    );
    return s.trim();
  }

  /// Gera bytes canônicos JSON ordenados recursivamente para estabilidade de hash entre plataformas.
  static Uint8List canonicalizeJsonBytes(Map<String, dynamic> obj) {
    dynamic sortNode(dynamic node) {
      if (node is Map) {
        final keys = node.keys.map((k) => k.toString()).toList()..sort();
        return <String, dynamic>{
          for (final k in keys) k: sortNode(node[k]),
        };
      } else if (node is List) {
        return node.map(sortNode).toList();
      }
      return node;
    }

    return Uint8List.fromList(utf8.encode(jsonEncode(sortNode(obj))));
  }

  /// Calcula hash SHA-256 hexadecimal de 64 caracteres (compatível com `archive_objects.hash`).
  static String computeContentHashHex(List<int> canonicalBytes) {
    return std_crypto.sha256.convert(canonicalBytes).toString();
  }

  Future<void> ensurePersonaRegistered({
    required String personaId,
    required NixIdentity identity,
    required KeyMaterialRepository keyMaterialRepo,
    String keyRef = 'vault:identity_main',
  }) async {
    final existingKey = await keyMaterialRepo.getKeyMaterial(keyRef);
    if (existingKey == null) {
      await keyMaterialRepo.storeKeyMaterial(
        id: keyRef,
        purpose: 'archive_author',
        wrappedBytes: Uint8List.fromList([1]),
        wrappingKeyRef: 'keyvault:master',
      );
    }
    await archiveRepo.upsertPersona(
      id: personaId,
      publicKey: Uint8List.fromList(identity.ed25519PublicKey.bytes),
      keyRef: keyRef,
    );
  }

  /// Publica artigo canônico `nix.archive.article.v1` assinado com Ed25519 e sanitizado contra XSS.
  Future<String> publishArticle({
    required NixIdentity author,
    required String title,
    required String rawHtmlBody,
    List<({String claimId, String text})> claims = const [],
    String? supersedesHash,
    String visibility = 'public',
    int? createdAtMs,
  }) async {
    final now = createdAtMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    final cleanHtml = sanitizeRichTextHtml(rawHtmlBody);

    final canonicalObj = <String, dynamic>{
      'schema': articleSchemaV1,
      'title': title.trim(),
      'bodyHtml': cleanHtml,
      'authorEd25519': author.ed25519PublicHex,
      'visibility': visibility,
      'createdAt': now,
      if (supersedesHash != null) 'supersedes': supersedesHash,
      'claims': claims
          .map((c) => {'claimId': c.claimId, 'text': c.text.trim()})
          .toList(),
    };

    final canonicalBytes = canonicalizeJsonBytes(canonicalObj);
    final hashHex = computeContentHashHex(canonicalBytes);
    final sig = await author.sign(canonicalBytes);

    await archiveRepo.upsertObject(
      hash: hashHex,
      kind: 'article',
      canonicalBytes: canonicalBytes,
      authorPublic: Uint8List.fromList(author.ed25519PublicKey.bytes),
      signature: Uint8List.fromList(sig),
      supersedesHash: supersedesHash,
      visibility: visibility,
      createdAt: now,
    );

    for (final c in claims) {
      await archiveRepo.upsertClaim(
        objectHash: hashHex,
        claimId: c.claimId,
        text: c.text.trim(),
      );
    }
    return hashHex;
  }

  /// Publica refutação assinada apontando explicitamente para `(targetHash, targetClaimId)`.
  Future<String> publishRefutation({
    required NixIdentity author,
    required String targetHash,
    required String targetClaimId,
    required String rationaleHtml,
    String visibility = 'public',
    int? createdAtMs,
  }) async {
    final now = createdAtMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    final cleanRationale = sanitizeRichTextHtml(rationaleHtml);

    final canonicalObj = <String, dynamic>{
      'schema': refutationSchemaV1,
      'targetHash': targetHash,
      'targetClaimId': targetClaimId,
      'rationaleHtml': cleanRationale,
      'authorEd25519': author.ed25519PublicHex,
      'visibility': visibility,
      'createdAt': now,
    };

    final canonicalBytes = canonicalizeJsonBytes(canonicalObj);
    final hashHex = computeContentHashHex(canonicalBytes);
    final sig = await author.sign(canonicalBytes);

    await archiveRepo.upsertObject(
      hash: hashHex,
      kind: 'refutation',
      canonicalBytes: canonicalBytes,
      authorPublic: Uint8List.fromList(author.ed25519PublicKey.bytes),
      signature: Uint8List.fromList(sig),
      visibility: visibility,
      createdAt: now,
    );

    await archiveRepo.insertRefutation(
      refutationHash: hashHex,
      targetHash: targetHash,
      targetClaimId: targetClaimId,
    );
    return hashHex;
  }

  /// Recalcula SHA-256 dos bytes canônicos e verifica a assinatura Ed25519 do objeto salvo.
  Future<bool> verifyStoredObject(String objectHash) async {
    final row = await archiveRepo.getObject(objectHash);
    if (row == null) return false;
    final bytes = row['canonical_bytes'] as List<int>;
    final authorPub = row['author_public'] as List<int>;
    final sig = row['signature'] as List<int>;

    final actualHash = computeContentHashHex(bytes);
    if (actualHash != objectHash) return false;

    return NixIdentity.verify(
      message: bytes,
      signatureBytes: sig,
      ed25519PublicKey: SimplePublicKey(authorPub, type: KeyPairType.ed25519),
    );
  }
}
