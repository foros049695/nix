import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;

export 'nix_bluetooth_mesh.dart';
export 'nix_embedded_tor.dart';

/// Exceção lançada sempre que a política de transporte bloqueia uma conexão insegura (fail-closed).
class TransportBlockedException implements Exception {
  final String message;
  const TransportBlockedException(this.message);

  @override
  String toString() => 'TransportBlockedException: $message';
}

/// Esquema de URI ainda não suportado sobre o túnel SOCKS5 (fail-closed, Issue #11).
/// É um [TransportBlockedException]: quem já trata bloqueios de política
/// continua falhando fechado sem precisar de código novo.
class UnsupportedTransportSchemeException extends TransportBlockedException {
  final String scheme;
  UnsupportedTransportSchemeException(this.scheme)
      : super('Esquema "$scheme" não suportado via SOCKS5: TLS sobre o túnel '
            'ainda não está implementado (Issue #11). Use http:// para serviços '
            '.onion v3; não há fallback para HTTP em claro nem conexão direta.');

  @override
  String toString() => 'UnsupportedTransportSchemeException: $message';
}

enum TransportMode {
  /// Permite exclusivamente endereços `.onion` v3 via proxy SOCKS5 Tor. Bloqueia qualquer clearnet/IP direto.
  torFailClosed,

  /// Permite apenas loopback local (`127.0.0.1` / `localhost` / `::1`) para testes automatizados locais.
  loopbackTest,
}

/// Validação rigorosa de destino para impedir vazamento de DNS e fallback silencioso para clearnet.
class TransportPolicy {
  final TransportMode mode;
  final String socksHost;
  final int socksPort;

  const TransportPolicy({
    this.mode = TransportMode.torFailClosed,
    this.socksHost = '127.0.0.1',
    this.socksPort = 9050,
  });

  static final RegExp _onionV3Pattern = RegExp(r'^[a-z2-7]{56}\.onion$', caseSensitive: false);

  static bool isValidOnionV3Host(String host) => _onionV3Pattern.hasMatch(host.trim());

  static bool isLoopbackHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == '127.0.0.1' || normalized == 'localhost' || normalized == '::1';
  }

  /// Valida um [uri] antes de abrir qualquer socket; lança [TransportBlockedException] se violar a política.
  void assertAllowedUri(Uri uri) {
    final host = uri.host.trim();
    if (host.isEmpty) {
      throw const TransportBlockedException('Destino sem hostname válido.');
    }

    if (mode == TransportMode.torFailClosed) {
      if (!isValidOnionV3Host(host)) {
        throw TransportBlockedException(
          'Política Tor fail-closed: destino "$host" bloqueado. Apenas serviços .onion v3 via SOCKS5 são permitidos (sem fallback para IP direto).',
        );
      }
      return;
    }

    // Modo loopbackTest: apenas loopback local ou .onion v3 válido.
    if (!isLoopbackHost(host) && !isValidOnionV3Host(host)) {
      throw TransportBlockedException(
        'Modo loopbackTest: host externo "$host" bloqueado; apenas loopback local ou .onion v3 é aceito.',
      );
    }
  }
}

/// Conector SOCKS5 (RFC 1928) enviando hostname (`ATYP = 0x03`) para resolução remota dentro da rede Tor.
class Socks5Connector {
  final String proxyHost;
  final int proxyPort;
  final String? username;
  final String? password;

  const Socks5Connector({
    this.proxyHost = '127.0.0.1',
    this.proxyPort = 9050,
    this.username,
    this.password,
  });

