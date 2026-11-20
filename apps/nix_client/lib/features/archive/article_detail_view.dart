import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/archive/archive_verification_status.dart';
import '../../core/archive/nix_archive_service.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import 'archive_moderation_dialog.dart';
import 'archive_document.dart';

/// Visualizador Completo e Interativo de Artigo do Nix Archive (Fase 19 / Etapa 2).
class ArticleDetailView extends StatefulWidget {
  final Map<String, dynamic> articleObject;
  final VoidCallback? onArticleUpdated;

  const ArticleDetailView({
    super.key,
    required this.articleObject,
    this.onArticleUpdated,
  });

  @override
  State<ArticleDetailView> createState() => _ArticleDetailViewState();
}

class _ArticleDetailViewState extends State<ArticleDetailView> {
  ArchiveCryptoVerificationStatus _cryptoStatus =
      ArchiveCryptoVerificationStatus.notVerified;
  List<Map<String, dynamic>> _claims = [];
  List<Map<String, dynamic>> _refutations = [];
  List<Map<String, dynamic>> _revisionHistory = [];
  List<Map<String, dynamic>> _comments = [];
  final Map<String, ArchiveCryptoVerificationStatus> _commentCryptoCache = {};

  bool _isLoading = true;
  String? _replyingToCommentHash;
  String? _quotingText;

  final TextEditingController _commentCtrl = TextEditingController();
  final TextEditingController _refutationRationaleCtrl = TextEditingController();

  String get _objectHash => widget.articleObject['hash'] as String;

  NixState get _nixState => context.read<NixState>();
  NixArchiveService get _archiveService => _nixState.archiveService!;

