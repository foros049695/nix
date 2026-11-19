import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nix_transport/nix_transport.dart';
import 'package:provider/provider.dart';
import '../../core/models/github_repo.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Aba GitHub Discovery (inspirada no Starwire e integrada ao dataset Starwire real com 4.188 repositórios).
/// Inclui gráficos com dados reais do catálogo, ações de cópia/clone, visualização de releases,
/// download de código-fonte em ZIP respeitando o transporte privado fail-closed e salvamento privado no Acervo.
class GithubDiscoveryView extends StatefulWidget {
  const GithubDiscoveryView({super.key});

  @override
  State<GithubDiscoveryView> createState() => _GithubDiscoveryViewState();
}

class _GithubDiscoveryViewState extends State<GithubDiscoveryView> {
  bool _showAnalytics = true;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = context.read<NixState>().githubSearchQuery;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final accent = context.accentColor;
    final accentText = context.accentTextColor;
    final repos = nixState.filteredGithubRepos;
    final langCounts = nixState.githubLanguageCounts;
    final catCounts = nixState.githubCategoryCounts;
    final totalTrending = nixState.githubRepos.where((r) => r.isTrending).length;

    return Container(
      color: NixColors.background,
      child: Column(
        children: [
          // Cabeçalho da Aba Discovery
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: NixColors.surfaceElevated,
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                Icon(Icons.code_rounded, size: 20, color: accentText),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'STARWIRE GITHUB DISCOVERY · ACERVO ABERTO',
                              style: TextStyle(
                                color: NixColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: accent.withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              'STARWIRE CC0-1.0',
                              style: TextStyle(
                                color: accentText,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${nixState.githubRepos.length} projetos carregados localmente · $totalTrending em alta · Salvamento privado por padrão',
                        style: TextStyle(color: NixColors.textMuted, fontSize: 10.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const Key('toggle_starwire_charts'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NixColors.textPrimary,
                    side: BorderSide(color: NixColors.surfaceBorderStrong),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: () => setState(() => _showAnalytics = !_showAnalytics),
                  icon: Icon(_showAnalytics ? Icons.bar_chart_rounded : Icons.analytics_outlined, size: 15, color: accentText),
                  label: Text(_showAnalytics ? 'Ocultar Gráficos' : 'Ver Gráficos', style: const TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: NixColors.surfaceActive,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    '${repos.length} EXIBIDOS',
                    style: TextStyle(
                      color: accentText,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Barra de Filtros, Tópicos e Busca
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: NixColors.surfaceSidebar,
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: nixState.setGithubSearchQuery,
                        style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Filtrar por nome, autor, descrição ou tópicos...',
                          prefixIcon: Icon(Icons.search_rounded, size: 18, color: accentText),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.close_rounded, size: 16, color: NixColors.textMuted),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    nixState.setGithubSearchQuery('');
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          filled: true,
                          fillColor: NixColors.surfaceCard,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: NixColors.surfaceBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: NixColors.surfaceBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: accent),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: NixColors.surfaceCard,
                        borderRadius: NixTokens.borderSm,
                        border: Border.all(color: NixColors.surfaceBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: nixState.githubSortBy,
                          dropdownColor: NixColors.surfaceElevatedHigh,
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'stars', child: Text('★ Mais Estrelados')),
                            DropdownMenuItem(value: 'trending', child: Text('🔥 Em Alta / Semana')),
                            DropdownMenuItem(value: 'updated', child: Text('⏱ Atualizados Recentemente')),
                          ],
                          onChanged: (v) {
                            if (v != null) nixState.setGithubSortBy(v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _topicChip(context, nixState, 'Todos'),
                      _topicChip(context, nixState, 'agents'),
                      _topicChip(context, nixState, 'cryptography'),
                      _topicChip(context, nixState, 'privacy'),
                      _topicChip(context, nixState, 'tor'),
                      _topicChip(context, nixState, 'systems'),
                      _topicChip(context, nixState, 'mesh'),
                      _topicChip(context, nixState, 'llm'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Lista + Gráficos Reais Starwire
          Expanded(
            child: repos.isEmpty && !_showAnalytics
                ? Center(
                    child: Text(
                      'Nenhum repositório encontrado para este filtro.',
                      style: TextStyle(color: NixColors.textMuted, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: repos.length + (_showAnalytics ? 1 : 0) + (repos.isEmpty ? 1 : 0),
                    itemBuilder: (context, idx) {
                      if (_showAnalytics && idx == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _StarwireRealChartsPanel(
                            totalRepos: nixState.githubRepos.length,
                            filteredCount: repos.length,
                            languageCounts: langCounts,
                            categoryCounts: catCounts,
                            onSelectTopic: (tag) {
                              _searchCtrl.text = tag;
                              nixState.setGithubSearchQuery(tag);
                            },
                          ),
                        );
                      }
                      final repoIdx = _showAnalytics ? idx - 1 : idx;
                      if (repos.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              'Nenhum repositório encontrado para este filtro.',
                              style: TextStyle(color: NixColors.textMuted, fontSize: 13),
                            ),
                          ),
                        );
                      }
                      final repo = repos[repoIdx];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RepoListItem(
                          rank: repoIdx + 1,
                          repo: repo,
                          onToggleSave: () {
                            nixState.toggleSaveRepoInAcervo(repo.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  repo.isSavedInAcervo
                                      ? '${repo.fullName} removido do Acervo.'
                                      : '${repo.fullName} salvo no seu Acervo (privado por padrão).',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          onDownloadZip: () => _showDownloadZipDialog(context, nixState, repo),
                          onViewReleases: () => _showReleasesDialog(context, repo),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _topicChip(BuildContext context, NixState state, String topic) {
    final isSelected = state.githubSelectedTopic.toLowerCase() == topic.toLowerCase();
    final accent = context.accentColor;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => state.setGithubTopic(topic),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? accent : NixColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isSelected ? accent : NixColors.surfaceBorder),
          ),
          child: Text(
            topic == 'Todos' ? 'Todos os Tópicos' : '#$topic',
            style: TextStyle(
              color: isSelected ? context.onAccentColor : NixColors.textSecondary,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  void _showReleasesDialog(BuildContext context, GithubRepository repo) {
    final tarballUrl = '${repo.htmlUrl}/archive/HEAD.zip';
    final releasesUrl = '${repo.htmlUrl}/releases';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.new_releases_outlined, color: context.accentTextColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Releases & Metadados · ${repo.fullName}',
                style: TextStyle(color: NixColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                repo.description,
                style: TextStyle(color: NixColors.textSecondary, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: NixTokens.borderSm,
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kvLine('Linguagem / Licença', '${repo.language} · ${repo.license}'),
                    _kvLine('Popularidade', '${repo.formattedStars} ★ · ${repo.forksCount} forks'),
                    _kvLine('Último Push Registrado', repo.updatedDate.toIso8601String().split('T').first),
                    _kvLine('Página de Releases', releasesUrl),
                    _kvLine('Tarball Código-Fonte', tarballUrl),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: NixColors.accentWarning.withValues(alpha: 0.10),
                  borderRadius: NixTokens.borderSm,
                  border: Border.all(color: NixColors.accentWarning.withValues(alpha: 0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: NixColors.accentWarning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Aviso: o catálogo Starwire não executa nem verifica binários de terceiros. Confira hashes SHA-256 e assinaturas PGP diretamente nas Releases antes de executar artefatos.',
                        style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: releasesUrl));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL de Releases copiada.')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 14),
            label: const Text('Copiar URL de Releases'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _kvLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(label, style: TextStyle(color: NixColors.textMuted, fontSize: 11)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: NixColors.textPrimary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDownloadZipDialog(BuildContext context, NixState state, GithubRepository repo) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RepoZipDownloadDialog(
        repo: repo,
        strictTorMode: state.settings.transportProfile.toLowerCase().contains('tor') ||
            state.settings.transportProfile.toLowerCase().contains('fail-closed'),
        isStrictOffGridMode: state.isStrictOffGridMode,
      ),
    );
  }
}

class _StarwireRealChartsPanel extends StatelessWidget {
  final int totalRepos;
  final int filteredCount;
  final Map<String, int> languageCounts;
  final Map<String, int> categoryCounts;
  final ValueChanged<String> onSelectTopic;

  const _StarwireRealChartsPanel({
    required this.totalRepos,
    required this.filteredCount,
    required this.languageCounts,
    required this.categoryCounts,
    required this.onSelectTopic,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    final accentText = context.accentTextColor;
    final topLangs = languageCounts.entries.take(6).toList();
    final topCats = categoryCounts.entries.take(5).toList();
    final maxLang = topLangs.isNotEmpty ? topLangs.first.value : 1;
    final maxCat = topCats.isNotEmpty ? topCats.first.value : 1;

    return Container(
      key: const Key('starwire_analytics_panel'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: NixTokens.borderMd,
        border: Border.all(color: NixColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, size: 16, color: accentText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'DISTRIBUIÇÃO REAL DO DATASET STARWIRE ($totalRepos REPOSITÓRIOS · $filteredCount FILTRADOS)',
                  style: NixTokens.labelUppercase(),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;
              final langChart = _buildBarBlock(
                title: 'Linguagens Mais Frequentes',
                entries: topLangs,
                maxVal: maxLang,
                accent: accent,
                accentText: accentText,
              );
              final catChart = _buildBarBlock(
                title: 'Categorias do Catálogo',
                entries: topCats,
                maxVal: maxCat,
                accent: accent.withValues(alpha: 0.78),
                accentText: accentText,
              );
              if (narrow) {
                return Column(
                  children: [
                    langChart,
                    const SizedBox(height: 12),
                    catChart,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: langChart),
                  const SizedBox(width: 20),
                  Expanded(child: catChart),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBarBlock({
    required String title,
    required List<MapEntry<String, int>> entries,
    required int maxVal,
    required Color accent,
    required Color accentText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: NixColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ...entries.map((e) {
          final ratio = maxVal > 0 ? (e.value / maxVal).clamp(0.04, 1.0) : 0.04;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => onSelectTopic(e.key),
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  SizedBox(
                    width: 112,
                    child: Text(
                      e.key,
                      style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Stack(
                        children: [
                          Container(height: 8, color: NixColors.surfaceActive),
                          FractionallySizedBox(
                            widthFactor: ratio,
                            child: Container(height: 8, color: accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${e.value}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: accentText,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _RepoListItem extends StatelessWidget {
  final int rank;
  final GithubRepository repo;
  final VoidCallback onToggleSave;
  final VoidCallback onDownloadZip;
  final VoidCallback onViewReleases;

  const _RepoListItem({
    required this.rank,
    required this.repo,
    required this.onToggleSave,
    required this.onDownloadZip,
    required this.onViewReleases,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    final accentText = context.accentTextColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: NixTokens.borderMd,
        border: Border.all(
          color: repo.isSavedInAcervo ? accent.withValues(alpha: 0.45) : NixColors.surfaceBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            alignment: Alignment.center,
            child: Text(
              '#$rank',
              style: TextStyle(
                color: repo.isTrending ? accentText : NixColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      '${repo.owner} / ',
                      style: TextStyle(color: NixColors.textSecondary, fontSize: 13),
                    ),
                    Text(
                      repo.name,
                      style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (repo.isTrending)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: accent.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          'EM ALTA',
                          style: TextStyle(color: accentText, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    if (repo.category.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: NixColors.surfaceActive,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          repo.category,
                          style: TextStyle(color: NixColors.textMuted, fontSize: 9),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: NixColors.surfaceActive,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: NixColors.surfaceBorder, width: 0.5),
                      ),
                      child: Text(
                        repo.license,
                        style: TextStyle(color: NixColors.textSecondary, fontSize: 9.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  repo.description,
                  style: TextStyle(color: NixColors.textSecondary, fontSize: 12, height: 1.3),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: repo.topics.map((t) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: NixColors.surfaceActive,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '#$t',
                        style: TextStyle(color: NixColors.textMuted, fontSize: 10),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _miniAction(
                      key: Key('copy_repo_url_${repo.id}'),
                      icon: Icons.link_rounded,
                      label: 'Copiar URL',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: repo.htmlUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('URL copiada: ${repo.htmlUrl}')),
                        );
                      },
                    ),
                    _miniAction(
                      icon: Icons.terminal_rounded,
                      label: 'git clone',
                      onTap: () {
                        final cmd = 'git clone ${repo.htmlUrl}.git';
                        Clipboard.setData(ClipboardData(text: cmd));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Comando copiado: $cmd')),
                        );
                      },
                    ),
                    _miniAction(
                      key: Key('releases_${repo.id}'),
                      icon: Icons.new_releases_outlined,
                      label: 'Releases',
                      onTap: onViewReleases,
                    ),
                    _miniAction(
                      key: Key('download_zip_${repo.id}'),
                      icon: Icons.archive_outlined,
                      label: 'Baixar ZIP',
                      onTap: onDownloadZip,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _languageColor(repo.language),
                    ),
                  ),
                  Text(
                    repo.language,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                  const SizedBox(width: 3),
                  Text(
                    repo.formattedStars,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (repo.starsThisWeek > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '+${repo.starsThisWeek} ★/semana',
                    style: TextStyle(color: accentText, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: Key('save_acervo_${repo.id}'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: repo.isSavedInAcervo ? accent : Colors.transparent,
                  foregroundColor: repo.isSavedInAcervo ? context.onAccentColor : NixColors.textPrimary,
                  side: BorderSide(
                    color: repo.isSavedInAcervo ? accent : NixColors.surfaceBorderStrong,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: onToggleSave,
                icon: Icon(
                  repo.isSavedInAcervo ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                  size: 14,
                ),
                label: Text(
                  repo.isSavedInAcervo ? 'Salvo no Acervo' : 'Salvar no Acervo',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniAction({
    Key? key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: NixColors.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: NixColors.surfaceBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: NixColors.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(color: NixColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Color _languageColor(String lang) {
    switch (lang.toLowerCase()) {
      case 'rust':
        return const Color(0xFFDEA584);
      case 'go':
        return const Color(0xFF00ADD8);
      case 'python':
        return const Color(0xFF3572A5);
      case 'c++':
        return const Color(0xFFF34B7D);
      case 'dart':
        return const Color(0xFF00B4AB);
      default:
        return NixColors.textMuted;
    }
  }
}

/// Impõe a política de transporte fail-closed para downloads do catálogo Starwire:
/// proíbe qualquer bypass clearnet quando `strictTorMode` está ativo.
TransportPolicy enforceStarwireDownloadTransport({
  required bool strictTorMode,
  bool allowClearnetBypass = false,
  bool isStrictOffGridMode = false,
  int socksPort = 9050,
}) {
  if (isStrictOffGridMode) {
    throw const TransportBlockedException(
      '[Modo Off-Grid Estrito] Downloads de rede/Wi-Fi estão bloqueados. Utilize apenas Bluetooth BLE ou Rádio LoRa.',
    );
  }
  if (strictTorMode && allowClearnetBypass) {
    throw const TransportBlockedException(
      '[Fail-Closed] Bypass clearnet proibido no Modo Tor Estrito (Starwire GitHub Discovery).',
    );
  }
  if (strictTorMode) {
    return TransportPolicy(
      mode: TransportMode.torFailClosed,
      socksHost: '127.0.0.1',
      socksPort: socksPort,
    );
  }
  return TransportPolicy(
    mode: TransportMode.loopbackTest,
    socksHost: '127.0.0.1',
    socksPort: socksPort,
  );
}

class _RepoZipDownloadDialog extends StatefulWidget {
  final GithubRepository repo;
  final bool strictTorMode;
  final bool isStrictOffGridMode;

  const _RepoZipDownloadDialog({
    required this.repo,
    required this.strictTorMode,
    this.isStrictOffGridMode = false,
  });

  @override
  State<_RepoZipDownloadDialog> createState() => _RepoZipDownloadDialogState();
}

class _RepoZipDownloadDialogState extends State<_RepoZipDownloadDialog> {
  bool _downloading = false;
  bool _cancelled = false;
  bool _completed = false;
  double? _progress;
  String? _statusText;
  String? _savedPath;
  HttpClient? _httpClient;

  @override
  void dispose() {
    _httpClient?.close(force: true);
    super.dispose();
  }

  Future<void> _startPolicyCompliantDownload() async {
    setState(() {
      _downloading = true;
      _cancelled = false;
      _completed = false;
      _progress = null;
      _statusText = widget.strictTorMode
          ? 'Validando política Tor fail-closed (bypass clearnet proibido)...'
          : 'Conectando ao arquivo fonte do repositório...';
      _savedPath = null;
    });

    try {
      final policy = enforceStarwireDownloadTransport(
        strictTorMode: widget.strictTorMode,
        allowClearnetBypass: false,
        isStrictOffGridMode: widget.isStrictOffGridMode,
      );
      final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      final outDir = Directory('$home/.local/share/nix/downloads');
      final outFile = resolveStarwireZipFile(
        outDir,
        widget.repo.owner,
        widget.repo.name,
      );
      final zipUrl = Uri.parse('${widget.repo.htmlUrl}/archive/HEAD.zip');

      if (widget.strictTorMode) {
        // Fail-closed estrito: bloqueia qualquer destino clearnet (ex: github.com) sem bypass
        policy.assertAllowedUri(zipUrl);
      }

      final client = HttpClient();
      _httpClient = client;
      try {
        final req = await client.getUrl(zipUrl);
        req.headers.set(HttpHeaders.userAgentHeader, 'NixClient/0.4.0');
        final res = await req.close();

        if (_cancelled || !mounted) return;
        if (res.statusCode < 200 || res.statusCode >= 300) {
          setState(() {
            _downloading = false;
            _statusText = 'Falha HTTP ${res.statusCode} ao obter arquivo.';
          });
          return;
        }

        outDir.createSync(recursive: true);
        final sink = outFile.openWrite();
        final total = res.contentLength;
        var received = 0;

        await for (final chunk in res) {
          if (_cancelled) {
            await sink.close();
            if (outFile.existsSync()) outFile.deleteSync();
            return;
          }
          sink.add(chunk);
          received += chunk.length;
          if (mounted) {
            setState(() {
              _progress = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
              _statusText = 'Baixando ${(received / 1024).toStringAsFixed(1)} KB...';
            });
          }
        }
        await sink.close();
        if (mounted && !_cancelled) {
          setState(() {
            _downloading = false;
            _completed = true;
            _progress = 1.0;
            _savedPath = outFile.path;
            _statusText = 'Código-fonte salvo em disco.';
          });
        }
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      if (mounted && !_cancelled) {
        setState(() {
          _downloading = false;
          _statusText = '[Fail-Closed] Conexão bloqueada ou indisponível: $e';
        });
      }
    }
  }

  void _cancel() {
    _cancelled = true;
    _httpClient?.close(force: true);
    if (mounted) {
      setState(() {
        _downloading = false;
        _statusText = 'Download cancelado pelo usuário.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final zipUrl = '${widget.repo.htmlUrl}/archive/HEAD.zip';
    return AlertDialog(
      title: Text(
        'Baixar Código-Fonte · ${widget.repo.name}',
        style: TextStyle(color: NixColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: NixColors.accentWarning.withValues(alpha: 0.12),
                borderRadius: NixTokens.borderSm,
                border: Border.all(color: NixColors.accentWarning.withValues(alpha: 0.35)),
              ),
              child: Text(
                'Aviso de Código-Fonte: Este ZIP contém código-fonte bruto de terceiros. Inspecione scripts e dependências antes de compilar ou executar.',
                style: TextStyle(color: NixColors.textPrimary, fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.strictTorMode) ...[
              Container(
                key: const Key('strict_tor_no_clearnet_bypass_banner'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: NixColors.accentDanger.withValues(alpha: 0.10),
                  borderRadius: NixTokens.borderSm,
                  border: Border.all(color: NixColors.accentDanger.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Política Fail-Closed Ativa (Bypass Clearnet Bloqueado)',
                      style: TextStyle(
                        color: NixColors.accentDanger,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'O Nix não permite bypass clearnet quando o Modo Tor Estrito está ativo. O download abaixo ocorre exclusivamente via circuito Tor SOCKS5 (127.0.0.1:9050) ou falha fechado.',
                      style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            SelectableText(
              zipUrl,
              style: TextStyle(color: NixColors.textMuted, fontSize: 11, fontFamily: 'monospace'),
            ),
            if (_downloading || _statusText != null) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: _downloading ? _progress : (_completed ? 1.0 : 0.0)),
              const SizedBox(height: 6),
              Text(
                _statusText ?? '',
                style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
              ),
              if (_savedPath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SelectableText(
                    _savedPath!,
                    style: TextStyle(color: NixColors.textMuted, fontSize: 10.5, fontFamily: 'monospace'),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (_downloading)
          TextButton(
            onPressed: _cancel,
            child: Text('Cancelar Download', style: TextStyle(color: NixColors.accentDanger)),
          )
        else ...[
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: zipUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL ZIP copiada!')),
              );
            },
            child: const Text('Copiar URL ZIP'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          ElevatedButton(
            key: const Key('download_zip_action_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accentColor,
              foregroundColor: context.onAccentColor,
            ),
            onPressed: _startPolicyCompliantDownload,
            child: Text(widget.strictTorMode ? 'Baixar ZIP via Tor (SOCKS5)' : 'Baixar ZIP'),
          ),
        ],
      ],
    );
  }
}

/// Gera um nome de arquivo seguro para o ZIP de código-fonte do Starwire,
/// mantendo apenas `[A-Za-z0-9._-]` e recusando entradas vazias ou apenas pontos.
/// Um ponto inicial só é substituído quando ficaria no começo do arquivo final,
/// evitando arquivo oculto no Unix sem descaracterizar nomes como `.github`.
String buildStarwireZipFilename(String owner, String name) {
  var safeOwner = _sanitizeStarwireSegment(owner);
  var safeName = _sanitizeStarwireSegment(name);
  if (safeOwner.startsWith('.')) {
    safeOwner = '_${safeOwner.substring(1)}';
  }
  if (safeName.endsWith('.')) {
    safeName = '${safeName.substring(0, safeName.length - 1)}_';
  }
  return '${safeOwner}_$safeName.zip';
}

/// Resolve o arquivo de destino do ZIP e confirma que permanece em `outDir`.
File resolveStarwireZipFile(Directory outDir, String owner, String name) {
  final fileName = buildStarwireZipFilename(owner, name);
  final sep = Platform.pathSeparator;
  final normalizedDir = outDir.absolute.uri.normalizePath().toFilePath(
        windows: Platform.isWindows,
      );
  final dirPrefix =
      normalizedDir.endsWith(sep) ? normalizedDir : '$normalizedDir$sep';
  final normalizedFile = File('$dirPrefix$fileName')
      .absolute
      .uri
      .normalizePath()
      .toFilePath(windows: Platform.isWindows);

  if (!normalizedFile.startsWith(dirPrefix) ||
      normalizedFile.substring(dirPrefix.length).contains(sep)) {
    throw ArgumentError.value(
      normalizedFile,
      'outFile',
      'Caminho resolvido escapa do diretório de downloads.',
    );
  }
  return File(normalizedFile);
}

String _sanitizeStarwireSegment(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || RegExp(r'^\.+$').hasMatch(trimmed)) {
    throw const FormatException('Identificador de repositório inválido.');
  }
  return trimmed
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
      .replaceAll(RegExp(r'\.{2,}'), '_');
}
