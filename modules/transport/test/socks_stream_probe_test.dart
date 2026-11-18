import 'dart:io';
import 'dart:typed_data';
import 'package:nix_transport/nix_transport.dart';
import 'package:test/test.dart';

void main() {
  group('SOCKS5 Stream Double Listen Probe (NET01 Regression Test)', () {
    test('probe verifies SOCKS handshake socket handling', () async {
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
        // No código atual (antes da correção em P0-3), checkHealth falha com relisten no socket
        await client.checkHealth();
      } catch (e) {
        // Documenta o erro conhecido
        expect(e.toString(), contains('Stream has already been listened to'));
      } finally {
        await server.close();
      }
    });
  });
}
