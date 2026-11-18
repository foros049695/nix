import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/space.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Tela Explorar (Discover) — Lista grupos e canais públicos do menos populoso ao mais populoso.
class ExploreSpacesView extends StatefulWidget {
  const ExploreSpacesView({super.key});

  @override
  State<ExploreSpacesView> createState() => _ExploreSpacesViewState();
}

class _ExploreSpacesViewState extends State<ExploreSpacesView> {
  String _selectedCategory = 'Todos';

  final List<String> _categories = const [
    'Todos',
    'Criptografia',
    'Cultura & Mídia',
    'Rádio & Hardware',
    'Infraestrutura',
    'Finanças XMR',
    'Arquitetura & Core',
  ];

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final allSpaces = nixState.filteredDiscoverableSpaces;

    final displayedSpaces = _selectedCategory == 'Todos'
        ? allSpaces
        : allSpaces.where((s) => s.categoryTag == _selectedCategory).toList();

    return Container(
      color: NixColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho Superior
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              color: NixColors.surfaceSidebar,
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                const Icon(Icons.explore_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                const Text(
                  'EXPLORAR COMUNIDADES & CANAIS PÚBLICOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                // Ordenação: Menos Populoso -> Mais Populoso (padrão)
                InkWell(
                  onTap: () => nixState.setExploreSortAscending(!nixState.exploreSortAscending),
                  borderRadius: NixTokens.borderSm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: NixColors.surfaceCard,
                      borderRadius: NixTokens.borderSm,
                      border: Border.all(color: NixColors.surfaceBorderStrong),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          nixState.exploreSortAscending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          nixState.exploreSortAscending
                              ? 'Ordem: Menos Populoso → Mais Populoso'
                              : 'Ordem: Mais Populoso → Menos Populoso',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Banner Hero Minimalista + Busca em Tempo Real
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: NixTokens.amoledMetalGradient,
                    borderRadius: NixTokens.borderLg,
                    border: Border.all(color: NixColors.surfaceBorderStrong),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ENCONTRE SUA COMUNIDADE NO NIX',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Listagem priorizando células enxutas (do menos populoso ao mais populoso) para descentralização orgânica.',
                        style: TextStyle(color: NixColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        onChanged: (v) => nixState.setExploreSearchQuery(v),
                        style: const TextStyle(color: Colors.white, fontSize: 13.5),
                        decoration: const InputDecoration(
                          hintText: 'Pesquisar grupos públicos por nome, tema ou tecnologia...',
                          prefixIcon: Icon(Icons.search_rounded, color: NixColors.textSecondary),
                          fillColor: NixColors.background,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Filtro de Categorias
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categories.map((cat) {
                      final selected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () => setState(() => _selectedCategory = cat),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: selected ? Colors.white : NixColors.surfaceCard,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected ? Colors.white : NixColors.surfaceBorder,
                              ),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                color: selected ? Colors.black : NixColors.textSecondary,
                                fontSize: 12,
                                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),

                // Grade de Cartões de Comunidades Públicas
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth > 900
                        ? 3
                        : (constraints.maxWidth > 560 ? 2 : 1);
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        mainAxisExtent: 210,
                      ),
                      itemCount: displayedSpaces.length,
                      itemBuilder: (context, idx) {
                        final space = displayedSpaces[idx];
                        return _PublicSpaceCard(
                          space: space,
                          onJoin: () => nixState.joinDiscoverableSpace(space),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicSpaceCard extends StatelessWidget {
  final Space space;
  final VoidCallback onJoin;

  const _PublicSpaceCard({
    required this.space,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onJoin,
      borderRadius: NixTokens.borderMd,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: NixColors.surfaceCard,
          borderRadius: NixTokens.borderMd,
          border: Border.all(color: NixColors.surfaceBorderStrong, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: NixColors.surfaceActive,
                    borderRadius: NixTokens.borderSm,
                    border: Border.all(color: Colors.white30),
                  ),
                  child: Center(
                    child: Text(
                      space.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_outlined, size: 14, color: Colors.white),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              space.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        space.categoryTag,
                        style: const TextStyle(color: NixColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Text(
                space.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: NixColors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
            const Divider(height: 16, color: NixColors.surfaceBorder),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '${space.onlineCount} on · ${space.memberCount} membros',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Acessar →',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
