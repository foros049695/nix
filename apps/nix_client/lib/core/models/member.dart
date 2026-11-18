enum MemberRole { admin, operator, sentinel, member }

class Member {
  final String id;
  final String name;
  final String roleName;
  final MemberRole role;
  final bool isVerified;
  final String fingerprint;
  final bool isOnline;
  final bool isSpeaking;

  const Member({
    required this.id,
    required this.name,
    required this.roleName,
    required this.role,
    this.isVerified = true,
    required this.fingerprint,
    this.isOnline = true,
    this.isSpeaking = false,
  });
}
