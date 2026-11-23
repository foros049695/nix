import '../theme/nix_palette.dart';
import 'pager_appearance.dart';
import 'interface_wallpaper.dart';

enum SettingsCategory {
  appearance,    // 5.0 Aparência: Paleta de Cores Living AMOLED
  notifications, // 5.1 Notificações e sons
  privacy,       // 5.2 Privacidade e segurança & Card ID Visibility
  chats,         // 5.3 Configurações dos chats
  audio,         // 5.4 Som e microfone
  connections,   // 5.5 Conexões e integrações (Tor Onion v3)
  devices,       // 5.6 Dispositivos e Compartimentalização
  survival,      // 5.7 Sobrevivência e Anti-Fingerprinting
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

class AuthorizedDevice {
  final String id;
  final String deviceName;
  final String clientVersion;
  final String lastSeenLabel;
  final bool isCurrent;
  final String fingerprint;

  const AuthorizedDevice({
    required this.id,
    required this.deviceName,
    required this.clientVersion,
    required this.lastSeenLabel,
    required this.isCurrent,
    required this.fingerprint,
  });
}

class UserSettings {
  // 5.0 Aparência — Dark Yellow, Light Yellow, AMOLED e Paleta
  final NixThemeMode themeMode;
  final NixPaletteType paletteType;
  final int? customPaletteColor;
  final bool floatingWindowMode;
  final double windowWidth;
  final double windowHeight;
  final double? windowOffsetX;
  final double? windowOffsetY;
  final double dockWidth;
  final double sidebarWidth;
  final InterfaceWallpaper interfaceWallpaper;

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
  final String cardIdVisibility;  // 'Público', 'Apenas Contatos Verificados', 'Oculto'
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
  final bool microphoneMuted;

  // 5.5 Conexões e integrações
  final String transportProfile; // 'Tor Onion v3 (Fail-Closed)', 'Rede Local LAN/BLE', 'Off-Grid LoRa'
  final bool hideSensitiveNetworkInfo;
  final bool autoReconnect;
  final List<IntegrationConnector> connectors;

  // 5.6 Dispositivos e Compartimentalização
  final List<AuthorizedDevice> devices;

  // 5.7 Sobrevivência e privacidade & Anti-Fingerprinting
  final bool persistWindowGeometry;
  final bool quantizeViewportDimensions;
  final bool blockRemoteEmbeds;
  final bool reducedMotion;
  final bool hidePagerAvatar;
  final bool roundedSquareAvatar;
  final String avatarFrameStyle;
  final String avatarFrameShape; // 'circle' ou 'square' (Seção 11)
  final String avatarFrameEffect; // 'none', 'glow', 'neon', 'softGlow', 'doubleBorder', 'pixelArt', 'subtle'
  final double avatarCornerRadius; // Cantos arredondados do quadrado
  final double avatarBorderWidth;
  final String avatarFrameColorHex;
  final double pagerWallpaperShade;
  final double pagerWallpaperBlur;
  final bool pagerWallpaperAcrossPages;
  final double pagerAvatarX;
  final double pagerAvatarY;
  final double pagerAvatarScale;
  final PagerCaseColor pagerCaseColor;
  final PagerLcdColor pagerLcdColor;
  final bool duressPinConfigured;
  final bool atakBridgeEnabled;

