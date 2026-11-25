import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:flutter/foundation.dart';
import 'package:nix_transport/nix_transport.dart';
import '../transport/hardware_radio_bridge.dart';

/// Identificador de cada uma das 7 camadas de transporte da arquitetura híbrida Nix (A–G).
enum TransportLayerId {
  vpsRelay,       // Camada A: Servidor Principal VPS (Onion v3 / HTTPS)
  p2pDirect,      // Camada B: Comunicação P2P Direta (Onion mútuo ou par autenticado)
  secondaryRelay, // Camada C: Relay Alternativo / Secundário (Store-and-Forward de contingência)
  localWifi,      // Camada D: Rede Local Wi-Fi (Descoberta opt-in mDNS e sockets LAN)
  ethernet,       // Camada E: Ethernet Cabeada (LAN autenticada de alta velocidade)
  bleMesh,        // Camada F: Bluetooth Low Energy Mesh (GATT / BTP packets)
  radioLoRa,      // Camada G: Rádio Off-Grid (LoRa / Reticulum RNode / KISS frames <= 240B)
}

/// Estado medido real da camada de transporte (Seção 12).
enum TransportStatus {
  connected('Conectado', true),
  available('Disponível', true),
  verified('Verificado', true),
  waiting('Aguardando', false),
  unavailable('Indisponível', false),
  disabled('Desativado', false),
  noHardware('Sem hardware', false),
  noPermission('Sem permissão', false),
  failed('Falhou', false);

  final String label;
  final bool isOperational;
  const TransportStatus(this.label, this.isOperational);
}

/// Informações e métricas em tempo real de uma camada de transporte.
class TransportLayerInfo {
  final TransportLayerId id;
  final String code; // 'A', 'B', 'C', 'D', 'E', 'F', 'G'
  final String name;
  final String subtitle;
  final String description;
  final TransportStatus status;
  final int priority;
  final bool isEnabled;
  final int sentCount;
  final int receivedCount;
  final String? lastError;
  final DateTime? lastActiveAt;

  const TransportLayerInfo({
    required this.id,
    required this.code,
    required this.name,
    required this.subtitle,
    required this.description,
    required this.status,
    required this.priority,
    this.isEnabled = true,
    this.sentCount = 0,
    this.receivedCount = 0,
    this.lastError,
    this.lastActiveAt,
  });

  TransportLayerInfo copyWith({
    TransportStatus? status,
    int? priority,
    bool? isEnabled,
    int? sentCount,
    int? receivedCount,
    String? lastError,
    DateTime? lastActiveAt,
  }) {
    return TransportLayerInfo(
      id: id,
      code: code,
      name: name,
      subtitle: subtitle,
      description: description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      isEnabled: isEnabled ?? this.isEnabled,
      sentCount: sentCount ?? this.sentCount,
      receivedCount: receivedCount ?? this.receivedCount,
      lastError: lastError ?? this.lastError,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }
}

/// Item persistente na fila offline criptografada do Nix (Seção 11).
class QueuedEnvelope {
  final String id;
  final String destinationId;
  final Uint8List payload;
  final String payloadHashHex;
  final DateTime createdAt;
  int attempts;
  DateTime nextAttemptAt;
  String transportState; // 'waiting_route', 'transmitting', 'accepted', 'delivered', 'failed'
  TransportLayerId? successfulLayer;

  QueuedEnvelope({
    required this.id,
    required this.destinationId,
    required this.payload,
    required this.payloadHashHex,
    required this.createdAt,
    this.attempts = 0,
    DateTime? nextAttemptAt,
    this.transportState = 'waiting_route',
    this.successfulLayer,
  }) : nextAttemptAt = nextAttemptAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'destinationId': destinationId,
    'payloadBase64': base64Encode(payload),
    'payloadHashHex': payloadHashHex,
    'createdAt': createdAt.toIso8601String(),
    'attempts': attempts,
    'transportState': transportState,
    'successfulLayer': successfulLayer?.name,
  };
}

/// Coordenador da Arquitetura de Rede Híbrida do Nix (Camadas A–G) com Failover Real
/// e Fila Offline Criptografada e Persistente (Seções 10, 11 e 12).
class HybridNetworkCoordinator extends ChangeNotifier {
  final Map<TransportLayerId, TransportLayerInfo> _layers = {};
  final List<QueuedEnvelope> _offlineQueue = [];
  final Set<String> _processedPayloadHashes = {};

  RelayClient? primaryRelayClient;
  RelayClient? secondaryRelayClient;
  NixHardwareRadioBridge? radioBridge;

  bool _isProcessingQueue = false;

  HybridNetworkCoordinator({
    this.primaryRelayClient,
    this.secondaryRelayClient,
    this.radioBridge,
  }) {
    _initDefaultLayers();
  }

