import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:nix_transport/nix_transport.dart';

typedef VoiceTor = ({int socksPort, int controlPort, String cookiePath});

/// Two-party, in-memory audio/chat link authenticated by a one-use invitation.
/// HTTP is carried inside an ephemeral v3 Onion service, with a separate AEAD
/// key for each direction. Nothing enters the relay or the conversation history.
class OnionVoiceLink {
  OnionVoiceLink._(this.onion, this.expires, this._key, this.mayConnect);

  static const maxAudioBytes = 24000;
  static const _maxWire = 52000;
  static const _path = '/nix-voice-v1';
  static const _prefix = 'nix-voice-v1.';
  static const _lifetime = Duration(minutes: 45);
  static final _token = RegExp(r'^[a-zA-Z0-9_-]{22}$');

  final String onion;
  final DateTime expires;
  final SecretKeyData _key;
  final bool Function() mayConnect;
  final _guest = _randomToken();
  final _circuit = _randomToken();
  final _events =
      StreamController<({Uint8List audio, String? text})>.broadcast();

  HttpServer? _server;
  TorControlClient? _control;
  Timer? _timer;
  RelayClient? _http;
  String? _connectedGuest;
  Uint8List _outAudio = Uint8List(0);
  DateTime? _outAudioAt;
  String? _outText;
  int _outTextId = 0;
  int _receivedTextId = 0;
  int _tx = 0;
  int _rx = 0;
  bool _closed = false;
  bool _inFlight = false;
  DateTime? _lastPeer;

  bool get available =>
      !_closed && expires.isAfter(DateTime.now()) && mayConnect();
  bool get peerConnected =>
      available &&
      _lastPeer != null &&
      DateTime.now().difference(_lastPeer!) < const Duration(seconds: 10);
  Stream<({Uint8List audio, String? text})> get updates => _events.stream;

  static String _randomToken() {
    final key = SecretKeyData.random(length: 16);
    try {
      return base64Url.encode(key.bytes).replaceAll('=', '');
    } finally {
      key.destroy();
    }
  }

