import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/archive/archive_verification_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Etapa 1.3 — Indicadores Criptográficos do Nix Archive', () {
    testWidgets('Renderiza estado VERIFIED corretamente com ícone verde', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArchiveCryptoBadge(status: ArchiveCryptoVerificationStatus.verified),
          ),
        ),
      );

      expect(find.text('VERIFIED'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.verified_rounded));
      expect(iconWidget.color, equals(Colors.greenAccent));
    });

    testWidgets('Renderiza estado INVALID_SIGNATURE com ícone de alerta vermelho', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArchiveCryptoBadge(status: ArchiveCryptoVerificationStatus.invalidSignature),
          ),
        ),
      );

      expect(find.text('INVALID_SIGNATURE'), findsOneWidget);
      expect(find.byIcon(Icons.gpp_bad_rounded), findsOneWidget);

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.gpp_bad_rounded));
      expect(iconWidget.color, equals(Colors.redAccent));
    });

    testWidgets('Renderiza estado NOT_VERIFIED com ícone neutro', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArchiveCryptoBadge(status: ArchiveCryptoVerificationStatus.notVerified),
          ),
        ),
      );

      expect(find.text('NOT_VERIFIED'), findsOneWidget);
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
    });

    testWidgets('Renderiza estado VERIFICATION_ERROR com ícone laranja', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArchiveCryptoBadge(status: ArchiveCryptoVerificationStatus.verificationError),
          ),
        ),
      );

      expect(find.text('VERIFICATION_ERROR'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.warning_amber_rounded));
      expect(iconWidget.color, equals(Colors.orangeAccent));
    });
  });
}
