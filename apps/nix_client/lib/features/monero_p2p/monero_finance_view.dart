import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import 'monero_p2p_view.dart';
import '../bitcoin/bitcoin_payment_view.dart';

class MoneroFinanceView extends StatelessWidget {
  final bool showWallet;

  const MoneroFinanceView({super.key, required this.showWallet});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        key: ValueKey(showWallet),
        length: 3,
        initialIndex: showWallet ? 1 : 0,
        child: const Column(
          children: [
            TabBar(labelPadding: EdgeInsets.symmetric(horizontal: 4), tabs: [
              Tab(text: 'Mercado Cripto'),
              Tab(child: Text('Carteira e histórico', textAlign: TextAlign.center)),
              Tab(child: Text('Bitcoin / Lightning', textAlign: TextAlign.center)),
            ]),
            Expanded(
              child: TabBarView(
                physics: NeverScrollableScrollPhysics(),
                children: [MoneroP2pView(), MoneroWalletView(), BitcoinPaymentView()],
              ),
            ),
          ],
        ),
      );
}

class MoneroWalletView extends StatelessWidget {
  const MoneroWalletView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    return Column(
      key: const ValueKey('home_stage_transactions'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Carteira Monero',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: NixTokens.borderMd,
                  border: Border.all(color: NixColors.surfaceBorderStrong),
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SALDO DESBLOQUEADO (SEED B ISOLADA)',
                            style: TextStyle(
                                color: NixColors.textMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0)),
                        const SizedBox(height: 6),
                        Text(state.moneroWalletBalanceLabel,
                            style: TextStyle(
                                color: NixColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'monospace')),
                      ],
                    ),
                    Text(state.moneroWalletStatusLabel,
                        style: TextStyle(
                            fontSize: 12, color: NixColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('HISTÓRICO DE LIQUIDAÇÕES LOCAL',
                  style: NixTokens.labelUppercase()),
              const SizedBox(height: 10),
              ...state.transactions.map((tx) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NixColors.surfaceCard,
                      borderRadius: NixTokens.borderSm,
                      border: Border.all(color: NixColors.surfaceBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          tx.isIncoming
                              ? Icons.call_received_rounded
                              : Icons.call_made_rounded,
                          color: NixColors.textPrimary,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tx.title,
                                  style: TextStyle(
                                      color: NixColors.textPrimary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                  '${tx.subaddressPreview} · ${tx.confirmations} confirmações',
                                  style: TextStyle(
                                      color: NixColors.textMuted,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                        Text(
                          tx.amountXmr,
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}