  const UserSettings({
    this.themeMode = NixThemeMode.darkYellow,
    this.paletteType = NixPaletteType.violet,
    this.customPaletteColor,
    this.floatingWindowMode = true,
    this.windowWidth = 1152.0,
    this.windowHeight = 720.0,
    this.windowOffsetX,
    this.windowOffsetY,
    this.dockWidth = 78.0,
    this.sidebarWidth = 288.0,
    this.interfaceWallpaper = const InterfaceWallpaper(),
    this.messageNotifications = true,
    this.callNotifications = true,
    this.systemAlerts = true,
    this.notificationSounds = true,
    this.alertVolume = 0.75,
    this.silentMode = false,
    this.showMessagePreview = false,
    this.desktopNotifications = true,
    this.profileVisibility = 'Apenas Contatos Verificados',
    this.cardIdVisibility = 'Apenas Contatos Verificados',
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
    this.microphoneMuted = false,
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
    this.devices = const [
      AuthorizedDevice(
        id: 'dev_current',
        deviceName: 'Linux Desktop (Esta Sessão)',
        clientVersion: 'Nix Client v0.4.0-dev',
        lastSeenLabel: 'Sessão Ativa',
        isCurrent: true,
        fingerprint: 'ED25-992A-44B1-02E3',
      ),
      AuthorizedDevice(
        id: 'dev_mobile',
        deviceName: 'Android Mobile (Tor TransProxy)',
        clientVersion: 'Nix Mobile v0.4.0-dev',
        lastSeenLabel: 'Última sincronização local',
        isCurrent: false,
        fingerprint: '77F1-30A8-C129-B582',
      ),
    ],
    this.persistWindowGeometry = false,
    this.quantizeViewportDimensions = false,
    this.blockRemoteEmbeds = true,
    this.reducedMotion = false,
    this.hidePagerAvatar = false,
    this.roundedSquareAvatar = false,
    this.avatarFrameStyle = 'circle',
    this.avatarFrameShape = 'circle',
    this.avatarFrameEffect = 'none',
    this.avatarCornerRadius = 8.0,
    this.avatarBorderWidth = 1.5,
    this.avatarFrameColorHex = '',
    this.pagerWallpaperShade = 0,
    this.pagerWallpaperBlur = 0,
    this.pagerWallpaperAcrossPages = false,
    this.pagerAvatarX = 0,
    this.pagerAvatarY = 0,
    this.pagerAvatarScale = .28,
    this.pagerCaseColor = PagerCaseColor.violet,
    this.pagerLcdColor = PagerLcdColor.cyan,
    this.duressPinConfigured = true,
    this.atakBridgeEnabled = false,
  });

