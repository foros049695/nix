import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/models/space.dart';
import '../../state/nix_state.dart';
import '../dialogs/create_space_dialog.dart';
import '../dialogs/privacy_info_dialog.dart';

class SpacesDock extends StatelessWidget {
  const SpacesDock({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();

    return Container(
      width: 72,
      decoration: const BoxDecoration(
        color: NixColors.surfaceDock,
        border: Border(
          right: BorderSide(color: NixColors.surfaceBorder, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Logo Oficial do Projeto Nix
          _BrandLogoButton(onTap: () {
            showDialog(
              context: context,
              builder: (ctx) => const PrivacyInfoDialog(),
            );
          }),
          const SizedBox(height: 8),
          const Divider(
            indent: 14,
            endIndent: 14,
            color: NixColors.surfaceBorder,
            height: 16,
          ),
          // Lista de Servidores / Espaços
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: nixState.spaces.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final space = nixState.spaces[index];
                final isSelected = space.id == nixState.currentSpace.id;

                return _SpaceItem(
                  space: space,
                  isSelected: isSelected,
                  onTap: () => nixState.selectSpace(space),
                );
              },
            ),
          ),
          // Botão Adicionar Espaço
          _ActionButton(
            icon: Icons.add,
            tooltip: 'Criar Novo Espaço / Comunidade',
            color: NixColors.accentGreen,
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => const CreateSpaceDialog(),
              );
            },
          ),
          const SizedBox(height: 8),
          // Status de Segurança & Tor
          _ActionButton(
            icon: Icons.shield_rounded,
            tooltip: 'Status da Matriz de Privacidade & Tor',
            color: NixColors.accentTor,
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => const PrivacyInfoDialog(),
              );
            },
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _BrandLogoButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BrandLogoButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Projeto Nix — Soberania & Privacidade',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NixColors.accentGreen.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: NixColors.accentGreen.withOpacity(0.15),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/images/nix_logo_128.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Text('🏴‍☠️', style: TextStyle(fontSize: 24)),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SpaceItem extends StatelessWidget {
  final Space space;
  final bool isSelected;
  final VoidCallback onTap;

  const _SpaceItem({
    required this.space,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Indicador lateral estilo Discord
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 4,
          height: isSelected ? 36 : 0,
          decoration: BoxDecoration(
            color: NixColors.accentGreen,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: '${space.name}\n${space.description}',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(isSelected ? 16 : 24),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isSelected ? NixColors.surfaceCardHover : NixColors.surfaceCard,
                borderRadius: BorderRadius.circular(isSelected ? 16 : 24),
                border: Border.all(
                  color: isSelected ? NixColors.accentGreen : NixColors.surfaceBorder,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Center(
                child: space.iconEmoji != null
                    ? Text(space.iconEmoji!, style: const TextStyle(fontSize: 22))
                    : Text(
                        space.initials,
                        style: TextStyle(
                          color: isSelected ? Colors.white : NixColors.textSecondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}
