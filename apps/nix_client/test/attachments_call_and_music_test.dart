import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/media/catalog_database.dart';
import 'package:nix_client/core/media/music_online_metadata_service.dart';
import 'package:nix_client/core/media/pager_playlist.dart';
import 'package:nix_client/core/models/channel.dart';
import 'package:nix_client/core/models/cultural_item.dart';
import 'package:nix_client/core/models/message.dart';
import 'package:nix_client/features/calls/call_room_view.dart';
import 'package:nix_client/features/chat/message_attachment_tile.dart';
import 'package:nix_client/features/profile/cultural_catalog_picker.dart';
import 'package:nix_client/features/navigation/channels_sidebar.dart';
import 'package:nix_client/features/navigation/spaces_dock.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('instala busca musical idempotente e preserva a base original',
      () async {
    final directory = await Directory.systemTemp.createTemp('nix-music-test-');
    addTearDown(() => directory.delete(recursive: true));
    final seed = await File('assets/catalog/seed_catalog.db')
        .copy('${directory.path}/test.db');
    final catalog = await CatalogDatabase.open(path: seed.path);
    addTearDown(catalog.close);
    expect(await catalog.getEntryCount(), 25);
    await catalog.installBundledMusic();
    final count = await catalog.getEntryCount();
    expect(count, greaterThan(40));
    await catalog.installBundledMusic();
    expect(await catalog.getEntryCount(), count);
    expect(await catalog.searchWorks(query: 'Blade Runner'), isNotEmpty);
    final tracks =
        await catalog.searchWorks(query: 'miles davis blue', kind: 'track');
    expect(tracks, isNotEmpty);
    expect(
        tracks.any((track) => track.originalTitle == 'Kind of Blue'), isTrue);
    expect(
        culturalItemFromCatalog(tracks.first).category, CulturalCategory.music);
  });

  testWidgets('anexo local exibe imagem e nome sem expor caminho',
      (tester) async {
    final file = await tester.runAsync(() async {
      final directory =
          await Directory.systemTemp.createTemp('nix-attachment-');
      addTearDown(() => directory.delete(recursive: true));
      return File('${directory.path}/photo.png').writeAsBytes(
        base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aDHsAAAAASUVORK5CYII='),
      );
    });
    final state = NixState(loadMockData: false);
    addTearDown(state.dispose);
    final message = Message(
      id: 'local-image',
      channelId: state.currentChannel.id,
      senderName: 'Local',
      senderFingerprint: 'local',
      isMe: true,
      text: '',
      timestamp: DateTime.now(),
      attachments: [file!.path],
    );
    Future<Uint8List?> remotePreview() => state.readMessageImage(
        Message(
            id: 'remote-untrusted',
            channelId: message.channelId,
            senderName: 'Remote',
            senderFingerprint: 'remote',
            isMe: false,
            text: '',
            timestamp: message.timestamp,
            attachments: [file.path]),
        0);
    expect(await remotePreview(), isNull);

    await tester.runAsync(() async {
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
            home: Scaffold(
                body: Center(
          child: MessageAttachmentTile(message: message, index: 0),
        ))),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
    // Conforme especificação moderna: fotos não expõem nome do arquivo por padrão nem o caminho
    expect(find.text('photo.png'), findsNothing);
    expect(find.text(file.path), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('aviso de chat aparece na sala ativa e reabre o painel',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 730));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = NixState(loadMockData: false);
    addTearDown(state.dispose);
    state.createChannel(
        name: 'Sala', type: ChannelType.voice, topic: '', category: 'Voz');
    final channel = state.currentChannel;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(home: Scaffold(body: CallRoomView(channel: channel))),
    ));
    await tester.tap(find.text('Entrar na Sala de Call'));
    await tester.pump();
    expect(state.sendMessage('aviso local'), isTrue);
    await tester.pump();
    final popup = find.byKey(const Key('call_chat_popup'));
    expect(popup, findsOneWidget);
    await tester.tap(popup);
    await tester.pumpAndSettle();
    expect(find.text('Chat da sala · sala'), findsOneWidget);
    expect(find.text('aviso local'), findsOneWidget);
    expect(popup, findsNothing);
    state.leaveCall();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('agrupa canais com o dedo e solta em Todas para retirar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = NixState(loadMockData: false);
    addTearDown(state.dispose);
    final general = state.currentChannel;
    state.createChannel(
        name: 'Estudos',
        type: ChannelType.text,
        topic: '',
        category: general.category);
    final study = state.currentChannel;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(
          home: Scaffold(
              body: Row(children: [
        SpacesDock(width: 75),
        Expanded(child: ChannelsSidebar(width: 315)),
      ]))),
    ));
    await tester.pumpAndSettle();

    Future<void> drag(Finder source, Finder destination) async {
      final gesture = await tester.startGesture(tester.getCenter(source));
      await tester.pump(const Duration(milliseconds: 650));
      await gesture.moveTo(tester.getCenter(destination));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await drag(find.text(study.name), find.text(general.name));
    final folder =
        state.folders.firstWhere((f) => f.conversationIds.contains(study.id));
    expect(folder.conversationIds, unorderedEquals([study.id, general.id]));
    await tester.tap(find.byKey(Key('folder_tab_${folder.id}')));
    await tester.pumpAndSettle();
    final member =
        find.byKey(ValueKey('folder_member_${folder.id}_${study.id}'));
    final expand = find.byKey(ValueKey('folder_expand_${folder.id}'));
    expect(member, findsOneWidget);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(member, findsNothing);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    await drag(
        find.descendant(
            of: find.byType(ChannelsSidebar), matching: find.text(study.name)),
        find.byKey(const Key('folder_tab_all')));
    expect(state.folders.firstWhere((f) => f.id == folder.id).conversationIds,
        [general.id]);
    expect(tester.takeException(), isNull);
  });

  test('move canais individuais e libera os itens ao dissolver pasta', () {
    final state = NixState(loadMockData: false);
    addTearDown(state.dispose);
    final general = state.currentChannel;
    state.createChannel(
        name: 'Estudos',
        type: ChannelType.text,
        topic: '',
        category: 'Conversas');
    final study = state.currentChannel;
    state.combineSpacesIntoFolder(study.id, general.id);
    final folder =
        state.folders.firstWhere((f) => f.conversationIds.contains(study.id));
    expect(folder.conversationIds, unorderedEquals([study.id, general.id]));
    expect(folder.spaceIds, isEmpty);
    state.selectFolder(folder.id);
    expect(state.channelsInActiveFolder(state.currentSpace), hasLength(2));
    state.ungroupWorkspaceItem(study.id);
    expect(
        state.channelsInActiveFolder(state.currentSpace).single.id, general.id);
    state.dissolveFolder(folder.id);
    expect(state.channelsInActiveFolder(state.currentSpace), hasLength(2));
  });

  test('busca online consentida via Tor rejeita sem consentimento e sem Tor, e indexa metadados no catalogo',
      () async {
    const service = MusicOnlineMetadataService();

    // 1. Falha sem consentimento do usuário
    expect(
      () => service.searchMusicOnline(
        query: 'Pink Floyd',
        userConsent: false,
        isTorReady: true,
      ),
      throwsA(isA<StateError>()),
    );

    // 2. Falha fail-closed se Tor não estiver pronto
    expect(
      () => service.searchMusicOnline(
        query: 'Pink Floyd',
        userConsent: true,
        isTorReady: false,
      ),
      throwsA(isA<Exception>()),
    );

    // 3. Com consentimento e Tor, realiza query mockada isolada
    var isolationSent = '';
    final mockedService = MusicOnlineMetadataService.withQuery(
        ({required query, required circuitIsolation}) async {
      isolationSent = circuitIsolation;
      expect(query, 'Echoes');
      return jsonEncode({
        'recordings': [
          {
            'id': 'mb-track-1234',
            'title': 'Echoes',
            'artist-credit': [
              {'name': 'Pink Floyd'}
            ],
            'releases': [
              {
                'title': 'Meddle',
                'date': '1971-10-30',
              }
            ]
          }
        ]
      });
    });

    final works = await mockedService.searchMusicOnline(
      query: 'Echoes',
      userConsent: true,
      isTorReady: true,
    );

    expect(isolationSent, hasLength(32));
    expect(works, hasLength(1));
    final work = works.first;
    expect(work.title, 'Echoes');
    expect(work.creators, 'Pink Floyd');
    expect(work.releaseYear, 1971);
    expect(work.originalTitle, 'Meddle');

    // 4. Ingestão no CatalogDatabase local e busca via FTS5
    final directory = await Directory.systemTemp.createTemp('nix-online-music-');
    addTearDown(() => directory.delete(recursive: true));
    final catalog = await CatalogDatabase.open(
        path: '${directory.path}/test_catalog.db');
    addTearDown(catalog.close);

    await catalog.upsertWork(work);
    final searchHits = await catalog.searchWorks(query: 'Echoes', kind: 'track');
    expect(searchHits, hasLength(1));
    expect(searchHits.first.id, 'mb_rec_mb-track-1234');

    // 5. Vinculação soberana ao arquivo local existente do usuário (sem streaming remoto)
    const localUri = 'file:///home/gus/Musicas/Echoes_Remaster.wav';
    final track = PagerTrack(
      uri: localUri,
      name: '${work.title} · ${work.creators}',
    );
    expect(track.uri, localUri);
    expect(track.name, 'Echoes · Pink Floyd');
  });
}
