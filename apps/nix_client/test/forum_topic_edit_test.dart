import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/forum_post.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('autor pode editar tópico, enquanto perfis não autorizados são bloqueados (em memória)', () {
    final state = NixState(loadMockData: true);
    addTearDown(state.dispose);

    state.createSpace(name: 'Comunidade Teste', description: '', emoji: '🏛️', withTopics: true);

    expect(state.createForumTag('Geral', '💬'), isTrue);
    expect(state.createForumTag('Hardware', '🔧'), isTrue);

    expect(
      state.createForumPost(
        title: 'Título Inicial',
        description: 'Descrição inicial com detalhes.',
        tags: ['Geral'],
      ),
      isTrue,
    );

    final post = state.currentForumPosts.single;
    expect(post.title, 'Título Inicial');
    expect(post.description, 'Descrição inicial com detalhes.');
    expect(post.tags, ['Geral']);
    expect(post.editedAt, isNull);
    expect(post.revision, 1);
    expect(state.canEditForumPost(post), isTrue);

    // Adiciona comentário antes da edição para verificar integridade
    expect(state.addForumComment(post.id, 'Primeira resposta importante'), isTrue);
    expect(state.currentForumPosts.single.comments.length, 1);

    // Edição pelo autor
    final edited = state.editForumPost(
      postId: post.id,
      title: 'Título Editado com Sucesso',
      description: 'Nova descrição atualizada.',
      tags: ['Hardware'],
    );

    expect(edited, isTrue);
    final updatedPost = state.currentForumPosts.single;
    expect(updatedPost.title, 'Título Editado com Sucesso');
    expect(updatedPost.description, 'Nova descrição atualizada.');
    expect(updatedPost.tags, ['Hardware']);
    expect(updatedPost.editedAt, isNotNull);
    expect(updatedPost.revision, 2);
    expect(updatedPost.comments.length, 1);
    expect(updatedPost.comments.first.text, 'Primeira resposta importante');

    // Tópico de outro usuário em canal onde não somos admin
    final foreignPost = ForumPost(
      id: 'foreign_post_1',
      channelId: 'other_unowned_channel',
      title: 'Post de Terceiros',
      authorName: 'Outro Usuario Desconhecido',
      authorFingerprint: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      createdAt: DateTime.now(),
      tags: ['Geral'],
      description: 'Não deveria poder ser editado por qualquer um.',
      comments: const [],
      images: const [],
    );

    expect(state.canEditForumPost(foreignPost), isFalse);
    expect(
      () => state.editForumPost(
        postId: foreignPost.id,
        title: 'Tentativa de Hack',
        description: 'Invasão',
        tags: ['Geral'],
      ),
      returnsNormally,
    );
  });

  test('autor pode editar tópico com cofre SQLCipher', () async {
    final dir = await Directory.systemTemp.createTemp('nix-forum-test1-');
    addTearDown(() => dir.delete(recursive: true));
    final db = '${dir.path}/nix.db';
    final vault = '${dir.path}/vault.json';
    const passphrase = 'forum-edit-teste1';

    final state = NixState(loadMockData: false);
    addTearDown(state.dispose);

    expect(
      await state.initializeEncryptedDatabase(
        passphrase: passphrase,
        customDbPath: db,
        customVaultPath: vault,
      ),
      isTrue,
    );

    if (!state.localDatabase!.cipherInfo.isEncrypted &&
        Platform.environment['NIX_TEST_ENCRYPTED_FORUM'] != 'true') {
      markTestSkipped('A integração do fórum exige SQLCipher nativo.');
      return;
    }

    await state.persistPrimaryIdentity(
      identity: await NixIdentity.generate(),
      displayName: 'Autor Original',
    );

    state.createSpace(name: 'Comunidade Teste', description: '', emoji: '🏛️', withTopics: true);

    expect(state.createForumTag('Geral', '💬'), isTrue);
    expect(state.createForumTag('Hardware', '🔧'), isTrue);

    expect(
      state.createForumPost(
        title: 'Título Inicial',
        description: 'Descrição inicial com detalhes.',
        tags: ['Geral'],
      ),
      isTrue,
    );

    final post = state.currentForumPosts.single;
    expect(post.title, 'Título Inicial');
    expect(post.description, 'Descrição inicial com detalhes.');
    expect(post.tags, ['Geral']);
    expect(post.editedAt, isNull);
    expect(post.revision, 1);
    expect(state.canEditForumPost(post), isTrue);

    // Adiciona comentário antes da edição para verificar integridade
    expect(state.addForumComment(post.id, 'Primeira resposta importante'), isTrue);
    expect(state.currentForumPosts.single.comments.length, 1);

    // Edição pelo autor
    final edited = state.editForumPost(
      postId: post.id,
      title: 'Título Editado com Sucesso',
      description: 'Nova descrição atualizada.',
      tags: ['Hardware'],
    );

    expect(edited, isTrue);
    final updatedPost = state.currentForumPosts.single;
    expect(updatedPost.title, 'Título Editado com Sucesso');
    expect(updatedPost.description, 'Nova descrição atualizada.');
    expect(updatedPost.tags, ['Hardware']);
    expect(updatedPost.editedAt, isNotNull);
    expect(updatedPost.revision, 2);
    // Assegura integridade das respostas existentes
    expect(updatedPost.comments.length, 1);
    expect(updatedPost.comments.first.text, 'Primeira resposta importante');

    // Tópico de outro usuário em canal onde não somos admin
    final foreignPost = ForumPost(
      id: 'foreign_post_1',
      channelId: 'other_unowned_channel',
      title: 'Post de Terceiros',
      authorName: 'Outro Usuario Desconhecido',
      authorFingerprint: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      createdAt: DateTime.now(),
      tags: ['Geral'],
      description: 'Não deveria poder ser editado por qualquer um.',
      comments: const [],
      images: const [],
    );

    expect(state.canEditForumPost(foreignPost), isFalse);
    expect(
      () => state.editForumPost(
        postId: foreignPost.id,
        title: 'Tentativa de Hack',
        description: 'Invasão',
        tags: ['Geral'],
      ),
      returnsNormally,
    );
  });

  test('edição de tópico persiste no cofre SQLCipher e restaura metadados de edição', () async {
    final dir = await Directory.systemTemp.createTemp('nix-forum-edit-sqlcipher-');
    addTearDown(() => dir.delete(recursive: true));
    final db = '${dir.path}/nix.db';
    final vault = '${dir.path}/vault.json';
    const passphrase = 'forum-edit-persistencia-teste';

    final state = NixState(loadMockData: false);
    addTearDown(state.dispose);

    expect(
      await state.initializeEncryptedDatabase(
        passphrase: passphrase,
        customDbPath: db,
        customVaultPath: vault,
      ),
      isTrue,
    );

    if (!state.localDatabase!.cipherInfo.isEncrypted &&
        Platform.environment['NIX_TEST_ENCRYPTED_FORUM'] != 'true') {
      markTestSkipped('A integração do fórum exige SQLCipher nativo.');
      return;
    }

    await state.persistPrimaryIdentity(
      identity: await NixIdentity.generate(),
      displayName: 'Editor Local',
    );

    state.createSpace(name: 'Comunidade Editavel', description: '', emoji: '📝', withTopics: true);
    expect(state.createForumTag('Ideias', '💡'), isTrue);

    expect(
      state.createForumPost(
        title: 'Ideia Versão 1',
        description: 'Primeiro rascunho.',
        tags: ['Ideias'],
      ),
      isTrue,
    );

    final postId = state.currentForumPosts.single.id;
    final channelId = state.currentChannel.id;
    expect(state.addForumComment(postId, 'Comentário persistente'), isTrue);

    // Executa edição
    expect(
      state.editForumPost(
        postId: postId,
        title: 'Ideia Versão Final',
        description: 'Rascunho aprimorado e revisado.',
        tags: ['Ideias'],
      ),
      isTrue,
    );

    await state.flushPreferences();
    await state.localDatabase!.close();

    // Restaura banco
    final restored = NixState(loadMockData: false);
    addTearDown(restored.dispose);
    await restored.unlockWithPassphrase(passphrase, customDbPath: db, customVaultPath: vault);

    final channel = restored.spaces
        .expand((space) => space.channels)
        .singleWhere((channel) => channel.id == channelId);
    restored.selectChannel(channel);

    final restoredPost = restored.currentForumPosts.single;
    expect(restoredPost.title, 'Ideia Versão Final');
    expect(restoredPost.description, 'Rascunho aprimorado e revisado.');
    expect(restoredPost.editedAt, isNotNull);
    expect(restoredPost.revision, 2);
    expect(restoredPost.comments.single.text, 'Comentário persistente');
  });
}
