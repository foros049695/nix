import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/messaging/direct_poll.dart';
import 'package:nix_client/core/messaging/local_group_poll.dart';
import 'package:nix_client/core/models/channel.dart';
import 'package:nix_client/state/nix_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('o canal isola voto, revoto e encerramento de enquetes locais',
      () async {
    final state = NixState(loadMockData: true);
    addTearDown(state.dispose);
    state.createChannel(
      name: 'Enquetes',
      type: ChannelType.text,
      topic: '',
      category: 'Geral',
    );
    final first = state.currentChannel;
    final spec = DirectPollSpec.create(
      question: 'Qual cor?',
      options: ['Amarela', 'Verde'],
      allowRevote: true,
    );
    await state.createLocalGroupPoll(first.id, spec);
    final poll = state.localGroupPollsFor(first.id).single;
    await state.voteLocalGroupPoll(first.id, poll.id, [0]);
    await state.voteLocalGroupPoll(first.id, poll.id, [1]);
    final voted = state.localGroupPollsFor(first.id).single;
    expect(voted.totals, [0, 1]);
    expect(LocalGroupPoll.parse(voted.toJson())!.votes.values.single, [1]);
    expect(() => voted.close('different-identity'), throwsStateError);
    state.createChannel(
      name: 'Outro canal',
      type: ChannelType.text,
      topic: '',
      category: 'Geral',
    );
    expect(state.localGroupPollsFor(first.id), isEmpty);
    await expectLater(
      state.voteLocalGroupPoll(state.currentChannel.id, poll.id, [0]),
      throwsStateError,
    );
    state.selectChannel(first);
    await state.closeLocalGroupPoll(first.id, poll.id);
    expect(state.localGroupPollsFor(first.id).single.closed, isTrue);
    await expectLater(
        state.voteLocalGroupPoll(first.id, poll.id, [0]), throwsStateError);
  });

  test('prazo, voto único e formato incompatível', () {
    final now = DateTime.utc(2026, 1);
    final poll = LocalGroupPoll(
      id: 'p',
      channelId: 'g',
      creator: 'creator',
      created: now,
      spec: DirectPollSpec.create(
        question: 'Qual?',
        options: ['Um', 'Dois'],
        durationMinutes: 1,
      ),
    ).vote('member', [1], now);
    expect(poll.totals, [0, 1]);
    expect(() => poll.vote('member', [0], now), throwsStateError);
    expect(() => poll.vote('other', [0], now.add(const Duration(minutes: 1))),
        throwsStateError);
    expect(
        LocalGroupPoll.parse({...poll.toJson(), 'created': 'wrong'}), isNull);
  });
}
