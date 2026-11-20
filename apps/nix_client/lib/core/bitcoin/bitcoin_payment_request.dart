import 'dart:convert';

import 'package:crypto/crypto.dart';

enum BitcoinNetwork { mainnet, testnet, signet, regtest, testNetworks }

class BitcoinPaymentRequest {
  final BitcoinNetwork network;
  final String payload;
  final bool lightning;
  final BigInt? milliSatoshis;

  const BitcoinPaymentRequest._(
      this.network, this.payload, this.lightning, this.milliSatoshis);

  static const _bechAlphabet = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  static const _base58Alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  static final _maxSats = BigInt.from(21000000) * BigInt.from(100000000);

  factory BitcoinPaymentRequest.parse(String text) {
    final raw = text.trim();
    if (raw.isEmpty || raw.length > 2048 || RegExp(r'\s').hasMatch(raw)) {
      throw const FormatException('Pedido Bitcoin ou Lightning inválido.');
    }
    if (raw.toLowerCase().startsWith('lightning:')) {
      return _invoice(raw.substring(10));
    }
    if (raw.toLowerCase().startsWith('ln')) return _invoice(raw);
    return _onChain(raw);
  }

  static BitcoinPaymentRequest _onChain(String value) {
    final uri = Uri.parse(
        value.toLowerCase().startsWith('bitcoin:') ? value : 'bitcoin:$value');
    if (uri.scheme != 'bitcoin' || uri.hasAuthority || uri.hasFragment) {
      throw const FormatException('Use um endereço Bitcoin ou URI BIP21.');
    }
    final address = uri.path;
    if (address.length < 14 || address.length > 90) {
      throw const FormatException('Endereço Bitcoin inválido.');
    }
    final params = uri.queryParametersAll;
    if (params.entries.any((e) =>
        e.value.length != 1 ||
        !const {'amount', 'label', 'message'}.contains(e.key))) {
      throw const FormatException('Parâmetro BIP21 incompatível.');
    }
    BigInt? sats;
    final amount = params['amount']?.single;
    if (amount != null) {
      if (!RegExp(r'^[0-9]{1,8}(\.[0-9]{1,8})?$').hasMatch(amount)) {
        throw const FormatException('Valor BIP21 inválido.');
      }
      final units = amount.split('.');
      sats = BigInt.parse(units.first) * BigInt.from(100000000) +
          BigInt.parse((units.length == 2 ? units.last : '').padRight(8, '0'));
      if (sats <= BigInt.zero || sats > _maxSats) {
        throw const FormatException('Valor Bitcoin fora do limite.');
      }
    }
    final network = _addressNetwork(address);
    final canonical = Uri(
        scheme: 'bitcoin',
        path: address,
        queryParameters: params.isEmpty
            ? null
            : {
                for (final entry in params.entries)
                  entry.key: entry.value.single,
              });
    return BitcoinPaymentRequest._(
      network,
      canonical.toString(),
      false,
      sats == null ? null : sats * BigInt.from(1000),
    );
  }

  static BitcoinNetwork _addressNetwork(String address) {
    final lower = address.toLowerCase();
    if (lower.startsWith('bc1') ||
        lower.startsWith('tb1') ||
        lower.startsWith('bcrt1')) {
      final (hrp, words, check) = _decodeBech32(address);
      if (words.isEmpty) throw const FormatException('SegWit inválido.');
      final version = words.first;
      var pending = 0;
      var accumulator = 0;
      var bytes = 0;
      for (final word in words.skip(1)) {
        accumulator = ((accumulator & 255) << 5) | word;
        pending += 5;
        if (pending >= 8) {
          pending -= 8;
          bytes++;
        }
      }
      if (version > 16 ||
          bytes < 2 ||
          bytes > 40 ||
          pending >= 5 ||
          (accumulator & ((1 << pending) - 1)) != 0 ||
          (version == 0
              ? check != 1 || (bytes != 20 && bytes != 32)
              : check != 0x2bc830a3)) {
        throw const FormatException('Programa SegWit inválido.');
      }
      return switch (hrp) {
        'bc' => BitcoinNetwork.mainnet,
        'tb' => BitcoinNetwork.testNetworks,
        'bcrt' => BitcoinNetwork.regtest,
        _ => throw const FormatException('Rede Bitcoin desconhecida.'),
      };
    }
    var value = BigInt.zero;
    for (final char in address.split('')) {
      final digit = _base58Alphabet.indexOf(char);
      if (digit < 0) throw const FormatException('Endereço Base58 inválido.');
      value = value * BigInt.from(58) + BigInt.from(digit);
    }
    final suffix = <int>[];
    while (value > BigInt.zero) {
      suffix.add((value & BigInt.from(255)).toInt());
      value >>= 8;
    }
    final leading =
        address.length - address.replaceFirst(RegExp(r'^1+'), '').length;
    final bytes = [...List.filled(leading, 0), ...suffix.reversed];
    if (bytes.length != 25)
      throw const FormatException('Endereço Base58 inválido.');
    final hash =
        sha256.convert(sha256.convert(bytes.sublist(0, 21)).bytes).bytes;
    for (var i = 0; i < 4; i++) {
      if (hash[i] != bytes[i + 21])
        throw const FormatException('Checksum inválido.');
    }
    return switch (bytes.first) {
      0 || 5 => BitcoinNetwork.mainnet,
      111 || 196 => BitcoinNetwork.testNetworks,
      _ => throw const FormatException('Rede Bitcoin desconhecida.'),
    };
  }

