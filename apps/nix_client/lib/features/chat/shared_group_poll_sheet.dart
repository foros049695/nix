import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/messaging/shared_group_poll.dart';
import '../../state/nix_state.dart';

Future<void> inviteSharedPollContacts(
    BuildContext context, String channel, String poll) async {
  final state = context.read<NixState>();
  final contacts = state.groupPollContacts;
  final checked = <String>{};
  final selected = await showDialog<Set<String>>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: const Text('Compartilhar enquete'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (contacts.isEmpty)
              const Text('Adicione um contato verificado com sessão cifrada.'),
            for (final contact in contacts)
              CheckboxListTile(
                title: Text(contact.peerName),
                value: checked.contains(contact.id),
                onChanged: (value) => refresh(() {
                  if (value == true) {
                    checked.add(contact.id);
                  } else {
                    checked.remove(contact.id);
                  }
                }),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed:
                checked.isEmpty ? null : () => Navigator.pop(dialog, checked),
            child: const Text('Convidar'),
          ),
        ],
      ),
    ),
  );
  if (selected != null)
    await state.synchronizeGroupPoll(channel, poll, invite: selected);
}

class SharedGroupPollSheet extends StatelessWidget {
  const SharedGroupPollSheet({super.key, required this.conversation});
  final String conversation;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final thread = state.sharedGroupPollsFor(conversation);
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .82),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(18),
          children: [
            Text('Enquetes compartilhadas',
                style: Theme.of(context).textTheme.titleLarge),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: !state.canSyncSharedPolls
                    ? null
                    : () async {
                        await state.syncWithRelay();
                      },
                icon: const Icon(Icons.sync),
                label: const Text('Atualizar enquetes'),
              ),
            ),
            if (thread?.received.isNotEmpty != true)
              const Text('Nenhuma enquete recebida nesta conversa.'),
            for (final offer
                in thread?.received.values ?? const <SharedGroupPollPacket>[])
              _BallotCard(
                key: ValueKey(offer.id),
                packet: offer,
                previous: thread?.sentBallots[offer.id]?.values,
                enabled: state.canSyncSharedPolls,
                send: (choices) => state.submitSharedGroupBallot(
                    conversation, offer.id, choices),
              ),
          ],
        ),
      ),
    );
  }
}

class _BallotCard extends StatefulWidget {
  const _BallotCard(
      {super.key,
      required this.packet,
      required this.previous,
      required this.enabled,
      required this.send});
  final SharedGroupPollPacket packet;
  final List<int>? previous;
  final bool enabled;
  final Future<void> Function(List<int>) send;

  @override
  State<_BallotCard> createState() => _BallotCardState();
}

class _BallotCardState extends State<_BallotCard> {
  Set<int>? _selection;
  bool _busy = false;

  Future<void> _send(List<int> values) async {
    setState(() => _busy = true);
    try {
      await widget.send(values);
      if (mounted) setState(() => _selection = null);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('O voto não pôde ser sincronizado.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packet = widget.packet;
    final spec = packet.spec!;
    final deadline = spec.durationMinutes == null
        ? null
        : packet.created!.add(Duration(minutes: spec.durationMinutes!));
    final open = !packet.closed && (deadline?.isAfter(DateTime.now()) ?? true);
    final mutable = widget.enabled &&
        open &&
        !_busy &&
        (widget.previous == null || spec.allowRevote);
    final selected = _selection ?? widget.previous?.toSet() ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(spec.question, style: Theme.of(context).textTheme.titleMedium),
            if (spec.description.isNotEmpty) Text(spec.description),
            if (!open) const Text('Encerrada'),
            for (var index = 0; index < spec.options.length; index++)
              CheckboxListTile(
                title: Text(spec.options[index]),
                subtitle: !spec.hideResults || packet.closed
                    ? Text('${packet.values[index]} voto(s)')
                    : null,
                value: selected.contains(index),
                onChanged: !mutable
                    ? null
                    : (active) => setState(() {
                          _selection = spec.multiple ? {...selected} : <int>{};
                          if (active == true) {
                            _selection!.add(index);
                          } else {
                            _selection!.remove(index);
                          }
                        }),
              ),
            if (mutable)
              FilledButton.tonal(
                onPressed: _selection != null && spec.accepts(selected.toList())
                    ? () => _send(selected.toList())
                    : null,
                child: const Text('Enviar voto'),
              ),
          ],
        ),
      ),
    );
  }
}
