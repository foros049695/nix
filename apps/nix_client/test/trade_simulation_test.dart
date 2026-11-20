import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/features/monero_p2p/trade_simulation_dialog.dart';

void main() {
  testWidgets('Gera IDs independentes e encerra a disputa simulada',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TradeSimulationDialog())),
    );

    await tester.tap(find.text('Criar ordem fictícia'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNWidgets(2));

    await tester.tap(find.text('Simular aceite'));
    await tester.pumpAndSettle();
    final identities = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((label) => label.data!.split(': ').last)
        .toSet();
    expect(identities, hasLength(3));
    expect(identities.every(RegExp(r'^[0-9a-f]{32}$').hasMatch), isTrue);

    await tester.tap(find.text('Abrir disputa'));
    await tester.pumpAndSettle();
    expect(find.text('Dossiê da ordem para o árbitro'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Encerrar exercício.');
    await tester.ensureVisible(find.text('Registrar decisão'));
    await tester.tap(find.text('Registrar decisão'));
    await tester.pumpAndSettle();
    expect(find.text('Decisão simulada: Encerrar exercício.'), findsOneWidget);
    expect(find.text('Informar pagamento'), findsNothing);
  });
}
