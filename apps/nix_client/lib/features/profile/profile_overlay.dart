import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../settings/settings_center.dart';
import 'card_id_widget.dart';

/// Painel de Perfil Animado (Fluid Motion) com Transição Integrada entre Card ID e Configurações.
class ProfileOverlay extends StatefulWidget {
  const ProfileOverlay({super.key});

  @override
  State<ProfileOverlay> createState() => _ProfileOverlayState();
}

class _ProfileOverlayState extends State<ProfileOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _backdropOpacity;
  late Animation<double> _panelScale;
  late Animation<double> _panelOpacity;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: NixTokens.motionFluid,
    );
    _backdropOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _panelScale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: NixTokens.curveFluid,
      ),
    );
    _panelOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.15, 1.0, curve: Curves.easeOutCubic),
    );

    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _closeWithAnimation(NixState state) async {
    if (!state.settings.reducedMotion) {
      await _controller.reverse();
    }
    if (mounted) {
      state.closeProfileOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final inSettings = nixState.isSettingsOpenInOverlay;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          _closeWithAnimation(nixState);
        }
      },
      child: Semantics(
        label: 'Painel de Perfil e Identidade Pública do Usuário',
        scopesRoute: true,
        explicitChildNodes: true,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Stack(
              children: [
                // Camada escura translúcida (fecha ao clicar fora)
                GestureDetector(
                  key: const Key('profile_overlay_backdrop'),
                  onTap: () => _closeWithAnimation(nixState),
                  child: Container(
                    color: Colors.black.withOpacity(0.82 * _backdropOpacity.value),
                  ),
                ),

                // Painel Central com Animação Fluida (Scale + Opacity)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Transform.scale(
                      scale: _panelScale.value,
                      child: Opacity(
                        opacity: _panelOpacity.value,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 920,
                            maxHeight: 680,
                          ),
                          child: Material(
                            color: NixColors.surfaceCard,
                            borderRadius: NixTokens.borderXl,
                            clipBehavior: Clip.antiAlias,
                            elevation: 28,
                            child: Container(
                              decoration: BoxDecoration(
                                color: NixColors.background,
                                borderRadius: NixTokens.borderXl,
                                border: Border.all(
                                  color: NixColors.surfaceBorderStrong,
                                  width: 1.2,
                                ),
                              ),
                              child: AnimatedSwitcher(
                                duration: NixTokens.motionMedium,
                                switchInCurve: NixTokens.curveStandard,
                                switchOutCurve: NixTokens.curveStandard,
                                child: inSettings
                                    ? SettingsCenter(
                                        key: const ValueKey('overlay_settings'),
                                        onBackToCardId: () => nixState.transitionBackToCardId(),
                                        onClose: () => _closeWithAnimation(nixState),
                                      )
                                    : Column(
                                        key: const ValueKey('overlay_card_id'),
                                        children: [
                                          // Barra de Controle do Overlay
                                          Container(
                                            height: 50,
                                            padding: const EdgeInsets.symmetric(horizontal: 18),
                                            decoration: const BoxDecoration(
                                              color: NixColors.surfaceSidebar,
                                              border: Border(
                                                bottom: BorderSide(color: NixColors.surfaceBorder),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.badge_outlined,
                                                  color: NixColors.textPrimary,
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 8),
                                                const Expanded(
                                                  child: Text(
                                                    'PERFIL & IDENTIDADE SOBERANA (CARD ID)',
                                                    style: TextStyle(
                                                      color: NixColors.textPrimary,
                                                      fontSize: 12.5,
                                                      fontWeight: FontWeight.w700,
                                                      letterSpacing: 1.0,
                                                    ),
                                                  ),
                                                ),
                                                TextButton.icon(
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: NixColors.textSecondary,
                                                  ),
                                                  onPressed: () {
                                                    nixState.openHomePrivateArea(resetToCardId: true);
                                                    _closeWithAnimation(nixState);
                                                  },
                                                  icon: const Icon(Icons.chat_outlined, size: 15),
                                                  label: const Text(
                                                    'Ir para Conversas Privadas',
                                                    style: TextStyle(fontSize: 11.5),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                IconButton(
                                                  key: const Key('close_profile_overlay_button'),
                                                  icon: const Icon(
                                                    Icons.close_rounded,
                                                    color: NixColors.textSecondary,
                                                    size: 20,
                                                  ),
                                                  tooltip: 'Fechar Painel (Esc)',
                                                  onPressed: () => _closeWithAnimation(nixState),
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Conteúdo do Card ID e Passaporte Cultural
                                          Expanded(
                                            child: CardIdWidget(
                                              onOpenSettings: () => nixState.transitionToSettings(),
                                              showCulturalPassport: true,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
