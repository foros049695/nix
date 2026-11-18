import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';

class ActiveCallBar extends StatelessWidget {
  const ActiveCallBar({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final call = nixState.callState;

    final minutes = (call.durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (call.durationSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF14241C),
        border: Border(
          top: BorderSide(color: Color(0xFF1B3D2B), width: 1),
          bottom: BorderSide(color: NixColors.surfaceBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Ícone pulsante de voz
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: NixColors.accentGreen.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: NixColors.accentGreen,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Text(
                      'Voz Conectada',
                      style: TextStyle(
                        color: NixColors.accentGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    SizedBox(width: 4),
                    Text(
                      '· Onion v3',
                      style: TextStyle(color: NixColors.textMuted, fontSize: 10),
                    ),
                  ],
                ),
                Text(
                  '${call.activeChannelName ?? "Call"} ($minutes:$seconds)',
                  style: const TextStyle(color: NixColors.textSecondary, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Botão Desconectar
          IconButton(
            icon: const Icon(Icons.call_end_rounded, color: NixColors.accentDanger, size: 18),
            tooltip: 'Desconectar da Call',
            onPressed: () => nixState.leaveCall(),
          ),
        ],
      ),
    );
  }
}
