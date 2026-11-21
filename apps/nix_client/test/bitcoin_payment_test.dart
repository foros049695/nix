import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/bitcoin/bitcoin_payment_request.dart';
import 'package:nix_client/core/bitcoin/bitcoin_testnet_node.dart';

const _testInvoice =
    'lntb20m1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygshp58yjmdan79s6qqdhdzgynm4zwqd5d7xmw5fk98klysy043l2ahrqspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqfpp3x9et2e20v6pu37c5d9vax37wxq72un989qrsgqdj545axuxtnfemtpwkc45hx9d2ft7x04mt8q7y6t0k2dge9e7h8kpy9p34ytyslj3yu569aalz2xdk8xkd7ltxqld94u8h2esmsmacgpghe9k8';

void main() {
  test('reconhece Base58Check, valores BIP21 e formatos inválidos', () {
    const address = '1BoatSLRHtKNngkdXEeobR76b53LETtpyT';
    final parsed =
        BitcoinPaymentRequest.parse('bitcoin:$address?amount=0.00001234');
    expect(parsed.milliSatoshis, BigInt.from(1234000));
    expect(parsed.network, BitcoinNetwork.mainnet);
    expect(() => BitcoinPaymentRequest.parse('${address}a'),
        throwsFormatException);
    expect(
        () => BitcoinPaymentRequest.parse('bitcoin:$address?amount=1&amount=2'),
        throwsFormatException);
    expect(() => BitcoinPaymentRequest.parse('bitcoin:$address?req-unknown=1'),
        throwsFormatException);
  });

  test('BOLT11 oficial preserva rede e valor, e rejeita checksum adulterado',
      () {
    final invoice = BitcoinPaymentRequest.parse(_testInvoice);
    expect(invoice.network, BitcoinNetwork.testnet);
    expect(invoice.lightning, isTrue);
    expect(invoice.milliSatoshis, BigInt.from(2000000000));
    expect(
        () => BitcoinPaymentRequest.parse(
              '${_testInvoice.substring(0, _testInvoice.length - 1)}q',
            ),
        throwsFormatException);
  });

  test('Bitcoin Core consulta somente altura e rede e rejeita mainnet',
      () async {
    var chain = 'regtest';
    final node = BitcoinTestnetNode.withQuery(({
      required path,
      required circuitIsolation,
      body,
      basicAuthorization,
      macaroon,
    }) async {
      expect(path, '/');
      expect(circuitIsolation, hasLength(22));
      expect(basicAuthorization, base64Encode(utf8.encode('tester:test-only')));
      expect(macaroon, isNull);
      expect(jsonDecode(body!)['method'], 'getblockchaininfo');
      return (
        statusCode: 200,
        body: jsonEncode({
          'result': {'chain': chain, 'blocks': 5}
        })
      );
    });
    expect(await node.checkBitcoinCore(user: 'tester', password: 'test-only'),
        (chain: 'regtest', blocks: 5));
    chain = 'main';
    await expectLater(
        node.checkBitcoinCore(user: 'tester', password: 'test-only'),
        throwsFormatException);
    expect(() => BitcoinTestnetNode.onion('https://example.com', socksPort: 1),
        throwsFormatException);
  });

  test('LND valida rede, circuitos distintos e expiração', () async {
    final paths = <String>[];
    final circuits = <String>{};
    var chain = 'testnet';
    var expired = false;
    final node = BitcoinTestnetNode.withQuery(({
      required path,
      required circuitIsolation,
      body,
      basicAuthorization,
      macaroon,
    }) async {
      paths.add(path);
      circuits.add(circuitIsolation);
      expect(macaroon, 'abcd');
      expect(body, isNull);
      expect(basicAuthorization, isNull);
      final reply = path == '/v1/getinfo'
          ? {
              'chains': [
                {'chain': 'bitcoin', 'network': chain}
              ]
            }
          : {
              'num_msat': '2000000000',
              'expiry': '3600',
              'timestamp': expired
                  ? '1'
                  : '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
              'payment_hash': ''.padLeft(64, 'a'),
            };
      return (statusCode: 200, body: jsonEncode(reply));
    });
    final invoice = BitcoinPaymentRequest.parse(_testInvoice);
    expect(
        await node.verifyLightningInvoice(
            request: invoice, readOnlyMacaroon: 'abcd'),
        BigInt.from(2000000000));
    expect(paths, ['/v1/getinfo', '/v1/payreq/$_testInvoice']);
    expect(circuits, hasLength(2));
    expired = true;
    await expectLater(
        node.verifyLightningInvoice(request: invoice, readOnlyMacaroon: 'abcd'),
        throwsFormatException);
    chain = 'mainnet';
    paths.clear();
    await expectLater(
        node.verifyLightningInvoice(request: invoice, readOnlyMacaroon: 'abcd'),
        throwsFormatException);
    expect(paths, ['/v1/getinfo']);
  });

  test('LND payLightningInvoice liquida fatura e retorna comprovante/preimage', () async {
    final invoice = BitcoinPaymentRequest.parse(_testInvoice);
    final node = BitcoinTestnetNode.withQuery(({
      required path,
      required circuitIsolation,
      body,
      basicAuthorization,
      macaroon,
    }) async {
      expect(path, '/v1/channels/transactions');
      expect(macaroon, '1234abcd');
      final req = jsonDecode(body!);
      expect(req['payment_request'], isNotEmpty);
      expect(req['fee_limit']['fixed'], 50);

      return (
        statusCode: 200,
        body: jsonEncode({
          'payment_error': '',
          'payment_preimage': '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
          'payment_route': {'total_fees_msat': '1000'},
        }),
      );
    });

    final res = await node.payLightningInvoice(
      request: invoice,
      adminMacaroon: '1234abcd',
      feeLimitSat: 50,
    );

    expect(res.status, BitcoinPaymentStatus.succeeded);
    expect(res.preimageOrTxId, '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef');
    expect(res.feeMilliSatoshis, BigInt.from(1000));
    expect(res.isLightning, isTrue);
  });

  test('Bitcoin Core sendBitcoinOnChain executa RPC sendtoaddress com sucesso', () async {
    const validTestnetAddress = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';
    final request = BitcoinPaymentRequest.parse('bitcoin:$validTestnetAddress?amount=0.01');
    final node = BitcoinTestnetNode.withQuery(({
      required path,
      required circuitIsolation,
      body,
      basicAuthorization,
      macaroon,
    }) async {
      expect(path, '/');
      expect(basicAuthorization, base64Encode(utf8.encode('rpcuser:rpcpass')));
      final req = jsonDecode(body!);
      expect(req['method'], 'sendtoaddress');
      expect(req['params'][0], validTestnetAddress);

      return (
        statusCode: 200,
        body: jsonEncode({
          'result': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          'error': null,
          'id': 'nix-sendtoaddress',
        }),
      );
    });

    final res = await node.sendBitcoinOnChain(
      request: request,
      user: 'rpcuser',
      password: 'rpcpass',
    );

    expect(res.status, BitcoinPaymentStatus.succeeded);
    expect(res.preimageOrTxId, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(res.isLightning, isFalse);
    expect(res.amountMilliSatoshis, BigInt.from(1000000000));
  });
}