  UserSettings copyWith({
    NixThemeMode? themeMode,
    NixPaletteType? paletteType,
    int? customPaletteColor,
    bool? floatingWindowMode,
    double? windowWidth,
    double? windowHeight,
    double? windowOffsetX,
    double? windowOffsetY,
    double? dockWidth,
    double? sidebarWidth,
    InterfaceWallpaper? interfaceWallpaper,
    bool? messageNotifications,
    bool? callNotifications,
    bool? systemAlerts,
    bool? notificationSounds,
    double? alertVolume,
    bool? silentMode,
    bool? showMessagePreview,
    bool? desktopNotifications,
    String? profileVisibility,
    String? cardIdVisibility,
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
    bool? microphoneMuted,
    String? transportProfile,
    bool? hideSensitiveNetworkInfo,
    bool? autoReconnect,
    List<IntegrationConnector>? connectors,
    List<AuthorizedDevice>? devices,
    bool? persistWindowGeometry,
    bool? quantizeViewportDimensions,
    bool? blockRemoteEmbeds,
    bool? reducedMotion,
    bool? hidePagerAvatar,
    bool? roundedSquareAvatar,
    String? avatarFrameStyle,
    String? avatarFrameShape,
    String? avatarFrameEffect,
    double? avatarCornerRadius,
    double? avatarBorderWidth,
    String? avatarFrameColorHex,
    double? pagerWallpaperShade,
    double? pagerWallpaperBlur,
    bool? pagerWallpaperAcrossPages,
    double? pagerAvatarX,
    double? pagerAvatarY,
    double? pagerAvatarScale,
    PagerCaseColor? pagerCaseColor,
    PagerLcdColor? pagerLcdColor,
    bool? duressPinConfigured,
    bool? atakBridgeEnabled,
  }) {
    return UserSettings(
      themeMode: themeMode ?? this.themeMode,
      paletteType: paletteType ?? this.paletteType,
      customPaletteColor: customPaletteColor ?? this.customPaletteColor,
      floatingWindowMode: floatingWindowMode ?? this.floatingWindowMode,
      windowWidth: windowWidth ?? this.windowWidth,
      windowHeight: windowHeight ?? this.windowHeight,
      windowOffsetX: windowOffsetX ?? this.windowOffsetX,
      windowOffsetY: windowOffsetY ?? this.windowOffsetY,
      dockWidth: dockWidth ?? this.dockWidth,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      interfaceWallpaper: interfaceWallpaper ?? this.interfaceWallpaper,
      messageNotifications: messageNotifications ?? this.messageNotifications,
      callNotifications: callNotifications ?? this.callNotifications,
      systemAlerts: systemAlerts ?? this.systemAlerts,
      notificationSounds: notificationSounds ?? this.notificationSounds,
      alertVolume: alertVolume ?? this.alertVolume,
      silentMode: silentMode ?? this.silentMode,
      showMessagePreview: showMessagePreview ?? this.showMessagePreview,
      desktopNotifications: desktopNotifications ?? this.desktopNotifications,
      profileVisibility: profileVisibility ?? this.profileVisibility,
      cardIdVisibility: cardIdVisibility ?? this.cardIdVisibility,
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
      microphoneMuted: microphoneMuted ?? this.microphoneMuted,
      transportProfile: transportProfile ?? this.transportProfile,
      hideSensitiveNetworkInfo: hideSensitiveNetworkInfo ?? this.hideSensitiveNetworkInfo,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      connectors: connectors ?? this.connectors,
      devices: devices ?? this.devices,
      persistWindowGeometry: persistWindowGeometry ?? this.persistWindowGeometry,
      quantizeViewportDimensions: quantizeViewportDimensions ?? this.quantizeViewportDimensions,
      blockRemoteEmbeds: blockRemoteEmbeds ?? this.blockRemoteEmbeds,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      hidePagerAvatar: hidePagerAvatar ?? this.hidePagerAvatar,
      roundedSquareAvatar: roundedSquareAvatar ?? this.roundedSquareAvatar,
      avatarFrameStyle: avatarFrameStyle ?? this.avatarFrameStyle,
      avatarFrameShape: avatarFrameShape ?? this.avatarFrameShape,
      avatarFrameEffect: avatarFrameEffect ?? this.avatarFrameEffect,
      avatarCornerRadius: avatarCornerRadius ?? this.avatarCornerRadius,
      avatarBorderWidth: avatarBorderWidth ?? this.avatarBorderWidth,
      avatarFrameColorHex: avatarFrameColorHex ?? this.avatarFrameColorHex,
      pagerWallpaperShade: pagerWallpaperShade ?? this.pagerWallpaperShade,
      pagerWallpaperBlur: pagerWallpaperBlur ?? this.pagerWallpaperBlur,
      pagerWallpaperAcrossPages: pagerWallpaperAcrossPages ?? this.pagerWallpaperAcrossPages,
      pagerAvatarX: pagerAvatarX ?? this.pagerAvatarX,
      pagerAvatarY: pagerAvatarY ?? this.pagerAvatarY,
      pagerAvatarScale: pagerAvatarScale ?? this.pagerAvatarScale,
      pagerCaseColor: pagerCaseColor ?? this.pagerCaseColor,
      pagerLcdColor: pagerLcdColor ?? this.pagerLcdColor,
      duressPinConfigured: duressPinConfigured ?? this.duressPinConfigured,
      atakBridgeEnabled: atakBridgeEnabled ?? this.atakBridgeEnabled,
    );
  }

