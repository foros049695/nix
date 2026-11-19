import 'dart:convert';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:nix_core_crypto/nix_core_crypto.dart';
import '../models/monero_order.dart';

/// Violação da fronteira estrita ADR-0003 entre Seed A (mensageria) e Seed B (Monero).
class MoneroSeedBoundaryException implements Exception {
  final String message;
  const MoneroSeedBoundaryException(this.message);

  @override
  String toString() => 'MoneroSeedBoundaryException: $message';
}

/// Impõe o isolamento criptográfico e de processo não-custodial do Monero P2P (Fase 6 / ADR-0003).
class MoneroIsolationPolicy {
  /// Valida que o RPC local ou daemon remoto da carteira Monero nunca vaza IP em clearnet.
  static void assertSafeWalletRpcUri(Uri rpcUri) {
    final host = rpcUri.host.trim().toLowerCase();
    final isLoopback = host == '127.0.0.1' || host == 'localhost' || host == '::1';
    final isOnion = host.endsWith('.onion') && host.length >= 62;
    if (!isLoopback && !isOnion) {
      throw MoneroSeedBoundaryException(
        '[Fail-Closed] Endpoint RPC Monero ($host) bloqueado: use apenas daemon local loopback ou .onion via Tor.',
      );
    }
  }

  /// Verifica que uma Seed mnemônica/hex financeira (Seed B) é totalmente distinta da Seed A de mensageria.
  static void assertDistinctSeedDomains({
    required List<String> seedAMnemonic,
    required List<String> seedBMnemonic,
  }) {
    if (seedAMnemonic.join(' ').trim().toLowerCase() ==
        seedBMnemonic.join(' ').trim().toLowerCase()) {
      throw const MoneroSeedBoundaryException(
        '[Fail-Closed] Proibido reutilizar a Seed A de mensageria como Seed B da carteira Monero.',
      );
    }
  }
}

/// Anúncio P2P Monero assinado criptograficamente via Ed25519 com nonce e expiração (Fase 6 / Fase 7).
class SignedMoneroAd {
  static final RegExp _ed25519PubHexRe = RegExp(r'^[0-9a-fA-F]{64}$');
  static final RegExp _ed25519SigHexRe = RegExp(r'^[0-9a-fA-F]{128}$');

  /// Registro em memória de digests canônicos cuja assinatura Ed25519 foi comprovada matematicamente.
  static final Set<String> _verifiedOrderDigests = <String>{};

  final MoneroP2pOrder order;
  final SignedRecord signedRecord;

  const SignedMoneroAd({
    required this.order,
    required this.signedRecord,
  });

  static void validatePriceAndLimits({
    required double pricePerXmr,
    required double minFiatLimit,
    required double maxFiatLimit,
    required String paymentMethod,
  }) {
    if (pricePerXmr.isNaN || pricePerXmr.isInfinite || pricePerXmr <= 0) {
      throw ArgumentError('O preço por XMR deve ser maior que zero.');
    }
    if (minFiatLimit.isNaN || minFiatLimit.isInfinite || minFiatLimit <= 0) {
      throw ArgumentError('O limite mínimo fiat deve ser maior que zero.');
    }
    if (maxFiatLimit.isNaN ||
        maxFiatLimit.isInfinite ||
        maxFiatLimit < minFiatLimit) {
      throw ArgumentError(
        'O limite máximo fiat deve ser maior ou igual ao limite mínimo.',
      );
    }
    if (paymentMethod.trim().isEmpty) {
      throw ArgumentError('O método de pagamento não pode ser vazio.');
    }
  }

