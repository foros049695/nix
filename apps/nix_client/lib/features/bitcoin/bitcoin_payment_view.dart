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

  Future<void> _payNode(BitcoinPaymentRequest request) async {
    final state = context.read<NixState>();
    var endpoint = '';
    var user = '';
    var secret = '';
    int? feeLimit;

    if (request.network == BitcoinNetwork.mainnet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pagamentos diretos via Nix são estritamente restritos a redes de teste/regtest.'),
        ),
      );
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(request.lightning
              ? 'Liquidar fatura Lightning (Nó Regtest)'
              : 'Enviar Bitcoin On-Chain (Nó Regtest)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber),
                ),
                child: const Text(
                  'ATENÇÃO: Use apenas fundos sintéticos em ambiente regtest/testnet. Credenciais são usadas apenas nesta operação e descartadas da memória.',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Valor: ${request.milliSatoshis != null ? '${request.milliSatoshis! ~/ BigInt.from(1000)} sats' : 'Não especificado'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) => endpoint = value,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'URL Onion v3 ou localhost do nó'),
              ),
              if (!request.lightning)
                TextField(
                  onChanged: (value) => user = value,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Usuário RPC Bitcoin Core'),
                ),
              TextField(
                onChanged: (value) => secret = value,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: request.lightning
                      ? 'Admin Macaroon LND (hexadecimal)'
                      : 'Senha RPC Bitcoin Core',
                ),
              ),
              if (request.lightning)
                TextField(
                  onChanged: (value) => feeLimit = int.tryParse(value),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Limite de taxa em satoshis (opcional)',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('confirm_nix_payment_button'),
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Confirmar Envio'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || accepted != true || _checking) return;
    setState(() => _checking = true);
    BitcoinPaymentResult? paymentResult;
    try {
      if (!state.canOpenPrivateTradeRoom) {
        throw const FormatException('O pagamento exige o Tor ou transporte de teste pronto no Nix.');
      }
      final node = BitcoinTestnetNode.onion(
        endpoint,
        socksPort: state.tradeTorConnection.socksPort,
        mayConnect: () => state.canOpenPrivateTradeRoom,
      );

      if (request.lightning) {
        paymentResult = await node.payLightningInvoice(
          request: request,
          adminMacaroon: secret.trim(),
          feeLimitSat: feeLimit,
        );
      } else {
        paymentResult = await node.sendBitcoinOnChain(
          request: request,
          user: user.trim(),
          password: secret.trim(),
        );
      }
    } on FormatException catch (error) {
      paymentResult = BitcoinPaymentResult(
        id: 'pay_${DateTime.now().millisecondsSinceEpoch}',
        status: BitcoinPaymentStatus.failed,
        failureReason: error.message,
        amountMilliSatoshis: request.milliSatoshis ?? BigInt.zero,
        feeMilliSatoshis: BigInt.zero,
        timestamp: DateTime.now().toUtc(),
        isLightning: request.lightning,
        destination: request.payload,
        network: request.network,
      );
    } catch (e) {
      paymentResult = BitcoinPaymentResult(
        id: 'pay_${DateTime.now().millisecondsSinceEpoch}',
        status: BitcoinPaymentStatus.failed,
        failureReason: 'Falha de comunicação ou timeout: $e',
        amountMilliSatoshis: request.milliSatoshis ?? BigInt.zero,
        feeMilliSatoshis: BigInt.zero,
        timestamp: DateTime.now().toUtc(),
        isLightning: request.lightning,
        destination: request.payload,
        network: request.network,
      );
    } finally {
      secret = '';
    }

    if (mounted) {
      state.recordBitcoinPayment(paymentResult);
      setState(() => _checking = false);
      final msg = switch (paymentResult.status) {
        BitcoinPaymentStatus.succeeded => 'Pagamento concluído com sucesso!',
        BitcoinPaymentStatus.failed => 'Falha no pagamento: ${paymentResult.failureReason}',
        BitcoinPaymentStatus.inFlight => 'Pagamento em trânsito (aguardando resolução na rota).',
        BitcoinPaymentStatus.expired => 'Pedido expirado.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _copy(request),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar para carteira'),
                ),
                if (request.network != BitcoinNetwork.mainnet)
                  FilledButton.icon(
                    key: const Key('pay_with_testnet_node_button'),
                    onPressed: _checking ? null : () => _payNode(request),
                    icon: const Icon(Icons.bolt),
                    label: Text(request.lightning
                        ? 'Liquidar fatura (LND Regtest)'
                        : 'Enviar On-Chain (Bitcoin Core Regtest)'),
                  ),
              ],
            ),
          ),
        ],
        Builder(
          builder: (context) {
            final history = context.watch<NixState>().bitcoinPaymentHistory;
            if (history.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Text('Histórico de Pagamentos (Nó de Teste)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...history.map((item) => Card(
                      key: Key('payment_history_${item.id}'),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          item.status == BitcoinPaymentStatus.succeeded
                              ? Icons.check_circle
                              : (item.status == BitcoinPaymentStatus.inFlight
                                  ? Icons.hourglass_top
                                  : Icons.error),
                          color: item.status == BitcoinPaymentStatus.succeeded
                              ? Colors.green
                              : (item.status == BitcoinPaymentStatus.inFlight
                                  ? Colors.amber
                                  : Colors.red),
                        ),
                        title: Text(
                          '${item.isLightning ? 'Lightning' : 'On-Chain'} · ${item.status.name.toUpperCase()}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.amountMilliSatoshis ~/ BigInt.from(1000)} sats · Taxa: ${item.feeMilliSatoshis ~/ BigInt.from(1000)} sats',
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (item.preimageOrTxId != null)
                              Text(
                                'Comp: ${item.preimageOrTxId}',
                                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (item.failureReason != null)
                              Text(
                                'Motivo: ${item.failureReason}',
                                style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                              ),
                          ],
                        ),
                        trailing: Text(
                          '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    )),
              ],
            );
          },
        ),
      ],
    );
  }
}