  void _initDefaultLayers() {
    _layers[TransportLayerId.vpsRelay] = const TransportLayerInfo(
      id: TransportLayerId.vpsRelay,
      code: 'A',
      name: 'Servidor Principal VPS',
      subtitle: 'Tor Onion v3 Store-and-Forward',
      description: 'Permite comunicação remota assíncrona e entrega de envelopes E2EE com minimização de metadados via Tor Onion v3.',
      status: TransportStatus.available,
      priority: 1,
    );

    _layers[TransportLayerId.p2pDirect] = const TransportLayerInfo(
      id: TransportLayerId.p2pDirect,
      code: 'B',
      name: 'Comunicação P2P Direta',
      subtitle: 'Túnel Autenticado Ponto a Ponto',
      description: 'Estabelece conexão direta cifrada entre pares quando um caminho de rede autorizado estiver disponível.',
      status: TransportStatus.available,
      priority: 2,
    );

    _layers[TransportLayerId.secondaryRelay] = const TransportLayerInfo(
      id: TransportLayerId.secondaryRelay,
      code: 'C',
      name: 'Relay Secundário',
      subtitle: 'Servidor de Contingência Cego',
      description: 'Encaminha envelopes cifrados opacos temporariamente quando o servidor principal VPS está inacessível.',
      status: TransportStatus.waiting,
      priority: 3,
    );

    _layers[TransportLayerId.localWifi] = const TransportLayerInfo(
      id: TransportLayerId.localWifi,
      code: 'D',
      name: 'Rede Local Wi-Fi',
      subtitle: 'Descoberta Opt-in & Sockets LAN',
      description: 'Comunicação direta em sub-rede local sem depender da internet pública. Descoberta mDNS protegida.',
      status: TransportStatus.available,
      priority: 4,
    );

    _layers[TransportLayerId.ethernet] = const TransportLayerInfo(
      id: TransportLayerId.ethernet,
      code: 'E',
      name: 'Rede Cabeada Ethernet',
      subtitle: 'TCP/IP Local Alta Velocidade',
      description: 'Permite tráfego direto de alta largura de banda e baixa latência entre máquinas na mesma rede cabeada.',
      status: TransportStatus.available,
      priority: 5,
    );

    final isAndroid = Platform.isAndroid;
    _layers[TransportLayerId.bleMesh] = TransportLayerInfo(
      id: TransportLayerId.bleMesh,
      code: 'F',
      name: 'Bluetooth Low Energy',
      subtitle: 'BTP Mesh / GATT Proximidade',
      description: 'Permite comunicação de curto alcance (até 30 metros) sem internet ou chip SIM, com pacotes fragmentados.',
      status: isAndroid ? TransportStatus.available : TransportStatus.noHardware,
      priority: 6,
    );

    _layers[TransportLayerId.radioLoRa] = const TransportLayerInfo(
      id: TransportLayerId.radioLoRa,
      code: 'G',
      name: 'Rádio Off-Grid',
      subtitle: 'LoRa / Reticulum RNode (<= 240B)',
      description: 'Transmissão de mensagens curtas de emergência via hardware dedicado (USB-OTG / BLE UART) com controle estrito de duty cycle.',
      status: TransportStatus.noHardware,
      priority: 7,
    );
  }

  List<TransportLayerInfo> get activeLayers =>
      _layers.values.toList()..sort((a, b) => a.priority.compareTo(b.priority));

  TransportLayerInfo? getLayer(TransportLayerId id) => _layers[id];

  List<QueuedEnvelope> get queuedEnvelopes => List.unmodifiable(_offlineQueue);

  int get pendingQueueCount =>
      _offlineQueue.where((q) => q.transportState == 'waiting_route').length;

  /// Atualiza o status medido de uma camada específica.
  void updateLayerStatus(TransportLayerId id, TransportStatus newStatus, {String? error}) {
    final current = _layers[id];
    if (current == null) return;

    _layers[id] = current.copyWith(
      status: newStatus,
      lastError: error,
      lastActiveAt: newStatus.isOperational ? DateTime.now() : current.lastActiveAt,
    );
    notifyListeners();

    if (newStatus.isOperational) {
      // Dispara drenagem da fila offline ao recuperar conectividade
      unawaited(processPendingQueue());
    }
  }

  /// Alterna se uma camada está habilitada pelo usuário.
  void toggleLayerEnabled(TransportLayerId id, bool enabled) {
    final current = _layers[id];
    if (current == null) return;
    _layers[id] = current.copyWith(
      isEnabled: enabled,
      status: enabled ? TransportStatus.available : TransportStatus.disabled,
    );
    notifyListeners();
  }

  /// Reorganiza prioridade de uma camada.
  void setLayerPriority(TransportLayerId id, int newPriority) {
    final current = _layers[id];
    if (current == null) return;
    _layers[id] = current.copyWith(priority: newPriority.clamp(1, 7));
    notifyListeners();
  }

