import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/nix_state.dart';
import '../design/nix_glass.dart';
import '../design/nix_surfaces.dart';
import '../settings/settings_center.dart';
import 'pager_profile.dart';

class ProfileOverlay extends StatelessWidget {
  const ProfileOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final settings = state.isSettingsOpenInOverlay;
    final mobile = MediaQuery.sizeOf(context).width < nixDesktopBreakpoint;
    final preferences = SettingsCenter(
      key: const ValueKey('overlay_settings'),
      fullScreen: mobile,
      initialCompactCategory: state.requestedOverlaySettingsCategory,
      onBackToCardId: state.backFromOverlaySettings,
      onClose: state.closeProfileOverlay,
    );
    if (mobile && settings) return SafeArea(child: preferences);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) state.closeProfileOverlay();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent ||
              event.logicalKey != LogicalKeyboardKey.escape) {
            return KeyEventResult.ignored;
          }
          state.closeProfileOverlay();
          return KeyEventResult.handled;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            ModalBarrier(
              key: const Key('profile_overlay_backdrop'),
              dismissible: true,
              semanticsLabel: 'Fechar perfil e voltar',
              onDismiss: state.closeProfileOverlay,
            ),
            SafeArea(
              minimum: EdgeInsets.symmetric(
                  horizontal: mobile ? 12 : 32, vertical: 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: 920, maxHeight: settings ? 680 : 850),
                  child: NixGlass(
                    child: settings
                        ? preferences
                        : Stack(
                            fit: StackFit.passthrough,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 40),
                                child: PagerProfile(),
                              ),
                              PositionedDirectional(
                                top: 2,
                                end: 3,
                                child: IconButton(
                                  key: const Key('close_pager_overlay'),
                                  tooltip: 'Fechar Pager',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: state.closeProfileOverlay,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