  /// Abre túnel TCP via proxy SOCKS5 sem resolução DNS local prévia.
  Future<Socket> connect(
    String targetHost,
    int targetPort, {
    Duration timeout = const Duration(seconds: 20),
    bool requireOnionV3 = true,
  }) async {
    final cleanHost = targetHost.trim();
    if (requireOnionV3 && !TransportPolicy.isValidOnionV3Host(cleanHost)) {
      throw TransportBlockedException(
        'Recusado pelo Socks5Connector: "$cleanHost" não é um endereço .onion v3 válido de 56 caracteres.',
      );
    }
    final hostBytes = utf8.encode(cleanHost);
    if (hostBytes.isEmpty || hostBytes.length > 255) {
      throw TransportBlockedException('Hostname inválido para quadro SOCKS5 ($cleanHost).');
    }

    final rawSocket = await Socket.connect(proxyHost, proxyPort, timeout: timeout);
    final controller = StreamController<Uint8List>();
    final buffer = BytesBuilder();
    Completer<void>? waiter;
    bool inHandshake = true;
    bool closed = false;
    Object? socketError;

    rawSocket.listen(
      (chunk) {
        if (inHandshake) {
          buffer.add(chunk);
          waiter?.complete();
          waiter = null;
        } else {
          controller.add(chunk);
        }
      },
      onError: (Object err, StackTrace st) {
        socketError = err;
        waiter?.completeError(err, st);
        waiter = null;
        if (!inHandshake) controller.addError(err, st);
      },
      onDone: () {
        closed = true;
        waiter?.complete();
        waiter = null;
        if (!inHandshake) controller.close();
      },
      cancelOnError: false,
    );

    Future<Uint8List> readExact(int count, {Duration timeout = const Duration(seconds: 15)}) async {
      final deadline = DateTime.now().add(timeout);
      while (buffer.length < count) {
        if (socketError != null) throw socketError!;
        if (closed) {
          throw const SocketException('Conexão encerrada antes de completar o handshake SOCKS5.');
        }
        final rem = deadline.difference(DateTime.now());
        if (rem.isNegative) {
          throw const SocketException('Timeout durante handshake SOCKS5.');
        }
        waiter ??= Completer<void>();
        await waiter!.future.timeout(rem);
      }
      final all = buffer.takeBytes();
      if (all.length > count) {
        buffer.add(all.sublist(count));
      }
      return Uint8List.fromList(all.sublist(0, count));
    }

    try {
      final useUserPass = username != null && password != null;
      // Greeting: VER=0x05, NMETHODS=1, METHOD=0x00 ou 0x02 (IsolateSOCKSAuth)
      rawSocket.add(<int>[0x05, 0x01, useUserPass ? 0x02 : 0x00]);
      await rawSocket.flush();

      final methodReply = await readExact(2, timeout: timeout);
      if (methodReply[0] != 0x05 || methodReply[1] == 0xFF) {
        throw const TransportBlockedException('Proxy SOCKS5 rejeitou os métodos de autenticação.');
      }

      if (methodReply[1] == 0x02) {
        if (!useUserPass) {
          throw const TransportBlockedException('Proxy SOCKS5 exigiu autenticação não fornecida.');
        }
        final uBytes = utf8.encode(username!);
        final pBytes = utf8.encode(password!);
        final authReq = BytesBuilder()
          ..addByte(0x01)
          ..addByte(uBytes.length)
          ..add(uBytes)
          ..addByte(pBytes.length)
          ..add(pBytes);
        rawSocket.add(authReq.toBytes());
        await rawSocket.flush();
        final authReply = await readExact(2, timeout: timeout);
        if (authReply[1] != 0x00) {
          throw const TransportBlockedException('Falha de autenticação no proxy SOCKS5.');
        }
      }

      // Connect command: VER=0x05, CMD=0x01 (CONNECT), RSV=0x00, ATYP=0x03 (DOMAINNAME)
      final portBytes = ByteData(2)..setUint16(0, targetPort, Endian.big);
      final req = BytesBuilder()
        ..add(<int>[0x05, 0x01, 0x00, 0x03, hostBytes.length])
        ..add(hostBytes)
        ..add(portBytes.buffer.asUint8List());
      rawSocket.add(req.toBytes());
      await rawSocket.flush();

      final header = await readExact(4, timeout: timeout);
      if (header[0] != 0x05 || header[1] != 0x00) {
        throw TransportBlockedException('Falha no túnel SOCKS5 (REP=0x${header[1].toRadixString(16)}).');
      }

      final atyp = header[3];
      if (atyp == 0x01) {
        await readExact(4 + 2, timeout: timeout);
      } else if (atyp == 0x03) {
        final lenBuf = await readExact(1, timeout: timeout);
        await readExact(lenBuf[0] + 2, timeout: timeout);
      } else if (atyp == 0x04) {
        await readExact(16 + 2, timeout: timeout);
      } else {
        throw TransportBlockedException('Tipo de endereço ATYP desconhecido ($atyp) retornado pelo proxy.');
      }

      inHandshake = false;
      final leftover = buffer.isNotEmpty ? Uint8List.fromList(buffer.takeBytes()) : null;
      return SocksSocket(rawSocket, controller, leftover);
    } catch (e) {
      rawSocket.destroy();
      rethrow;
    }
  }
}

