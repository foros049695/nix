import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:nix_transport/nix_transport.dart';

typedef TradeTorConnection = ({
  int socksPort,
  int controlPort,
  String cookiePath,
});

class PrivateTradeMessage {
  const PrivateTradeMessage(this.id, this.text, {required this.fromHost});

  final String id;
  final String text;
  final bool fromHost;
}

/// Sala efêmera de duas partes. O convite autentica ambas as pontas e usa
/// um serviço Onion dedicado, sem vincular a sessão às chaves do Nix ou XMR.
class PrivateTradeRoom extends ChangeNotifier {
  PrivateTradeRoom._({
    required this.isHost,
    required this.onion,
    required this.expiresAt,
    required SecretKeyData secret,
    required this.tor,
    required this.canUseTor,
    this.control,
    this.server,
  }) : _secret = secret {
    _expiryTimer = Timer(expiresAt.difference(DateTime.now()), close);
  }

  static const lifetime = Duration(minutes: 30);
  static const _invitePrefix = 'nix-trade-v1.';
  static const _path = '/trade-room-v1';
  static const _maxMessages = 80;
  static const _maxTextBytes = 1200;
  static const _maximumPacket = 300000;
  static final _messageIdPattern = RegExp(r'^[a-zA-Z0-9_-]{22}$');

  final bool isHost;
  final String onion;
  final DateTime expiresAt;
  final TradeTorConnection tor;
  final bool Function() canUseTor;
  final TorControlClient? control;
  final HttpServer? server;
  final SecretKeyData _secret;
  final _guestId = newMessageId();
  final _circuitIsolation = newMessageId();
  String? _pairedGuest;
  final _messages = <PrivateTradeMessage>[];
  late final Timer _expiryTimer;
  bool _closed = false;
  bool _disposed = false;
  bool _inFlight = false;

  bool get isClosed => _closed;
  bool get available =>
      !_closed && DateTime.now().isBefore(expiresAt) && canUseTor();

  List<PrivateTradeMessage> get messages => List.unmodifiable(_messages);

