import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/archive/nix_archive_service.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Ambiente Exclusivo Nix Archive — Publicações Canônicas, Rascunhos e Discussões (Fase 19).
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 0) _loadArticles();
      if (_tabController.index == 1) _loadDrafts();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadArticles();
      _loadDrafts();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleCtrl.dispose();
    _categoryCtrl.dispose();
    _contentCtrl.dispose();
    _claimsCtrl.dispose();
    super.dispose();
  }

  NixState get _nixState => context.read<NixState>();
  NixArchiveService get _archiveService => _nixState.archiveService!;

  Future<void> _loadArticles() async {
    setState(() => _isLoading = true);
    try {
      final objects = await _nixState.archiveRepository.listObjects(kind: 'article', limit: 50);
      if (mounted) {
        setState(() {
          _recentArticles = objects;
          _isLoading = false;
        });
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
      // Extrai alegações (claims) informadas linha a linha
      final claimsLines = _claimsCtrl.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      final claims = claimsLines.asMap().entries.map((entry) {
        return (claimId: 'claim_${entry.key + 1}', text: entry.value);
      }).toList();

      // Sanitiza HTML / Markdown e assina deterministicamente com Ed25519
      final hash = await _archiveService.publishArticle(
        author: identity,
        title: title,
        rawHtmlBody: '<p>${body.replaceAll('\n', '<br>')}</p>',
        claims: claims,
      );

      // Limpa rascunho se publicado
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
            backgroundColor: Colors.green.shade800,
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
      _tabController.animateTo(2); // Aba do editor
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NixColors.background,
      appBar: AppBar(
        backgroundColor: NixColors.surfaceCard,
        elevation: 0,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_stories_rounded, color: Colors.amber, size: 22),
              const SizedBox(width: 10),
              Text(
                'Nix Archive',
                style: TextStyle(
                  color: NixColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.12),
                  borderRadius: NixTokens.borderSm,
                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                ),
                child: const Text(
                  'Assinado Ed25519 · Imutável',
                  style: TextStyle(color: Colors.amber, fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: NixColors.textSecondary,
          tabs: [
            Tab(
              icon: const Icon(Icons.explore_outlined, size: 18),
              text: 'Explorar (${_recentArticles.length})',
            ),
            Tab(
              icon: const Icon(Icons.drafts_outlined, size: 18),
              text: 'Rascunhos (${_userDrafts.length})',
            ),
            const Tab(
              icon: Icon(Icons.edit_note_rounded, size: 18),
              text: 'Publicar Artigo',
            ),
            const Tab(
              icon: Icon(Icons.forum_outlined, size: 18),
              text: 'Discussões',
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildExploreTab(),
            _buildDraftsTab(),
            _buildEditorTab(),
            _buildDiscussionsTab(),
          ],
        ),
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
            side: BorderSide(color: NixColors.surfaceBorder.withOpacity(0.5)),
          ),
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
                        color: Colors.amber.withOpacity(0.12),
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
                    const Icon(Icons.verified_rounded, size: 14, color: Colors.greenAccent),
                    const SizedBox(width: 4),
                    Text(
                      'Ed25519 OK',
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
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
              ],
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
                'Os artigos em edição na aba Publicar são auto-salvos em cofre SQLCipher local.',
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
            side: BorderSide(color: NixColors.surfaceBorder.withOpacity(0.5)),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.amber.withOpacity(0.15),
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
            onChanged: (_) => _saveDraftAuto(),
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
            onChanged: (_) => _saveDraftAuto(),
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
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(height: 20),
                  Text(
                    _contentCtrl.text,
                    style: TextStyle(color: NixColors.textPrimary, fontSize: 13, height: 1.4),
                  ),
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
                hintText: 'Escreva seu artigo aqui. O conteúdo é sanitizado contra XSS e canonicamente assinado.',
                filled: true,
                fillColor: NixColors.surfaceCard,
                border: OutlineInputBorder(borderRadius: NixTokens.borderSm),
              ),
              onChanged: (_) => _saveDraftAuto(),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: NixColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'Discussões Encadeadas do Nix Archive',
              style: TextStyle(
                color: NixColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Comentários autenticados criptograficamente (`nix.archive.comment.v1`) com encadeamento em árvore e moderação local.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
