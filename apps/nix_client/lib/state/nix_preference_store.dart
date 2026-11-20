import 'dart:convert';
import 'dart:io';

import '../core/database/repositories/preferences_repository.dart';
import '../core/models/space.dart';
import '../core/models/user_profile.dart';
import '../core/models/user_settings.dart';
import '../core/security/platform_runtime.dart';

/// Serializa gravações e mantém o formato de preferências de instalações existentes.
class NixPreferenceStore {
  static const _personalKey = 'personal_preferences_v1';
  static const _legacyPrivateFields = {
    'savedAcervoIds',
    'pagerMusic',
    'culturalItems'
  };
  static const savedAcervoKey = 'saved_acervo_ids_v1';
  static const _workspaceKey = 'workspace_layout_v1';

  Future<void> _writes = Future<void>.value();
  Future<void> flush() => _writes;

  Future<void> enqueue(Future<void> Function() write,
      {required bool reportErrors}) {
    final pending = _writes.then((_) => write());
    _writes = pending.catchError((Object _) {
      // Uma falha não impede as gravações seguintes.
    });
    return reportErrors ? pending : _writes;
  }

  final String? bootstrapPath;

  NixPreferenceStore({this.bootstrapPath});

  String get _path =>
      bootstrapPath ??
      (Platform.environment['FLUTTER_TEST'] == 'true'
          ? ''
          : NixPlatformPaths.resolveDataFile('client_prefs_v4.json'));

  Future<Map<String, dynamic>?> readBootstrap() async {
    final path = _path;
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final raw = jsonDecode(await file.readAsString());
    return raw is Map<String, dynamic> ? raw : null;
  }

  Future<void> write({
    required PreferencesRepository? repository,
    required UserSettings settings,
    required UserProfile profile,
    required List<Space> spaces,
    required List<SpaceFolder> folders,
    required bool workspaceChanged,
    required bool Function() mayWrite,
  }) async {
    if (!mayWrite()) return;
    if (repository != null) {
      await repository.setOption(_personalKey, {
        'settings': settings.toJson(),
        'avatarStyle': profile.avatarStyle,
        'avatarPath': profile.customAvatarPath,
        'avatarCropScale': profile.avatarCropScale,
        'avatarCropX': profile.avatarCropOffsetX,
        'avatarCropY': profile.avatarCropOffsetY,
        'pagerMusic': profile.currentActivity,
      });
      if (workspaceChanged) {
        await repository.setOption(_workspaceKey, {
          'spaces': spaces
              .where((space) => !space.isDirectMessages)
              .map((space) => space.toJson())
              .toList(),
          'folders': folders.map((folder) => folder.toJson()).toList(),
        });
      }
    }
    if (!mayWrite()) return;
    try {
      final path = _path;
      if (path.isEmpty) return;
      final existing = await readBootstrap() ?? {};
      final data = {
        'settings': settings.toBootstrapJson(),
        for (final field in _legacyPrivateFields)
          if (existing.containsKey(field)) field: existing[field],
        if (existing.containsKey('folders')) 'folders': existing['folders'],
      };
      if (mayWrite()) await _writeBootstrap(data);
    } catch (_) {
      // Preferências de inicialização são auxiliares ao cofre.
    }
  }

  Future<void> _writeBootstrap(Map<String, dynamic> data) async {
    final file = File(_path);
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.pending');
    await pending.writeAsString(jsonEncode(data), flush: true);
    await pending.rename(file.path);
  }

  /// Migra dados de instalações antigas somente depois de abrir o cofre cifrado.
  /// O JSON só é limpo após todos os registros legados terem destino durável.
  Future<void> migrateLegacyAcervo({
    required PreferencesRepository repository,
    required Future<void> Function(Map<String, dynamic>) importMissingItem,
    required bool Function() mayWrite,
  }) =>
      enqueue(() async {
        final legacy = await readBootstrap();
        if (legacy == null ||
            !_legacyPrivateFields.any(legacy.containsKey) ||
            !mayWrite()) return;
        if (legacy['savedAcervoIds'] case final List ids) {
          if (await repository.getOption(savedAcervoKey) == null) {
            await repository.setOption(savedAcervoKey, ids);
          }
        }
        if (legacy['pagerMusic'] case final String track) {
          final options = await repository.getOption(_personalKey);
          final personal =
              options is Map<String, dynamic> ? options : <String, dynamic>{};
          if (personal['pagerMusic'] == null) {
            await repository
                .setOption(_personalKey, {...personal, 'pagerMusic': track});
          }
        }
        if (legacy['culturalItems'] case final List items) {
          for (final item in items.whereType<Map<String, dynamic>>()) {
            if (!mayWrite()) return;
            await importMissingItem(item);
          }
        }
        if (!mayWrite()) return;
        for (final field in _legacyPrivateFields) {
          legacy.remove(field);
        }
        await _writeBootstrap(legacy);
      }, reportErrors: true);

  Future<({UserSettings? settings, UserProfile profile, String? avatarStyle})?>
      readPersonal(
          PreferencesRepository? repository, UserProfile profile) async {
    final raw = await repository?.getOption(_personalKey);
    if (raw is! Map<String, dynamic>) return null;
    final options = raw['settings'];
    double crop(String field, double fallback, double min, double max) {
      final value = raw[field];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    return (
      settings: options is Map<String, dynamic>
          ? UserSettings.fromJson(options)
          : null,
      avatarStyle: raw['avatarStyle'] as String?,
      profile: profile.copyWith(
        customAvatarPath: raw['avatarPath'] as String?,
        clearCustomAvatar: raw['avatarPath'] == null,
        avatarCropScale: crop('avatarCropScale', 1, 1, 2.4),
        avatarCropOffsetX: crop('avatarCropX', 0, -1, 1),
        avatarCropOffsetY: crop('avatarCropY', 0, -1, 1),
        currentActivity: raw['pagerMusic'] as String?,
      ),
    );
  }

  Future<({List<Space>? spaces, List<SpaceFolder>? folders})> readWorkspace(
      PreferencesRepository repository) async {
    var raw = await repository.getOption(_workspaceKey);
    if (raw == null) {
      final bootstrap = await readBootstrap();
      if (bootstrap?['folders'] case final List folders) {
        raw = {'folders': folders};
      }
    }
    if (raw is! Map) return (spaces: null, folders: null);
    final spaces = raw['spaces'];
    final folders = raw['folders'];
    return (
      spaces: spaces is List
          ? spaces
              .whereType<Map<String, dynamic>>()
              .map(Space.fromJson)
              .where((space) => space.channels.isNotEmpty)
              .toList()
          : null,
      folders: folders is List
          ? folders
              .whereType<Map<String, dynamic>>()
              .map(SpaceFolder.fromJson)
              .where((folder) => folder.id != 'all' && folder.id != 'private')
              .toList()
          : null,
    );
  }
}
