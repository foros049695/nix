import 'dart:math';

import 'package:flutter/material.dart';
import '../../core/theme/nix_colors.dart';
import 'payment_method_picker.dart';
import '../chat/conversation_surface.dart';
import '../design/nix_surfaces.dart';

enum _TradeStage { draft, open, accepted, paymentReported, dispute, closed }

class TradeSimulationDialog extends StatefulWidget {
  const TradeSimulationDialog({super.key});

  @override
  State<TradeSimulationDialog> createState() => _TradeSimulationDialogState();
}

class _TradeSimulationDialogState extends State<TradeSimulationDialog> {
  static const _avatars = [
    Icons.eco_outlined,
    Icons.auto_awesome_outlined,
    Icons.bolt_outlined,
    Icons.nightlight_outlined,
    Icons.park_outlined,
    Icons.water_drop_outlined,
  ];

  final _random = Random.secure();
  final _entry = TextEditingController();
  final _events = <({String text, bool? maker})>[];
  var _stage = _TradeStage.draft;
  var _method = 'BTC / Lightning';
  var _side = 'Comprar';
  String? _orderId;
  ({String id, IconData avatar})? _maker;
  ({String id, IconData avatar})? _taker;
  var _asMaker = true;

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  String _randomId() => List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();

  ({String id, IconData avatar}) _participant() =>
      (id: _randomId(), avatar: _avatars[_random.nextInt(_avatars.length)]);

  void _advance(_TradeStage next, String description) {
    setState(() {
      _stage = next;
      _events.add((text: description, maker: null));
    });
  }

  void _publish() {
    _orderId = _randomId();
    _maker = _participant();
    _advance(_TradeStage.open, 'Ordem de $_side aberta com $_method.');
  }

  void _accept() {
    _taker = _participant();
    _advance(_TradeStage.accepted, 'A contraparte aceitou a ordem.');
  }

  void _addEntry({required bool decision}) {
    final text = _entry.text.trim();
    if (text.isEmpty) return;
    _entry.clear();
    if (decision) {
      _advance(_TradeStage.closed, 'Decisão simulada: $text');
    } else {
      setState(() => _events.add((text: text, maker: _asMaker)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final inTrade =
        _stage == _TradeStage.accepted || _stage == _TradeStage.paymentReported;
    final inDispute = _stage == _TradeStage.dispute;
    return AlertDialog(
      title: const NixPanelTitle(icon: Icons.compare_arrows_rounded, title: 'Simular negociação'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Exercício local. Use dados fictícios. A simulação termina ao fechar esta tela.'),
              const SizedBox(height: 12),
              if (_stage == _TradeStage.draft) ...[
                DropdownButtonFormField(
                  value: _side,
                  decoration: const InputDecoration(labelText: 'Tipo de ordem'),
                  items: const [
                    DropdownMenuItem(value: 'Comprar', child: Text('Comprar')),
                    DropdownMenuItem(value: 'Vender', child: Text('Vender')),
                  ],
                  onChanged: (value) => setState(() => _side = value!),
                ),
                PaymentMethodPicker(
                  value: _method,
                  onChanged: (method) => setState(() => _method = method),
                ),
              ],
              if (_method == 'PIX' || _method == 'Boleto')
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                      'Em operação real, o banco ou emissor pode revelar dados cadastrais.'),
                ),
              if (_orderId case final id?) SelectableText('Ordem: $id'),
              if (_maker case final maker?)
                _identityRow('Autor', maker.id, maker.avatar),
              if (_taker case final taker?)
                _identityRow('Contraparte', taker.id, taker.avatar),
              if (_events.isNotEmpty) ...[
                const Divider(),
                Text(inDispute
                    ? 'Dossiê da ordem para o árbitro'
                    : 'Linha do tempo'),
                for (final event in _events)
                  if (event.maker == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Text(event.text,
                          style: TextStyle(color: NixColors.textSecondary)),
                    )
                  else
                    Align(
                      alignment: event.maker!
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 285),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: messageDecoration(context, outgoing: event.maker!),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(event.maker! ? 'Autor' : 'Contraparte',
                                style: TextStyle(
                                    fontSize: 11, color: NixColors.accentText)),
                            Text(event.text),
                          ],
                        ),
                      ),
                    ),
              ],
              if (inTrade || inDispute) ...[
                const SizedBox(height: 12),
                if (inTrade)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_asMaker
                        ? 'Escrevendo como autor'
                        : 'Escrevendo como contraparte'),
                    value: _asMaker,
                    onChanged: (value) => setState(() => _asMaker = value),
                  ),
                TextField(
                  controller: _entry,
                  maxLength: 300,
                  textInputAction:
                      inDispute ? TextInputAction.done : TextInputAction.send,
                  onSubmitted: (_) => _addEntry(decision: inDispute),
                  decoration: InputDecoration(
                    suffixIcon: inDispute
                        ? null
                        : IconButton(
                            tooltip: 'Enviar mensagem',
                            icon: const Icon(Icons.send_rounded),
                            onPressed: () => _addEntry(decision: false),
                          ),
                    labelText:
                        inDispute ? 'Decisão simulada' : 'Mensagem da ordem',
                  ),
                ),
                if (inDispute)
                  TextButton(
                    onPressed: () => _addEntry(decision: true),
                    child: const Text('Registrar decisão'),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar')),
        if (_stage == _TradeStage.draft)
          FilledButton(
              onPressed: _publish, child: const Text('Criar ordem fictícia')),
        if (_stage == _TradeStage.open)
          FilledButton(onPressed: _accept, child: const Text('Simular aceite')),
        if (_stage == _TradeStage.accepted)
          FilledButton(
            onPressed: () => _advance(
                _TradeStage.paymentReported, 'Pagamento fictício informado.'),
            child: const Text('Informar pagamento'),
          ),
        if (inTrade)
          TextButton(
            onPressed: () => _advance(_TradeStage.dispute,
                'Disputa aberta. Apenas esta ordem integra o dossiê.'),
            child: const Text('Abrir disputa'),
          ),
        if (_stage == _TradeStage.paymentReported)
          FilledButton(
            onPressed: () => _advance(
                _TradeStage.closed, 'Recebimento fictício confirmado.'),
            child: const Text('Confirmar recebimento'),
          ),
      ],
    );
  }

  Widget _identityRow(String role, String id, IconData avatar) => Row(
        children: [
          Icon(avatar, size: 18),
          const SizedBox(width: 8),
          Expanded(child: SelectableText('$role: $id')),
        ],
      );
}
