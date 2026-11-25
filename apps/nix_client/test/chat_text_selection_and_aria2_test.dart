import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nix_client/core/downloads/aria2_download_controller.dart';
import 'package:nix_client/core/models/message.dart';
import 'package:nix_client/features/chat/message_bubble.dart';
import 'package:nix_client/state/nix_state.dart';

void main() {
  group('Chat Text Selection (Telegram-style)', () {
    testWidgets('MessageBubble renders SelectionArea with text cursor and selectable text', (tester) async {
      final nixState = NixState();
      final message = Message(
        id: 'msg_sel_1',
        channelId: 'general',
        senderName: 'Soberano',
        senderFingerprint: 'F123456789',
        isMe: true,
        text: 'KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK',
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<NixState>.value(
          value: nixState,
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message),
            ),
          ),
        ),
      );

      // Verify SelectionArea exists
      expect(find.byType(SelectionArea), findsOneWidget);
      // Verify MouseRegion with text cursor exists
      final mouseRegionFinder = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.text,
      );
      expect(mouseRegionFinder, findsAtLeastNWidgets(1));
      // Verify message text is rendered
      expect(find.text('KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK'), findsOneWidget);
    });

    testWidgets('Secondary tap on selectable message text triggers context menu', (tester) async {
      final nixState = NixState();
      final message = Message(
        id: 'msg_sel_2',
        channelId: 'general',
        senderName: 'Soberano',
        senderFingerprint: 'F123456789',
        isMe: false,
        text: 'Mensagem de teste para selecao contextual',
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<NixState>.value(
          value: nixState,
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mensagem de teste para selecao contextual'), buttons: kSecondaryMouseButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Reagir com emoji'), findsOneWidget);
      expect(find.text('Responder'), findsOneWidget);
      expect(find.text('Copiar Texto'), findsOneWidget);
    });
  });

  group('Aria2 Performance Profiles and Daemon Launch', () {
    setUp(() {
      HttpOverrides.global = null;
    });

    test('all performance profiles have minSplitSize >= 1M for aria2 compliance', () {
      for (final profile in DownloadPerformanceProfile.values) {
        expect(profile.minSplitSize, matches(r'^[1-9]\d*M$'),
            reason: 'Profile ${profile.slug} must have minSplitSize >= 1M to satisfy aria2 OptionHandler');
      }
    });

    test('Aria2DownloadController startDaemon succeeds when binary is available', () async {
      final controller = Aria2DownloadController(enableFallback: false);
      final started = await controller.startDaemon();
      expect(started, isTrue);
      expect(controller.isDaemonRunning, isTrue);
      expect(controller.actualRpcPort, greaterThan(0));
      await controller.stopDaemon();
      expect(controller.isDaemonRunning, isFalse);
    });
  });
}