  String? get invite => _server != null && available && _connectedGuest == null
      ? '$_prefix${base64Url.encode(utf8.encode(jsonEncode([
              onion,
              expires.millisecondsSinceEpoch,
              base64Url.encode(_key.bytes),
            ])))}'
      : null;

  static Future<OnionVoiceLink> host(
      VoiceTor config, bool Function() gate) async {
    if (!gate()) throw StateError('Tor indisponível.');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    TorControlClient? control;
    try {
      control = await TorControlClient.connect(port: config.controlPort);
      await control.authenticateCookieFile(config.cookiePath);
      final entry = await control.addOnionV3(
        virtualPort: 80,
        targetPort: server.port,
        discardPrivateKey: true,
      );
      final onion = '${entry.serviceId}.onion';
      if (!TransportPolicy.isValidOnionV3Host(onion) || !gate()) {
        throw StateError('O serviço Onion ficou indisponível.');
      }
      final room = OnionVoiceLink._(onion, DateTime.now().add(_lifetime),
          SecretKeyData.random(length: 32), gate)
        .._server = server
        .._control = control;
      server.idleTimeout = const Duration(seconds: 4);
      server.listen(room._serve);
      room._startTimer();
      return room;
    } catch (_) {
      await server.close(force: true);
      await control?.close();
      rethrow;
    }
  }

  static OnionVoiceLink join(
      String invite, VoiceTor config, bool Function() gate) {
    if (!gate()) throw StateError('Tor indisponível.');
    final input = invite.trim();
    if (!input.startsWith(_prefix) || input.length > 600) {
      throw const FormatException('Convite de voz inválido.');
    }
    final raw = jsonDecode(
        utf8.decode(base64Url.decode(input.substring(_prefix.length))));
    if (raw is! List ||
        raw.length != 3 ||
        raw[0] is! String ||
        raw[1] is! int ||
        raw[2] is! String) throw const FormatException();
    final onion = raw[0] as String;
    final expiry = raw[1] as int;
    final now = DateTime.now();
    if (!TransportPolicy.isValidOnionV3Host(onion) ||
        expiry <= now.millisecondsSinceEpoch ||
        expiry > now.add(_lifetime).millisecondsSinceEpoch)
      throw const FormatException();
    final bytes = base64Url.decode(raw[2] as String);
    if (bytes.length != 32) throw const FormatException();
    final room = OnionVoiceLink._(
        onion,
        DateTime.fromMillisecondsSinceEpoch(expiry),
        SecretKeyData(bytes, overwriteWhenDestroyed: true),
        gate)
      .._http = RelayClient(
          baseUri: Uri(scheme: 'http', host: onion),
          policy: TransportPolicy(socksPort: config.socksPort));
    room._startTimer();
    return room;
  }

  void _startTimer() {
    _timer = Timer(expires.difference(DateTime.now()), close);
  }

  void setAudio(Uint8List bytes) {
    if (!available || bytes.length > maxAudioBytes || bytes.length.isOdd)
      return;
    _outAudio.fillRange(0, _outAudio.length, 0);
    _outAudio = Uint8List.fromList(bytes);
    _outAudioAt = DateTime.now();
  }

  void sendText(String text) {
    final clean = text.trim();
    if (!available ||
        clean.isEmpty ||
        utf8.encode(clean).length > 900 ||
        _outText != null) {
      throw StateError('Aguarde a confirmação anterior ou use até 900 bytes.');
    }
    _outText = clean;
    _outTextId++;
  }

  Future<SecretKey> _direction(String value) => Hkdf(
        hmac: Hmac.sha256(),
        outputLength: 32,
      ).deriveKey(
        secretKey: _key,
        nonce: utf8
            .encode('nix-voice-v1:$onion:${expires.millisecondsSinceEpoch}'),
        info: utf8.encode(value),
      );

  Future<String> _seal(List<Object?> value, String direction,
      [List<int> nonce = const []]) async {
    final key = await _direction(direction);
    try {
      final packet = await SealedEnvelope.seal(
        key: key,
        plaintext: utf8.encode(jsonEncode(value)),
        aad: nonce,
      );
      return base64Url.encode(packet.encode());
    } finally {
      if (key is SecretKeyData) key.destroy();
    }
  }

  Future<_VoicePacket> _open(SealedPayload packet, String direction,
      [List<int> nonce = const []]) async {
    final key = await _direction(direction);
    try {
      final data =
          await SealedEnvelope.open(key: key, payload: packet, aad: nonce);
      return _VoicePacket.parse(jsonDecode(utf8.decode(data)));
    } finally {
      if (key is SecretKeyData) key.destroy();
    }
  }

  List<Object?> _outgoing(String guest, int seq) {
    final audio = _outAudio;
    _outAudio = Uint8List(0);
    final stamp = _outAudioAt;
    _outAudioAt = null;
    final fresh = stamp != null &&
        DateTime.now().difference(stamp) < const Duration(milliseconds: 900);
    final encoded = fresh ? base64Encode(audio) : '';
    audio.fillRange(0, audio.length, 0);
    return [
      guest,
      seq,
      encoded,
      _outText,
      _outText == null ? 0 : _outTextId,
      _receivedTextId
    ];
  }

  void _receive(_VoicePacket payload) {
    if (!available || payload.sequence <= _rx) throw const FormatException();
    _lastPeer = DateTime.now();
    _rx = payload.sequence;
    if (payload.ack == _outTextId) _outText = null;
    final fresh = payload.textId > _receivedTextId ? payload.text : null;
    if (fresh != null) _receivedTextId = payload.textId;
    if (payload.audio.isNotEmpty || fresh != null) {
      _events.add((audio: payload.audio, text: fresh));
    }
  }

  Future<void> tick() async {
    if (!available || _inFlight || _http == null) return;
    _inFlight = true;
    try {
      final outgoing = _outgoing(_guest, ++_tx);
      final wire = await _seal(outgoing, 'client');
      if (!available) return;
      final nonce = SealedPayload.decode(base64Url.decode(wire)).nonce;
      final reply = await _http!.postOnionPacket(_path, wire,
          maxResponseBytes: _maxWire + 4096, circuitIsolation: _circuit);
      if (!available || reply.statusCode != 200)
        throw StateError('Sala indisponível.');
      final payload = await _open(
          SealedPayload.decode(base64Url.decode(reply.body)), 'host', nonce);
      if (payload.guest != _guest) throw const FormatException();
      _receive(payload);
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    response.statusCode = HttpStatus.notFound;
    try {
      if (!available ||
          request.method != 'POST' ||
          request.uri.path != _path ||
          request.contentLength < 54 ||
          request.contentLength > _maxWire) throw const FormatException();
      final body = BytesBuilder(copy: false);
      await for (final part in request.timeout(const Duration(seconds: 5))) {
        if (body.length + part.length > _maxWire) throw const FormatException();
        body.add(part);
      }
      final sealed = SealedPayload.decode(
          base64Url.decode(ascii.decode(body.takeBytes())));
      final payload = await _open(sealed, 'client');
      if (!available ||
          (_connectedGuest != null && _connectedGuest != payload.guest)) {
        throw const FormatException();
      }
      _receive(payload);
      _connectedGuest = payload.guest;
      final outgoing = _outgoing(payload.guest, ++_tx);
      final reply = await _seal(outgoing, 'host', sealed.nonce);
      if (!available) throw const FormatException();
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = ContentType.binary;
      response.contentLength = reply.length;
      response.write(reply);
    } catch (_) {
      // A resposta padrão é 404. Um socket interrompido encerra só este quadro.
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _outAudio.fillRange(0, _outAudio.length, 0);
    _outText = null;
    _key.destroy();
    unawaited(_events.close());
    unawaited(_server
            ?.close(force: true)
            .then<void>((_) {})
            .catchError((Object _) {}) ??
        Future.value());
    unawaited(_control?.close().catchError((Object _) {}) ?? Future.value());
  }
}

class _VoicePacket {
  const _VoicePacket(
      this.guest, this.sequence, this.audio, this.text, this.textId, this.ack);

  final String guest;
  final int sequence;
  final Uint8List audio;
  final String? text;
  final int textId;
  final int ack;

  factory _VoicePacket.parse(Object? raw) {
    if (raw is! List ||
        raw.length != 6 ||
        raw[0] is! String ||
        !OnionVoiceLink._token.hasMatch(raw[0] as String) ||
        raw[1] is! int ||
        (raw[1] as int) < 1 ||
        (raw[1] as int) > 100000 ||
        raw[4] is! int ||
        (raw[4] as int) < 0 ||
        (raw[4] as int) > 100000 ||
        raw[5] is! int ||
        (raw[5] as int) < 0 ||
        (raw[5] as int) > 100000 ||
        ((raw[4] == 0) != (raw[3] == null)) ||
        raw[2] is! String ||
        (raw[2] as String).length > 32000 ||
        (raw[3] != null &&
            (raw[3] is! String || utf8.encode(raw[3] as String).length > 900)))
      throw const FormatException();
    final audio = base64Decode(raw[2] as String);
    if (audio.length > OnionVoiceLink.maxAudioBytes || audio.length.isOdd) {
      throw const FormatException();
    }
    return _VoicePacket(raw[0] as String, raw[1] as int, audio,
        raw[3] as String?, raw[4] as int, raw[5] as int);
  }
}