  @override
  void initState() {
    super.initState();
    _loadArticleDetails();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _refutationRationaleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadArticleDetails() async {
    setState(() => _isLoading = true);

    try {
      // 1. Verificação Criptográfica do Artigo
      final isValid = await _archiveService.verifyStoredObject(_objectHash);
      _cryptoStatus = isValid
          ? ArchiveCryptoVerificationStatus.verified
          : ArchiveCryptoVerificationStatus.invalidSignature;
    } catch (_) {
      _cryptoStatus = ArchiveCryptoVerificationStatus.verificationError;
    }

    try {
      // 2. Alegações e Refutações
      _claims = await _archiveService.getClaimsForObject(_objectHash);
      _refutations = await _archiveService.listRefutationsForTarget(_objectHash);

      // 3. Histórico de Revisões
      _revisionHistory = await _archiveService.getRevisionHistory(_objectHash);

      // 4. Comentários Encadeados
      _comments = await _archiveService.getThreadedComments(_objectHash);

      // Verifica assinaturas dos comentários
      for (final c in _comments) {
        final cHash = c['hash'] as String;
        _commentCryptoCache[cHash] = ArchiveCryptoVerificationStatus.notVerified;
        _verifyComment(cHash);
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyComment(String commentHash) async {
    try {
      final ok = await _archiveService.verifyStoredComment(commentHash);
      if (mounted) {
        setState(() {
          _commentCryptoCache[commentHash] = ok
              ? ArchiveCryptoVerificationStatus.verified
              : ArchiveCryptoVerificationStatus.invalidSignature;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _commentCryptoCache[commentHash] =
              ArchiveCryptoVerificationStatus.verificationError;
        });
      }
    }
  }

  Future<void> _publishComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    final identity = _nixState.primaryIdentity;
    if (identity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identidade soberana não inicializada.')),
      );
      return;
    }

    try {
      final personaId = 'persona_${identity.ed25519PublicHex.substring(0, 8)}';
      await _archiveService.publishComment(
        author: identity,
        authorPersonaId: personaId,
        targetObjectHash: _objectHash,
        parentCommentHash: _replyingToCommentHash,
        quoteText: _quotingText,
        contentMarkdown: text,
      );

      _commentCtrl.clear();
      setState(() {
        _replyingToCommentHash = null;
        _quotingText = null;
      });

      // Recarrega comentários
      _comments = await _archiveService.getThreadedComments(_objectHash);
      for (final c in _comments) {
        final cHash = c['hash'] as String;
        _commentCryptoCache[cHash] = ArchiveCryptoVerificationStatus.notVerified;
        _verifyComment(cHash);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao publicar comentário: $e')),
        );
      }
    }
  }

  Future<void> _openRefutationDialog(String claimId, String claimText) async {
    _refutationRationaleCtrl.clear();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NixColors.surfaceElevatedHigh,
        title: Text(
          'Refutar Alegação Auditável',
          style: TextStyle(color: NixColors.textPrimary, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alegação Alvo [$claimId]:',
                style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  claimText,
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Justificativa / Evidência da Refutação:',
                style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _refutationRationaleCtrl,
                maxLines: 4,
                style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Apresente fatos, referências e provas contrárias...',
                  hintStyle: TextStyle(color: NixColors.textSecondary),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: TextStyle(color: NixColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final rationale = _refutationRationaleCtrl.text.trim();
              if (rationale.isEmpty) return;
              Navigator.pop(ctx);

              final identity = _nixState.primaryIdentity;
              if (identity == null) return;

              await _archiveService.publishRefutation(
                author: identity,
                targetHash: _objectHash,
                targetClaimId: claimId,
                rationaleHtml: '<p>$rationale</p>',
              );

              // Recarrega refutações
              _refutations = await _archiveService.listRefutationsForTarget(_objectHash);
              if (mounted) setState(() {});
            },
            child: const Text('Assinar e Publicar Refutação', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshComments() async {
    final comments = await _archiveService.getThreadedComments(_objectHash);
    if (!mounted) return;
    setState(() => _comments = comments);
    for (final comment in comments) {
      if (!_commentCryptoCache.containsKey(comment['hash'])) {
        unawaited(_verifyComment(comment['hash'] as String));
      }
    }
  }

  Future<void> _moderateAuthor(List<int> authorPublicBytes, String action) async {
    final pubBytes = Uint8List.fromList(authorPublicBytes);
    try {
      if (action == 'mute') {
        await _archiveService.muteAuthor(pubBytes, reason: 'Silenciado pelo usuário');
      } else {
        await _archiveService.blockAuthor(pubBytes, reason: 'Bloqueado pelo usuário');
      }
      if (mounted) await _refreshComments();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao atualizar a moderação local.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final obj = widget.articleObject;
    final authorBytes = obj['author_public'] as List<int>;
    final authorHex = authorBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    Map<String, dynamic> parsedPayload = {};
    try {
      final rawBytes = obj['canonical_bytes'] as List<int>;
      parsedPayload = jsonDecode(utf8.decode(rawBytes)) as Map<String, dynamic>;
    } catch (_) {}

    final title = (parsedPayload['title'] as String?) ?? 'Artigo Sem Título';
    final bodyHtml = (parsedPayload['bodyHtml'] as String?) ?? '';
    final createdAt = obj['created_at'] as int? ?? 0;
    final dateStr = DateTime.fromMillisecondsSinceEpoch(createdAt).toLocal().toString().split('.')[0];

    return Scaffold(
      backgroundColor: NixColors.background,
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: NixColors.surfaceElevatedHigh,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: ArchiveCryptoBadge(status: _cryptoStatus),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabeçalho de Metadados Criptográficos
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: NixColors.surfaceCard,
                      borderRadius: NixTokens.borderMd,
                      border: Border.all(color: NixColors.surfaceBorder.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Autor:',
                              style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${authorHex.substring(0, 16)}... (Ed25519)',
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            Text(
                              dateStr,
                              style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              'CID Hash:',
                              style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _objectHash,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: NixColors.textPrimary,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 14),
                              tooltip: 'Copiar Hash CID',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _objectHash));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('CID copiado para a área de transferência')),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Título e Corpo do Artigo
                  Text(
                    title,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (bodyHtml.isEmpty)
                    const Text('Sem conteúdo textual registrado.')
                  else
                    ArchiveDocument(source: bodyHtml),

                  const Divider(height: 32),

                  // Seção: Alegações Auditáveis e Refutações
                  Row(
                    children: [
                      const Icon(Icons.gavel_rounded, size: 18, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Alegações Auditáveis e Refutações (${_claims.length})',
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_claims.isEmpty)
                    Text(
                      'Nenhuma alegação específica vinculada a esta publicação.',
                      style: TextStyle(color: NixColors.textSecondary, fontSize: 12.5),
                    )
                  else
                    ..._claims.map((claim) {
                      final claimId = claim['claim_id'] as String;
                      final claimText = claim['text'] as String;
                      final refutationsForClaim = _refutations
                          .where((r) => r['target_claim_id'] == claimId)
                          .toList();

                      return Card(
                        color: NixColors.surfaceCard,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: BorderSide(
                            color: refutationsForClaim.isNotEmpty
                                ? Colors.redAccent.withValues(alpha: 0.4)
                                : NixColors.surfaceBorder.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Claim: $claimId',
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    icon: const Icon(Icons.shield_outlined, size: 14, color: Colors.redAccent),
                                    label: const Text('Refutar', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                                    onPressed: () => _openRefutationDialog(claimId, claimText),
                                  ),
                                ],
                              ),
                              Text(
                                claimText,
                                style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                              ),
                              if (refutationsForClaim.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Refutações registradas (${refutationsForClaim.length}):',
                                  style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                ...refutationsForClaim.map((rf) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4, left: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.arrow_right, size: 14, color: Colors.redAccent),
                                        Expanded(
                                          child: Text(
                                            'Refutação assinada: ${(rf['refutation_hash'] as String).substring(0, 12)}...',
                                            style: const TextStyle(
                                              color: Colors.redAccent,
                                              fontSize: 11,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),

                  const Divider(height: 32),

                  // Seção: Histórico de Revisões
                  if (_revisionHistory.length > 1) ...[
                    Row(
                      children: [
                        const Icon(Icons.history_rounded, size: 18, color: Colors.amber),
                        const SizedBox(width: 8),
                        Text(
                          'Cadeia de Revisões (${_revisionHistory.length})',
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._revisionHistory.map((rev) {
                      final revHash = rev['hash'] as String;
                      final isCurrent = revHash == _objectHash;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              isCurrent ? Icons.radio_button_checked : Icons.radio_button_off,
                              size: 14,
                              color: isCurrent ? Colors.greenAccent : NixColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${revHash.substring(0, 16)}... ${isCurrent ? "(Versão Atual)" : "(Predecessora)"}',
                              style: TextStyle(
                                color: isCurrent ? Colors.greenAccent : NixColors.textSecondary,
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 32),
                  ],

                  // Seção: Discussões & Comentários Encadeados
                  Row(
                    children: [
                      const Icon(Icons.forum_rounded, size: 18, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Discussões Encadeadas (${_comments.length})',
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Gerenciar moderação local',
                        icon: const Icon(Icons.person_off_outlined),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => ArchiveModerationDialog(
                            service: _archiveService,
                            onChanged: () {
                              if (mounted) unawaited(_refreshComments());
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Composer de Comentário
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: NixColors.surfaceCard,
                      borderRadius: NixTokens.borderMd,
                      border: Border.all(color: NixColors.surfaceBorder.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_replyingToCommentHash != null) ...[
                          Row(
                            children: [
                              Text(
                                'Respondendo a: ${_replyingToCommentHash!.substring(0, 8)}...',
                                style: const TextStyle(color: Colors.amber, fontSize: 11),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.close, size: 14),
                                onPressed: () => setState(() {
                                  _replyingToCommentHash = null;
                                  _quotingText = null;
                                }),
                              ),
                            ],
                          ),
                          if (_quotingText != null)
                            Container(
                              padding: const EdgeInsets.all(6),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: NixColors.background,
                                border: const Border(left: BorderSide(color: Colors.amber, width: 3)),
                              ),
                              child: Text(
                                _quotingText!,
                                style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                              ),
                            ),
                        ],
                        TextField(
                          controller: _commentCtrl,
                          maxLines: 3,
                          style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Escreva um comentário assinado com sua identidade soberana...',
                            hintStyle: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.all(10),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: NixColors.accentYellow,
                                foregroundColor: Colors.black,
                              ),
                              icon: const Icon(Icons.send_rounded, size: 14),
                              label: const Text('Comentar com Ed25519', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              onPressed: _publishComment,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Lista Encadeada de Comentários
                  if (_comments.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Nenhum comentário registrado ainda. Participe da discussão!',
                          style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                        ),
                      ),
                    )
                  else
                    ..._comments.map((comment) {
                      final cHash = comment['hash'] as String;
                      final depth = comment['thread_depth'] as int? ?? 0;
                      final authorPersona = comment['author_persona_id'] as String;
                      final content = comment['content_markdown'] as String;
                      final quote = comment['quote_text'] as String?;
                      final authorPub = comment['author_public'] as List<int>;
                      final cStatus = _commentCryptoCache[cHash] ??
                          ArchiveCryptoVerificationStatus.notVerified;

                      return Padding(
                        padding: EdgeInsets.only(left: (depth * 20.0).clamp(0.0, 80.0), bottom: 8),
                        child: Card(
                          color: NixColors.surfaceCard,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: BorderSide(
                              color: depth > 0
                                  ? Colors.amber.withValues(alpha: 0.3)
                                  : NixColors.surfaceBorder.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      authorPersona,
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const Spacer(),
                                    ArchiveCryptoBadge(status: cStatus, fontSize: 9.5, iconSize: 12),
                                    PopupMenuButton<String>(
                                      icon: Icon(Icons.more_vert, size: 16, color: NixColors.textSecondary),
                                      onSelected: (val) => _moderateAuthor(authorPub, val),
                                      itemBuilder: (ctx) => [
                                        const PopupMenuItem(
                                          value: 'mute',
                                          child: Text('Silenciar Autor Localmente'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'block',
                                          child: Text('Bloquear Autor Localmente'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (quote != null && quote.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    decoration: BoxDecoration(
                                      color: NixColors.background,
                                      border: const Border(
                                        left: BorderSide(color: Colors.amber, width: 2),
                                      ),
                                    ),
                                    child: Text(
                                      quote,
                                      style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  content,
                                  style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      icon: const Icon(Icons.reply_rounded, size: 13),
                                      label: const Text('Responder', style: TextStyle(fontSize: 11)),
                                      onPressed: () {
                                        setState(() {
                                          _replyingToCommentHash = cHash;
                                          _quotingText = content.length > 60
                                              ? '${content.substring(0, 60)}...'
                                              : content;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
