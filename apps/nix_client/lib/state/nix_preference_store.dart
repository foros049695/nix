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

  String get _path => Platform.environment['FLUTTER_TEST'] == 'true'
      ? ''
      : NixPlatformPaths.resolveDataFile('client_prefs_v4.json');

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
    required Set<String> savedAcervoIds,
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
      final file = File(path);
      await file.parent.create(recursive: true);
      final data = {
        'settings': settings.toBootstrapJson(),
        'savedAcervoIds': savedAcervoIds.toList(),
        'pagerMusic': profile.currentActivity,
        'culturalItems':
            profile.culturalItems.map((item) => item.toJson()).toList(),
      };
      final pending = File('$path.pending');
      await pending.writeAsString(jsonEncode(data), flush: true);
      await pending.rename(file.path);
    } catch (_) {
      // Preferências de inicialização são auxiliares ao cofre.
    }
  }

  Future<({UserSettings? settings, UserProfile profile, String? avatarStyle})?> readPersonal(
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
