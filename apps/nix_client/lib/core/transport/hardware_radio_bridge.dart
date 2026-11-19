import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:nix_transport/nix_transport.dart';

/// Estado real do hardware Bluetooth LE Mesh no dispositivo físico.
class BleHardwareStatus {
  final bool supported;
  final bool adapterEnabled;
  final bool permissionsGranted;
  final bool isAdvertising;
  final bool isScanning;
  final bool isGattServerRunning;
  final String detail;

  const BleHardwareStatus({
    required this.supported,
    required this.adapterEnabled,
    required this.permissionsGranted,
    required this.isAdvertising,
    required this.isScanning,
    required this.isGattServerRunning,
    required this.detail,
  });
}

/// Dispositivo LoRa / RNode detectado via USB-OTG ou BLE Nordic UART.
class RNodeHardwareDevice {
  final String id;
  final String name;
  final String transport; // 'usb_otg' | 'ble_uart'
  final String detail;

  const RNodeHardwareDevice({
    required this.id,
    required this.name,
    required this.transport,
    required this.detail,
  });
}

/// Quadro recebido via Bluetooth BLE Mesh ou Rádio LoRa/RNode para auditoria ao vivo.
class HardwareRadioLogEntry {
  final DateTime timestamp;
  final String medium; // 'BLE' | 'LORA'
  final String direction; // 'TX' | 'RX' | 'SYS'
  final String summary;

  const HardwareRadioLogEntry({
    required this.timestamp,
    required this.medium,
    required this.direction,
    required this.summary,
  });
}

/// Ponte nativa real para Bluetooth BLE Mesh (`com.projetonix.nix/ble_mesh`)
/// e Rádio LoRa / Reticulum RNode (`com.projetonix.nix/lora_rnode`).
///
/// Em Android físico, comunica diretamente com `NixBleMeshController.kt` (BLE GATT
/// Server + Client + Scanner + Advertiser) e `NixRNodeRadioController.kt` (USB-OTG
/// + BLE NUS KISS). Em Linux/testes sem controlador nativo, reporta honestamente a ausência.
class NixHardwareRadioBridge {
  static const MethodChannel _bleChannel =
      MethodChannel('com.projetonix.nix/ble_mesh');
  static const MethodChannel _loraChannel =
      MethodChannel('com.projetonix.nix/lora_rnode');

  final BluetoothMeshManager bluetoothMesh;
  final DutyCycleGovernor dutyCycleGovernor = DutyCycleGovernor();
  final void Function(HardwareRadioLogEntry entry)? onLog;
  final void Function(String from, Uint8List payload, int seq)? onLoraFrameRx;

  bool _attached = false;
  bool _loraConnected = false;
  String? _connectedLoraDeviceName;
  int _loraSequence = 1;
  int _loraTxCount = 0;
  int _loraRxCount = 0;

  NixHardwareRadioBridge({
    required this.bluetoothMesh,
    this.onLog,
    this.onLoraFrameRx,
  });

  bool get isLoraConnected => _loraConnected;
  String? get connectedLoraDeviceName => _connectedLoraDeviceName;
  int get loraTxCount => _loraTxCount;
  int get loraRxCount => _loraRxCount;

  void _log(String medium, String direction, String summary) {
    onLog?.call(HardwareRadioLogEntry(
      timestamp: DateTime.now().toUtc(),
      medium: medium,
      direction: direction,
      summary: summary,
    ));
  }

