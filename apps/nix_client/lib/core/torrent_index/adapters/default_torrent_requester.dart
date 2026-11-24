import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:nix_transport/nix_transport.dart';
import '../../network/transport_profile.dart';
import '../../security/fail_closed_http_overrides.dart';

/// Requester HTTP resiliente e soberano para indexadores do Nix Torrent Index.
///
/// Respeita o perfil de transporte ativo (Perfil A: Onion v3, Perfil B: Tor SOCKS5,
/// Perfil C: SOCKS5 Custom, Perfil D: Direto HTTPS).
///
/// REGRAS DE SEGURANÇA INEGOCIÁVEIS:
/// 1. Zero fallback silencioso: se Tor / SOCKS5 falhar, a operação é bloqueada com erro explícito.
/// 2. Conexão direta clearnet APENAS quando explicitamente configurada (Perfil D) ou autorizada.
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
  final profile = GlobalTransportRegistry.current.getProfile(TransportModule.torrents);

  // Perfil A: Requer estritamente .onion v3
  if (profile == TransportProfileType.onionV3Strict) {
    if (!uri.host.toLowerCase().endsWith('.onion')) {
      throw TransportBlockedException(
        '[Perfil A: Onion v3 Estrito] Destino ${uri.host} bloqueado. '
        'Este perfil aceita exclusivamente serviços ocultos .onion.',
      );
    }
  }

  final allowDirect = preferClearnet || profile == TransportProfileType.directHttps;

  // 1. SOCKS5 Isolado (Tor ou Customizado)
  if (!allowDirect) {
    final isCustom = profile == TransportProfileType.customSocks5;
    final proxyHost = isCustom ? GlobalTransportRegistry.current.customSocksHost : '127.0.0.1';
    final proxyPort = isCustom ? GlobalTransportRegistry.current.customSocksPort : socksPort;
    final username = isCustom ? GlobalTransportRegistry.current.customSocksUsername : 'nix_indexer';
    final password = isCustom ? GlobalTransportRegistry.current.customSocksPassword : 'nix_indexer';

    try {
      final connector = Socks5Connector(
        proxyHost: proxyHost,
        proxyPort: proxyPort,
        username: username,
        password: password,
      );
      final res = await connector.httpRequest(
        method,
        uri,
        headers: headers ?? const {},
        body: body,
        requireOnionV3: profile == TransportProfileType.onionV3Strict,
        timeout: effectiveTimeout,
      );
      return (statusCode: res.statusCode, body: res.body);
    } catch (e) {
      // FAIL-CLOSED: Jamais cai silenciosamente para Clearnet quando o usuário optou por Tor/SOCKS5
      throw TransportBlockedException(
        '[${profile.shortLabel}] Falha ao consultar indexador ${uri.host} via túnel SOCKS5: $e. '
        'Fallback silencioso para Clearnet desativado por política de fail-closed.',
      );
    }
  }

  // 2. Consulta fora da rede Tor (Clearnet) - Somente quando expressamente autorizado
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
