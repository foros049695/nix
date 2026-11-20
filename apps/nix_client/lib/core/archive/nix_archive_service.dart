import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import '../database/repositories.dart';
import '../replication/replication_coordinator.dart';
import 'archive_image.dart';

/// Serviço oficial de publicação imutável Nix Archive v1 (`nix.archive.article.v1`, Fase 7 / Fase 9).
/// Realiza canonicalização determinística, hash SHA-256 content-addressed, assinatura Ed25519,
/// sanitização HTML com parser/tokenizador por whitelist estrita e grafo de alegações/refutações/substituições (`supersedes`).
class NixArchiveService {
  static const String articleSchemaV1 = 'nix.archive.article.v1';
  static const String refutationSchemaV1 = 'nix.archive.refutation.v1';

  static const Set<String> _allowedHtmlTags = {
    'p',
    'br',
    'b',
    'i',
    'em',
    'strong',
    's',
    'del',
    'u',
    'code',
    'pre',
    'blockquote',
    'ul',
    'ol',
    'li',
    'h1',
    'h2',
    'h3',
    'h4',
    'a',
    'span',
    'sup',
    'section',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
    'hr',
  };

  static const Set<String> _voidHtmlTags = {'br', 'hr'};

  static const Set<String> _dropBlockTagsWithContent = {
    'script',
    'iframe',
    'object',
    'embed',
    'svg',
    'style',
    'form',
    'meta',
    'link',
    'base',
    'applet',
    'math',
    'template',
    'noscript',
  };

  final ArchiveRepository archiveRepo;
  final NixReplicationCoordinator? replicationCoordinator;

  NixArchiveService(this.archiveRepo, {this.replicationCoordinator});

  /// Sanitizador HTML com tokenizador determinístico e whitelist de tags/atributos:
  /// - Remove comentários, tags não fechadas/malformadas e blocos perigosos (`script`, `iframe`, `svg`, `style`, `object`, `embed`, `form`, etc.).
  /// - Decodifica entidades HTML numéricas/hexadecimais/nomeadas antes de inspecionar atributos e esquemas de URI.
  /// - Preserva apenas tags estruturais da whitelist e o atributo `href` em `<a>` (exclusivamente `https://`, `http://` ou `#`).
  static String sanitizeRichTextHtml(String rawHtml) {
    // 1. Remove caracteres nulos de evasão e comentários HTML (inclusive truncados no fim)
    var input = rawHtml.replaceAll('\x00', '');
    input = input.replaceAll(RegExp(r'<!--[\s\S]*?(?:-->|$)'), '');

    final out = StringBuffer();
    int i = 0;
    final len = input.length;
    String? skippingBlockTag;

    while (i < len) {
      final lt = input.indexOf('<', i);
      if (lt == -1) {
        if (skippingBlockTag == null) {
          out.write(_neutralizeBareDangerousSchemes(input.substring(i)));
        }
        break;
      }

      if (lt > i && skippingBlockTag == null) {
        out.write(_neutralizeBareDangerousSchemes(input.substring(i, lt)));
      }

      // Localiza o '>' correspondente respeitando aspas de atributos; se não houver '>', trata como tag truncada até EOF
      final gt = _findTagEnd(input, lt + 1);
      final rawTagBody =
          gt == -1 ? input.substring(lt + 1) : input.substring(lt + 1, gt);
      i = gt == -1 ? len : gt + 1;

      final parsed = _parseHtmlTagToken(rawTagBody);
      if (parsed == null) {
        continue;
      }

      final tagName = parsed.tagName;
      final isClosing = parsed.isClosing;

      if (skippingBlockTag != null) {
        if (isClosing && tagName == skippingBlockTag) {
          skippingBlockTag = null;
        }
        continue;
      }

      if (_dropBlockTagsWithContent.contains(tagName)) {
        if (!isClosing && !parsed.isSelfClosing && gt != -1) {
          skippingBlockTag = tagName;
        }
        continue;
      }

      if (!_allowedHtmlTags.contains(tagName)) {
        continue;
      }

      if (isClosing) {
        if (!_voidHtmlTags.contains(tagName)) {
          out.write('</$tagName>');
        }
        continue;
      }

      if (tagName == 'a') {
        final safeHref = _extractSafeHref(parsed.rawAttributes);
        if (safeHref != null) {
          out.write('<a href="$safeHref">');
        } else {
          out.write('<a>');
        }
      } else if (_voidHtmlTags.contains(tagName)) {
        out.write('<$tagName>');
      } else {
        out.write('<$tagName>');
      }
    }

    return out.toString().trim();
  }

