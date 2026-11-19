import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/models/user_settings.dart';
import '../../core/theme/nix_palette.dart';

/// ViewModel desacoplado para preferências do usuário, temas, privacidade e persistência (Fase 17 / Etapa 8).
class PreferencesViewModel extends ChangeNotifier {
  UserSettings _settings;
  final String? storageFilePath;

  PreferencesViewModel({
    UserSettings initialSettings = const UserSettings(),
    this.storageFilePath,
  }) : _settings = initialSettings;

  UserSettings get settings => _settings;

  // Helpers de acesso rápido
  NixThemeMode get themeMode => _settings.themeMode;
  NixPaletteType get paletteType => _settings.paletteType;
  bool get silentMode => _settings.silentMode;
  double get fontScale => _settings.fontScale;
  bool get compactChatMode => _settings.compactChatMode;
  bool get enterToSend => _settings.enterToSend;
  bool get stripExifMetadata => _settings.stripExifMetadata;
  String get transportProfile => _settings.transportProfile;
  int get defaultRetentionDays => _settings.defaultRetentionDays;

  void updateSettings(UserSettings newSettings) {
    _settings = newSettings;
    notifyListeners();
    _saveToDisk();
  }

  void setThemeMode(NixThemeMode mode) {
    if (_settings.themeMode != mode) {
      _settings = _settings.copyWith(themeMode: mode);
      notifyListeners();
      _saveToDisk();
    }
  }

  void setPaletteType(NixPaletteType palette) {
    if (_settings.paletteType != palette) {
      _settings = _settings.copyWith(paletteType: palette);
      notifyListeners();
      _saveToDisk();
    }
  }

  void setSilentMode(bool silent) {
    if (_settings.silentMode != silent) {
      _settings = _settings.copyWith(silentMode: silent);
      notifyListeners();
      _saveToDisk();
    }
  }

  void setFontScale(double scale) {
    if (_settings.fontScale != scale) {
      _settings = _settings.copyWith(fontScale: scale);
      notifyListeners();
      _saveToDisk();
    }
  }

  void setCompactChatMode(bool compact) {
    if (_settings.compactChatMode != compact) {
      _settings = _settings.copyWith(compactChatMode: compact);
      notifyListeners();
      _saveToDisk();
    }
  }

  void setEnterToSend(bool enter) {
    if (_settings.enterToSend != enter) {
      _settings = _settings.copyWith(enterToSend: enter);
      notifyListeners();
      _saveToDisk();
    }
  }

  void setStripExifMetadata(bool strip) {
    if (_settings.stripExifMetadata != strip) {
      _settings = _settings.copyWith(stripExifMetadata: strip);
      notifyListeners();
      _saveToDisk();
    }
  }

  void setTransportProfile(String profile) {
    if (_settings.transportProfile != profile) {
      _settings = _settings.copyWith(transportProfile: profile);
      notifyListeners();
      _saveToDisk();
    }
  }

  void setDefaultRetentionDays(int days) {
    if (_settings.defaultRetentionDays != days) {
      _settings = _settings.copyWith(defaultRetentionDays: days);
      notifyListeners();
      _saveToDisk();
    }
  }

  Future<void> _saveToDisk() async {
    if (storageFilePath == null) return;
    try {
      final f = File(storageFilePath!);
      if (!f.parent.existsSync()) {
        f.parent.createSync(recursive: true);
      }
      await f.writeAsString(jsonEncode(_settings.toJson()));
    } catch (_) {}
  }

  Future<void> loadFromDisk() async {
    if (storageFilePath == null) return;
    try {
      final f = File(storageFilePath!);
      if (await f.exists()) {
        final raw = await f.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _settings = UserSettings.fromJson(json);
        notifyListeners();
      }
    } catch (_) {}
  }
}
