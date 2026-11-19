import 'dart:io';
import 'package:nix_transport/nix_transport.dart'
    show TransportBlockedException, TransportPolicy;

/// Firewall HTTP global em modo Fail-Closed (Zero Vazamento de Rede Doméstica).
///
/// Quando instalado via [install], intercepta todas as criações de [HttpClient]
/// no processo Dart/Flutter e bloqueia qualquer tentativa de conexão HTTP/HTTPS
/// direta para hosts externos (fora de loopback `127.0.0.1` / `localhost` / `::1`).
///
/// Todo tráfego externo legítimo do Projeto Nix deve atravessar exclusivamente
/// sockets SOCKS5 do daemon Tor embutido (`Socks5TcpTransport` / `Socks5HttpClient`).
class NixFailClosedHttpOverrides extends HttpOverrides {
  final HttpOverrides? _previous;
  static bool _installedGlobally = false;

  NixFailClosedHttpOverrides([this._previous]);

  static bool get isInstalled =>
      _installedGlobally || HttpOverrides.current is NixFailClosedHttpOverrides;

  /// Instala o firewall global fail-closed no processo atual.
  static void install() {
    if (HttpOverrides.current is NixFailClosedHttpOverrides) {
      _installedGlobally = true;
      return;
    }
    HttpOverrides.global = NixFailClosedHttpOverrides(HttpOverrides.current);
    _installedGlobally = true;
  }

  /// Executa um bloco com uma exceção temporária estritamente para transferência
  /// offline P2P em LAN local (ex: compartilhamento de APK via hotspot sem internet).
  static Future<T> runWithExplicitOfflineLanPeer<T>({
    required String allowedLanHost,
    required Future<T> Function() action,
  }) {
    final normalized = allowedLanHost.trim().toLowerCase();
    return HttpOverrides.runWithHttpOverrides(
      action,
      _ScopedLanPeerHttpOverrides(normalized),
    );
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final prev = _previous;
    final inner = prev != null
        ? prev.createHttpClient(context)
        : super.createHttpClient(context);
    return _FailClosedHttpClient(inner, allowedHosts: const {});
  }
}

class _ScopedLanPeerHttpOverrides extends HttpOverrides {
  final String allowedLanHost;
  _ScopedLanPeerHttpOverrides(this.allowedLanHost);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final inner = super.createHttpClient(context);
    return _FailClosedHttpClient(inner, allowedHosts: {allowedLanHost});
  }
}

class _FailClosedHttpClient implements HttpClient {
  final HttpClient _inner;
  final Set<String> _allowedHosts;

  _FailClosedHttpClient(this._inner, {required Set<String> allowedHosts})
      : _allowedHosts = allowedHosts;

  void _assertHostAllowed(String host, int port) {
    final clean = host.trim().toLowerCase();
    if (TransportPolicy.isLoopbackHost(clean)) return;
    if (_allowedHosts.contains(clean)) return;
    throw TransportBlockedException(
      '[Fail-Closed] Conexão direta pela rede doméstica bloqueada para "$host:$port". '
      'Todo tráfego externo do Projeto Nix exige túnel Tor Onion v3.',
    );
  }

  void _assertUriAllowed(Uri url) => _assertHostAllowed(url.host, url.port);

  @override
  Future<HttpClientRequest> open(
      String method, String host, int port, String path) {
    _assertHostAllowed(host, port);
    return _inner.open(method, host, port, path);
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    _assertUriAllowed(url);
    return _inner.openUrl(method, url);
  }

  @override
  Future<HttpClientRequest> get(String host, int port, String path) {
    _assertHostAllowed(host, port);
    return _inner.get(host, port, path);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    _assertUriAllowed(url);
    return _inner.getUrl(url);
  }

  @override
  Future<HttpClientRequest> post(String host, int port, String path) {
    _assertHostAllowed(host, port);
    return _inner.post(host, port, path);
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    _assertUriAllowed(url);
    return _inner.postUrl(url);
  }

  @override
  Future<HttpClientRequest> put(String host, int port, String path) {
    _assertHostAllowed(host, port);
    return _inner.put(host, port, path);
  }

  @override
  Future<HttpClientRequest> putUrl(Uri url) {
    _assertUriAllowed(url);
    return _inner.putUrl(url);
  }

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) {
    _assertHostAllowed(host, port);
    return _inner.delete(host, port, path);
  }

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) {
    _assertUriAllowed(url);
    return _inner.deleteUrl(url);
  }

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) {
    _assertHostAllowed(host, port);
    return _inner.patch(host, port, path);
  }

  @override
  Future<HttpClientRequest> patchUrl(Uri url) {
    _assertUriAllowed(url);
    return _inner.patchUrl(url);
  }

  @override
  Future<HttpClientRequest> head(String host, int port, String path) {
    _assertHostAllowed(host, port);
    return _inner.head(host, port, path);
  }

  @override
  Future<HttpClientRequest> headUrl(Uri url) {
    _assertUriAllowed(url);
    return _inner.headUrl(url);
  }

  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) =>
      _inner.maxConnectionsPerHost = value;

  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  void addCredentials(
          Uri url, String realm, HttpClientCredentials credentials) =>
      _inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(String host, int port, String realm,
          HttpClientCredentials credentials) =>
      _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  set authenticate(
          Future<bool> Function(Uri url, String scheme, String? realm)? f) =>
      _inner.authenticate = f;

  @override
  set authenticateProxy(
          Future<bool> Function(
                  String host, int port, String scheme, String? realm)?
              f) =>
      _inner.authenticateProxy = f;

  @override
  set badCertificateCallback(
          bool Function(X509Certificate cert, String host, int port)?
              callback) =>
      _inner.badCertificateCallback = callback;

  @override
  void close({bool force = false}) => _inner.close(force: force);

  @override
  set connectionFactory(
          Future<ConnectionTask<Socket>> Function(
                  Uri url, String? proxyHost, int? proxyPort)?
              f) =>
      _inner.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;
}
