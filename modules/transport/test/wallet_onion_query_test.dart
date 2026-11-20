import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nix_transport/nix_transport.dart';
import 'package:test/test.dart';

void main() {
  const isolation = '1234567890123456789012';
  final host = '${'a' * 56}.onion';

  test('a consulta ao nó usa DNS remoto e autenticação SOCKS isolada',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final request = Completer<String>();
    final authorization = Completer<List<int>>();
    final destination = Completer<List<int>>();
    server.listen((socket) {
      var stage = 0;
      final data = StringBuffer();
      socket.listen((bytes) {
        switch (stage++) {
          case 0:
            socket.add(bytes.length == 3 && bytes[2] == 2 ? [5, 2] : [5, 255]);
          case 1:
            authorization.complete(bytes);
            socket.add([1, 0]);
          case 2:
            destination.complete(bytes);
            socket.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 80]);
          default:
            data.write(ascii.decode(bytes));
            if (!data.toString().endsWith('{"name":"test"}')) return;
            request.complete(data.toString());
            socket.write(
                'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}');
            socket.close();
        }
      });
    });
    final client = RelayClient(
      baseUri: Uri.parse('http://$host:18332'),
      policy: TransportPolicy(socksPort: server.port),
    );
    final response = await client.requestOnionJson(
      path: '/',
      circuitIsolation: isolation,
      basicAuthorization: 'dTpw',
      body: '{"name":"test"}',
    );
    expect(response, (statusCode: 200, body: '{}'));
    expect(await authorization.future,
        [1, 22, ...isolation.codeUnits, 22, ...isolation.codeUnits]);
    expect(await destination.future, [
      5,
      1,
      0,
      3,
      host.length,
      ...host.codeUnits,
      18332 >> 8,
      18332 & 255,
    ]);
    expect(await request.future, contains('Authorization: Basic dTpw\r\n'));
  });

  test('recusa clearnet, modo de laboratório e cabeçalhos inválidos', () {
    final client = RelayClient(baseUri: Uri.parse('http://$host'));
    expect(
        () => client.requestOnionJson(
              path: '//outro',
              circuitIsolation: isolation,
              macaroon: 'aabb',
            ),
        throwsA(isA<TransportBlockedException>()));
    expect(
        () => client.requestOnionJson(
              path: '/',
              circuitIsolation: isolation,
              basicAuthorization: 'a\r\nb',
            ),
        throwsA(isA<TransportBlockedException>()));
    final local = RelayClient(
      baseUri: Uri.parse('http://127.0.0.1'),
      policy: const TransportPolicy(mode: TransportMode.loopbackTest),
    );
    expect(() => local.requestOnionJson(path: '/', circuitIsolation: isolation),
        throwsA(isA<TransportBlockedException>()));
  });
}
