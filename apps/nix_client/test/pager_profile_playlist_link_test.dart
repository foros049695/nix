import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/database/repositories.dart';
import 'package:nix_client/core/media/pager_playlist.dart';
import 'package:nix_client/features/profile/pager_profile.dart';
import 'package:nix_client/features/profile/pager_playlist_dialog.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

class _MemoryPreferencesRepository implements PreferencesRepository {
  final _storage = <String, dynamic>{};

  @override
  Future<dynamic> getOption(String key) async => _storage[key];

  @override
  Future<void> setOption(String key, dynamic value, {int revision = 1}) async {
    _storage[key] = value;
  }
}

void main() {
  testWidgets('Pager Profile links activity to playlist tracks and clears on removal',
      (tester) async {
    final state = NixState(loadMockData: true);
    final repo = _MemoryPreferencesRepository();
    final playlist = PagerPlaylist(repo);
    await playlist.save([
      const PagerTrack(uri: 'file:///home/user/music/ambient.wav', name: 'Ambient Track 01'),
    ]);
    state.setPagerPlaylistForTest(playlist);

    await tester.pumpWidget(
      ChangeNotifierProvider<NixState>.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(
            body: PagerProfile(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open profile editor
    await tester.tap(find.byTooltip('Editar nome e biografia'));
    await tester.pumpAndSettle();

    expect(find.text('Editar perfil do Pager'), findsOneWidget);
    expect(find.byKey(const Key('select_profile_track_button')), findsOneWidget);

    // Click track selection button
    await tester.tap(find.byKey(const Key('select_profile_track_button')));
    await tester.pumpAndSettle();

    expect(find.text('Selecionar música da Playlist'), findsOneWidget);
    expect(find.text('Ambient Track 01'), findsOneWidget);

    // Select the track
    await tester.tap(find.widgetWithText(ElevatedButton, 'Escolher'));
    await tester.pumpAndSettle();

    // Save profile editor
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(state.userProfile.currentActivity, 'Ambient Track 01');

    // Now test removing track updates profile
    await tester.pumpWidget(
      ChangeNotifierProvider<NixState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: PagerPlaylistDialog(playlist: playlist),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Find and remove track
    expect(find.text('Ambient Track 01'), findsOneWidget);
    final deleteButton = find.byIcon(Icons.delete_outline);
    if (deleteButton.evaluate().isNotEmpty) {
      await tester.tap(deleteButton.first);
      await tester.pumpAndSettle();
      expect(state.userProfile.currentActivity, '');
    }
  });
}
