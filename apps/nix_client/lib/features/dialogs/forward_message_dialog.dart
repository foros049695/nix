import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/message.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';

class ForwardMessageDialog extends StatefulWidget {
  final Message message;

  const ForwardMessageDialog({super.key, required this.message});

  static Future<void> show(BuildContext context, Message message) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => ForwardMessageDialog(message: message),
    );
  }

  @override
  State<ForwardMessageDialog> createState() => _ForwardMessageDialogState();
}

class _ForwardMessageDialogState extends State<ForwardMessageDialog> {
  String? _selectedTargetId;
  bool _isChannelTarget = true;
  String _targetName = '';

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final accent = context.accentColor;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 480,
          constraints: const BoxConstraints(maxHeight: 560),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Icon(Icons.forward_rounded, color: accent, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Encaminhar Mensagem',
                      style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 18, color: NixColors.textMuted),
                      tooltip: 'Fechar (Esc)',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: NixColors.surfaceBorder),

              // Prévia da Mensagem Original
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NixColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.message.senderName,
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.message.senderFingerprint.length >= 9
                              ? widget.message.senderFingerprint.substring(0, 9)
                              : widget.message.senderFingerprint,
                          style: TextStyle(
                            color: NixColors.textMuted,
                            fontSize: 9.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.message.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: NixColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(
                  'SELECIONE O DESTINO:',
                  style: TextStyle(
                    color: NixColors.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),

              // Lista de Destinos (Canais e DMs)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  children: [
                    // Seção Canais
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: Text(
                        'Canais da Comunidade',
                        style: TextStyle(color: NixColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    for (final space in nixState.spaces)
                      for (final channel in space.channels)
                        _buildTargetTile(
                          id: channel.id,
                          name: '# ${channel.name} (${space.name})',
                          icon: channel.icon,
                          isChannel: true,
                          accent: accent,
                        ),

                    const SizedBox(height: 10),
                    // Seção Mensagens Diretas
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: Text(
                        'Conversas Privadas (DM)',
                        style: TextStyle(color: NixColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                      for (final dm in nixState.directMessages)
                        _buildTargetTile(
                          id: dm.id,
                          name: dm.isSavedMessages ? '★ Mensagens Salvas (Cofre Pessoal)' : dm.peerName,
                          icon: dm.isSavedMessages ? Icons.bookmark_rounded : Icons.person_outline,
                          isChannel: false,
                          accent: accent,
                        ),
                  ],
                ),
              ),

              Divider(height: 1, color: NixColors.surfaceBorder),

              // Footer com Botão de Envio
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancelar', style: TextStyle(color: NixColors.textSecondary)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: context.onAccentColor,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _selectedTargetId == null
                          ? null
                          : () {
                              nixState.forwardMessage(
                                widget.message,
                                targetId: _selectedTargetId!,
                                isChannel: _isChannelTarget,
                              );
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: NixColors.surfaceCard,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(color: accent.withValues(alpha: 0.5)),
                                  ),
                                  content: Text(
                                    'Mensagem encaminhada para $_targetName!',
                                    style: TextStyle(color: NixColors.textPrimary),
                                  ),
                                ),
                              );
                            },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.send_rounded, size: 16),
                          SizedBox(width: 6),
                          Text('Encaminhar', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTargetTile({
    required String id,
    required String name,
    required IconData icon,
    required bool isChannel,
    required Color accent,
  }) {
    final isSelected = _selectedTargetId == id;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTargetId = id;
          _isChannelTarget = isChannel;
          _targetName = name;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? accent.withValues(alpha: 0.4) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? accent : NixColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: isSelected ? NixColors.textPrimary : NixColors.textSecondary,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, size: 16, color: accent),
          ],
        ),
      ),
    );
  }
}
