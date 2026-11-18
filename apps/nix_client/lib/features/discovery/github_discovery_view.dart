import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/github_repo.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Aba GitHub Discovery (Inspirada no layout starwire.foo e integrada ao dataset Starwire com 4.188 repositórios).
/// Permite explorar projetos de código aberto de agentes, privacidade, IA e sistemas,
/// com pesquisa em tempo real, filtros de tópicos/linguagens e salvamento de 1 clique no Acervo Cultural.
class GithubDiscoveryView extends StatelessWidget {
  const GithubDiscoveryView({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final accent = context.accentColor;
    final repos = nixState.filteredGithubRepos;

    return Container(
      color: NixColors.background,
      child: Column(
        children: [
          // Cabeçalho da Aba Discovery
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              color: NixColors.surfaceElevated,
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                Icon(Icons.code_rounded, size: 20, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'GITHUB DISCOVERY · ACERVO ABERTO DE CÓDIGO',
                              style: TextStyle(
                                color: Colors.white,
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
                              color: accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: accent.withValues(alpha: 0.3)),
                            ),
                            child: const Text(
                              'STARWIRE CC0-1.0',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'Catálogo integrado starwire.foo · Repositórios de agentes, sistemas, criptografia e privacidade',
                        style: TextStyle(color: NixColors.textMuted, fontSize: 10.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: NixColors.surfaceActive,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: accent.withValues(alpha: 0.3), width: 1),
                  ),
                  child: Text(
                    '${repos.length} REPOSITÓRIOS',
                    style: TextStyle(
                      color: accent,
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
            decoration: const BoxDecoration(
              color: NixColors.surfaceSidebar,
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Linha de Busca e Seleção de Ordenação
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) => nixState.setGithubSearchQuery(v),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Filtrar por nome, autor, descrição ou tópicos (Ctrl+K)...',
                          prefixIcon: Icon(Icons.search_rounded, size: 18, color: accent),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          filled: true,
                          fillColor: NixColors.surfaceCard,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: NixColors.surfaceBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: NixColors.surfaceBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: accent),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Dropdown de Ordenação
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
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          items: const [
                            DropdownMenuItem(value: 'stars', child: Text('★ Mais Estrelados')),
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
                // Pílulas de Tópicos
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _topicChip(nixState, 'Todos', accent),
                      _topicChip(nixState, 'agents', accent),
                      _topicChip(nixState, 'cryptography', accent),
                      _topicChip(nixState, 'privacy', accent),
                      _topicChip(nixState, 'tor', accent),
                      _topicChip(nixState, 'systems', accent),
                      _topicChip(nixState, 'mesh', accent),
                      _topicChip(nixState, 'llm', accent),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tabela / Lista de Repositórios
          Expanded(
            child: repos.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhum repositório encontrado para este filtro.',
                      style: TextStyle(color: NixColors.textMuted, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: repos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, idx) {
                      final repo = repos[idx];
                      return _RepoListItem(
                        rank: idx + 1,
                        repo: repo,
                        accent: accent,
                        onToggleSave: () => nixState.toggleSaveRepoInAcervo(repo.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _topicChip(NixState state, String topic, Color accent) {
    final isSelected = state.githubSelectedTopic.toLowerCase() == topic.toLowerCase();
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
              color: isSelected ? Colors.black : NixColors.textSecondary,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _RepoListItem extends StatelessWidget {
  final int rank;
  final GithubRepository repo;
  final Color accent;
  final VoidCallback onToggleSave;

  const _RepoListItem({
    required this.rank,
    required this.repo,
    required this.accent,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: NixTokens.borderMd,
        border: Border.all(
          color: repo.isSavedInAcervo ? accent.withValues(alpha: 0.4) : NixColors.surfaceBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ranking
          Container(
            width: 32,
            alignment: Alignment.center,
            child: Text(
              '#$rank',
              style: TextStyle(
                color: repo.isTrending ? accent : NixColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Informações do Repositório
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
                      style: const TextStyle(color: NixColors.textSecondary, fontSize: 13),
                    ),
                    Text(
                      repo.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (repo.isTrending)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: accent.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'EM ALTA',
                          style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    if (repo.category.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          repo.category,
                          style: const TextStyle(color: NixColors.textMuted, fontSize: 9),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white24, width: 0.5),
                      ),
                      child: Text(
                        repo.license,
                        style: const TextStyle(color: NixColors.textSecondary, fontSize: 9.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  repo.description,
                  style: const TextStyle(color: NixColors.textSecondary, fontSize: 12, height: 1.3),
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
                        style: const TextStyle(color: NixColors.textMuted, fontSize: 10),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Coluna Direita: Stars & Botão Salvar no Acervo
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
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                  const SizedBox(width: 3),
                  Text(
                    repo.formattedStars,
                    style: const TextStyle(
                      color: Colors.white,
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
                    style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: Key('save_acervo_${repo.id}'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: repo.isSavedInAcervo ? accent : Colors.transparent,
                  foregroundColor: repo.isSavedInAcervo ? Colors.black : Colors.white,
                  side: BorderSide(
                    color: repo.isSavedInAcervo ? accent : Colors.white38,
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
        return Colors.white54;
    }
  }
}
