import 'package:flutter/material.dart';
import '../../state/nix_state.dart';
import '../onboarding/sovereign_onboarding_flow.dart';

/// Ponto de entrada do assistente de onboarding soberano nos menus e diálogos.
/// Conecta diretamente à máquina de estados explícita de 9 etapas (Seção 2).
class SovereignOnboardingDialog extends StatelessWidget {
  final NixState nixState;
  final VoidCallback onComplete;
  final VoidCallback? onDismiss;

  const SovereignOnboardingDialog({
    super.key,
    required this.nixState,
    required this.onComplete,
    this.onDismiss,
  });

  static Future<void> show(
    BuildContext context,
    NixState state, {
    VoidCallback? onComplete,
    VoidCallback? onDismiss,
  }) {
    return SovereignOnboardingFlow.showAsDialog(
      context,
      state,
      onComplete: onComplete,
      onDismiss: onDismiss,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SovereignOnboardingFlow(
      nixState: nixState,
      onComplete: onComplete,
      onDismiss: onDismiss,
    );
  }
}
