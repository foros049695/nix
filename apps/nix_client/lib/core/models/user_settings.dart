enum SettingsCategory {
  notifications, // 5.1 Notificações e sons
  privacy,       // 5.2 Privacidade e segurança
  chats,         // 5.3 Configurações dos chats
  audio,         // 5.4 Som e microfone
  connections,   // 5.5 Conexões e integrações
  survival,      // 5.6 Sobrevivência e privacidade
}

class IntegrationConnector {
  final String id;
  final String name;
  final String description;
  final String scopeLabel;
  final bool isEnabled;
  final bool routesViaTor;

  const IntegrationConnector({
    required this.id,
    required this.name,
    required this.description,
    required this.scopeLabel,
    required this.isEnabled,
    this.routesViaTor = true,
  });

  IntegrationConnector copyWith({bool? isEnabled, bool? routesViaTor}) {
    return IntegrationConnector(
      id: id,
      name: name,
      description: description,
      scopeLabel: scopeLabel,
      isEnabled: isEnabled ?? this.isEnabled,
      routesViaTor: routesViaTor ?? this.routesViaTor,
    );
  }
}

class UserSettings {
  // 5.1 Notificações e sons
  final bool messageNotifications;
  final bool callNotifications;
  final bool systemAlerts;
  final bool notificationSounds;
  final double alertVolume;
  final bool silentMode;
  final bool showMessagePreview; // Oculto por padrão por privacidade
  final bool desktopNotifications;

  // 5.2 Privacidade e segurança
  final String profileVisibility; // 'Apenas Contatos Verificados', 'Público via QR', 'Oculto'
  final bool allowPublicIdSharing;
  final String communicationPermission; // 'Somente Pares Verificados', 'Qualquer ID c/ PoW'
  final List<String> blockedUserIds;
  final int autoLockMinutes; // 1, 5, 15, 30, 0
  final bool stripExifMetadata;
  final int defaultRetentionDays; // 7 dias base
  final bool allowMediaAttachments;

  // 5.3 Configurações dos chats
  final bool compactChatMode;
  final double fontScale; // 0.9, 1.0, 1.1, 1.2
  final bool enterToSend;
  final bool autoDownloadMedia;
  final bool autoPlayMedia;
  final bool sendReadReceipts;

  // 5.4 Som e microfone
  final String inputDevice;
  final String outputDevice;
  final double inputVolume;
  final double outputVolume;
  final bool noiseSuppression;
  final bool echoCancellation;
  final bool micPermissionGranted;

  // 5.5 Conexões e integrações
  final String transportProfile; // 'Tor Onion v3 (Fail-Closed)', 'Rede Local LAN/BLE', 'Off-Grid LoRa'
  final bool hideSensitiveNetworkInfo;
  final bool autoReconnect;
  final List<IntegrationConnector> connectors;

  // 5.6 Sobrevivência e privacidade & Anti-Fingerprinting (Seção 7)
  final bool persistWindowGeometry;
  final bool quantizeViewportDimensions; // Discretiza dimensões reportadas (ex: 1152x720)
  final bool blockRemoteEmbeds;
  final bool reducedMotion;
  final bool duressPinConfigured;
  final bool atakBridgeEnabled; // 127.0.0.1:4242/UDP sob consentimento

  const UserSettings({
    this.messageNotifications = true,
    this.callNotifications = true,
    this.systemAlerts = true,
    this.notificationSounds = true,
    this.alertVolume = 0.75,
    this.silentMode = false,
    this.showMessagePreview = false,
    this.desktopNotifications = true,
    this.profileVisibility = 'Apenas Contatos Verificados',
    this.allowPublicIdSharing = true,
    this.communicationPermission = 'Somente Pares Verificados',
    this.blockedUserIds = const ['NIX-9900-SPAM-BOT1'],
    this.autoLockMinutes = 5,
    this.stripExifMetadata = true,
    this.defaultRetentionDays = 7,
    this.allowMediaAttachments = true,
    this.compactChatMode = false,
    this.fontScale = 1.0,
    this.enterToSend = true,
    this.autoDownloadMedia = false,
    this.autoPlayMedia = false,
    this.sendReadReceipts = false,
    this.inputDevice = 'Microfone Padrão ALSA/PipeWire (Isolado)',
    this.outputDevice = 'Saída Estéreo Digital (PipeWire)',
    this.inputVolume = 0.85,
    this.outputVolume = 0.80,
    this.noiseSuppression = true,
    this.echoCancellation = true,
    this.micPermissionGranted = true,
    this.transportProfile = 'Tor Onion v3 (Fail-Closed)',
    this.hideSensitiveNetworkInfo = true,
    this.autoReconnect = true,
    this.connectors = const [
      IntegrationConnector(
        id: 'conn_xmr',
        name: 'Nó Monero Remoto (.onion)',
        description: 'Sincronização de subendereços e transmissão de transações XMR via SOCKS5.',
        scopeLabel: 'Processo Seed B Isolado',
        isEnabled: true,
        routesViaTor: true,
      ),
      IntegrationConnector(
        id: 'conn_tmdb',
        name: 'Catálogo Cultural (TMDB / AniList Proxy)',
        description: 'Busca de metadados de capas para o Passaporte Cultural sem cookies.',
        scopeLabel: 'Sandbox Somente-Leitura',
        isEnabled: true,
        routesViaTor: true,
      ),
      IntegrationConnector(
        id: 'conn_jellyfin',
        name: 'Servidor Pessoal Jellyfin',
        description: 'Biblioteca de mídia auto-hospedada pelo usuário.',
        scopeLabel: 'Desativado por padrão',
        isEnabled: false,
        routesViaTor: true,
      ),
    ],
    this.persistWindowGeometry = false,
    this.quantizeViewportDimensions = true,
    this.blockRemoteEmbeds = true,
    this.reducedMotion = false,
    this.duressPinConfigured = true,
    this.atakBridgeEnabled = false,
  });

