import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/messaging/local_group_poll.dart';
import '../../state/nix_state.dart';
import 'direct_poll_widgets.dart';

class LocalGroupPollSheet extends StatelessWidget {
  const LocalGroupPollSheet({super.key, required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final polls = state.localGroupPollsFor(channelId);
    final enabled = state.canUseLocalGroupPolls(channelId);
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .82),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Text('Enquetes locais do canal',
                style: Theme.of(context).textTheme.titleLarge),
            const Text(
                'As enquetes desta sala ficam no cofre deste dispositivo.'),
            const SizedBox(height: 10),
            for (final poll in polls.reversed)
              _LocalPollCard(
                  key: ValueKey(poll.id), poll: poll, enabled: enabled),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: !enabled
                    ? null
                    : () => showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => CreateDirectPollDialog(
                            local: true,
                            onCreate: (spec) =>
                                state.createLocalGroupPoll(channelId, spec),
                          ),
                        ),
                icon: const Icon(Icons.add),
                label: const Text('Nova enquete'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalPollCard extends StatefulWidget {
  const _LocalPollCard({super.key, required this.poll, required this.enabled});
  final LocalGroupPoll poll;
  final bool enabled;

  @override
  State<_LocalPollCard> createState() => _LocalPollCardState();
}

class _LocalPollCardState extends State<_LocalPollCard> {
  Set<int>? _selection;
  bool _busy = false;

  Future<void> _apply(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
      if (mounted) setState(() => _selection = null);
    } catch (error) {
      if (mounted) {
        final message = error is StateError
            ? error.message
            : 'Não foi possível salvar a enquete.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<NixState>();
    final poll = widget.poll;
    final actor = state.localGroupPollActor;
    final previous = poll.votes[actor];
    final selection = _selection ?? previous?.toSet() ?? {};
    final open = poll.isOpen(DateTime.now());
    final canVote = widget.enabled &&
        open &&
        !_busy &&
        (previous == null || poll.spec.allowRevote);
    final showResults = !poll.spec.hideResults || !open;
    final totals = poll.totals;
    final indexes = List.generate(poll.spec.options.length, (index) => index);
    if (poll.spec.shuffle) {
      indexes.sort((a, b) => ('${poll.id}:$actor:$a')
          .hashCode
          .compareTo(('${poll.id}:$actor:$b').hashCode));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(poll.spec.question,
                style: Theme.of(context).textTheme.titleMedium),
            if (poll.spec.description.isNotEmpty) Text(poll.spec.description),
            if (!open) const Text('Encerrada'),
            for (final index in indexes)
              CheckboxListTile(
                dense: true,
                title: Text(poll.spec.options[index]),
                subtitle: showResults
                    ? Text(
                        '${totals[index]} voto(s)${!open && poll.spec.correctOption == index ? ' · Resposta correta' : ''}',
                      )
                    : null,
                value: selection.contains(index),
                onChanged: !canVote
                    ? null
                    : (selected) => setState(() {
                          _selection =
                              poll.spec.multiple ? {...selection} : <int>{};
                          if (selected == true) {
                            _selection!.add(index);
                          } else {
                            _selection!.remove(index);
                          }
                        }),
              ),
            Wrap(
              spacing: 8,
              children: [
                if (canVote)
                  FilledButton.tonal(
                    onPressed: _selection == null ||
                            !poll.spec.accepts(selection.toList())
                        ? null
                        : () => _apply(() => state.voteLocalGroupPoll(
                            poll.channelId, poll.id, selection.toList())),
                    child: const Text('Votar'),
                  ),
                if (widget.enabled && !poll.closed && actor == poll.creator)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _apply(
                              () => state.closeLocalGroupPoll(
                                  poll.channelId, poll.id),
                            ),
                    child: const Text('Encerrar enquete'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
