import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/messaging/direct_poll.dart';
import '../../state/nix_state.dart';

class CreateDirectPollDialog extends StatefulWidget {
  const CreateDirectPollDialog({super.key, required this.onCreate});

  final Future<void> Function(DirectPollSpec) onCreate;

  @override
  State<CreateDirectPollDialog> createState() => _CreateDirectPollDialogState();
}

class _CreateDirectPollDialogState extends State<CreateDirectPollDialog> {
  final _question = TextEditingController();
  final _description = TextEditingController();
  final _options = [TextEditingController(), TextEditingController()];
  bool _multiple = false;
  bool _revote = true;
  bool _hide = false;
  bool _shuffle = false;
  int? _correct;
  int? _duration;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    _description.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final poll = DirectPollSpec.create(
        question: _question.text,
        description: _description.text,
        options: _options.map((option) => option.text).toList(),
        multiple: _multiple,
        allowRevote: _revote,
        hideResults: _hide,
        shuffle: _shuffle,
        correctOption: _correct,
        durationMinutes: _duration,
      );
      await widget.onCreate(poll);
      if (mounted) Navigator.pop(context);
    } on FormatException catch (error) {
      _error = error.message;
    } on StateError catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Não foi possível salvar a enquete no cofre.';
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_sending,
        child: AlertDialog(
          title: const Text('Criar enquete'),
          scrollable: true,
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _question,
                  enabled: !_sending,
                  maxLength: 140,
                  decoration: const InputDecoration(labelText: 'Pergunta'),
                ),
                TextField(
                  controller: _description,
                  enabled: !_sending,
                  maxLength: 400,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Descrição opcional'),
                ),
                for (final (index, option) in _options.indexed)
                  TextField(
                    controller: option,
                    enabled: !_sending,
                    maxLength: 80,
                    decoration:
                        InputDecoration(labelText: 'Opção ${index + 1}'),
                  ),
                TextButton.icon(
                  onPressed: _options.length >= 8 || _sending
                      ? null
                      : () =>
                          setState(() => _options.add(TextEditingController())),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar opção'),
                ),
                SwitchListTile(
                  title: const Text('Várias respostas'),
                  value: _multiple,
                  onChanged: _sending || _correct != null
                      ? null
                      : (value) => setState(() => _multiple = value),
                ),
                SwitchListTile(
                  title: const Text('Permitir alterar voto'),
                  value: _revote,
                  onChanged: _sending
                      ? null
                      : (value) => setState(() => _revote = value),
                ),
                SwitchListTile(
                  title: const Text('Ocultar resultados enquanto aberta'),
                  value: _hide,
                  onChanged: _sending
                      ? null
                      : (value) => setState(() => _hide = value),
                ),
                SwitchListTile(
                  title: const Text('Embaralhar as opções'),
                  value: _shuffle,
                  onChanged: _sending
                      ? null
                      : (value) => setState(() => _shuffle = value),
                ),
                DropdownButtonFormField<int>(
                  value: _duration ?? 0,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Duração'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Sem prazo')),
                    DropdownMenuItem(value: 5, child: Text('5 minutos')),
                    DropdownMenuItem(value: 60, child: Text('1 hora')),
                    DropdownMenuItem(value: 1440, child: Text('24 horas')),
                    DropdownMenuItem(value: 10080, child: Text('7 dias')),
                  ],
                  onChanged: _sending
                      ? null
                      : (value) =>
                          setState(() => _duration = value == 0 ? null : value),
                ),
                if (!_multiple)
                  DropdownButtonFormField<int>(
                    value: _correct ?? -1,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Resposta correta do quiz'),
                    items: [
                      const DropdownMenuItem(
                          value: -1, child: Text('Sem quiz')),
                      for (var index = 0; index < _options.length; index++)
                        DropdownMenuItem(
                            value: index, child: Text('Opção ${index + 1}')),
                    ],
                    onChanged: _sending
                        ? null
                        : (value) => setState(
                            () => _correct = value == -1 ? null : value),
                  ),
                const SizedBox(height: 12),
                const Text(
                    'A enquete e os votos ficam na conversa cifrada. O outro contato pode identificar seu voto.'),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: _sending ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: _sending ? null : _submit,
                child: Text(_sending ? 'Salvando…' : 'Publicar enquete')),
          ],
        ),
      );
}

class DirectPollCard extends StatefulWidget {
  const DirectPollCard({
    super.key,
    required this.poll,
    required this.conversationId,
    required this.outgoing,
    required this.deliveryState,
  });

  final DirectPollState poll;
  final String conversationId;
  final bool outgoing;
  final String deliveryState;

  @override
  State<DirectPollCard> createState() => _DirectPollCardState();
}

