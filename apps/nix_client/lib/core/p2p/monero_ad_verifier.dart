import 'dart:convert';
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

/// Anúncio P2P Monero assinado criptograficamente via Ed25519 com nonce e expiração (Fase 6).
class SignedMoneroAd {
  final MoneroP2pOrder order;
  final SignedRecord signedRecord;

  const SignedMoneroAd({
    required this.order,
    required this.signedRecord,
  });

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
    Duration ttl = const Duration(hours: 12),
    DateTime? now,
  }) async {
    final payload = {
      'orderId': orderId,
      'traderPublicId': signer.publicId,
      'side': side.name,
      'fiat': fiatCurrency,
      'pricePerXmr': pricePerXmr,
      'minFiat': minFiatLimit,
      'maxFiat': maxFiatLimit,
      'method': paymentMethod,
    };
    final record = await SignedRecord.create(
      signer: signer,
      recordType: 'nix.monero.ad.v1',
      payload: payload,
      ttl: ttl,
      now: now,
    );
    final order = MoneroP2pOrder(
      id: orderId,
      traderName: traderName,
      traderPublicId: signer.publicId,
      side: side,
      fiatCurrency: fiatCurrency,
      pricePerXmr: pricePerXmr,
      minFiatLimit: minFiatLimit,
      maxFiatLimit: maxFiatLimit,
      paymentMethod: paymentMethod,
      signedManifestHash: signer.ed25519PublicHex,
      signatureHex: record.signatureHex,
      nonceHex: record.nonceHex,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        record.expiresAtEpochMs,
        isUtc: true,
      ),
      isSignatureVerified: false, // Só vira verificado após check Ed25519 explícito!
    );
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
      if (price <= 0 || minF <= 0 || maxF < minF) return false;
      return await record.verify(now: now, replayGuard: replayGuard);
    } catch (_) {
      return false;
    }
  }
}
