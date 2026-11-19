import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Exceção lançada quando um quadro de rádio excede o limite físico de 240 bytes (Fase 5).
class RadioFrameTooLargeException implements Exception {
  final int actualBytes;
  final int maxBytes;
  const RadioFrameTooLargeException(this.actualBytes, [this.maxBytes = 240]);

  @override
  String toString() =>
      'RadioFrameTooLargeException: quadro de $actualBytes bytes excede limite estrito de $maxBytes bytes.';
}

/// Exceção lançada quando mídia binária/anexo é bloqueada no filtro de banda estreita LoRa/Meshtastic.
class RadioMediaBlockedException implements Exception {
  final String reason;
  const RadioMediaBlockedException(this.reason);

  @override
  String toString() => 'RadioMediaBlockedException: $reason';
}

/// Exceção lançada quando a cota regulatória de ciclo de trabalho (duty cycle) é atingida.
class RadioDutyCycleExceededException implements Exception {
  final int remainingBudgetMs;
  const RadioDutyCycleExceededException(this.remainingBudgetMs);

  @override
  String toString() =>
      'RadioDutyCycleExceededException: orçamento de transmissão esgotado ($remainingBudgetMs ms restantes).';
}

/// Codec estrito de pacotes off-grid banda estreita (<= 240 bytes wire frame, texto curto + assinatura/mac).
/// Bloqueia explicitamente mídia binária, anexos e frames maiores que 240 bytes.
class RadioPacketCodec {
  static const int maxWireBytes = 240;
  static const int _headerBytes = 10; // [2B magic 'NX'][1B flags][1B hopLimit][4B seq][2B crc16]
  static const int maxPayloadBytes = maxWireBytes - _headerBytes;

  static const int flagEncryptedText = 0x01;
  static const int flagAck = 0x02;
  static const int flagHasMediaAttachment = 0x80;

  static Uint8List encodeShortFrame({
    required int sequenceNo,
    required Uint8List payloadBytes,
    int hopLimit = 3,
    bool containsMediaOrAttachment = false,
    bool isAck = false,
  }) {
    if (containsMediaOrAttachment) {
      throw const RadioMediaBlockedException(
        'Mídias e anexos são estritamente bloqueados no enlace de rádio banda estreita (<= 240B).',
      );
    }
    if (payloadBytes.length > maxPayloadBytes) {
      throw RadioFrameTooLargeException(
        payloadBytes.length + _headerBytes,
        maxWireBytes,
      );
    }

    final flags = flagEncryptedText | (isAck ? flagAck : 0);
    final frameWithoutCrc = Uint8List(_headerBytes - 2 + payloadBytes.length);
    frameWithoutCrc[0] = 0x4E; // 'N'
    frameWithoutCrc[1] = 0x58; // 'X'
    frameWithoutCrc[2] = flags;
    frameWithoutCrc[3] = hopLimit.clamp(0, 7);
    final bd = ByteData.sublistView(frameWithoutCrc);
    bd.setUint32(4, sequenceNo, Endian.big);
    frameWithoutCrc.setRange(8, 8 + payloadBytes.length, payloadBytes);

    final crc = _crc16Ccitt(frameWithoutCrc);
    final out = Uint8List(frameWithoutCrc.length + 2);
    out.setRange(0, frameWithoutCrc.length, frameWithoutCrc);
    out[out.length - 2] = (crc >> 8) & 0xFF;
    out[out.length - 1] = crc & 0xFF;
    return out;
  }

  static ({int flags, int hopLimit, int sequenceNo, Uint8List payload}) decodeFrame(
    Uint8List rawFrame,
  ) {
    if (rawFrame.length > maxWireBytes) {
      throw RadioFrameTooLargeException(rawFrame.length, maxWireBytes);
    }
    if (rawFrame.length < _headerBytes) {
      throw const FormatException('Quadro de rádio truncado (< 10 bytes).');
    }
    if (rawFrame[0] != 0x4E || rawFrame[1] != 0x58) {
      throw const FormatException('Magic byte de rádio inválido.');
    }
    final flags = rawFrame[2];
    if ((flags & flagHasMediaAttachment) != 0) {
      throw const RadioMediaBlockedException(
        'Quadro recebido com bit proibido de mídia em enlace rádio.',
      );
    }
    final bodyWithoutCrc = rawFrame.sublist(0, rawFrame.length - 2);
    final expectedCrc = (rawFrame[rawFrame.length - 2] << 8) | rawFrame[rawFrame.length - 1];
    final actualCrc = _crc16Ccitt(bodyWithoutCrc);
    if (actualCrc != expectedCrc) {
      throw const FormatException('CRC16-CCITT do quadro de rádio inválido.');
    }
    final bd = ByteData.sublistView(rawFrame);
    return (
      flags: flags,
      hopLimit: rawFrame[3],
      sequenceNo: bd.getUint32(4, Endian.big),
      payload: Uint8List.fromList(rawFrame.sublist(8, rawFrame.length - 2)),
    );
  }

  static int _crc16Ccitt(List<int> data) {
    int crc = 0xFFFF;
    for (final b in data) {
      crc ^= (b << 8);
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc;
  }
}

/// Controlador de orçamento de tempo no ar (duty cycle máximo regulatório, ex: 1% = 36.000 ms/hora).
class DutyCycleGovernor {
  final int maxAirTimeMsPerWindow;
  final Duration window;
  final List<({DateTime at, int durationMs})> _txHistory = [];

  DutyCycleGovernor({
    this.maxAirTimeMsPerWindow = 36000,
    this.window = const Duration(hours: 1),
  });

