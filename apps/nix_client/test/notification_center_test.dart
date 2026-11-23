import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/nix_notification.dart';
import 'package:nix_client/features/notifications/notification_center_dialog.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Notification Center manages state and opens dialog cleanly',
      (tester) async {
    final state = NixState(loadMockData: true);

    expect(state.notifications, isNotEmpty);
    expect(state.unreadNotificationCount, greaterThan(0));

    await tester.pumpWidget(
      ChangeNotifierProvider<NixState>.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(
            body: NotificationCenterDialog(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Central de Notificações'), findsOneWidget);
    expect(find.text('Nova mensagem privada'), findsOneWidget);

    // Test mark all as read
    state.markAllNotificationsAsRead();
    await tester.pumpAndSettle();
    expect(state.unreadNotificationCount, 0);

    // Test adding a notification
    state.addNotification(
      NixNotification(
        id: 'test_notif',
        type: NixNotificationType.message,
        title: 'Alerta Teste',
        body: 'Conteúdo do teste local',
        timestamp: DateTime.now(),
        isRead: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alerta Teste'), findsOneWidget);

    // Test clear notifications
    state.clearNotifications();
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma notificação recente.'), findsOneWidget);
  });
}
