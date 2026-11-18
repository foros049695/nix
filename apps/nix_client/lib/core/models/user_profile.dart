import 'cultural_item.dart';

class UserProfile {
  final String publicId;
  final String displayName;
  final String bio;
  final String currentActivity;
  final String memberSinceYear;
  final String avatarStyle; // 'nyx_emblem', 'monogram', 'custom_1', 'custom_2', 'none'
  final String? customAvatarPath;
  final List<CulturalItem> culturalItems;

  const UserProfile({
    required this.publicId,
    required this.displayName,
    required this.bio,
    required this.currentActivity,
    required this.memberSinceYear,
    this.avatarStyle = 'nyx_emblem',
    this.customAvatarPath,
    required this.culturalItems,
  });

  /// Payload público seguro para QR Code (NUNCA inclui chaves privadas, seeds ou tokens).
  String get qrPublicPayload => 'nix://id/$publicId?name=${Uri.encodeComponent(displayName)}&v=1';

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
