import 'package:equatable/equatable.dart';

/// Modelo unificado para ofertas de compra/venda no Mercado Cripto.
///
/// - `kind` identifica a moeda (ex.: "btc", "xmr").
/// - `price` é o valor em fiat (USD, EUR…) usando fundos sintéticos.
/// - `isBuy` define se a oferta é de compra (`true`) ou venda (`false`).
/// - Campos opcionais (`creator`, `album`, `releaseYear`) são mantidos
///   para compatibilidade com as interfaces existentes.
class CryptoMarketItem extends Equatable {
  final String id;
  final String kind; // moeda: "btc", "xmr", ...
  final String title; // descrição curta da oferta
  final String? creator;
  final String? album;
  final int? releaseYear;
  final double price; // preço em fiat (synthetic)
  final String currency; // ex.: "USD", "EUR"
  final bool isBuy; // true = compra, false = venda
  final String? summary; // texto livre explicativo
  final DateTime updatedAt;

  const CryptoMarketItem({
    required this.id,
    required this.kind,
    required this.title,
    this.creator,
    this.album,
    this.releaseYear,
    required this.price,
    required this.currency,
    required this.isBuy,
    this.summary,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  CryptoMarketItem copyWith({
    String? id,
    String? kind,
    String? title,
    String? creator,
    String? album,
    int? releaseYear,
    double? price,
    String? currency,
    bool? isBuy,
    String? summary,
    DateTime? updatedAt,
  }) =>
      CryptoMarketItem(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        title: title ?? this.title,
        creator: creator ?? this.creator,
        album: album ?? this.album,
        releaseYear: releaseYear ?? this.releaseYear,
        price: price ?? this.price,
        currency: currency ?? this.currency,
        isBuy: isBuy ?? this.isBuy,
        summary: summary ?? this.summary,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  List<Object?> get props => [
        id,
        kind,
        title,
        creator,
        album,
        releaseYear,
        price,
        currency,
        isBuy,
        summary,
        updatedAt,
      ];
}
