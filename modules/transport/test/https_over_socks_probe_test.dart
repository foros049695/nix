import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nix_transport/nix_transport.dart';
import 'package:test/test.dart';

// Issue #11: HTTPS sobre SOCKS5 deve funcionar via RawSocket -> RawSecureSocket
// sem `_detachRaw`, falhar fechado em certificado inválido e rejeitar esquemas
// não suportados antes de abrir socket.
void main() {
  const onion =
      'abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuvwx.onion';

  late Directory tempDir;
  late String certPath;
  late String keyPath;
  late SecurityContext serverTls;
  late SecurityContext trustedClientTls;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('nix_https_socks_');
    certPath = '${tempDir.path}/cert.pem';
    keyPath = '${tempDir.path}/key.pem';

    final res = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-keyout',
      keyPath,
      '-out',
      certPath,
      '-days',
      '1',
      '-nodes',
      '-subj',
      '/CN=$onion',
      '-addext',
      'subjectAltName=DNS:$onion',
    ]);
    if (res.exitCode != 0) {
      fail('openssl falhou ao gerar certificado de teste: ${res.stderr}');
    }

    serverTls = SecurityContext()
      ..useCertificateChain(certPath)
      ..usePrivateKey(keyPath);
    trustedClientTls = SecurityContext()..setTrustedCertificates(certPath);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('https:// sobre SOCKS5 completa handshake TLS real e responde HTTP 200',
      () async {
    final httpsServer =
        await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverTls);
    httpsServer.listen((HttpRequest req) async {
      await req.drain<void>();
      if (req.uri.path == '/healthz') {
        req.response.statusCode = HttpStatus.ok;
        req.response.write('{"status":"ok"}');
      } else {
        req.response.statusCode = HttpStatus.accepted;
        req.response.write('{"id":"env_tls_1"}');
      }
      await req.response.close();
    });

    final socksProxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    String? requestedAtypHost;
    int? requestedPort;

    socksProxy.listen((Socket clientSock) async {
      Socket? upstream;
      try {
        final buf = <int>[];
        bool tunneling = false;
        Completer<void>? waiter;

        final sub = clientSock.listen(
          (chunk) {
            final up = upstream;
            if (tunneling && up != null) {
              up.add(chunk);
              return;
            }
            buf.addAll(chunk);
            if (waiter != null && !waiter!.isCompleted) waiter!.complete();
          },
          onDone: () {
            if (waiter != null && !waiter!.isCompleted) waiter!.complete();
            upstream?.close();
          },
          onError: (_) {
            if (waiter != null && !waiter!.isCompleted) waiter!.complete();
            upstream?.destroy();
          },
          cancelOnError: true,
        );

        Future<Uint8List> readExact(int n) async {
          while (buf.length < n) {
            waiter = Completer<void>();
            await waiter!.future;
          }
          final out = Uint8List.fromList(buf.sublist(0, n));
          buf.removeRange(0, n);
          return out;
        }

        final greet = await readExact(3);
        expect(greet[0], 5);
        clientSock.add([5, 0]);
        await clientSock.flush();

        final hdr = await readExact(5); // VER, CMD, RSV, ATYP=3, LEN
        expect(hdr[0], 5);
        expect(hdr[1], 1);
        expect(hdr[3], 3); // ATYP 0x03 (remote DNS, sem DNS leak local)
        final hostLen = hdr[4];
        final hostBytes = await readExact(hostLen);
        final portBytes = await readExact(2);
        requestedAtypHost = String.fromCharCodes(hostBytes);
        requestedPort = (portBytes[0] << 8) | portBytes[1];

        final up =
            await Socket.connect(InternetAddress.loopbackIPv4, httpsServer.port);
        upstream = up;

        tunneling = true;
        clientSock.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 0]);
        await clientSock.flush();

        if (buf.isNotEmpty) {
          up.add(buf);
          buf.clear();
        }
        final upSub = up.listen(
          clientSock.add,
          onDone: () => clientSock.close(),
          onError: (_) => clientSock.destroy(),
        );
        await Future.wait([
          upSub.asFuture<void>().catchError((_) {}),
          sub.asFuture<void>().catchError((_) {}),
        ]);
      } catch (_) {
        clientSock.destroy();
        upstream?.destroy();
      }
    });

    try {
      final client = RelayClient(
        baseUri: Uri.parse('https://$onion:${httpsServer.port}/'),
        policy: TransportPolicy(socksPort: socksProxy.port),
        tlsContext: trustedClientTls,
      );

      final healthy = await client.checkHealth().timeout(const Duration(seconds: 2));
      expect(healthy, isTrue);
      expect(requestedAtypHost, equals(onion));
      expect(requestedPort, equals(httpsServer.port));

      final envId = await client
          .storeEnvelope(
            mailboxId: 'mbox_tls',
            cipherPayload: Uint8List.fromList([1, 2, 3, 4]),
          )
          .timeout(const Duration(seconds: 2));
      expect(envId, equals('env_tls_1'));
    } finally {
      await socksProxy.close();
      await httpsServer.close(force: true);
    }
  });

  test('https:// sobre SOCKS5 falha fechado com certificado não confiável',
      () async {
    final httpsServer =
        await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverTls);
    httpsServer.listen((HttpRequest req) async {
      req.response.write('should-not-reach');
      await req.response.close();
    });

    final socksProxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    socksProxy.listen((Socket clientSock) async {
      Socket? upstream;
      try {
        final buf = <int>[];
        bool tunneling = false;
        Completer<void>? waiter;
        final sub = clientSock.listen(
          (c) {
            final up = upstream;
            if (tunneling && up != null) {
              up.add(c);
              return;
            }
            buf.addAll(c);
            if (waiter != null && !waiter!.isCompleted) waiter!.complete();
          },
          onDone: () => upstream?.close(),
          onError: (_) => upstream?.destroy(),
        );
        Future<Uint8List> readExact(int n) async {
          while (buf.length < n) {
            waiter = Completer<void>();
            await waiter!.future;
          }
          final out = Uint8List.fromList(buf.sublist(0, n));
          buf.removeRange(0, n);
          return out;
        }

        await readExact(3);
        clientSock.add([5, 0]);
        await clientSock.flush();
        final hdr = await readExact(5);
        await readExact(hdr[4] + 2);
        final up =
            await Socket.connect(InternetAddress.loopbackIPv4, httpsServer.port);
        upstream = up;
        tunneling = true;
        clientSock.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 0]);
        await clientSock.flush();
        if (buf.isNotEmpty) {
          up.add(buf);
          buf.clear();
        }
        final upSub = up.listen(
          clientSock.add,
          onDone: () => clientSock.close(),
          onError: (_) => clientSock.destroy(),
        );
        await Future.wait([
          upSub.asFuture<void>().catchError((_) {}),
          sub.asFuture<void>().catchError((_) {}),
        ]);
      } catch (_) {
        clientSock.destroy();
        upstream?.destroy();
      }
    });

    try {
      // Sem trustedClientTls -> deve rejeitar o certificado self-signed!
      final strictClient = RelayClient(
        baseUri: Uri.parse('https://$onion:${httpsServer.port}/'),
        policy: TransportPolicy(socksPort: socksProxy.port),
      );

      Object? caught;
      try {
        await strictClient.checkHealth();
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<HandshakeException>());
      expect(caught, isNot(isA<NoSuchMethodError>()));
    } finally {
      await socksProxy.close();
      await httpsServer.close(force: true);
    }
  });

  test('esquema não suportado (ex: ftp://) falha fechado sem abrir socket',
      () async {
    int connections = 0;
    final fakeSocks = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    fakeSocks.listen((s) {
      connections++;
      s.destroy();
    });

    try {
      final client = RelayClient(
        baseUri: Uri.parse('ftp://$onion/'),
        policy: TransportPolicy(socksPort: fakeSocks.port),
      );
      await expectLater(
        client.checkHealth(),
        throwsA(isA<UnsupportedTransportSchemeException>()
            .having((e) => e.scheme, 'scheme', 'ftp')),
      );
      expect(connections, 0);
    } finally {
      await fakeSocks.close();
    }
  });
}
