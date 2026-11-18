import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/monero_order.dart';
import '../../core/models/member.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Aba Monero Non-Custodial P2P Marketplace (Inspirada no Trocador.app).
/// Plataforma de descoberta ponto-a-ponto para compra e venda de XMR sem intermediários,
/// sem custódia de fundos e com negociação direta via mensagens cifradas E2EE.
class MoneroP2pView extends StatelessWidget {
  const MoneroP2pView({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final orders = nixState.filteredMoneroOrders;

    return Container(
      color: NixColors.background,
      child: Column(
        children: [
          // Cabeçalho Principal da Aba Monero P2P
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              color: NixColors.surfaceElevated,
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                const Icon(Icons.currency_exchange_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MERCADO MONERO P2P DESCENTRALIZADO (NON-CUSTODIAL)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Inspirado no Trocador.app · Livro de ofertas soberano, sem custódia central e sem KYC',
                        style: TextStyle(color: NixColors.textMuted, fontSize: 10.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  key: const Key('create_monero_order_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () => _showCreateOrderDialog(context, nixState),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Criar Anúncio', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

          // Banner de Segurança Non-Custodial
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0F1014),
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, size: 15, color: NixColors.accentGreen),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aviso de Segurança: O Projeto Nix opera estritamente como quadro de descoberta. Nenhum fundo, chave privada ou senha é retido pela aplicação. Toda a liquidação é realizada diretamente entre os pares.',
                    style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // Filtros: Comprar / Vender, Moedas Fiat e Método de Pagamento
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: NixColors.surfaceSidebar,
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Toggle Comprar XMR / Vender XMR
                    Container(
                      decoration: BoxDecoration(
                        color: NixColors.surfaceCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: NixColors.surfaceBorder),
                      ),
                      child: Row(
                        children: [
                          _sideButton(
                            title: 'Comprar XMR',
                            isSelected: nixState.moneroSelectedSide == MoneroP2pSide.sell,
                            onTap: () => nixState.setMoneroSide(MoneroP2pSide.sell),
                          ),
                          _sideButton(
                            title: 'Vender XMR',
                            isSelected: nixState.moneroSelectedSide == MoneroP2pSide.buy,
                            onTap: () => nixState.setMoneroSide(MoneroP2pSide.buy),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Filtro de Moeda Fiat
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
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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

                    // Campo de Pesquisa Rápida
                    Expanded(
                      child: TextField(
                        onChanged: (v) => nixState.setMoneroSearchQuery(v),
                        style: const TextStyle(color: Colors.white, fontSize: 12.5),
                        decoration: const InputDecoration(
                          hintText: 'Filtrar por método de pagamento, trader ou notas...',
                          prefixIcon: Icon(Icons.search, size: 16, color: NixColors.textMuted),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Pílulas de Métodos de Pagamento
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _paymentMethodChip(nixState, 'Todos'),
                      _paymentMethodChip(nixState, 'PIX'),
                      _paymentMethodChip(nixState, 'Dinheiro'),
                      _paymentMethodChip(nixState, 'SEPA'),
                      _paymentMethodChip(nixState, 'Wise'),
                      _paymentMethodChip(nixState, 'TED'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Livro de Ofertas P2P
          Expanded(
            child: orders.isEmpty
                ? const Center(
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
                      return _MoneroOrderCard(
                        order: order,
                        onTrade: () => nixState.openTradeWithOrder(order),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sideButton({
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
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.black : NixColors.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _paymentMethodChip(NixState state, String method) {
    final isSelected = state.moneroSelectedPaymentMethod == method;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => state.setMoneroPaymentMethod(method),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : NixColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isSelected ? Colors.white : NixColors.surfaceBorder),
          ),
          child: Text(
            method,
            style: TextStyle(
              color: isSelected ? Colors.black : NixColors.textSecondary,
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
    final methodCtrl = TextEditingController(text: 'PIX Instantâneo');
    final notesCtrl = TextEditingController(text: 'Liberação imediata em subendereço único.');
    MoneroP2pSide side = state.moneroSelectedSide;
    String fiat = state.moneroSelectedFiat;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: NixColors.surfaceElevatedHigh,
            title: const Text('Publicar Oferta P2P Descentralizada', style: TextStyle(color: Colors.white, fontSize: 16)),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sua oferta será assinada com sua chave Ed25519 e transmitida para os nós da rede Onion.',
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
                          onSelected: (_) => setModalState(() => side = MoneroP2pSide.sell),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Quero Comprar XMR'),
                          selected: side == MoneroP2pSide.buy,
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
                child: const Text('Cancelar', style: TextStyle(color: NixColors.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  final price = double.tryParse(priceCtrl.text) ?? 850.0;
                  final minL = double.tryParse(minLimitCtrl.text) ?? 100.0;
                  final maxL = double.tryParse(maxLimitCtrl.text) ?? 5000.0;
                  final newOrder = MoneroP2pOrder(
                    id: 'ord_${DateTime.now().millisecondsSinceEpoch}',
                    traderName: state.userProfile.effectiveDisplayName,
                    traderPublicId: state.userProfile.publicId,
                    trustLevel: NixTrustLevel.level3Green,
                    side: side,
                    fiatCurrency: fiat,
                    pricePerXmr: price,
                    minFiatLimit: minL,
                    maxFiatLimit: maxL,
                    paymentMethod: methodCtrl.text.trim().isNotEmpty ? methodCtrl.text.trim() : 'PIX',
                    signedManifestHash: 'ed25_${DateTime.now().millisecondsSinceEpoch}',
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
  final VoidCallback onTrade;

  const _MoneroOrderCard({
    required this.order,
    required this.onTrade,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: NixTokens.borderMd,
        border: Border.all(color: NixColors.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Informações do Anunciante
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: order.isOnline ? NixColors.accentGreen : NixColors.textMuted,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        order.traderName,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _orderTrustIndicator(order.trustLevel),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${order.reputationScore}% avaliação · ${order.completedTrades} ordens concluídas · resposta ~${order.avgResponseMinutes}m',
                  style: const TextStyle(color: NixColors.textMuted, fontSize: 11),
                ),
                const SizedBox(height: 8),
                Text(
                  order.notes,
                  style: const TextStyle(color: NixColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Preço & Limites
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PREÇO UNITÁRIO', style: NixTokens.labelUppercase()),
                const SizedBox(height: 2),
                Text(
                  order.formattedPrice,
                  style: const TextStyle(
                    color: Colors.white,
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
                  style: const TextStyle(color: NixColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Método de Pagamento & Botão Negociar
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: NixColors.surfaceActive,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white24, width: 0.5),
                ),
                child: Text(
                  order.paymentMethod,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                key: Key('trade_button_${order.id}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: onTrade,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                label: const Text('Negociar', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
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
        color: Colors.black45,
        borderRadius: BorderRadius.circular(8),
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