  static Future<SignedMoneroAd> createSigned({
    required NixIdentity signer,
    required String orderId,
    required String traderName,
    required MoneroP2pSide side,
    required String fiatCurrency,
    required double pricePerXmr,
    required double minFiatLimit,
    required double maxFiatLimit,
    required String paymentMethod,
    String notes = 'Liberação P2P imediata após confirmação na blockchain Monero.',
    String publicationState = 'local_signed',
    Duration ttl = const Duration(hours: 12),
    DateTime? now,
  }) async {
    validatePriceAndLimits(
      pricePerXmr: pricePerXmr,
      minFiatLimit: minFiatLimit,
      maxFiatLimit: maxFiatLimit,
      paymentMethod: paymentMethod,
    );
    final payload = {
      'orderId': orderId,
      'traderPublicId': signer.publicId,
      'side': side.name,
      'fiat': fiatCurrency,
      'pricePerXmr': pricePerXmr,
      'minFiat': minFiatLimit,
      'maxFiat': maxFiatLimit,
      'method': paymentMethod.trim(),
    };
    final record = await SignedRecord.create(
      signer: signer,
      recordType: 'nix.monero.ad.v1',
      payload: payload,
      ttl: ttl,
      now: now,
    );
    final wire = jsonEncode({
      'recordType': record.recordType,
      'issuer': record.issuerEd25519Hex,
      'nonce': record.nonceHex,
      'iat': record.issuedAtEpochMs,
      'exp': record.expiresAtEpochMs,
      'payload': record.payload,
      'sig': record.signatureHex,
    });
    final verified = await record.verify(now: now);
    final order = MoneroP2pOrder(
      id: orderId,
      traderName: traderName,
      traderPublicId: signer.publicId,
      side: side,
      fiatCurrency: fiatCurrency,
      pricePerXmr: pricePerXmr,
      minFiatLimit: minFiatLimit,
      maxFiatLimit: maxFiatLimit,
      paymentMethod: paymentMethod.trim(),
      signedManifestHash: signer.ed25519PublicHex,
      signatureHex: record.signatureHex,
      nonceHex: record.nonceHex,
      issuedAtEpochMs: record.issuedAtEpochMs,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        record.expiresAtEpochMs,
        isUtc: true,
      ),
      isSignatureVerified: verified,
      publicationState: publicationState,
      wireJson: wire,
      notes: notes,
    );
    if (verified) {
      _verifiedOrderDigests.add(computeCanonicalOrderDigest(order));
    }
    return SignedMoneroAd(order: order, signedRecord: record);
  }

  String toWireJson() => jsonEncode({
        'recordType': signedRecord.recordType,
        'issuer': signedRecord.issuerEd25519Hex,
        'nonce': signedRecord.nonceHex,
        'iat': signedRecord.issuedAtEpochMs,
        'exp': signedRecord.expiresAtEpochMs,
        'payload': signedRecord.payload,
        'sig': signedRecord.signatureHex,
      });

  static String computeCanonicalOrderDigest(MoneroP2pOrder order) {
    final canonical = jsonEncode({
      'id': order.id,
      'traderPublicId': order.traderPublicId,
      'side': order.side.name,
      'fiat': order.fiatCurrency,
      'pricePerXmr': order.pricePerXmr,
      'minFiat': order.minFiatLimit,
      'maxFiat': order.maxFiatLimit,
      'method': order.paymentMethod.trim(),
      'issuer': order.signedManifestHash.toLowerCase(),
      'nonce': order.nonceHex ?? '',
      'iat': order.issuedAtEpochMs ?? 0,
      'exp': order.expiresAt?.toUtc().millisecondsSinceEpoch ?? 0,
      'sig': (order.signatureHex ?? '').toLowerCase(),
    });
    return std_crypto.sha256.convert(utf8.encode(canonical)).toString();
  }

  /// Registra um digest de ordem pré-assinada após validação Ed25519 explícita.
  static void registerPreVerifiedOrder(MoneroP2pOrder order) {
    if (_ed25519PubHexRe.hasMatch(order.signedManifestHash) &&
        order.signatureHex != null &&
        _ed25519SigHexRe.hasMatch(order.signatureHex!)) {
      _verifiedOrderDigests.add(computeCanonicalOrderDigest(order));
    }
  }

  /// Verifica matematicamente a assinatura Ed25519, limites, expiração e anti-replay da ordem.
  static Future<bool> verifyOrderCryptographically(
    MoneroP2pOrder order, {
    ReplayGuard? replayGuard,
    DateTime? now,
  }) async {
    try {
      validatePriceAndLimits(
        pricePerXmr: order.pricePerXmr,
        minFiatLimit: order.minFiatLimit,
        maxFiatLimit: order.maxFiatLimit,
        paymentMethod: order.paymentMethod,
      );
      if (!_ed25519PubHexRe.hasMatch(order.signedManifestHash)) return false;
      if (order.signatureHex == null ||
          !_ed25519SigHexRe.hasMatch(order.signatureHex!)) {
        return false;
      }
      if (order.nonceHex == null || order.nonceHex!.trim().isEmpty) {
        return false;
      }
      if (order.issuedAtEpochMs == null || order.expiresAt == null) {
        return false;
      }

      final record = SignedRecord(
        recordType: 'nix.monero.ad.v1',
        issuerEd25519Hex: order.signedManifestHash.toLowerCase(),
        nonceHex: order.nonceHex!,
        issuedAtEpochMs: order.issuedAtEpochMs!,
        expiresAtEpochMs: order.expiresAt!.toUtc().millisecondsSinceEpoch,
        payload: {
          'orderId': order.id,
          'traderPublicId': order.traderPublicId,
          'side': order.side.name,
          'fiat': order.fiatCurrency,
          'pricePerXmr': order.pricePerXmr,
          'minFiat': order.minFiatLimit,
          'maxFiat': order.maxFiatLimit,
          'method': order.paymentMethod.trim(),
        },
        signatureHex: order.signatureHex!.toLowerCase(),
      );
      final ok = await record.verify(now: now, replayGuard: replayGuard);
      final digest = computeCanonicalOrderDigest(order);
      if (ok) {
        _verifiedOrderDigests.add(digest);
      } else {
        _verifiedOrderDigests.remove(digest);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Verificação síncrona para a árvore de widgets apoiada exclusivamente em registros Ed25519 verificados.
  static bool verifyOrderSync(
    MoneroP2pOrder order, {
    Map<String, String>? consumedNonceToOrderId,
    DateTime? now,
  }) {
    final currentNow = now ?? DateTime.now();
    if (!order.isSignatureVerified) return false;
    if (order.expiresAt == null || currentNow.isAfter(order.expiresAt!)) {
      return false;
    }
    try {
      validatePriceAndLimits(
        pricePerXmr: order.pricePerXmr,
        minFiatLimit: order.minFiatLimit,
        maxFiatLimit: order.maxFiatLimit,
        paymentMethod: order.paymentMethod,
      );
    } catch (_) {
      return false;
    }
    if (!_ed25519PubHexRe.hasMatch(order.signedManifestHash)) return false;
    if (order.signatureHex == null ||
        !_ed25519SigHexRe.hasMatch(order.signatureHex!)) {
      return false;
    }
    if (order.nonceHex == null || order.nonceHex!.trim().length < 8) {
      return false;
    }
    final digest = computeCanonicalOrderDigest(order);
    if (!_verifiedOrderDigests.contains(digest)) {
      return false;
    }
    if (consumedNonceToOrderId != null) {
      final nonceKey =
          '${order.signedManifestHash.toLowerCase()}:${order.nonceHex}';
      final existingOrderId = consumedNonceToOrderId[nonceKey];
      if (existingOrderId != null && existingOrderId != order.id) {
        return false;
      }
      consumedNonceToOrderId[nonceKey] = order.id;
    }
    return true;
  }

  static Future<bool> verifyWireJson(
    String rawJson, {
    required ReplayGuard replayGuard,
    DateTime? now,
  }) async {
    try {
      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final record = SignedRecord(
        recordType: map['recordType'] as String,
        issuerEd25519Hex: map['issuer'] as String,
        nonceHex: map['nonce'] as String,
        issuedAtEpochMs: (map['iat'] as num).toInt(),
        expiresAtEpochMs: (map['exp'] as num).toInt(),
        payload: Map<String, dynamic>.from(map['payload'] as Map),
        signatureHex: map['sig'] as String,
      );
      if (record.recordType != 'nix.monero.ad.v1') return false;
      final price = (record.payload['pricePerXmr'] as num?)?.toDouble() ?? 0;
      final minF = (record.payload['minFiat'] as num?)?.toDouble() ?? 0;
      final maxF = (record.payload['maxFiat'] as num?)?.toDouble() ?? 0;
      final method = (record.payload['method'] as String?) ?? 'PIX';
      validatePriceAndLimits(
        pricePerXmr: price,
        minFiatLimit: minF,
        maxFiatLimit: maxF,
        paymentMethod: method,
      );
      return await record.verify(now: now, replayGuard: replayGuard);
    } catch (_) {
      return false;
    }
  }
}
