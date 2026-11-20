import 'package:flutter/material.dart';

class PaymentMethodPicker extends StatelessWidget {
  const PaymentMethodPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  static const methods = <String, IconData>{
    'PIX': Icons.pix,
    'Boleto': Icons.receipt_long_rounded,
    'BTC / Lightning': Icons.currency_bitcoin_rounded,
    'Monero (XMR)': Icons.currency_exchange_rounded,
    'Tether (USDT)': Icons.paid_outlined,
    'USD Coin (USDC)': Icons.paid_outlined,
    'Dai (DAI)': Icons.toll_outlined,
    'PayPal USD (PYUSD)': Icons.payments_outlined,
    'Gift card Amazon': Icons.card_giftcard_rounded,
    'Gift card Steam': Icons.sports_esports_outlined,
    'Gift card Google Play': Icons.shop_outlined,
    'Gift card Apple': Icons.phone_iphone_rounded,
    'Gift card Xbox': Icons.videogame_asset_outlined,
    'Gift card PlayStation': Icons.gamepad_outlined,
    'Gift card Netflix': Icons.movie_outlined,
    'Gift card Spotify': Icons.headphones_rounded,
    'Dinheiro': Icons.money_rounded,
    'TED': Icons.account_balance_outlined,
    'SEPA': Icons.account_balance_outlined,
    'Wise': Icons.swap_horiz_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      menuMaxHeight: 360,
      decoration: const InputDecoration(labelText: 'Forma de pagamento'),
      items: [
        for (final item in methods.entries)
          DropdownMenuItem(
            value: item.key,
            child: Row(
              children: [
                Icon(item.value, size: 19),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(item.key, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
      onChanged: (method) {
        if (method != null) onChanged(method);
      },
    );
  }
}
