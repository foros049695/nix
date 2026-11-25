import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/network/hybrid_network_coordinator.dart';
import 'package:nix_client/features/network/connectivity_center_dialog.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Arquitetura de Rede Híbrida (Camadas A–G) e Failover (Seções 10, 11 e 12)', () {
    test('HybridNetworkCoordinator inicializa 7 camadas com status honesto', () {
      final coordinator = HybridNetworkCoordinator();
      final layers = coordinator.activeLayers;

      expect(layers.length, equals(7));
      expect(layers.map((l) => l.code).toList(), equals(['A', 'B', 'C', 'D', 'E', 'F', 'G']));

      final layerA = coordinator.getLayer(TransportLayerId.vpsRelay);
      expect(layerA?.name, equals('Servidor Principal VPS'));
      expect(layerA?.status, equals(TransportStatus.available));

      final layerG = coordinator.getLayer(TransportLayerId.radioLoRa);
      expect(layerG?.name, equals('Rádio Off-Grid'));
      expect(layerG?.status, equals(TransportStatus.noHardware));
    });

    test('Failover: mensagem sem rota ativa permanece na fila como Aguardando conexão', () async {
      final coordinator = HybridNetworkCoordinator();

      // Desativa todas as camadas simulando queda completa de rede
      for (final l in coordinator.activeLayers) {
        coordinator.updateLayerStatus(l.id, TransportStatus.unavailable);
      }

      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final result = await coordinator.sendEnvelopeWithFailover(
        destinationId: 'dest_test_mailbox',
        payload: payload,
      );

      expect(result.delivered, isFalse);
      expect(result.layerUsed, isNull);
      expect(result.statusMessage, equals('Aguardando conexão com o destinatário.'));

      expect(coordinator.pendingQueueCount, equals(1));
      expect(coordinator.queuedEnvelopes.first.transportState, equals('waiting_route'));
    });

    testWidgets('Central de Conectividade exibe todas as 7 camadas e métricas reais', (tester) async {
      final state = NixState(loadMockData: false);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<NixState>.value(
            value: state,
            child: const Scaffold(
              body: ConnectivityCenterDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Central de Conectividade'), findsOneWidget);
      expect(find.text('Arquitetura Híbrida Resiliente (Camadas A–G)'), findsOneWidget);
      expect(find.text('Servidor Principal VPS'), findsOneWidget);
      expect(find.text('Comunicação P2P Direta'), findsOneWidget);
      expect(find.text('Relay Secundário'), findsOneWidget);
      expect(find.text('Rede Local Wi-Fi'), findsOneWidget);
      expect(find.text('Rede Cabeada Ethernet'), findsOneWidget);
      expect(find.text('Bluetooth Low Energy'), findsOneWidget);
      expect(find.text('Rádio Off-Grid'), findsOneWidget);

      // Letras indicativas A a G
      for (final letter in ['A', 'B', 'C', 'D', 'E', 'F', 'G']) {
        expect(find.text(letter), findsOneWidget);
      }
    });
  });
}
