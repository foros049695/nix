import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/models/channel.dart';
import '../../core/models/member.dart';
import '../../state/nix_state.dart';

class CallRoomView extends StatelessWidget {
  final Channel channel;

  const CallRoomView({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final call = nixState.callState;
    final isCurrentCallActive = call.isConnected && call.activeChannelId == channel.id;

    final minutes = (call.durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (call.durationSeconds % 60).toString().padLeft(2, '0');

    return Column(
      children: [
        // Cabeçalho da Sala de Call
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: NixColors.surfaceSidebar,
            border: Border(bottom: BorderSide(color: NixColors.surfaceBorder, width: 1)),
          ),
          child: Row(
            children: [
              Icon(Icons.volume_up_rounded, color: NixColors.accentVoice, size: 20),
              const SizedBox(width: 8),
              Text(
                channel.name,
                style: TextStyle(
                  color: NixColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: NixColors.accentTor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: NixColors.accentTor.withOpacity(0.3)),
                ),
                child: Text(
                  'TOR ONION E2EE · ZERO IP LEAK',
                  style: TextStyle(color: NixColors.accentTor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              if (isCurrentCallActive)
                Text(
                  'Duração: $minutes:$seconds',
                  style: TextStyle(color: NixColors.textSecondary, fontSize: 12, fontFamily: 'monospace'),
                ),
            ],
          ),
        ),

        // Área Central: Grid de Participantes
        Expanded(
          child: Container(
            color: NixColors.background,
            padding: const EdgeInsets.all(24),
            child: isCurrentCallActive
                ? _buildActiveCallGrid(call.participants, call.isMuted)
                : _buildJoinCallPrompt(context, nixState),
          ),
        ),

        // Barra de Controles da Call (se conectado)
        if (isCurrentCallActive)
          _buildControlBar(context, nixState),
      ],
    );
  }

  Widget _buildActiveCallGrid(List<Member> participants, bool isMeMuted) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 700 ? 3 : 2;

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.3,
          ),
          itemCount: participants.length,
          itemBuilder: (context, index) {
            final member = participants[index];
            final isSpeaking = member.isSpeaking;

            return Container(
              decoration: BoxDecoration(
                color: NixColors.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSpeaking ? NixColors.accentGreen : NixColors.surfaceBorder,
                  width: isSpeaking ? 2 : 1,
                ),
                boxShadow: isSpeaking
                    ? [
                        BoxShadow(
                          color: NixColors.accentGreen.withOpacity(0.2),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ]
                    : [],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: NixColors.surfaceCardHover,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSpeaking ? NixColors.accentGreen : NixColors.surfaceBorder,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.person,
                            size: 36,
                            color: isSpeaking ? NixColors.accentGreen : NixColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        member.name,
                        style: TextStyle(
                          color: NixColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        member.roleName,
                        style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        member.name.contains('Você') && isMeMuted ? Icons.mic_off : (isSpeaking ? Icons.graphic_eq : Icons.mic),
                        size: 14,
                        color: member.name.contains('Você') && isMeMuted ? NixColors.accentDanger : (isSpeaking ? NixColors.accentGreen : NixColors.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildJoinCallPrompt(BuildContext context, NixState nixState) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: NixColors.surfaceCard,
              shape: BoxShape.circle,
              border: Border.all(color: NixColors.accentVoice.withOpacity(0.4), width: 2),
            ),
            child: Icon(Icons.volume_up_rounded, color: NixColors.accentVoice, size: 64),
          ),
          const SizedBox(height: 20),
          Text(
            'Sala de Voz: ${channel.name}',
            style: TextStyle(color: NixColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Comunicação por áudio cifrada de ponta a ponta.\nNenhum dado é gravado no relay.',
            textAlign: TextAlign.center,
            style: TextStyle(color: NixColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: NixColors.accentVoice,
              foregroundColor: NixColors.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => nixState.joinCall(channel),
            icon: const Icon(Icons.call, size: 20),
            label: const Text('Entrar na Sala de Call', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar(BuildContext context, NixState nixState) {
    final call = nixState.callState;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
        color: NixColors.surfaceSidebar,
        border: Border(top: BorderSide(color: NixColors.surfaceBorder, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mutar
          _ControlIconButton(
            icon: call.isMuted ? Icons.mic_off : Icons.mic,
            label: call.isMuted ? 'Mutado' : 'Microfone',
            isActive: !call.isMuted,
            color: call.isMuted ? NixColors.accentDanger : NixColors.textPrimary,
            onTap: () => nixState.toggleMute(),
          ),
          const SizedBox(width: 16),
          // Ensordecer
          _ControlIconButton(
            icon: call.isDeafened ? Icons.headset_off : Icons.headset,
            label: call.isDeafened ? 'Surdo' : 'Áudio',
            isActive: !call.isDeafened,
            color: call.isDeafened ? NixColors.accentDanger : NixColors.textPrimary,
            onTap: () => nixState.toggleDeafen(),
          ),
          const SizedBox(width: 24),
          // Desconectar
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: NixColors.accentDanger,
              foregroundColor: NixColors.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => nixState.leaveCall(),
            icon: const Icon(Icons.call_end, size: 18),
            label: const Text('Desconectar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _ControlIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;

  const _ControlIconButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: NixColors.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: NixColors.surfaceBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
