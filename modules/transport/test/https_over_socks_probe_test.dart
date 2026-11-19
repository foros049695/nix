import 'dart:io';
import 'dart:typed_data';

import 'package:nix_transport/nix_transport.dart';
import 'package:test/test.dart';

// Issue #11: HTTPS via SOCKS deve falhar fechado com erro tipado,
// sem tocar a rede e sem nenhum downgrade para HTTP ou caminho direto.
void main() {
  const onion =
      'abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuvwx.onion';

  late ServerSocket fakeSocks;
  late int connections;

  setUp(() async {
    connections = 0;
    fakeSocks = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    fakeSocks.listen((socket) {
      connections++;
      socket.destroy();
    });
  });

  tearDown(() async => fakeSocks.close());

  RelayClient clientFor(String scheme) => RelayClient(
        baseUri: Uri.parse('$scheme://$onion/'),
        policy: TransportPolicy(
          socksHost: '127.0.0.1',
          socksPort: fakeSocks.port,
        ),
      );

  test('https:// via SOCKS lança UnsupportedTransportSchemeException', () async {
    await expectLater(
      clientFor('https').checkHealth(),
      throwsA(isA<UnsupportedTransportSchemeException>()
          .having((e) => e.scheme, 'scheme', 'https')
          .having((e) => e.message, 'message', contains('Issue #11'))),
    );
    expect(connections, 0, reason: 'nenhum socket pode ser aberto');
  });

  test('erro é um TransportBlockedException (fail-closed compatível)', () async {
    await expectLater(
      clientFor('https').storeEnvelope(
        mailboxId: 'mbox',
        cipherPayload: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(isA<TransportBlockedException>()),
    );
    expect(connections, 0);
  });

  test('NoSuchMethodError (_detachRaw) não ocorre mais', () async {
    Object? caught;
    try {
      await clientFor('https').checkHealth();
    } catch (e) {
      caught = e;
    }
    expect(caught, isNot(isA<NoSuchMethodError>()));
  });

  test('http:// para .onion continua usando o túnel SOCKS', () async {
    // O servidor sintético derruba a conexão: o handshake falha, mas a
    // tentativa prova que http:// segue pelo SOCKS e não é afetado.
    await expectLater(clientFor('http').checkHealth(), throwsA(anything));
    expect(connections, 1);
  });
}
