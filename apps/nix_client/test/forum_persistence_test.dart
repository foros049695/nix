import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/channel.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fórum restaura conteúdo, filtros e reações do cofre cifrado', () async {
    final dir = await Directory.systemTemp.createTemp('nix-forum-sqlcipher-');
    addTearDown(() => dir.delete(recursive: true));
    final db = '${dir.path}/nix.db';
    final vault = '${dir.path}/vault.json';
    const passphrase = 'forum-persistencia-laboratorio';
    final state = NixState(loadMockData: false);
    addTearDown(state.dispose);
    expect(
        await state.initializeEncryptedDatabase(
          passphrase: passphrase,
          customDbPath: db,
          customVaultPath: vault,
        ),
        isTrue);
    if (!state.localDatabase!.cipherInfo.isEncrypted &&
        Platform.environment['NIX_TEST_ENCRYPTED_FORUM'] != 'true') {
      markTestSkipped('A integração do fórum exige SQLCipher nativo.');
      return;
    }
    expect(state.localDatabase!.cipherInfo.isEncrypted, isTrue);
    await state.persistPrimaryIdentity(
      identity: await NixIdentity.generate(),
      displayName: 'Autora local',
    );
    state.createSpace(name: 'Comunidade privada', description: '', emoji: 'C', withTopics: true);
    final forum = state.currentChannel;
    expect(state.createForumTag('Pesquisa', '🔎'), isTrue);
    expect(
        state.createForumPost(
          title: 'Assunto exclusivo abc123',
          description: 'Descrição **formatada**.',
          tags: ['Pesquisa'],
        ),
        isTrue);
    final post = state.currentForumPosts.single;
    expect(post.images, isEmpty);
    expect(state.addForumComment(post.id, 'Comentário privado xyz987'), isTrue);
    final comment = state.currentForumPosts.single.comments.single;
    state.toggleMessageReaction(comment.id, '👍');
    expect(state.currentForumPosts.single.comments.single.reactions, {'👍': 1});

    expect(
        await state.updateChannelSettings(forum.copyWith(
          type: ChannelType.text,
          permissions: forum.permissions.copyWith(allowMessages: false),
        )),
        isTrue);
    expect(state.addForumComment(post.id, 'Comentário recusado'), isFalse);
    expect(state.createForumPost(title: 'Recusado', description: '', tags: []),
        isFalse);

    await state.flushPreferences();
    await state.localDatabase!.close();
    final raw = latin1.decode(await File(db).readAsBytes());
    expect(raw, isNot(contains('Assunto exclusivo abc123')));
    expect(raw, isNot(contains('xyz987')));

    final restored = NixState(loadMockData: false);
    addTearDown(restored.dispose);
    await restored.unlockWithPassphrase(passphrase,
        customDbPath: db, customVaultPath: vault);
    final channel = restored.spaces
        .expand((space) => space.channels)
        .singleWhere((channel) => channel.id == forum.id);
    restored.selectChannel(channel);
    expect(restored.currentSpace.isSingleChat, isTrue);
    expect(restored.currentForumPosts, isEmpty);
    expect(await restored.updateChannelSettings(channel.copyWith(type: ChannelType.forum)), isTrue);
    final stored = restored.currentForumPosts.single;
    expect(stored.id, post.id);
    expect(stored.tags, ['Pesquisa']);
    expect(restored.forumTagsFor(channel.id), {'Pesquisa': '🔎'});
    expect(stored.comments.single.text, 'Comentário privado xyz987');
    expect(stored.comments.single.reactions, {'👍': 1});
    expect(restored.addForumComment(stored.id, 'Ainda recusado'), isFalse);
  });
}
