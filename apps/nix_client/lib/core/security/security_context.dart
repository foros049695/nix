/// Estado formal dos subsistemas de segurança e integridade do Nix.
enum SecuritySubsystemState {
  unknown,
  initializing,
  locked,
  connecting,
  ready,
  failed,
}

/// Contexto de segurança dinâmico derivado dos serviços reais.
/// Não utiliza flags estáticas pré-validadas (P0-0 / APP02).
class SecurityContext {
  final SecuritySubsystemState status;
  final bool isTorConnected;
  final String onionNode;
  final bool isFailClosedEnabled;
  final bool isSqlCipherUnlocked;
  final String myFingerprint;
  final String myPersona;
  final int activePeersCount;

  const SecurityContext({
    this.status = SecuritySubsystemState.unknown,
    this.isTorConnected = false,
    this.onionNode = '',
    this.isFailClosedEnabled = true,
    this.isSqlCipherUnlocked = false,
    this.myFingerprint = 'NX-UNVERIFIED',
    this.myPersona = 'Operador Local',
    this.activePeersCount = 0,
  });

  SecurityContext copyWith({
    SecuritySubsystemState? status,
    bool? isTorConnected,
    String? onionNode,
    bool? isFailClosedEnabled,
    bool? isSqlCipherUnlocked,
    String? myFingerprint,
    String? myPersona,
    int? activePeersCount,
  }) {
    return SecurityContext(
      status: status ?? this.status,
      isTorConnected: isTorConnected ?? this.isTorConnected,
      onionNode: onionNode ?? this.onionNode,
      isFailClosedEnabled: isFailClosedEnabled ?? this.isFailClosedEnabled,
      isSqlCipherUnlocked: isSqlCipherUnlocked ?? this.isSqlCipherUnlocked,
      myFingerprint: myFingerprint ?? this.myFingerprint,
      myPersona: myPersona ?? this.myPersona,
      activePeersCount: activePeersCount ?? this.activePeersCount,
    );
  }
}
