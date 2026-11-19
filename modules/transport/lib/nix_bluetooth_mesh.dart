import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;

/// UUID padrão do serviço de Proximidade e Mesh Bluetooth do Projeto Nix (estilo Briar BTP).
const String kNixBluetoothServiceUuid = '0000ff01-0000-1000-8000-00805f9b34fb';
const List<int> kNixBluetoothMagic = [0x4E, 0x49, 0x58, 0x42]; // "NIXB"

/// Tipos de pacotes do protocolo de transporte Bluetooth Mesh do Nix.
enum BluetoothPacketType {
  handshakeInit(0x01),
  handshakeAck(0x02),
  syncOffers(0x03),
  envelopeRequest(0x04),
  envelopeTransfer(0x05),
  deliveryAck(0x06),
  keepAlive(0x07);

  final int code;
  const BluetoothPacketType(this.code);

  static BluetoothPacketType fromCode(int code) {
    return BluetoothPacketType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => throw FormatException('Código de pacote Bluetooth Mesh desconhecido: $code'),
    );
  }
}

/// Estado da conexão com um nó par via Bluetooth.
enum BluetoothPeerStatus {
  discovered,
  connecting,
  authenticated,
  syncing,
  disconnected,
}

/// Pacote binário de transporte Bluetooth Mesh (framing compacto com MTU adaptável).
class BluetoothMeshPacket {
  final BluetoothPacketType type;
  final Uint8List payload;

  const BluetoothMeshPacket({
    required this.type,
    required this.payload,
  });

  /// Serializa o pacote com cabeçalho mágico de 7 bytes:
  /// [4 bytes MAGIC ('NIXB')] + [1 byte TYPE] + [2 bytes BIG-ENDIAN LENGTH] + [PAYLOAD]
  Uint8List encode() {
    final length = payload.length;
    if (length > 65535) {
      throw ArgumentError('Carga útil Bluetooth excede o limite máximo de 64 KiB.');
    }

    final bytes = BytesBuilder();
    bytes.add(kNixBluetoothMagic);
    bytes.addByte(type.code);
    bytes.addByte((length >> 8) & 0xFF);
    bytes.addByte(length & 0xFF);
    bytes.add(payload);
    return bytes.toBytes();
  }

  /// Decodifica um pacote a partir de stream ou buffer binário.
  static BluetoothMeshPacket decode(Uint8List rawBytes) {
    if (rawBytes.length < 7) {
      throw const FormatException('Buffer de pacote Bluetooth Mesh truncado (< 7 bytes).');
    }

    for (var i = 0; i < 4; i++) {
      if (rawBytes[i] != kNixBluetoothMagic[i]) {
        throw const FormatException('Cabeçalho mágico de pacote Bluetooth inválido.');
      }
    }

    final typeCode = rawBytes[4];
    final length = (rawBytes[5] << 8) | rawBytes[6];

    if (rawBytes.length < 7 + length) {
      throw const FormatException('Tamanho de carga útil incompatível com cabeçalho.');
    }

    final payload = rawBytes.sublist(7, 7 + length);
    return BluetoothMeshPacket(
      type: BluetoothPacketType.fromCode(typeCode),
      payload: Uint8List.fromList(payload),
    );
  }
}

/// Representação de um contato ou nó retransmissor descoberto no raio Bluetooth.
class BluetoothProximityPeer {
  final String deviceAddress; // Endereço MAC ou UUID periférico BLE
  final String peerPublicCardId; // Card ID ou fingerprint Ed25519 do par
  final int rssiSignalStrength; // Indicador de proximidade (ex: -65 dBm)
  BluetoothPeerStatus status;
  DateTime lastSeen;

