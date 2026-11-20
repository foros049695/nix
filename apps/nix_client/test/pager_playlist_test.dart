import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/database/repositories.dart';
import 'package:nix_client/core/media/pager_playlist.dart';
import 'package:nix_client/features/profile/pager_playlist_dialog.dart';

const _first = PagerTrack(
  uri:
      'content://com.android.externalstorage.documents/document/primary%3AMusic%2Fa.wav',
  name: 'Faixa A',
);
const _second = PagerTrack(
  uri: 'content://com.android.providers.media.documents/document/audio%3A2',
  name: 'Faixa B',
);

class _MemoryPlaylist implements PagerPlaylist {
  List<PagerTrack> tracks = [_first];

  @override
  PreferencesRepository get preferences => throw UnimplementedError();

  @override
  Future<List<PagerTrack>> load() async => [...tracks];

  @override
  Future<void> save(List<PagerTrack> tracks) async => this.tracks = [...tracks];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('playlist recupera ordem após reabrir cofre e rejeita fontes externas',
      () async {
    final temp = await Directory.systemTemp.createTemp('nix_playlist_');
    final path = '${temp.path}/private.db';
    final key = Uint8List.fromList(List.generate(32, (index) => index + 1));
    var db = await LocalDatabase.open(path: path, rawCipherKey: key);
    try {
      var playlist = PagerPlaylist(PreferencesRepository(db));
      await playlist.save([_second, _first]);
      await db.close();
      db = await LocalDatabase.open(path: path, rawCipherKey: key);
      playlist = PagerPlaylist(PreferencesRepository(db));
      expect((await playlist.load()).map((track) => track.name),
          [_second.name, _first.name]);
      await expectLater(
        playlist.save([
          const PagerTrack(uri: 'https://example.test/audio.mp3', name: 'Rede')
        ]),
        throwsFormatException,
      );
      await expectLater(playlist.save([_first, _first]), throwsFormatException);
      expect((await playlist.load()).map((track) => track.uri),
          [_second.uri, _first.uri]);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  testWidgets(
      'playlist aciona o player apenas por comando e persiste alterações',
      (tester) async {
    final playlist = _MemoryPlaylist();
    final operations = <String>[];
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    binaryMessenger.setMockMethodCallHandler(PagerPlaylistDialog.channel,
        (call) async {
      operations.add(call.method);
      return switch (call.method) {
        'pick' => _second.toMap(),
        'playing' => null,
        _ => null,
      };
    });
    addTearDown(() => binaryMessenger.setMockMethodCallHandler(
        PagerPlaylistDialog.channel, null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => PagerPlaylistDialog(playlist: playlist),
        ),
        child: const Text('Abrir'),
      ),
    ))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(operations, isEmpty);

    await tester.tap(find.text('Adicionar faixa'));
    await tester.pumpAndSettle();
    expect(playlist.tracks.map((track) => track.name), ['Faixa A', 'Faixa B']);
    await tester.tap(find.byTooltip('Opções da faixa').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mover para cima'));
    await tester.pumpAndSettle();
    expect(playlist.tracks.map((track) => track.name), ['Faixa B', 'Faixa A']);

    await tester.tap(find.byTooltip('Reproduzir').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Parar'), findsOneWidget);
    await tester.tap(find.byTooltip('Opções da faixa').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover faixa'));
    await tester.pumpAndSettle();
    expect(playlist.tracks.map((track) => track.name), ['Faixa A']);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(operations, containsAllInOrder(['pick', 'play', 'release', 'stop']));
  });
}