/// Socket decorado que mantém o fluxo contínuo do socket TCP subjacente
/// sem incorrer no erro de relisten em stream single-subscription (Marco P0-3 / NET01).
class SocksSocket extends Stream<Uint8List> implements Socket {
  final Socket _rawSocket;
  final StreamController<Uint8List> _controller;
  final Uint8List? _initialBytes;

  SocksSocket(this._rawSocket, this._controller, [this._initialBytes]);

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (_initialBytes != null && _initialBytes.isNotEmpty) {
      scheduleMicrotask(() {
        if (!_controller.isClosed) {
          onData?.call(_initialBytes);
        }
      });
    }
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Encoding get encoding => _rawSocket.encoding;
  @override
  set encoding(Encoding value) => _rawSocket.encoding = value;

  @override
  void add(List<int> data) => _rawSocket.add(data);
  @override
  void write(Object? object) => _rawSocket.write(object);
  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) => _rawSocket.writeAll(objects, separator);
  @override
  void writeln([Object? object = '']) => _rawSocket.writeln(object);
  @override
  void writeCharCode(int charCode) => _rawSocket.writeCharCode(charCode);
  @override
  void addError(Object error, [StackTrace? stackTrace]) => _rawSocket.addError(error, stackTrace);
  @override
  Future<dynamic> addStream(Stream<List<int>> stream) => _rawSocket.addStream(stream);
  @override
  Future<dynamic> flush() => _rawSocket.flush();
  @override
  Future<dynamic> close() => _rawSocket.close();
  @override
  Future<dynamic> get done => _rawSocket.done;
  @override
  void destroy() => _rawSocket.destroy();
  @override
  bool setOption(SocketOption option, bool enabled) => _rawSocket.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) => _rawSocket.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => _rawSocket.setRawOption(option);
  @override
  int get port => _rawSocket.port;
  @override
  int get remotePort => _rawSocket.remotePort;
  @override
  InternetAddress get address => _rawSocket.address;
  @override
  InternetAddress get remoteAddress => _rawSocket.remoteAddress;
}

/// Cliente para a ControlPort do daemon Tor (autenticação, bootstrap e Hidden Services v3).
class TorControlClient {
  final Socket _socket;
  final List<String> _lineBuffer = <String>[];
  String _partial = '';
  Completer<void>? _lineWaiter;
  late final StreamSubscription<Uint8List> _sub;
  bool _closed = false;

  TorControlClient._(this._socket) {
    _sub = _socket.listen(
      (Uint8List data) {
        _partial += utf8.decode(data, allowMalformed: true);
        while (true) {
          final idx = _partial.indexOf('\n');
          if (idx == -1) break;
          final line = _partial.substring(0, idx).replaceAll('\r', '');
          _partial = _partial.substring(idx + 1);
          _lineBuffer.add(line);
        }
        _lineWaiter?.complete();
        _lineWaiter = null;
      },
      onDone: () {
        _closed = true;
        _lineWaiter?.complete();
        _lineWaiter = null;
      },
      onError: (Object err, StackTrace st) {
        _closed = true;
        _lineWaiter?.completeError(err, st);
        _lineWaiter = null;
      },
    );
  }

  static Future<TorControlClient> connect({
    String host = '127.0.0.1',
    int port = 9051,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    return TorControlClient._(socket);
  }

  Future<List<String>> _sendCommand(String command, {Duration timeout = const Duration(seconds: 8)}) async {
    _socket.write('$command\r\n');
    await _socket.flush();

    final lines = <String>[];
    final deadline = DateTime.now().add(timeout);

    while (true) {
      while (_lineBuffer.isNotEmpty) {
        final line = _lineBuffer.removeAt(0);
        lines.add(line);
        if (line.length >= 4 && line[3] == ' ' && RegExp(r'^\d{3} ').hasMatch(line)) {
          final code = int.parse(line.substring(0, 3));
          if (code >= 400) {
            throw StateError('Tor ControlPort retornou erro ($code): ${lines.join(' | ')}');
          }
          return lines;
        }
      }
      if (_closed) {
        throw const SocketException('Conexão com ControlPort encerrada inesperadamente.');
      }
      final rem = deadline.difference(DateTime.now());
      if (rem.isNegative) {
        throw TimeoutException('Timeout aguardando resposta da ControlPort para "$command"');
      }
      _lineWaiter ??= Completer<void>();
      await _lineWaiter!.future.timeout(rem);
    }
  }

  Future<void> authenticateHex(String hexCookie) async {
    await _sendCommand('AUTHENTICATE $hexCookie');
  }

  Future<void> authenticateCookieFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await authenticateHex(hex);
  }