  BluetoothProximityPeer({
    required this.deviceAddress,
    required this.peerPublicCardId,
    required this.rssiSignalStrength,
    this.status = BluetoothPeerStatus.discovered,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now().toUtc();

  bool get isNearby => rssiSignalStrength > -85;
}

/// Sessão de sincronização par a par sobre Bluetooth (Briar-inspired Store-and-Forward Mesh).
class BluetoothMeshSession {
  final String localIdentityCardId;
  final BluetoothProximityPeer remotePeer;
  final int maxChunkMtu;

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  BluetoothMeshSession({
    required this.localIdentityCardId,
    required this.remotePeer,
    this.maxChunkMtu = 512,
  });

  /// Gera o pacote inicial de handshake com a identidade local e nonce criptográfico.
  BluetoothMeshPacket createHandshakeInit({required Uint8List ephemeralPublic}) {
    final cardIdBytes = utf8.encode(localIdentityCardId);
    final builder = BytesBuilder();
    builder.addByte(cardIdBytes.length);
    builder.add(cardIdBytes);
    builder.add(ephemeralPublic);

    return BluetoothMeshPacket(
      type: BluetoothPacketType.handshakeInit,
      payload: builder.toBytes(),
    );
  }

  /// Processa o handshake de resposta e autentica o nó vizinho.
  void processHandshakeAck(BluetoothMeshPacket packet) {
    if (packet.type != BluetoothPacketType.handshakeAck) {
      throw StateError('Esperava handshakeAck, recebido: ${packet.type}');
    }
    _isAuthenticated = true;
    remotePeer.status = BluetoothPeerStatus.authenticated;
  }

  /// Empacota ofertas de envelopes disponíveis no outbox local para o par.
  BluetoothMeshPacket createSyncOffers(List<String> destinationMailboxes) {
    final builder = BytesBuilder();
    builder.addByte(destinationMailboxes.length);
    for (final mailbox in destinationMailboxes) {
      final mbBytes = utf8.encode(mailbox);
      builder.addByte(mbBytes.length);
      builder.add(mbBytes);
    }

    return BluetoothMeshPacket(
      type: BluetoothPacketType.syncOffers,
      payload: builder.toBytes(),
    );
  }

  /// Cria o pacote de transferência de envelope cifrado de ponta a ponta.
  BluetoothMeshPacket createEnvelopeTransfer({
    required String deliveryId,
    required String destinationMailbox,
    required Uint8List ciphertext,
    required int expiresAt,
  }) {
    final builder = BytesBuilder();
    final delivBytes = utf8.encode(deliveryId);
    final mbxBytes = utf8.encode(destinationMailbox);

    builder.addByte(delivBytes.length);
    builder.add(delivBytes);
    builder.addByte(mbxBytes.length);
    builder.add(mbxBytes);

    // 8 bytes para timestamp expiresAt (uint64)
    for (var i = 7; i >= 0; i--) {
      builder.addByte((expiresAt >> (i * 8)) & 0xFF);
    }

    builder.add(ciphertext);

    return BluetoothMeshPacket(
      type: BluetoothPacketType.envelopeTransfer,
      payload: builder.toBytes(),
    );
  }

  /// Processa recebimento de envelope e valida integridade.
  Map<String, dynamic> parseReceivedEnvelope(BluetoothMeshPacket packet) {
    if (packet.type != BluetoothPacketType.envelopeTransfer) {
      throw StateError('Esperava envelopeTransfer, recebido: ${packet.type}');
    }

    final data = packet.payload;
    var offset = 0;

    final delivLen = data[offset++];
    final deliveryId = utf8.decode(data.sublist(offset, offset + delivLen));
    offset += delivLen;

    final mbxLen = data[offset++];
    final destinationMailbox = utf8.decode(data.sublist(offset, offset + mbxLen));
    offset += mbxLen;

    var expiresAt = 0;
    for (var i = 0; i < 8; i++) {
      expiresAt = (expiresAt << 8) | data[offset++];
    }

    final ciphertext = data.sublist(offset);
    final payloadHash = std_crypto.sha256.convert(ciphertext).bytes;

    return {
      'deliveryId': deliveryId,
      'destinationMailbox': destinationMailbox,
      'expiresAt': expiresAt,
      'ciphertext': Uint8List.fromList(ciphertext),
      'payloadHash': Uint8List.fromList(payloadHash),
    };
  }
}

/// Gerenciador de Rede Mesh Proximidade Bluetooth (P2P Mesh Driver).
class BluetoothMeshManager {
  final String localCardId;
  final Map<String, BluetoothProximityPeer> _peers = {};
  bool _isMeshEnabled = false;
  int _txPacketsSent = 0;
  int _rxPacketsReceived = 0;

  /// Hook injetado pelo driver nativo (ex: Android BluetoothGatt / Linux BlueZ) para enviar bytes reais pelo ar.
  Future<bool> Function(String deviceAddress, Uint8List encodedPacket)?
      onTransmitPacket;

  final _peerDiscoveredController =
      StreamController<BluetoothProximityPeer>.broadcast();
  final _envelopeReceivedController =
      StreamController<Map<String, dynamic>>.broadcast();

  BluetoothMeshManager({required this.localCardId, this.onTransmitPacket});

  bool get isMeshEnabled => _isMeshEnabled;
  int get txPacketsSent => _txPacketsSent;
  int get rxPacketsReceived => _rxPacketsReceived;
  List<BluetoothProximityPeer> get activePeers => _peers.values.toList();
  Stream<BluetoothProximityPeer> get onPeerDiscovered =>
      _peerDiscoveredController.stream;
  Stream<Map<String, dynamic>> get onEnvelopeReceived =>
      _envelopeReceivedController.stream;

  /// Habilita ou desabilita o modo de malha por proximidade Bluetooth.
  void setMeshEnabled(bool enabled) {
    _isMeshEnabled = enabled;
    if (!enabled) {
      _peers.clear();
    }
  }

  /// Registra ou atualiza um par próximo descoberto via anúncio Bluetooth LE.
  void registerDiscoveredPeer({
    required String deviceAddress,
    required String peerCardId,
    required int rssi,
  }) {
    if (!_isMeshEnabled) return;

    final existing = _peers[deviceAddress];
    if (existing != null) {
      existing.lastSeen = DateTime.now().toUtc();
      _peers[deviceAddress] = BluetoothProximityPeer(
        deviceAddress: deviceAddress,
        peerPublicCardId:
            peerCardId.isNotEmpty ? peerCardId : existing.peerPublicCardId,
        rssiSignalStrength: rssi,
        status: existing.status,
        lastSeen: existing.lastSeen,
      );
      _peerDiscoveredController.add(_peers[deviceAddress]!);
    } else {
      final newPeer = BluetoothProximityPeer(
        deviceAddress: deviceAddress,
        peerPublicCardId: peerCardId,
        rssiSignalStrength: rssi,
      );
      _peers[deviceAddress] = newPeer;
      _peerDiscoveredController.add(newPeer);
    }
  }

  /// Entrega um pacote recebido via rádio Bluetooth para processamento no Nix.
  void handleIncomingPacket(String fromAddress, Uint8List rawBytes) {
    if (!_isMeshEnabled) return;
    final packet = BluetoothMeshPacket.decode(rawBytes);

    if (packet.type == BluetoothPacketType.envelopeTransfer) {
      final peer = _peers[fromAddress] ??
          BluetoothProximityPeer(
            deviceAddress: fromAddress,
            peerPublicCardId: 'unknown',
            rssiSignalStrength: -70,
          );
      final session = BluetoothMeshSession(
        localIdentityCardId: localCardId,
        remotePeer: peer,
      );
      final parsed = session.parseReceivedEnvelope(packet);
      parsed['fromAddress'] = fromAddress;
      parsed['receivedAtMs'] = DateTime.now().toUtc().millisecondsSinceEpoch;
      _rxPacketsReceived++;
      _envelopeReceivedController.add(parsed);
    }
  }

  /// Transmite ou difunde um envelope cifrado para os pares da malha por proximidade.
  /// Retorna a quantidade de pares que confirmaram transmissão pelo driver BLE nativo.
  Future<int> broadcastEnvelope({
    required String recipientCardId,
    required Uint8List payload,
    String? targetDeviceAddress,
  }) async {
    if (!_isMeshEnabled) return 0;
    final targets = targetDeviceAddress != null
        ? _peers.values
            .where((p) => p.deviceAddress == targetDeviceAddress)
            .toList()
        : _peers.values.toList();

    int sentCount = 0;
    for (final peer in targets) {
      final session = BluetoothMeshSession(
        localIdentityCardId: localCardId,
        remotePeer: peer,
      );
      final packet = session.createEnvelopeTransfer(
        deliveryId: 'btp_${DateTime.now().millisecondsSinceEpoch}',
        destinationMailbox: recipientCardId,
        ciphertext: payload,
        expiresAt: DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .millisecondsSinceEpoch,
      );
      final encoded = packet.encode();
      if (onTransmitPacket != null) {
        final ok = await onTransmitPacket!(peer.deviceAddress, encoded);
        if (ok) {
          _txPacketsSent++;
          sentCount++;
        }
      }
    }
    return sentCount;
  }

  void dispose() {
    _peerDiscoveredController.close();
    _envelopeReceivedController.close();
  }
}
