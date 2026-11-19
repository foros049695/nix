/// Relatório imutável e auditável dos pré-requisitos obrigatórios de anonimato
/// e criptografia exigidos pelo Gate Fail-Closed antes de liberar o acesso ao app.
class SovereignSecurityGateStatus {
  final bool clearnetFirewallActive;
  final bool torSocksActive;
  final bool torBootstrapped100;
  final bool torOnionV3Ready;
  final bool failClosedPolicyVerified;
  final bool isStrictOffGridMode;
  final bool sqlCipherEncrypted;
  final bool keyVaultUnlocked;
  final bool identityKeysLoaded;
  final int torBootstrapPercent;
  final String torStatusMessage;
  final String? liveOnionV3Address;
  final String? torVersion;
  final String? torBinaryPath;
  final String? sqlCipherVersion;
  final String osKeyringBackend;
  final String? blockingReason;
  final bool isBootstrapping;

  const SovereignSecurityGateStatus({
    this.clearnetFirewallActive = false,
    this.torSocksActive = false,
    this.torBootstrapped100 = false,
    this.torOnionV3Ready = false,
    this.failClosedPolicyVerified = false,
    this.isStrictOffGridMode = false,
    this.sqlCipherEncrypted = false,
    this.keyVaultUnlocked = false,
    this.identityKeysLoaded = false,
    this.torBootstrapPercent = 0,
    this.torStatusMessage = 'Inicializando proteção Tor Onion v3...',
    this.liveOnionV3Address,
    this.torVersion,
    this.torBinaryPath,
    this.sqlCipherVersion,
    this.osKeyringBackend = 'Verificando...',
    this.blockingReason,
    this.isBootstrapping = false,
  });

  /// Transporte anônimo Tor Onion v3 + firewall anti-vazamento 100% confirmados.
  bool get isTorAnonymityReady =>
      clearnetFirewallActive &&
      torSocksActive &&
      torBootstrapped100 &&
      torOnionV3Ready &&
      failClosedPolicyVerified;

  /// Modo Off-Grid Estrito (Bluetooth BLE / Rádio LoRa):
  /// Zero acesso a Wi-Fi/Internet (firewall anti-clearnet obrigatório ativo),
  /// liberando exclusivamente rádios locais BLE/LoRa e cofre SQLCipher.
  bool get isOffGridBoundaryReady =>
      isStrictOffGridMode &&
      clearnetFirewallActive &&
      failClosedPolicyVerified;

  /// Fronteira de transporte segura (Tor Onion v3 operacional OU Off-Grid Estrito sem rede IP).
  bool get isTransportGateSatisfied =>
      isTorAnonymityReady || isOffGridBoundaryReady;

  /// Cofre SQLCipher + KeyVault + Identidade Seed A (Ed25519/X25519) ativos e verificados.
  bool get isCryptographyReady =>
      sqlCipherEncrypted && keyVaultUnlocked && identityKeysLoaded;

  /// Libera a entrada no aplicativo SOMENTE quando a fronteira de transporte
  /// (Tor Onion v3 ou Off-Grid Estrito) E toda a criptografia estão verificadas.
  bool get canEnterApplication =>
      isTransportGateSatisfied && isCryptographyReady;

  /// Retorna uma lista objetiva dos requisitos pendentes quando bloqueado.
  List<String> get missingRequirements {
    final missing = <String>[];
    if (!clearnetFirewallActive) {
      missing.add('Firewall HTTP Fail-Closed contra rede doméstica inativo');
    }
    if (!failClosedPolicyVerified) {
      missing.add('Política fail-closed de bloqueio clearnet não verificada');
    }
    if (!isStrictOffGridMode) {
      if (!torSocksActive) {
        missing.add('Proxy SOCKS5 Tor local não respondeu ao handshake RFC 1928');
      }
      if (!torBootstrapped100) {
        missing.add('Bootstrap do circuito Tor Onion v3 ainda não atingiu 100%');
      }
      if (!torOnionV3Ready) {
        missing.add('Serviço/circuito Onion v3 (56 caracteres .onion) não confirmado');
      }
    }
    if (!keyVaultUnlocked) {
      missing.add('KeyVault (Argon2id + XChaCha20-Poly1305) bloqueado');
    }
    if (!sqlCipherEncrypted) {
      missing.add('Banco local SQLCipher não cifrado ou indisponível');
    }
    if (!identityKeysLoaded) {
      missing.add('Identidade soberana Seed A (Ed25519/X25519) não carregada');
    }
    return missing;
  }
}
