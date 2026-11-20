import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_palette.dart';
import '../../core/models/channel.dart';
import '../../core/models/member.dart';
import '../../core/models/message.dart';
import '../../state/nix_state.dart';
import '../design/nix_surfaces.dart';
import '../chat/chat_input_bar.dart';
import '../chat/message_timeline.dart';

class CallRoomView extends StatefulWidget {
  final Channel channel;

  const CallRoomView({super.key, required this.channel});

  @override
  State<CallRoomView> createState() => _CallRoomViewState();
}

class _CallRoomViewState extends State<CallRoomView> {
  bool _showTextChat = false;
  NixState? _state;
  String? _lastMessageId;
  Message? _toast;
  Timer? _toastTimer;
  Channel get channel => widget.channel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<NixState>();
    if (identical(_state, state)) return;
    _state?.removeListener(_observeMessages);
    _state = state;
    _lastMessageId = state.messagesForChannel(channel.id).lastOrNull?.id;
    state.addListener(_observeMessages);
  }

  @override
  void didUpdateWidget(CallRoomView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != channel.id) {
      _toastTimer?.cancel();
      _toast = null;
      _showTextChat = false;
      _lastMessageId = _state?.messagesForChannel(channel.id).lastOrNull?.id;
    }
  }

  @override
  void dispose() {
    _state?.removeListener(_observeMessages);
    _toastTimer?.cancel();
    super.dispose();
  }

  void _observeMessages() {
    final state = _state!;
    final last = state.messagesForChannel(channel.id).lastOrNull;
    if (last?.id == _lastMessageId) return;
    _lastMessageId = last?.id;
    if (last == null || _showTextChat || !state.callState.isConnected ||
        state.callState.activeChannelId != channel.id || !state.settings.messageNotifications) return;
    _toastTimer?.cancel();
    setState(() => _toast = last);
    _toastTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _toggleChat() {
    _toastTimer?.cancel();
    setState(() {
      _toast = null;
      _showTextChat = !_showTextChat;
    });
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.read<NixState>();

    return LayoutBuilder(builder: (context, constraints) {
      final split = constraints.maxWidth >= 760;
      final callView = ListenableBuilder(
        listenable: nixState.calls,
        builder: (context, _) {
          final call = nixState.calls.callState;
          final isCurrentCallActive =
              call.isConnected && call.activeChannelId == channel.id;

          final minutes =
              (call.durationSeconds ~/ 60).toString().padLeft(2, '0');
          final seconds =
              (call.durationSeconds % 60).toString().padLeft(2, '0');

          return Column(
            children: [
              // Cabeçalho da Sala de Call
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: NixColors.surfaceSidebar,
                  border: Border(
                      bottom:
                          BorderSide(color: NixColors.surfaceBorder, width: 1)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.volume_up_rounded,
                        color: NixColors.accentVoice, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        channel.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: NixColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (split)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: NixColors.accentTor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: NixColors.accentTor.withOpacity(0.3)),
                        ),
                        child: Text(
                          'SALA LOCAL',
                          style: TextStyle(
                              color: NixColors.accentTor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    if (isCurrentCallActive && split)
                      Text(
                        'Duração: $minutes:$seconds',
                        style: TextStyle(
                            color: NixColors.textSecondary,
                            fontSize: 12,
                            fontFamily: 'monospace'),
                      ),
                    IconButton(
                      tooltip: _showTextChat
                          ? 'Fechar chat da sala'
                          : 'Abrir chat da sala',
                      onPressed: _toggleChat,
                      icon: const Icon(Icons.chat_outlined),
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
                      ? Stack(fit: StackFit.expand, children: [
                          _buildActiveCallGrid(call.participants, call.isMuted),
                          if (_toast case final toast?)
                            Align(alignment: Alignment.topCenter, child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 430),
                              child: Material(
                                color: NixColors.surfaceElevatedHigh,
                                borderRadius: BorderRadius.circular(12), elevation: 4,
                                child: Semantics(liveRegion: true, child: ListTile(
                                  key: const Key('call_chat_popup'), leading: const Icon(Icons.chat_outlined),
                                  title: Text(toast.senderName, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(toast.text.isEmpty ? 'Enviou um anexo' : toast.text,
                                    maxLines: 2, overflow: TextOverflow.ellipsis),
                                  onTap: _toggleChat,
                                  trailing: IconButton(tooltip: 'Dispensar mensagem', icon: const Icon(Icons.close),
                                    onPressed: () => setState(() => _toast = null)),
                                )),
                              ),
                            )),
                        ])
                      : _buildJoinCallPrompt(context, nixState),
                ),
              ),

              // Barra de Controles da Call (se conectado)
              if (isCurrentCallActive) _buildControlBar(context, nixState),
            ],
          );
        },
      );
      if (!_showTextChat) return callView;
      final messages = context.watch<NixState>().messagesForChannel(channel.id);
      final chat = Column(children: [
        ListTile(
          title: Text('Chat da sala · ${channel.name}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: const Text('Mensagens locais desta sala'),
          trailing: IconButton(
            tooltip: 'Fechar chat da sala',
            icon: const Icon(Icons.close),
            onPressed: _toggleChat,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: MessageTimeline(key: ValueKey(channel.id), messages: messages),
        ),
        ChatInputBar(
          channelName: channel.name,
          onSendCustom: (text, attachments) {
            if (nixState.currentChannel.id == channel.id) {
              nixState.sendMessage(text, attachments: attachments);
            }
          },
        ),
      ]);
      if (!split) return chat;
      return Row(children: [
        Expanded(child: callView),
        VerticalDivider(width: 1, color: NixColors.surfaceBorder),
        SizedBox(width: 340, child: chat),
      ]);
    });
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
                  color: isSpeaking
                      ? NixColors.accentGreen
                      : NixColors.surfaceBorder,
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
                            color: isSpeaking
                                ? NixColors.accentGreen
                                : NixColors.surfaceBorder,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.person,
                            size: 36,
                            color: isSpeaking
                                ? NixColors.accentGreen
                                : NixColors.textSecondary,
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
                        style:
                            TextStyle(color: NixColors.textMuted, fontSize: 11),
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
                        member.name.contains('Você') && isMeMuted
                            ? Icons.mic_off
                            : (isSpeaking ? Icons.graphic_eq : Icons.mic),
                        size: 14,
                        color: member.name.contains('Você') && isMeMuted
                            ? NixColors.accentDanger
                            : (isSpeaking
                                ? NixColors.accentGreen
                                : NixColors.textMuted),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: NixFrame(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NixMotionCard(child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: nixFrameDecoration(context, background: context.surfaceActiveColor),
                  child: Icon(Icons.graphic_eq_rounded, color: context.accentTextColor, size: 38),
                )),
          const SizedBox(height: 20),
          Text(
            'Sala de Voz: ${channel.name}',
            style: TextStyle(
                color: NixColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Prévia local da sala de voz e do chat.',
            textAlign: TextAlign.center,
            style: TextStyle(color: NixColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: NixColors.accentVoice,
              foregroundColor: NixPalette.foregroundOn(NixColors.accentVoice),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => nixState.joinCall(channel),
            icon: const Icon(Icons.call, size: 20),
            label: const Text('Entrar na Sala de Call',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlBar(BuildContext context, NixState nixState) {
    final call = nixState.callState;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
        color: NixColors.surfaceSidebar,
        border:
            Border(top: BorderSide(color: NixColors.surfaceBorder, width: 1)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          // Mutar
          _ControlIconButton(
            icon: call.isMuted ? Icons.mic_off : Icons.mic,
            label: call.isMuted ? 'Mutado' : 'Microfone',
            isActive: !call.isMuted,
            color:
                call.isMuted ? NixColors.accentDanger : NixColors.textPrimary,
            onTap: () => nixState.toggleMute(),
          ),
          // Ensordecer
          _ControlIconButton(
            icon: call.isDeafened ? Icons.headset_off : Icons.headset,
            label: call.isDeafened ? 'Surdo' : 'Áudio',
            isActive: !call.isDeafened,
            color: call.isDeafened
                ? NixColors.accentDanger
                : NixColors.textPrimary,
            onTap: () => nixState.toggleDeafen(),
          ),
          // Desconectar
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: NixColors.accentDanger,
              foregroundColor: NixPalette.foregroundOn(NixColors.accentDanger),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => nixState.leaveCall(),
            icon: const Icon(Icons.call_end, size: 18),
            label: const Text('Desconectar',
                style: TextStyle(fontWeight: FontWeight.bold)),
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
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
