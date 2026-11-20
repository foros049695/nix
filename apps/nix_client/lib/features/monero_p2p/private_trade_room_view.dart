import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/p2p/private_trade_room.dart';
import '../../state/nix_state.dart';

class PrivateTradeRoomView extends StatefulWidget {
  const PrivateTradeRoomView._({required this.state, required this.join});

  final NixState state;
  final bool join;

  static Future<void> open(BuildContext context, NixState state,
      {bool join = false}) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PrivateTradeRoomView._(state: state, join: join),
    ));
  }

  @override
  State<PrivateTradeRoomView> createState() => _PrivateTradeRoomViewState();
}

class _PrivateTradeRoomViewState extends State<PrivateTradeRoomView> {
  final _field = TextEditingController();
  PrivateTradeRoom? _room;
  Timer? _poller;
  bool _opening = false;
  bool _sending = false;
  bool _polling = false;
  String? _problem;
  String? _deliveryId;
  String? _deliveryText;
  String _host = '';
  String _guest = '';

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_checkTransport);
  }

  void _checkTransport() {
    if (!widget.state.canOpenPrivateTradeRoom) _room?.close();
    if (mounted) setState(() {});
  }

  void _onRoomChanged() {
    if (_room?.isClosed == true) {
      _poller?.cancel();
      _field.clear();
      _deliveryText = null;
      _deliveryId = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    if (_opening || !widget.state.canOpenPrivateTradeRoom) return;
    setState(() {
      _opening = true;
      _problem = null;
    });
    PrivateTradeRoom? created;
    try {
      final tor = widget.state.tradeTorConnection;
      bool canUseTor() => mounted && widget.state.canOpenPrivateTradeRoom;
      final room = widget.join
          ? PrivateTradeRoom.join(
              invitation: _field.text, tor: tor, canUseTor: canUseTor)
          : await PrivateTradeRoom.host(tor: tor, canUseTor: canUseTor);
      created = room;
      final host = await room.alias(host: true);
      final guest = await room.alias(host: false);
      if (!mounted) {
        room.dispose();
        return;
      }
      _field.clear();
      _room = room..addListener(_onRoomChanged);
      _host = host;
      _guest = guest;
      if (!room.isHost) {
        _poller = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
        unawaited(_poll());
      }
    } on FormatException {
      created?.dispose();
      _problem = 'Convite inválido ou expirado.';
    } catch (_) {
      created?.dispose();
      _problem = 'Não foi possível abrir a sala pelo Tor.';
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _poll() async {
    final room = _room;
    if (!mounted || room == null || !room.available || _sending || _polling)
      return;
    setState(() => _polling = true);
    try {
      await room.poll();
      if (mounted && _deliveryId == null) _problem = null;
    } catch (_) {
      if (mounted && _deliveryId == null) _problem = 'Aguardando a sala Onion.';
    } finally {
      if (mounted) setState(() => _polling = false);
    }
  }

  Future<void> _send() async {
    final room = _room;
    final text = _field.text.trim();
    if (room == null || !room.available || text.isEmpty || _sending || _polling)
      return;
    if (_deliveryText != text) {
      _deliveryText = text;
      _deliveryId = PrivateTradeRoom.newMessageId();
    }
    setState(() {
      _sending = true;
      _problem = null;
    });
    try {
      await room.send(text, messageId: _deliveryId!);
      if (!mounted) return;
      if (_field.text.trim() == text) _field.clear();
      _deliveryId = null;
      _deliveryText = null;
    } on FormatException {
      if (mounted) _problem = 'Envie uma mensagem de texto menor.';
    } catch (_) {
      if (mounted)
        _problem = 'Mensagem sem confirmação. Tente enviar novamente.';
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_checkTransport);
    _poller?.cancel();
    _room?.dispose();
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Negociação privada'),
          actions: [
            IconButton(
              tooltip: 'Fechar sala',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _room == null ? _setup() : _chat(_room!),
              ),
            ),
          ),
        ),
      );

  Widget _setup() => ListView(
        key: const Key('private_trade_setup'),
        children: [
          const Text(
              'Sala de duas pessoas via Tor. Os nomes são sorteados para esta sessão e a sala expira em 30 minutos.'),
          const SizedBox(height: 12),
          if (!widget.state.canOpenPrivateTradeRoom)
            const Text('Conecte ao Tor para criar ou abrir uma sala.'),
          if (widget.join) ...[
            TextField(
              controller: _field,
              maxLength: 600,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Convite privado'),
              onSubmitted: (_) => _open(),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: _opening || !widget.state.canOpenPrivateTradeRoom
                ? null
                : _open,
            child: Text(_opening
                ? 'Conectando…'
                : widget.join
                    ? 'Entrar na sala'
                    : 'Criar sala Onion'),
          ),
          if (_problem != null) Text(_problem!),
        ],
      );

  Widget _chat(PrivateTradeRoom room) {
    if (!room.available) {
      return const Center(child: Text('Sessão encerrada.'));
    }
    final messages = room.messages.reversed.toList();
    final invite = room.invitation;
    return Column(
      children: [
        if (invite != null)
          ListTile(
            title: const Text('Convidar uma pessoa'),
            subtitle: const Text(
                'O código dá acesso à sala. Compartilhe-o em particular.'),
            trailing: IconButton(
              tooltip: 'Copiar convite privado',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () => Clipboard.setData(ClipboardData(text: invite)),
            ),
          ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final mine = message.fromHost == room.isHost;
              return Align(
                alignment: mine
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message.fromHost ? _host : _guest,
                            style: Theme.of(context).textTheme.labelSmall),
                        Text(message.text),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_problem != null) Text(_problem!),
        TextField(
          controller: _field,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 400,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _send(),
          decoration: InputDecoration(
            labelText: 'Mensagem da negociação',
            suffixIcon: IconButton(
              tooltip: 'Enviar mensagem privada',
              onPressed: _sending || _polling ? null : _send,
              icon: const Icon(Icons.send_rounded),
            ),
          ),
        ),
      ],
    );
  }
}
