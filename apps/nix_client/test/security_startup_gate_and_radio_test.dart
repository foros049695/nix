import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/media/media_catalog_service.dart';
import 'package:nix_client/core/security/fail_closed_http_overrides.dart';
import 'package:nix_client/core/security/sovereign_security_gate.dart';
import 'package:nix_client/features/discovery/github_discovery_view.dart';
import 'package:nix_client/features/navigation/app_shell.dart';
import 'package:nix_client/features/onboarding/sovereign_onboarding_flow.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_transport/nix_transport.dart';
import 'package:provider/provider.dart';

void main() {
  group('Gate Fail-Closed de Inicialização, Firewall Clearnet e Rádio Off-Grid', () {
    test('NixFailClosedHttpOverrides bloqueia conexões HTTP/HTTPS na rede doméstica', () async {
      await HttpOverrides.runWithHttpOverrides(
        () async {
          expect(NixFailClosedHttpOverrides.isInstalled, isTrue);
          final client = HttpClient();
          try {
            await expectLater(
              () => client.getUrl(Uri.parse('https://example.com/leak-test')),
              throwsA(isA<TransportBlockedException>()),
            );
            await expectLater(
              () => client.getUrl(Uri.parse('http://1.1.1.1/dns-query')),
              throwsA(isA<TransportBlockedException>()),
            );
          } finally {
            client.close(force: true);
          }
        },
        NixFailClosedHttpOverrides(),
      );
    });

    test('NixFailClosedHttpOverrides permite exclusivamente loopback local', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((req) {
        req.response
          ..statusCode = HttpStatus.ok
          ..write('loopback-ok');
        req.response.close();
      });

      await HttpOverrides.runWithHttpOverrides(
        () async {
          final client = HttpClient();
          try {
            final req = await client.getUrl(
              Uri.parse('http://127.0.0.1:${server.port}/health'),
            );
            final res = await req.close();
            expect(res.statusCode, HttpStatus.ok);
          } finally {
            client.close(force: true);
          }
        },
        NixFailClosedHttpOverrides(),
      );
    });

    test('SovereignSecurityGateStatus exige TODOS os parâmetros Tor Onion v3 e criptografia', () {
      const incompleteTor = SovereignSecurityGateStatus(
        clearnetFirewallActive: true,
        torSocksActive: true,
        torBootstrapped100: true,
        torOnionV3Ready: false, // Sem Onion v3
        failClosedPolicyVerified: true,
        sqlCipherEncrypted: true,
        keyVaultUnlocked: true,
        identityKeysLoaded: true,
      );
      expect(incompleteTor.isTorAnonymityReady, isFalse);
      expect(incompleteTor.canEnterApplication, isFalse);

      const incompleteCrypto = SovereignSecurityGateStatus(
        clearnetFirewallActive: true,
        torSocksActive: true,
        torBootstrapped100: true,
        torOnionV3Ready: true,
        failClosedPolicyVerified: true,
        sqlCipherEncrypted: false, // Sem SQLCipher
        keyVaultUnlocked: true,
        identityKeysLoaded: true,
      );
      expect(incompleteCrypto.isTorAnonymityReady, isTrue);
      expect(incompleteCrypto.isCryptographyReady, isFalse);
      expect(incompleteCrypto.canEnterApplication, isFalse);

      const fullReady = SovereignSecurityGateStatus(
        clearnetFirewallActive: true,
        torSocksActive: true,
        torBootstrapped100: true,
        torOnionV3Ready: true,
        failClosedPolicyVerified: true,
        sqlCipherEncrypted: true,
        keyVaultUnlocked: true,
        identityKeysLoaded: true,
      );
      expect(fullReady.isTorAnonymityReady, isTrue);
      expect(fullReady.isCryptographyReady, isTrue);
      expect(fullReady.canEnterApplication, isTrue);
      expect(fullReady.missingRequirements, isEmpty);
    });

    testWidgets('AppShell em modo produção bloqueia entrada sem Tor Onion v3 ativo',
        (WidgetTester tester) async {
      final state = NixState(loadMockData: false, enforceStartupGate: true);
      addTearDown(state.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<NixState>.value(
          value: state,
          child: const MaterialApp(
            home: AppShell(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('sovereign_security_gate_view')), findsOneWidget);
      expect(find.textContaining('TOR ONION V3 OBRIGATÓRIO'), findsOneWidget);
      // Garante ausência de botão para pular proteção
      expect(find.textContaining('Pular'), findsNothing);
      expect(find.textContaining('Ignorar'), findsNothing);
    });

    test('KissFrameCodec + RadioPacketCodec preservam bytes reservados (0xC0/0xDB) com CRC16', () {
      final rawPayload = Uint8List.fromList([0xC0, 0xDB, 0xDC, 0xDD, 0x4E, 0x49, 0x58]);
      final radioFrame = RadioPacketCodec.encodeShortFrame(
        sequenceNo: 42,
        payloadBytes: rawPayload,
      );
      final kissBytes = KissFrameCodec.encodeFrame(radioFrame);
      expect(kissBytes.first, KissFrameCodec.fend);
      expect(kissBytes.last, KissFrameCodec.fend);

      final decodedKiss = KissFrameCodec.decodeAll(kissBytes);
      expect(decodedKiss.length, 1);
      expect(decodedKiss.first.command, KissFrameCodec.cmdData);

      final decodedRadio = RadioPacketCodec.decodeFrame(decodedKiss.first.payload);
      expect(decodedRadio.sequenceNo, 42);
      expect(decodedRadio.payload, orderedEquals(rawPayload));

      final detectResp = Uint8List.fromList([
        KissFrameCodec.fend,
        KissFrameCodec.cmdDetect,
        KissFrameCodec.detectResp,
        KissFrameCodec.fend,
      ]);
      expect(KissFrameCodec.isDetectResponse(detectResp), isTrue);
    });

    test('BluetoothMeshManager transmite e recebe pacote NIXB via hook de hardware nativo', () async {
      final receivedOnPeerB = <Map<String, dynamic>>[];
      final peerA = BluetoothMeshManager(localCardId: 'NIX-PHONE-A');
      final peerB = BluetoothMeshManager(localCardId: 'NIX-PHONE-B');
      addTearDown(() {
        peerA.dispose();
        peerB.dispose();
      });

      peerA.setMeshEnabled(true);
      peerB.setMeshEnabled(true);
      peerB.onEnvelopeReceived.listen(receivedOnPeerB.add);

      // Liga o transmissor de hardware simulado entre Telefone A -> Telefone B
      peerA.onTransmitPacket = (destAddr, encodedNixb) async {
        expect(destAddr, 'AA:BB:CC:DD:EE:02');
        peerB.handleIncomingPacket('AA:BB:CC:DD:EE:01', encodedNixb);
        return true;
      };

      peerA.registerDiscoveredPeer(
        deviceAddress: 'AA:BB:CC:DD:EE:02',
        peerCardId: 'NIX-PHONE-B',
        rssi: -58,
      );

      final payload = Uint8List.fromList('envelope-cifrado-ble'.codeUnits);
      final count = await peerA.broadcastEnvelope(
        recipientCardId: 'NIX-PHONE-B',
        payload: payload,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(count, 1);
      expect(peerA.txPacketsSent, 1);
      expect(peerB.rxPacketsReceived, 1);
      expect(receivedOnPeerB.length, 1);
      expect(receivedOnPeerB.first['ciphertext'], orderedEquals(payload));
    });

    test('Modo Off-Grid Estrito exige firewall clearnet + toda criptografia e bloqueia rede/Wi-Fi', () async {
      const offGridNoCrypto = SovereignSecurityGateStatus(
        clearnetFirewallActive: true,
        failClosedPolicyVerified: true,
        isStrictOffGridMode: true,
        sqlCipherEncrypted: false,
        keyVaultUnlocked: true,
        identityKeysLoaded: true,
      );
      expect(offGridNoCrypto.isOffGridBoundaryReady, isTrue);
      expect(offGridNoCrypto.isTransportGateSatisfied, isTrue);
      expect(offGridNoCrypto.canEnterApplication, isFalse);

      const offGridFullCrypto = SovereignSecurityGateStatus(
        clearnetFirewallActive: true,
        failClosedPolicyVerified: true,
        isStrictOffGridMode: true,
        sqlCipherEncrypted: true,
        keyVaultUnlocked: true,
        identityKeysLoaded: true,
      );
      expect(offGridFullCrypto.isTransportGateSatisfied, isTrue);
      expect(offGridFullCrypto.canEnterApplication, isTrue);
      expect(offGridFullCrypto.missingRequirements, isEmpty);

      final state = NixState(loadMockData: false, enforceStartupGate: true);
      addTearDown(state.dispose);

      await HttpOverrides.runWithHttpOverrides(
        () async {
          final gate = await state.enterStrictOffGridMode();
          expect(state.isStrictOffGridMode, isTrue);
          expect(gate.isOffGridBoundaryReady, isTrue);

          // Relay, Starwire e conectores opt-in ficam bloqueados em Off-Grid Estrito
          final syncRes = await state.syncWithRelay();
          expect(syncRes.acceptedOutbox, 0);
          expect(state.lastMessagingError, contains('Modo Off-Grid Estrito'));

          expect(
            () => enforceStarwireDownloadTransport(
              strictTorMode: false,
              isStrictOffGridMode: true,
            ),
            throwsA(isA<TransportBlockedException>()),
          );

          await expectLater(
            () => state.queryOptInMediaConnector(
              connector: OptInMediaConnectorKind.tmdb,
              query: 'matrix',
            ),
            throwsA(isA<TransportBlockedException>()),
          );
        },
        NixFailClosedHttpOverrides(),
      );
    });

    testWidgets('Escudo Fail-Closed permite entrar em Modo Off-Grid Estrito (BLE/LoRa) sem Wi-Fi',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = NixState(loadMockData: false, enforceStartupGate: true);
      addTearDown(state.dispose);

      await HttpOverrides.runWithHttpOverrides(
        () async {
          await tester.pumpWidget(
            ChangeNotifierProvider<NixState>.value(
              value: state,
              child: const MaterialApp(
                home: AppShell(),
              ),
            ),
          );
          await tester.pump();

          expect(find.byKey(const Key('sovereign_security_gate_view')), findsOneWidget);
          final offGridBtn = find.byKey(const Key('enter_strict_offgrid_button'));
          expect(offGridBtn, findsOneWidget);

          await tester.ensureVisible(offGridBtn);
          await tester.tap(offGridBtn);
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 80)));
          await tester.pumpAndSettle();

          // Sem conta configurada ainda -> entra no Onboarding Offline (sem acesso à rede IP)
          expect(state.isStrictOffGridMode, isTrue);
          expect(find.byType(SovereignOnboardingFlow), findsOneWidget);
          expect(find.textContaining('MODO OFF-GRID ESTRITO (BLE / LORA)'), findsOneWidget);
        },
        NixFailClosedHttpOverrides(),
      );
    });
  });
}