  static int _findTagEnd(String s, int start) {
    String? quote;
    for (int idx = start; idx < s.length; idx++) {
      final ch = s[idx];
      if (quote != null) {
        if (ch == quote) quote = null;
      } else {
        if (ch == '"' || ch == "'") {
          quote = ch;
        } else if (ch == '>') {
          return idx;
        }
      }
    }
    return -1;
  }

  static ({
    String tagName,
    bool isClosing,
    bool isSelfClosing,
    String rawAttributes
  })? _parseHtmlTagToken(String rawTagBody) {
    var body = rawTagBody.trim();
    if (body.isEmpty || body.startsWith('!') || body.startsWith('?')) {
      return null;
    }
    bool isClosing = false;
    if (body.startsWith('/')) {
      isClosing = true;
      body = body.substring(1).trimLeft();
    }
    bool isSelfClosing = false;
    if (body.endsWith('/')) {
      isSelfClosing = true;
      body = body.substring(0, body.length - 1).trimRight();
    }
    final match = RegExp(r'^([a-zA-Z][a-zA-Z0-9:-]*)([\s\S]*)$').firstMatch(body);
    if (match == null) return null;
    final tagName = match.group(1)!.toLowerCase();
    final rawAttrs = match.group(2) ?? '';
    return (
      tagName: tagName,
      isClosing: isClosing,
      isSelfClosing: isSelfClosing,
      rawAttributes: rawAttrs,
    );
  }

  static String? _extractSafeHref(String rawAttrs) {
    final attrMatches = RegExp(
      r'''([a-zA-Z0-9_:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))''',
    ).allMatches(rawAttrs);
    for (final m in attrMatches) {
      final name = _decodeHtmlEntities(m.group(1)!).trim().toLowerCase();
      if (name != 'href') continue;
      final rawVal = m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
      return _sanitizeHrefValue(rawVal);
    }
    return null;
  }

  static String _sanitizeHrefValue(String rawVal) {
    final decoded = _decodeHtmlEntities(rawVal);
    // Remove caracteres de controle e espaços invisíveis usados para ofuscar `java\tscript:`
    final compact =
        decoded.replaceAll(RegExp(r'[\x00-\x20\x7f]+'), '').toLowerCase();
    if (compact.startsWith('javascript:') ||
        compact.startsWith('vbscript:') ||
        compact.startsWith('data:') ||
        compact.startsWith('file:')) {
      return 'blocked:';
    }
    final trimmed = decoded.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('https://') ||
        lower.startsWith('http://') ||
        lower.startsWith('#')) {
      return trimmed
          .replaceAll('&', '&amp;')
          .replaceAll('"', '&quot;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
    }
    return 'blocked:';
  }

  static String _neutralizeBareDangerousSchemes(String text) {
    final decoded = _decodeHtmlEntities(text);
    if (RegExp(r'(?:javascript|vbscript|data)\s*:', caseSensitive: false)
        .hasMatch(decoded)) {
      return decoded.replaceAll(
        RegExp(r'(?:javascript|vbscript|data)\s*:', caseSensitive: false),
        'blocked:',
      );
    }
    return text;
  }

