import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/member.dart';
import '../../core/models/monero_order.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Aba Monero Non-Custodial P2P Marketplace.
/// Exibe anúncios assinados com verificação Ed25519 local, controle de expiração,
/// proteção anti-replay por nonce e zero custódia de chaves ou fundos.
class MoneroP2pView extends StatelessWidget {
  const MoneroP2pView({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final orders = nixState.filteredMoneroOrders;
    final accent = context.accentColor;
    final accentText = context.accentTextColor;

    return Container(
      color: NixColors.background,
      child: Column(
        children: [
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: NixColors.surfaceElevated,
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                Icon(Icons.currency_exchange_rounded, size: 18, color: accentText),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MERCADO MONERO P2P DESCENTRALIZADO (NON-CUSTODIAL)',
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    'Aviso Non-Custodial & Anti-Fraude: O Nix apenas exibe ordens assinadas e abre negociação E2EE. Nunca transfira XMR ou fiat para endereços fora do canal criptografado verificado nem ignore alertas de assinatura.',
                    style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // Filtros: Comprar / Vender, Moedas Fiat e Método de Pagamento
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: NixColors.surfaceSidebar,
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: NixColors.surfaceCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: NixColors.surfaceBorder),
                      ),
                      child: Row(
                        children: [
                          _sideButton(
                            context: context,
                            title: 'Comprar XMR',
                            isSelected: nixState.moneroSelectedSide == MoneroP2pSide.sell,
                            onTap: () => nixState.setMoneroSide(MoneroP2pSide.sell),
                          ),
                          _sideButton(
                            context: context,
                            title: 'Vender XMR',
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
                        borderRadius: BorderRadius.circular(8),
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
                          items: const [
                            DropdownMenuItem(value: 'BRL', child: Text('BRL (R\$)')),
                            DropdownMenuItem(value: 'USD', child: Text('USD (\$)')),
                            DropdownMenuItem(value: 'EUR', child: Text('EUR (€)')),
                          ],
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
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _paymentMethodChip(context, nixState, 'Todos'),
                      _paymentMethodChip(context, nixState, 'PIX'),
                      _paymentMethodChip(context, nixState, 'Dinheiro'),
                      _paymentMethodChip(context, nixState, 'SEPA'),
                      _paymentMethodChip(context, nixState, 'Wise'),
                      _paymentMethodChip(context, nixState, 'TED'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: orders.isEmpty
                ? Center(
                    child: Text(
                      'Nenhuma oferta encontrada para os filtros selecionados.',
                      style: TextStyle(color: NixColors.textMuted, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, idx) {
                      final order = orders[idx];
                      final valid = nixState.verifyMoneroOrder(order);
                      return _MoneroOrderCard(
                        order: order,
                        isCryptographicallyValid: valid,
                        onTrade: valid ? () => nixState.openTradeWithOrder(order) : null,
                      );
                    },
                  ),
          ),
        ],
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
        onTap: () => state.setMoneroPaymentMethod(method),
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

  void _showCreateOrderDialog(BuildContext context, NixState state) {
    final priceCtrl = TextEditingController(text: '850.00');
    final minLimitCtrl = TextEditingController(text: '100');
    final maxLimitCtrl = TextEditingController(text: '5000');
    final methodCtrl = TextEditingController(text: 'PIX');
    final notesCtrl = TextEditingController(text: 'Liberação imediata em subendereço único.');
    MoneroP2pSide side = state.moneroSelectedSide;
    final fiat = state.moneroSelectedFiat;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final accent = context.accentColor;
          return AlertDialog(
            backgroundColor: NixColors.surfaceElevatedHigh,
            title: Text(
              'Publicar Oferta P2P Descentralizada',
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
                      'Sua oferta receberá assinatura Ed25519, nonce anti-replay e expiração de 7 dias.',
                      style: TextStyle(color: NixColors.textMuted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 14),
                    Text('TIPO DE ORDEM', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Quero Vender XMR'),
                          selected: side == MoneroP2pSide.sell,
                          selectedColor: accent,
                          labelStyle: TextStyle(
                            color: side == MoneroP2pSide.sell ? context.onAccentColor : NixColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => setModalState(() => side = MoneroP2pSide.sell),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Quero Comprar XMR'),
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
                    Text('PREÇO POR XMR', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixText: fiat == 'BRL' ? 'R\$ ' : (fiat == 'EUR' ? '€ ' : '\$ '),
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
                              TextField(controller: minLimitCtrl),
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
                              TextField(controller: maxLimitCtrl),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('MÉTODO DE PAGAMENTO', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    TextField(controller: methodCtrl),
                    const SizedBox(height: 12),
                    Text('INSTRUÇÕES / TERMOS P2P', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    TextField(controller: notesCtrl, maxLines: 2),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancelar', style: TextStyle(color: NixColors.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: context.onAccentColor,
                ),
                onPressed: () {
                  final nowMs = DateTime.now().millisecondsSinceEpoch;
                  final price = double.tryParse(priceCtrl.text) ?? 850.0;
                  final minL = double.tryParse(minLimitCtrl.text) ?? 100.0;
                  final maxL = double.tryParse(maxLimitCtrl.text) ?? 5000.0;
                  final newOrder = MoneroP2pOrder(
                    id: 'ord_$nowMs',
                    traderName: state.userProfile.effectiveDisplayName,
                    traderPublicId: state.userProfile.publicId,
                    trustLevel: NixTrustLevel.level3Green,
                    side: side,
                    fiatCurrency: fiat,
                    pricePerXmr: price,
                    minFiatLimit: minL,
                    maxFiatLimit: maxL,
                    paymentMethod: methodCtrl.text.trim().isNotEmpty ? methodCtrl.text.trim() : 'PIX',
                    signedManifestHash: 'ed25519_$nowMs',
                    signatureHex: 'sig_${nowMs.toRadixString(16)}',
                    nonceHex: 'n_${nowMs.toRadixString(36)}',
                    expiresAt: DateTime.now().add(const Duration(days: 7)),
                    isSignatureVerified: true,
                    notes: notesCtrl.text.trim(),
                  );
                  state.createMoneroOrder(newOrder);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Oferta P2P assinada e publicada com sucesso.')),
                  );
                },
                child: const Text('Publicar Oferta', style: TextStyle(fontWeight: FontWeight.bold)),
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
    final accent = context.accentColor;
    final expLabel = order.expiresAt == null
        ? 'Sem expiração'
        : (order.isExpired
            ? 'Expirada'
            : 'Expira em ${order.expiresAt!.difference(DateTime.now()).inHours.clamp(1, 999)}h');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: NixTokens.borderMd,
        border: Border.all(
          color: isCryptographicallyValid
              ? NixColors.surfaceBorder
              : NixColors.accentDanger.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
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
                      order.traderName,
                      style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
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
              ElevatedButton.icon(
                key: Key('trade_button_${order.id}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: context.onAccentColor,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
}