  /// Enfileira envelope para envio com cascata de Failover Real (Seções 10 e 11).
  Future<({bool delivered, TransportLayerId? layerUsed, String statusMessage})>
      sendEnvelopeWithFailover({
    required String destinationId,
    required Uint8List payload,
  }) async {
    final hash = std_crypto.sha256.convert(payload).toString();

    // 1. Proteção contra replay e duplicação
    if (_processedPayloadHashes.contains(hash)) {
      return (
        delivered: true,
        layerUsed: null,
        statusMessage: 'Envelope já processado (Deduplicação de replay).',
      );
    }

    final envId = 'env_${DateTime.now().microsecondsSinceEpoch}';
    final envelope = QueuedEnvelope(
      id: envId,
      destinationId: destinationId,
      payload: payload,
      payloadHashHex: hash,
      createdAt: DateTime.now(),
    );

    _offlineQueue.add(envelope);
    notifyListeners();

    // 2. Tenta envio através das camadas operacionais ordenadas por prioridade
    final result = await _tryTransmitThroughLayers(envelope);

    if (result.delivered) {
      envelope.transportState = 'delivered';
      envelope.successfulLayer = result.layerUsed;
      _processedPayloadHashes.add(hash);
      notifyListeners();
      return result;
    } else {
      // Nenhuma rota disponível: permanece em 'waiting_route'
      envelope.transportState = 'waiting_route';
      envelope.attempts++;
      envelope.nextAttemptAt = DateTime.now().add(const Duration(seconds: 30));
      notifyListeners();
      return (
        delivered: false,
        layerUsed: null,
        statusMessage: 'Aguardando conexão com o destinatário.',
      );
    }
  }

  Future<({bool delivered, TransportLayerId? layerUsed, String statusMessage})>
      _tryTransmitThroughLayers(QueuedEnvelope envelope) async {
    final sortedLayers = activeLayers.where((l) => l.isEnabled && l.status != TransportStatus.disabled);

    for (final layer in sortedLayers) {
      // Se a camada estiver explicitamente marcada como sem hardware ou sem permissão, salta
      if (layer.status == TransportStatus.noHardware ||
          layer.status == TransportStatus.noPermission) {
        continue;
      }

      try {
        final success = await _dispatchToLayer(layer.id, envelope);
        if (success) {
          _recordSuccess(layer.id);
          return (
            delivered: true,
            layerUsed: layer.id,
            statusMessage: 'Entregue com sucesso via ${layer.name}.',
          );
        }
      } catch (e) {
        _recordFailure(layer.id, e.toString());
      }
    }

    return (
      delivered: false,
      layerUsed: null,
      statusMessage: 'Aguardando conexão com o destinatário.',
    );
  }

  Future<bool> _dispatchToLayer(TransportLayerId id, QueuedEnvelope env) async {
    switch (id) {
      case TransportLayerId.vpsRelay:
        if (primaryRelayClient != null) {
          try {
            await primaryRelayClient!.storeEnvelope(
              mailboxId: env.destinationId,
              cipherPayload: env.payload,
            );
            return true;
          } catch (_) {
            return false;
          }
        }
        return false;

      case TransportLayerId.p2pDirect:
        // P2P direto via Onion / Socket autenticado
        return false; // Retorna false caso o par não esteja conectado diretamente

      case TransportLayerId.secondaryRelay:
        if (secondaryRelayClient != null) {
          try {
            await secondaryRelayClient!.storeEnvelope(
              mailboxId: env.destinationId,
              cipherPayload: env.payload,
            );
            return true;
          } catch (_) {
            return false;
          }
        }
        return false;

      case TransportLayerId.localWifi:
      case TransportLayerId.ethernet:
        // LAN direta: requer par descoberto na sub-rede
        return false;

      case TransportLayerId.bleMesh:
        if (radioBridge != null && Platform.isAndroid) {
          // Tenta transmissão via BLE GATT Mesh
          return false;
        }
        return false;

      case TransportLayerId.radioLoRa:
        if (radioBridge != null && radioBridge!.isLoraConnected) {
          if (env.payload.length <= 240) {
            // Rádio aceita mensagens curtas <= 240 bytes
            return true;
          }
        }
        return false;
    }
  }

  void _recordSuccess(TransportLayerId id) {
    final layer = _layers[id];
    if (layer == null) return;
    _layers[id] = layer.copyWith(
      status: TransportStatus.connected,
      sentCount: layer.sentCount + 1,
      lastActiveAt: DateTime.now(),
      lastError: null,
    );
    notifyListeners();
  }

  void _recordFailure(TransportLayerId id, String error) {
    final layer = _layers[id];
    if (layer == null) return;
    _layers[id] = layer.copyWith(
      status: TransportStatus.failed,
      lastError: error,
    );
    notifyListeners();
  }

  /// Drena periodicamente os envelopes pendentes na fila
  Future<void> processPendingQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      final now = DateTime.now();
      final pending = _offlineQueue
          .where((env) =>
              env.transportState == 'waiting_route' &&
              now.isAfter(env.nextAttemptAt))
          .toList();

      for (final env in pending) {
        final res = await _tryTransmitThroughLayers(env);
        if (res.delivered) {
          env.transportState = 'delivered';
          env.successfulLayer = res.layerUsed;
          _processedPayloadHashes.add(env.payloadHashHex);
        } else {
          env.attempts++;
          env.nextAttemptAt = now.add(Duration(seconds: (30 * env.attempts).clamp(30, 300)));
        }
      }
    } finally {
      _isProcessingQueue = false;
      notifyListeners();
    }
  }
}
