import 'cultural_item.dart';

class UserProfile {
  final String publicId;
  final String displayName;
  final String bio;
  final String currentActivity; // Removido da exibição no Card ID (V4)
  final String memberSinceYear;
  final String avatarStyle; // 'nyx_emblem', 'monogram', 'custom_1', 'custom_2', 'local_file'
  final String? customAvatarPath;
  final double avatarCropScale;
  final double avatarCropOffsetX;
  final double avatarCropOffsetY;
  final List<CulturalItem> culturalItems;

  const UserProfile({
    required this.publicId,
    required this.displayName,
    required this.bio,
    this.currentActivity = '',
    required this.memberSinceYear,
    this.avatarStyle = 'nyx_emblem',
    this.customAvatarPath,
    this.avatarCropScale = 1.0,
    this.avatarCropOffsetX = 0.0,
    this.avatarCropOffsetY = 0.0,
    required this.culturalItems,
  });

  /// Nome de exibição efetivo: se o usuário deixar o nome em branco, gera fallback determinístico
  /// derivado da chave pública/ID (ex: NX-7E3A), sem nomes aleatórios a cada inicialização.
  String get effectiveDisplayName {
    if (displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    final cleanId = publicId.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '');
    final suffix = cleanId.length >= 4 ? cleanId.substring(0, 4).toUpperCase() : 'SOVR';
    return 'NX-$suffix';
  }

  /// Retorna apenas os itens marcados para exibição pública no Card ID.
  List<CulturalItem> get publicCulturalItems =>
      culturalItems.where((item) => item.isPublicInCardId).toList();

  /// Payload público seguro para QR Code (NUNCA inclui chaves privadas, seeds ou tokens).
  String get qrPublicPayload =>
      'nix://id/$publicId?name=${Uri.encodeComponent(effectiveDisplayName)}&v=4';

  UserProfile copyWith({
    String? publicId,
    String? displayName,
    String? bio,
    String? currentActivity,
    String? memberSinceYear,
    String? avatarStyle,
    String? customAvatarPath,
    bool clearCustomAvatar = false,
    double? avatarCropScale,
    double? avatarCropOffsetX,
    double? avatarCropOffsetY,
    List<CulturalItem>? culturalItems,
  }) {
    return UserProfile(
      publicId: publicId ?? this.publicId,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      currentActivity: currentActivity ?? this.currentActivity,
      memberSinceYear: memberSinceYear ?? this.memberSinceYear,
      avatarStyle: avatarStyle ?? this.avatarStyle,
      customAvatarPath: clearCustomAvatar ? null : (customAvatarPath ?? this.customAvatarPath),
      avatarCropScale: avatarCropScale ?? this.avatarCropScale,
      avatarCropOffsetX: avatarCropOffsetX ?? this.avatarCropOffsetX,
      avatarCropOffsetY: avatarCropOffsetY ?? this.avatarCropOffsetY,
      culturalItems: culturalItems ?? this.culturalItems,
    );
  }
}