  static BitcoinPaymentRequest _invoice(String value) {
    final (hrp, words, check) = _decodeBech32(value);
    final header =
        RegExp(r'^ln(bcrt|tbs|tb|bc)([0-9]+)?([munp])?$').firstMatch(hrp);
    if (header == null ||
        check != 1 ||
        words.length < 7 + 104 ||
        (header[2] == null && header[3] != null)) {
      throw const FormatException('Fatura BOLT11 inválida.');
    }
    final network = switch (header[1]) {
      'bc' => BitcoinNetwork.mainnet,
      'tb' => BitcoinNetwork.testnet,
      'tbs' => BitcoinNetwork.signet,
      _ => BitcoinNetwork.regtest,
    };
    BigInt? msat;
    if (header[2] case final amount?) {
      final digits = BigInt.parse(amount);
      final multiplier = switch (header[3]) {
        'm' => 100000000,
        'u' => 100000,
        'n' => 100,
        'p' => 1,
        _ => 100000000000,
      };
      if (header[3] == 'p' && digits % BigInt.from(10) != BigInt.zero) {
        throw const FormatException('Precisão Lightning inválida.');
      }
      msat = digits * BigInt.from(multiplier);
      if (header[3] == 'p') msat ~/= BigInt.from(10);
      if (msat <= BigInt.zero || msat > _maxSats * BigInt.from(1000)) {
        throw const FormatException('Valor Lightning fora do limite.');
      }
    }
    final tags = <String>{};
    final end = words.length - 104;
    var index = 7;
    while (index < end) {
      if (index + 3 > end)
        throw const FormatException('Campo BOLT11 truncado.');
      final tag = _bechAlphabet[words[index]];
      final count = (words[index + 1] << 5) | words[index + 2];
      index += 3;
      if (index + count > end ||
          (const {'p', 'h', 's'}.contains(tag) && count != 52) ||
          (const {'p', 'h', 'd', 's'}.contains(tag) && tags.contains(tag))) {
        throw const FormatException('Campo BOLT11 inválido.');
      }
      tags.add(tag);
      index += count;
    }
    if (!tags.contains('p') || (tags.contains('h') == tags.contains('d'))) {
      throw const FormatException('Faltam campos obrigatórios da fatura.');
    }
    return BitcoinPaymentRequest._(
      network,
      'lightning:${value.toLowerCase()}',
      true,
      msat,
    );
  }

  static (String, List<int>, int) _decodeBech32(String value) {
    final lower = value.toLowerCase();
    if (value != lower && value != value.toUpperCase()) {
      throw const FormatException('Bech32 mistura maiúsculas e minúsculas.');
    }
    final separator = lower.lastIndexOf('1');
    if (separator < 1 ||
        separator + 7 > lower.length ||
        lower.codeUnits.any((code) => code < 33 || code > 126)) {
      throw const FormatException('Formato Bech32 inválido.');
    }
    final hrp = lower.substring(0, separator);
    final data = lower
        .substring(separator + 1)
        .split('')
        .map(_bechAlphabet.indexOf)
        .toList();
    if (data.any((digit) => digit < 0)) {
      throw const FormatException('Caractere Bech32 inválido.');
    }
    const generators = [
      0x3b6a57b2,
      0x26508e6d,
      0x1ea119fa,
      0x3d4233dd,
      0x2a1462b3
    ];
    var checksum = 1;
    for (final word in [
      for (final code in ascii.encode(hrp)) code >> 5,
      0,
      for (final code in ascii.encode(hrp)) code & 31,
      ...data,
    ]) {
      final top = checksum >> 25;
      checksum = ((checksum & 0x1ffffff) << 5) ^ word;
      for (var i = 0; i < generators.length; i++) {
        if (((top >> i) & 1) != 0) checksum ^= generators[i];
      }
    }
    return (hrp, data.sublist(0, data.length - 6), checksum);
  }
}
