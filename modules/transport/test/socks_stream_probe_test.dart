import 'dart:io';
import 'dart:typed_data';
import 'package:nix_transport/nix_transport.dart';
import 'package:test/test.dart';

void main() {
  group('SOCKS5 Stream Double Listen Resolution (NET01 / NET02 / Marco P0-3)', () {
    test('checkHealth succeeds over SOCKS tunnel without relisten error', () async {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      server.listen((s) {
        int step = 0;
        s.listen((Uint8List b) {
          if (step++ == 0) {
            s.add([5, 0]); // NO AUTHENTICATION REQUIRED
          } else if (step == 2) {
            s.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 80]); // SUCCESS CONNECT
          } else {
            s.write('HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}');
            s.close();
          }
        });
      });

      final client = RelayClient(
        baseUri: Uri.parse('http://${'a' * 56}.onion/'),
        policy: TransportPolicy(socksPort: server.port),
      );

      try {
        final ok = await client.checkHealth();
        expect(ok, isTrue);
      } finally {
        await server.close();
      }
    });

    test('decodes chunked transfer encoding responses accurately', () async {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      server.listen((s) {
        int step = 0;
        s.listen((Uint8List b) {
          if (step++ == 0) {
            s.add([5, 0]);
          } else if (step == 2) {
            s.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 80]);
          } else {
            s.write(
              'HTTP/1.1 200 OK\r\n'
              'Transfer-Encoding: chunked\r\n'
              'Connection: close\r\n\r\n'
              '7\r\n'
              '{"id": \r\n'
              '5\r\n'
              '"ok"}\r\n'
              '0\r\n\r\n',
            );
            s.close();
          }
        });
      });

      final client = RelayClient(
        baseUri: Uri.parse('http://${'b' * 56}.onion/'),
        policy: TransportPolicy(socksPort: server.port),
      );

      try {
        final ok = await client.checkHealth();
        expect(ok, isTrue);
      } finally {
        await server.close();
      }
    });
  });
}