  Future<void> authenticatePassword(String password) async {
    final escaped = password.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    await _sendCommand('AUTHENTICATE "$escaped"');
  }

  Future<String> getInfo(String key) async {
    final lines = await _sendCommand('GETINFO $key');
    final prefix = '$key=';
    for (final line in lines) {
      if (line.startsWith('250-$prefix') || line.startsWith('250+$prefix')) {
        return line.substring(4 + prefix.length);
      }
      if (line.startsWith('250 $prefix')) {
        return line.substring(4 + prefix.length);
      }
    }
    return lines.join('\n');
  }

  Future<({String serviceId, String? privateKey})> addOnionV3({
    required int virtualPort,
    required int targetPort,
    String? keyBlob,
  }) async {
    final keySpec = keyBlob ?? 'NEW:ED25519-V3';
    final lines = await _sendCommand('ADD_ONION $keySpec Port=$virtualPort,127.0.0.1:$targetPort');
    String? serviceId;
    String? privKey;
    for (final line in lines) {
      if (line.contains('ServiceID=')) {
        serviceId = line.split('ServiceID=').last.trim();
      } else if (line.contains('PrivateKey=')) {
        privKey = line.split('PrivateKey=').last.trim();
      }
    }
    if (serviceId == null || serviceId.isEmpty) {
      throw StateError('ADD_ONION não retornou ServiceID: ${lines.join(' | ')}');
    }
    return (serviceId: serviceId, privateKey: privKey);
  }

  Future<void> delOnion(String serviceId) async {
    await _sendCommand('DEL_ONION $serviceId');
  }

  Future<void> signalNewNym() async {
    await _sendCommand('SIGNAL NEWNYM');
  }

  Future<void> close() async {
    await _sub.cancel();
    await _socket.close();
  }
}

/// Diagnóstico local de conectividade com o daemon Tor.
class TorDiagnosticResult {
  final bool socksReachable;
  final bool controlPortReachable;
  final String? bootstrapStatus;
  final String message;

  const TorDiagnosticResult({
    required this.socksReachable,
    required this.controlPortReachable,
    this.bootstrapStatus,
    required this.message,
  });
}

