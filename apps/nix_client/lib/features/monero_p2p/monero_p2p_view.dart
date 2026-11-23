import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/member.dart';
import '../../core/models/monero_order.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../design/nix_surfaces.dart';
import 'trade_simulation_dialog.dart';
import 'private_trade_room_view.dart';
import 'payment_method_picker.dart';

/// Aba Monero Non-Custodial P2P Marketplace.
/// Exibe anúncios assinados com verificação Ed25519 local, controle de expiração,
/// proteção anti-replay por nonce e zero custódia de chaves ou fundos.
class MoneroP2pView extends StatelessWidget {
  const MoneroP2pView({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final accent = context.accentColor;
    final accentText = context.accentTextColor;

    return ListenableBuilder(
      listenable: nixState.moneroFilters,
      builder: (context, _) {
        final orders = nixState.moneroFilters.filteredOrders;

        return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 740;

        return Container(
          color: NixColors.background,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: () => PrivateTradeRoomView.open(context, nixState),
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Criar sala'),
                      ),
                      TextButton.icon(
                        onPressed: () => PrivateTradeRoomView.open(context, nixState, join: true),
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Usar convite'),
                      ),
                      TextButton.icon(
                        onPressed: () => showDialog<void>(
                          context: context, builder: (_) => const TradeSimulationDialog(),
                        ),
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('Simular negociação'),
                      ),
                    ],
                  ),
                ),
              ),
              // Cabeçalho Responsivo do Mercado P2P
              Container(
                margin: const EdgeInsets.fromLTRB(10, 4, 13, 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: nixFrameDecoration(context, background: context.surfaceSidebarColor),
                child: isNarrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.currency_exchange_rounded, size: 18, color: accentText),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'MERCADO CRIPTO (NON-CUSTODIAL)',
                                  style: TextStyle(
                                    color: NixColors.textPrimary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ElevatedButton.icon(
                                key: const Key('create_monero_order_button'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: context.onAccentColor,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: NixTokens.borderButtonCompact),
                                ),
                                onPressed: () => _showCreateOrderDialog(context, nixState),
                                icon: const Icon(Icons.add_rounded, size: 15),
                                label: const Text('Anúncio', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Assinaturas Ed25519 · Anti-replay por nonce · Zero custódia e sem KYC',
                            style: TextStyle(color: NixColors.textMuted, fontSize: 10),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Icon(Icons.currency_exchange_rounded, size: 18, color: accentText),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MERCADO CRIPTO DESCENTRALIZADO (NON-CUSTODIAL)',
                                  style: TextStyle(
                                    color: NixColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Assinaturas Ed25519 verificadas · Anti-replay por nonce · Zero custódia e sem KYC',
                                  style: TextStyle(color: NixColors.textMuted, fontSize: 10.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            key: const Key('create_monero_order_button'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: context.onAccentColor,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: NixTokens.borderButtonCompact),
                            ),
                            onPressed: () => _showCreateOrderDialog(context, nixState),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Criar Anúncio', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
              ),

              // Banner de Segurança Non-Custodial & Anti-Fraude
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 15, color: NixColors.accentGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Aviso Non-Custodial & Anti-Fraude: O Nix apenas exibe ordens assinadas e abre negociação E2EE. Nunca transfira XMR, BTC ou fiat para endereços fora do canal criptografado verificado nem ignore alertas de assinatura.',
                        style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),

              // Filtros Responsivos: Comprar / Vender, Moedas Fiat e Método de Pagamento
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: NixColors.surfaceSidebar,
                  border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
                ),
                child: Column(
                  children: [
                    if (isNarrow) ...[
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: NixColors.surfaceCard,
                              borderRadius: NixTokens.borderButtonCompact,
                              border: Border.all(color: NixColors.surfaceBorder),
                            ),
                            child: Wrap(
                              children: [
                                _assetButton(
                                  context: context,
                                  title: 'XMR',
                                  isSelected: nixState.moneroSelectedAsset == CryptoAsset.xmr,
                                  onTap: () => nixState.setMoneroAsset(CryptoAsset.xmr),
                                ),
                                _assetButton(
                                  context: context,
                                  title: 'BTC',
                                  isSelected: nixState.moneroSelectedAsset == CryptoAsset.btc,
                                  onTap: () => nixState.setMoneroAsset(CryptoAsset.btc),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: NixColors.surfaceCard,
                              borderRadius: NixTokens.borderButtonCompact,
                              border: Border.all(color: NixColors.surfaceBorder),
                            ),
                            child: Wrap(
                              children: [
                                _sideButton(
                                  context: context,
                                  title: nixState.moneroSelectedAsset == CryptoAsset.btc ? 'Comprar BTC' : 'Comprar XMR',
                                  isSelected: nixState.moneroSelectedSide == MoneroP2pSide.sell,
                                  onTap: () => nixState.setMoneroSide(MoneroP2pSide.sell),
                                ),
                                _sideButton(
                                  context: context,
                                  title: nixState.moneroSelectedAsset == CryptoAsset.btc ? 'Vender BTC' : 'Vender XMR',
                                  isSelected: nixState.moneroSelectedSide == MoneroP2pSide.buy,
                                  onTap: () => nixState.setMoneroSide(MoneroP2pSide.buy),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 132,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: NixColors.surfaceCard,
                              borderRadius: NixTokens.borderButtonCompact,
                              border: Border.all(color: NixColors.surfaceBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: nixState.moneroSelectedFiat,
                                dropdownColor: NixColors.surfaceElevatedHigh,
                                style: TextStyle(
                                  color: NixColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                items: _fiatOptions(),
                                selectedItemBuilder: _selectedFiatLabels,
                                menuMaxHeight: 380,
                                menuWidth: 235,
                                onChanged: (v) {
                                  if (v != null) nixState.setMoneroFiat(v);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: nixState.setMoneroSearchQuery,
                        style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: 'Filtrar por método de pagamento, trader ou notas...',
                          prefixIcon: Icon(Icons.search, size: 16, color: NixColors.textMuted),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: NixTokens.borderInput,
                            borderSide: BorderSide(color: NixColors.surfaceBorder),
                          ),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: NixColors.surfaceCard,
                              borderRadius: NixTokens.borderButtonCompact,
                              border: Border.all(color: NixColors.surfaceBorder),
                            ),
                            child: Row(
                              children: [
                                _assetButton(
                                  context: context,
                                  title: 'XMR',
                                  isSelected: nixState.moneroSelectedAsset == CryptoAsset.xmr,
                                  onTap: () => nixState.setMoneroAsset(CryptoAsset.xmr),
                                ),
                                _assetButton(
                                  context: context,
                                  title: 'BTC',
                                  isSelected: nixState.moneroSelectedAsset == CryptoAsset.btc,
                                  onTap: () => nixState.setMoneroAsset(CryptoAsset.btc),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            decoration: BoxDecoration(
                              color: NixColors.surfaceCard,
                              borderRadius: NixTokens.borderButtonCompact,
                              border: Border.all(color: NixColors.surfaceBorder),
                            ),
                            child: Row(
                              children: [
                                _sideButton(
                                  context: context,
                                  title: nixState.moneroSelectedAsset == CryptoAsset.btc ? 'Comprar BTC' : 'Comprar XMR',
                                  isSelected: nixState.moneroSelectedSide == MoneroP2pSide.sell,
                                  onTap: () => nixState.setMoneroSide(MoneroP2pSide.sell),
                                ),
                                _sideButton(
                                  context: context,
                                  title: nixState.moneroSelectedAsset == CryptoAsset.btc ? 'Vender BTC' : 'Vender XMR',
                                  isSelected: nixState.moneroSelectedSide == MoneroP2pSide.buy,
                                  onTap: () => nixState.setMoneroSide(MoneroP2pSide.buy),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: NixColors.surfaceCard,
                              borderRadius: NixTokens.borderButtonCompact,
                              border: Border.all(color: NixColors.surfaceBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: nixState.moneroSelectedFiat,
                                dropdownColor: NixColors.surfaceElevatedHigh,
                                style: TextStyle(
                                  color: NixColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                items: _fiatOptions(),
                                selectedItemBuilder: _selectedFiatLabels,
                                menuMaxHeight: 380,
                                menuWidth: 235,
                                onChanged: (v) {
                                  if (v != null) nixState.setMoneroFiat(v);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              onChanged: nixState.setMoneroSearchQuery,
                              style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5),
                              decoration: InputDecoration(
                                hintText: 'Filtrar por método de pagamento, trader ou notas...',
                                prefixIcon: Icon(Icons.search, size: 16, color: NixColors.textMuted),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: NixTokens.borderInput,
                                  borderSide: BorderSide(color: NixColors.surfaceBorder),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _paymentMethodChip(context, nixState, 'PIX'),
                          _paymentMethodChip(context, nixState, 'Dinheiro'),
                          _paymentMethodChip(context, nixState, 'SEPA'),
                          _paymentMethodChip(context, nixState, 'Wise'),
                          _paymentMethodChip(context, nixState, 'TED'),
                          if (nixState.moneroSelectedPaymentMethod.isNotEmpty &&
                              nixState.moneroSelectedPaymentMethod != 'Todos')
                            IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              tooltip: 'Limpar filtro de pagamento',
                              onPressed: () => nixState.setMoneroPaymentMethod(''),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

                  ],
                ),
              ),
              if (orders.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Nenhuma oferta encontrada para os filtros selecionados.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: NixColors.textSecondary),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final order = orders[index];
                      final valid = nixState.verifyMoneroOrder(order);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _MoneroOrderCard(
                          order: order,
                          isCryptographicallyValid: valid,
                          onTrade: valid ? () => PrivateTradeRoomView.open(context, nixState) : null,
                        ),
                      );
                    }, childCount: orders.length),
                  ),
                ),
            ],
          ),
        );
      },
    );
      },
    );
  }

  Widget _assetButton({
    required BuildContext context,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? context.accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? context.onAccentColor : NixColors.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _sideButton({
    required BuildContext context,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? context.accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? context.onAccentColor : NixColors.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _paymentMethodChip(BuildContext context, NixState state, String method) {
    final isSelected = state.moneroSelectedPaymentMethod == method;
    final accent = context.accentColor;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () {
          if (isSelected) {
            state.setMoneroPaymentMethod('');
          } else {
            state.setMoneroPaymentMethod(method);
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? accent : NixColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isSelected ? accent : NixColors.surfaceBorder),
          ),
          child: Text(
            method,
            style: TextStyle(
              color: isSelected ? context.onAccentColor : NixColors.textSecondary,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  static List<DropdownMenuItem<String>> _fiatOptions() => [
    for (final currency in MoneroFiat.values)
      DropdownMenuItem(
        value: currency.code,
        child: Text('${currency.code} · ${currency.label}', overflow: TextOverflow.ellipsis),
      ),
  ];

  static List<Widget> _selectedFiatLabels(BuildContext context) => [
    for (final currency in MoneroFiat.values)
      Center(child: Text('${currency.code} (${currency.symbol})')),
  ];

  void _showCreateOrderDialog(BuildContext context, NixState state) {
    var asset = state.moneroSelectedAsset ?? CryptoAsset.xmr;
    final priceCtrl = TextEditingController(text: asset == CryptoAsset.btc ? '520000.00' : '850.00');
    final minLimitCtrl = TextEditingController(text: '100');
    final maxLimitCtrl = TextEditingController(text: '5000');
    var paymentMethod = 'PIX';
    final notesCtrl = TextEditingController(text: 'Liberação imediata em subendereço único.');
    MoneroP2pSide side = state.moneroSelectedSide;
    var fiat = state.moneroSelectedFiat;
    String? formError;
    bool isSigning = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final accent = context.accentColor;
          return AlertDialog(
            backgroundColor: NixColors.surfaceElevatedHigh,
            title: Text(
              'Assinar Oferta P2P Local (Ed25519)',
              style: TextStyle(color: NixColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sua oferta será assinada criptograficamente com Ed25519, receberá nonce anti-replay e ficará armazenada localmente.',
                      style: TextStyle(color: NixColors.textMuted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 14),
                    Text('CRIPTOMOEDA / ATIVO', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Monero (XMR)'),
                          selected: asset == CryptoAsset.xmr,
                          selectedColor: accent,
                          labelStyle: TextStyle(
                            color: asset == CryptoAsset.xmr ? context.onAccentColor : NixColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => setModalState(() {
                            asset = CryptoAsset.xmr;
                            if (priceCtrl.text == '520000.00' || priceCtrl.text == '520000') {
                              priceCtrl.text = '850.00';
                            }
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('Bitcoin (BTC)'),
                          selected: asset == CryptoAsset.btc,
                          selectedColor: accent,
                          labelStyle: TextStyle(
                            color: asset == CryptoAsset.btc ? context.onAccentColor : NixColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => setModalState(() {
                            asset = CryptoAsset.btc;
                            if (priceCtrl.text == '850.00' || priceCtrl.text == '850') {
                              priceCtrl.text = '520000.00';
                            }
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('TIPO DE ORDEM', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text('Quero Vender ${asset.code}'),
                          selected: side == MoneroP2pSide.sell,
                          selectedColor: accent,
                          labelStyle: TextStyle(
                            color: side == MoneroP2pSide.sell ? context.onAccentColor : NixColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => setModalState(() => side = MoneroP2pSide.sell),
                        ),
                        ChoiceChip(
                          label: Text('Quero Comprar ${asset.code}'),
                          selected: side == MoneroP2pSide.buy,
                          selectedColor: accent,
                          labelStyle: TextStyle(
                            color: side == MoneroP2pSide.buy ? context.onAccentColor : NixColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => setModalState(() => side = MoneroP2pSide.buy),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const Key('monero_order_currency'),
                      value: fiat,
                      items: _fiatOptions(),
                      selectedItemBuilder: _selectedFiatLabels,
                      isExpanded: true,
                      menuMaxHeight: 380,
                      decoration: const InputDecoration(labelText: 'Moeda de cotação'),
                      onChanged: isSigning ? null : (value) {
                        if (value != null) setModalState(() => fiat = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text('PREÇO POR ${asset.code}', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    TextField(
                      key: const Key('monero_order_price_input'),
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixText: '${MoneroFiat.symbolFor(fiat)} ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('LIMITE MÍNIMO', style: NixTokens.labelUppercase()),
                              const SizedBox(height: 6),
                              TextField(
                                key: const Key('monero_order_min_input'),
                                controller: minLimitCtrl,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('LIMITE MÁXIMO', style: NixTokens.labelUppercase()),
                              const SizedBox(height: 6),
                              TextField(
                                key: const Key('monero_order_max_input'),
                                controller: maxLimitCtrl,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('MÉTODO DE PAGAMENTO', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    PaymentMethodPicker(
                      key: const Key('monero_order_method_input'),
                      value: paymentMethod,
                      onChanged: (method) => setModalState(() => paymentMethod = method),
                    ),
                    const SizedBox(height: 12),
                    Text('INSTRUÇÕES / TERMOS P2P', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    TextField(
                      key: const Key('monero_order_notes_input'),
                      controller: notesCtrl,
                      maxLines: 2,
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        formError!,
                        key: const Key('monero_order_form_error'),
                        style: const TextStyle(color: Colors.redAccent, fontSize: 11.5),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSigning ? null : () => Navigator.pop(ctx),
                child: Text('Cancelar', style: TextStyle(color: NixColors.textMuted)),
              ),
              ElevatedButton(
                key: const Key('submit_monero_order_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: context.onAccentColor,
                ),
                onPressed: isSigning
                    ? null
                    : () async {
                        final price = double.tryParse(priceCtrl.text.trim());
                        final minL = double.tryParse(minLimitCtrl.text.trim());
                        final maxL = double.tryParse(maxLimitCtrl.text.trim());
                        final method = paymentMethod;
                        if (price == null || price <= 0) {
                          setModalState(() => formError = 'Informe um preço por ${asset.code} válido (> 0).');
                          return;
                        }
                        if (minL == null || minL <= 0) {
                          setModalState(() => formError = 'Informe um limite mínimo válido (> 0).');
                          return;
                        }
                        if (maxL == null || maxL < minL) {
                          setModalState(() => formError = 'O limite máximo deve ser >= limite mínimo.');
                          return;
                        }
                        if (method.isEmpty) {
                          setModalState(() => formError = 'Informe o método de pagamento.');
                          return;
                        }
                        setModalState(() {
                          isSigning = true;
                          formError = null;
                        });
                        try {
                          await state.createAndSignMoneroOrder(
                            side: side,
                            asset: asset,
                            fiatCurrency: fiat,
                            pricePerXmr: price,
                            minFiatLimit: minL,
                            maxFiatLimit: maxL,
                            paymentMethod: method,
                            notes: notesCtrl.text.trim(),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Oferta P2P assinada localmente com Ed25519 (não transmitida a rede externa).',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          setModalState(() {
                            isSigning = false;
                            formError = e.toString();
                          });
                        }
                      },
                child: const Text('Assinar Oferta Local', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MoneroOrderCard extends StatelessWidget {
  final MoneroP2pOrder order;
  final bool isCryptographicallyValid;
  final VoidCallback? onTrade;

  const _MoneroOrderCard({
    required this.order,
    required this.isCryptographicallyValid,
    required this.onTrade,
  });

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final isOwner = order.publicationState == 'local_signed' ||
        nixState.isMyMoneroOrder(order.id) ||
        (nixState.userProfile.publicId.isNotEmpty &&
            order.traderPublicId == nixState.userProfile.publicId);
    final accent = context.accentColor;
    final expLabel = order.expiresAt == null
        ? 'Sem expiração'
        : (order.isExpired
            ? 'Expirada'
            : 'Expira em ${order.expiresAt!.difference(DateTime.now()).inHours.clamp(1, 999)}h');
    final pubScopeLabel = order.publicationState == 'relay_published'
        ? 'PUBLICADO NO RELAY'
        : 'LOCAL ASSINADO';

    return LayoutBuilder(
      builder: (context, cardConstraints) {
        final isCompact = cardConstraints.maxWidth < 640;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: NixTokens.borderCard,
            border: Border.all(
              color: isCryptographicallyValid
                  ? NixColors.surfaceBorderStrong
                  : NixColors.accentDanger.withValues(alpha: 0.6),
            ),
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top: Trader info & trust badges
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: order.isOnline ? NixColors.accentGreen : NixColors.textMuted,
                          ),
                        ),
                        Text(
                          (RegExp(r'^Parte-[A-F0-9]{8}$').hasMatch(order.traderName)
                                  ? order.traderName : 'Anúncio P2P'),
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: (order.asset == CryptoAsset.btc
                                    ? const Color(0xFFF7931A)
                                    : NixColors.accentGreen)
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: order.asset == CryptoAsset.btc
                                  ? const Color(0xFFF7931A)
                                  : NixColors.accentGreen,
                            ),
                          ),
                          child: Text(
                            order.asset.code,
                            style: TextStyle(
                              color: order.asset == CryptoAsset.btc
                                  ? const Color(0xFFF7931A)
                                  : NixColors.accentGreen,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _orderTrustIndicator(order.trustLevel),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isCryptographicallyValid ? NixColors.accentGreen : NixColors.accentDanger)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: (isCryptographicallyValid ? NixColors.accentGreen : NixColors.accentDanger)
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            isCryptographicallyValid
                                ? 'Ed25519 OK · $pubScopeLabel · $expLabel'
                                : 'ALERTA: ASSINATURA / EXPIRAÇÃO',
                            style: TextStyle(
                              color: isCryptographicallyValid ? NixColors.accentGreen : NixColors.accentDanger,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${order.reputationScore}% avaliação · ${order.completedTrades} ordens concluídas · resposta ~${order.avgResponseMinutes}m'
                      '${order.nonceHex != null ? ' · nonce ${order.nonceHex}' : ''}',
                      style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                    ),
                    if (order.notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        order.notes,
                        style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Divider(height: 1, color: NixColors.surfaceBorder),
                    const SizedBox(height: 10),

                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('PREÇO UNITÁRIO', style: NixTokens.labelUppercase()),
                            const SizedBox(height: 2),
                            Text(
                              order.formattedPrice,
                              style: TextStyle(
                                color: NixColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'LIMITES: ${order.formattedLimits}',
                              style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: NixColors.surfaceActive,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: NixColors.surfaceBorder),
                              ),
                              child: Text(
                                order.paymentMethod,
                                style: TextStyle(
                                  color: NixColors.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (isOwner)
                                  _deleteOrderButton(context, nixState, order),
                                ElevatedButton.icon(
                                  key: Key('trade_button_${order.id}'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accent,
                                    foregroundColor: context.onAccentColor,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: NixTokens.borderButtonCompact),
                                  ),
                                  onPressed: onTrade,
                                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                                  label: Text(
                                    isCryptographicallyValid ? 'Negociar' : 'Bloqueado',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: order.isOnline ? NixColors.accentGreen : NixColors.textMuted,
                                ),
                              ),
                              Text(
                                (RegExp(r'^Parte-[A-F0-9]{8}$').hasMatch(order.traderName)
                                  ? order.traderName : 'Anúncio P2P'),
                                style: TextStyle(
                                  color: NixColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (order.asset == CryptoAsset.btc
                                          ? const Color(0xFFF7931A)
                                          : NixColors.accentGreen)
                                      .withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: order.asset == CryptoAsset.btc
                                        ? const Color(0xFFF7931A)
                                        : NixColors.accentGreen,
                                  ),
                                ),
                                child: Text(
                                  order.asset.code,
                                  style: TextStyle(
                                    color: order.asset == CryptoAsset.btc
                                        ? const Color(0xFFF7931A)
                                        : NixColors.accentGreen,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              _orderTrustIndicator(order.trustLevel),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isCryptographicallyValid ? NixColors.accentGreen : NixColors.accentDanger)
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: (isCryptographicallyValid ? NixColors.accentGreen : NixColors.accentDanger)
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  isCryptographicallyValid
                                      ? 'Ed25519 OK · $expLabel'
                                      : 'ALERTA: ASSINATURA / EXPIRAÇÃO',
                                  style: TextStyle(
                                    color: isCryptographicallyValid ? NixColors.accentGreen : NixColors.accentDanger,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${order.reputationScore}% avaliação · ${order.completedTrades} ordens concluídas · resposta ~${order.avgResponseMinutes}m'
                            '${order.nonceHex != null ? ' · nonce ${order.nonceHex}' : ''}',
                            style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            order.notes,
                            style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),

                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PREÇO UNITÁRIO', style: NixTokens.labelUppercase()),
                          const SizedBox(height: 2),
                          Text(
                            order.formattedPrice,
                            style: TextStyle(
                              color: NixColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('LIMITES', style: NixTokens.labelUppercase()),
                          const SizedBox(height: 2),
                          Text(
                            order.formattedLimits,
                            style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),

                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: NixColors.surfaceActive,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: NixColors.surfaceBorder),
                          ),
                          child: Text(
                            order.paymentMethod,
                            style: TextStyle(
                              color: NixColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (isOwner)
                              _deleteOrderButton(context, nixState, order),
                            ElevatedButton.icon(
                              key: Key('trade_button_${order.id}'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: context.onAccentColor,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: NixTokens.borderButtonCompact),
                              ),
                              onPressed: onTrade,
                              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                              label: Text(
                                isCryptographicallyValid ? 'Negociar' : 'Bloqueado',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _orderTrustIndicator(NixTrustLevel level) {
    Color dotColor = NixColors.trustLevel3Green;
    if (level == NixTrustLevel.level1Red) dotColor = NixColors.trustLevel1Red;
    if (level == NixTrustLevel.level2Yellow) dotColor = NixColors.trustLevel2Yellow;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: NixColors.surfaceActive,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NixColors.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Icon(Icons.shield, size: 10, color: dotColor),
        ],
      ),
    );
  }

  Widget _deleteOrderButton(BuildContext context, NixState state, MoneroP2pOrder order) {
    final isLocalOnly = order.publicationState == 'local_signed';
    final actionLabel = isLocalOnly ? 'Excluir anúncio local' : 'Cancelar ordem';
    return OutlinedButton.icon(
      key: Key('delete_order_${order.id}'),
      style: OutlinedButton.styleFrom(
        foregroundColor: NixColors.accentDanger,
        side: BorderSide(color: NixColors.accentDanger.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: NixTokens.borderButtonCompact),
      ),
      onPressed: () => _confirmOrderDeletion(context, state, order),
      icon: const Icon(Icons.delete_outline_rounded, size: 14),
      label: Text(actionLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  void _confirmOrderDeletion(BuildContext context, NixState state, MoneroP2pOrder order) {
    final isLocalOnly = order.publicationState == 'local_signed';
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(isLocalOnly ? 'Excluir anúncio local' : 'Cancelar ordem'),
        content: Text(
          isLocalOnly
              ? 'Deseja remover este anúncio local assinado? Ele será retirado imediatamente da sua listagem. Registros de negociações em andamento serão preservados.'
              : 'Deseja cancelar esta ordem? A remoção da cópia local preserva assinaturas e histórico. Se a ordem foi divulgada na rede, a oferta pode requerer revogação explícita nos canais distribuídos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NixColors.accentDanger),
            onPressed: () {
              Navigator.pop(dialogCtx);
              state.cancelOrDeleteMoneroOrder(order.id);
            },
            child: const Text('Confirmar exclusão'),
          ),
        ],
      ),
    );
  }
}
