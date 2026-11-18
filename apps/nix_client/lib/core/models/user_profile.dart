import 'cultural_item.dart';

class UserProfile {
  final String publicId;
  final String displayName;
  final String bio;
  final String currentActivity; // Mantido para compatibilidade, mas removido da exibição visual principal do Card ID
  final String memberSinceYear;
  final String avatarStyle; // 'nyx_emblem', 'monogram', 'custom_1', 'custom_2', 'local_file'
  final String? customAvatarPath;
  final List<CulturalItem> culturalItems;

  const UserProfile({
    required this.publicId,
    required this.displayName,
    required this.bio,
    this.currentActivity = '',
    required this.memberSinceYear,
    this.avatarStyle = 'nyx_emblem',
    this.customAvatarPath,
    required this.culturalItems,
  });

  /// Nome de exibição efetivo: se o usuário deixar o nome em branco, gera fallback determinístico
  /// derivado da chave pública/ID (ex: NX-7E3A), preservando anonimato e estabilidade.
  String get effectiveDisplayName {
    if (displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    final cleanId = publicId.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '');
    final suffix = cleanId.length >= 4 ? cleanId.substring(0, 4).toUpperCase() : 'SOVR';
    return 'NX-$suffix';
  }

  /// Retorna apenas os itens visíveis no Card ID conforme configuração de privacidade
  List<CulturalItem> get publicCulturalItems =>
      culturalItems.where((item) => item.isPublicInCardId).toList();

  /// Payload público seguro para QR Code (NUNCA inclui chaves privadas, seeds ou tokens).
  String get qrPublicPayload =>
      'nix://id/$publicId?name=${Uri.encodeComponent(effectiveDisplayName)}&v=2';

  UserProfile copyWith({
    String? publicId,
    String? displayName,
    String? bio,
    String? currentActivity,
    String? memberSinceYear,
    String? avatarStyle,
    String? customAvatarPath,
    bool clearCustomAvatar = false,
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
      culturalItems: culturalItems ?? this.culturalItems,
    );
  }
}
