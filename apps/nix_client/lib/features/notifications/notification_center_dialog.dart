import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/nix_notification.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

class NotificationCenterDialog extends StatelessWidget {
  const NotificationCenterDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const NotificationCenterDialog(),
    );
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    return 'há ${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final notifications = state.notifications;
    final unreadCount = state.unreadNotificationCount;

    return Dialog(
      backgroundColor: NixColors.surfaceElevatedHigh,
      shape: RoundedRectangleBorder(borderRadius: NixTokens.borderLg),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabeçalho da Central de Notificações
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Central de Notificações',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          unreadCount > 0
                              ? '$unreadCount não lida${unreadCount > 1 ? 's' : ''}'
                              : 'Todas as notificações lidas',
                          style: TextStyle(
                            fontSize: 12,
                            color: NixColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (notifications.isNotEmpty) ...[
                    if (unreadCount > 0)
                      TextButton(
                        onPressed: state.markAllNotificationsAsRead,
                        child: const Text('Ler todas', style: TextStyle(fontSize: 12)),
                      ),
                    IconButton(
                      tooltip: 'Limpar notificações',
                      icon: const Icon(Icons.delete_sweep_outlined, size: 19),
                      onPressed: state.clearNotifications,
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Lista de Notificações
            Expanded(
              child: notifications.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_off_outlined,
                                size: 40, color: NixColors.textMuted),
                            const SizedBox(height: 12),
                            Text(
                              'Nenhuma notificação recente.',
                              style: TextStyle(color: NixColors.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Eventos privados e avisos locais aparecerão aqui.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: NixColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = notifications[index];
                        return InkWell(
                          onTap: () {
                            state.markNotificationAsRead(item.id);
                            if (item.targetArea != null || item.targetId != null) {
                              Navigator.pop(context);
                              state.openNotificationTarget(item);
                            }
                          },
                          child: Container(
                            color: item.isRead
                                ? Colors.transparent
                                : NixColors.accentCyan.withValues(alpha: 0.08),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 17,
                                  backgroundColor: item.isRead
                                      ? NixColors.surfaceCard
                                      : NixColors.accentCyan.withValues(alpha: 0.2),
                                  child: Icon(
                                    item.type.icon,
                                    size: 17,
                                    color: item.isRead
                                        ? NixColors.textSecondary
                                        : NixColors.accentCyan,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: NixColors.surfaceCard,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              item.type.label,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: NixColors.textMuted,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            _formatRelativeTime(item.timestamp),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: NixColors.textMuted,
                                            ),
                                          ),
                                          if (!item.isRead) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: NixColors.accentCyan,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.title,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: item.isRead
                                              ? FontWeight.w500
                                              : FontWeight.bold,
                                          color: NixColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.body,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: NixColors.textSecondary,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