  int remainingBudgetMs({DateTime? now}) {
    final clock = (now ?? DateTime.now().toUtc());
    _prune(clock);
    final used = _txHistory.fold<int>(0, (sum, e) => sum + e.durationMs);
    final rem = maxAirTimeMsPerWindow - used;
    return rem < 0 ? 0 : rem;
  }

  void consumeOrThrow(int airtimeMs, {DateTime? now}) {
    final clock = (now ?? DateTime.now().toUtc());
    final rem = remainingBudgetMs(now: clock);
    if (airtimeMs <= 0) return;
    if (airtimeMs > rem) {
      throw RadioDutyCycleExceededException(rem);
    }
    _txHistory.add((at: clock, durationMs: airtimeMs));
  }

  void _prune(DateTime now) {
    final cutoff = now.subtract(window);
    _txHistory.removeWhere((e) => e.at.isBefore(cutoff));
  }
}

/// Integração ATAK / CoT (Cursor-on-Target) em XML mínimo com consentimento explícito obrigatório.
class AtakCotBridge {
  static String buildCotEventXml({
    required String uid,
    required double lat,
    required double lon,
    required String callsign,
    required bool explicitUserConsent,
    String cotType = 'a-f-G-U-C',
    Duration staleAfter = const Duration(minutes: 5),
    DateTime? now,
  }) {
    if (!explicitUserConsent) {
      throw StateError(
        '[Fail-Closed] Transmissão de telemetria tática ATAK/CoT bloqueada sem consentimento explícito do usuário.',
      );
    }
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      throw ArgumentError('Coordenadas geográficas inválidas.');
    }
    final t = (now ?? DateTime.now().toUtc()).toUtc();
    final stale = t.add(staleAfter).toUtc();
    final safeUid = _xmlEscape(uid);
    final safeCall = _xmlEscape(callsign);
    return '<event version="2.0" uid="$safeUid" type="$cotType" time="${t.toIso8601String()}" '
        'start="${t.toIso8601String()}" stale="${stale.toIso8601String()}" how="h-e">'
        '<point lat="${lat.toStringAsFixed(6)}" lon="${lon.toStringAsFixed(6)}" '
        'hae="0.0" ce="10.0" le="10.0"/>'
        '<detail><contact callsign="$safeCall"/></detail>'
        '</event>';
  }

  /// Envia evento CoT via UDP exclusivamente para interface local/multicast local mediante consentimento explícito.
  static Future<int> sendCotUdp({
    required String xmlEvent,
    required bool explicitUserConsent,
    InternetAddress? destination,
    int port = 4242,
  }) async {
    if (!explicitUserConsent) {
      throw StateError('[Fail-Closed] Envio UDP ATAK/CoT negado sem consentimento.');
    }
    final target = destination ?? InternetAddress.loopbackIPv4;
    final sock = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      return sock.send(utf8.encode(xmlEvent), target, port);
    } finally {
      sock.close();
    }
  }

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// Codec KISS padrão compatível com transceptores LoRa Reticulum RNode (USB-OTG / BLE UART).
/// Referência: especificação KISS (FEND=0xC0, FESC=0xDB, TFEND=0xDC, TFESC=0xDD).
class KissFrameCodec {
  static const int fend = 0xC0;
  static const int fesc = 0xDB;
  static const int tfend = 0xDC;
  static const int tfesc = 0xDD;

  static const int cmdData = 0x00;
  static const int cmdDetect = 0x08;
  static const int detectReq = 0x73;
  static const int detectResp = 0x46;

  /// Comando de sondagem RNode KISS (`CMD_DETECT` + `DETECT_REQ`).
  static Uint8List buildDetectProbe() =>
      Uint8List.fromList(const [fend, cmdDetect, detectReq, fend]);

  /// Verifica se um buffer bruto contém resposta válida de hardware RNode (`CMD_DETECT` + `DETECT_RESP`).
  static bool isDetectResponse(Uint8List rawBytes) {
    final frames = decodeAll(rawBytes);
    return frames.any((f) =>
        f.command == cmdDetect &&
        f.payload.isNotEmpty &&
        f.payload.first == detectResp);
  }

  /// Encapsula um quadro [RadioPacketCodec] (`<= 240B`) em envelope KISS com escaping rigoroso.
  static Uint8List encodeFrame(Uint8List payload, {int command = cmdData}) {
    final out = BytesBuilder();
    out.addByte(fend);
    out.addByte(command & 0xFF);
    for (final b in payload) {
      if (b == fend) {
        out.addByte(fesc);
        out.addByte(tfend);
      } else if (b == fesc) {
        out.addByte(fesc);
        out.addByte(tfesc);
      } else {
        out.addByte(b);
      }
    }
    out.addByte(fend);
    return out.toBytes();
  }

  /// Decodifica todos os quadros KISS válidos presentes em um fluxo/buffer serial.
  static List<({int command, Uint8List payload})> decodeAll(Uint8List streamBytes) {
    final frames = <({int command, Uint8List payload})>[];
    bool inFrame = false;
    bool escaped = false;
    int? currentCmd;
    final buf = <int>[];

    for (final b in streamBytes) {
      if (b == fend) {
        if (inFrame && currentCmd != null) {
          frames.add((command: currentCmd, payload: Uint8List.fromList(buf)));
        }
        inFrame = true;
        escaped = false;
        currentCmd = null;
        buf.clear();
        continue;
      }
      if (!inFrame) continue;
      if (currentCmd == null) {
        currentCmd = b;
        continue;
      }
      if (escaped) {
        escaped = false;
        if (b == tfend) {
          buf.add(fend);
        } else if (b == tfesc) {
          buf.add(fesc);
        }
        continue;
      }
      if (b == fesc) {
        escaped = true;
        continue;
      }
      buf.add(b);
    }
    return frames;
  }
}
