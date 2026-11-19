import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:nix_transport/nix_transport.dart';

void main() {
  group('Bluetooth Mesh Proximity Transport (Briar-inspired BTP)', () {
    test('serializa e decodifica pacotes com cabeçalho mágico NIXB e framing seguro', () {
      final payload = utf8.encode('NIX_PROXIMITY_MESH_TEST_DATA');
      final packet = BluetoothMeshPacket(
        type: BluetoothPacketType.envelopeTransfer,
        payload: Uint8List.fromList(payload),
      );

      final encoded = packet.encode();
      expect(encoded.length, equals(7 + payload.length));
      expect(encoded.sublist(0, 4), equals(kNixBluetoothMagic));
      expect(encoded[4], equals(BluetoothPacketType.envelopeTransfer.code));

      final decoded = BluetoothMeshPacket.decode(encoded);
      expect(decoded.type, equals(BluetoothPacketType.envelopeTransfer));
      expect(decoded.payload, equals(payload));
    });

    test('rejeita pacotes adulterados ou com magic byte incorreto', () {
      final invalidMagic = Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x01, 0x00, 0x00]);
      expect(
        () => BluetoothMeshPacket.decode(invalidMagic),
        throwsA(isA<FormatException>()),
      );
    });

    test('executa fluxo de handshake e transferência de envelope cifrado entre dois nós próximos', () {
      final peerAlice = BluetoothProximityPeer(
        deviceAddress: 'AA:BB:CC:DD:EE:01',
        peerPublicCardId: 'NX-ALICE-1234',
        rssiSignalStrength: -62, // Sinal forte (próximo)
      );

      final peerBob = BluetoothProximityPeer(
        deviceAddress: 'AA:BB:CC:DD:EE:02',
        peerPublicCardId: 'NX-BOB-5678',
        rssiSignalStrength: -65,
      );

      expect(peerAlice.isNearby, isTrue);

      final sessionAlice = BluetoothMeshSession(
        localIdentityCardId: 'NX-ALICE-1234',
        remotePeer: peerBob,
      );

      // 1. Alice cria handshakeInit
      final ephemeralAlice = Uint8List.fromList(List.generate(32, (i) => i));
      final initPacket = sessionAlice.createHandshakeInit(ephemeralPublic: ephemeralAlice);
      expect(initPacket.type, equals(BluetoothPacketType.handshakeInit));

      // 2. Bob responde com handshakeAck
      final ackPacket = BluetoothMeshPacket(
        type: BluetoothPacketType.handshakeAck,
        payload: Uint8List(0),
      );
      sessionAlice.processHandshakeAck(ackPacket);
      expect(sessionAlice.isAuthenticated, isTrue);
      expect(peerBob.status, equals(BluetoothPeerStatus.authenticated));

      // 3. Alice transfere envelope cifrado diretamente via Bluetooth sem internet/Tor
      final secretCiphertext = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);
      final transferPacket = sessionAlice.createEnvelopeTransfer(
        deliveryId: 'deliv_bt_99',
        destinationMailbox: 'mbx_bob_hex_mailbox_destination_address_64',
        ciphertext: secretCiphertext,
        expiresAt: 1735000000000,
      );

      // 4. Bob decodifica e valida o envelope
      final receivedData = sessionAlice.parseReceivedEnvelope(transferPacket);
      expect(receivedData['deliveryId'], equals('deliv_bt_99'));
      expect(receivedData['destinationMailbox'], equals('mbx_bob_hex_mailbox_destination_address_64'));
      expect(receivedData['ciphertext'], equals(secretCiphertext));
      expect((receivedData['payloadHash'] as Uint8List).length, equals(32));
    });

    test('BluetoothMeshManager gerencia nós vizinhos e despacha eventos', () async {
      final manager = BluetoothMeshManager(localCardId: 'NX-LOCAL-001');
      expect(manager.isMeshEnabled, isFalse);

      manager.setMeshEnabled(true);
      expect(manager.isMeshEnabled, isTrue);

      final discoveredPeers = <BluetoothProximityPeer>[];
      final sub = manager.onPeerDiscovered.listen(discoveredPeers.add);

      manager.registerDiscoveredPeer(
        deviceAddress: 'E4:5F:01:22:33:44',
        peerCardId: 'NX-CHARLIE-999',
        rssi: -70,
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(discoveredPeers.length, equals(1));
      expect(discoveredPeers.first.peerPublicCardId, equals('NX-CHARLIE-999'));

      await sub.cancel();
      manager.dispose();
    });
  });
}
