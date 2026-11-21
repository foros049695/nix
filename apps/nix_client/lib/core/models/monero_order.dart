import 'member.dart';

enum MoneroP2pSide {
  buy,  // Comprar
  sell, // Vender
}

enum CryptoAsset {
  xmr('XMR', 'Monero'),
  btc('BTC', 'Bitcoin');

  const CryptoAsset(this.code, this.name);
  final String code;
  final String name;
}

/// Moedas de cotação das ofertas. Os códigos são preservados no registro assinado.
enum MoneroFiat {
  brl('BRL', 'Real brasileiro', 'R\$'),
  usd('USD', 'Dólar americano', '\$'),
  eur('EUR', 'Euro', '€'),
  cny('CNY', 'Yuan chinês', 'CN¥'),
  ars('ARS', 'Peso argentino', 'AR\$'),
  mxn('MXN', 'Peso mexicano', 'MX\$'),
  clp('CLP', 'Peso chileno', 'CL\$'),
  cop('COP', 'Peso colombiano', 'CO\$'),
  uyu('UYU', 'Peso uruguaio', '\$U'),
  gbp('GBP', 'Libra esterlina', '£'),
  jpy('JPY', 'Iene japonês', 'JP¥'),
  cad('CAD', 'Dólar canadense', 'CA\$'),
  aud('AUD', 'Dólar australiano', 'A\$'),
  chf('CHF', 'Franco suíço', 'CHF'),
  inr('INR', 'Rúpia indiana', '₹');

  const MoneroFiat(this.code, this.label, this.symbol);

  final String code;
  final String label;
  final String symbol;

  static String symbolFor(String code) {
    for (final currency in values) {
      if (code == currency.code) return currency.symbol;
    }
    return code;
  }
}

class MoneroP2pOrder {
  final String id;
  final String traderName;
  final String traderPublicId;
  final NixTrustLevel trustLevel;
  final double reputationScore;
  final int completedTrades;
  final MoneroP2pSide side;
  final CryptoAsset asset;
  final String fiatCurrency;
  final double pricePerXmr;
  final double minFiatLimit;
  final double maxFiatLimit;
  final String paymentMethod; // 'PIX', 'TED', 'SEPA', 'Wise', 'Dinheiro'
  final bool isOnline;
  final int avgResponseMinutes;
  final String signedManifestHash;
  final String? signatureHex;
  final String? nonceHex;
  final int? issuedAtEpochMs;
  final DateTime? expiresAt;
  final bool isSignatureVerified;
  final String publicationState; // 'local_signed', 'relay_published', 'unverified'
  final String? wireJson;
  final String notes;

