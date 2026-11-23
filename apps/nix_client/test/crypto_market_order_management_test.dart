import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/monero_order.dart';
import 'package:nix_client/features/monero_p2p/monero_p2p_view.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Mercado Cripto manages order deletion and excludes Todos button',
      (tester) async {
    final state = NixState(loadMockData: true);

    // Create a local order
    final myOrder = await state.createAndSignMoneroOrder(
      side: MoneroP2pSide.sell,
      asset: CryptoAsset.xmr,
      fiatCurrency: 'BRL',
      pricePerXmr: 850.0,
      minFiatLimit: 100.0,
      maxFiatLimit: 1000.0,
      paymentMethod: 'PIX',
      notes: 'Anúncio de teste local',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<NixState>.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(
            body: MoneroP2pView(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify there is no 'Todos' button in asset filters
    expect(find.widgetWithText(InkWell, 'Todos'), findsNothing);

    // Verify XMR and BTC buttons exist
    expect(find.text('XMR'), findsWidgets);
    expect(find.text('BTC'), findsWidgets);

    // Verify user's local order shows "Excluir anúncio local"
    final deleteButtonFinder = find.byKey(Key('delete_order_${myOrder.id}'));
    expect(deleteButtonFinder, findsOneWidget);

    // Click delete order
    await tester.tap(deleteButtonFinder);
    await tester.pumpAndSettle();

    // Dialog appears with confirmation
    expect(find.text('Excluir anúncio local'), findsWidgets);
    expect(find.text('Confirmar exclusão'), findsOneWidget);

    // Confirm deletion
    await tester.tap(find.text('Confirmar exclusão'));
    await tester.pumpAndSettle();

    // Order is removed from state immediately
    expect(state.moneroOrders.any((o) => o.id == myOrder.id), isFalse);
    expect(find.byKey(Key('delete_order_${myOrder.id}')), findsNothing);
  });
}
