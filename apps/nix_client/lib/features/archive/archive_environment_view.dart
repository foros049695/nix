import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/archive/archive_verification_status.dart';
import '../../core/archive/nix_archive_service.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../design/nix_surfaces.dart';
import 'article_detail_view.dart';

/// Ambiente Exclusivo Nix Archive — Publicações Canônicas, Rascunhos e Discussões (Fase 19 / Etapa 2).
class NixArchiveEnvironmentView extends StatefulWidget {
  const NixArchiveEnvironmentView({super.key});

  @override
  State<NixArchiveEnvironmentView> createState() =>
      _NixArchiveEnvironmentViewState();
}

class _NixArchiveEnvironmentViewState extends State<NixArchiveEnvironmentView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _recentArticles = [];
  List<Map<String, dynamic>> _userDrafts = [];
  final Map<String, ArchiveCryptoVerificationStatus> _verificationCache = {};
  bool _isLoading = false;

  // Controlador do editor de novo artigo
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _categoryCtrl = TextEditingController(text: 'Tecnologia');
  final TextEditingController _contentCtrl = TextEditingController();
  final TextEditingController _claimsCtrl = TextEditingController();
  String? _activeDraftId;
  bool _isPreviewMode = false;
  bool _isPublishing = false;
  String? _publishFeedback;
  Timer? _autoSaveDebouncer;

  // Estado da aba de discussões
  Map<String, dynamic>? _selectedDiscussionArticle;
  List<Map<String, dynamic>> _discussionComments = [];
  final Map<String, ArchiveCryptoVerificationStatus> _discussionCommentCrypto = {};
  final TextEditingController _discussionCommentCtrl = TextEditingController();
  String? _discussionReplyToHash;
  String? _discussionQuoteText;
  bool _isLoadingDiscussionComments = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 0) _loadArticles();
      if (_tabController.index == 1) _loadDrafts();
      if (_tabController.index == 3 && _selectedDiscussionArticle != null) {
        _loadDiscussionComments(_selectedDiscussionArticle!['hash'] as String);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadArticles();
      _loadDrafts();
    });
  }

  @override
  void dispose() {
    _autoSaveDebouncer?.cancel();
    _tabController.dispose();
    _titleCtrl.dispose();
    _categoryCtrl.dispose();
    _contentCtrl.dispose();
    _claimsCtrl.dispose();
    _discussionCommentCtrl.dispose();
    super.dispose();
  }

  NixState get _nixState => context.read<NixState>();
  NixArchiveService get _archiveService => _nixState.archiveService!;

  Future<void> _verifyObject(String objectHash) async {
    if (_verificationCache[objectHash] == ArchiveCryptoVerificationStatus.verified ||
        _verificationCache[objectHash] == ArchiveCryptoVerificationStatus.invalidSignature) {
      return;
    }
    try {
      final isValid = await _archiveService.verifyStoredObject(objectHash);
      if (mounted) {
        setState(() {
          _verificationCache[objectHash] = isValid
              ? ArchiveCryptoVerificationStatus.verified
              : ArchiveCryptoVerificationStatus.invalidSignature;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _verificationCache[objectHash] =
              ArchiveCryptoVerificationStatus.verificationError;
        });
      }
    }
  }

  Future<void> _loadArticles() async {
    setState(() => _isLoading = true);
    try {
      final objects = await _nixState.archiveRepository.listObjects(kind: 'article', publicOnly: true, limit: 50);
      if (mounted) {
        setState(() {
          _recentArticles = objects;
          _isLoading = false;
        });
        for (final obj in objects) {
          final h = obj['hash'] as String?;
          if (h != null) {
            _verificationCache[h] ??= ArchiveCryptoVerificationStatus.notVerified;
            _verifyObject(h);
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDrafts() async {
    try {
      final drafts = await _archiveService.listDrafts();
      if (mounted) {
        setState(() => _userDrafts = drafts);
      }
    } catch (_) {}
  }

  void _scheduleAutoSave() {
    _autoSaveDebouncer?.cancel();
    _autoSaveDebouncer = Timer(const Duration(milliseconds: 600), () {
      _saveDraftAuto();
    });
  }

  Future<void> _saveDraftAuto() async {
    if (_titleCtrl.text.trim().isEmpty && _contentCtrl.text.trim().isEmpty) {
      return;
    }
    final draftId = _activeDraftId ?? 'draft_${DateTime.now().millisecondsSinceEpoch}';
    _activeDraftId = draftId;

    await _archiveService.saveDraft(
      id: draftId,
      title: _titleCtrl.text.trim().isNotEmpty ? _titleCtrl.text.trim() : 'Sem título',
      category: _categoryCtrl.text.trim(),
      markdownContent: _contentCtrl.text,
    );
    await _loadDrafts();
  }

  Future<void> _publishArticle() async {
    final title = _titleCtrl.text.trim();
    final body = _contentCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Título e conteúdo são obrigatórios.')),
      );
      return;
    }

    final identity = _nixState.primaryIdentity;
    if (identity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identidade soberana não inicializada.')),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      final claimsLines = _claimsCtrl.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      final claims = claimsLines.asMap().entries.map((entry) {
        return (claimId: 'claim_${entry.key + 1}', text: entry.value);
      }).toList();

      final hash = await _archiveService.publishArticle(
        author: identity,
        title: title,
        rawHtmlBody: '<p>${body.replaceAll('\n', '<br>')}</p>',
        claims: claims,
      );

      if (_activeDraftId != null) {
        await _archiveService.deleteDraft(_activeDraftId!);
        _activeDraftId = null;
      }

      _titleCtrl.clear();
      _contentCtrl.clear();
      _claimsCtrl.clear();

      await _loadArticles();
      await _loadDrafts();

      if (mounted) {
        setState(() {
          _isPublishing = false;
          _publishFeedback = 'Publicado com sucesso! Hash CID: ${hash.substring(0, 16)}...';
        });
        _tabController.animateTo(0);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Artigo publicado e assinado com Ed25519: ${hash.substring(0, 12)}...'),
            backgroundColor: NixColors.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao publicar: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _loadDraftIntoEditor(Map<String, dynamic> draft) {
    setState(() {
      _activeDraftId = draft['id'] as String;
      _titleCtrl.text = draft['title'] as String? ?? '';
      _categoryCtrl.text = draft['category'] as String? ?? 'Tecnologia';
      _contentCtrl.text = draft['markdown_content'] as String? ?? '';
      _tabController.animateTo(2);
    });
  }

  void _openArticleDetail(Map<String, dynamic> article) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArticleDetailView(
          articleObject: article,
          onArticleUpdated: _loadArticles,
        ),
      ),
    );
  }

  Future<void> _loadDiscussionComments(String articleHash) async {
    setState(() => _isLoadingDiscussionComments = true);
    try {
      final comments = await _archiveService.getThreadedComments(articleHash);
      if (mounted && _selectedDiscussionArticle?['hash'] == articleHash) {
        setState(() {
          _discussionComments = comments;
          _isLoadingDiscussionComments = false;
        });
        for (final c in comments) {
          final cHash = c['hash'] as String;
          _discussionCommentCrypto[cHash] = ArchiveCryptoVerificationStatus.notVerified;
          _verifyDiscussionComment(cHash);
        }
      }
    } catch (_) {
      if (mounted && _selectedDiscussionArticle?['hash'] == articleHash) setState(() => _isLoadingDiscussionComments = false);
    }
  }

  Future<void> _verifyDiscussionComment(String commentHash) async {
    try {
      final ok = await _archiveService.verifyStoredComment(commentHash);
      if (mounted) {
        setState(() {
          _discussionCommentCrypto[commentHash] = ok
              ? ArchiveCryptoVerificationStatus.verified
              : ArchiveCryptoVerificationStatus.invalidSignature;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _discussionCommentCrypto[commentHash] =
              ArchiveCryptoVerificationStatus.verificationError;
        });
      }
    }
  }

  Future<void> _publishDiscussionComment() async {
    if (_selectedDiscussionArticle == null) return;
    final text = _discussionCommentCtrl.text.trim();
    if (text.isEmpty) return;

    final identity = _nixState.primaryIdentity;
    if (identity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identidade soberana não inicializada.')),
      );
      return;
    }

    try {
      final articleHash = _selectedDiscussionArticle!['hash'] as String;
      final personaId = 'persona_${identity.ed25519PublicHex.substring(0, 8)}';
      await _archiveService.publishComment(
        author: identity,
        authorPersonaId: personaId,
        targetObjectHash: articleHash,
        parentCommentHash: _discussionReplyToHash,
        quoteText: _discussionQuoteText,
        contentMarkdown: text,
      );

      _discussionCommentCtrl.clear();
      setState(() {
        _discussionReplyToHash = null;
        _discussionQuoteText = null;
      });

      await _loadDiscussionComments(articleHash);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao comentar: $e')),
        );
      }
    }
  }

  Widget _buildMarkdownPreview(String text) {
    if (text.trim().isEmpty) {
      return Text(
        'Nenhum conteúdo para pré-visualização.',
        style: TextStyle(color: NixColors.textSecondary, fontStyle: FontStyle.italic),
      );
    }

    final lines = text.split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            trimmed.substring(2),
            style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ));
      } else if (trimmed.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 3),
          child: Text(
            trimmed.substring(3),
            style: TextStyle(color: NixColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ));
      } else if (trimmed.startsWith('### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(
            trimmed.substring(4),
            style: TextStyle(color: NixColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ));
      } else if (trimmed.startsWith('> ')) {
        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: NixColors.background,
            border: const Border(left: BorderSide(color: Colors.amber, width: 3)),
          ),
          child: Text(
            trimmed.substring(2),
            style: TextStyle(color: NixColors.textSecondary, fontStyle: FontStyle.italic, fontSize: 12.5),
          ),
        ));
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(color: Colors.amber, fontSize: 14)),
              Expanded(
                child: Text(
                  trimmed.substring(2),
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                ),
              ),
            ],
          ),
        ));
      } else if (trimmed.isNotEmpty) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            trimmed,
            style: TextStyle(color: NixColors.textPrimary, fontSize: 13, height: 1.4),
          ),
        ));
      } else {
        widgets.add(const SizedBox(height: 6));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NixColors.background,
      appBar: AppBar(
        backgroundColor: NixColors.surfaceCard,
        elevation: 0,
        title: const NixPanelTitle(
          icon: Icons.auto_stories_rounded,
          title: 'Nix Archive',
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: context.accentTextColor,
          labelColor: context.accentTextColor,
          unselectedLabelColor: NixColors.textSecondary,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(
              icon: const Icon(Icons.travel_explore_rounded, size: 18),
              text: 'Explorar (${_recentArticles.length})',
            ),
            Tab(
              icon: const Icon(Icons.drafts_outlined, size: 18),
              text: 'Rascunhos (${_userDrafts.length})',
            ),
            const Tab(
              icon: Icon(Icons.edit_document, size: 18),
              text: 'Novo Artigo',
            ),
            const Tab(
              icon: Icon(Icons.forum_outlined, size: 18),
              text: 'Discussões',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildExploreTab(),
          _buildDraftsTab(),
          _buildEditorTab(),
          _buildDiscussionsTab(),
        ],
      ),
    );
  }

  Widget _buildExploreTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.amber));
    }
    if (_recentArticles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.article_outlined, size: 48, color: NixColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                'Nenhum artigo publicado no arquivo local',
                style: TextStyle(
                  color: NixColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Seja o primeiro a publicar uma obra imutável, assinada criptograficamente pela sua identidade soberana.',
                textAlign: TextAlign.center,
                style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _recentArticles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final obj = _recentArticles[index];
        final hash = obj['hash'] as String;
        final authorHex = (obj['author_public'] as List<int>)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();

        Map<String, dynamic> parsedPayload = {};
        try {
          final rawBytes = obj['canonical_bytes'] as List<int>;
          parsedPayload = jsonDecode(utf8.decode(rawBytes)) as Map<String, dynamic>;
        } catch (_) {}

        final title = (parsedPayload['title'] as String?) ?? 'Artigo sem título';
        final claims = parsedPayload['claims'] as List<dynamic>? ?? [];

        return Card(
          color: NixColors.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: NixTokens.borderMd,
            side: BorderSide(color: NixColors.surfaceBorder.withValues(alpha: 0.5)),
          ),
          child: InkWell(
            borderRadius: NixTokens.borderMd,
            onTap: () => _openArticleDetail(obj),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'CID: ${hash.substring(0, 10)}...',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const Spacer(),
                      ArchiveCryptoBadge(
                        status: _verificationCache[hash] ??
                            ArchiveCryptoVerificationStatus.notVerified,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Autor: ${authorHex.substring(0, 12)}...',
                    style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
                  ),
                  if (claims.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${claims.length} alegações auditáveis registradas',
                      style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Ler Artigo Completo & Discussões',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.amber),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDraftsTab() {
    if (_userDrafts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.drafts_outlined, size: 48, color: NixColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                'Nenhum rascunho salvo',
                style: TextStyle(
                  color: NixColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Os artigos em edição na aba Novo Artigo são auto-salvos em cofre SQLCipher local.',
                textAlign: TextAlign.center,
                style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _userDrafts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final draft = _userDrafts[index];
        final id = draft['id'] as String;
        final title = (draft['title'] as String?) ?? 'Sem título';
        final category = (draft['category'] as String?) ?? 'Geral';

        return Card(
          color: NixColors.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: NixTokens.borderMd,
            side: BorderSide(color: NixColors.surfaceBorder.withValues(alpha: 0.5)),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.amber.withValues(alpha: 0.15),
              child: const Icon(Icons.edit_note_rounded, color: Colors.amber, size: 20),
            ),
            title: Text(
              title,
              style: TextStyle(
                color: NixColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              'Categoria: $category',
              style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_rounded, color: Colors.amber),
                  tooltip: 'Continuar Editando',
                  onPressed: () => _loadDraftIntoEditor(draft),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  tooltip: 'Excluir Rascunho',
                  onPressed: () async {
                    await _archiveService.deleteDraft(id);
                    await _loadDrafts();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditorTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _activeDraftId != null ? 'Editando Rascunho' : 'Nova Publicação Soberana',
                  style: TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              OutlinedButton.icon(
                icon: Icon(
                  _isPreviewMode ? Icons.edit_rounded : Icons.visibility_rounded,
                  size: 16,
                  color: Colors.amber,
                ),
                label: Text(
                  _isPreviewMode ? 'Editar' : 'Prévia',
                  style: const TextStyle(color: Colors.amber, fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.amber),
                ),
                onPressed: () => setState(() => _isPreviewMode = !_isPreviewMode),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            style: TextStyle(color: NixColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: 'Título do Artigo',
              hintText: 'Digite o título da publicação...',
              filled: true,
              fillColor: NixColors.surfaceCard,
              border: OutlineInputBorder(borderRadius: NixTokens.borderSm),
            ),
            onChanged: (_) => _scheduleAutoSave(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _categoryCtrl,
            style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Categoria / Tema',
              hintText: 'Ex: Tecnologia, Criptografia, Filosofia, Ciência...',
              filled: true,
              fillColor: NixColors.surfaceCard,
              border: OutlineInputBorder(borderRadius: NixTokens.borderSm),
              isDense: true,
            ),
            onChanged: (_) => _scheduleAutoSave(),
          ),
          const SizedBox(height: 10),
          if (_isPreviewMode) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NixColors.surfaceCard,
                borderRadius: NixTokens.borderSm,
                border: Border.all(color: NixColors.surfaceBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titleCtrl.text.isEmpty ? 'Sem título' : _titleCtrl.text,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(height: 20),
                  _buildMarkdownPreview(_contentCtrl.text),
                ],
              ),
            ),
          ] else ...[
            TextField(
              controller: _contentCtrl,
              maxLines: 8,
              style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Conteúdo em Markdown / Rich Text',
                hintText: 'Escreva seu artigo aqui. Suporta cabeçalhos (#), listas (-) e citações (>).',
                filled: true,
                fillColor: NixColors.surfaceCard,
                border: OutlineInputBorder(borderRadius: NixTokens.borderSm),
              ),
              onChanged: (_) => _scheduleAutoSave(),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _claimsCtrl,
            maxLines: 2,
            style: TextStyle(color: NixColors.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              labelText: 'Alegações Chave (uma por linha, opcional para refutação formal)',
              hintText: 'Ex: A criptografia ponta a ponta protege metadados essenciais.',
              filled: true,
              fillColor: NixColors.surfaceCard,
              border: OutlineInputBorder(borderRadius: NixTokens.borderSm),
              isDense: true,
            ),
            onChanged: (_) => _scheduleAutoSave(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: _isPublishing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.publish_rounded, color: Colors.black),
                  label: Text(
                    _isPublishing ? 'Assinando e Publicando...' : 'Publicar com Assinatura Ed25519',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: NixTokens.borderSm),
                  ),
                  onPressed: _isPublishing ? null : _publishArticle,
                ),
              ),
            ],
          ),
          if (_publishFeedback != null) ...[
            const SizedBox(height: 10),
            Text(
              _publishFeedback!,
              style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiscussionsTab() {
    if (_selectedDiscussionArticle != null) {
      final article = _selectedDiscussionArticle!;
      final rawBytes = article['canonical_bytes'] as List<int>? ?? [];
      String articleTitle = 'Artigo Selecionado';
      try {
        final payload = jsonDecode(utf8.decode(rawBytes)) as Map<String, dynamic>;
        articleTitle = payload['title'] as String? ?? articleTitle;
      } catch (_) {}

      return Column(
        children: [
          // Barra de navegação interna da discussão
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: NixColors.surfaceCard,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  tooltip: 'Voltar à lista de tópicos',
                  onPressed: () => setState(() {
                    _selectedDiscussionArticle = null;
                    _discussionComments = [];
                    _discussionCommentCrypto.clear();
                    _discussionCommentCtrl.clear();
                    _isLoadingDiscussionComments = false;
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    articleTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Lista de Comentários ou Carregando
          Expanded(
            child: _isLoadingDiscussionComments
                ? const Center(child: CircularProgressIndicator(color: Colors.amber))
                : _discussionComments.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum comentário registrado nesta discussão. Seja o primeiro!',
                          style: TextStyle(color: NixColors.textSecondary, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _discussionComments.length,
                        itemBuilder: (context, idx) {
                          final c = _discussionComments[idx];
                          final cHash = c['hash'] as String;
                          final depth = c['thread_depth'] as int? ?? 0;
                          final persona = c['author_persona_id'] as String;
                          final content = c['content_markdown'] as String;
                          final quote = c['quote_text'] as String?;
                          final cStatus = _discussionCommentCrypto[cHash] ??
                              ArchiveCryptoVerificationStatus.notVerified;

                          return Padding(
                            padding: EdgeInsets.only(
                              left: (depth * 20.0).clamp(0.0, 60.0),
                              bottom: 8,
                            ),
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
                                          persona,
                                          style: const TextStyle(
                                            color: Colors.amber,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const Spacer(),
                                        ArchiveCryptoBadge(status: cStatus, fontSize: 9.5, iconSize: 12),
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
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(Icons.reply_rounded, size: 12),
                                          label: const Text('Responder', style: TextStyle(fontSize: 11)),
                                          onPressed: () {
                                            setState(() {
                                              _discussionReplyToHash = cHash;
                                              _discussionQuoteText = content.length > 50
                                                  ? '${content.substring(0, 50)}...'
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
                        },
                      ),
          ),

          // Composer de Comentário da Discussão
          Container(
            padding: const EdgeInsets.all(10),
            color: NixColors.surfaceCard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_discussionReplyToHash != null) ...[
                  Row(
                    children: [
                      Text(
                        'Respondendo a: ${_discussionReplyToHash!.substring(0, 8)}...',
                        style: const TextStyle(color: Colors.amber, fontSize: 11),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        onPressed: () => setState(() {
                          _discussionReplyToHash = null;
                          _discussionQuoteText = null;
                        }),
                      ),
                    ],
                  ),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _discussionCommentCtrl,
                        maxLines: 2,
                        style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Comentar com identidade soberana...',
                          hintStyle: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.all(8),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      style: IconButton.styleFrom(backgroundColor: Colors.amber),
                      icon: const Icon(Icons.send_rounded, color: Colors.black, size: 18),
                      tooltip: 'Publicar Comentário Assinado',
                      onPressed: _publishDiscussionComment,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Se nenhum artigo foi selecionado, lista os tópicos de discussão
    if (_recentArticles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 48, color: NixColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                'Nenhuma discussão ativa',
                style: TextStyle(
                  color: NixColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Publique um artigo na aba "Novo Artigo" para iniciar um tópico de discussão auditável.',
                textAlign: TextAlign.center,
                style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _recentArticles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final article = _recentArticles[index];
        final hash = article['hash'] as String;

        Map<String, dynamic> parsedPayload = {};
        try {
          final rawBytes = article['canonical_bytes'] as List<int>;
          parsedPayload = jsonDecode(utf8.decode(rawBytes)) as Map<String, dynamic>;
        } catch (_) {}

        final title = (parsedPayload['title'] as String?) ?? 'Artigo sem título';
        final cStatus = _verificationCache[hash] ?? ArchiveCryptoVerificationStatus.notVerified;

        return Card(
          color: NixColors.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: NixTokens.borderMd,
            side: BorderSide(color: NixColors.surfaceBorder.withValues(alpha: 0.5)),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.amber.withValues(alpha: 0.15),
              child: const Icon(Icons.forum_rounded, color: Colors.amber, size: 20),
            ),
            title: Text(
              title,
              style: TextStyle(
                color: NixColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              'CID: ${hash.substring(0, 12)}...',
              style: TextStyle(color: NixColors.textSecondary, fontSize: 11, fontFamily: 'monospace'),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ArchiveCryptoBadge(status: cStatus, fontSize: 9.5, iconSize: 12),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onPressed: () {
                    setState(() {
                      _selectedDiscussionArticle = article;
                    });
                    _loadDiscussionComments(hash);
                  },
                  child: const Text('Entrar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