  UserSettings copyWith({
    bool? messageNotifications,
    bool? callNotifications,
    bool? systemAlerts,
    bool? notificationSounds,
    double? alertVolume,
    bool? silentMode,
    bool? showMessagePreview,
    bool? desktopNotifications,
    String? profileVisibility,
    bool? allowPublicIdSharing,
    String? communicationPermission,
    List<String>? blockedUserIds,
    int? autoLockMinutes,
    bool? stripExifMetadata,
    int? defaultRetentionDays,
    bool? allowMediaAttachments,
    bool? compactChatMode,
    double? fontScale,
    bool? enterToSend,
    bool? autoDownloadMedia,
    bool? autoPlayMedia,
    bool? sendReadReceipts,
    String? inputDevice,
    String? outputDevice,
    double? inputVolume,
    double? outputVolume,
    bool? noiseSuppression,
    bool? echoCancellation,
    bool? micPermissionGranted,
    String? transportProfile,
    bool? hideSensitiveNetworkInfo,
    bool? autoReconnect,
    List<IntegrationConnector>? connectors,
    bool? persistWindowGeometry,
    bool? quantizeViewportDimensions,
    bool? blockRemoteEmbeds,
    bool? reducedMotion,
    bool? duressPinConfigured,
    bool? atakBridgeEnabled,
  }) {
    return UserSettings(
      messageNotifications: messageNotifications ?? this.messageNotifications,
      callNotifications: callNotifications ?? this.callNotifications,
      systemAlerts: systemAlerts ?? this.systemAlerts,
      notificationSounds: notificationSounds ?? this.notificationSounds,
      alertVolume: alertVolume ?? this.alertVolume,
      silentMode: silentMode ?? this.silentMode,
      showMessagePreview: showMessagePreview ?? this.showMessagePreview,
      desktopNotifications: desktopNotifications ?? this.desktopNotifications,
      profileVisibility: profileVisibility ?? this.profileVisibility,
      allowPublicIdSharing: allowPublicIdSharing ?? this.allowPublicIdSharing,
      communicationPermission: communicationPermission ?? this.communicationPermission,
      blockedUserIds: blockedUserIds ?? this.blockedUserIds,
      autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
      stripExifMetadata: stripExifMetadata ?? this.stripExifMetadata,
      defaultRetentionDays: defaultRetentionDays ?? this.defaultRetentionDays,
      allowMediaAttachments: allowMediaAttachments ?? this.allowMediaAttachments,
      compactChatMode: compactChatMode ?? this.compactChatMode,
      fontScale: fontScale ?? this.fontScale,
      enterToSend: enterToSend ?? this.enterToSend,
      autoDownloadMedia: autoDownloadMedia ?? this.autoDownloadMedia,
      autoPlayMedia: autoPlayMedia ?? this.autoPlayMedia,
      sendReadReceipts: sendReadReceipts ?? this.sendReadReceipts,
      inputDevice: inputDevice ?? this.inputDevice,
      outputDevice: outputDevice ?? this.outputDevice,
      inputVolume: inputVolume ?? this.inputVolume,
      outputVolume: outputVolume ?? this.outputVolume,
      noiseSuppression: noiseSuppression ?? this.noiseSuppression,
      echoCancellation: echoCancellation ?? this.echoCancellation,
      micPermissionGranted: micPermissionGranted ?? this.micPermissionGranted,
      transportProfile: transportProfile ?? this.transportProfile,
      hideSensitiveNetworkInfo: hideSensitiveNetworkInfo ?? this.hideSensitiveNetworkInfo,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      connectors: connectors ?? this.connectors,
      persistWindowGeometry: persistWindowGeometry ?? this.persistWindowGeometry,
      quantizeViewportDimensions: quantizeViewportDimensions ?? this.quantizeViewportDimensions,
      blockRemoteEmbeds: blockRemoteEmbeds ?? this.blockRemoteEmbeds,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      duressPinConfigured: duressPinConfigured ?? this.duressPinConfigured,
      atakBridgeEnabled: atakBridgeEnabled ?? this.atakBridgeEnabled,
    );
  }
}