  Map<String, dynamic> toBootstrapJson() => {
        'themeMode': themeMode.name,
        'paletteType': paletteType.name,
        'customPaletteColor': customPaletteColor,
        'floatingWindowMode': floatingWindowMode,
        'windowWidth': windowWidth,
        'windowHeight': windowHeight,
        'windowOffsetX': windowOffsetX,
        'windowOffsetY': windowOffsetY,
        'dockWidth': dockWidth,
        'sidebarWidth': sidebarWidth,
        'cardIdVisibility': cardIdVisibility,
        'allowPublicIdSharing': allowPublicIdSharing,
        'compactChatMode': compactChatMode,
        'fontScale': fontScale,
        'enterToSend': enterToSend,
        'persistWindowGeometry': persistWindowGeometry,
        'quantizeViewportDimensions': quantizeViewportDimensions,
        'reducedMotion': reducedMotion,
        'hidePagerAvatar': hidePagerAvatar,
        'roundedSquareAvatar': roundedSquareAvatar,
        'avatarFrameStyle': avatarFrameStyle,
        'avatarFrameShape': avatarFrameShape,
        'avatarFrameEffect': avatarFrameEffect,
        'avatarCornerRadius': avatarCornerRadius,
        'avatarBorderWidth': avatarBorderWidth,
        'avatarFrameColorHex': avatarFrameColorHex,
        'pagerWallpaperShade': pagerWallpaperShade,
        'interfaceWallpaper': interfaceWallpaper.toJson(),
        'pagerWallpaperBlur': pagerWallpaperBlur,
        'pagerWallpaperAcrossPages': pagerWallpaperAcrossPages,
        'pagerAvatarX': pagerAvatarX,
        'pagerAvatarY': pagerAvatarY,
        'pagerAvatarScale': pagerAvatarScale,
        'pagerCaseColor': pagerCaseColor.name,
        'pagerLcdColor': pagerLcdColor.name,
        'transportProfile': transportProfile,
      };

  Map<String, dynamic> toJson() => {
        ...toBootstrapJson(),
        'messageNotifications': messageNotifications,
        'callNotifications': callNotifications,
        'systemAlerts': systemAlerts,
        'notificationSounds': notificationSounds,
        'silentMode': silentMode,
        'showMessagePreview': showMessagePreview,
        'desktopNotifications': desktopNotifications,
        'stripExifMetadata': stripExifMetadata,
        'allowMediaAttachments': allowMediaAttachments,
        'autoDownloadMedia': autoDownloadMedia,
        'autoPlayMedia': autoPlayMedia,
        'sendReadReceipts': sendReadReceipts,
        'noiseSuppression': noiseSuppression,
        'echoCancellation': echoCancellation,
        'micPermissionGranted': micPermissionGranted,
        'microphoneMuted': microphoneMuted,
        'hideSensitiveNetworkInfo': hideSensitiveNetworkInfo,
        'autoReconnect': autoReconnect,
        'blockRemoteEmbeds': blockRemoteEmbeds,
        'duressPinConfigured': duressPinConfigured,
        'atakBridgeEnabled': atakBridgeEnabled,
        'profileVisibility': profileVisibility,
        'communicationPermission': communicationPermission,
        'inputDevice': inputDevice,
        'outputDevice': outputDevice,
        'autoLockMinutes': autoLockMinutes,
        'defaultRetentionDays': defaultRetentionDays,
        'alertVolume': alertVolume,
        'inputVolume': inputVolume,
        'outputVolume': outputVolume,
        'blockedUserIds': blockedUserIds,
        'connectors': {for (final c in connectors) c.id: c.isEnabled},
        'devices': [
          for (final d in devices)
            {
              'id': d.id,
              'deviceName': d.deviceName,
              'clientVersion': d.clientVersion,
              'lastSeenLabel': d.lastSeenLabel,
              'isCurrent': d.isCurrent,
              'fingerprint': d.fingerprint,
            },
        ],
      };

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    double readAvatarValue(Object? raw, double fallback, double min, double max) =>
        raw is num && raw.isFinite ? raw.toDouble().clamp(min, max) : fallback;

