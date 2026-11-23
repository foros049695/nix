import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:nix_transport/nix_transport.dart';
import '../../security/fail_closed_http_overrides.dart';

/// Requester HTTP resiliente para indexadores do Nix Torrent Index.
///
/// Tenta primeiramente consultar via túnel SOCKS5 do Tor (Onion v3 / isolado).
/// Caso o daemon Tor esteja indisponível, em bootstrap ou a conexão falhe,
/// abre automaticamente a opção de consulta fora da rede Tor (Clearnet)
/// conforme a autorização expressa do usuário.
Future<({int statusCode, String body})> defaultTorrentHttpRequester(
  String method,
  Uri uri, {
  Map<String, String>? headers,
  String? body,
  Duration? timeout,
  int socksPort = 9050,
  bool preferClearnet = false,
}) async {
  final effectiveTimeout = timeout ?? const Duration(seconds: 20);

  // 1. Se não preferir clearnet, tenta via SOCKS5 do Tor primeiro
  if (!preferClearnet) {
    try {
      final connector = Socks5Connector(
        proxyHost: '127.0.0.1',
        proxyPort: socksPort,
        username: 'nix_indexer',
        password: 'nix_indexer',
      );
      final res = await connector.httpRequest(
        method,
        uri,
        headers: headers ?? const {},
        body: body,
        requireOnionV3: false,
        timeout: effectiveTimeout,
      );
      if (res.statusCode >= 200 && res.statusCode < 500) {
        return (statusCode: res.statusCode, body: res.body);
      }
    } catch (_) {
      // Falha na rota Tor: continua para fallback fora da rede
    }
  }

  // 2. Consulta fora da rede Tor (Clearnet)
  return await NixFailClosedHttpOverrides.runWithExplicitClearnetDownload(action: () async {
    final client = HttpClient();
    client.connectionTimeout = effectiveTimeout;
    try {
      final req = await client.openUrl(method, uri).timeout(effectiveTimeout);
      headers?.forEach((k, v) => req.headers.set(k, v));
      if (headers == null || !headers.containsKey('User-Agent')) {
        req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) NixTorrentIndex/1.0');
      }
      if (body != null) req.write(body);
      final resp = await req.close().timeout(effectiveTimeout);
      final respBody = await utf8.decodeStream(resp);
      return (statusCode: resp.statusCode, body: respBody);
    } finally {
      client.close(force: true);
    }
  });
}