  static String _decodeHtmlEntities(String input) {
    var s = input;
    s = s.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);?'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      if (code == null || code <= 0 || code > 0x10FFFF) return '';
      return String.fromCharCode(code);
    });
    s = s.replaceAllMapped(RegExp(r'&#([0-9]+);?'), (m) {
      final code = int.tryParse(m.group(1)!);
      if (code == null || code <= 0 || code > 0x10FFFF) return '';
      return String.fromCharCode(code);
    });
    return s
        .replaceAll(RegExp(r'&colon;?', caseSensitive: false), ':')
        .replaceAll(RegExp(r'&tab;?', caseSensitive: false), '\t')
        .replaceAll(RegExp(r'&newline;?', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'&quot;?', caseSensitive: false), '"')
        .replaceAll(RegExp(r'&apos;?', caseSensitive: false), "'")
        .replaceAll(RegExp(r'&lt;?', caseSensitive: false), '<')
        .replaceAll(RegExp(r'&gt;?', caseSensitive: false), '>')
        .replaceAll(RegExp(r'&amp;?', caseSensitive: false), '&');
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

  static String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _fromHex(String hex) {
    final res = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      res.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return res;
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
    List<ArchiveImage> images = const [],
    String? supersedesHash,
    String visibility = 'public',
    int? createdAtMs,
  }) async {
    final embedded = List<ArchiveImage>.of(images);
    ArchiveImage.validateLimits(embedded);
    if (visibility == 'public' && supersedesHash != null &&
        (await archiveRepo.getObject(supersedesHash))?['visibility'] == 'restricted') {
      visibility = 'restricted';
    }
    final now = createdAtMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    final cleanHtml = sanitizeRichTextHtml(rawHtmlBody);

    final canonicalObj = <String, dynamic>{
      'schema': articleSchemaV1,
      'title': title.trim(),
      'bodyHtml': cleanHtml,
      if (embedded.isNotEmpty) 'images': embedded.map((image) => image.toJson()).toList(),
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

    if (visibility == 'public' && replicationCoordinator != null) {
      try {
        await replicationCoordinator!.replicatePublicObject(
          objectHash: hashHex,
          kind: 'article',
          canonicalBytes: canonicalBytes,
          metadata: {
            'signature': _toHex(sig),
            'author': author.ed25519PublicHex,
            'kind': 'article',
            'created_at': now.toString(),
            'visibility': visibility,
            if (supersedesHash != null) 'supersedes': supersedesHash,
            if (claims.isNotEmpty)
              'claims_json': jsonEncode(
                claims.map((c) => {'claimId': c.claimId, 'text': c.text.trim()}).toList(),
              ),
          },
        );
      } catch (_) {}
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
    if (visibility == 'public' &&
        (await archiveRepo.getObject(targetHash))?['visibility'] == 'restricted') {
      visibility = 'restricted';
    }
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

    if (visibility == 'public' && replicationCoordinator != null) {
      try {
        await replicationCoordinator!.replicatePublicObject(
          objectHash: hashHex,
          kind: 'public_refutation',
          canonicalBytes: canonicalBytes,
          metadata: {
            'signature': _toHex(sig),
            'author': author.ed25519PublicHex,
            'kind': 'public_refutation',
            'created_at': now.toString(),
            'target_object_hash': targetHash,
            'target_claim_id': targetClaimId,
            'visibility': visibility,
          },
        );
      } catch (_) {}
    }

    return hashHex;
  }

  /// Recalcula SHA-256 dos bytes canônicos e verifica a assinatura Ed25519 do objeto salvo.
  Future<bool> verifyStoredObject(String objectHash) async {
    final row = await archiveRepo.getObject(objectHash);
    if (row == null) return false;
    return _verifyObjectRow(objectHash, row);
  }

  Future<List<ArchiveImage>> readVerifiedArticleImages(String objectHash) async {
    final row = await archiveRepo.getObject(objectHash);
    if (row == null || row['kind'] != 'article' ||
        !await _verifyObjectRow(objectHash, row)) return const [];
    final bytes = row['canonical_bytes'] as List<int>;
    final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (payload['schema'] != articleSchemaV1) return const [];
    return ArchiveImage.readList(payload['images']);
  }

  Future<bool> _verifyObjectRow(String objectHash, Map<String, dynamic> row) async {
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

  /// Retorna a cadeia histórica de revisões (`supersedes`) a partir de um hash mais recente.
  Future<List<Map<String, dynamic>>> getRevisionHistory(String latestHash) async {
    final chain = <Map<String, dynamic>>[];
    String? current = latestHash;
    final visited = <String>{};
    while (current != null && current.isNotEmpty && !visited.contains(current)) {
      visited.add(current);
      final row = await archiveRepo.getObject(current);
      if (row == null) break;
      chain.add(row);
      current = row['supersedes_hash'] as String?;
    }
    return chain;
  }

  /// Retorna as alegações (claims) vinculadas a um artigo auditável.
  Future<List<Map<String, dynamic>>> getClaimsForObject(String objectHash) =>
      archiveRepo.getClaimsForObject(objectHash);

  /// Retorna as refutações registradas contra um artigo ou claim alvo.
  Future<List<Map<String, dynamic>>> listRefutationsForTarget(String targetHash) =>
      archiveRepo.listRefutationsForTarget(targetHash);

  // ===========================================================================
  // SUBSISTEMA DE DISCUSSÕES, RASCUNHOS E MODERAÇÃO LOCAL (Fase 19)
  // ===========================================================================

  static const String commentSchemaV1 = 'nix.archive.comment.v1';

  /// Publica comentário assinado `nix.archive.comment.v1` vinculado ao objeto do artigo
  /// ou encadeado a outro comentário pai (`parentCommentHash`).
  Future<String> publishComment({
    required NixIdentity author,
    required String authorPersonaId,
    required String targetObjectHash,
    String? parentCommentHash,
    required String contentMarkdown,
    String? quoteText,
    int? createdAtMs,
  }) async {
    final now = createdAtMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    final cleanContent = contentMarkdown.trim();

    final canonicalObj = <String, dynamic>{
      'schema': commentSchemaV1,
      'targetObjectHash': targetObjectHash,
      if (parentCommentHash != null) 'parentCommentHash': parentCommentHash,
      'authorPersonaId': authorPersonaId,
      'authorEd25519': author.ed25519PublicHex,
      'contentMarkdown': cleanContent,
      if (quoteText != null && quoteText.isNotEmpty) 'quoteText': quoteText.trim(),
      'createdAt': now,
    };

    final canonicalBytes = canonicalizeJsonBytes(canonicalObj);
    final hashHex = computeContentHashHex(canonicalBytes);
    final sig = await author.sign(canonicalBytes);

    await archiveRepo.insertComment(
      hash: hashHex,
      targetObjectHash: targetObjectHash,
      parentCommentHash: parentCommentHash,
      authorPublic: Uint8List.fromList(author.ed25519PublicKey.bytes),
      authorPersonaId: authorPersonaId,
      signature: Uint8List.fromList(sig),
      contentMarkdown: cleanContent,
      quoteText: quoteText,
      createdAt: now,
    );

    if (replicationCoordinator != null) {
      try {
        await replicationCoordinator!.replicatePublicObject(
          objectHash: hashHex,
          kind: 'comment',
          canonicalBytes: canonicalBytes,
          metadata: {
            'signature': _toHex(sig),
            'author': author.ed25519PublicHex,
            'kind': 'comment',
            'created_at': now.toString(),
            'target_object_hash': targetObjectHash,
            if (parentCommentHash != null) 'parent_comment_hash': parentCommentHash,
            'author_persona_id': authorPersonaId,
            if (quoteText != null && quoteText.isNotEmpty) 'quote_text': quoteText,
          },
        );
      } catch (_) {}
    }

    return hashHex;
  }

  /// Verifica a integridade e autenticidade Ed25519 de um comentário salvo.
  Future<bool> verifyStoredComment(String commentHash) async {
    final row = await archiveRepo.getComment(commentHash);
    if (row == null) return false;

    final targetObjectHash = row['target_object_hash'] as String;
    final parentCommentHash = row['parent_comment_hash'] as String?;
    final authorPersonaId = row['author_persona_id'] as String;
    final authorPub = row['author_public'] as List<int>;
    final sig = row['signature'] as List<int>;
    final content = row['content_markdown'] as String;
    final quoteText = row['quote_text'] as String?;
    final createdAt = row['created_at'] as int;

    final canonicalObj = <String, dynamic>{
      'schema': commentSchemaV1,
      'targetObjectHash': targetObjectHash,
      if (parentCommentHash != null) 'parentCommentHash': parentCommentHash,
      'authorPersonaId': authorPersonaId,
      'authorEd25519': _toHex(authorPub),
      'contentMarkdown': content,
      if (quoteText != null && quoteText.isNotEmpty) 'quoteText': quoteText,
      'createdAt': createdAt,
    };

    final canonicalBytes = canonicalizeJsonBytes(canonicalObj);
    final actualHash = computeContentHashHex(canonicalBytes);
    if (actualHash != commentHash) return false;

    return NixIdentity.verify(
      message: canonicalBytes,
      signatureBytes: sig,
      ed25519PublicKey: SimplePublicKey(authorPub, type: KeyPairType.ed25519),
    );
  }

  /// Retorna lista de comentários organizados e encadeados por profundidade de resposta.
  Future<List<Map<String, dynamic>>> getThreadedComments(
    String objectHash, {
    bool filterModerated = true,
  }) async {
    final rawComments = await archiveRepo.listCommentsForObject(objectHash);
    if (rawComments.isEmpty) return const [];

    final moderatedAuthors = <String>{};
    if (filterModerated) {
      final modRows = await archiveRepo.listModeratedAuthors();
      for (final m in modRows) {
        final pubBytes = m['author_public'] as List<int>;
        moderatedAuthors.add(_toHex(pubBytes));
      }
    }

    final commentMap = <String, Map<String, dynamic>>{};
    final childrenMap = <String, List<String>>{};
    final rootHashes = <String>[];

    for (final row in rawComments) {
      final hash = row['hash'] as String;
      final authorHex = _toHex(row['author_public'] as List<int>);
      if (filterModerated && moderatedAuthors.contains(authorHex)) {
        continue;
      }

      final parent = row['parent_comment_hash'] as String?;
      commentMap[hash] = Map<String, dynamic>.from(row);

      if (parent == null || parent.isEmpty) {
        rootHashes.add(hash);
      } else {
        childrenMap.putIfAbsent(parent, () => []).add(hash);
      }
    }

    final result = <Map<String, dynamic>>[];
    void traverse(String commentHash, int depth) {
      final node = commentMap[commentHash];
      if (node != null) {
        node['thread_depth'] = depth;
        result.add(node);
        final children = childrenMap[commentHash] ?? [];
        for (final child in children) {
          traverse(child, depth + 1);
        }
      }
    }

    for (final root in rootHashes) {
      traverse(root, 0);
    }

    return result;
  }

  // --- RASCUNHOS DE ARTIGOS ---

  Future<void> saveDraft({
    required String id,
    required String title,
    required String category,
    required String markdownContent,
    List<String> tags = const [],
    List<ArchiveImage>? images,
  }) {
    if (images != null) ArchiveImage.validateLimits(images);
    return archiveRepo.saveDraft(
      id: id,
      title: title,
      category: category,
      markdownContent: markdownContent,
      tags: tags,
      images: images?.map((image) => image.toJson()).toList(),
    );
  }

  Future<List<ArchiveImage>> readDraftImages(String id) async =>
      ArchiveImage.readList(await archiveRepo.getDraftImages(id));

  Future<Map<String, dynamic>?> getDraft(String id) =>
      archiveRepo.getDraft(id);

  Future<List<Map<String, dynamic>>> listDrafts() =>
      archiveRepo.listDrafts();

  Future<void> deleteDraft(String id) =>
      archiveRepo.deleteDraft(id);

  // --- MODERAÇÃO LOCAL ---

  Future<void> muteAuthor(Uint8List authorPublic, {String? reason}) =>
      archiveRepo.setAuthorModeration(
        authorPublic: authorPublic,
        status: 'muted',
        reason: reason,
      );

  Future<void> blockAuthor(Uint8List authorPublic, {String? reason}) =>
      archiveRepo.setAuthorModeration(
        authorPublic: authorPublic,
        status: 'blocked',
        reason: reason,
      );

  Future<void> unmoderateAuthor(Uint8List authorPublic) =>
      archiveRepo.removeAuthorModeration(authorPublic);

  Future<bool> isAuthorModerated(Uint8List authorPublic) async {
    final status = await archiveRepo.getAuthorModeration(authorPublic);
    return status != null;
  }

  // ===========================================================================
  // SUBSISTEMA DE SINCRONIZAÇÃO DISTRIBUÍDA (Etapa 6)
  // ===========================================================================

  /// Sincroniza um objeto distribuído a partir do [replicationCoordinator],
  /// valida SHA-256 (CID) e assinatura Ed25519 do autor, descartando dados adulterados.
  Future<bool> syncObjectFromNetwork(String objectHash) async {
    if (replicationCoordinator == null) return false;

    // 1. Deduplicação: verifica se já existe na base local
    final existingObj = await archiveRepo.getObject(objectHash);
    final existingComm = await archiveRepo.getComment(objectHash);
    if (existingObj != null || existingComm != null) {
      return true; // Já sincronizado
    }

    // 2. Busca na malha S3 / IPFS
    final res = await replicationCoordinator!.fetchVerifiedObjectWithMetadata(objectHash);
    if (res == null) return false;

    final canonicalBytes = res.bytes;
    final metadata = res.metadata;

    // 3. Validação estrita de integridade SHA-256 do payload canônico
    final computedHash = computeContentHashHex(canonicalBytes);
    if (computedHash.toLowerCase() != objectHash.toLowerCase()) {
      throw ArchiveTamperDetectedException(
        '[Segurança] Hash SHA-256 adulterado em trânsito ($computedHash != $objectHash).',
      );
    }

    // 4. Decodificação canônica do payload JSON
    Map<String, dynamic> canonicalObj;
    try {
      canonicalObj = jsonDecode(utf8.decode(canonicalBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const ArchiveTamperDetectedException(
        '[Segurança] Payload não é JSON válido ou está corrompido.',
      );
    }

    final authorEd25519Hex = (canonicalObj['authorEd25519'] as String?) ?? metadata['author'];
    if (authorEd25519Hex == null || authorEd25519Hex.isEmpty) {
      throw const ArchiveTamperDetectedException(
        '[Segurança] Identidade pública do autor ausente.',
      );
    }

    final sigHex = metadata['signature'];
    if (sigHex == null || sigHex.isEmpty) {
      throw const ArchiveTamperDetectedException(
        '[Segurança] Assinatura digital ausente nos metadados de distribuição.',
      );
    }

    final authorBytes = _fromHex(authorEd25519Hex);
    final sigBytes = _fromHex(sigHex);

    // 5. Validação estrita de assinatura Ed25519
    final isSigValid = await NixIdentity.verify(
      message: canonicalBytes,
      signatureBytes: sigBytes,
      ed25519PublicKey: SimplePublicKey(authorBytes, type: KeyPairType.ed25519),
    );

    if (!isSigValid) {
      throw ArchiveTamperDetectedException(
        '[Segurança] Assinatura Ed25519 do autor inválida para o objeto $objectHash.',
      );
    }

    // 6. Ingestão segura no Archive local com estado verificado
    final schema = canonicalObj['schema'] as String? ?? '';
    if (canonicalObj.containsKey('images')) {
      if (schema != articleSchemaV1) {
        throw const FormatException('Imagens só são admitidas em artigos.');
      }
      ArchiveImage.readList(canonicalObj['images']);
    }
    final createdAt = (canonicalObj['createdAt'] as int?) ??
        int.tryParse(metadata['created_at'] ?? '') ??
        DateTime.now().toUtc().millisecondsSinceEpoch;

    if (schema == commentSchemaV1 || metadata['kind'] == 'comment') {
      final targetObjHash = (canonicalObj['targetObjectHash'] as String?) ??
          metadata['target_object_hash'] ??
          '';
      final parentCommHash = (canonicalObj['parentCommentHash'] as String?) ??
          metadata['parent_comment_hash'];
      final authorPersona = (canonicalObj['authorPersonaId'] as String?) ??
          metadata['author_persona_id'] ??
          'anonymous';
      final quote = (canonicalObj['quoteText'] as String?) ?? metadata['quote_text'];
      final content = (canonicalObj['contentMarkdown'] as String?) ?? '';

      await archiveRepo.insertComment(
        hash: objectHash,
        targetObjectHash: targetObjHash,
        parentCommentHash: parentCommHash,
        authorPublic: Uint8List.fromList(authorBytes),
        authorPersonaId: authorPersona,
        signature: Uint8List.fromList(sigBytes),
        contentMarkdown: content,
        quoteText: quote,
        createdAt: createdAt,
      );
    } else {
      final kind = (schema == articleSchemaV1)
          ? 'article'
          : (metadata['kind'] ?? 'article');
      final supersedes = (canonicalObj['supersedes'] as String?) ??
          metadata['supersedes'];
      final visibility = (canonicalObj['visibility'] as String?) ??
          metadata['visibility'] ??
          'public';

      await archiveRepo.upsertObject(
        hash: objectHash,
        kind: kind,
        canonicalBytes: Uint8List.fromList(canonicalBytes),
        authorPublic: Uint8List.fromList(authorBytes),
        signature: Uint8List.fromList(sigBytes),
        supersedesHash: supersedes,
        visibility: visibility,
        createdAt: createdAt,
      );

      if (kind == 'article') {
        final rawClaims = canonicalObj['claims'];
        if (rawClaims is List) {
          for (final c in rawClaims) {
            if (c is Map && c['claimId'] != null && c['text'] != null) {
              await archiveRepo.upsertClaim(
                objectHash: objectHash,
                claimId: c['claimId'].toString(),
                text: c['text'].toString(),
              );
            }
          }
        }
      } else if (kind == 'public_refutation' || kind == 'refutation') {
        final targetHash = (canonicalObj['targetHash'] as String?) ??
            (canonicalObj['targetObjectHash'] as String?) ??
            metadata['target_object_hash'];
        final targetClaim = (canonicalObj['targetClaimId'] as String?) ??
            metadata['target_claim_id'];
        if (targetHash != null && targetClaim != null) {
          await archiveRepo.insertRefutation(
            refutationHash: objectHash,
            targetHash: targetHash,
            targetClaimId: targetClaim,
          );
        }
      }
    }

    return true;
  }

  /// Sincronização incremental: processa lista de hashes remotos pulando itens já conhecidos
  /// e respeitando [sinceTimestampMs] opcional.
  Future<int> syncIncrementalFromNetwork({
    required List<String> remoteHashes,
    int? sinceTimestampMs,
  }) async {
    int syncedCount = 0;
    for (final h in remoteHashes) {
      try {
        final existing = await archiveRepo.getObject(h);
        final existingComm = await archiveRepo.getComment(h);
        if (existing != null || existingComm != null) {
          continue; // Pula item já sincronizado
        }

        final ok = await syncObjectFromNetwork(h);
        if (ok) {
          syncedCount++;
        }
      } on ArchiveTamperDetectedException {
        // Conteúdo adulterado é descartado com segurança sem interromper o loop nem corromper a base local
        continue;
      } catch (_) {
        continue;
      }
    }
    return syncedCount;
  }
}

class ArchiveTamperDetectedException implements Exception {
  final String message;
  const ArchiveTamperDetectedException(this.message);

  @override
  String toString() => 'ArchiveTamperDetectedException: $message';
}

/// Pacote canônico de distribuição de objetos do Nix Archive para S3 e IPFS.
class ArchiveTransferBundle {
  static const String bundleSchemaV1 = 'nix.archive.bundle.v1';

  final String kind; // 'article', 'comment', 'refutation'
  final String hash;
  final List<int> canonicalBytes;
  final List<int> authorPublic;
  final List<int> signature;
  final int createdAt;
  final String? supersedesHash;
  final String visibility;
  final List<({String claimId, String text})> claims;
  final String? targetObjectHash;
  final String? parentCommentHash;
  final String? authorPersonaId;
  final String? quoteText;
  final String? targetClaimId;

  const ArchiveTransferBundle({
    required this.kind,
    required this.hash,
    required this.canonicalBytes,
    required this.authorPublic,
    required this.signature,
    required this.createdAt,
    this.supersedesHash,
    this.visibility = 'public',
    this.claims = const [],
    this.targetObjectHash,
    this.parentCommentHash,
    this.authorPersonaId,
    this.quoteText,
    this.targetClaimId,
  });

  Map<String, dynamic> toJson() => {
        'schema': bundleSchemaV1,
        'kind': kind,
        'hash': hash,
        'canonicalBytesB64': base64Encode(canonicalBytes),
        'authorPublicHex': _toHex(authorPublic),
        'signatureHex': _toHex(signature),
        'createdAt': createdAt,
        if (supersedesHash != null) 'supersedesHash': supersedesHash,
        'visibility': visibility,
        if (claims.isNotEmpty)
          'claims': claims.map((c) => {'claimId': c.claimId, 'text': c.text}).toList(),
        if (targetObjectHash != null) 'targetObjectHash': targetObjectHash,
        if (parentCommentHash != null) 'parentCommentHash': parentCommentHash,
        if (authorPersonaId != null) 'authorPersonaId': authorPersonaId,
        if (quoteText != null) 'quoteText': quoteText,
        if (targetClaimId != null) 'targetClaimId': targetClaimId,
      };

  factory ArchiveTransferBundle.fromJson(Map<String, dynamic> json) {
    final claimsList = <({String claimId, String text})>[];
    if (json['claims'] is List) {
      for (final c in (json['claims'] as List)) {
        if (c is Map) {
          claimsList.add((
            claimId: c['claimId'] as String,
            text: c['text'] as String,
          ));
        }
      }
    }

    return ArchiveTransferBundle(
      kind: json['kind'] as String,
      hash: json['hash'] as String,
      canonicalBytes: base64Decode(json['canonicalBytesB64'] as String),
      authorPublic: _fromHex(json['authorPublicHex'] as String),
      signature: _fromHex(json['signatureHex'] as String),
      createdAt: json['createdAt'] as int,
      supersedesHash: json['supersedesHash'] as String?,
      visibility: json['visibility'] as String? ?? 'public',
      claims: claimsList,
      targetObjectHash: json['targetObjectHash'] as String?,
      parentCommentHash: json['parentCommentHash'] as String?,
      authorPersonaId: json['authorPersonaId'] as String?,
      quoteText: json['quoteText'] as String?,
      targetClaimId: json['targetClaimId'] as String?,
    );
  }

  List<int> toBytes() => utf8.encode(jsonEncode(toJson()));

  factory ArchiveTransferBundle.fromBytes(List<int> bytes) {
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return ArchiveTransferBundle.fromJson(json);
  }

  static String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _fromHex(String hex) {
    final res = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      res.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return res;
  }
}
