import 'dart:convert';
import 'dart:math';

import 'package:nix_transport/nix_transport.dart';

import 'bitcoin_payment_request.dart';

typedef BitcoinOnionQuery = Future<({int statusCode, String body})> Function({
  required String path,
  required String circuitIsolation,
  String? body,
  String? basicAuthorization,
  String? macaroon,
});

/// Consultas de leitura aos nós próprios do usuário. Nenhuma chave da conta é usada.
class BitcoinTestnetNode {
  BitcoinTestnetNode._(this._query);

  final BitcoinOnionQuery _query;

  factory BitcoinTestnetNode.onion(
    String endpoint, {
    required int socksPort,
    bool Function()? mayConnect,
  }) {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        !TransportPolicy.isValidOnionV3Host(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
          'Informe a URL HTTP ou HTTPS de um nó Onion v3.');
    }
    final client = RelayClient(
      baseUri: uri,
      policy: TransportPolicy(socksPort: socksPort),
    );
    return BitcoinTestnetNode._(({
      required path,
      required circuitIsolation,
      body,
      basicAuthorization,
      macaroon,
    }) {
      if (mayConnect?.call() == false) {
        throw const TransportBlockedException(
            'O Tor do Nix deixou de estar disponível.');
      }
      return client.requestOnionJson(
        path: path,
        circuitIsolation: circuitIsolation,
        body: body,
        basicAuthorization: basicAuthorization,
        macaroon: macaroon,
      );
    });
  }

  BitcoinTestnetNode.withQuery(BitcoinOnionQuery query) : this._(query);

  static String _isolate() {
    final random = Random.secure();
    return base64UrlEncode(List.generate(16, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  Future<({String chain, int blocks})> checkBitcoinCore({
    required String user,
    required String password,
  }) async {
    if (user.isEmpty ||
        user.contains(':') ||
        password.isEmpty ||
        utf8.encode(user).length + utf8.encode(password).length > 512) {
      throw const FormatException('Informe as credenciais RPC do nó de teste.');
    }
    final reply = await _query(
      path: '/',
      body: jsonEncode({
        'jsonrpc': '1.0',
        'id': 'nix-testnet',
        'method': 'getblockchaininfo',
        'params': <String>[],
      }),
      basicAuthorization: base64Encode(utf8.encode('$user:$password')),
      circuitIsolation: _isolate(),
    );
    final result = _response(reply)['result'];
    if (result is! Map ||
        !const {'test', 'testnet4', 'signet', 'regtest'}
            .contains(result['chain']) ||
        result['blocks'] is! int ||
        (result['blocks'] as int) < 0) {
      throw const FormatException(
          'A resposta não confirma um nó Bitcoin de teste.');
    }
    return (chain: result['chain'] as String, blocks: result['blocks'] as int);
  }

  Future<BigInt> verifyLightningInvoice({
    required BitcoinPaymentRequest request,
    required String readOnlyMacaroon,
  }) async {
    if (!request.lightning ||
        request.network == BitcoinNetwork.mainnet ||
        !RegExp(r'^(?:[0-9a-fA-F]{2}){1,1024}$').hasMatch(readOnlyMacaroon)) {
      throw const FormatException(
          'Use uma fatura de teste e um macaroon de leitura em hexadecimal.');
    }
    final chainResponse = _response(await _query(
      path: '/v1/getinfo',
      macaroon: readOnlyMacaroon,
      circuitIsolation: _isolate(),
    ));
    final chains = chainResponse['chains'];
    final expected = switch (request.network) {
      BitcoinNetwork.testnet => 'testnet',
      BitcoinNetwork.signet => 'signet',
      BitcoinNetwork.regtest => 'regtest',
      _ => '',
    };
    if (chains is! List ||
        !chains.whereType<Map>().any(
              (item) =>
                  item['chain'] == 'bitcoin' && item['network'] == expected,
            )) {
      throw const FormatException('A rede do nó Lightning difere da fatura.');
    }
    final payload = request.payload.substring('lightning:'.length);
    final result = _response(await _query(
      path: '/v1/payreq/$payload',
      macaroon: readOnlyMacaroon,
      circuitIsolation: _isolate(),
    ));
    final amount = BigInt.tryParse(result['num_msat']?.toString() ?? '');
    final timestamp = int.tryParse(result['timestamp']?.toString() ?? '');
    final expiry = int.tryParse(result['expiry']?.toString() ?? '');
    final hash = result['payment_hash'];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (amount == null ||
        amount < BigInt.zero ||
        amount != (request.milliSatoshis ?? BigInt.zero) ||
        timestamp == null ||
        timestamp < 0 ||
        timestamp > now + 300 ||
        expiry == null ||
        expiry <= 0 ||
        expiry <= now - timestamp ||
        hash is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('A fatura não confere com o nó ou expirou.');
    }
    return amount;
  }

  Map<String, dynamic> _response(({int statusCode, String body}) reply) {
    if (reply.statusCode != 200) {
      throw const FormatException(
          'O nó não autorizou ou não concluiu a consulta.');
    }
    final decoded = jsonDecode(reply.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Resposta incompatível do nó.');
    }
    return decoded;
  }

  /// Realiza liquidação de fatura Lightning via endpoint `/v1/channels/transactions` do nó LND próprio.
  /// Suporta fundos sintéticos e validação estrita em redes de teste (rejeita mainnet).
  Future<BitcoinPaymentResult> payLightningInvoice({
    required BitcoinPaymentRequest request,
    required String adminMacaroon,
    int? feeLimitSat,
  }) async {
    if (!request.lightning ||
        request.network == BitcoinNetwork.mainnet ||
        !RegExp(r'^(?:[0-9a-fA-F]{2}){1,1024}$').hasMatch(adminMacaroon)) {
      throw const FormatException(
          'Use uma fatura de teste e um macaroon administrativo em hexadecimal.');
    }

    final rawInvoice = request.payload.startsWith('lightning:')
        ? request.payload.substring('lightning:'.length)
        : request.payload;

    final body = jsonEncode({
      'payment_request': rawInvoice,
      if (feeLimitSat != null) 'fee_limit': {'fixed': feeLimitSat},
    });

    final reply = await _query(
      path: '/v1/channels/transactions',
      body: body,
      macaroon: adminMacaroon,
      circuitIsolation: _isolate(),
    );

    final now = DateTime.now().toUtc();
    final res = _response(reply);

    final paymentError = res['payment_error'] as String?;
    final preimage = res['payment_preimage'] as String?;
    final feeMsat = BigInt.tryParse(res['payment_route']?['total_fees_msat']?.toString() ?? '0') ?? BigInt.zero;

    if (paymentError != null && paymentError.isNotEmpty) {
      return BitcoinPaymentResult(
        id: 'ln_${now.millisecondsSinceEpoch}',
        status: BitcoinPaymentStatus.failed,
        failureReason: paymentError,
        amountMilliSatoshis: request.milliSatoshis ?? BigInt.zero,
        feeMilliSatoshis: feeMsat,
        timestamp: now,
        isLightning: true,
        destination: rawInvoice,
        network: request.network,
      );
    }

    if (preimage != null && preimage.isNotEmpty && !RegExp(r'^0+$').hasMatch(preimage)) {
      return BitcoinPaymentResult(
        id: 'ln_${now.millisecondsSinceEpoch}',
        status: BitcoinPaymentStatus.succeeded,
        preimageOrTxId: preimage,
        amountMilliSatoshis: request.milliSatoshis ?? BigInt.zero,
        feeMilliSatoshis: feeMsat,
        timestamp: now,
        isLightning: true,
        destination: rawInvoice,
        network: request.network,
      );
    }

    return BitcoinPaymentResult(
      id: 'ln_${now.millisecondsSinceEpoch}',
      status: BitcoinPaymentStatus.inFlight,
      amountMilliSatoshis: request.milliSatoshis ?? BigInt.zero,
      feeMilliSatoshis: feeMsat,
      timestamp: now,
      isLightning: true,
      destination: rawInvoice,
      network: request.network,
    );
  }

  /// Realiza envio Bitcoin On-chain via RPC `sendtoaddress` do nó Bitcoin Core próprio em regtest/testnet.
  Future<BitcoinPaymentResult> sendBitcoinOnChain({
    required BitcoinPaymentRequest request,
    required String user,
    required String password,
  }) async {
    if (request.lightning || request.network == BitcoinNetwork.mainnet) {
      throw const FormatException(
          'Envios diretos são restritos a endereços on-chain de teste (regtest/testnet/signet).');
    }

    final amountMsat = request.milliSatoshis;
    if (amountMsat == null || amountMsat <= BigInt.zero) {
      throw const FormatException('O pedido on-chain deve especificar um valor válido.');
    }

    final btcValue = amountMsat.toDouble() / 100000000000.0;
    final address = request.payload.startsWith('bitcoin:')
        ? Uri.parse(request.payload).path
        : request.payload;

    final body = jsonEncode({
      'jsonrpc': '1.0',
      'id': 'nix-sendtoaddress',
      'method': 'sendtoaddress',
      'params': [address, btcValue, 'nix-regtest', '', false, true],
    });

    final reply = await _query(
      path: '/',
      body: body,
      basicAuthorization: base64Encode(utf8.encode('$user:$password')),
      circuitIsolation: _isolate(),
    );

    final now = DateTime.now().toUtc();
    final res = _response(reply);

    final error = res['error'];
    if (error != null && error is Map) {
      return BitcoinPaymentResult(
        id: 'btc_${now.millisecondsSinceEpoch}',
        status: BitcoinPaymentStatus.failed,
        failureReason: error['message']?.toString() ?? 'Erro RPC no nó Bitcoin',
        amountMilliSatoshis: amountMsat,
        timestamp: now,
        isLightning: false,
        destination: address,
        network: request.network,
      );
    }

    final txid = res['result'] as String?;
    if (txid != null && RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(txid)) {
      return BitcoinPaymentResult(
        id: 'btc_${now.millisecondsSinceEpoch}',
        status: BitcoinPaymentStatus.succeeded,
        preimageOrTxId: txid,
        amountMilliSatoshis: amountMsat,
        timestamp: now,
        isLightning: false,
        destination: address,
        network: request.network,
      );
    }

    return BitcoinPaymentResult(
      id: 'btc_${now.millisecondsSinceEpoch}',
      status: BitcoinPaymentStatus.failed,
      failureReason: 'Resposta inesperada do nó Bitcoin Core.',
      amountMilliSatoshis: amountMsat,
      timestamp: now,
      isLightning: false,
      destination: address,
      network: request.network,
    );
  }
}

enum BitcoinPaymentStatus {
  succeeded,
  failed,
  inFlight,
  expired,
}

class BitcoinPaymentResult {
  final String id;
  final BitcoinPaymentStatus status;
  final String? preimageOrTxId;
  final String? failureReason;
  final BigInt amountMilliSatoshis;
  final BigInt feeMilliSatoshis;
  final DateTime timestamp;
  final bool isLightning;
  final String destination;
  final BitcoinNetwork network;

  BitcoinPaymentResult({
    required this.id,
    required this.status,
    this.preimageOrTxId,
    this.failureReason,
    required this.amountMilliSatoshis,
    BigInt? feeMilliSatoshis,
    required this.timestamp,
    required this.isLightning,
    required this.destination,
    required this.network,
  }) : feeMilliSatoshis = feeMilliSatoshis ?? BigInt.zero;

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.name,
    'preimageOrTxId': preimageOrTxId,
    'failureReason': failureReason,
    'amountMsat': amountMilliSatoshis.toString(),
    'feeMsat': feeMilliSatoshis.toString(),
    'timestampMs': timestamp.toUtc().millisecondsSinceEpoch,
    'isLightning': isLightning,
    'destination': destination,
    'network': network.name,
  };

  factory BitcoinPaymentResult.fromJson(Map<String, dynamic> json) => BitcoinPaymentResult(
    id: json['id'] as String,
    status: BitcoinPaymentStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => BitcoinPaymentStatus.failed,
    ),
    preimageOrTxId: json['preimageOrTxId'] as String?,
    failureReason: json['failureReason'] as String?,
    amountMilliSatoshis: BigInt.tryParse(json['amountMsat']?.toString() ?? '0') ?? BigInt.zero,
    feeMilliSatoshis: BigInt.tryParse(json['feeMsat']?.toString() ?? '0') ?? BigInt.zero,
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      json['timestampMs'] as int? ?? DateTime.now().toUtc().millisecondsSinceEpoch,
      isUtc: true,
    ),
    isLightning: json['isLightning'] as bool? ?? false,
    destination: json['destination'] as String? ?? '',
    network: BitcoinNetwork.values.firstWhere(
      (n) => n.name == json['network'],
      orElse: () => BitcoinNetwork.regtest,
    ),
  );
}