  /// Conecta os callbacks Kotlin -> Dart e injeta o transmissor real no [BluetoothMeshManager].
  void attach() {
    if (_attached) return;
    _attached = true;

    if (!Platform.isAndroid || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }

    bluetoothMesh.onTransmitPacket = (deviceAddress, encodedBytes) async {
      try {
        final res = await _bleChannel.invokeMapMethod<String, dynamic>(
          'sendPacket',
          {
            'deviceAddress': deviceAddress,
            'bytes': encodedBytes,
          },
        );
        final ok = (res?['delivered'] as bool?) ?? false;
        final err = res?['error'] as String?;
        _log(
          'BLE',
          'TX',
          ok
              ? 'NIXB (${encodedBytes.length}B) entregue a $deviceAddress (MTU=${res?['mtu'] ?? '?'})'
              : 'Falha TX para $deviceAddress: ${err ?? "erro GATT"}',
        );
        return ok;
      } catch (e) {
        _log('BLE', 'TX', 'Exceção BLE TX para $deviceAddress: $e');
        return false;
      }
    };

    _bleChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPeerDiscovered':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final addr = (args['address'] as String?) ?? '';
          final cardId = (args['peerCardId'] as String?) ?? 'NIX-BLE';
          final rssi = (args['rssi'] as int?) ?? -70;
          if (addr.isNotEmpty) {
            bluetoothMesh.registerDiscoveredPeer(
              deviceAddress: addr,
              peerCardId: cardId,
              rssi: rssi,
            );
            _log('BLE', 'SYS', 'Par Nix descoberto: $cardId ($addr · $rssi dBm)');
          }
          break;
        case 'onPacketReceived':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final addr = (args['address'] as String?) ?? 'ble_peer';
          final raw = args['bytes'];
          if (raw is Uint8List && raw.isNotEmpty) {
            try {
              bluetoothMesh.handleIncomingPacket(addr, raw);
              _log('BLE', 'RX',
                  'Pacote NIXB (${raw.length}B) autenticado de $addr');
            } catch (e) {
              _log('BLE', 'RX', 'Quadro BLE descartado de $addr: $e');
            }
          }
          break;
        case 'onMeshLog':
          final msg = (call.arguments as String?) ?? '';
          if (msg.isNotEmpty) _log('BLE', 'SYS', msg);
          break;
      }
    });

    _loraChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onKissBytesReceived':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final src = (args['source'] as String?) ?? 'rnode';
          final raw = args['bytes'];
          if (raw is Uint8List && raw.isNotEmpty) {
            final kissFrames = KissFrameCodec.decodeAll(raw);
            for (final kf in kissFrames) {
              if (kf.command == KissFrameCodec.cmdDetect &&
                  kf.payload.isNotEmpty &&
                  kf.payload.first == KissFrameCodec.detectResp) {
                _log('LORA', 'RX',
                    'RNode KISS CMD_DETECT confirmado pelo transceptor ($src)');
                continue;
              }
              if (kf.command == KissFrameCodec.cmdData &&
                  kf.payload.isNotEmpty) {
                try {
                  final decoded = RadioPacketCodec.decodeFrame(kf.payload);
                  _loraRxCount++;
                  _log(
                    'LORA',
                    'RX',
                    'Quadro NX #${decoded.sequenceNo} (${decoded.payload.length}B, CRC16 OK, hops=${decoded.hopLimit})',
                  );
                  onLoraFrameRx?.call(src, decoded.payload, decoded.sequenceNo);
                } catch (e) {
                  _log('LORA', 'RX', 'Quadro LoRa descartado (CRC/formato): $e');
                }
              }
            }
          }
          break;
        case 'onRadioLog':
          final msg = (call.arguments as String?) ?? '';
          if (msg.isNotEmpty) _log('LORA', 'SYS', msg);
          break;
      }
    });
  }

  /// Consulta estado real do adaptador Bluetooth LE nativo.
  Future<BleHardwareStatus> getBleStatus() async {
    if (!Platform.isAndroid || Platform.environment.containsKey('FLUTTER_TEST')) {
      return const BleHardwareStatus(
        supported: false,
        adapterEnabled: false,
        permissionsGranted: false,
        isAdvertising: false,
        isScanning: false,
        isGattServerRunning: false,
        detail:
            'Driver BLE GATT nativo ativo exclusivamente no APK Android físico.',
      );
    }
    try {
      final res =
          await _bleChannel.invokeMapMethod<String, dynamic>('getBluetoothStatus');
      return BleHardwareStatus(
        supported: (res?['supported'] as bool?) ?? false,
        adapterEnabled: (res?['enabled'] as bool?) ?? false,
        permissionsGranted: (res?['permissionsGranted'] as bool?) ?? false,
        isAdvertising: (res?['advertising'] as bool?) ?? false,
        isScanning: (res?['scanning'] as bool?) ?? false,
        isGattServerRunning: (res?['gattServerActive'] as bool?) ?? false,
        detail: (res?['detail'] as String?) ?? 'BLE pronto.',
      );
    } catch (e) {
      return BleHardwareStatus(
        supported: false,
        adapterEnabled: false,
        permissionsGranted: false,
        isAdvertising: false,
        isScanning: false,
        isGattServerRunning: false,
        detail: 'Erro ao consultar adaptador BLE: $e',
      );
    }
  }

  /// Solicita permissões Android 12+ (`BLUETOOTH_SCAN/ADVERTISE/CONNECT`) ou localização <= 11.
  Future<bool> requestBlePermissions() async {
    if (!Platform.isAndroid || Platform.environment.containsKey('FLUTTER_TEST')) {
      return false;
    }
    try {
      final res = await _bleChannel
          .invokeMapMethod<String, dynamic>('requestPermissions');
      final granted = (res?['granted'] as bool?) ?? false;
      _log(
        'BLE',
        'SYS',
        granted
            ? 'Permissões Bluetooth LE concedidas pelo sistema.'
            : 'Permissões Bluetooth LE negadas pelo usuário.',
      );
      return granted;
    } catch (e) {
      _log('BLE', 'SYS', 'Erro ao solicitar permissões BLE: $e');
      return false;
    }
  }

  /// Inicia Advertising + Scanning + GATT Server BLE no hardware Android.
  Future<bool> startNativeBleMesh(String localCardId) async {
    attach();
    if (!Platform.isAndroid || Platform.environment.containsKey('FLUTTER_TEST')) {
      _log('BLE', 'SYS',
          'Modo lógico local ativado (sem rádio BLE GATT nativo neste host).');
      return false;
    }
    try {
      final res = await _bleChannel.invokeMapMethod<String, dynamic>(
        'startMesh',
        {'localCardId': localCardId},
      );
      final ok = (res?['started'] as bool?) ?? false;
      _log('BLE', 'SYS', (res?['detail'] as String?) ?? 'startMesh=$ok');
      return ok;
    } catch (e) {
      _log('BLE', 'SYS', 'Falha ao iniciar BLE Mesh nativo: $e');
      return false;
    }
  }

  /// Encerra Advertising + Scanning + GATT Server BLE.
  Future<void> stopNativeBleMesh() async {
    if (!Platform.isAndroid || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      await _bleChannel.invokeMethod('stopMesh');
      _log('BLE', 'SYS', 'BLE Mesh nativo encerrado.');
    } catch (_) {}
  }

  /// Lista dispositivos LoRa / RNode reais via USB-OTG e BLE Nordic UART.
  Future<List<RNodeHardwareDevice>> scanRNodeDevices() async {
    attach();
    if (!Platform.isAndroid || Platform.environment.containsKey('FLUTTER_TEST')) {
      _log('LORA', 'SYS',
          'Sondagem RNode USB-OTG/BLE disponível no APK Android físico.');
      return const [];
    }
    try {
      final rawList = await _loraChannel.invokeListMethod<dynamic>('listDevices');
      final out = <RNodeHardwareDevice>[];
      for (final item in (rawList ?? const [])) {
        if (item is Map) {
          out.add(RNodeHardwareDevice(
            id: (item['id'] as String?) ?? '',
            name: (item['name'] as String?) ?? 'Dispositivo RNode',
            transport: (item['transport'] as String?) ?? 'usb_otg',
            detail: (item['detail'] as String?) ?? '',
          ));
        }
      }
      _log(
        'LORA',
        'SYS',
        out.isEmpty
            ? 'Nenhum rádio LoRa/RNode USB-OTG ou BLE UART detectado.'
            : '${out.length} dispositivo(s) LoRa/RNode detectado(s).',
      );
      return out;
    } catch (e) {
      _log('LORA', 'SYS', 'Falha ao enumerar RNode: $e');
      return const [];
    }
  }

  /// Conecta a um rádio LoRa / RNode USB-OTG ou BLE UART e envia probe KISS `CMD_DETECT`.
  Future<bool> connectRNodeDevice(RNodeHardwareDevice device) async {
    attach();
    if (!Platform.isAndroid || Platform.environment.containsKey('FLUTTER_TEST')) {
      return false;
    }
    try {
      final res = await _loraChannel.invokeMapMethod<String, dynamic>(
        'connectDevice',
        {
          'id': device.id,
          'transport': device.transport,
          'detectProbe': KissFrameCodec.buildDetectProbe(),
        },
      );
      final ok = (res?['connected'] as bool?) ?? false;
      _loraConnected = ok;
      _connectedLoraDeviceName = ok ? device.name : null;
      _log('LORA', 'SYS', (res?['detail'] as String?) ?? 'connect=$ok');
      return ok;
    } catch (e) {
      _loraConnected = false;
      _connectedLoraDeviceName = null;
      _log('LORA', 'SYS', 'Falha ao conectar RNode ${device.name}: $e');
      return false;
    }
  }

  /// Codifica texto/payload em quadro [RadioPacketCodec] (`<= 240B`, CRC16-CCITT),
  /// valida cota do [DutyCycleGovernor], encapsula em KISS e transmite pelo RNode conectado.
  Future<({bool sent, String detail})> sendLoraShortPacket(
    Uint8List payloadBytes, {
    int estimatedAirtimeMs = 350,
  }) async {
    try {
      final wireFrame = RadioPacketCodec.encodeShortFrame(
        sequenceNo: _loraSequence++,
        payloadBytes: payloadBytes,
      );
      dutyCycleGovernor.consumeOrThrow(estimatedAirtimeMs);
      final kissBytes = KissFrameCodec.encodeFrame(wireFrame);

      if (!Platform.isAndroid || !_loraConnected) {
        final msg =
            'Quadro NX (${wireFrame.length}B, CRC16 válido, KISS=${kissBytes.length}B) validado, porém nenhum rádio RNode físico está conectado.';
        _log('LORA', 'SYS', msg);
        return (sent: false, detail: msg);
      }

      final res = await _loraChannel.invokeMapMethod<String, dynamic>(
        'sendKissFrame',
        {'bytes': kissBytes},
      );
      final ok = (res?['sent'] as bool?) ?? false;
      final detail = (res?['detail'] as String?) ??
          (ok ? 'Quadro KISS enviado (${kissBytes.length}B).' : 'Falha TX RNode.');
      if (ok) _loraTxCount++;
      _log('LORA', 'TX', detail);
      return (sent: ok, detail: detail);
    } catch (e) {
      final msg = 'Transmissão LoRa bloqueada: $e';
      _log('LORA', 'SYS', msg);
      return (sent: false, detail: msg);
    }
  }

  Future<void> disconnectRNode() async {
    _loraConnected = false;
    _connectedLoraDeviceName = null;
    if (!Platform.isAndroid || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      await _loraChannel.invokeMethod('disconnect');
      _log('LORA', 'SYS', 'Transceptor LoRa/RNode desconectado.');
    } catch (_) {}
  }
}
