enum MemberRole { admin, operator, sentinel, member }

enum NixTrustLevel {
  level1Red,    // Nível 1: Não verificado diretamente / contato externo
  level2Yellow, // Nível 2: Conhecido por contexto de espaço privado compartilhado
  level3Green,  // Nível 3: Verificado diretamente (troca de chaves QR / fingerprint)
}

class Member {
  final String id;
  final String name;
  final String roleName;
  final MemberRole role;
  final bool isVerified;
  final String fingerprint;
  final bool isOnline;
  final bool isSpeaking;
  final NixTrustLevel trustLevel;
  final bool hasCryptographicShield;

  const Member({
    required this.id,
    required this.name,
    required this.roleName,
    required this.role,
    this.isVerified = true,
    required this.fingerprint,
    this.isOnline = true,
    this.isSpeaking = false,
    this.trustLevel = NixTrustLevel.level3Green,
    this.hasCryptographicShield = true,
  });

  Member copyWith({
    String? id,
    String? name,
    String? roleName,
    MemberRole? role,
    bool? isVerified,
    String? fingerprint,
    bool? isOnline,
    bool? isSpeaking,
    NixTrustLevel? trustLevel,
    bool? hasCryptographicShield,
  }) {
    return Member(
      id: id ?? this.id,
      name: name ?? this.name,
      roleName: roleName ?? this.roleName,
      role: role ?? this.role,
      isVerified: isVerified ?? this.isVerified,
      fingerprint: fingerprint ?? this.fingerprint,
      isOnline: isOnline ?? this.isOnline,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      trustLevel: trustLevel ?? this.trustLevel,
      hasCryptographicShield: hasCryptographicShield ?? this.hasCryptographicShield,
    );
  }
}
