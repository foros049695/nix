import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/database/repositories.dart';
import 'package:nix_client/core/models/user_profile.dart';
import 'package:nix_client/core/models/user_settings.dart';
import 'package:nix_client/state/nix_preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migra acervo e faixa privados antes de limpar as preferências antigas',
      () async {
    final temp = await Directory.systemTemp.createTemp('nix-acervo-migration-');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/client_prefs_v4.json');
    await file.writeAsString(jsonEncode({
      'settings': {},
      'culturalItems': [
        {'id': 'book1', 'title': 'Livro privado'}
      ],
      'savedAcervoIds': ['repo1'],
      'pagerMusic': 'Faixa privada',
    }));
    final store = NixPreferenceStore(bootstrapPath: file.path);
    final db = await LocalDatabase.open(path: '${temp.path}/migration.db');
    addTearDown(db.close);
    final repo = PreferencesRepository(db);
    await repo.setOption(NixPreferenceStore.savedAcervoKey, ['mais-recente']);

    await expectLater(
      store.migrateLegacyAcervo(
        repository: repo,
        mayWrite: () => true,
        importMissingItem: (_) async => throw StateError('falha transitória'),
      ),
      throwsStateError,
    );
    expect(await file.readAsString(), contains('Livro privado'));

    final imported = <Map<String, dynamic>>[];
    await store.migrateLegacyAcervo(
      repository: repo,
      mayWrite: () => true,
      importMissingItem: (item) async => imported.add(item),
    );
    expect(imported.single['title'], 'Livro privado');
    expect(await repo.getOption(NixPreferenceStore.savedAcervoKey),
        ['mais-recente']);
    const profile = UserProfile(
      publicId: '',
      displayName: '',
      culturalItems: [],
      currentActivity: '',
      bio: '',
      avatarStyle: 'sentinel',
      memberSinceYear: '26',
    );
    expect((await store.readPersonal(repo, profile))!.profile.currentActivity,
        'Faixa privada');
    final public =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(public.keys, ['settings']);

    await store.write(
      repository: repo,
      settings: const UserSettings(),
      profile: profile.copyWith(currentActivity: 'Nova faixa privada'),
      spaces: const [],
      folders: const [],
      workspaceChanged: false,
      mayWrite: () => true,
    );
    expect((await file.readAsString()).contains('Nova faixa privada'), isFalse);
  });
}