class _DirectPollCardState extends State<DirectPollCard>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _busy = false;

  void _arm() {
    _timer?.cancel();
    final left = widget.poll.deadline?.difference(DateTime.now());
    if (left != null && left > Duration.zero && !widget.poll.closed) {
      _timer = Timer(left, () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arm();
  }

  @override
  void didUpdateWidget(DirectPollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.poll.deadline != widget.poll.deadline ||
        oldWidget.poll.closed != widget.poll.closed) _arm();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _arm();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _do(Future<void> Function() operation) async {
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        final message = error is StateError
            ? error.message
            : 'Não foi possível registrar a ação.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(NixState state, String actor) async {
    final poll = widget.poll;
    final choices = await showDialog<List<int>>(
      context: context,
      builder: (_) => _PollBallot(
          poll: poll,
          initial: poll.choicesOf(actor),
          order: poll.optionsFor(actor)),
    );
    if (!mounted || choices == null || _busy) return;
    await _do(
        () => state.voteDirectPoll(widget.conversationId, poll.id, choices));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final actor = state.userProfile.publicId;
    final poll = widget.poll;
    final spec = poll.spec;
    final open = poll.acceptsVotesAt(DateTime.now());
    final canAct = !_busy && state.canUseDirectPolls(widget.conversationId);
    final own = poll.choicesOf(actor);
    final showCounts = !spec.hideResults || !open;
    final counts = showCounts ? poll.counts : null;
    final deadline = poll.deadline?.toLocal();
    return Align(
      alignment: widget.outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(spec.correctOption == null ? 'Enquete' : 'Quiz',
                    style: Theme.of(context).textTheme.labelMedium),
                Text(spec.question,
                    style: Theme.of(context).textTheme.titleMedium),
                if (spec.description.isNotEmpty) Text(spec.description),
                if (deadline != null && open)
                  Text(
                      'Até ${MaterialLocalizations.of(context).formatShortDate(deadline)} '
                      '${TimeOfDay.fromDateTime(deadline).format(context)}'),
                for (final index in poll.optionsFor(actor))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        if (own.contains(index))
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(Icons.check,
                                size: 16, semanticLabel: 'Seu voto'),
                          ),
                        Expanded(child: Text(spec.options[index])),
                        if (counts != null) Text('${counts[index]}'),
                        if (!open && spec.correctOption == index)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.task_alt,
                                size: 16, semanticLabel: 'Resposta correta'),
                          ),
                      ],
                    ),
                  ),
                if (poll.pendingFor(actor) ||
                    (widget.outgoing &&
                        ['queued', 'failed'].contains(widget.deliveryState)))
                  const Text('Envio pendente no cofre.'),
                if (poll.closed)
                  const Text('Encerrada pelo autor.')
                else if (!open)
                  const Text('Prazo encerrado.'),
                Wrap(
                  spacing: 8,
                  children: [
                    if (open && (own.isEmpty || spec.allowRevote))
                      FilledButton.tonal(
                        onPressed: canAct ? () => _choose(state, actor) : null,
                        child: Text(own.isEmpty ? 'Votar' : 'Alterar voto'),
                      ),
                    if (!poll.closed && poll.creatorId == actor)
                      TextButton(
                        onPressed: canAct
                            ? () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dialog) => AlertDialog(
                                    title: const Text('Encerrar enquete?'),
                                    content: const Text(
                                        'O resultado será fechado com os votos disponíveis neste dispositivo.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialog, false),
                                          child: const Text('Cancelar')),
                                      FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(dialog, true),
                                          child: const Text('Encerrar')),
                                    ],
                                  ),
                                );
                                if (!mounted || confirmed != true || _busy)
                                  return;
                                await _do(() => state.closeDirectPoll(
                                    widget.conversationId, poll.id));
                              }
                            : null,
                        child: const Text('Encerrar'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PollBallot extends StatefulWidget {
  const _PollBallot(
      {required this.poll, required this.initial, required this.order});
  final DirectPollState poll;
  final List<int> initial;
  final List<int> order;

  @override
  State<_PollBallot> createState() => _PollBallotState();
}

class _PollBallotState extends State<_PollBallot> {
  late final _choices = widget.initial.toSet();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Registrar voto'),
        scrollable: true,
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final index in widget.order)
                CheckboxListTile(
                  title: Text(widget.poll.spec.options[index]),
                  value: _choices.contains(index),
                  onChanged: (checked) => setState(() {
                    if (!widget.poll.spec.multiple) _choices.clear();
                    if (checked == true) {
                      _choices.add(index);
                    } else {
                      _choices.remove(index);
                    }
                  }),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: _choices.isEmpty
                ? null
                : () => Navigator.pop(context, _choices.toList()..sort()),
            child: const Text('Confirmar voto'),
          ),
        ],
      );
}