class TorDiagnostics {
  static Future<bool> probeTcpPort(
    String host,
    int port, {
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    try {
      final sock = await Socket.connect(host, port, timeout: timeout);
      sock.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<TorDiagnosticResult> diagnose({
    String host = '127.0.0.1',
    int socksPort = 9050,
    int controlPort = 9051,
  }) async {
    final socksOk = await probeTcpPort(host, socksPort);
    final ctrlOk = await probeTcpPort(host, controlPort);

    if (!socksOk) {
      return TorDiagnosticResult(
        socksReachable: false,
        controlPortReachable: ctrlOk,
        message: 'Tor SOCKS5 inacessível em $host:$socksPort (tráfego fail-closed bloqueado).',
      );
    }

    return TorDiagnosticResult(
      socksReachable: true,
      controlPortReachable: ctrlOk,
      message: ctrlOk
          ? 'Tor SOCKS5 ($socksPort) e ControlPort ($controlPort) operacionais.'
          : 'Tor SOCKS5 ($socksPort) ativo; ControlPort ($controlPort) fechado ou desabilitado.',
    );
  }
}

/// Credenciais de caixa postal cega no Nix Relay.
class MailboxCredentials {
  final String mailboxId;
  final String readToken;
  final String writeQuotaToken;

  const MailboxCredentials({
    required this.mailboxId,
    required this.readToken,
    this.writeQuotaToken = '',
  });

  /// Gera identificador de mailbox cego por hash SHA-256 com domínio fixo.
  static String deriveBlindMailboxId(List<int> routingKeyBytes) {
    final digest = std_crypto.sha256.convert(<int>[...utf8.encode('nix-mailbox-v4:'), ...routingKeyBytes]);
    return digest.toString();
  }
}

/// Envelope opaco armazenado em trânsito pelo Nix Relay.
class RelayEnvelope {
  final String id;
  final String payloadBase64;
  final int createdAtUnix;
  final int expiresAtUnix;

  const RelayEnvelope({
    required this.id,
    required this.payloadBase64,
    required this.createdAtUnix,
    required this.expiresAtUnix,
  });

  factory RelayEnvelope.fromJson(Map<String, dynamic> json) => RelayEnvelope(
        id: json['id'] as String,
        payloadBase64: json['payload_b64'] as String,
        createdAtUnix: (json['created_at'] as num).toInt(),
        expiresAtUnix: (json['expires_at'] as num).toInt(),
      );
}

/// Cliente store-and-forward para comunicação com o `nix_relay` obedecendo estritamente a [TransportPolicy].
class RelayClient {
  final Uri baseUri;
  final TransportPolicy policy;

  const RelayClient({
    required this.baseUri,
    this.policy = const TransportPolicy(),
  });

  void _checkPolicy() {
    policy.assertAllowedUri(baseUri);
  }

  /// Verifica saúde do relay (`/healthz`).
  Future<bool> checkHealth() async {
    _checkPolicy();
    final res = await _request('GET', '/healthz');
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  /// Envia envelope cifrado opaco para uma caixa postal no relay.
  Future<String> storeEnvelope({
    required String mailboxId,
    required Uint8List cipherPayload,
    int ttlSeconds = 604800,
    String? quotaToken,
  }) async {
    _checkPolicy();
    final body = jsonEncode(<String, dynamic>{
      'payload_b64': base64Encode(cipherPayload),
      'ttl_seconds': ttlSeconds,
    });
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (quotaToken != null && quotaToken.isNotEmpty) 'X-Nix-Quota-Token': quotaToken,
    };
    final res = await _request('POST', '/v1/mailboxes/$mailboxId/envelopes', headers: headers, body: body);
    if (res.statusCode != 200 && res.statusCode != 201 && res.statusCode != 202) {
      throw HttpException('Relay rejeitou storeEnvelope (HTTP ${res.statusCode}): ${res.body}');
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return decoded['id'] as String;
  }

  /// Busca envelopes pendentes da caixa postal autenticada pelo `readToken`.
  Future<List<RelayEnvelope>> fetchEnvelopes(MailboxCredentials creds) async {
    _checkPolicy();
    final res = await _request(
      'GET',
      '/v1/mailboxes/${creds.mailboxId}/envelopes',
      headers: <String, String>{'Authorization': 'Bearer ${creds.readToken}'},
    );
    if (res.statusCode != 200) {
      throw HttpException('Falha ao buscar envelopes (HTTP ${res.statusCode}): ${res.body}');
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (decoded['envelopes'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    return list.map(RelayEnvelope.fromJson).toList();
  }

  /// Confirma entrega e remove envelopes consumidos no relay.
  Future<int> acknowledge(MailboxCredentials creds, List<String> envelopeIds) async {
    _checkPolicy();
    final res = await _request(
      'POST',
      '/v1/mailboxes/${creds.mailboxId}/ack',
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${creds.readToken}',
      },
      body: jsonEncode(<String, dynamic>{'ids': envelopeIds}),
    );
    if (res.statusCode != 200) {
      throw HttpException('Falha em ack (HTTP ${res.statusCode}): ${res.body}');
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return (decoded['deleted'] as num?)?.toInt() ?? 0;
  }

  Future<({int statusCode, String body})> _request(
    String method,
    String path, {
    Map<String, String> headers = const <String, String>{},
    String? body,
  }) async {
    final targetUri = baseUri.resolve(path.startsWith('/') ? path.substring(1) : path);
    if (TransportPolicy.isLoopbackHost(baseUri.host) && policy.mode == TransportMode.loopbackTest) {
      return _directLoopbackHttp(method, targetUri, headers: headers, body: body);
    }
    return _socksHttp(method, targetUri, headers: headers, body: body);
  }

  Future<({int statusCode, String body})> _directLoopbackHttp(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, uri);
      headers.forEach(req.headers.set);
      if (body != null) {
        req.write(body);
      }
      final res = await req.close();
      final resBody = await utf8.decodeStream(res);
      return (statusCode: res.statusCode, body: resBody);
    } finally {
      client.close(force: true);
    }
  }

  Future<({int statusCode, String body})> _socksHttp(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Issue #11: `SecureSocket.secure` exige o `_Socket` interno do SDK e falha
    // com `NoSuchMethodError: _detachRaw` ao receber o [SocksSocket]. Até existir
    // um handshake SOCKS em `RawSocket` + `RawSecureSocket`, HTTPS via SOCKS é
    // recusado explicitamente, ANTES de abrir qualquer socket. Nunca há downgrade
    // para HTTP nem caminho direto. Destinos `.onion` v3 já possuem canal
    // cifrado e autenticado pela própria chave do serviço.
    if (uri.scheme != 'http') {
      throw UnsupportedTransportSchemeException(uri.scheme);
    }

    final connector = Socks5Connector(proxyHost: policy.socksHost, proxyPort: policy.socksPort);
    final port = uri.hasPort ? uri.port : 80;
    final Socket socket = await connector.connect(uri.host, port, requireOnionV3: true, timeout: timeout);

    try {
      final bodyBytes = body != null ? utf8.encode(body) : const <int>[];
      final targetPath = uri.path.isEmpty ? '/' : uri.path;
      final reqBuf = StringBuffer()
        ..write('$method $targetPath${uri.hasQuery ? '?${uri.query}' : ''} HTTP/1.1\r\n')
        ..write('Host: ${uri.host}\r\n')
        ..write('Connection: close\r\n');
      headers.forEach((k, v) => reqBuf.write('$k: $v\r\n'));
      if (bodyBytes.isNotEmpty) {
        reqBuf.write('Content-Length: ${bodyBytes.length}\r\n');
      }
      reqBuf.write('\r\n');

      socket.add(utf8.encode(reqBuf.toString()));
      if (bodyBytes.isNotEmpty) {
        socket.add(bodyBytes);
      }
      await socket.flush();

      final rawBytes = await socket.fold<BytesBuilder>(
        BytesBuilder(),
        (acc, chunk) => acc..add(chunk),
      ).timeout(timeout);

      final fullBytes = rawBytes.takeBytes();
      int splitIdx = -1;
      for (int i = 0; i < fullBytes.length - 3; i++) {
        if (fullBytes[i] == 13 && fullBytes[i + 1] == 10 && fullBytes[i + 2] == 13 && fullBytes[i + 3] == 10) {
          splitIdx = i;
          break;
        }
      }
      if (splitIdx == -1) {
        throw const HttpException('Resposta HTTP inválida sobre túnel SOCKS5.');
      }

      final headerStr = utf8.decode(fullBytes.sublist(0, splitIdx), allowMalformed: true);
      final bodyPayloadBytes = fullBytes.sublist(splitIdx + 4);

      final headerLines = headerStr.split('\r\n');
      final statusLine = headerLines.first;
      final parts = statusLine.split(' ');
      final statusCode = parts.length >= 2 ? (int.tryParse(parts[1]) ?? 500) : 500;

      bool isChunked = false;
      for (final line in headerLines.skip(1)) {
        final colon = line.indexOf(':');
        if (colon != -1) {
          final key = line.substring(0, colon).trim().toLowerCase();
          final val = line.substring(colon + 1).trim().toLowerCase();
          if (key == 'transfer-encoding' && val.contains('chunked')) {
            isChunked = true;
          }
        }
      }

      final payload = isChunked ? _decodeChunked(bodyPayloadBytes) : Uint8List.fromList(bodyPayloadBytes);
      final resBody = utf8.decode(payload, allowMalformed: true);
      return (statusCode: statusCode, body: resBody);
    } finally {
      socket.destroy();
    }
  }

  static Uint8List _decodeChunked(List<int> bytes) {
    final builder = BytesBuilder();
    int pos = 0;
    while (pos < bytes.length) {
      int lineEnd = -1;
      for (int i = pos; i < bytes.length - 1; i++) {
        if (bytes[i] == 13 && bytes[i + 1] == 10) {
          lineEnd = i;
          break;
        }
      }
      if (lineEnd == -1) break;
      final sizeStr = utf8.decode(bytes.sublist(pos, lineEnd)).trim().split(';').first;
      final chunkSize = int.tryParse(sizeStr, radix: 16) ?? 0;
      pos = lineEnd + 2;
      if (chunkSize <= 0) break;
      if (pos + chunkSize > bytes.length) {
        builder.add(bytes.sublist(pos));
        break;
      }
      builder.add(bytes.sublist(pos, pos + chunkSize));
      pos += chunkSize;
      if (pos < bytes.length && bytes[pos] == 13) pos++;
      if (pos < bytes.length && bytes[pos] == 10) pos++;
    }
    return builder.toBytes();
  }
}