  const MoneroP2pOrder({
    required this.id,
    required this.traderName,
    required this.traderPublicId,
    this.trustLevel = NixTrustLevel.level3Green,
    this.reputationScore = 99.5,
    this.completedTrades = 84,
    required this.side,
    this.asset = CryptoAsset.xmr,
    required this.fiatCurrency,
    required this.pricePerXmr,
    required this.minFiatLimit,
    required this.maxFiatLimit,
    required this.paymentMethod,
    this.isOnline = true,
    this.avgResponseMinutes = 4,
    required this.signedManifestHash,
    this.signatureHex,
    this.nonceHex,
    this.issuedAtEpochMs,
    this.expiresAt,
    this.isSignatureVerified = false,
    this.publicationState = 'local_signed',
    this.wireJson,
    this.notes = 'Liberação P2P imediata após confirmação na blockchain Monero.',
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  MoneroP2pOrder copyWith({
    String? id,
    String? traderName,
    String? traderPublicId,
    NixTrustLevel? trustLevel,
    double? reputationScore,
    int? completedTrades,
    MoneroP2pSide? side,
    CryptoAsset? asset,
    String? fiatCurrency,
    double? pricePerXmr,
    double? minFiatLimit,
    double? maxFiatLimit,
    String? paymentMethod,
    bool? isOnline,
    int? avgResponseMinutes,
    String? signedManifestHash,
    String? signatureHex,
    String? nonceHex,
    int? issuedAtEpochMs,
    DateTime? expiresAt,
    bool? isSignatureVerified,
    String? publicationState,
    String? wireJson,
    String? notes,
  }) {
    return MoneroP2pOrder(
      id: id ?? this.id,
      traderName: traderName ?? this.traderName,
      traderPublicId: traderPublicId ?? this.traderPublicId,
      trustLevel: trustLevel ?? this.trustLevel,
      reputationScore: reputationScore ?? this.reputationScore,
      completedTrades: completedTrades ?? this.completedTrades,
      side: side ?? this.side,
      asset: asset ?? this.asset,
      fiatCurrency: fiatCurrency ?? this.fiatCurrency,
      pricePerXmr: pricePerXmr ?? this.pricePerXmr,
      minFiatLimit: minFiatLimit ?? this.minFiatLimit,
      maxFiatLimit: maxFiatLimit ?? this.maxFiatLimit,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isOnline: isOnline ?? this.isOnline,
      avgResponseMinutes: avgResponseMinutes ?? this.avgResponseMinutes,
      signedManifestHash: signedManifestHash ?? this.signedManifestHash,
      signatureHex: signatureHex ?? this.signatureHex,
      nonceHex: nonceHex ?? this.nonceHex,
      issuedAtEpochMs: issuedAtEpochMs ?? this.issuedAtEpochMs,
      expiresAt: expiresAt ?? this.expiresAt,
      isSignatureVerified: isSignatureVerified ?? this.isSignatureVerified,
      publicationState: publicationState ?? this.publicationState,
      wireJson: wireJson ?? this.wireJson,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'traderName': traderName,
        'traderPublicId': traderPublicId,
        'trustLevel': trustLevel.name,
        'reputationScore': reputationScore,
        'completedTrades': completedTrades,
        'side': side.name,
        'asset': asset.name,
        'fiatCurrency': fiatCurrency,
        'pricePerXmr': pricePerXmr,
        'minFiatLimit': minFiatLimit,
        'maxFiatLimit': maxFiatLimit,
        'paymentMethod': paymentMethod,
        'isOnline': isOnline,
        'avgResponseMinutes': avgResponseMinutes,
        'signedManifestHash': signedManifestHash,
        'signatureHex': signatureHex,
        'nonceHex': nonceHex,
        'issuedAtEpochMs': issuedAtEpochMs,
        'expiresAtMs': expiresAt?.toUtc().millisecondsSinceEpoch,
        'isSignatureVerified': isSignatureVerified,
        'publicationState': publicationState,
        'wireJson': wireJson,
        'notes': notes,
      };

  factory MoneroP2pOrder.fromJson(Map<String, dynamic> json) {
    final expMs = (json['expiresAtMs'] as num?)?.toInt();
    return MoneroP2pOrder(
      id: json['id'] as String,
      traderName: json['traderName'] as String,
      traderPublicId: json['traderPublicId'] as String,
      trustLevel: NixTrustLevel.values.firstWhere(
        (t) => t.name == json['trustLevel'],
        orElse: () => NixTrustLevel.level2Yellow,
      ),
      reputationScore: (json['reputationScore'] as num?)?.toDouble() ?? 99.0,
      completedTrades: (json['completedTrades'] as num?)?.toInt() ?? 0,
      side: json['side'] == 'buy' ? MoneroP2pSide.buy : MoneroP2pSide.sell,
      asset: CryptoAsset.values.firstWhere(
        (a) => a.name == json['asset'],
        orElse: () => CryptoAsset.xmr,
      ),
      fiatCurrency: json['fiatCurrency'] as String? ?? 'BRL',
      pricePerXmr: (json['pricePerXmr'] as num).toDouble(),
      minFiatLimit: (json['minFiatLimit'] as num).toDouble(),
      maxFiatLimit: (json['maxFiatLimit'] as num).toDouble(),
      paymentMethod: json['paymentMethod'] as String,
      isOnline: json['isOnline'] as bool? ?? true,
      avgResponseMinutes: (json['avgResponseMinutes'] as num?)?.toInt() ?? 4,
      signedManifestHash: json['signedManifestHash'] as String,
      signatureHex: json['signatureHex'] as String?,
      nonceHex: json['nonceHex'] as String?,
      issuedAtEpochMs: (json['issuedAtEpochMs'] as num?)?.toInt(),
      expiresAt: expMs != null
          ? DateTime.fromMillisecondsSinceEpoch(expMs, isUtc: true)
          : null,
      isSignatureVerified: json['isSignatureVerified'] as bool? ?? false,
      publicationState: json['publicationState'] as String? ?? 'local_signed',
      wireJson: json['wireJson'] as String?,
      notes: json['notes'] as String? ?? '',
    );
  }

  String get fiatSymbol => MoneroFiat.symbolFor(fiatCurrency);

  String get formattedPrice => '$fiatSymbol ${pricePerXmr.toStringAsFixed(2)} / ${asset.code}';
  String get formattedLimits =>
      '$fiatSymbol ${minFiatLimit.toStringAsFixed(0)} - $fiatSymbol ${maxFiatLimit.toStringAsFixed(0)}';
}
