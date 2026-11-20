import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/space.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../design/nix_glass.dart';

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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: Row(
              children: [
                Expanded(
                    child: Text('Comunidades e canais públicos',
                        style: NixTokens.headingMedium())),
                IconButton.outlined(
                  tooltip: nixState.exploreSortAscending
                      ? 'Menos populosos primeiro'
                      : 'Mais populosos primeiro',
                  onPressed: () => nixState
                      .setExploreSortAscending(!nixState.exploreSortAscending),
                  icon: Icon(nixState.exploreSortAscending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded),
                ),
              ],
            ),
          ),

          // Banner Hero Minimalista + Busca em Tempo Real
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                NixGlass(
                    child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ENCONTRE SUA COMUNIDADE NO NIX',
                        style: TextStyle(
                          color: NixColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Listagem priorizando células enxutas (do menos populoso ao mais populoso) para descentralização orgânica.',
                        style: TextStyle(
                            color: NixColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        onChanged: (v) => nixState.setExploreSearchQuery(v),
                        style: TextStyle(
                            color: NixColors.textPrimary, fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: 'Nome, tema ou tecnologia',
                          prefixIcon: Icon(Icons.search_rounded,
                              color: NixColors.textSecondary),
                          fillColor: NixColors.background,
                        ),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 16),

                Wrap(
                  spacing: 7,
                  runSpacing: 4,
                  children: [
                    for (final category in _categories)
                      ChoiceChip(
                        label: Text(category),
                        selected: category == _selectedCategory,
                        selectedColor: context.accentColor,
                        labelStyle: TextStyle(
                          color: category == _selectedCategory
                              ? context.onAccentColor
                              : NixColors.textSecondary,
                        ),
                        onSelected: (_) =>
                            setState(() => _selectedCategory = category),
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // Grade de Cartões de Comunidades Públicas
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth > 900
                        ? 3
                        : (constraints.maxWidth > 560 ? 2 : 1);
                    final width =
                        (constraints.maxWidth - (cols - 1) * 16) / cols;
                    if (displayedSpaces.isEmpty)
                      return const Text('Nenhuma comunidade encontrada.');
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final space in displayedSpaces)
                          SizedBox(
                              width: width,
                              child: _PublicSpaceCard(
                                space: space,
                                onJoin: () {
                                  if (!nixState.joinDiscoverableSpace(space)) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Entrada indisponível. O canal pode exigir aprovação.')),
                                    );
                                  }
                                },
                              )),
                      ],
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
                      style: TextStyle(
                        color: NixColors.textPrimary,
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
                          Icon(Icons.verified_outlined,
                              size: 14, color: NixColors.textPrimary),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              space.name,
                              style: TextStyle(
                                color: NixColors.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        space.categoryTag,
                        style:
                            TextStyle(color: NixColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              space.description,
              style: TextStyle(
                color: NixColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            Divider(height: 16, color: NixColors.surfaceBorder),
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      if (space.memberCount case final count?)
                        count == 1 ? '1 membro conhecido' : '$count membros',
                      if (space.onlineCount case final count?) '$count online',
                    ].join(' · '),
                    style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Acessar',
                  style: TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, size: 13),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
