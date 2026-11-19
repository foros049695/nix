import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:nix_transport/nix_transport.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 5 Off-Grid Radio <= 240B, Duty Cycle e ATAK CoT com consentimento', () {
    test('RadioPacketCodec impõe limite estrito <= 240B e bloqueia mídias/anexos', () {
      final small = Uint8List.fromList(utf8.encode('SOS_SETOR_NORTE_OK'));
      final frame = RadioPacketCodec.encodeShortFrame(
        sequenceNo: 42,
        payloadBytes: small,
        hopLimit: 3,
      );
      expect(frame.length, lessThanOrEqualTo(RadioPacketCodec.maxWireBytes));
      final decoded = RadioPacketCodec.decodeFrame(frame);
      expect(decoded.sequenceNo, 42);
      expect(utf8.decode(decoded.payload), 'SOS_SETOR_NORTE_OK');

      // Bloqueia mídia binária explicitamente
      expect(
        () => RadioPacketCodec.encodeShortFrame(
          sequenceNo: 43,
          payloadBytes: small,
          containsMediaOrAttachment: true,
        ),
        throwsA(isA<RadioMediaBlockedException>()),
      );

      // Bloqueia payload acima da janela física (wire > 240B)
      expect(
        () => RadioPacketCodec.encodeShortFrame(
          sequenceNo: 44,
          payloadBytes: Uint8List(RadioPacketCodec.maxPayloadBytes + 1),
        ),
        throwsA(isA<RadioFrameTooLargeException>()),
      );

      // Adulteração de bit detectada pelo CRC16-CCITT
      final corrupted = Uint8List.fromList(frame);
      corrupted[10] ^= 0xFF;
      expect(
        () => RadioPacketCodec.decodeFrame(corrupted),
        throwsA(isA<FormatException>()),
      );
    });

    test('DutyCycleGovernor aplica cota de tempo no ar dentro da janela', () {
      final gov = DutyCycleGovernor(
        maxAirTimeMsPerWindow: 1000,
        window: const Duration(minutes: 10),
      );
      final t0 = DateTime.utc(2026, 11, 19, 12, 0, 0);
      gov.consumeOrThrow(600, now: t0);
      expect(gov.remainingBudgetMs(now: t0), 400);
      expect(
        () => gov.consumeOrThrow(500, now: t0.add(const Duration(seconds: 10))),
        throwsA(isA<RadioDutyCycleExceededException>()),
      );
      // Após janela expirar, orçamento renova
      expect(
        gov.remainingBudgetMs(now: t0.add(const Duration(minutes: 11))),
        1000,
      );
    });

    test('AtakCotBridge bloqueia sem consentimento e envia XML via UDP loopback com consentimento', () async {
      expect(
        () => AtakCotBridge.buildCotEventXml(
          uid: 'nix-node-1',
          lat: -23.5505,
          lon: -46.6333,
          callsign: 'ALPHA-1',
          explicitUserConsent: false,
        ),
        throwsA(isA<StateError>()),
      );

      final xml = AtakCotBridge.buildCotEventXml(
        uid: 'nix-node-1',
        lat: -23.5505,
        lon: -46.6333,
        callsign: 'ALPHA-1',
        explicitUserConsent: true,
      );
      expect(xml, contains('uid="nix-node-1"'));
      expect(xml, contains('callsign="ALPHA-1"'));

      final rxSock = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(rxSock.close);
      final received = Completer<Datagram?>();
      rxSock.listen((e) {
        if (e == RawSocketEvent.read && !received.isCompleted) {
          received.complete(rxSock.receive());
        }
      });
      await AtakCotBridge.sendCotUdp(
        xmlEvent: xml,
        explicitUserConsent: true,
        destination: InternetAddress.loopbackIPv4,
        port: rxSock.port,
      );
      final dg = await received.future.timeout(const Duration(seconds: 2));
      expect(dg, isNotNull);
      expect(utf8.decode(dg!.data), equals(xml));
    });
  });
}
