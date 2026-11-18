import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:nix_transport/nix_transport.dart';
import 'package:test/test.dart';

void main() {
  group('TransportPolicy (Fail-Closed)', () {
    test('allows valid 56-char .onion v3 host and blocks clearnet IPs/domains', () {
      const policy = TransportPolicy(mode: TransportMode.torFailClosed);
      const validOnion = 'gpoun4vo5v5h3cmcfdxtudm3nlzxri3qzjd7fhbvy6oep2ap67g4qvyd.onion';

      expect(TransportPolicy.isValidOnionV3Host(validOnion), isTrue);
      expect(TransportPolicy.isValidOnionV3Host('example.com'), isFalse);
      expect(TransportPolicy.isValidOnionV3Host('127.0.0.1'), isFalse);

      expect(() => policy.assertAllowedUri(Uri.parse('http://$validOnion:8080/healthz')), returnsNormally);
      expect(
        () => policy.assertAllowedUri(Uri.parse('https://github.com/tor')),
        throwsA(isA<TransportBlockedException>()),
      );
      expect(
        () => policy.assertAllowedUri(Uri.parse('http://198.51.100.10:8080')),
        throwsA(isA<TransportBlockedException>()),
      );
    });
  });

  group('Socks5Connector & Mock SOCKS5 Server', () {
    test('performs RFC 1928 handshake with DOMAINNAME ATYP 0x03 without local DNS leak', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      final capturedHostCompleter = Completer<String>();

      unawaited(() async {
        final client = await server.first;
        final it = StreamIterator<Uint8List>(client);
        expect(await it.moveNext(), isTrue);
        final firstMsg = it.current;
        // Greeting: [0x05, 0x01, 0x00]
        expect(firstMsg.sublist(0, 3), equals(<int>[0x05, 0x01, 0x00]));
        client.add(<int>[0x05, 0x00]); // No auth accepted

        expect(await it.moveNext(), isTrue);
        final reqMsg = it.current;
        // [0x05, 0x01, 0x00, 0x03, len, ...host, portHi, portLo]
        expect(reqMsg[0], 0x05);
        expect(reqMsg[1], 0x01);
        expect(reqMsg[3], 0x03);
        final hostLen = reqMsg[4];
        final host = utf8.decode(reqMsg.sublist(5, 5 + hostLen));
        capturedHostCompleter.complete(host);

        client.add(<int>[0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90]);
        await client.flush();
        client.destroy();
      }());

      const onion = 'gpoun4vo5v5h3cmcfdxtudm3nlzxri3qzjd7fhbvy6oep2ap67g4qvyd.onion';
      final connector = Socks5Connector(proxyHost: '127.0.0.1', proxyPort: server.port);
      final tunnel = await connector.connect(onion, 8080, requireOnionV3: true);
      tunnel.destroy();

      expect(await capturedHostCompleter.future, equals(onion));
    });
  });

  group('TorControlClient Protocol', () {
    test('authenticates with hex cookie and parses ADD_ONION + GETINFO responses', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      unawaited(() async {
        final sock = await server.first;
        await sock.cast<List<int>>().transform(utf8.decoder).forEach((chunk) {
          for (final raw in chunk.split('\r\n')) {
            if (raw.isEmpty) continue;
            if (raw.startsWith('AUTHENTICATE')) {
              sock.write('250 OK\r\n');
            } else if (raw.startsWith('GETINFO status/bootstrap-phase')) {
              sock.write('250-status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS=100 SUMMARY="Done"\r\n250 OK\r\n');
            } else if (raw.startsWith('ADD_ONION')) {
              sock.write('250-ServiceID=abcdef234567234567abcdef234567234567abcdef234567abcdef23\r\n');
              sock.write('250-PrivateKey=ED25519-V3:MOCKKEYDATA\r\n');
              sock.write('250 OK\r\n');
            }
          }
        });
      }());

      final ctrl = await TorControlClient.connect(host: '127.0.0.1', port: server.port);
      await ctrl.authenticateHex('DEADBEEF');
      final info = await ctrl.getInfo('status/bootstrap-phase');
      expect(info, contains('PROGRESS=100'));

      final onion = await ctrl.addOnionV3(virtualPort: 80, targetPort: 8080);
      expect(onion.serviceId, hasLength(56));
      expect(onion.privateKey, equals('ED25519-V3:MOCKKEYDATA'));
      await ctrl.close();
    });
  });

  group('RelayClient (Mock Loopback & Policy Enforcement)', () {
    test('stores, fetches and acknowledges encrypted envelopes over local loopback test server', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final stored = <Map<String, dynamic>>[];

      unawaited(() async {
        await for (final req in server) {
          if (req.uri.path == '/healthz') {
            req.response.statusCode = 200;
            req.response.write('{"status":"ok"}');
          } else if (req.method == 'POST' && req.uri.path == '/v1/mailboxes/mbox1/envelopes') {
            final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
            final id = 'env_${stored.length + 1}';
            stored.add({
              'id': id,
              'payload_b64': body['payload_b64'],
              'created_at': 1000,
              'expires_at': 2000,
            });
            req.response.statusCode = 202;
            req.response.write(jsonEncode({'id': id}));
          } else if (req.method == 'GET' && req.uri.path == '/v1/mailboxes/mbox1/envelopes') {
            req.response.statusCode = 200;
            req.response.write(jsonEncode({'envelopes': stored}));
          } else if (req.method == 'POST' && req.uri.path == '/v1/mailboxes/mbox1/ack') {
            final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
            final ids = (body['ids'] as List<dynamic>).cast<String>();
            final before = stored.length;
            stored.removeWhere((e) => ids.contains(e['id']));
            req.response.statusCode = 200;
            req.response.write(jsonEncode({'deleted': before - stored.length}));
          } else {
            req.response.statusCode = 404;
          }
          await req.response.close();
        }
      }());

      final client = RelayClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
        policy: const TransportPolicy(mode: TransportMode.loopbackTest),
      );
      expect(await client.checkHealth(), isTrue);

      final envId = await client.storeEnvelope(
        mailboxId: 'mbox1',
        cipherPayload: Uint8List.fromList(<int>[1, 2, 3, 4]),
      );
      expect(envId, equals('env_1'));

      const creds = MailboxCredentials(mailboxId: 'mbox1', readToken: 'tok-abc');
      final fetched = await client.fetchEnvelopes(creds);
      expect(fetched, hasLength(1));
      expect(base64Decode(fetched.first.payloadBase64), equals(<int>[1, 2, 3, 4]));

      final deleted = await client.acknowledge(creds, <String>[envId]);
      expect(deleted, equals(1));
      expect(await client.fetchEnvelopes(creds), isEmpty);
    });
  });
}
