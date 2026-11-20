import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/bitcoin/bitcoin_payment_request.dart';
import '../../core/bitcoin/bitcoin_testnet_node.dart';
import '../../state/nix_state.dart';

class BitcoinPaymentView extends StatefulWidget {
  const BitcoinPaymentView({super.key});

  @override
  State<BitcoinPaymentView> createState() => _BitcoinPaymentViewState();
}

class _BitcoinPaymentViewState extends State<BitcoinPaymentView> {
  final _input = TextEditingController();
  BitcoinPaymentRequest? _request;
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _review() {
    try {
      final result = BitcoinPaymentRequest.parse(_input.text);
      setState(() {
        _request = result;
        _error = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _request = null;
        _error = error.message;
      });
    }
  }

  String _network(BitcoinNetwork network) => switch (network) {
        BitcoinNetwork.mainnet => 'Rede principal',
        BitcoinNetwork.testnet => 'Testnet',
        BitcoinNetwork.signet => 'Signet',
        BitcoinNetwork.regtest => 'Regtest',
        BitcoinNetwork.testNetworks => 'Rede de teste compatível',
      };

  Future<void> _copy(BitcoinPaymentRequest request) async {
    await Clipboard.setData(ClipboardData(text: request.payload));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Pedido copiado para a carteira externa.')),
      );
    }
  }

  Future<void> _checkNode({BitcoinPaymentRequest? invoice}) async {
    final state = context.read<NixState>();
    var endpoint = '';
    var user = '';
    var secret = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: Text(invoice == null
            ? 'Consultar Bitcoin Core'
            : 'Validar fatura no LND'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Conecte seu nó Onion de teste usando credenciais de leitura para esta consulta.'),
            TextField(
              onChanged: (value) => endpoint = value,
              autocorrect: false,
              decoration:
                  const InputDecoration(labelText: 'URL Onion v3 do nó'),
            ),
            if (invoice == null)
              TextField(
                onChanged: (value) => user = value,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Usuário RPC'),
              ),
            TextField(
              onChanged: (value) => secret = value,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: invoice == null
                    ? 'Senha RPC'
                    : 'Macaroon de leitura (hexadecimal)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Consultar via Tor')),
        ],
      ),
    );
    if (!mounted || accepted != true || _checking) return;
    setState(() => _checking = true);
    String result;
    try {
      if (!state.canOpenPrivateTradeRoom) {
        throw const FormatException('A consulta exige o Tor pronto no Nix.');
      }
      final node = BitcoinTestnetNode.onion(endpoint,
          socksPort: state.tradeTorConnection.socksPort,
          mayConnect: () => state.canOpenPrivateTradeRoom);
      if (invoice == null) {
        final status =
            await node.checkBitcoinCore(user: user, password: secret);
        result =
            'Nó de teste confirmado. Rede ${status.chain}, ${status.blocks} blocos.';
      } else {
        await node.verifyLightningInvoice(
            request: invoice, readOnlyMacaroon: secret.trim());
        result = 'A fatura foi validada pelo nó de teste.';
      }
    } on FormatException catch (error) {
      result = error.message;
    } catch (_) {
      result =
          'A consulta ao nó Onion falhou. Confira a conexão e as credenciais.';
    } finally {
      secret = '';
    }
    if (mounted) {
      setState(() => _checking = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Bitcoin e Lightning',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
            'Revise um pedido de pagamento e leve-o à sua carteira. A carteira confirma o destinatário, a validade da fatura e a transação.'),
        const SizedBox(height: 16),
        TextField(
          key: const Key('bitcoin_payment_input'),
          controller: _input,
          minLines: 2,
          maxLines: 4,
          maxLength: 2048,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) {
            if (_request != null || _error != null) {
              setState(() {
                _request = null;
                _error = null;
              });
            }
          },
          decoration: InputDecoration(
            labelText: 'Endereço Bitcoin, BIP21 ou fatura BOLT11',
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
              onPressed: _review, child: const Text('Revisar pedido')),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: _checking ? null : () => _checkNode(),
            child: const Text('Consultar Bitcoin Core de teste'),
          ),
        ),
        if (_checking) const LinearProgressIndicator(),
        if (request != null) ...[
          const SizedBox(height: 24),
          Text(
              '${request.lightning ? 'Lightning' : 'Bitcoin on-chain'} · ${_network(request.network)}'),
          if (request.milliSatoshis case final amount?)
            Text(amount.remainder(BigInt.from(1000)) == BigInt.zero
                ? '${amount ~/ BigInt.from(1000)} sats'
                : '$amount msats')
          else
            const Text('Valor a confirmar na carteira'),
          if (request.lightning && request.network != BitcoinNetwork.mainnet)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed:
                    _checking ? null : () => _checkNode(invoice: request),
                child: const Text('Validar fatura no LND de teste'),
              ),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: QrImageView(
              data: request.payload,
              backgroundColor: Colors.white,
              size: 240,
              padding: const EdgeInsets.all(12),
              errorStateBuilder: (_, __) =>
                  const Text('Use a opção de copiar para este pedido.'),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _copy(request),
              icon: const Icon(Icons.copy),
              label: const Text('Copiar para carteira'),
            ),
          ),
        ],
      ],
    );
  }
}
