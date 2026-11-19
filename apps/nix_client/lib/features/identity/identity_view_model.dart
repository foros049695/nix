import 'package:flutter/foundation.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import '../../core/models/user_profile.dart';
import '../../core/security/security_context.dart';

/// ViewModel desacoplado para identidades criptográficas, perfis e controle de chaves (Etapa 8).
class IdentityViewModel extends ChangeNotifier {
  NixIdentity? _primaryIdentity;
  UserProfile _userProfile;
  SecurityContext _securityContext;
  bool _requiresPassphraseUnlock = false;
  String? _lastDatabaseInitError;
  String _localDeviceId;
  bool _isVaultUnlocked = false;
  String? _osKeyringBackend;

  IdentityViewModel({
    NixIdentity? initialIdentity,
    UserProfile? initialProfile,
    SecurityContext initialSecurityContext = const SecurityContext(myPersona: 'NX-7E3A'),
    String localDeviceId = 'dev_primary',
  })  : _primaryIdentity = initialIdentity,
        _userProfile = initialProfile ??
            const UserProfile(
              publicId: 'NX-7E3A-9B2F-4C1D',
              displayName: 'Anônimo',
              bio: '',
              memberSinceYear: '2026',
              culturalItems: [],
            ),
        _securityContext = initialSecurityContext,
        _localDeviceId = localDeviceId;

  // Getters
  NixIdentity? get primaryIdentity => _primaryIdentity;
  UserProfile get userProfile => _userProfile;
  SecurityContext get securityContext => _securityContext;
  bool get requiresPassphraseUnlock => _requiresPassphraseUnlock;
  String? get lastDatabaseInitError => _lastDatabaseInitError;
  String get localDeviceId => _localDeviceId;
  bool get isVaultUnlocked => _isVaultUnlocked;
  String? get osKeyringBackend => _osKeyringBackend;

  bool get hasIdentity => _primaryIdentity != null;
  String get effectiveDisplayName => _userProfile.effectiveDisplayName;
  String get publicId => _primaryIdentity?.publicId ?? _userProfile.publicId;

  void setPrimaryIdentity(NixIdentity? identity) {
    _primaryIdentity = identity;
    if (identity != null) {
      _userProfile = _userProfile.copyWith(publicId: identity.publicId);
      _securityContext = _securityContext.copyWith(
        myFingerprint: identity.publicId,
        myPersona: _userProfile.effectiveDisplayName,
      );
    }
    notifyListeners();
  }

  void setUserProfile(UserProfile profile) {
    _userProfile = profile;
    _securityContext = _securityContext.copyWith(
      myPersona: profile.effectiveDisplayName,
      myFingerprint: profile.publicId,
    );
    notifyListeners();
  }

  void updateDisplayName(String newName) {
    final clean = newName.trim();
    if (clean.isNotEmpty && clean != _userProfile.displayName) {
      _userProfile = _userProfile.copyWith(displayName: clean);
      _securityContext = _securityContext.copyWith(myPersona: clean);
      notifyListeners();
    }
  }

  void updateBio(String newBio) {
    final clean = newBio.trim();
    if (clean != _userProfile.bio) {
      _userProfile = _userProfile.copyWith(bio: clean);
      notifyListeners();
    }
  }

  void setSecurityContext(SecurityContext context) {
    _securityContext = context;
    notifyListeners();
  }

  void setRequiresPassphraseUnlock(bool requires) {
    if (_requiresPassphraseUnlock != requires) {
      _requiresPassphraseUnlock = requires;
      notifyListeners();
    }
  }

  void setLastDatabaseInitError(String? error) {
    if (_lastDatabaseInitError != error) {
      _lastDatabaseInitError = error;
      notifyListeners();
    }
  }

  void setVaultStatus({required bool isUnlocked, String? keyringBackend}) {
    _isVaultUnlocked = isUnlocked;
    _osKeyringBackend = keyringBackend;
    notifyListeners();
  }

  void setLocalDeviceId(String deviceId) {
    _localDeviceId = deviceId;
    notifyListeners();
  }

  void clearIdentity() {
    _primaryIdentity = null;
    _isVaultUnlocked = false;
    notifyListeners();
  }
}
