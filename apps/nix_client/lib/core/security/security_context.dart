class SecurityContext {
  final bool isTorConnected;
  final String onionNode;
  final bool isFailClosedEnabled;
  final bool isSqlCipherUnlocked;
  final String myFingerprint;
  final String myPersona;
  final int activePeersCount;

  const SecurityContext({
    this.isTorConnected = true,
    this.onionNode = "gpoun4vo5v5h3cmcfdxtudm3nlzxri3qzjd7fhbvy6oep2ap67g4qvyd.onion",
    this.isFailClosedEnabled = true,
    this.isSqlCipherUnlocked = true,
    this.myFingerprint = "7E3A-9F01-C45B-289D",
    this.myPersona = "Operador-01",
    this.activePeersCount = 14,
  });
}
