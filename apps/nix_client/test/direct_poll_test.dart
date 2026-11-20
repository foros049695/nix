import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/messaging/direct_poll.dart';
import 'package:nix_client/features/chat/direct_poll_widgets.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10);
  final spec = DirectPollSpec.create(
    question: 'Qual é a opção correta?',
    options: ['A', 'B'],
    correctOption: 1,
    durationMinutes: 5,
    hideResults: true,
    shuffle: true,
  );

  Map<String, Object?> entry(
          String id, String actor, DirectPollEvent event, DateTime when) =>
      {
        'id': id,
        'author_key': actor,
        'created_at': when.millisecondsSinceEpoch,
        'delivery_state': 'delivered',
        'body': event.encode(),
      };

  test(
      'enquete rejeita identidade alheia, segunda revisão e votos após o prazo',
      () {
    DirectPollVote vote(int revision, int option) =>
        DirectPollVote(pollId: 'poll', revision: revision, options: [option]);
    final polls = DirectPollState.project(
        [
          entry('poll', 'alice', spec, now),
          entry('vote_late', 'alice', vote(1, 1),
              now.add(const Duration(minutes: 5))),
          entry('vote_a', 'bob', vote(1, 1), now),
          entry('vote_b', 'bob', vote(2, 0), now),
          entry('vote_other', 'carol', vote(1, 0), now),
          entry(
              'close_other',
              'bob',
              const DirectPollClose(
                pollId: 'poll',
                creatorChoices: [0],
                peerChoices: [0],
              ),
              now),
        ].reversed,
        localId: 'alice',
        remoteId: 'bob');
    final poll = polls['poll']!;
    expect(poll.closed, isFalse);
    expect(poll.counts, [0, 1]);
    expect(poll.optionsFor('bob').toSet(), {0, 1});
    expect(poll.optionsFor('bob'), poll.optionsFor('bob'));
    expect(() => poll.makeVote('bob', [0], now), throwsStateError);
    expect(() => poll.makeClose('bob'), throwsStateError);
    expect(poll.acceptsVotesAt(now.add(const Duration(minutes: 5))), isFalse);
  });

  test('formato recusa opções duplicadas e votos fora do limite', () {
    expect(
        () => DirectPollSpec.create(
            question: 'Pergunta', options: ['Sim', 'sim']),
        throwsFormatException);
    expect(
        DirectPollEvent.parse(const DirectPollVote(
          pollId: 'poll',
          revision: 1,
          options: [8],
        ).encode()),
        isNull);
    expect(DirectPollEvent.parse('nix.poll.v1:}'), isNull);
  });

  testWidgets('compositor de enquete valida e publica opções', (tester) async {
    DirectPollSpec? published;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => CreateDirectPollDialog(onCreate: (value) async {
            published = value;
          }),
        ),
        child: const Text('Abrir'),
      ),
    ))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publicar enquete'));
    await tester.pumpAndSettle();
    expect(published, isNull);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Tema da reunião');
    await tester.enterText(fields.at(2), 'Alfa');
    await tester.enterText(fields.at(3), 'Beta');
    await tester.tap(find.text('Publicar enquete'));
    await tester.pumpAndSettle();
    expect(published?.question, 'Tema da reunião');
    expect(published?.options, ['Alfa', 'Beta']);
    expect(find.byType(CreateDirectPollDialog), findsNothing);
  });
}