  String? get invitation => isHost && available && _pairedGuest == null
      ? '$_invitePrefix${base64Url.encode(utf8.encode(jsonEncode([
              onion,
              expiresAt.millisecondsSinceEpoch,
              base64Url.encode(_secret.bytes),
            ])))}'
      : null;

  Future<String> alias({required bool host}) async {
    final key = await _deriveKey(host ? 'host-alias' : 'guest-alias');
    try {
      final bytes = await key.extractBytes();
      return 'Parte-${bytes.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
    } finally {
      if (key is SecretKeyData) key.destroy();
    }
  }

  static Future<PrivateTradeRoom> host({
    required TradeTorConnection tor,
    required bool Function() canUseTor,
  }) async {
    if (!canUseTor()) throw StateError('Tor indisponível.');
    final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    TorControlClient? connection;
    try {
      connection = await TorControlClient.connect(port: tor.controlPort);
      await connection.authenticateCookieFile(tor.cookiePath);
      final service = await connection.addOnionV3(
        virtualPort: 80,
        targetPort: listener.port,
        discardPrivateKey: true,
      );
      final onion = '${service.serviceId}.onion';
      if (!TransportPolicy.isValidOnionV3Host(onion) || !canUseTor()) {
        throw StateError('Tor indisponível.');
      }
      final room = PrivateTradeRoom._(
        isHost: true,
        onion: onion,
        expiresAt: DateTime.now().add(lifetime),
        secret: SecretKeyData.random(length: 32),
        tor: tor,
        canUseTor: canUseTor,
        server: listener,
        control: connection,
      );
      listener.idleTimeout = const Duration(seconds: 10);
      listener.listen(room._serve);
      return room;
    } catch (_) {
      await listener.close(force: true);
      await connection?.close();
      rethrow;
    }
  }

  static PrivateTradeRoom join({
    required String invitation,
    required TradeTorConnection tor,
    required bool Function() canUseTor,
  }) {
    final input = invitation.trim();
    if (!canUseTor()) throw StateError('Tor indisponível.');
    if (!input.startsWith(_invitePrefix) || input.length > 600) {
      throw const FormatException('Convite inválido.');
    }
    final data = jsonDecode(
        utf8.decode(base64Url.decode(input.substring(_invitePrefix.length))));
    if (data is! List ||
        data.length != 3 ||
        data[0] is! String ||
        data[1] is! int ||
        data[2] is! String) {
      throw const FormatException('Convite inválido.');
    }
    final onion = data[0] as String;
    final expiryMs = data[1] as int;
    final now = DateTime.now();
    if (expiryMs <= now.millisecondsSinceEpoch ||
        expiryMs > now.add(lifetime).millisecondsSinceEpoch ||
        !TransportPolicy.isValidOnionV3Host(onion)) {
      throw const FormatException('Convite inválido ou expirado.');
    }
    final bytes = base64Url.decode(data[2] as String);
    if (bytes.length != 32) throw const FormatException('Convite inválido.');
    return PrivateTradeRoom._(
      isHost: false,
      onion: onion,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiryMs),
      secret: SecretKeyData(bytes, overwriteWhenDestroyed: true),
      tor: tor,
      canUseTor: canUseTor,
    );
  }

  Future<SecretKey> _deriveKey(String purpose) => Hkdf(
        hmac: Hmac.sha256(),
        outputLength: 32,
      ).deriveKey(
        secretKey: _secret,
        nonce: utf8.encode(
            'nix-trade-room-v1:$onion:${expiresAt.millisecondsSinceEpoch}'),
        info: utf8.encode(purpose),
      );

  Future<String> _seal(Object value, String purpose,
      [List<int> aad = const []]) async {
    final key = await _deriveKey(purpose);
    try {
      final packet = await SealedEnvelope.seal(
        key: key,
        plaintext: utf8.encode(jsonEncode(value)),
        aad: aad,
      );
      return base64Url.encode(packet.encode());
    } finally {
      if (key is SecretKeyData) key.destroy();
    }
  }

  Future<dynamic> _open(SealedPayload packet, String purpose,
      [List<int> aad = const []]) async {
    final key = await _deriveKey(purpose);
    try {
      final clear =
          await SealedEnvelope.open(key: key, payload: packet, aad: aad);
      return jsonDecode(utf8.decode(clear));
    } finally {
      if (key is SecretKeyData) key.destroy();
    }
  }

  static bool _validText(Object? text) =>
      text is String &&
      text.trim().isNotEmpty &&
      text.length <= _maxTextBytes &&
      !RegExp(r'[\x00-\x08\x0b-\x1f\x7f]').hasMatch(text) &&
      utf8.encode(text).length <= _maxTextBytes;

  Future<void> send(String text, {required String messageId}) async {
    final clean = text.trim();
    if (!_validText(clean) || !_messageIdPattern.hasMatch(messageId)) {
      throw const FormatException('Mensagem inválida.');
    }
    if (!available) throw StateError('Sala indisponível.');
    if (isHost) {
      _append(PrivateTradeMessage(messageId, clean, fromHost: true));
    } else {
      await _exchange({'id': messageId, 'text': clean});
    }
  }

  static String newMessageId() => base64Url
      .encode(
        SecretKeyData.random(length: 16).bytes,
      )
      .replaceAll('=', '');

  Future<void> poll() async {
    if (!isHost && !_inFlight) await _exchange(const {});
  }

  void _append(PrivateTradeMessage message) {
    if (_messages.any((entry) => entry.id == message.id)) return;
    if (_messages.length >= _maxMessages) throw StateError('Sala cheia.');
    _messages.add(message);
    if (!_disposed) notifyListeners();
  }

  Future<void> _exchange(Map<String, String> command) async {
    if (!available || _inFlight) throw StateError('Sala indisponível.');
    _inFlight = true;
    try {
      final packet =
          await _seal({'guest': _guestId, ...command}, 'guest-request');
      final nonce = SealedPayload.decode(base64Url.decode(packet)).nonce;
      if (!available) throw StateError('Sala indisponível.');
      final reply = await RelayClient(
        baseUri: Uri(scheme: 'http', host: onion),
        policy: TransportPolicy(socksPort: tor.socksPort),
      ).postOnionPacket(
        _path,
        packet,
        maxResponseBytes: _maximumPacket + 4096,
        circuitIsolation: _circuitIsolation,
      );
      if (reply.statusCode != 200 || !available)
        throw StateError('Sala indisponível.');
      final plain = await _open(
        SealedPayload.decode(base64Url.decode(reply.body)),
        'host-response',
        nonce,
      );
      if (plain is! List || plain.length > _maxMessages) {
        throw const FormatException('Histórico inválido.');
      }
      final entries = <PrivateTradeMessage>[];
      final ids = <String>{};
      for (final entry in plain) {
        if (entry is! List ||
            entry.length != 3 ||
            entry[0] is! String ||
            !_messageIdPattern.hasMatch(entry[0] as String) ||
            !ids.add(entry[0] as String) ||
            !_validText(entry[1]) ||
            entry[2] is! bool) {
          throw const FormatException('Mensagem recebida inválida.');
        }
        entries.add(PrivateTradeMessage(entry[0] as String, entry[1] as String,
            fromHost: entry[2] as bool));
      }
      if (!available) throw StateError('Sala indisponível.');
      if (command['id'] case final id?) {
        if (!entries.any((entry) =>
            entry.id == id && !entry.fromHost && entry.text == command['text']))
          throw StateError('Mensagem sem confirmação.');
      }
      if (entries.length == _messages.length) return;
      _messages
        ..clear()
        ..addAll(entries);
      if (!_disposed) notifyListeners();
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      if (!available ||
          request.method != 'POST' ||
          request.uri.path != _path ||
          request.contentLength < 54 ||
          request.contentLength > 4096) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final part in request.timeout(const Duration(seconds: 8))) {
        if (bytes.length + part.length > 4096) throw const FormatException();
        bytes.add(part);
      }
      final packet = SealedPayload.decode(
          base64Url.decode(utf8.decode(bytes.takeBytes())));
      final value = await _open(packet, 'guest-request');
      if (!available || value is! Map<String, dynamic>)
        throw const FormatException();
      final guest = value['guest'];
      if (guest is! String ||
          !_messageIdPattern.hasMatch(guest) ||
          (_pairedGuest != null && _pairedGuest != guest)) {
        throw const FormatException();
      }
      if (value.length != 1) {
        final id = value['id'];
        final text = value['text'];
        if (value.length != 3 ||
            id is! String ||
            !_messageIdPattern.hasMatch(id) ||
            !_validText(text)) throw const FormatException();
        _append(PrivateTradeMessage(id, text as String, fromHost: false));
      }
      if (_pairedGuest == null) {
        _pairedGuest = guest;
        if (!_disposed) notifyListeners();
      }
      final result = await _seal([
        for (final message in _messages)
          [message.id, message.text, message.fromHost],
      ], 'host-response', packet.nonce);
      if (!available) throw const FormatException();
      response.headers.contentType = ContentType.binary;
      response.contentLength = result.length;
      response.write(result);
    } catch (_) {
      response.statusCode = HttpStatus.notFound;
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _expiryTimer.cancel();
    _secret.destroy();
    _messages.clear();
    unawaited(server
            ?.close(force: true)
            .then<void>((_) {})
            .catchError((Object _) {}) ??
        Future.value());
    // A conexão ControlPort é dona do serviço não destacado.
    unawaited(control?.close().catchError((Object _) {}) ?? Future.value());
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    close();
    super.dispose();
  }
}