    NixThemeMode parsedMode = NixThemeMode.darkYellow;
    if (json['themeMode'] is String) {
      for (final m in NixThemeMode.values) {
        if (m.name == json['themeMode']) {
          parsedMode = m;
          break;
        }
      }
    }
    NixPaletteType parsedPalette = NixPaletteType.violet;
    if (json['paletteType'] is String) {
      for (final p in NixPaletteType.values) {
        if (p.name == json['paletteType']) {
          parsedPalette = p;
          break;
        }
      }
    }
    const defaults = UserSettings();
    T read<T>(String key, T fallback) => json[key] is T ? json[key] as T : fallback;
    final connectorFlags = read('connectors', const <String, dynamic>{});
    final deviceRecords = json['devices'];
    return UserSettings(
      messageNotifications: read('messageNotifications', defaults.messageNotifications),
      callNotifications: read('callNotifications', defaults.callNotifications),
      systemAlerts: read('systemAlerts', defaults.systemAlerts),
      notificationSounds: read('notificationSounds', defaults.notificationSounds),
      silentMode: read('silentMode', defaults.silentMode),
      showMessagePreview: read('showMessagePreview', defaults.showMessagePreview),
      desktopNotifications: read('desktopNotifications', defaults.desktopNotifications),
      stripExifMetadata: read('stripExifMetadata', defaults.stripExifMetadata),
      allowMediaAttachments: read('allowMediaAttachments', defaults.allowMediaAttachments),
      autoDownloadMedia: read('autoDownloadMedia', defaults.autoDownloadMedia),
      autoPlayMedia: read('autoPlayMedia', defaults.autoPlayMedia),
      sendReadReceipts: read('sendReadReceipts', defaults.sendReadReceipts),
      noiseSuppression: read('noiseSuppression', defaults.noiseSuppression),
      echoCancellation: read('echoCancellation', defaults.echoCancellation),
      micPermissionGranted: read('micPermissionGranted', defaults.micPermissionGranted),
      microphoneMuted: read('microphoneMuted', defaults.microphoneMuted),
      hideSensitiveNetworkInfo: read('hideSensitiveNetworkInfo', defaults.hideSensitiveNetworkInfo),
      autoReconnect: read('autoReconnect', defaults.autoReconnect),
      blockRemoteEmbeds: read('blockRemoteEmbeds', defaults.blockRemoteEmbeds),
      duressPinConfigured: read('duressPinConfigured', defaults.duressPinConfigured),
      atakBridgeEnabled: read('atakBridgeEnabled', defaults.atakBridgeEnabled),
      profileVisibility: read('profileVisibility', defaults.profileVisibility),
      communicationPermission: read('communicationPermission', defaults.communicationPermission),
      inputDevice: read('inputDevice', defaults.inputDevice),
      outputDevice: read('outputDevice', defaults.outputDevice),
      autoLockMinutes: read('autoLockMinutes', defaults.autoLockMinutes),
      defaultRetentionDays: read('defaultRetentionDays', defaults.defaultRetentionDays),
      alertVolume: readAvatarValue(json['alertVolume'], defaults.alertVolume, 0, 1),
      inputVolume: readAvatarValue(json['inputVolume'], defaults.inputVolume, 0, 1),
      outputVolume: readAvatarValue(json['outputVolume'], defaults.outputVolume, 0, 1),
      blockedUserIds: read('blockedUserIds', defaults.blockedUserIds.cast<dynamic>()).whereType<String>().toList(),
      connectors: [
        for (final connector in defaults.connectors)
          connector.copyWith(isEnabled: connectorFlags[connector.id] is bool
              ? connectorFlags[connector.id] as bool : connector.isEnabled),
      ],
      devices: deviceRecords is List
          ? [
              for (final raw in deviceRecords.whereType<Map<String, dynamic>>())
                if (raw['id'] is String && raw['deviceName'] is String)
                  AuthorizedDevice(
                    id: raw['id'] as String,
                    deviceName: raw['deviceName'] as String,
                    clientVersion: raw['clientVersion'] as String? ?? '',
                    lastSeenLabel: raw['lastSeenLabel'] as String? ?? '',
                    isCurrent: raw['isCurrent'] == true,
                    fingerprint: raw['fingerprint'] as String? ?? '',
                  ),
            ]
          : defaults.devices,
      themeMode: parsedMode,
      paletteType: parsedPalette,
      customPaletteColor: json['customPaletteColor'] as int?,
      floatingWindowMode: (json['floatingWindowMode'] as bool?) ?? true,
      windowWidth: (json['windowWidth'] as num?)?.toDouble() ?? 1152.0,
      windowHeight: (json['windowHeight'] as num?)?.toDouble() ?? 720.0,
      windowOffsetX: (json['windowOffsetX'] as num?)?.toDouble(),
      windowOffsetY: (json['windowOffsetY'] as num?)?.toDouble(),
      dockWidth: (json['dockWidth'] as num?)?.toDouble() ?? 78.0,
      sidebarWidth: (json['sidebarWidth'] as num?)?.toDouble() ?? 288.0,
      cardIdVisibility: (json['cardIdVisibility'] as String?) ?? 'Apenas Contatos Verificados',
      allowPublicIdSharing: (json['allowPublicIdSharing'] as bool?) ?? true,
      compactChatMode: (json['compactChatMode'] as bool?) ?? false,
      fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
      enterToSend: (json['enterToSend'] as bool?) ?? true,
      persistWindowGeometry: (json['persistWindowGeometry'] as bool?) ?? false,
      quantizeViewportDimensions: (json['quantizeViewportDimensions'] as bool?) ?? false,
      reducedMotion: (json['reducedMotion'] as bool?) ?? false,
      hidePagerAvatar: (json['hidePagerAvatar'] as bool?) ?? false,
      roundedSquareAvatar: json['roundedSquareAvatar'] == true,
      avatarFrameStyle: (json['avatarFrameStyle'] as String?) ??
          (json['roundedSquareAvatar'] == true ? 'roundedSquare' : 'circle'),
      avatarFrameShape: (json['avatarFrameShape'] as String?) ??
          ((json['roundedSquareAvatar'] == true || json['avatarFrameStyle'] == 'roundedSquare') ? 'square' : 'circle'),
      avatarFrameEffect: (json['avatarFrameEffect'] as String?) ??
          (json['avatarFrameStyle'] == 'cyberpunkNeon'
              ? 'neon'
              : json['avatarFrameStyle'] == 'pixelArt'
                  ? 'pixelArt'
                  : json['avatarFrameStyle'] == 'goldenBorder'
                      ? 'glow'
                      : 'none'),
      avatarCornerRadius: readAvatarValue(json['avatarCornerRadius'], 8.0, 0, 32),
      avatarBorderWidth: (json['avatarBorderWidth'] as num?)?.toDouble() ?? 1.5,
      avatarFrameColorHex: (json['avatarFrameColorHex'] as String?) ?? '',
      interfaceWallpaper: InterfaceWallpaper.fromJson(json['interfaceWallpaper']),
      pagerWallpaperShade: readAvatarValue(json['pagerWallpaperShade'], 0, 0, .75),
      pagerWallpaperBlur: readAvatarValue(json['pagerWallpaperBlur'], 0, 0, 18),
      pagerWallpaperAcrossPages: json['pagerWallpaperAcrossPages'] == true,
      pagerAvatarX: readAvatarValue(json['pagerAvatarX'], 0, -1, 1),
      pagerAvatarY: readAvatarValue(json['pagerAvatarY'], 0, -1, 1),
      pagerAvatarScale: readAvatarValue(json['pagerAvatarScale'], .28, .14, .56),
      pagerCaseColor: PagerCaseColor.read(json['pagerCaseColor']),
      pagerLcdColor: PagerLcdColor.read(json['pagerLcdColor']),
      transportProfile: (json['transportProfile'] as String?) ?? 'Tor Onion v3 (Fail-Closed)',
    );
  }
}
