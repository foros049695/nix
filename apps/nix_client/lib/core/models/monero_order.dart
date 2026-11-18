import 'member.dart';

enum MoneroP2pSide {
  buy,  // Comprar XMR
  sell, // Vender XMR
}

class MoneroP2pOrder {
  final String id;
  final String traderName;
  final String traderPublicId;
  final NixTrustLevel trustLevel;
  final double reputationScore; // ex: 99.4%
  final int completedTrades;
  final MoneroP2pSide side; // buy ou sell
  final String fiatCurrency; // 'BRL', 'USD', 'EUR'
  final double pricePerXmr;
  final double minFiatLimit;
  final double maxFiatLimit;
  final String paymentMethod; // 'PIX', 'TED', 'SEPA', 'Wise', 'Dinheiro'
  final bool isOnline;
  final int avgResponseMinutes;
  final String signedManifestHash;
  final String notes;

  const MoneroP2pOrder({
    required this.id,
    required this.traderName,
    required this.traderPublicId,
    this.trustLevel = NixTrustLevel.level3Green,
    this.reputationScore = 99.5,
    this.completedTrades = 84,
    required this.side,
    required this.fiatCurrency,
    required this.pricePerXmr,
    required this.minFiatLimit,
    required this.maxFiatLimit,
    required this.paymentMethod,
    this.isOnline = true,
    this.avgResponseMinutes = 4,
    required this.signedManifestHash,
    this.notes = 'Liberação P2P imediata após confirmação na blockchain Monero.',
  });

  String get fiatSymbol {
    switch (fiatCurrency) {
      case 'BRL':
        return 'R\$';
      case 'EUR':
        return '€';
      case 'USD':
      default:
        return '\$';
    }
  }

  String get formattedPrice => '$fiatSymbol ${pricePerXmr.toStringAsFixed(2)} / XMR';
  String get formattedLimits =>
      '$fiatSymbol ${minFiatLimit.toStringAsFixed(0)} - $fiatSymbol ${maxFiatLimit.toStringAsFixed(0)}';
}
