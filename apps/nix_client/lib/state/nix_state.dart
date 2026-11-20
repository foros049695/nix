import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:flutter/foundation.dart' show compute, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import '../core/models/space.dart';
import '../core/models/channel.dart';
import '../core/models/message.dart';
import '../core/models/member.dart';
import '../core/models/call_state.dart';
import '../core/models/publication.dart';
import '../core/models/forum_post.dart';
import '../core/models/cultural_item.dart';
import '../core/models/user_profile.dart';
import '../core/models/direct_message.dart';
import '../core/models/user_settings.dart';
import '../core/models/monero_order.dart';
import '../core/models/github_repo.dart';
import '../core/theme/nix_colors.dart';
import '../core/theme/nix_palette.dart';
import '../core/security/security_context.dart';
import '../core/security/fail_closed_http_overrides.dart';
import '../core/security/platform_runtime.dart';
import '../core/security/sovereign_security_gate.dart';
import '../core/transport/hardware_radio_bridge.dart';
import '../core/database/local_database.dart';
import '../core/database/repositories.dart';
import '../core/security/key_vault.dart';
import '../core/security/local_image_helper.dart';
import '../core/security/seed_recovery.dart';
import '../core/security/anti_forensic_shredder.dart';
import '../core/messaging/sovereign_messenger.dart';
import '../core/messaging/direct_poll.dart';
import '../core/messaging/local_group_poll.dart';
import '../core/messaging/shared_group_poll.dart';
import '../core/messaging/scheduled_messages.dart';
import '../core/p2p/monero_ad_verifier.dart';
import '../core/archive/archive_image.dart';
import '../core/archive/nix_archive_service.dart';
import '../core/replication/replication_coordinator.dart';
import '../core/media/media_catalog_service.dart';
import '../core/media/pager_playlist.dart';
import '../core/media/voice_note.dart';
import '../core/media/catalog_database.dart';
import '../core/media/media_index_updater.dart';
import '../features/calls/call_view_model.dart';
import '../features/home/peer_hover_view_model.dart';
import '../features/discovery/starwire_filter_view_model.dart';
import '../features/monero_p2p/monero_order_filter_view_model.dart';
import '../features/navigation/navigation_view_model.dart';
import '../features/settings/settings_view_model.dart';
import '../features/chat/chat_view_model.dart';
import '../features/identity/identity_view_model.dart';
import '../features/media/media_view_model.dart';
import '../features/archive/archive_view_model.dart';
import 'package:nix_transport/nix_transport.dart';
import '../features/onboarding/sovereign_onboarding_model.dart';
import 'mock_data.dart';
import 'nix_preference_store.dart';
import 'forum_store.dart';
import 'workspace_folder_store.dart';

enum NixActiveArea {
  homePrivate, // Conversas privadas, Mensagens Salvas, Amigos, Solicitações e Card ID
  spaces,      // Espaços / Grupos e Canais
  explore,     // Explorar Canais e Grupos Públicos
  github,      // GitHub Discovery (Starwire)
  moneroP2p,   // Mercado Monero P2P Não Custodial
  mediaIndex,  // Nix Media Index Offline-First (Acervo Cultural)
  archive,     // Nix Archive Ambiente Dedicado
}

enum ConversationFilter {
  all,
  unread,
  pinned,
  privateChats,
  groups,
  channels,
  muted,
}

enum PeerCardHoverState {
  closed,
  openingPending,
  openByHover,
  openByClick,
  closingRequested,
}

class AuthorizedPeerCardData {
  final String peerName;
  final String peerPublicId;
  final NixTrustLevel trustLevel;
  final bool hasCryptographicShield;
  final bool isAuthorized;
  final String visibilityLabel;
  final String bio;
  final List<String> culturalHighlights;

  const AuthorizedPeerCardData({
    required this.peerName,
    required this.peerPublicId,
    required this.trustLevel,
    required this.hasCryptographicShield,
    required this.isAuthorized,
    required this.visibilityLabel,
    required this.bio,
    required this.culturalHighlights,
  });
}

class NixState extends ChangeNotifier {
  late List<Space> _spaces;
  final _workspaceFolders = WorkspaceFolderStore();
  List<SpaceFolder> get _folders => _workspaceFolders.folders;
  set _folders(List<SpaceFolder> folders) => _workspaceFolders.folders = folders;
  late List<Space> _discoverableSpaces;
  late Space _currentSpace;
  late Channel _currentChannel;
  late Map<String, List<Message>> _messages;
  late Map<String, List<Publication>> _publications;
  late List<ForumPost> _forumPosts;
  final _sharedGroupPollThreads = <String, SharedGroupPollThread>{};
  final _localGroupPolls = <LocalGroupPoll>[];
  static const _localGroupPollsKey = 'local_group_polls_v1';
  final _directPolls = <String, Map<String, DirectPollState>>{};
  late List<Member> _members;
  late UserProfile _userProfile;
  late List<DirectMessageThread> _directMessages;
  late List<ContactRequest> _contactRequests;
  late List<XmrTransactionRecord> _transactions;
  late List<SystemUpdateRecord> _systemUpdates;
  late List<MoneroP2pOrder> _moneroOrders;
  late List<GithubRepository> _githubRepos;
  UserSettings _settings = const UserSettings();

  // ViewModels extraídos (Issue #35: decomposição incremental)
  final CallViewModel _calls = CallViewModel();
  final PeerHoverViewModel _peerHover = PeerHoverViewModel();
  late final StarwireFilterViewModel _starwireFilters;
  late final MoneroOrderFilterViewModel _moneroFilters;

  CallViewModel get calls => _calls;
  PeerHoverViewModel get peerHover => _peerHover;
  StarwireFilterViewModel get starwireFilters => _starwireFilters;
  MoneroOrderFilterViewModel get moneroFilters => _moneroFilters;

  // ViewModels especializados (Etapa 8 - Desacoplamento de Estado)
  late final NavigationViewModel _navigation;
  late final SettingsViewModel _settingsVm;
  late final ChatViewModel _chatVm;
  late final IdentityViewModel _identityVm;
  late final MediaViewModel _mediaVm;
  late final ArchiveViewModel _archiveVm;

  NavigationViewModel get navigation => _navigation;
  SettingsViewModel get settingsVm => _settingsVm;
  SettingsViewModel get settingsViewModel => _settingsVm;
  ChatViewModel get chatVm => _chatVm;
  ChatViewModel get chatViewModel => _chatVm;
  IdentityViewModel get identityVm => _identityVm;
  IdentityViewModel get identityViewModel => _identityVm;
  MediaViewModel get mediaVm => _mediaVm;
  MediaViewModel get mediaViewModel => _mediaVm;
  ArchiveViewModel get archiveVm => _archiveVm;
  ArchiveViewModel get archiveViewModel => _archiveVm;

  SecurityContext _securityContext = const SecurityContext(myPersona: 'NX-7E3A');

  NixActiveArea _activeArea = NixActiveArea.spaces;
  HomeSubTab _homeSubTab = HomeSubTab.cardId;
  DirectMessageThread? _selectedDm;
  ForumPost? _selectedForumPost;

  // Navegação por Pastas & Filtros (Estilo Telegram Desktop)
  String _activeFolderId = 'all'; // 'all', 'private', ou folder.id
  ConversationFilter _conversationFilter = ConversationFilter.all;
  String _conversationSearchQuery = '';
  bool _isWindowMaximized = false;

  bool _isProfileOverlayOpen = false;
  bool _isSettingsOpenInOverlay = false;
  SettingsCategory _activeSettingsCategory = SettingsCategory.appearance;
  SettingsCategory? _requestedOverlaySettingsCategory;

  bool _isMembersPanelOpen = false;
  bool _isConversationInfoOpen = false;
  String _conversationHistorySearch = '';
  int _selectedEphemeralTimer = 0;
  bool _exploreSortAscending = true;
  String _exploreSearchQuery = '';

  // Estado de Mensagens (Responder, Editar, Seleção Múltipla, Fixada destacada)
  Message? _replyingToMessage;
  Message? _editingMessage;
  final Set<String> _selectedMessageIds = {};
  String? _highlightedMessageId;

  // Acervo Ids salvos localmente
  final Set<String> _savedAcervoIds = {};

  // Estado Tor Onion v3 & Gate Fail-Closed de Inicialização
  String _onionAddress = 'aguardando-circuito-onion-v3';
  bool _isTorRunning = false;
  bool _torBootstrapped100 = false;
  bool _torOnionV3Ready = false;
  bool _failClosedPolicyVerified = false;
  bool _isStrictOffGridMode = false;
  bool _isBootstrappingSecurityGate = false;
  String? _securityGateError;
  String _torDiagnosticDetail = 'Tor aguardando conexão SOCKS5 em 127.0.0.1:9050';
  final List<String> _torBootstrapLogs = [];
  StreamSubscription<TorBootstrapEvent>? _torBootstrapSub;
  Timer? _torWatchdogTimer;

  // Gerenciador de Tor Embutido (Zero-Configuration / Desktop Linux & Android NDK libtor.so)
  final EmbeddedTorManager _embeddedTor = EmbeddedTorManager(
    dataDirResolver: () => NixPlatformPaths.resolveDataFile('tor_data'),
    extraBinaryCandidatesResolver: NixPlatformPaths.extraTorBinaryCandidates,
  );
  EmbeddedTorManager get embeddedTor => _embeddedTor;
  bool get isMockMode => _isMockMode;
  bool get isStrictOffGridMode => _isStrictOffGridMode;
  List<String> get torBootstrapLogs => List.unmodifiable(_torBootstrapLogs);

  void _appendTorLog(String line) {
    final ts = DateTime.now().toUtc().toIso8601String().substring(11, 19);
    _torBootstrapLogs.add('[$ts] $line');
    if (_torBootstrapLogs.length > 60) {
      _torBootstrapLogs.removeAt(0);
    }
  }

  /// Relatório consolidado do Gate Fail-Closed (Tor Onion v3 + Criptografia).
  /// Bloqueia a entrada no aplicativo enquanto qualquer requisito estiver ausente.
  SovereignSecurityGateStatus get securityGate {
    final clearnetBlocked = NixFailClosedHttpOverrides.isInstalled;
    final sqlCipherOk = _localDatabase?.cipherInfo.isEncrypted ?? false;
    final vaultOk = _keyVault.isUnlocked;
    final identityOk = _primaryIdentity != null && _sovereignMessenger != null;

    return SovereignSecurityGateStatus(
      clearnetFirewallActive: clearnetBlocked,
      torSocksActive: _isTorRunning,
      torBootstrapped100: _torBootstrapped100,
      torOnionV3Ready: _torOnionV3Ready,
      failClosedPolicyVerified: _failClosedPolicyVerified,
      isStrictOffGridMode: _isStrictOffGridMode,
      sqlCipherEncrypted: sqlCipherOk,
      keyVaultUnlocked: vaultOk,
      identityKeysLoaded: identityOk,
      torBootstrapPercent: _torBootstrapped100 ? 100 : _embeddedTor.currentProgress,
      torStatusMessage: _torDiagnosticDetail,
      liveOnionV3Address: _torOnionV3Ready ? _onionAddress : null,
      torVersion: _embeddedTor.torVersion,
      torBinaryPath: _embeddedTor.resolvedBinaryPath,
      sqlCipherVersion: _localDatabase?.cipherInfo.cipherVersion,
      osKeyringBackend: _keyVault.osKeyStorage.backendName,
      blockingReason: _securityGateError,
      isBootstrapping: _isBootstrappingSecurityGate,
    );
  }

  /// Entra em Modo Off-Grid Estrito (Bluetooth BLE / Rádio LoRa · Zero Wi-Fi/Internet).
  ///
  /// Mantém o firewall HTTP anti-clearnet 100% ativo, desliga qualquer acesso à rede IP/relay,
  /// exige toda a criptografia local (SQLCipher + KeyVault + Seed A) e libera apenas comunicação
  /// física de proximidade via Bluetooth BLE Mesh (`NIXB`) e Rádio LoRa / RNode (`NX` KISS).
  Future<SovereignSecurityGateStatus> enterStrictOffGridMode() async {
    if (_disposed) return securityGate;
    _torWatchdogTimer?.cancel();
    await _torBootstrapSub?.cancel();
    _isBootstrappingSecurityGate = false;

    // 1. Garante firewall HTTP Fail-Closed contra rede doméstica/Wi-Fi
    NixFailClosedHttpOverrides.install();

    // 2. Audita política Fail-Closed de bloqueio clearnet
    bool failClosedOk = false;
    try {
      const strictPolicy = TransportPolicy(
        mode: TransportMode.torFailClosed,
        socksHost: '127.0.0.1',
        socksPort: 9050,
      );
      try {
        strictPolicy.assertAllowedUri(Uri.parse('https://example.com'));
        failClosedOk = false;
      } on TransportBlockedException {
        failClosedOk = true;
      }
    } catch (_) {
      failClosedOk = false;
    }

    // 3. Encerra qualquer daemon Tor ativo — zero tráfego IP em Modo Off-Grid
    try {
      await _embeddedTor.stop();
    } catch (_) {}

    _isTorRunning = false;
    _torBootstrapped100 = false;
    _torOnionV3Ready = false;
    _failClosedPolicyVerified = failClosedOk;
    _isStrictOffGridMode = true;
    _securityGateError = null;
    _torDiagnosticDetail =
        'Modo Off-Grid Estrito ativo · Rede Wi-Fi/Internet bloqueada · Rádios BLE e LoRa disponíveis.';
    _settings = _settings.copyWith(
      transportProfile: 'Off-Grid BLE/LoRa (Zero Rede IP)',
    );
    unawaited(_persistState());
    _appendTorLog(
      'MODO OFF-GRID ESTRITO ATIVADO: rede Wi-Fi/Internet bloqueada; apenas BLE Mesh & LoRa/RNode.',
    );
    if (!_disposed) notifyListeners();

    if (!_disposed && _localDatabase == null) {
      await _checkPersistedOnboardingStatus();
    }
    unawaited(refreshBleHardwareStatus());
    if (!_disposed) notifyListeners();
    return securityGate;
  }

  /// Sai do Modo Off-Grid Estrito e retorna ao Escudo Fail-Closed Tor Onion v3.
  Future<void> exitOffGridModeAndConnectTor() async {
    if (_disposed) return;
    _isStrictOffGridMode = false;
    _settings = _settings.copyWith(
      transportProfile: 'Tor Onion v3 (Fail-Closed)',
    );
    unawaited(_persistState());
    _torDiagnosticDetail = 'Retornando ao modo Tor Onion v3 Fail-Closed...';
    notifyListeners();
    await bootstrapSovereignEnvironment();
  }

  /// Abre diretamente o painel de Controle de Rádio BLE Mesh & LoRa / RNode.
  void openHardwareRadioSettings() {
    openProfileOverlay(startInSettings: true, category: SettingsCategory.connections);
  }

  /// Automação completa de inicialização segura (Fail-Closed):
  /// 1. Garante firewall HTTP contra vazamentos na rede doméstica.
  /// 2. Inicia daemon Tor embutido (0..100%) e provisiona/valida Onion v3.
  /// 3. Valida bloqueio ativo de clearnet e ativa watchdog contínuo.
  /// 4. Tenta desbloqueio automático do KeyVault/SQLCipher pelo chaveiro do SO (libsecret / AndroidKeyStore TEE).
  Future<SovereignSecurityGateStatus> bootstrapSovereignEnvironment() async {
    if (_disposed) return securityGate;
    if (_isBootstrappingSecurityGate) return securityGate;

    _isBootstrappingSecurityGate = true;
    _securityGateError = null;
    NixFailClosedHttpOverrides.install();
    _appendTorLog('Firewall HTTP Fail-Closed instalado (bloqueio de rede doméstica ativo).');
    _torDiagnosticDetail = 'Iniciando daemon Tor Onion v3 embutido...';
    notifyListeners();

    try {
      await _torBootstrapSub?.cancel();
      _torBootstrapSub = _embeddedTor.onBootstrapProgress.listen((ev) {
        if (_disposed) return;
        _torDiagnosticDetail = '[${ev.progressPercent}%] ${ev.stepSummary}';
        _appendTorLog('Tor ${ev.progressPercent}%: ${ev.stepSummary}');
        notifyListeners();
      });

      final started = await _embeddedTor.startEmbeddedTor(
        timeout: const Duration(seconds: 75),
      );
      if (_disposed) return securityGate;

      if (!started) {
        _isTorRunning = false;
        _torBootstrapped100 = false;
        _torOnionV3Ready = false;
        _securityGateError =
            'Falha ao estabelecer circuito Tor Onion v3: ${_embeddedTor.lastSummary}';
        _torDiagnosticDetail = _securityGateError!;
        _appendTorLog('BLOQUEADO: $_securityGateError');
      } else {
        final report = await verifyTorTransportAndFailClosed();
        if (!report.socksActive ||
            !report.circuitOperational ||
            !report.failClosedVerified ||
            !_torOnionV3Ready) {
          _securityGateError =
              'Auditoria Tor Onion v3 incompleta: ${report.detail}';
          _appendTorLog('BLOQUEADO: $_securityGateError');
        } else {
          _securityGateError = null;
          _appendTorLog(
            'Tor Onion v3 100% operacional ($_onionAddress · SOCKS5 127.0.0.1:${_embeddedTor.socksPort}).',
          );
          _startTorWatchdog();
        }
      }

      // Após validar transporte Tor, tenta montar o cofre SQLCipher (se ainda não aberto)
      if (!_disposed && _localDatabase == null) {
        await _checkPersistedOnboardingStatus();
      }
    } catch (e) {
      _securityGateError = 'Erro na inicialização soberana fail-closed: $e';
      _torDiagnosticDetail = _securityGateError!;
      _appendTorLog('ERRO: $_securityGateError');
    } finally {
      _isBootstrappingSecurityGate = false;
      if (!_disposed) notifyListeners();
    }
    return securityGate;
  }

  void _startTorWatchdog() {
    if (_isMockMode || Platform.environment.containsKey('FLUTTER_TEST')) return;
    _torWatchdogTimer?.cancel();
    _torWatchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_disposed || _isBootstrappingSecurityGate) return;
      final op = await _embeddedTor.verifyOperationalState();
      if (_disposed) return;
      if (!op.daemonSocksActive || !op.circuitOperational) {
        _isTorRunning = false;
        _torBootstrapped100 = false;
        _torOnionV3Ready = false;
        _securityGateError =
            'Conexão Tor Onion v3 interrompida (${op.detail}). Acesso bloqueado para evitar vazamento na rede doméstica.';
        _torDiagnosticDetail = _securityGateError!;
        _securityContext = _securityContext.copyWith(
          isTorConnected: false,
          status: SecuritySubsystemState.failed,
        );
        _appendTorLog('WATCHDOG FAIL-CLOSED: Tor caiu, tráfego bloqueado.');
        notifyListeners();
        if (_settings.autoReconnect) unawaited(bootstrapSovereignEnvironment());
      }
    });
  }

  /// Inicia o daemon Tor embutido nativo de forma automática e transparente.
  Future<bool> startEmbeddedTor() async {
    _torDiagnosticDetail = 'Iniciando daemon Tor embutido nativo...';
    notifyListeners();
    final ok = await _embeddedTor.startEmbeddedTor();
    if (ok) {
      final report = await verifyTorTransportAndFailClosed();
      return report.socksActive && report.circuitOperational && _torOnionV3Ready;
    }
    _torDiagnosticDetail = _embeddedTor.lastSummary;
    notifyListeners();
    return false;
  }

  // Banco de Dados Local Cifrado & KeyVault (P0-2)
  bool _disposed = false;
  bool _isMockMode = false;
  bool _enforceStartupGate = false;
  bool get enforceStartupGate => _enforceStartupGate;
  LocalDatabase? _localDatabase;
  late final KeyVault _keyVault;
  Uint8List? _activeMasterKey;
  NixIdentity? _primaryIdentity;
  String _localDeviceId = 'dev_primary';
  bool _requiresPassphraseUnlock = false;
  String? _lastDatabaseInitError;

  // Orquestradores de Domínio (Fases 3, 7, 8, 9)
  SovereignMessenger? _sovereignMessenger;
  RelayClient? _activeRelayClient;
  MailboxCredentials? _activeMailboxCredentials;
  String? _lastMessagingError;
  final Map<String, String> _consumedMoneroNonces = {};
  NixArchiveService? _archiveService;
  NixReplicationCoordinator? _replicationCoordinator;
  MediaCatalogService? _mediaCatalogService;
  String? _connectedMoneroRemoteNode;
  double? _moneroNonCustodialBalanceXmr;

  IdentityRepository? _identityRepo;
  ContactRepository? _contactRepo;
  ConversationRepository? _conversationRepo;
  MessageRepository? _messageRepo;
  OutboxRepository? _outboxRepo;
  PreferencesRepository? _preferencesRepo;
  KeyMaterialRepository? _keyMaterialRepo;
  PreKeyRepository? _preKeyRepo;
  SessionRepository? _sessionRepo;
  ObjectChunkRepository? _objectChunkRepo;
  MediaRepository? _mediaRepo;
  ArchiveRepository? _archiveRepo;

  bool get isDatabaseReady => _localDatabase != null;
  bool get requiresPassphraseUnlock => _requiresPassphraseUnlock;
  String? get lastDatabaseInitError => _lastDatabaseInitError;
  NixIdentity? get primaryIdentity => _primaryIdentity;
  String get localDeviceId => _localDeviceId;
  LocalDatabase? get localDatabase => _localDatabase;
  KeyVault get keyVault => _keyVault;
  SovereignMessenger? get sovereignMessenger => _sovereignMessenger;
  String? get lastMessagingError => _lastMessagingError;
  NixArchiveService? get archiveService => _archiveService;
  NixReplicationCoordinator? get replicationCoordinator => _replicationCoordinator;
  MediaCatalogService? get mediaCatalogService => _mediaCatalogService;

  void clearLastMessagingError() {
    _lastMessagingError = null;
    notifyListeners();
  }

  /// Rótulo honesto de saldo Monero não custodial (Seed B isolada da Seed A da mensageria).
  String get moneroWalletBalanceLabel => _moneroNonCustodialBalanceXmr != null
      ? '${_moneroNonCustodialBalanceXmr!.toStringAsFixed(12)} XMR'
      : 'Carteira externa desconectada';

  /// Rótulo honesto de conexão ao nó remoto Monero .onion.
  String get moneroWalletStatusLabel => _connectedMoneroRemoteNode != null
      ? 'Nó Remoto .onion: $_connectedMoneroRemoteNode'
      : 'Sem Custódia Local · Conecte Carteira Externa (Seed B Isolada)';

  IdentityRepository? get identityRepo => _identityRepo;
  ContactRepository? get contactRepo => _contactRepo;
  ConversationRepository? get conversationRepo => _conversationRepo;
  MessageRepository? get messageRepo => _messageRepo;
  OutboxRepository? get outboxRepo => _outboxRepo;
  PreferencesRepository? get preferencesRepo => _preferencesRepo;
  KeyMaterialRepository? get keyMaterialRepo => _keyMaterialRepo;
  PreKeyRepository? get preKeyRepo => _preKeyRepo;
  SessionRepository? get sessionRepo => _sessionRepo;
  ObjectChunkRepository? get objectChunkRepo => _objectChunkRepo;
  MediaRepository? get mediaRepo => _mediaRepo;
  ArchiveRepository? get archiveRepo => _archiveRepo;

  CatalogDatabase? _catalogDatabase;
  CatalogRepository? _catalogRepo;

  CatalogDatabase? get catalogDatabase => _catalogDatabase;
  CatalogRepository? get catalogRepo => _catalogRepo;
  MediaRepository get mediaRepository => _mediaRepo!;
  ArchiveRepository get archiveRepository => _archiveRepo!;

  void debugOverrideArchive(
    ArchiveRepository repo,
    NixArchiveService service,
    NixIdentity identity,
  ) {
    _archiveRepo = repo;
    _archiveService = service;
    _primaryIdentity = identity;
    _archiveVm.attachServices(archiveService: service, archiveRepo: repo);
    _identityVm.setPrimaryIdentity(identity);
  }

  Future<void>? _catalogOpen;

  Future<void> ensureCatalogDatabaseOpened() async {
    if (_catalogDatabase != null || _panicWipe != null) return;
    final opening = _catalogOpen ??= _openCatalog();
    try {
      await opening;
    } finally {
      if (identical(_catalogOpen, opening)) _catalogOpen = null;
    }
  }

  Future<void> _openCatalog() async {
    var db = await CatalogDatabase.open();
    if (_disposed || _panicWipe != null) {
      await db.close();
      return;
    }
    try {
      if (await db.getEntryCount() == 0) {
        final seed = await rootBundle.load('assets/catalog/seed_catalog.db');
        final bytes = seed.buffer.asUint8List(seed.offsetInBytes, seed.lengthInBytes);
        const bundledSeedSha256 =
            'f14e9d230bbbcdcd1542771a8bc9d87ff4045a61058afc3c4dba6dd97e846c6c';
        if (std_crypto.sha256.convert(bytes).toString() != bundledSeedSha256) {
          throw const FormatException('O catálogo incluído no aplicativo falhou na verificação de integridade.');
        }
        final file = File(db.path);
        final temporary = File('${db.path}.seed.tmp');
        try {
          await temporary.writeAsBytes(bytes, flush: true);
          await db.close();
          await temporary.rename(file.path);
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
        if (_disposed || _panicWipe != null) return;
        db = await CatalogDatabase.open(path: file.path);
      }
      await db.installBundledMusic();
      setCatalogDatabase(db);
    } catch (_) {
      try {
        await db.close();
      } catch (_) {}
      rethrow;
    }
  }

  CatalogUpdateManager? _catalogUpdateManager;
  CatalogUpdateManager get catalogUpdateManager =>
      _catalogUpdateManager ??= CatalogUpdateManager();

  void setCatalogDatabase(CatalogDatabase newDb) {
    if (_disposed || _panicWipe != null) {
      unawaited(newDb.close());
      return;
    }
    final previous = _catalogDatabase;
    _catalogDatabase = newDb;
    if (previous != null && !identical(previous, newDb)) {
      unawaited(previous.close());
    }
    _catalogRepo = CatalogRepository(_catalogDatabase!);
    if (_mediaRepo != null) {
      _mediaCatalogService =
          MediaCatalogService(_mediaRepo!, catalogRepo: _catalogRepo);
    }
    _mediaVm.attachServices(
      catalogService: _mediaCatalogService,
      catalogDatabase: _catalogDatabase,
    );
    notifyListeners();
  }

  void _rebuildSovereignMessenger() {
    if (_localDatabase != null &&
        _primaryIdentity != null &&
        _activeMasterKey != null) {
      _activeMailboxCredentials ??=
          SovereignMessenger.deriveMailboxCredentials(_primaryIdentity!.publicId);
      _sovereignMessenger = SovereignMessenger(
        database: _localDatabase!,
        identity: _primaryIdentity!,
        localDeviceId: _localDeviceId,
        vaultMasterKey: _activeMasterKey!,
      );
    } else {
      _sovereignMessenger = null;
    }
  }

  static const _relayPreferenceKey = 'messaging.relay.v1';

  bool _useCurrentTorPort = false;

  RelayClient? get _relayForMessaging {
    final relay = _activeRelayClient;
    if (relay == null || !_useCurrentTorPort) return relay;
    return RelayClient(
      baseUri: relay.baseUri,
      policy: TransportPolicy(socksPort: _embeddedTor.socksPort),
    );
  }

  bool get hasRelayConfiguration => _activeRelayClient != null;

  String get localRelayMailboxId => _activeMailboxCredentials?.mailboxId ??
      (_primaryIdentity == null
          ? ''
          : SovereignMessenger.deriveMailboxCredentials(_primaryIdentity!.publicId)
              .mailboxId);

  Uri? get relayAddress => _activeRelayClient?.baseUri;

  Uri _validateRelayAddress(String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !TransportPolicy.isValidOnionV3Host(uri.host) ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('Informe o endereço HTTP(S) de um relay Onion v3.');
    }
    return uri;
  }

  void _activateProvisionedRelay(Uri uri, MailboxCredentials credentials) {
    configureRelayTransport(
      relayClient: RelayClient(
        baseUri: uri,
        policy: TransportPolicy(socksPort: _embeddedTor.socksPort),
      ),
      mailboxCredentials: credentials,
    );
    _useCurrentTorPort = true;
  }

  Future<void> saveRelayConfiguration({
    required String address,
    required String readToken,
    required String writeToken,
  }) async {
    final repo = _preferencesRepo;
    final mailbox = localRelayMailboxId;
    if (_localDatabase?.cipherInfo.isEncrypted != true || repo == null ||
        mailbox.isEmpty || _panicWipe != null) {
      throw StateError('Desbloqueie o cofre SQLCipher antes de configurar o relay.');
    }
    final uri = _validateRelayAddress(address);
    final read = readToken.trim();
    final write = writeToken.trim();
    if (read.isEmpty || read.length > 512 || write.length > 512 ||
        RegExp(r'\s').hasMatch(read) || RegExp(r'\s').hasMatch(write) ||
        RegExp(r'^read_[0-9a-f]{64}$').hasMatch(read)) {
      throw const FormatException('Use as credenciais provisionadas pelo operador do relay.');
    }
    await repo.setOption(_relayPreferenceKey, {
      'address': uri.toString(),
      'mailbox': mailbox,
      'readToken': read,
      'writeToken': write,
    });
    if (_disposed || _panicWipe != null) return;
    _activateProvisionedRelay(uri, MailboxCredentials(
      mailboxId: mailbox, readToken: read, writeQuotaToken: write,
    ));
  }

  Future<void> _restoreRelayConfiguration() async {
    if (_localDatabase?.cipherInfo.isEncrypted != true) return;
    try {
      final settings = await _preferencesRepo?.getOption(_relayPreferenceKey);
      if (settings is! Map || settings['mailbox'] != localRelayMailboxId) return;
      _activateProvisionedRelay(
        _validateRelayAddress(settings['address'] as String),
        MailboxCredentials(
          mailboxId: settings['mailbox'] as String,
          readToken: settings['readToken'] as String,
          writeQuotaToken: settings['writeToken'] as String,
        ),
      );
    } catch (_) {
      _lastMessagingError = 'A configuração do relay no cofre é inválida.';
    }
  }

  /// Configura o cliente de transporte do relay cego e credenciais de mailbox para o [SovereignMessenger].
  void configureRelayTransport({
    required RelayClient relayClient,
    MailboxCredentials? mailboxCredentials,
  }) {
    if (Platform.environment['FLUTTER_TEST'] != 'true' &&
        (mailboxCredentials == null ||
            mailboxCredentials.readToken.isEmpty ||
            RegExp(r'^read_[0-9a-f]{64}$').hasMatch(mailboxCredentials.readToken))) {
      throw ArgumentError(
        'Configure uma credencial de leitura provisionada pelo operador do relay.',
      );
    }
    _useCurrentTorPort = false;
    _activeRelayClient = relayClient;
    if (mailboxCredentials != null) {
      _activeMailboxCredentials = mailboxCredentials;
    } else if (_primaryIdentity != null) {
      _activeMailboxCredentials = SovereignMessenger.deriveMailboxCredentials(
        _primaryIdentity!.publicId,
      );
    }
    if (_sovereignMessenger == null) _rebuildSovereignMessenger();
    notifyListeners();
  }

  // Gerenciador de Malha por Proximidade Bluetooth (estilo Briar BTP) & Rádio LoRa / RNode
  late final BluetoothMeshManager _bluetoothMesh = BluetoothMeshManager(
    localCardId: _userProfile.publicId,
  );
  late final NixHardwareRadioBridge _hardwareRadioBridge =
      NixHardwareRadioBridge(
    bluetoothMesh: _bluetoothMesh,
    onLog: _appendHardwareRadioLog,
    onLoraFrameRx: (src, payload, seq) {
      final decodedText = utf8.decode(payload, allowMalformed: true);
      _appendHardwareRadioLog(HardwareRadioLogEntry(
        timestamp: DateTime.now().toUtc(),
        medium: 'LORA',
        direction: 'RX',
        summary: 'Payload #$seq ($src): "$decodedText"',
      ));
    },
  );
  final List<HardwareRadioLogEntry> _hardwareRadioLogs = [];
  BleHardwareStatus? _bleHardwareStatus;
  List<RNodeHardwareDevice> _detectedRNodeDevices = const [];
  StreamSubscription<BluetoothProximityPeer>? _blePeerSub;
  StreamSubscription<void>? _bleRxSub;

  void _appendHardwareRadioLog(HardwareRadioLogEntry entry) {
    _hardwareRadioLogs.insert(0, entry);
    if (_hardwareRadioLogs.length > 80) {
      _hardwareRadioLogs.removeLast();
    }
    if (!_disposed) notifyListeners();
  }

  BluetoothMeshManager get bluetoothMesh => _bluetoothMesh;
  NixHardwareRadioBridge get hardwareRadioBridge => _hardwareRadioBridge;
  bool get isBluetoothMeshEnabled => _bluetoothMesh.isMeshEnabled;
  BleHardwareStatus? get bleHardwareStatus => _bleHardwareStatus;
  List<RNodeHardwareDevice> get detectedRNodeDevices =>
      List.unmodifiable(_detectedRNodeDevices);
  List<HardwareRadioLogEntry> get hardwareRadioLogs =>
      List.unmodifiable(_hardwareRadioLogs);

  Future<BleHardwareStatus> refreshBleHardwareStatus() async {
    _hardwareRadioBridge.attach();
    _bleHardwareStatus = await _hardwareRadioBridge.getBleStatus();
    if (!_disposed) notifyListeners();
    return _bleHardwareStatus!;
  }

  Future<bool> requestBleHardwarePermissions() async {
    final ok = await _hardwareRadioBridge.requestBlePermissions();
    await refreshBleHardwareStatus();
    return ok;
  }

  Future<void> setBluetoothMeshEnabled(bool enabled) async {
    _hardwareRadioBridge.attach();
    _bluetoothMesh.setMeshEnabled(enabled);
    if (enabled) {
      final localId = _primaryIdentity?.publicId ??
          (_userProfile.publicId.isNotEmpty ? _userProfile.publicId : 'NIX-LOCAL');
      await _hardwareRadioBridge.startNativeBleMesh(localId);
    } else {
      await _hardwareRadioBridge.stopNativeBleMesh();
    }
    await refreshBleHardwareStatus();
  }

  /// Envia um pacote NIXB assinado (Ed25519) via Bluetooth BLE físico para pares Nix próximos.
  Future<int> sendBleTestPacket(String message, {String? targetAddress}) async {
    final text = message.trim();
    if (text.isEmpty) return 0;
    final bodyBytes = utf8.encode(text);
    Uint8List payload;
    if (_primaryIdentity != null) {
      final sig = await _primaryIdentity!.sign(bodyBytes);
      payload = Uint8List.fromList(utf8.encode(jsonEncode({
        'from': _primaryIdentity!.publicId,
        'edPub': _primaryIdentity!.ed25519PublicHex,
        'msg': text,
        'sig': base64Encode(sig),
        'ts': DateTime.now().toUtc().millisecondsSinceEpoch,
      })));
    } else {
      payload = Uint8List.fromList(bodyBytes);
    }
    final sent = await _bluetoothMesh.broadcastEnvelope(
      recipientCardId: targetAddress ?? 'NIX-BLE-BROADCAST',
      payload: payload,
      targetDeviceAddress: targetAddress,
    );
    _appendHardwareRadioLog(HardwareRadioLogEntry(
      timestamp: DateTime.now().toUtc(),
      medium: 'BLE',
      direction: 'TX',
      summary: sent > 0
          ? 'Teste NIXB assinado enviado para $sent par(es): "$text"'
          : 'Nenhum par BLE em alcance ou falha de escrita GATT.',
    ));
    return sent;
  }

  Future<List<RNodeHardwareDevice>> scanRNodeHardwareDevices() async {
    _detectedRNodeDevices = await _hardwareRadioBridge.scanRNodeDevices();
    if (!_disposed) notifyListeners();
    return _detectedRNodeDevices;
  }

  Future<bool> connectRNodeHardwareDevice(RNodeHardwareDevice device) async {
    final ok = await _hardwareRadioBridge.connectRNodeDevice(device);
    if (!_disposed) notifyListeners();
    return ok;
  }

  Future<void> disconnectRNodeHardwareDevice() async {
    await _hardwareRadioBridge.disconnectRNode();
    if (!_disposed) notifyListeners();
  }

  Future<({bool sent, String detail})> sendLoraTestMessage(String text) async {
    final res = await _hardwareRadioBridge.sendLoraShortPacket(
      Uint8List.fromList(utf8.encode(text.trim())),
    );
    if (!_disposed) notifyListeners();
    return res;
  }

  // Estado e Controle de Onboarding Soberano (Seção 2 / Fase 6)
  bool _isOnboarded = false;
  bool _onboardingNoticeDismissed = false;

  bool get isOnboarded => _isOnboarded;
  bool get onboardingNoticeDismissed => _onboardingNoticeDismissed;

  void dismissOnboardingToIncompleteNotice() {
    _onboardingNoticeDismissed = true;
    notifyListeners();
  }

  void reopenOnboardingFlow() {
    _onboardingNoticeDismissed = false;
    notifyListeners();
  }

  /// Verifica ativamente o transporte Tor (SOCKS5 + ControlPort bootstrap 100%) e a política fail-closed.
  /// Diferencia daemon SOCKS5 ativo (`socksActive`) de circuito operacional (`circuitOperational`)
  /// e confirma que conexões diretas clearnet são bloqueadas quando `torRequired` está ativo.
  Future<
      ({
        bool socksActive,
        bool circuitOperational,
        bool failClosedVerified,
        String detail,
      })> verifyTorTransportAndFailClosed({
    int? customSocksPort,
    int? customControlPort,
  }) async {
    bool failClosedOk = false;
    try {
      const strictPolicy = TransportPolicy(
        mode: TransportMode.torFailClosed,
        socksHost: '127.0.0.1',
        socksPort: 9050,
      );
      try {
        strictPolicy.assertAllowedUri(Uri.parse('https://example.com'));
        failClosedOk = false;
      } on TransportBlockedException {
        failClosedOk = true;
      }
      strictPolicy.assertAllowedUri(
        Uri.parse('http://gpoun4vo5v5h3cmcfdxtudm3nlzxri3qzjd7fhbvy6oep2ap67g4qvyd.onion/v1/health'),
      );
    } catch (_) {
      failClosedOk = false;
    }

    final socksPort = customSocksPort ?? _embeddedTor.socksPort;
    final controlPort = customControlPort ?? _embeddedTor.controlPort;
    final cookiePath = '${_embeddedTor.dataDirectory}/control_auth_cookie';
    final hasCookie = File(cookiePath).existsSync();

    bool socksActive = false;
    bool circuitOperational = false;
    bool onionV3Ready = false;
    String detailMsg;

    if (customSocksPort == null && customControlPort == null && hasCookie) {
      final prov = await _embeddedTor.verifyAndProvisionOnionV3();
      socksActive = prov.socksActive;
      circuitOperational = prov.circuitOperational;
      onionV3Ready = prov.onionV3Ready;
      if (prov.onionV3Address != null && prov.onionV3Address!.isNotEmpty) {
        _onionAddress = prov.onionV3Address!;
      }
      detailMsg = prov.detail;
    } else {
      final diag = await TorDiagnostics.diagnose(
        host: '127.0.0.1',
        socksPort: socksPort,
        controlPort: controlPort,
        controlCookiePath: hasCookie ? cookiePath : null,
      );
      socksActive = diag.socksReachable;
      final controlBootstrapped = diag.bootstrapStatus == null ||
          diag.bootstrapStatus!.contains('PROGRESS=100');
      circuitOperational =
          diag.socksReachable && (controlBootstrapped || !hasCookie);
      onionV3Ready = circuitOperational &&
          TransportPolicy.isValidOnionV3Host(_onionAddress);
      detailMsg = diag.message;
    }

    _isTorRunning = socksActive;
    _torBootstrapped100 = circuitOperational;
    _torOnionV3Ready = onionV3Ready;
    _failClosedPolicyVerified = failClosedOk;
    _torDiagnosticDetail = detailMsg;
    _securityContext = _securityContext.copyWith(
      isTorConnected: circuitOperational && onionV3Ready,
      status: (circuitOperational && onionV3Ready && failClosedOk)
          ? SecuritySubsystemState.ready
          : SecuritySubsystemState.failed,
    );
    notifyListeners();
    return (
      socksActive: socksActive,
      circuitOperational: circuitOperational,
      failClosedVerified: failClosedOk,
      detail:
          '$detailMsg · OnionV3=${onionV3Ready ? "ATIVO" : "PENDENTE"} · Fail-Closed=${failClosedOk ? "VERIFICADO" : "FALHOU"}',
    );
  }

  /// Conclui o fluxo de primeiro acesso soberano e comuta o app para produção real.
  /// Exige pré-requisitos essenciais (identidade criptográfica gerada/derivada) fora do modo de fixtures.
  Future<void> completeOnboarding({
    String? publicId,
    String? displayName,
    String? avatarStyle,
  }) async {
    if (displayName != null && displayName.isNotEmpty) {
      updateProfile(displayName: displayName);
    }
    if (avatarStyle != null && avatarStyle.isNotEmpty) {
      updateProfile(avatarStyle: avatarStyle);
    }
    if (publicId != null && publicId.isNotEmpty) {
      _userProfile = _userProfile.copyWith(publicId: publicId);
    }

    final hasValidIdentity =
        _primaryIdentity != null || _userProfile.publicId.trim().isNotEmpty;
    if (!_isMockMode && !hasValidIdentity) {
      throw StateError(
        '[Fail-Closed] Pré-requisito de onboarding ausente: identidade criptográfica (Seed A) não foi inicializada.',
      );
    }

    _isOnboarded = true;
    _onboardingNoticeDismissed = false;

    if (_localDatabase != null &&
        _identityRepo != null &&
        _userProfile.publicId.isNotEmpty) {
      final primary = await _identityRepo!.getPrimaryIdentity();
      if (primary != null) {
        await _identityRepo!.saveProfile(
          identityId: primary['id'] as String,
          displayName: _userProfile.effectiveDisplayName,
          bio: _userProfile.bio,
          avatarObjectId: _userProfile.avatarStyle,
        );
      }
    }

    final prevSnapshot = await OnboardingStateSnapshot.load();
    final snapshot = OnboardingStateSnapshot(
      currentStep: OnboardingStep.ready,
      torConsentAccepted: true,
      torBootstrapped: prevSnapshot.torBootstrapped || _isTorRunning,
      torVerified: prevSnapshot.torVerified || _isTorRunning,
      identityGenerated: true,
      backupConfirmed: true,
      publicIdDerived: _userProfile.publicId.isNotEmpty,
      profileConfigured: true,
      isCompleted: true,
      publicId: _userProfile.publicId,
      displayName: _userProfile.effectiveDisplayName,
      avatarStyle: _userProfile.avatarStyle,
    );
    await OnboardingStateSnapshot.save(snapshot);
    notifyListeners();
  }

  /// Importa a identidade, a caixa postal e a pré-chave assinadas pelo contato.
  Future<void>? _importingInvitation;

  Future<void> addNewContact({required String publicId, String? nickname}) {
    if (_importingInvitation != null) {
      return Future.error(StateError('Já existe um convite sendo importado.'));
    }
    return _importingInvitation = _importContactInvitation(publicId, nickname)
        .whenComplete(() => _importingInvitation = null);
  }

  Future<void> _importContactInvitation(String publicId, String? nickname) async {
    final raw = publicId.trim();
    if (raw.length > 8192 || !raw.startsWith('{')) {
      throw const FormatException('Cole o convite assinado completo do contato.');
    }
    final messenger = _sovereignMessenger;
    if (messenger == null) {
      throw StateError('Desbloqueie o cofre para importar um convite.');
    }
    final result = await messenger.importAndVerifyCardJson(
      rawJson: raw,
      markVerifiedOutOfBand: false,
      upgradeLegacyPlaceholder: true,
    );
    final peerId = result.publicId;
    final bundle = result.signedPreKeyBundle;
    if (result.status != CardImportStatus.importedUnverified ||
        peerId == null || bundle == null) {
      throw StateError(result.status == CardImportStatus.keyChangedWarning
          ? 'As chaves do contato mudaram. Confirme a identidade antes de continuar.'
          : 'O convite é inválido ou expirou.');
    }
    final localId = messenger.identity.publicId;
    final id = SovereignMessenger.invitationConversationId(localId, peerId);
    final alias = nickname?.trim();
    final title = alias != null && alias.isNotEmpty
        ? alias
        : result.displayName ?? peerId;
    // Só um lado inicia X3DH, mesmo se ambos importarem os convites ao mesmo tempo.
    if (localId.compareTo(peerId) < 0 &&
        await messenger.getSessionMetadata(id) == null) {
      await messenger.establishInitiatorSession(
        conversationId: id,
        peerPublicId: peerId,
        peerDeviceId: 'dev_primary',
        peerBundle: bundle,
        peerTitle: title,
        peerMailbox: result.mailboxId,
      );
    } else if (await messenger.conversationRepo.getConversation(id) == null) {
      await messenger.conversationRepo.createConversation(
        id: id,
        kind: 'direct',
        ownerIdentityId: localId,
        title: title,
      );
    }
    await _refreshDirectThreadsFromDatabase();
    selectDirectMessage(_directMessages.firstWhere((thread) => thread.id == id));
  }

  /// Procedimento Anti-Forense / Botão de Pânico (estilo BleachBit):
  /// Destrói a memória RAM, fecha banco e sobrescreve arquivos em múltiplas passagens destrutivas.
  Future<ShredReport>? _panicWipe;

  Future<ShredReport> panicWipeAllData({String? customBaseDir}) {
    return _panicWipe ??= _runPanicWipe(customBaseDir).whenComplete(() {
      _panicWipe = null;
    });
  }

  Future<ShredReport> _runPanicWipe(String? customBaseDir) async {
    try {
      _torBootstrapSub?.cancel();
      _torBootstrapSub = null;
      await _embeddedTor.stop();
    } catch (_) {}
    _scheduledWakeup?.cancel();
    _scheduledWakeup = null;
    await _scheduledRun;
    await _interactiveDirectSend;
    if (Platform.isAndroid) {
      try {
        await const MethodChannel('com.projetonix.nix/voice_notes')
            .invokeMethod<void>('cancel');
      } catch (_) {}
      try {
        await const MethodChannel('com.projetonix.nix/pager_audio')
            .invokeMethod<void>('wipe');
      } catch (_) {
        // Um erro no player não impede a destruição do cofre.
      }
    }
    _hasScheduledMessages = false;
    _scheduledOutboxNeedsRetry = false;
    await _catalogUpdateManager?.cancelAndWait();
    await _pagerWallpaperChange;
    await flushPreferences();
    try {
      await _catalogOpen;
      await _catalogDatabase?.close();
    } catch (_) {}
    _catalogDatabase = null;
    _calls.reset();
    _peerHover.reset();
    _starwireFilters.resetFilters();
    _moneroFilters.resetFilters();

    final report = await AntiForensicShredder.panicWipeAccount(
      activeDatabase: _localDatabase,
      activeVault: _keyVault,
      customBaseDir: customBaseDir,
    );
    if (_activeMasterKey != null) {
      _activeMasterKey!.fillRange(0, _activeMasterKey!.length, 0);
      _activeMasterKey = null;
    }
    _primaryIdentity = null;
    _fallbackArchiveIdentity = null;
    _inMemoryArchiveObjects.clear();
    _consumedMoneroNonces.clear();
    _forumTags.clear();
    _directPolls.clear();
    _localGroupPolls.clear();
    _sharedGroupPollThreads.clear();
    _localDeviceId = 'dev_primary';
    _localDatabase = null;
    _sovereignMessenger = null;
    _activeRelayClient = null;
    _activeMailboxCredentials = null;
    _archiveService = null;
    _mediaCatalogService = null;
    _identityRepo = null;
    _contactRepo = null;
    _conversationRepo = null;
    _messageRepo = null;
    _outboxRepo = null;
    _preferencesRepo = null;
    _keyMaterialRepo = null;
    _preKeyRepo = null;
    _sessionRepo = null;
    _objectChunkRepo = null;
    _mediaRepo = null;
    _catalogRepo = null;
    _archiveRepo = null;
    _isOnboarded = false;
    _requiresPassphraseUnlock = false;
    _initializeProductionCleanState();
    notifyListeners();
    return report;
  }

  /// Deriva uma chave de envelopamento de material privado isolada por contexto HKDF-SHA256.
  Future<SecretKeyData> _deriveWrappingKey(String domainInfo) async {
    final master = _activeMasterKey;
    if (master == null || master.isEmpty) {
      throw StateError('[Fail-Closed] Cofre local não desbloqueado para envelopar chaves.');
    }
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(master),
      nonce: utf8.encode('nix-keyvault-v1'),
      info: utf8.encode(domainInfo),
    );
    final bytes = await derived.extractBytes();
    return SecretKeyData(bytes);
  }

  void _instantiateRepositories() {
    final db = _localDatabase!;
    _identityRepo = IdentityRepository(db);
    _contactRepo = ContactRepository(db);
    _conversationRepo = ConversationRepository(db);
    _messageRepo = MessageRepository(db);
    _outboxRepo = OutboxRepository(db);
    _preferencesRepo = PreferencesRepository(db);
    _keyMaterialRepo = KeyMaterialRepository(db);
    _preKeyRepo = PreKeyRepository(db);
    _sessionRepo = SessionRepository(db);
    _objectChunkRepo = ObjectChunkRepository(db);
    _mediaRepo = MediaRepository(db);
    _archiveRepo = ArchiveRepository(db);
    _archiveService = NixArchiveService(_archiveRepo!);
    _mediaCatalogService = MediaCatalogService(_mediaRepo!);
    _rebuildSovereignMessenger();
  }

  /// Inicializa o cofre de chaves local com Argon2id + XChaCha20-Poly1305
  /// e abre a conexão com o banco de dados SQLCipher executando migrações auditadas (P0-2 / P0-5 / Fase 5).
  /// Sem frase-passe padrão fixa: `passphrase` é obrigatório.
  Future<bool> initializeEncryptedDatabase({
    required String passphrase,
    String? customDbPath,
    String? customVaultPath,
    String? migration001Sql,
    String? migration002Sql,
    bool bindToOsKeyring = false,
    String? duressPassphrase,
    bool? requireEncryption,
    bool overwriteExistingVault = false,
  }) async {
    if (_disposed) return false;
    _lastDatabaseInitError = null;
    if (passphrase.trim().isEmpty) {
      _lastDatabaseInitError = '[Fail-Closed] Frase-passe do cofre não pode ser vazia.';
      return false;
    }
    final effectiveRequireEncryption = requireEncryption ??
        (!Platform.environment.containsKey('FLUTTER_TEST') ||
            Platform.environment['NIX_REQUIRE_SQLCIPHER'] == 'true');
    final resolvedVaultPath = customVaultPath ?? KeyVault.getDefaultBootstrapPath();
    final resolvedDbPath = customDbPath ?? LocalDatabase.getDefaultDatabasePath();
    final existedVaultBefore = !overwriteExistingVault &&
        (await _keyVault.isInitialized(customPath: customVaultPath) ||
            await File(resolvedVaultPath).exists());
    final existedDbBefore = !overwriteExistingVault &&
        (resolvedDbPath != ':memory:' && await File(resolvedDbPath).exists());
    try {
      Uint8List masterKey;
      if (existedVaultBefore) {
        final unlockResult = await _keyVault.unlockOrDuress(
          passphrase: passphrase,
          customPath: customVaultPath,
        );
        if (unlockResult.status == VaultUnlockStatus.duressTriggered) {
          await panicWipeAllData();
          return false;
        }
        masterKey = unlockResult.masterKey!;
      } else {
        masterKey = await _keyVault.initialize(
          passphrase: passphrase,
          customPath: customVaultPath,
          duressPassphrase: duressPassphrase,
          bindToOsKeyring: bindToOsKeyring,
          overwrite: overwriteExistingVault,
        );
        if (bindToOsKeyring && !_keyVault.lastKeyringBindSucceeded) {
          throw StateError(
            '[Fail-Closed] Não foi possível vincular o cofre ao keyring do SO.',
          );
        }
      }

      if (_disposed) {
        _keyVault.lock();
        return false;
      }

      final database = await LocalDatabase.open(
        path: customDbPath,
        rawCipherKey: Uint8List.fromList(masterKey),
        migration001Sql: migration001Sql,
        migration002Sql: migration002Sql,
        requireEncryption: effectiveRequireEncryption,
      );

      // O descarte pode ocorrer durante a derivação da chave ou abertura do banco.
      // Não publica recursos nem notifica ouvintes depois desse ponto.
      if (_disposed) {
        try {
          await database.close();
        } finally {
          _keyVault.lock();
        }
        return false;
      }
      _activeMasterKey = Uint8List.fromList(masterKey);
      _localDatabase = database;
      _securityContext = _securityContext.copyWith(
        isSqlCipherUnlocked: database.cipherInfo.isEncrypted,
        status: SecuritySubsystemState.ready,
      );

      // Instanciação completa dos repositórios de domínio
      _instantiateRepositories();
      _requiresPassphraseUnlock = false;

      notifyListeners();
      return true;
    } catch (e) {
      _lastDatabaseInitError = e.toString();
      if (!existedVaultBefore) {
        await _keyVault.rollbackFreshBootstrap(customPath: customVaultPath);
      } else if (_disposed) {
        _keyVault.lock();
      }
      if (!existedDbBefore && resolvedDbPath != ':memory:') {
        for (final suffix in const ['', '-wal', '-shm']) {
          final f = File('$resolvedDbPath$suffix');
          if (await f.exists() && (await f.length()) == 0) {
            try {
              await f.delete();
            } catch (_) {}
          }
        }
      }
      debugPrint('[NixState] Erro ao inicializar banco de dados cifrado: $e');
      return false;
    }
  }

  /// Configura ou altera o PIN de coação (duress) no KeyVault ativo.
  Future<bool> configureDuressPin({
    required String vaultPassphrase,
    required String duressPin,
    String? customVaultPath,
  }) async {
    try {
      await _keyVault.configureDuressPassphrase(
        vaultPassphrase: vaultPassphrase,
        duressPassphrase: duressPin,
        customPath: customVaultPath,
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[NixState] Falha ao configurar PIN de coação: $e');
      return false;
    }
  }

  /// Desbloqueia o KeyVault usando a frase-passe do usuário (ou executa apagamento silencioso
  /// caso a senha fornecida corresponda ao PIN de coação configurado) e recarrega o estado local.
  Future<VaultUnlockResult> unlockWithPassphrase(
    String passphrase, {
    String? customDbPath,
    String? customVaultPath,
    String? customWipeBaseDir,
    bool loadState = true,
    bool? requireEncryption,
  }) async {
    final result = await _keyVault.unlockOrDuress(
      passphrase: passphrase,
      customPath: customVaultPath,
    );
    if (result.status == VaultUnlockStatus.duressTriggered) {
      await panicWipeAllData(customBaseDir: customWipeBaseDir);
      return result;
    }
    _activeMasterKey = Uint8List.fromList(result.masterKey!);
    _localDatabase = await LocalDatabase.open(
      path: customDbPath,
      rawCipherKey: Uint8List.fromList(result.masterKey!),
      requireEncryption: requireEncryption ??
          (!Platform.environment.containsKey('FLUTTER_TEST') ||
              Platform.environment['NIX_REQUIRE_SQLCIPHER'] == 'true'),
    );
    _securityContext = _securityContext.copyWith(
      isSqlCipherUnlocked: _localDatabase!.cipherInfo.isEncrypted,
      status: SecuritySubsystemState.ready,
    );
    _instantiateRepositories();
    _requiresPassphraseUnlock = false;
    if (loadState) {
      await reloadFromDatabase();
    }
    notifyListeners();
    return result;
  }

  /// Tenta desbloquear o KeyVault via chaveiro nativo do SO (libsecret / AndroidKeyStore)
  /// e restaurar toda a conta (identidade, perfil, contatos, mensagens salvas) na inicialização.
  Future<bool> tryAutoUnlockAndRestore({
    String? customDbPath,
    String? customVaultPath,
    bool? requireEncryption,
  }) async {
    try {
      final initialized = await _keyVault.isInitialized(customPath: customVaultPath);
      if (!initialized) return false;

      final masterKey = await _keyVault.tryUnlockWithOsKeyring(
        customPath: customVaultPath,
      );
      if (masterKey == null) {
        _requiresPassphraseUnlock = true;
        notifyListeners();
        return false;
      }

      _activeMasterKey = Uint8List.fromList(masterKey);
      _localDatabase = await LocalDatabase.open(
        path: customDbPath,
        rawCipherKey: Uint8List.fromList(masterKey),
        requireEncryption: requireEncryption ??
            (!Platform.environment.containsKey('FLUTTER_TEST') ||
                Platform.environment['NIX_REQUIRE_SQLCIPHER'] == 'true'),
      );
      _securityContext = _securityContext.copyWith(
        isSqlCipherUnlocked: _localDatabase!.cipherInfo.isEncrypted,
        status: SecuritySubsystemState.ready,
      );
      _instantiateRepositories();
      _requiresPassphraseUnlock = false;
      await reloadFromDatabase();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[NixState] Falha ao desbloquear automaticamente pelo SO: $e');
      return false;
    }
  }

  /// Persiste a identidade soberana Seed A (pública em `identities` + semente envelopada em `key_material`),
  /// registra o dispositivo principal, salva o perfil local e garante a conversa de Mensagens Salvas.
  Future<void> persistPrimaryIdentity({
    required NixIdentity identity,
    required String displayName,
    String bio = '',
    String avatarStyle = 'nyx_emblem',
  }) async {
    _primaryIdentity = identity;
    final cleanName = displayName.trim().isEmpty ? 'Soberano Nix' : displayName.trim();
    _userProfile = _userProfile.copyWith(
      publicId: identity.publicId,
      displayName: cleanName,
      bio: bio,
      avatarStyle: avatarStyle,
    );
    _securityContext = _securityContext.copyWith(
      status: _localDatabase != null
          ? SecuritySubsystemState.ready
          : _securityContext.status,
      isSqlCipherUnlocked: _localDatabase?.cipherInfo.isEncrypted ?? false,
      myFingerprint: identity.publicId,
      myPersona: cleanName,
    );
    _rebuildSovereignMessenger();

    if (_localDatabase != null && _identityRepo != null && _keyMaterialRepo != null) {
      final edPub = Uint8List.fromList(identity.ed25519PublicKey.bytes);
      final xPub = Uint8List.fromList(identity.x25519PublicKey.bytes);
      final edData = await identity.ed25519KeyPair.extract();
      final xData = await identity.x25519KeyPair.extract();
      final secretJson = utf8.encode(jsonEncode({
        'publicId': identity.publicId,
        'edSeed': base64Encode(edData.bytes),
        'xSeed': base64Encode(xData.bytes),
      }));
      final wrapKey = await _deriveWrappingKey('Nix-IdentityWrap-v1');
      final sealed = await SealedEnvelope.seal(
        key: wrapKey,
        plaintext: secretJson,
        aad: utf8.encode('identity:${identity.publicId}'),
      );

      await _keyMaterialRepo!.storeKeyMaterial(
        id: 'vault:identity_main',
        purpose: 'identity_seed_a',
        wrappedBytes: sealed.encode(),
        wrappingKeyRef: 'keyvault:master',
      );

      final existing = await _identityRepo!.getPrimaryIdentity();
      if (existing == null) {
        await _identityRepo!.createIdentity(
          id: identity.publicId,
          publicId: identity.publicId,
          edPublic: edPub,
          xPublic: xPub,
          keyRef: 'vault:identity_main',
        );
      }

      final devices = await _identityRepo!.listDevices(identity.publicId);
      if (devices.isEmpty) {
        final grantSig = await identity.sign(
          utf8.encode('nix-device-grant:${identity.publicId}:$_localDeviceId'),
        );
        await _identityRepo!.registerDevice(
          deviceId: _localDeviceId,
          identityId: identity.publicId,
          signingPublic: edPub,
          grant: Uint8List.fromList(grantSig),
        );
      } else {
        _localDeviceId = devices.first['id'] as String;
      }

      await _identityRepo!.saveProfile(
        identityId: identity.publicId,
        displayName: cleanName,
        bio: bio,
        avatarObjectId: avatarStyle,
      );

      // Emite Card ID público assinado (revision 1) na tabela `cards`
      final cardPayload = utf8.encode(jsonEncode({
        'publicId': identity.publicId,
        'ed': base64Encode(edPub),
        'x': base64Encode(xPub),
        'name': cleanName,
        'rev': 1,
      }));
      final cardSig = await identity.sign(cardPayload);
      await _identityRepo!.saveCard(
        id: 'card_${identity.publicId}_r1',
        identityId: identity.publicId,
        revision: 1,
        publicBundle: Uint8List.fromList(cardPayload),
        signature: Uint8List.fromList(cardSig),
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)).millisecondsSinceEpoch,
      );

      // Garante a existência da conversa `dm_saved_messages` no SQLCipher
      final savedConv = await _conversationRepo!.getConversation('dm_saved_messages');
      if (savedConv == null) {
        await _conversationRepo!.createConversation(
          id: 'dm_saved_messages',
          kind: 'saved',
          ownerIdentityId: identity.publicId,
          title: 'Mensagens Salvas',
        );
      }
      _rebuildSovereignMessenger();
    }

    // Sincroniza thread Mensagens Salvas em memória com o publicId real
    final savedIdx = _directMessages.indexWhere((d) => d.id == 'dm_saved_messages');
    if (savedIdx != -1) {
      _directMessages[savedIdx] = _directMessages[savedIdx].copyWith(
        peerPublicId: identity.publicId,
      );
      if (_selectedDm?.id == 'dm_saved_messages') {
        _selectedDm = _directMessages[savedIdx];
      }
    }

    notifyListeners();
  }

  /// Recarrega identidade, perfil, contatos, conversas, estado criptográfico e mensagens após reinicialização.
  Future<void> reloadFromDatabase() async {
    await _startupPreferences;
    await flushPreferences();
    await _restoreWorkspaceLayout();
    await _restoreForum();
    await _restoreLocalGroupPolls();
    await _migrateLegacyAcervo();
    final restoredAvatarStyle = await _restorePersonalPreferences();
    if (_localDatabase == null || _identityRepo == null) return;

    // 1. Varre mensagens efêmeras expiradas antes de montar o estado em memória
    await _messageRepo?.sweepExpiredMessages();

    final primaryRow = await _identityRepo!.getPrimaryIdentity();
    if (primaryRow == null) return;

    final identityId = primaryRow['id'] as String;
    final publicId = primaryRow['public_id'] as String;
    final keyRef = primaryRow['key_ref'] as String;

    // 2. Desempacota o Seed A privado protegido em `key_material`
    final matRow = await _keyMaterialRepo?.getKeyMaterial(keyRef);
    if (matRow != null && _activeMasterKey != null) {
      final wrapKey = await _deriveWrappingKey('Nix-IdentityWrap-v1');
      final sealed = SealedPayload.decode(
        Uint8List.fromList(matRow['wrapped_bytes'] as List<int>),
      );
      final clear = await SealedEnvelope.open(
        key: wrapKey,
        payload: sealed,
        aad: utf8.encode('identity:$publicId'),
      );
      final decoded = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      final edSeed = base64Decode(decoded['edSeed'] as String);
      final xSeed = base64Decode(decoded['xSeed'] as String);
      final restoredIdentity = await NixIdentity.fromSeeds(
        ed25519Seed: edSeed,
        x25519PrivateBytes: xSeed,
      );
      _primaryIdentity = restoredIdentity;
      _securityContext = _securityContext.copyWith(
        status: SecuritySubsystemState.ready,
        isSqlCipherUnlocked: _localDatabase!.cipherInfo.isEncrypted,
        myFingerprint: restoredIdentity.publicId,
      );
    }

    final devices = await _identityRepo!.listDevices(identityId);
    if (devices.isNotEmpty) {
      _localDeviceId = devices.first['id'] as String;
    }

    _rebuildSovereignMessenger();

    final profileRow = await _identityRepo!.getProfile(identityId);
    final restoredName =
        (profileRow?['display_name'] as String?) ?? _userProfile.displayName;
    _securityContext = _securityContext.copyWith(myPersona: restoredName);
    _userProfile = _userProfile.copyWith(
      publicId: publicId,
      displayName: restoredName,
      bio: (profileRow?['bio'] as String?) ?? _userProfile.bio,
      avatarStyle: restoredAvatarStyle ??
          (profileRow?['avatar_object_id'] as String?) ?? _userProfile.avatarStyle,
    );

    await _restoreRelayConfiguration();

    // 3. Restaura contatos verificados e conversas diretas / Mensagens Salvas
    await _refreshDirectThreadsFromDatabase(publicId: publicId);

    // 4. Restaura Acervo Cultural persistido em media_items
    final mediaRows = await _mediaRepo?.listMediaItems(limit: 200) ?? [];
    if (mediaRows.isNotEmpty) {
      final items = <CulturalItem>[];
      for (final row in mediaRows) {
        try {
          final meta = jsonDecode(row['metadata_json'] as String) as Map<String, dynamic>;
          items.add(CulturalItem.fromJson(meta));
        } catch (_) {}
      }
      if (items.isNotEmpty) {
        _userProfile = _userProfile.copyWith(culturalItems: items);
      }
    }

    // 5. Restaura favoritos do GitHub Discovery (Starwire) persistidos no SQLCipher
    final rawSavedIds = await _preferencesRepo?.getOption(NixPreferenceStore.savedAcervoKey);
    if (rawSavedIds is List) {
      try {
        final ids = rawSavedIds.map((e) => e.toString()).toSet();
        _savedAcervoIds
          ..clear()
          ..addAll(ids);
        _githubRepos = _githubRepos
            .map((r) => r.copyWith(isSavedInAcervo: _savedAcervoIds.contains(r.id)))
            .toList();
        _starwireFilters.updateRepos(_githubRepos);
      } catch (_) {}
    }

    // 6. Restaura anúncios Monero P2P assinados localmente e valida assinaturas Ed25519
    final rawOrders = await _preferencesRepo?.getOption('monero_local_orders_v1');
    if (rawOrders is List) {
      try {
        for (final item in rawOrders.reversed) {
          if (item is Map<String, dynamic>) {
            final order = MoneroP2pOrder.fromJson(item);
            final ok = await SignedMoneroAd.verifyOrderCryptographically(order);
            if (ok && !_moneroOrders.any((o) => o.id == order.id)) {
              _moneroOrders.insert(0, order.copyWith(isSignatureVerified: true));
            }
          }
        }
        _moneroFilters.updateOrders(_moneroOrders);
      } catch (_) {}
    }

    _isOnboarded = true;
    await _restoreScheduledMessages();
    notifyListeners();
  }

  /// Sincroniza threads de Mensagens Salvas e conversas diretas a partir do banco SQLCipher,
  /// preservando estados reais (`queued`, `accepted`, `delivered`, `failed`, `saved`) e sessões ativas.
  Future<void> _refreshDirectThreadsFromDatabase({String? publicId}) async {
    if (_localDatabase == null || _conversationRepo == null || _messageRepo == null) {
      return;
    }
    final myPublicId = publicId ?? _userProfile.publicId;
    final conversations = await _conversationRepo!.listConversations();
    final savedIdx = _directMessages.indexWhere((d) => d.id == 'dm_saved_messages');
    if (savedIdx != -1) {
      final savedRows = await _messageRepo!.getMessagesForConversation(
        'dm_saved_messages',
        limit: 200,
      );
      final loadedSavedMsgs = <Message>[];
      for (final r in savedRows) {
        final msgId = r['id'] as String;
        final attRows = await _localDatabase!.rawDatabase.query(
          'attachments',
          where: 'message_id = ?',
          whereArgs: [msgId],
          orderBy: 'ordinal ASC',
        );
        final attNames = attRows
            .map((a) => (a['file_name'] as String?) ?? (a['object_id'] as String))
            .toList();
        loadedSavedMsgs.add(
          Message(
            id: msgId,
            channelId: 'dm_saved_messages',
            senderName: _userProfile.effectiveDisplayName,
            senderFingerprint: _securityContext.myFingerprint,
            isMe: (r['author_key'] as String) == myPublicId,
            text: (r['body'] as String?) ?? '',
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              r['created_at'] as int,
              isUtc: true,
            ),
            isVerified: true,
            deliveryState: 'saved',
            attachments: attNames,
          ),
        );
      }

      final baseWelcome = _directMessages[savedIdx]
          .messages
          .where((m) => m.id == 'saved_welcome')
          .toList();
      _directMessages[savedIdx] = _directMessages[savedIdx].copyWith(
        peerPublicId: myPublicId,
        messages: [...baseWelcome, ...loadedSavedMsgs],
      );
      if (_selectedDm?.id == 'dm_saved_messages') {
        _selectedDm = _directMessages[savedIdx];
      }
    }

    for (final conv in conversations) {
      final cid = conv['id'] as String;
      if (cid == 'dm_saved_messages') continue;
      if ((conv['kind'] as String) == 'direct') {
        final existingIdx = _directMessages.indexWhere((d) => d.id == cid);
        final sessionRow = await _sessionRepo?.getSessionByConversation(cid);
        final sessionMeta = await _sovereignMessenger?.getSessionMetadata(cid);
        final hasSession = sessionRow != null && sessionMeta != null;
        final invitedPeer = cid.startsWith('dm_pair_')
            ? cid.split('_').skip(2).where((id) => id != myPublicId).firstOrNull
            : null;
        final existingPeerId = (sessionMeta?['peerPublicId'] as String?) ??
            (existingIdx != -1 ? _directMessages[existingIdx].peerPublicId : invitedPeer ?? cid);
        final peerContact = await _contactRepo?.getContact(existingPeerId);
        final isVerified = hasSession && peerContact?['verification'] == 'verified';
        if (hasSession && _sovereignMessenger != null) {
          _directPolls[cid] = await _sovereignMessenger!.directPollsFor(cid, existingPeerId);
        } else {
          _directPolls.remove(cid);
        }
        if (isVerified && _sovereignMessenger != null) {
          _sharedGroupPollThreads[cid] =
              await _sovereignMessenger!.sharedGroupPollsFor(cid, existingPeerId);
        } else {
          _sharedGroupPollThreads.remove(cid);
        }
        final existingPeerMailbox = (sessionMeta?['peerMailbox'] as String?) ??
            (existingIdx != -1 ? _directMessages[existingIdx].peerMailboxId : null) ??
            SovereignMessenger.deriveMailboxCredentials(existingPeerId).mailboxId;
        final msgRows = await _messageRepo!.getLatestMessagesForConversation(cid);
        final msgs = <Message>[];
        for (final r in msgRows) {
          final body = (r['body'] as String?) ?? '';
          if (body.startsWith(SharedGroupPollPacket.prefix)) continue;
          final msgId = r['id'] as String;
          final rawState = (r['delivery_state'] as String?) ?? 'queued';
          final isMe = (r['author_key'] as String) == myPublicId;
          final mappedState = rawState == 'received' ? 'delivered' : rawState;
          final attRows = await _localDatabase!.rawDatabase.query(
            'attachments',
            where: 'message_id = ?',
            whereArgs: [msgId],
            orderBy: 'ordinal ASC',
          );
          final attNames = attRows
              .map((a) => (a['file_name'] as String?) ?? (a['object_id'] as String))
              .toList();
          msgs.add(
            Message(
              id: msgId,
              channelId: cid,
              senderName: isMe
                  ? _userProfile.effectiveDisplayName
                  : (conv['title'] as String),
              senderFingerprint: r['author_key'] as String,
              isMe: isMe,
              text: body,
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                r['created_at'] as int,
                isUtc: true,
              ),
              isVerified: isVerified && mappedState != 'failed',
              deliveryState: mappedState,
              deliveryError: mappedState == 'failed'
                  ? 'Falha no envio do envelope ao relay.'
                  : null,
              attachments: attNames,
            ),
          );
        }

        final thread = DirectMessageThread(
          id: cid,
          peerName: conv['title'] as String,
          peerPublicId: existingPeerId,
          peerMailboxId: existingPeerMailbox,
          hasActiveSession: hasSession,
          statusText: hasSession
              ? 'Sessão E2EE preparada'
              : 'Aguardando a primeira mensagem cifrada do contato',
          isOnline: false,
          isVerified: isVerified,
          trustLevel: isVerified ? NixTrustLevel.level3Green : NixTrustLevel.level1Red,
          unreadCount: 0,
          messages: msgs,
        );
        if (existingIdx == -1) {
          _directMessages.add(thread);
        } else {
          _directMessages[existingIdx] = thread;
        }
        if (_selectedDm?.id == cid) {
          _selectedDm = thread;
        }
      }
    }
  }

  /// Envia mensagem com garantia de persistência local atômica no SQLCipher,
  /// enfileiramento na Outbox e difusão via Bluetooth Mesh e/ou Relay Onion (P0-5).
  Future<bool> sendSovereignMessage({
    required String conversationId,
    required String text,
    String? recipientMailbox,
    Uint8List? recipientX25519PublicKey,
    List<String> attachments = const [],
  }) async {
    if (text.trim().isEmpty && attachments.isEmpty) return false;

    // Este transporte genérico não verifica associação nem aprovação de canais.
    if (_findChannel(conversationId) != null) return false;

    final now = DateTime.now().toUtc();
    final messageId = 'msg_${now.millisecondsSinceEpoch}';

    // 1. Cria representação em memória para resposta instantânea da interface
    final newMessage = Message(
      id: messageId,
      channelId: conversationId,
      senderName: _userProfile.effectiveDisplayName,
      senderFingerprint: _securityContext.myFingerprint,
      isMe: true,
      text: text.trim(),
      timestamp: now,
      ephemeralSeconds: _selectedEphemeralTimer,
      remainingSeconds: _selectedEphemeralTimer,
      isVerified: true,
      attachments: attachments,
    );

    if (!_messages.containsKey(conversationId)) {
      _messages[conversationId] = [];
    }
    _messages[conversationId]!.add(newMessage);
    notifyListeners();

    // 2. Se o banco SQLCipher estiver pronto, persiste de forma atômica na tabela messages + FTS5
    if (_localDatabase != null && _messageRepo != null) {
      try {
        await _messageRepo!.insertMessage(
          id: messageId,
          conversationId: conversationId,
          authorKey: _userProfile.publicId,
          deviceId: 'local_client_dev',
          body: text.trim(),
          deliveryState: 'queued',
        );
      } catch (e) {
        debugPrint('[NixState] Aviso ao salvar mensagem no banco local: $e');
      }
    }

    // 3. Serializa e cifra o envelope da mensagem (fail-closed: nunca grava plaintext em outbox.ciphertext)
    Uint8List payloadBytes;
    final clearJson = jsonEncode({
      'id': messageId,
      'sender': _userProfile.publicId,
      'text': text.trim(),
      'ts': now.millisecondsSinceEpoch,
      'attachments': attachments.map(LocalImageHelper.getFileName).toList(),
    });
    final clearBytes = utf8.encode(clearJson);

    if (recipientX25519PublicKey != null) {
      try {
        final ephemeralKp = await X25519().newKeyPair();
        final sharedSecret = await X25519().sharedSecretKey(
          keyPair: ephemeralKp,
          remotePublicKey: SimplePublicKey(recipientX25519PublicKey, type: KeyPairType.x25519),
        );
        final sealed = await SealedEnvelope.seal(
          key: sharedSecret,
          plaintext: clearBytes,
        );
        final ephemPub = await ephemeralKp.extractPublicKey();
        final builder = BytesBuilder(copy: false)
          ..add(ephemPub.bytes)
          ..add(sealed.encode());
        payloadBytes = builder.toBytes();
      } catch (e) {
        debugPrint('[NixState] Fail-Closed E2EE ao cifrar para destinatário: $e');
        return false;
      }
    } else if (_activeMasterKey != null) {
      // Envelope selado local com chave derivada do cofre ativo quando ainda não há prekey X25519 do par
      try {
        final outboxKey = await _deriveWrappingKey('Nix-OutboxEnvelope-v1');
        final sealed = await SealedEnvelope.seal(
          key: outboxKey,
          plaintext: clearBytes,
          aad: utf8.encode('conv:$conversationId'),
        );
        payloadBytes = sealed.encode();
      } catch (e) {
        debugPrint('[NixState] Fail-Closed ao selar envelope da outbox: $e');
        return false;
      }
    } else {
      debugPrint('[NixState] Fail-Closed: tentativa de envio sem chave E2EE nem KeyVault desbloqueado.');
      return false;
    }

    // 4. Enfileira na Outbox local com delivery ID e payload_hash estáveis
    final outboxId = 'out_${now.millisecondsSinceEpoch}';
    final destMailbox = recipientMailbox ?? 'mailbox_${conversationId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
    final expiresAt = now.add(const Duration(days: 7)).millisecondsSinceEpoch;

    if (_localDatabase != null && _outboxRepo != null) {
      try {
        await _outboxRepo!.enqueue(
          id: outboxId,
          destinationMailbox: destMailbox,
          ciphertext: payloadBytes,
          expiresAt: expiresAt,
        );
      } catch (e) {
        debugPrint('[NixState] Aviso ao enfileirar na outbox: $e');
      }
    }

    // 5. Se o modo Malha Bluetooth estiver ativo, transmite aos nós vizinhos
    if (_bluetoothMesh.isMeshEnabled) {
      try {
        await _bluetoothMesh.broadcastEnvelope(
          recipientCardId: conversationId,
          payload: payloadBytes,
        );
      } catch (e) {
        debugPrint('[NixState] Aviso ao transmitir via malha Bluetooth: $e');
      }
    }

    return true;
  }

  /// Processa recebimento de envelope cifrado aplicando deduplicação estrita (inbox_dedup),
  /// decifração e commit atômico no banco local antes de qualquer confirmação (ACK).
  Future<bool> processInboundEnvelope({
    required String mailboxId,
    required String deliveryId,
    required Uint8List ciphertext,
    int? expiresAt,
    SecretKeyData? sessionKey,
  }) async {
    if (_findChannel(mailboxId) != null) return false;

    final now = DateTime.now().toUtc();
    final exp = expiresAt ?? now.add(const Duration(days: 7)).millisecondsSinceEpoch;
    final payloadHash = Uint8List.fromList(std_crypto.sha256.convert(ciphertext).bytes);

    // 1. Deduplicação estrita: se já processado, descarta para evitar replay (Gate P0-5)
    if (_localDatabase != null && _outboxRepo != null) {
      if (await _outboxRepo!.isDuplicateEnvelope(mailboxId, deliveryId)) {
        return false;
      }
    }

    // 2. Decifra e autentica o payload antes de persistir ou emitir deduplicação/ACK
    String plaintext = '';
    String senderId = 'desconhecido';
    final String conversationId = mailboxId;
    List<String> attachments = [];

    try {
      if (sessionKey == null) {
        debugPrint('[NixState] Fail-Closed: envelope recebido sem chave de sessão autenticada.');
        return false;
      }
      final sealed = SealedPayload.decode(ciphertext);
      final clear = await SealedEnvelope.open(key: sessionKey, payload: sealed);
      final map = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      plaintext = map['text'] as String? ?? '';
      senderId = map['sender'] as String? ?? 'desconhecido';
      attachments = (map['attachments'] as List?)?.cast<String>() ?? [];
    } catch (e) {
      debugPrint('[NixState] Fail-Closed: falha ao autenticar/decifrar envelope de entrada: $e');
      return false;
    }

    // 3. Commit-before-ACK: persiste mensagem e registra dedup atomicamente no banco local
    final msgId = 'in_${now.millisecondsSinceEpoch}_$deliveryId';
    if (_localDatabase != null && _messageRepo != null && _outboxRepo != null) {
      await _localDatabase!.rawDatabase.transaction((txn) async {
        await txn.insert('messages', {
          'id': msgId,
          'conversation_id': conversationId,
          'author_key': senderId,
          'device_id': 'remote_client_dev',
          'body': plaintext,
          'created_at': now.millisecondsSinceEpoch,
          'received_at': now.millisecondsSinceEpoch,
          'revision': 1,
          'delivery_state': 'received',
        });
        await txn.insert('inbox_dedup', {
          'mailbox_id': mailboxId,
          'delivery_id': deliveryId,
          'payload_hash': payloadHash,
          'committed_at': now.millisecondsSinceEpoch,
          'expires_at': exp,
        });
      });
    }

    // 4. Atualiza a lista em memória para refletir na UI
    final incomingMsg = Message(
      id: msgId,
      channelId: conversationId,
      senderName: senderId,
      senderFingerprint: '',
      isMe: false,
      text: plaintext,
      timestamp: now,
      isVerified: true,
      attachments: attachments,
    );

    if (!_messages.containsKey(conversationId)) {
      _messages[conversationId] = [];
    }
    _messages[conversationId]!.add(incomingMsg);
    notifyListeners();
    return true;
  }

  NixState({bool? loadMockData, KeyVault? keyVault, bool? enforceStartupGate}) {
    _keyVault = keyVault ?? KeyVault();
    final isTest = Platform.environment['FLUTTER_TEST'] == 'true';
    final shouldLoadMock = loadMockData ?? isTest;
    _isMockMode = shouldLoadMock;
    _enforceStartupGate = enforceStartupGate ?? (!shouldLoadMock && !isTest);

    if (shouldLoadMock) {
      _loadMockFixtures();
      _isOnboarded = true;
    } else {
      _initializeProductionCleanState();
    }
    _starwireFilters = StarwireFilterViewModel(initialRepos: _githubRepos);
    _moneroFilters = MoneroOrderFilterViewModel(initialOrders: _moneroOrders);
    _navigation = NavigationViewModel(
      initialArea: _activeArea,
      initialSubTab: _homeSubTab,
      initialFolderId: _activeFolderId,
      initialFilter: _conversationFilter,
    );
    _settingsVm = SettingsViewModel(
      initialSettings: _settings,
    );
    _chatVm = ChatViewModel(
      initialDirectMessages: _directMessages,
      initialMessages: _messages,
    );
    _identityVm = IdentityViewModel(
      initialIdentity: _primaryIdentity,
      initialProfile: _userProfile,
      initialSecurityContext: _securityContext,
      localDeviceId: _localDeviceId,
    );
    _mediaVm = MediaViewModel(
      catalogService: _mediaCatalogService,
      catalogDatabase: _catalogDatabase,
      updateManager: _catalogUpdateManager,
      initialSavedIds: _savedAcervoIds,
    );
    _archiveVm = ArchiveViewModel(
      archiveService: _archiveService,
      archiveRepo: _archiveRepo,
      replicationCoordinator: _replicationCoordinator,
      initialPublications: _publications,
    );
    NixColors.sync(
      NixSurfaceScheme.resolve(_settings.themeMode),
      currentPalette,
    );
    if (!shouldLoadMock) {
      _startupPreferences = loadPersistedState();
      _attachHardwareRadioListeners();
      if (!isTest) {
        unawaited(_bootstrapFromPreferences());
      } else {
        _checkPersistedOnboardingStatus();
      }
    }
  }

  void _attachHardwareRadioListeners() {
    _hardwareRadioBridge.attach();
    _blePeerSub?.cancel();
    _blePeerSub = _bluetoothMesh.onPeerDiscovered.listen((_) {
      if (!_disposed) notifyListeners();
    });
    _bleRxSub?.cancel();
    _bleRxSub = _bluetoothMesh.onEnvelopeReceived.asyncMap<void>((env) async {
      if (_disposed) return;
      final fromAddr = (env['fromAddress'] as String?) ?? 'ble_peer';
      final rawCt = env['ciphertext'] as Uint8List?;
      if (rawCt == null) return;
      final deliveryId = env['deliveryId'] as String;
      if (deliveryId.startsWith('out_')) {
        final messenger = _sovereignMessenger;
        if (!_isStrictOffGridMode || messenger == null) return;
        final mailbox = (_activeMailboxCredentials ??
                SovereignMessenger.deriveMailboxCredentials(
                  messenger.identity.publicId,
                ))
            .mailboxId;
        if (env['destinationMailbox'] != mailbox) return;
        try {
          final result = await messenger.commitNearbyDelivery(
            mailboxId: mailbox,
            deliveryId: deliveryId,
            ciphertext: rawCt,
            expiresAtMs: env['expiresAt'] as int,
          );
          if (_disposed || result.committed.isEmpty) return;
          await _refreshDirectThreadsFromDatabase();
          if (!_disposed) notifyListeners();
        } catch (_) {
          // Captura de rádio não autenticada nunca entra no histórico.
        }
        return;
      }
      String summary = 'Envelope NIXB (${rawCt.length}B) recebido de $fromAddr';
      try {
        final decoded = jsonDecode(utf8.decode(rawCt));
        if (decoded is Map<String, dynamic> &&
            decoded['msg'] is String &&
            decoded['edPub'] is String &&
            decoded['sig'] is String) {
          final msgText = decoded['msg'] as String;
          final edHex = decoded['edPub'] as String;
          final sigBytes = base64Decode(decoded['sig'] as String);
          final pubBytes = _hexToBytes(edHex);
          final ok = await Ed25519().verify(
            utf8.encode(msgText),
            signature: Signature(
              sigBytes,
              publicKey: SimplePublicKey(pubBytes, type: KeyPairType.ed25519),
            ),
          );
          final sender = (decoded['from'] as String?) ?? fromAddr;
          summary = ok
              ? '[Ed25519 VERIFICADO] de $sender ($fromAddr): "$msgText"'
              : '[ASSINATURA INVÁLIDA] de $sender ($fromAddr)';
        }
      } catch (_) {}
      _appendHardwareRadioLog(HardwareRadioLogEntry(
        timestamp: DateTime.now().toUtc(),
        medium: 'BLE',
        direction: 'RX',
        summary: summary,
      ));
    }).listen(null);
  }

  static List<int> _hexToBytes(String hex) {
    final clean = hex.trim();
    final out = <int>[];
    for (int i = 0; i + 1 < clean.length; i += 2) {
      out.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  void _loadMockFixtures() {
    _spaces = MockData.getInitialSpaces();
    _folders = MockData.getInitialFolders();
    _discoverableSpaces = MockData.getDiscoverablePublicSpaces();
    _currentSpace = _spaces.first;
    _currentChannel = _currentSpace.channels.first;
    _messages = MockData.getInitialMessages();
    _publications = MockData.getInitialPublications();
    _forumPosts = MockData.getInitialForumPosts();
    _selectedForumPost = _forumPosts.first;
    _members = MockData.getInitialMembers();
    _userProfile = MockData.getInitialUserProfile();
    _directMessages = MockData.getInitialDirectMessages();
    _contactRequests = MockData.getInitialContactRequests();
    _transactions = MockData.getInitialTransactions();
    _systemUpdates = MockData.getInitialSystemUpdates();
    _moneroOrders = MockData.getInitialMoneroOrders();
    for (final order in _moneroOrders) {
      SignedMoneroAd.registerPreVerifiedOrder(order);
    }
    _githubRepos = MockData.getInitialGithubRepos();
  }

  void _initializeProductionCleanState() {
    _userProfile = const UserProfile(
      publicId: '',
      displayName: '',
      bio: '',
      currentActivity: '',
      memberSinceYear: '26',
      avatarStyle: 'nyx_emblem',
      culturalItems: [],
    );
    const defaultChannel = Channel(
      id: 'general_saved',
      spaceId: 'local_space',
      name: 'geral',
      topic: 'Canal local soberano',
      category: 'GERAL',
      type: ChannelType.text,
      description: 'Canal local soberano.',
    );
    const defaultSpace = Space(
      id: 'local_space',
      name: 'Nix Local',
      initials: 'NX',
      description: 'Espaço local soberano',
      channels: [defaultChannel],
    );
    _spaces = [defaultSpace];
    _currentSpace = defaultSpace;
    _currentChannel = defaultChannel;
    _discoverableSpaces = [];
    _folders = [
      const SpaceFolder(
        id: 'all',
        name: 'Todas',
        iconName: 'folder',
        spaceIds: ['local_space'],
        conversationIds: ['dm_saved_messages'],
      ),
    ];
    _messages = {};
    _publications = {};
    _forumPosts = [];
    _members = [
      Member(
        id: 'me',
        name: _userProfile.effectiveDisplayName,
        roleName: 'Proprietário',
        role: MemberRole.admin,
        fingerprint: _securityContext.myFingerprint,
        isOnline: true,
      ),
    ];
    _contactRequests = [];
    _transactions = [];
    _systemUpdates = [];
    _moneroOrders = [];
    _githubRepos = [];

    // Mensagens Salvas (Cofre Pessoal Real e Cifrado)
    _directMessages = [
      DirectMessageThread(
        id: 'dm_saved_messages',
        peerName: 'Mensagens Salvas',
        peerPublicId: _userProfile.publicId,
        statusText: 'Cofre Pessoal Cifrado · Notas & Arquivo Local',
        isOnline: true,
        isVerified: true,
        trustLevel: NixTrustLevel.level3Green,
        isSavedMessages: true,
        isPinned: true,
        unreadCount: 0,
        messages: [
          Message(
            id: 'saved_welcome',
            channelId: 'dm_saved_messages',
            senderName: _userProfile.effectiveDisplayName,
            senderFingerprint: _securityContext.myFingerprint,
            isMe: true,
            isPinned: true,
            text: 'Bem-vindo ao seu cofre de Mensagens Salvas do Projeto Nix.\n\n'
                '• Todas as notas e arquivos salvos aqui são cifrados localmente no banco SQLCipher.\n'
                '• Roteamento Tor Onion v3 ativo e fail-closed por padrão.\n'
                '• Suas mensagens não passam por servidores nem coletam telemetria.',
            timestamp: DateTime.now().toUtc(),
            attachments: const [],
          ),
        ],
      ),
    ];
    _selectedDm = _directMessages.first;
    _homeSubTab = HomeSubTab.cardId;
    _activeArea = NixActiveArea.homePrivate;
  }

  Future<void> _checkPersistedOnboardingStatus() async {
    try {
      // 1. Tenta desbloqueio automático via chaveiro nativo do SO (libsecret / AndroidKeyStore TEE)
      final unlocked = await tryAutoUnlockAndRestore();
      if (unlocked) {
        return;
      }

      // 2. Política Fail-Closed: nunca marca a conta como pronta sem cofre SQLCipher real desbloqueado.
      // Se existe cofre no disco mas o chaveiro do SO não o abriu, exige frase-passe explícita.
      final vaultExists = await _keyVault.isInitialized();
      if (vaultExists) {
        _requiresPassphraseUnlock = true;
        notifyListeners();
        return;
      }

      // 3. Apenas em ambiente de testes isolados permite pré-preencher metadados de snapshot.
      if (Platform.environment['FLUTTER_TEST'] == 'true') {
        final snapshot = await OnboardingStateSnapshot.load();
        if (snapshot.isCompleted) {
          _isOnboarded = true;
          if (snapshot.displayName != null && snapshot.displayName!.isNotEmpty) {
            _userProfile = _userProfile.copyWith(displayName: snapshot.displayName);
          }
          if (snapshot.avatarStyle != null && snapshot.avatarStyle!.isNotEmpty) {
            _userProfile = _userProfile.copyWith(avatarStyle: snapshot.avatarStyle);
          }
          if (snapshot.publicId != null && snapshot.publicId!.isNotEmpty) {
            _userProfile = _userProfile.copyWith(publicId: snapshot.publicId);
          }
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  final _preferenceStore = NixPreferenceStore();
  Future<void>? _startupPreferences;

  Future<void> _persistState(
      {bool workspaceChanged = false, bool reportErrors = false}) =>
      _preferenceStore.enqueue(
        () => _preferenceStore.write(
          repository: _preferencesRepo,
          settings: _settings,
          profile: _userProfile,
          spaces: _spaces,
          folders: _folders,
          workspaceChanged: workspaceChanged,
          mayWrite: () => _panicWipe == null,
        ),
        reportErrors: reportErrors,
      );

  Future<void> flushPreferences() => _preferenceStore.flush();

  ForumStore? get _forumStore {
    final repository = _preferencesRepo;
    if (_isMockMode || repository == null ||
        _localDatabase?.cipherInfo.isEncrypted != true) return null;
    return ForumStore(repository);
  }

  Future<void> _restoreLocalGroupPolls() async {
    final repository = _preferencesRepo;
    if (repository == null || _localDatabase?.cipherInfo.isEncrypted != true) return;
    try {
      final stored = await repository.getOption(_localGroupPollsKey);
      if (stored is! List || _disposed || _panicWipe != null) return;
      _localGroupPolls
        ..clear()
        ..addAll(stored.map(LocalGroupPoll.parse).nonNulls.where(
          (poll) => _findChannel(poll.channelId) != null,
        ));
    } catch (_) {
      // Preferências auxiliares não bloqueiam a abertura do cofre.
    }
  }

  bool canUseLocalGroupPolls(String channelId) {
    final channel = _currentChannel;
    return !_disposed && _panicWipe == null &&
        channel.id == channelId && channel.type == ChannelType.text &&
        (_isMockMode || _localDatabase?.cipherInfo.isEncrypted == true) &&
        channel.permissions.allowMessages && !_isLocallyBanned(channel) &&
        !channel.mutedMembers.contains(_ownWorkspaceIdentity) &&
        !channel.mutedMembers.contains(_securityContext.myFingerprint);
  }

  List<LocalGroupPoll> localGroupPollsFor(String channelId) =>
      _currentChannel.id != channelId || _isLocallyBanned(_currentChannel)
          ? const []
          : _localGroupPolls.where((poll) => poll.channelId == channelId).toList();

  String get localGroupPollActor => _ownWorkspaceIdentity;

  Future<void> createLocalGroupPoll(String channel, DirectPollSpec spec) =>
      _writeLocalGroupPolls(channel, (entries) {
        if (entries.where((poll) => poll.channelId == channel).length >= 30) {
          throw StateError('Limite de enquetes locais neste canal.');
        }
        final now = DateTime.now().toUtc();
        return [...entries, LocalGroupPoll(
          id: 'group-poll-${now.microsecondsSinceEpoch}',
          channelId: channel, creator: _ownWorkspaceIdentity, created: now, spec: spec,
        )];
      });

  Future<void> voteLocalGroupPoll(String channel, String id, List<int> choices) =>
      _changeLocalGroupPoll(channel, id,
        (poll) => poll.vote(_ownWorkspaceIdentity, choices, DateTime.now()));

  Future<void> closeLocalGroupPoll(String channel, String id) =>
      _changeLocalGroupPoll(channel, id, (poll) => poll.close(_ownWorkspaceIdentity));

  Future<void> _changeLocalGroupPoll(String channel, String id,
      LocalGroupPoll Function(LocalGroupPoll) change) =>
      _writeLocalGroupPolls(channel, (entries) {
        final index = entries.indexWhere((poll) => poll.id == id && poll.channelId == channel);
        if (index < 0) throw StateError('Enquete indisponível.');
        return List<LocalGroupPoll>.of(entries)..[index] = change(entries[index]);
      });

  Future<void> _writeLocalGroupPolls(String channel,
      List<LocalGroupPoll> Function(List<LocalGroupPoll>) write) {
    final repository = _preferencesRepo;
    return _preferenceStore.enqueue(() async {
      if (!canUseLocalGroupPolls(channel)) throw StateError('Canal indisponível.');
      final updated = write(_localGroupPolls);
      if (repository != null && !_isMockMode) {
        await repository.setOption(_localGroupPollsKey,
          updated.map((entry) => entry.toJson()).toList());
      }
      if (_disposed || _panicWipe != null) return;
      _localGroupPolls
        ..clear()
        ..addAll(updated);
      notifyListeners();
    }, reportErrors: true);
  }

  Future<void> _restoreForum() async {
    final store = _forumStore;
    if (store == null) return;
    try {
      final snapshot = await store.load();
      if (_disposed || _panicWipe != null) return;
      bool existingForum(String id) => _findChannel(id) != null;
      _forumPosts = snapshot.posts.where((post) => existingForum(post.channelId)).toList();
      _forumTags
        ..clear()
        ..addEntries(snapshot.tags.entries.where((entry) => existingForum(entry.key)));
      _selectedForumPost = currentForumPosts.firstOrNull;
    } catch (_) {
      // Uma falha auxiliar do fórum não impede a abertura do cofre.
    }
  }

  void _persistForum() {
    final store = _forumStore;
    if (store == null || _panicWipe != null || _disposed) return;
    final posts = List<ForumPost>.of(_forumPosts);
    final tags = _forumTags.map((channel, values) => MapEntry(channel, Map<String, String>.of(values)));
    unawaited(_preferenceStore.enqueue(() async {
      if (_panicWipe == null) await store.save(posts, tags);
    }, reportErrors: false));
  }


  Future<void> loadPersistedState() async {
    try {
      final raw = await _preferenceStore.readBootstrap();
      if (raw != null) {
        if (raw['settings'] is Map<String, dynamic>) {
          _settings = UserSettings.fromJson(raw['settings'] as Map<String, dynamic>);
          NixColors.sync(
            NixSurfaceScheme.resolve(_settings.themeMode),
            currentPalette,
          );
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _bootstrapFromPreferences() async {
    await _startupPreferences;
    if (_disposed) return;
    if (_settings.transportProfile.startsWith('Off-Grid')) {
      await enterStrictOffGridMode();
    } else {
      await bootstrapSovereignEnvironment();
    }
  }

  Future<void> _migrateLegacyAcervo() async {
    final repository = _preferencesRepo;
    final media = _mediaRepo;
    if (_localDatabase?.cipherInfo.isEncrypted != true || repository == null || media == null) return;
    try {
      await _preferenceStore.migrateLegacyAcervo(
        repository: repository,
        mayWrite: () => !_disposed && _panicWipe == null,
        importMissingItem: (entry) async {
          final item = CulturalItem.fromJson(entry);
          await media.upsertMediaItem(
            id: item.id,
            kind: _mapMediaKind(item.category),
            title: item.title,
            metadata: item.toJson(),
            source: 'local_acervo',
            sourceId: item.id,
            preserveExisting: true,
          );
        },
      );
    } catch (_) {
      // Os dados legados permanecem disponíveis para nova tentativa.
    }
  }

  Future<String?> _restorePersonalPreferences() async {
    final restored = await _preferenceStore.readPersonal(_preferencesRepo, _userProfile);
    if (restored == null) return null;
    if (restored.settings case final settings?) {
      _settings = settings;
      _calls.restoreMicrophone(settings.microphoneMuted);
      NixColors.sync(NixSurfaceScheme.resolve(settings.themeMode), currentPalette);
    }
    _userProfile = restored.profile;
    return restored.avatarStyle;
  }

  Future<void> _restoreWorkspaceLayout() async {
    final repo = _preferencesRepo;
    if (repo == null) return;
    try {
      final restored = await _preferenceStore.readWorkspace(repo);
      if (restored.spaces case final spaces? when spaces.isNotEmpty) {
        _spaces = spaces;
        _currentSpace = spaces.first;
        _currentChannel = _currentSpace.channels.first;
      }
      if (restored.folders case final folders?) _folders = folders;
    } catch (_) {}
  }

  Future<void>? _starwireLoad;

  /// Carrega o catálogo na primeira visita à descoberta.
  Future<void> loadStarwireRepos() => _starwireLoad ??= _loadStarwireRepos();

  Future<void> _loadStarwireRepos() async {
    if (_isMockMode) return;
    try {
      final raw = await rootBundle.loadString(
        'assets/data/starwire_repos.json',
        cache: false,
      );
      final repos = await compute(_parseStarwireRepos, raw);
      if (_disposed || repos.isEmpty) return;
      _githubRepos = repos.map((repo) {
        return _savedAcervoIds.contains(repo.id)
            ? repo.copyWith(isSavedInAcervo: true)
            : repo;
      }).toList();
      _starwireFilters.updateRepos(_githubRepos);
      notifyListeners();
    } catch (_) {
      // Permite retentar ao voltar à aba depois de uma falha de leitura.
      _starwireLoad = null;
    }
  }

  static List<GithubRepository> _parseStarwireRepos(String raw) {
    final data = jsonDecode(raw) as List<dynamic>;
    return [
      for (final row in data)
        GithubRepository.fromStarwireJson(row as Map<String, dynamic>),
    ];
  }

  // Getters principais
  List<Space> get spaces => _spaces;
  List<SpaceFolder> get folders => _folders;
  Space get currentSpace => _currentSpace;
  Channel get currentChannel => _currentChannel;

  List<Message> get activeConversationMessages {
    if (_activeArea == NixActiveArea.homePrivate &&
        _homeSubTab == HomeSubTab.directChat &&
        _selectedDm != null) {
      return _selectedDm!.messages;
    }
    return _messages[_currentChannel.id] ?? [];
  }

  List<Message> get currentMessages => _messages[_currentChannel.id] ?? [];
  List<Publication> get currentPublications => _publications[_currentChannel.id] ?? [];
  List<ForumPost> get currentForumPosts {
    if (_currentChannel.type != ChannelType.forum ||
        _isLocallyBanned(_currentChannel)) return [];
    return _forumPosts.where((p) => p.channelId == _currentChannel.id).toList();
  }
  ForumPost? get selectedForumPost {
    final post = _selectedForumPost;
    if (post == null || post.channelId != _currentChannel.id ||
        _currentChannel.type != ChannelType.forum ||
        _isLocallyBanned(_currentChannel)) return null;
    return post;
  }
  List<Member> get members => _members;
  CallState get callState => _calls.callState;
  SecurityContext get securityContext => _securityContext;
  UserProfile get userProfile => _userProfile;
  UserSettings get settings => _settings;
  NixThemeMode get themeMode => _settings.themeMode;

  NixPalette get currentPalette => NixPalette.fromType(
        _settings.paletteType,
        _settings.customPaletteColor != null ? Color(_settings.customPaletteColor!) : null,
      );

  NixActiveArea get activeArea => _activeArea;
  HomeSubTab get homeSubTab => _homeSubTab;
  List<DirectMessageThread> get directMessages => _directMessages;
  DirectMessageThread? get selectedDm => _selectedDm;
  DirectMessageThread get savedMessagesThread => _directMessages.firstWhere(
        (d) => d.isSavedMessages,
        orElse: () => _directMessages.first,
      );

  String get activeFolderId => _activeFolderId;
  ConversationFilter get conversationFilter => _conversationFilter;
  String get conversationSearchQuery => _conversationSearchQuery;
  bool get isWindowMaximized => _isWindowMaximized;

  List<ContactRequest> get contactRequests => _contactRequests;
  String? get hoverLockoutRequestId => _peerHover.hoverLockoutRequestId;

  List<XmrTransactionRecord> get transactions => _transactions;
  List<SystemUpdateRecord> get systemUpdates => _systemUpdates;
  List<MoneroP2pOrder> get moneroOrders => _moneroOrders;
  List<GithubRepository> get githubRepos => _githubRepos;

  bool get isProfileOverlayOpen => _isProfileOverlayOpen;
  bool get isSettingsOpenInOverlay => _isSettingsOpenInOverlay;
  SettingsCategory get activeSettingsCategory => _activeSettingsCategory;
  SettingsCategory? get requestedOverlaySettingsCategory => _requestedOverlaySettingsCategory;
  bool get isMembersPanelOpen => _isMembersPanelOpen;
  bool get isConversationInfoOpen => _isConversationInfoOpen;
  String get conversationHistorySearch => _conversationHistorySearch;
  int get selectedEphemeralTimer => _selectedEphemeralTimer;
  bool get exploreSortAscending => _exploreSortAscending;
  String get exploreSearchQuery => _exploreSearchQuery;

  Message? get replyingToMessage => _replyingToMessage;
  Message? get editingMessage => _editingMessage;
  Set<String> get selectedMessageIds => _selectedMessageIds;
  String? get highlightedMessageId => _highlightedMessageId;

  // Getters Tor Onion
  String get onionAddress => _onionAddress;
  bool get isTorRunning => _isTorRunning;
  String get torDiagnosticDetail => _torDiagnosticDetail;
  bool get isTorFailClosed => _settings.transportProfile.contains('Fail-Closed');

  /// Diagnóstico real de conectividade e handshake SOCKS5 + ControlPort do daemon Tor.
  Future<bool> checkTorDaemonStatus() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _isTorRunning = false;
      return false;
    }
    try {
      final cookiePath = '${_embeddedTor.dataDirectory}/control_auth_cookie';
      final diag = await TorDiagnostics.diagnose(
        host: '127.0.0.1',
        socksPort: _embeddedTor.socksPort,
        controlPort: _embeddedTor.controlPort,
        controlCookiePath: cookiePath,
      );
      if (diag.socksReachable) {
        _isTorRunning = true;
        _torDiagnosticDetail =
            '${diag.message} · Endpoint: $_onionAddress';
        _securityContext = _securityContext.copyWith(
          isTorConnected: true,
          status: SecuritySubsystemState.ready,
        );
        notifyListeners();
        return true;
      }
      _isTorRunning = false;
      _torDiagnosticDetail = isTorFailClosed
          ? '${diag.message} (Fallback IP direto bloqueado)'
          : diag.message;
      _securityContext = _securityContext.copyWith(
        isTorConnected: false,
        status: SecuritySubsystemState.failed,
      );
      notifyListeners();
      return false;
    } catch (_) {
      _isTorRunning = false;
      _torDiagnosticDetail = isTorFailClosed
          ? 'Tor indisponível — Fail-Closed ATIVO (Fallback IP direto bloqueado)'
          : 'Tor indisponível em 127.0.0.1:9050';
      _securityContext = _securityContext.copyWith(
        isTorConnected: false,
        status: SecuritySubsystemState.failed,
      );
      notifyListeners();
      return false;
    }
  }

  // Getters Filtros GitHub (delegados para StarwireFilterViewModel)
  String get githubSearchQuery => _starwireFilters.searchQuery;
  String get githubSelectedTopic => _starwireFilters.selectedTopic;
  String get githubSelectedLanguage => _starwireFilters.selectedLanguage;
  String get githubSortBy => _starwireFilters.sortBy;
  List<GithubRepository> get filteredGithubRepos => _starwireFilters.filteredRepos;
  Map<String, int> get githubLanguageCounts => _starwireFilters.languageCounts;
  Map<String, int> get githubCategoryCounts => _starwireFilters.categoryCounts;

  // Getters Filtros Monero P2P (delegados para MoneroOrderFilterViewModel)
  MoneroP2pSide get moneroSelectedSide => _moneroFilters.selectedSide;
  String get moneroSelectedFiat => _moneroFilters.selectedFiat;
  String get moneroSelectedPaymentMethod => _moneroFilters.selectedPaymentMethod;
  String get moneroSearchQuery => _moneroFilters.searchQuery;
  List<MoneroP2pOrder> get filteredMoneroOrders => _moneroFilters.filteredOrders;

  bool verifyMoneroOrder(MoneroP2pOrder order) {
    return SignedMoneroAd.verifyOrderSync(
      order,
      consumedNonceToOrderId: _consumedMoneroNonces,
    );
  }

  Iterable<Space> get _publishedSpaces sync* {
    for (final space in _spaces) {
      if (space.isDirectMessages) continue;
      final visible = space.channels.where((ch) => ch.permissions.isPublic).toList();
      if (visible.isEmpty) continue;
      yield Space(
        id: space.id, name: space.name, initials: space.initials,
        description: space.description, categoryTag: space.categoryTag,
        memberCount: _isMockMode ? space.memberCount
            : space.ownerFingerprint == _ownWorkspaceIdentity ? 1 : null,
        onlineCount: _isMockMode ? space.onlineCount : null,
        isPublic: true,
        channels: [
          for (final channel in visible)
            Channel(
              id: channel.id, spaceId: space.id, name: channel.name,
              topic: channel.topic, type: channel.type, category: channel.category,
              permissions: ChannelPermissions(
                isPublic: true, requireApproval: channel.permissions.requireApproval,
              ),
            ),
        ],
      );
    }
    if (_isMockMode) {
      yield* _discoverableSpaces.where((space) => space.isPublic &&
          !_spaces.any((local) => local.id == space.id && local.ownerFingerprint != null));
    }
  }

  /// Lista de grupos públicos filtrada e ordenada (padrão: do menos populoso ao mais populoso).
  List<Space> get filteredDiscoverableSpaces {
    final query = _exploreSearchQuery.trim().toLowerCase();
    final filtered = _publishedSpaces.where((s) {
      if (query.isEmpty) return true;
      return s.name.toLowerCase().contains(query) ||
          s.description.toLowerCase().contains(query) ||
          s.categoryTag.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) {
      final aCount = a.memberCount;
      final bCount = b.memberCount;
      if (aCount == null && bCount != null) return 1;
      if (bCount == null && aCount != null) return -1;
      final byCount = (aCount ?? 0).compareTo(bCount ?? 0);
      return byCount == 0 ? a.name.compareTo(b.name)
          : _exploreSortAscending ? byCount : -byCount;
    });
    return filtered;
  }

  /// Lista filtrada/ordenada de conversas diretas (sempre colocando Mensagens Salvas primeiro, depois fixadas).
  List<DirectMessageThread> get filteredDirectMessages {
    final q = _conversationSearchQuery.trim().toLowerCase();
    SpaceFolder? activeFolder;
    if (_activeFolderId != 'all' && _activeFolderId != 'private') {
      final fIdx = _folders.indexWhere((f) => f.id == _activeFolderId);
      if (fIdx != -1) activeFolder = _folders[fIdx];
    }

    final list = _directMessages.where((dm) {
      if (activeFolder != null && !dm.isSavedMessages) {
        if (!activeFolder.conversationIds.contains(dm.id)) return false;
      }
      if (q.isNotEmpty) {
        final match = dm.peerName.toLowerCase().contains(q) ||
            dm.lastMessagePreview.toLowerCase().contains(q) ||
            dm.peerPublicId.toLowerCase().contains(q);
        if (!match) return false;
      }
      switch (_conversationFilter) {
        case ConversationFilter.unread:
          return dm.unreadCount > 0;
        case ConversationFilter.pinned:
          return dm.isPinned;
        case ConversationFilter.muted:
          return dm.isMuted;
        case ConversationFilter.groups:
        case ConversationFilter.channels:
          return false;
        case ConversationFilter.all:
        case ConversationFilter.privateChats:
          return true;
      }
    }).toList();

    list.sort((a, b) {
      if (a.isSavedMessages != b.isSavedMessages) return a.isSavedMessages ? -1 : 1;
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final ta = a.lastActivityAt ?? DateTime(2000);
      final tb = b.lastActivityAt ?? DateTime(2000);
      return tb.compareTo(ta);
    });
    return list;
  }

  List<Channel> channelsInActiveFolder(Space space) {
    final folder = _folders.where((folder) => folder.id == _activeFolderId).firstOrNull;
    if (folder == null || _activeFolderId == 'all' || folder.spaceIds.contains(space.id)) return space.channels;
    return space.channels.where((channel) => folder.conversationIds.contains(channel.id)).toList();
  }

  List<Space> get visibleSpacesForFolder {
    if (_activeFolderId == 'private') return const [];
    final q = _conversationSearchQuery.trim().toLowerCase();
    Iterable<Space> base = _spaces;
    if (_activeFolderId != 'all') {
      final fIdx = _folders.indexWhere((f) => f.id == _activeFolderId);
      if (fIdx != -1) {
        base = base.where((space) => channelsInActiveFolder(space).isNotEmpty);
      }
    }
    return base.where((s) {
      if (q.isNotEmpty) {
        final matchSpace = s.name.toLowerCase().contains(q);
        final matchChannel = s.channels.any((c) => c.name.toLowerCase().contains(q));
        if (!matchSpace && !matchChannel) return false;
      }
      switch (_conversationFilter) {
        case ConversationFilter.unread:
          return s.unreadCount > 0 || s.channels.any((c) => c.unreadCount > 0);
        case ConversationFilter.pinned:
          return s.isPinned || s.channels.any((c) => c.isPinned);
        case ConversationFilter.muted:
          return s.isMuted || s.channels.any((c) => c.isMuted);
        case ConversationFilter.privateChats:
          return false;
        case ConversationFilter.channels:
          return s.channels.any((c) => c.type == ChannelType.announcement || c.type == ChannelType.publication);
        case ConversationFilter.groups:
        case ConversationFilter.all:
          return true;
      }
    }).toList();
  }

  /// Privacidade do Card ID aplicada na disponibilização dos dados no estado.
  AuthorizedPeerCardData getAuthorizedPeerCardData({
    required String peerName,
    required String peerPublicId,
    required NixTrustLevel trustLevel,
    required bool hasCryptographicShield,
    required String rawBio,
    required List<String> rawHighlights,
    required String ownerVisibility,
    bool isVerifiedContact = false,
  }) {
    if (ownerVisibility == 'Oculto') {
      return AuthorizedPeerCardData(
        peerName: peerName,
        peerPublicId: peerPublicId,
        trustLevel: trustLevel,
        hasCryptographicShield: hasCryptographicShield,
        isAuthorized: false,
        visibilityLabel: 'Oculto pelo proprietário',
        bio: 'Dados restritos pelo proprietário (Configurações → Privacidade → Visibilidade do Card ID).',
        culturalHighlights: const [],
      );
    }
    if (ownerVisibility == 'Apenas Contatos Verificados' && !isVerifiedContact) {
      return AuthorizedPeerCardData(
        peerName: peerName,
        peerPublicId: peerPublicId,
        trustLevel: trustLevel,
        hasCryptographicShield: hasCryptographicShield,
        isAuthorized: false,
        visibilityLabel: 'Apenas Contatos Verificados',
        bio: 'Adicione e verifique este par (QR / Chave Pública) para liberar biografia e acervo completo.',
        culturalHighlights: const [],
      );
    }
    return AuthorizedPeerCardData(
      peerName: peerName,
      peerPublicId: peerPublicId,
      trustLevel: trustLevel,
      hasCryptographicShield: hasCryptographicShield,
      isAuthorized: true,
      visibilityLabel: ownerVisibility,
      bio: rawBio,
      culturalHighlights: rawHighlights,
    );
  }

  // ================= NAVEGAÇÃO DE ÁREAS =================

  void openHomePrivateArea({bool resetToCardId = false}) {
    _activeArea = NixActiveArea.homePrivate;
    _activeFolderId = 'private';
    if (resetToCardId) {
      _homeSubTab = HomeSubTab.cardId;
      _selectedDm = null;
    }
    _clearTransientMessageModes();
    notifyListeners();
  }

  void openExploreArea() {
    _activeArea = NixActiveArea.explore;
    notifyListeners();
  }

  void openGithubDiscoveryArea() {
    _activeArea = NixActiveArea.github;
    notifyListeners();
  }

  bool _financeShowWallet = false;
  bool get financeShowWallet => _financeShowWallet;

  void openMoneroP2pArea({bool showWallet = false}) {
    _financeShowWallet = showWallet;
    _activeArea = NixActiveArea.moneroP2p;
    notifyListeners();
  }

  void openMediaIndexArea() {
    _activeArea = NixActiveArea.mediaIndex;
    _clearTransientMessageModes();
    notifyListeners();
  }

  void openArchiveArea() {
    _activeArea = NixActiveArea.archive;
    _clearTransientMessageModes();
    notifyListeners();
  }

  void selectHomeSubTab(HomeSubTab tab) {
    if (tab == HomeSubTab.moneroP2p) {
      openMoneroP2pArea();
      return;
    }
    if (tab == HomeSubTab.transactions) {
      openMoneroP2pArea(showWallet: true);
      return;
    }
    if (tab == HomeSubTab.githubDiscovery) {
      openGithubDiscoveryArea();
      return;
    }
    _activeArea = NixActiveArea.homePrivate;
    _homeSubTab = tab;
    if (tab != HomeSubTab.directChat) {
      _selectedDm = null;
    }
    _clearTransientMessageModes();
    notifyListeners();
  }

  // ================= MÁQUINA DE ESTADOS HOVER CARD ID (DELEGADA PARA PEERHOVERVIEWMODEL) =================

  ContactRequest? get hoveredContactRequest => _peerHover.hoveredContactRequest;
  PeerCardHoverState get peerHoverState => _peerHover.peerHoverState;

  void setHoveredContactRequest(ContactRequest? req) {
    if (req == null) {
      _peerHover.dismissHoveredPeerCard();
    } else {
      _peerHover.onRequestPeerHoverEnter(req);
    }
  }

  void onRequestPeerHoverEnter(ContactRequest req) => _peerHover.onRequestPeerHoverEnter(req);
  void onRequestPeerHoverExit(ContactRequest req) => _peerHover.onRequestPeerHoverExit(req);
  void setHoverOverPreviewCard(bool over) => _peerHover.setHoverOverPreviewCard(over);
  void dismissHoveredPeerCard() => _peerHover.dismissHoveredPeerCard();

  // ================= PASTAS, FILTROS & CONVERSAS DIRETAS =================

  void selectFolder(String folderId) {
    _activeFolderId = folderId;
    if (folderId == 'private') {
      _activeArea = NixActiveArea.homePrivate;
    } else if (folderId != 'all') {
      final target = _spaces.where((space) => channelsInActiveFolder(space).isNotEmpty).firstOrNull;
      if (target != null) {
        _currentSpace = target;
        _currentChannel = channelsInActiveFolder(target).first;
        _activeArea = NixActiveArea.spaces;
      } else {
        _activeArea = NixActiveArea.homePrivate;
      }
    }
    notifyListeners();
  }

  void setConversationFilter(ConversationFilter filter) {
    _conversationFilter = filter;
    notifyListeners();
  }

  void setConversationSearchQuery(String query) {
    _conversationSearchQuery = query;
    notifyListeners();
  }

  void openSavedMessages() {
    selectDirectMessage(savedMessagesThread);
  }

  void saveToSavedMessages(
    String text, {
    List<String> attachments = const [],
    String? forwardedFrom,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;
    final target = savedMessagesThread;
    final msg = Message(
      id: 'saved_${DateTime.now().millisecondsSinceEpoch}',
      channelId: target.id,
      senderName: _userProfile.effectiveDisplayName,
      senderFingerprint: _securityContext.myFingerprint,
      isMe: true,
      text: trimmed.isNotEmpty ? trimmed : 'Anexo salvo',
      timestamp: DateTime.now(),
      forwardedFrom: forwardedFrom,
      attachments: attachments,
    );
    final idx = _directMessages.indexWhere((d) => d.id == target.id);
    if (idx != -1) {
      final updatedMsgs = List<Message>.from(_directMessages[idx].messages)..add(msg);
      _directMessages[idx] = _directMessages[idx].copyWith(messages: updatedMsgs);
      if (_selectedDm?.id == target.id) {
        _selectedDm = _directMessages[idx];
      }
      notifyListeners();
    }
  }

  void selectDirectMessage(DirectMessageThread dm) {
    _activeArea = NixActiveArea.homePrivate;
    _homeSubTab = HomeSubTab.directChat;
    final idx = _directMessages.indexWhere((d) => d.id == dm.id);
    if (idx != -1) {
      _directMessages[idx] = _directMessages[idx].copyWith(unreadCount: 0);
      _selectedDm = _directMessages[idx];
    } else {
      _selectedDm = dm;
    }
    _clearTransientMessageModes();
    notifyListeners();
  }

  void togglePinDirectMessage(String dmId) {
    final idx = _directMessages.indexWhere((d) => d.id == dmId);
    if (idx == -1) return;
    _directMessages[idx] = _directMessages[idx].copyWith(isPinned: !_directMessages[idx].isPinned);
    if (_selectedDm?.id == dmId) {
      _selectedDm = _directMessages[idx];
    }
    notifyListeners();
  }

  void toggleMuteDirectMessage(String dmId) {
    final idx = _directMessages.indexWhere((d) => d.id == dmId);
    if (idx == -1) return;
    _directMessages[idx] = _directMessages[idx].copyWith(isMuted: !_directMessages[idx].isMuted);
    if (_selectedDm?.id == dmId) {
      _selectedDm = _directMessages[idx];
    }
    notifyListeners();
  }

  Future<String>? _exportingInvitation;

  Future<String> exportContactInvitation() {
    if (!_settings.allowPublicIdSharing) {
      throw StateError('Ative o compartilhamento da identidade para criar o convite.');
    }
    return _exportingInvitation ??= exportLocalSignedCardJson().whenComplete(() {
      _exportingInvitation = null;
    });
  }

  /// Exporta o convite assinado com uma SignedPreKey X25519 para X3DH.
  Future<String> exportLocalSignedCardJson({
    String? displayName,
    String preKeyId = 'spk_active_1',
  }) async {
    final messenger = _sovereignMessenger;
    if (messenger == null || _primaryIdentity == null) {
      throw StateError(
        '[Fail-Closed] SovereignMessenger / Identidade Seed A não inicializados.',
      );
    }
    final bundle = await messenger.signedPreKeyForInvitation(preKeyId);
    final creds = _activeMailboxCredentials ??
        SovereignMessenger.deriveMailboxCredentials(_primaryIdentity!.publicId);
    _activeMailboxCredentials = creds;
    return messenger.exportSignedCardJson(
      displayName: displayName ?? _userProfile.effectiveDisplayName,
      mailboxId: creds.mailboxId,
      preKeyBundle: bundle,
    );
  }

  /// Importa o Card ID assinado de um par remoto (validando assinatura Ed25519 e SPK)
  /// sem iniciar sessão iniciadora (usado pelo lado receptor antes ou durante o handshake).
  Future<CardImportResult> importPeerCardOnly(
    String rawCardJson, {
    String? conversationId,
  }) async {
    final messenger = _sovereignMessenger;
    if (messenger == null) {
      throw StateError('[Fail-Closed] SovereignMessenger não inicializado.');
    }
    final res = await messenger.importAndVerifyCardJson(rawJson: rawCardJson);
    if (res.status != CardImportStatus.importedVerified &&
        res.status != CardImportStatus.importedUnverified) {
      throw StateError(res.reason ?? 'Falha ao validar Card ID do par.');
    }
    final cid = conversationId ?? 'dm_${res.publicId}';
    final existingConv = await _conversationRepo?.getConversation(cid);
    if (existingConv == null && _conversationRepo != null) {
      await _conversationRepo!.createConversation(
        id: cid,
        kind: 'direct',
        ownerIdentityId: _userProfile.publicId,
        title: res.displayName ?? res.publicId!,
      );
    }
    final thread = DirectMessageThread(
      id: cid,
      peerName: res.displayName ?? res.publicId!,
      peerPublicId: res.publicId!,
      peerMailboxId: res.mailboxId,
      hasActiveSession: false,
      statusText: 'Contato Verificado · Aguardando Handshake X3DH',
      isOnline: true,
      isVerified: true,
      trustLevel: NixTrustLevel.level3Green,
      messages: const [],
    );
    final idx = _directMessages.indexWhere((d) => d.id == cid);
    if (idx == -1) {
      _directMessages.add(thread);
    } else {
      _directMessages[idx] = thread;
    }
    notifyListeners();
    return res;
  }

  /// Importa o Card ID assinado de um par remoto, estabelece sessão iniciadora X3DH + Double Ratchet
  /// no SQLCipher e seleciona a conversa privada pronta para envio E2EE.
  Future<DirectMessageThread> importPeerCardAndEstablishSession(
    String rawCardJson, {
    String? conversationId,
    String peerDeviceId = 'dev_primary',
  }) async {
    final messenger = _sovereignMessenger;
    if (messenger == null) {
      throw StateError('[Fail-Closed] SovereignMessenger não inicializado.');
    }
    final res = await messenger.importAndVerifyCardJson(rawJson: rawCardJson);
    if ((res.status != CardImportStatus.importedVerified &&
            res.status != CardImportStatus.importedUnverified) ||
        res.publicId == null ||
        res.signedPreKeyBundle == null) {
      throw StateError(res.reason ?? 'Card ID inválido para estabelecer sessão X3DH.');
    }
    final cid = conversationId ?? 'dm_${res.publicId}';
    await messenger.establishInitiatorSession(
      conversationId: cid,
      peerPublicId: res.publicId!,
      peerDeviceId: peerDeviceId,
      peerBundle: res.signedPreKeyBundle!,
      peerTitle: res.displayName ?? res.publicId!,
      peerMailbox: res.mailboxId,
    );
    await _refreshDirectThreadsFromDatabase();
    final thread = _directMessages.firstWhere(
      (d) => d.id == cid,
      orElse: () => DirectMessageThread(
        id: cid,
        peerName: res.displayName ?? res.publicId!,
        peerPublicId: res.publicId!,
        peerMailboxId: res.mailboxId,
        hasActiveSession: true,
        statusText: 'Sessão E2EE Double Ratchet Ativa · Tor Onion v3',
        isOnline: true,
        isVerified: true,
        trustLevel: NixTrustLevel.level3Green,
        messages: const [],
      ),
    );
    selectDirectMessage(thread);
    return thread;
  }

  Timer? _scheduledWakeup;
  Future<void>? _scheduledRun;
  bool _scheduledForeground = false;
  bool _hasScheduledMessages = false;
  bool _scheduledOutboxNeedsRetry = false;

  bool get canScheduleDirectMessages =>
      !_disposed && _panicWipe == null &&
      (_localDatabase?.cipherInfo.isEncrypted ?? false) &&
      _sovereignMessenger != null;

  void setScheduledMessagesForeground(bool foreground) {
    _scheduledForeground = foreground;
    if (foreground) {
      _armScheduledMessages();
    } else {
      _scheduledWakeup?.cancel();
      _scheduledWakeup = null;
    }
  }

  Future<void> _restoreScheduledMessages() async {
    if (!canScheduleDirectMessages) return;
    try {
      _hasScheduledMessages =
          (await _sovereignMessenger!.listScheduledMessages()).isNotEmpty;
      _scheduledOutboxNeedsRetry =
          await _sovereignMessenger!.outboxRepo.hasPendingScheduledEnvelopes();
      _armScheduledMessages();
    } catch (_) {
      // Um agendamento ilegível não impede a abertura do cofre.
    }
  }

  Future<List<ScheduledMessage>> scheduledMessagesFor(String conversationId) async {
    if (!canScheduleDirectMessages) return [];
    final entries = await _sovereignMessenger!.listScheduledMessages();
    return entries.where((entry) => entry.conversationId == conversationId).toList();
  }

  Future<void> scheduleDirectMessage({
    required String conversationId,
    required String text,
    required DateTime dueAt,
    required MessageRecurrence recurrence,
  }) async {
    final messenger = _sovereignMessenger;
    if (!canScheduleDirectMessages || messenger == null) {
      throw StateError('Desbloqueie o cofre para agendar mensagens.');
    }
    await messenger.scheduleDirectMessage(
      conversationId: conversationId,
      text: text,
      dueAt: dueAt,
      recurrence: recurrence,
      now: DateTime.now(),
    );
    _hasScheduledMessages = true;
    _armScheduledMessages();
  }

  Future<bool> cancelScheduledMessage(ScheduledMessage entry) async {
    if (!canScheduleDirectMessages) {
      throw StateError('Desbloqueie o cofre para cancelar o agendamento.');
    }
    return _sovereignMessenger!.cancelScheduledMessage(entry);
  }

  void _armScheduledMessages() {
    if (!_scheduledForeground || !canScheduleDirectMessages ||
        (!_hasScheduledMessages && !_scheduledOutboxNeedsRetry) ||
        _scheduledWakeup != null || _scheduledRun != null) return;
    _scheduledWakeup = Timer(const Duration(seconds: 20), () {
      _scheduledWakeup = null;
      _scheduledRun = _dispatchScheduledMessages().whenComplete(() {
        _scheduledRun = null;
        _armScheduledMessages();
      });
    });
  }

  Future<void> _dispatchScheduledMessages() async {
    final messenger = _sovereignMessenger;
    final relay = _relayForMessaging;
    bool maySend() => _scheduledForeground && canScheduleDirectMessages &&
        identical(messenger, _sovereignMessenger) &&
        !_isStrictOffGridMode && securityGate.isTorAnonymityReady;
    if (messenger == null || relay == null ||
        relay.policy.mode != TransportMode.torFailClosed ||
        !TransportPolicy.isValidOnionV3Host(relay.baseUri.host) || !maySend()) return;
    try {
      final credentials = _activeMailboxCredentials ??
          SovereignMessenger.deriveMailboxCredentials(messenger.identity.publicId);
      await messenger.enqueueDueScheduledMessages(
        now: DateTime.now(),
        senderMailbox: credentials.mailboxId,
        mayEnqueue: maySend,
      );
      _scheduledOutboxNeedsRetry =
          await messenger.outboxRepo.hasPendingScheduledEnvelopes();
      if (_scheduledOutboxNeedsRetry && maySend()) {
        await messenger.flushOutbox(
          relayClient: relay,
          quotaToken: credentials.writeQuotaToken.isEmpty
              ? null : credentials.writeQuotaToken,
          maySend: maySend,
        );
        _scheduledOutboxNeedsRetry = await messenger.outboxRepo.hasPendingScheduledEnvelopes();
        if (canScheduleDirectMessages && identical(messenger, _sovereignMessenger)) {
          await _refreshDirectThreadsFromDatabase();
          if (!_disposed && _panicWipe == null) notifyListeners();
        }
      }
      _hasScheduledMessages = (await messenger.listScheduledMessages()).isNotEmpty;
    } catch (_) {
      // Os agendamentos e os envelopes já gravados são preservados para retentativa.
    }
  }

  /// Sincroniza a Outbox pendente e a Inbox do relay cego via [SovereignMessenger],
  /// atualizando os estados reais (`queued`, `accepted`, `delivered`, `failed`) nas conversas.
  Future<({int acceptedOutbox, int failedOutbox, int receivedInbox})>
      syncWithRelay({
    String preKeyId = 'spk_active_1',
  }) async {
    if (_isStrictOffGridMode) {
      _lastMessagingError =
          '[Modo Off-Grid Estrito] Funções de rede/Wi-Fi/Relay desativadas. Utilize Bluetooth BLE Mesh ou Rádio LoRa.';
      notifyListeners();
      return (acceptedOutbox: 0, failedOutbox: 0, receivedInbox: 0);
    }
    final messenger = _sovereignMessenger;
    final relay = _relayForMessaging;
    if (messenger == null || relay == null) {
      _lastMessagingError =
          messenger == null
              ? 'Desbloqueie o cofre para sincronizar as conversas.'
              : 'Configure o relay Onion em Configurações → Conexões.';
      notifyListeners();
      return (acceptedOutbox: 0, failedOutbox: 0, receivedInbox: 0);
    }
    final creds = _activeMailboxCredentials ??
        SovereignMessenger.deriveMailboxCredentials(messenger.identity.publicId);
    _activeMailboxCredentials = creds;

    final flushRes = await messenger.flushOutbox(
      relayClient: relay,
      quotaToken: creds.writeQuotaToken.isEmpty ? null : creds.writeQuotaToken,
    );
    if (_disposed || _panicWipe != null || _isStrictOffGridMode) {
      return (acceptedOutbox: flushRes.accepted, failedOutbox: flushRes.failed, receivedInbox: 0);
    }
    final PollCommitResult pollRes;
    try {
      pollRes = await messenger.pollAndCommitInbox(
        creds: creds,
        relayClient: relay,
        preKeyId: preKeyId,
      );
    } catch (_) {
      if (!_disposed && _panicWipe == null) {
        _lastMessagingError = 'Falha ao ler a caixa postal. Confira o Tor e as credenciais do relay.';
        await _refreshDirectThreadsFromDatabase();
        if (!_disposed) notifyListeners();
      }
      return (acceptedOutbox: flushRes.accepted, failedOutbox: flushRes.failed, receivedInbox: 0);
    }
    if (flushRes.failed > 0) {
      _lastMessagingError =
          'Falha ao transmitir ${flushRes.failed} envelope(s) da Outbox ao relay.';
    } else if (pollRes.errors.isNotEmpty) {
      _lastMessagingError = pollRes.errors.first;
    } else {
      _lastMessagingError = null;
    }
    await _refreshDirectThreadsFromDatabase();
    notifyListeners();
    return (
      acceptedOutbox: flushRes.accepted,
      failedOutbox: flushRes.failed,
      receivedInbox: pollRes.committed.length,
    );
  }

  Future<bool> _transmitNearbyEnvelope(
    SovereignMessenger messenger,
    DirectMessageThread thread,
    Map<String, dynamic> row,
  ) async {
    if (!_isStrictOffGridMode || !_bluetoothMesh.isMeshEnabled || _disposed) {
      return false;
    }
    final cardId = thread.peerPublicId;
    final targets = _bluetoothMesh.activePeers.where((peer) {
      final advertisedId = peer.peerPublicCardId;
      return advertisedId.length == 13 && cardId.startsWith(advertisedId);
    }).toList();
    if (targets.length != 1) return false;

    final wireBytes = row['ciphertext'] as Uint8List;
    final mailbox = row['destination_mailbox'] as String;
    final deliveryId = row['id'] as String;
    final expiresAtMs = row['expires_at'] as int;
    if (wireBytes.length > 32768 ||
        expiresAtMs <= DateTime.now().millisecondsSinceEpoch) {
      return false;
    }
    final packet = await messenger.sealNearbyDelivery(
      peerPublicId: cardId,
      mailboxId: mailbox,
      deliveryId: deliveryId,
      wireBytes: wireBytes,
      expiresAtMs: expiresAtMs,
    );
    if (!_isStrictOffGridMode || _disposed) return false;
    return await _bluetoothMesh.broadcastEnvelope(
          recipientCardId: mailbox,
          payload: packet,
          targetDeviceAddress: targets.single.deviceAddress,
          deliveryId: deliveryId,
          expiresAtMs: expiresAtMs,
        ) >
        0;
  }

  /// Retenta mensagens de texto da conversa selecionada sem usar o relay.
  Future<void> retryNearbyMessages() async {
    final thread = _selectedDm;
    final messenger = _sovereignMessenger;
    final db = _localDatabase;
    if (!_isStrictOffGridMode ||
        thread == null ||
        thread.isSavedMessages ||
        messenger == null ||
        db == null) {
      return;
    }
    final rows = await db.rawDatabase.rawQuery(
      """
      SELECT o.id, o.destination_mailbox, o.ciphertext, o.expires_at
      FROM outbox o
      JOIN messages m ON m.id = o.message_id
      WHERE m.conversation_id = ? AND o.session_id IS NOT NULL
        AND o.transport_state IN ('queued', 'failed') AND o.expires_at > ?
        AND (m.expires_at IS NULL OR m.expires_at > ?)
        AND NOT EXISTS (SELECT 1 FROM attachments a WHERE a.message_id = m.id)
      ORDER BY m.created_at, o.id
      LIMIT 20
      """,
      [
        thread.id,
        DateTime.now().millisecondsSinceEpoch,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    var written = 0;
    for (final row in rows) {
      try {
        if (await _transmitNearbyEnvelope(messenger, thread, row)) written++;
      } catch (_) {
        // O envelope original continua disponível na outbox cifrada.
      }
    }
    if (_disposed || !_isStrictOffGridMode) return;
    _lastMessagingError = rows.isEmpty
        ? null
        : written > 0
            ? '$written mensagem(ns) transmitida(s) por Bluetooth. Confirmação pendente.'
            : 'Nenhuma mensagem transmitida. Verifique se o contato está próximo e com Bluetooth ativo.';
    notifyListeners();
  }

  Future<Uint8List?> readMessageImage(Message message, int index) async {
    if (_disposed || _panicWipe != null || index < 0 || index >= message.attachments.length) return null;
    try {
      final reference = message.attachments[index];
      if (!LocalImageHelper.isSupportedExtension(reference)) return null;
      if (message.isMe && File(reference).isAbsolute) {
        final file = File(reference);
        if (await file.exists() && await file.length() <= 20 * 1024 * 1024) {
          return LocalImageHelper.stripMetadataBytes(await file.readAsBytes());
        }
      }
      return await _sovereignMessenger?.readImageAttachment(message.id, index);
    } catch (_) {
      return null;
    }
  }

  Future<void>? _interactiveDirectSend;

  bool _canSendInteractiveDirect(String conversationId) =>
      canScheduleDirectMessages && !_isStrictOffGridMode &&
      _selectedDm?.id == conversationId && _selectedDm?.hasActiveSession == true &&
      _selectedDm?.isSavedMessages == false &&
      _editingMessage == null && _replyingToMessage == null;

  Future<VoiceNote?> readMessageVoiceNote(Message message, int index) async {
    if (_disposed || _panicWipe != null) return null;
    try {
      final note = await _sovereignMessenger?.readVoiceNote(message.id, index);
      if (note != null && (_disposed || _panicWipe != null)) {
        note.pcm.fillRange(0, note.pcm.length, 0);
        return null;
      }
      return note;
    } catch (_) {
      return null;
    }
  }

  Map<String, DirectPollState> directPollsFor(String conversationId) =>
      _directPolls[conversationId] ?? const {};

  List<DirectMessageThread> get groupPollContacts => _directMessages.where(
    (thread) => thread.hasActiveSession && thread.isVerified && !thread.isSavedMessages,
  ).toList(growable: false);

  SharedGroupPollThread? sharedGroupPollsFor(String conversationId) =>
      _sharedGroupPollThreads[conversationId];

  bool get canSyncSharedPolls => canScheduleDirectMessages &&
      !_isStrictOffGridMode && securityGate.isTorAnonymityReady &&
      _relayForMessaging?.policy.mode == TransportMode.torFailClosed;

  Future<void> _sendSharedGroupPacket(String conversation, SharedGroupPollPacket packet) async {
    final messenger = _sovereignMessenger;
    bool allowed() => canSyncSharedPolls && identical(messenger, _sovereignMessenger) &&
        groupPollContacts.any((thread) => thread.id == conversation);
    if (messenger == null || !allowed()) throw StateError('Conexão cifrada indisponível.');
    await messenger.enqueueSharedGroupPollPacket(
      conversationId: conversation,
      senderMailbox: localRelayMailboxId,
      packet: packet,
      mayEnqueue: allowed,
    );
  }

  Future<void> submitSharedGroupBallot(String conversation, String id, List<int> choices) async {
    final thread = _sharedGroupPollThreads[conversation];
    final offer = thread?.received[id];
    final spec = offer?.spec;
    final previous = thread?.sentBallots[id]?.revision ?? 0;
    if (offer == null || spec == null || offer.closed || !spec.accepts(choices) ||
        (previous > 0 && !spec.allowRevote) ||
        (spec.durationMinutes != null &&
         !DateTime.now().isBefore(offer.created!.add(Duration(minutes: spec.durationMinutes!))))) {
      throw StateError('A enquete não aceita este voto.');
    }
    await _sendSharedGroupPacket(conversation,
        SharedGroupPollPacket.ballot(id, previous + 1, choices));
    await _refreshDirectThreadsFromDatabase();
    if (!_disposed) notifyListeners();
    if (canSyncSharedPolls) await syncWithRelay();
  }

  Future<void> synchronizeGroupPoll(String channel, String id, {
    Set<String> invite = const {},
    bool close = false,
  }) async {
    if (!canUseLocalGroupPolls(channel) || !canSyncSharedPolls) {
      throw StateError('Abra o canal e conecte o relay Onion.');
    }
    final result = await syncWithRelay();
    if (!canUseLocalGroupPolls(channel) || !canSyncSharedPolls ||
        (result.receivedInbox == 0 && _lastMessagingError?.startsWith('Falha ao ler') == true)) {
      throw StateError('Não foi possível sincronizar a caixa postal.');
    }
    final participants = groupPollContacts.where((thread) =>
      invite.contains(thread.id) ||
      _sharedGroupPollThreads[thread.id]?.sent.containsKey(id) == true).toList();
    if (participants.length > 50) throw StateError('Limite de 50 participantes.');
    late LocalGroupPoll snapshot;
    await _changeLocalGroupPoll(channel, id, (value) {
      if (value.creator != _ownWorkspaceIdentity) throw StateError('Autor da enquete inválido.');
      var updated = value;
      for (final peer in participants) {
        final inbox = _sharedGroupPollThreads[peer.id];
        if (inbox?.sent.containsKey(id) != true) continue;
        final ballot = value.spec.allowRevote
            ? inbox?.receivedBallots[id] : inbox?.firstBallots[id];
        if (ballot == null || listEquals(ballot.values, updated.votes[peer.peerPublicId])) continue;
        try {
          updated = updated.vote(peer.peerPublicId, ballot.values, DateTime.now());
        } on StateError {
          // Ignora votos fora das regras, expirados ou já encerrados.
        }
      }
      snapshot = close && !updated.closed ? updated.close(_ownWorkspaceIdentity) : updated;
      return snapshot;
    });
    try {
      for (final participant in participants) {
        final thread = await _sovereignMessenger?.sharedGroupPollsFor(
          participant.id, participant.peerPublicId,
        );
        final previous = thread?.sent[id]?.revision ?? 0;
        await _sendSharedGroupPacket(participant.id,
            SharedGroupPollPacket.snapshot(snapshot, previous + 1));
      }
    } finally {
      if (!_disposed && _panicWipe == null) {
        await _refreshDirectThreadsFromDatabase();
        if (!_disposed) notifyListeners();
      }
    }
    if (canSyncSharedPolls) await syncWithRelay();
  }

  bool canUseDirectPolls(String conversationId) => _canSendInteractiveDirect(conversationId);

  bool canSendVoiceNote(String conversationId) => _canSendInteractiveDirect(conversationId);

  Future<void> createDirectPoll(String conversationId, DirectPollSpec poll) =>
      _sendDirectPollEvent(conversationId, (_, __) => poll);

  Future<void> voteDirectPoll(String conversationId, String pollId, List<int> choices) =>
      _sendDirectPollEvent(conversationId, (polls, actor) {
        final poll = polls[pollId];
        if (poll == null) throw StateError('Enquete indisponível.');
        return poll.makeVote(actor, choices, DateTime.now());
      });

  Future<void> closeDirectPoll(String conversationId, String pollId) =>
      _sendDirectPollEvent(conversationId, (polls, actor) {
        final poll = polls[pollId];
        if (poll == null) throw StateError('Enquete indisponível.');
        return poll.makeClose(actor);
      });

  Future<void> _sendDirectPollEvent(
    String conversationId,
    DirectPollEvent Function(Map<String, DirectPollState>, String) build,
  ) => _sendInteractiveDirect(
    conversationId,
    (messenger, allowed) => messenger.enqueueDirectPollEvent(
      conversationId: conversationId,
      senderMailbox: localRelayMailboxId,
      build: build,
      mayEnqueue: allowed,
    ),
  );

  Future<void> sendVoiceNote(String conversationId, VoiceNote note) =>
      _sendInteractiveDirect(
    conversationId,
    (messenger, allowed) => messenger.enqueueVoiceNote(
      conversationId: conversationId,
      senderMailbox: localRelayMailboxId,
      note: note,
      ephemeralTtlSeconds: _selectedEphemeralTimer,
      mayEnqueue: allowed,
    ),
  );

  Future<void> _sendInteractiveDirect(
    String conversationId,
    Future<void> Function(SovereignMessenger, bool Function()) enqueue,
  ) async {
    final messenger = _sovereignMessenger;
    bool allowed() => identical(messenger, _sovereignMessenger) &&
        _canSendInteractiveDirect(conversationId);
    if (_interactiveDirectSend != null || messenger == null || !allowed()) {
      throw StateError('Abra uma conversa direta com sessão cifrada e aguarde o envio anterior.');
    }
    final relay = _relayForMessaging;
    final send = () async {
      await enqueue(messenger, allowed);
      try {
        if (!_disposed && _panicWipe == null) await _refreshDirectThreadsFromDatabase();
        if (!_disposed && _panicWipe == null) notifyListeners();
        bool maySend() => allowed() && securityGate.isTorAnonymityReady;
        if (relay != null && relay.policy.mode == TransportMode.torFailClosed &&
            TransportPolicy.isValidOnionV3Host(relay.baseUri.host) && maySend()) {
          final quota = _activeMailboxCredentials?.writeQuotaToken;
          await messenger.flushOutbox(
            relayClient: relay, quotaToken: quota?.isNotEmpty == true ? quota : null,
            maySend: maySend,
          );
          if (!_disposed && _panicWipe == null) await _refreshDirectThreadsFromDatabase();
        }
      } catch (_) {
        // O envelope já gravado continua disponível para sincronização.
      }
      if (!_disposed && _panicWipe == null) notifyListeners();
    }();
    _interactiveDirectSend = send.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    try {
      await send;
    } finally {
      _interactiveDirectSend = null;
    }
  }

  static String _inferAttachmentMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  /// Caminho unificado de envio de mensagens privadas (Fase 3):
  /// - Diferencia `Mensagens Salvas` (`deliveryState: 'saved'`, cofre local) de conversas remotas.
  /// - Em conversas remotas, exige sessão Double Ratchet válida no [SovereignMessenger],
  ///   enfileira atomicamente (`sessions` + `messages` + `attachments` + `outbox`),
  ///   transmite ao relay se configurado e reflete estados reais (`queued`, `accepted`, `failed`).
  Future<void> sendDirectMessage(
    String text, {
    List<String> attachments = const [],
  }) async {
    if (_selectedDm == null || _panicWipe != null) return;
    if (text.trim().isEmpty && attachments.isEmpty) return;

    if (_editingMessage != null) {
      saveEditedMessage(_editingMessage!.id, text);
      return;
    }

    final thread = _selectedDm!;
    final cleanBody = text.trim();
    final reply = _replyingToMessage;
    final idx = _directMessages.indexWhere((d) => d.id == thread.id);
    if (idx == -1) return;

    // 1. Mensagens Salvas: cofre local cifrado (não passa por relay nem exige sessão remota)
    if (thread.isSavedMessages) {
      final savedMsg = Message(
        id: 'dm_msg_${DateTime.now().millisecondsSinceEpoch}',
        channelId: thread.id,
        senderName: _userProfile.effectiveDisplayName,
        senderFingerprint: _securityContext.myFingerprint,
        isMe: true,
        isVerified: true,
        deliveryState: 'saved',
        text: cleanBody,
        timestamp: DateTime.now().toUtc(),
        ephemeralSeconds: _selectedEphemeralTimer,
        remainingSeconds: _selectedEphemeralTimer,
        attachments: attachments,
        replyToMessageId: reply?.id,
        replyToSenderName: reply?.senderName,
        replyToExcerpt: reply?.text,
      );
      final updatedMsgs = List<Message>.from(_directMessages[idx].messages)
        ..add(savedMsg);
      _directMessages[idx] = _directMessages[idx].copyWith(messages: updatedMsgs);
      _selectedDm = _directMessages[idx];
      _replyingToMessage = null;
      if (_localDatabase != null && _messageRepo != null) {
        await _persistDirectMessageToDb(
          message: savedMsg,
          thread: _selectedDm!,
          cleanBody: cleanBody,
        );
      }
      notifyListeners();
      return;
    }

    if (_isStrictOffGridMode &&
        (attachments.isNotEmpty || utf8.encode(cleanBody).length > 8192)) {
      _lastMessagingError =
          'Bluetooth direto aceita texto de até 8 KiB. Remova anexos ou reduza a mensagem.';
      notifyListeners();
      return;
    }

    // 2. Conversa privada remota com SovereignMessenger ativo
    final messenger = _sovereignMessenger;
    if (messenger != null) {
      final sessionMeta = await messenger.getSessionMetadata(thread.id);
      if (sessionMeta == null) {
        final err =
            'A sessão cifrada com ${thread.peerName} ainda não foi iniciada. Troque os convites assinados e sincronize o relay.';
        _lastMessagingError = err;
        final failedMsg = Message(
          id: 'dm_failed_${DateTime.now().millisecondsSinceEpoch}',
          channelId: thread.id,
          senderName: _userProfile.effectiveDisplayName,
          senderFingerprint: _securityContext.myFingerprint,
          isMe: true,
          isVerified: false,
          deliveryState: 'failed',
          deliveryError: err,
          text: cleanBody,
          timestamp: DateTime.now().toUtc(),
          attachments: attachments,
        );
        final updatedMsgs = List<Message>.from(_directMessages[idx].messages)
          ..add(failedMsg);
        _directMessages[idx] = _directMessages[idx].copyWith(
          messages: updatedMsgs,
          hasActiveSession: false,
        );
        _selectedDm = _directMessages[idx];
        _replyingToMessage = null;
        notifyListeners();
        return;
      }

      try {
        _lastMessagingError = null;
        final preparedManifests = <AttachmentManifest>[];
        final displayAttachmentNames = <String>[];
        for (final att in attachments) {
          final f = File(att);
          if (f.existsSync()) {
            final rawBytes = await f.readAsBytes();
            final fileName = LocalImageHelper.getFileName(att);
            final manifest = await messenger.prepareEncryptedAttachment(
              fileName: fileName,
              mimeType: _inferAttachmentMimeType(fileName),
              rawBytes: rawBytes,
            );
            preparedManifests.add(manifest);
            displayAttachmentNames.add(manifest.fileName);
          } else {
            throw const FormatException('Um anexo não está mais disponível no dispositivo.');
          }
        }

        final destMailbox = (sessionMeta['peerMailbox'] as String?) ??
            thread.peerMailboxId ??
            SovereignMessenger.deriveMailboxCredentials(thread.peerPublicId)
                .mailboxId;
        final senderMailbox = (_activeMailboxCredentials ??
                SovereignMessenger.deriveMailboxCredentials(
                  messenger.identity.publicId,
                ))
            .mailboxId;

        final enqueued = await messenger.enqueueDirectMessage(
          conversationId: thread.id,
          destinationMailbox: destMailbox,
          senderMailbox: senderMailbox,
          text: cleanBody,
          ephemeralTtlSeconds:
              _selectedEphemeralTimer > 0 ? _selectedEphemeralTimer : null,
          attachments: preparedManifests,
        );

        var currentDeliveryState = 'queued';
        String? currentDeliveryError;

        if (_isStrictOffGridMode) {
          currentDeliveryError =
              'Na fila local. A entrega por Bluetooth ainda não foi confirmada.';
          try {
            final rows = await _localDatabase!.rawDatabase.query(
              'outbox',
              columns: ['id', 'destination_mailbox', 'ciphertext', 'expires_at'],
              where: 'id = ?',
              whereArgs: [enqueued.outboxId],
            );
            if (await _transmitNearbyEnvelope(messenger, thread, rows.single)) {
              currentDeliveryError =
                  'Transmitida por Bluetooth. Confirmação do contato pendente.';
            }
          } catch (_) {
            // O envelope original continua disponível na outbox cifrada.
          }
        } else if (_relayForMessaging case final relay?) {
          await messenger.flushOutbox(
            relayClient: relay,
            quotaToken: _activeMailboxCredentials?.writeQuotaToken.isNotEmpty == true
                ? _activeMailboxCredentials!.writeQuotaToken : null,
          );
          final msgRows = await _localDatabase!.rawDatabase.query(
            'messages',
            columns: ['delivery_state'],
            where: 'id = ?',
            whereArgs: [enqueued.messageId],
            limit: 1,
          );
          if (msgRows.isNotEmpty) {
            currentDeliveryState =
                (msgRows.first['delivery_state'] as String?) ?? 'queued';
          }
          if (currentDeliveryState == 'failed') {
            currentDeliveryState = 'failed';
            currentDeliveryError =
                'Falha ao entregar envelope cifrado ao relay Tor/SOCKS5.';
            _lastMessagingError = currentDeliveryError;
          }
        }

        final sentMsg = Message(
          id: enqueued.messageId,
          channelId: thread.id,
          senderName: _userProfile.effectiveDisplayName,
          senderFingerprint: _securityContext.myFingerprint,
          isMe: true,
          isVerified: thread.isVerified && currentDeliveryState != 'failed',
          deliveryState: currentDeliveryState,
          deliveryError: currentDeliveryError,
          text: cleanBody,
          timestamp: DateTime.now().toUtc(),
          ephemeralSeconds: _selectedEphemeralTimer,
          remainingSeconds: _selectedEphemeralTimer,
          attachments: displayAttachmentNames,
          replyToMessageId: reply?.id,
          replyToSenderName: reply?.senderName,
          replyToExcerpt: reply?.text,
        );
        final updatedMsgs = List<Message>.from(_directMessages[idx].messages)
          ..add(sentMsg);
        _directMessages[idx] = _directMessages[idx].copyWith(
          messages: updatedMsgs,
          hasActiveSession: true,
          peerMailboxId: destMailbox,
        );
        _selectedDm = _directMessages[idx];
        _replyingToMessage = null;
        notifyListeners();
        return;
      } catch (e) {
        final err = e is FormatException
            ? e.message
            : 'O envio cifrado falhou. Verifique a conversa e tente novamente.';
        _lastMessagingError = err;
        final failedMsg = Message(
          id: 'dm_err_${DateTime.now().millisecondsSinceEpoch}',
          channelId: thread.id,
          senderName: _userProfile.effectiveDisplayName,
          senderFingerprint: _securityContext.myFingerprint,
          isMe: true,
          isVerified: false,
          deliveryState: 'failed',
          deliveryError: err,
          text: cleanBody,
          timestamp: DateTime.now().toUtc(),
          attachments: attachments,
        );
        final updatedMsgs = List<Message>.from(_directMessages[idx].messages)
          ..add(failedMsg);
        _directMessages[idx] = _directMessages[idx].copyWith(messages: updatedMsgs);
        _selectedDm = _directMessages[idx];
        _replyingToMessage = null;
        notifyListeners();
        return;
      }
    }

    // 3. Sem SovereignMessenger ativo:
    // Em modo produção, falha fechado; em modo mock de testes de widget sem banco, marca apenas como 'queued' (nunca 'delivered').
    if (!_isMockMode) {
      const err =
          '[Fail-Closed] Cofre SQLCipher ou identidade soberana não inicializados para envio remoto.';
      _lastMessagingError = err;
      final failedMsg = Message(
        id: 'dm_uninit_${DateTime.now().millisecondsSinceEpoch}',
        channelId: thread.id,
        senderName: _userProfile.effectiveDisplayName,
        senderFingerprint: _securityContext.myFingerprint,
        isMe: true,
        isVerified: false,
        deliveryState: 'failed',
        deliveryError: err,
        text: cleanBody,
        timestamp: DateTime.now().toUtc(),
        attachments: attachments,
      );
      final updatedMsgs = List<Message>.from(_directMessages[idx].messages)
        ..add(failedMsg);
      _directMessages[idx] = _directMessages[idx].copyWith(messages: updatedMsgs);
      _selectedDm = _directMessages[idx];
      _replyingToMessage = null;
      notifyListeners();
      return;
    }

    final mockQueuedMsg = Message(
      id: 'dm_msg_${DateTime.now().millisecondsSinceEpoch}',
      channelId: thread.id,
      senderName: _userProfile.effectiveDisplayName,
      senderFingerprint: _securityContext.myFingerprint,
      isMe: true,
      isVerified: false,
      deliveryState: 'queued',
      text: cleanBody,
      timestamp: DateTime.now(),
      ephemeralSeconds: _selectedEphemeralTimer,
      remainingSeconds: _selectedEphemeralTimer,
      attachments: attachments,
      replyToMessageId: reply?.id,
      replyToSenderName: reply?.senderName,
      replyToExcerpt: reply?.text,
    );
    final updatedMsgs = List<Message>.from(_directMessages[idx].messages)
      ..add(mockQueuedMsg);
    _directMessages[idx] = _directMessages[idx].copyWith(messages: updatedMsgs);
    _selectedDm = _directMessages[idx];
    _replyingToMessage = null;
    notifyListeners();
  }

  Future<void> _persistDirectMessageToDb({
    required Message message,
    required DirectMessageThread thread,
    required String cleanBody,
  }) async {
    try {
      final db = _localDatabase;
      final convRepo = _conversationRepo;
      final msgRepo = _messageRepo;
      if (db == null || convRepo == null || msgRepo == null) return;

      final existingConv = await convRepo.getConversation(thread.id);
      if (existingConv == null) {
        final primary = await _identityRepo?.getPrimaryIdentity();
        final ownerId = (primary?['id'] as String?) ?? _userProfile.publicId;
        if (ownerId.isNotEmpty) {
          await convRepo.createConversation(
            id: thread.id,
            kind: thread.isSavedMessages ? 'saved' : 'direct',
            ownerIdentityId: ownerId,
            title: thread.peerName,
          );
        }
      }

      final nowMs = message.timestamp.toUtc().millisecondsSinceEpoch;
      final expiresAt = message.ephemeralSeconds > 0
          ? nowMs + (message.ephemeralSeconds * 1000)
          : null;

      await msgRepo.insertMessage(
        id: message.id,
        conversationId: thread.id,
        authorKey: _userProfile.publicId,
        deviceId: _localDeviceId,
        body: cleanBody,
        deliveryState: thread.isSavedMessages ? 'received' : 'queued',
        replyToId: message.replyToMessageId,
        createdAt: nowMs,
        expiresAt: expiresAt,
      );
      final messenger = _sovereignMessenger;
      if (thread.isSavedMessages && messenger != null) {
        for (final (ordinal, reference) in message.attachments.indexed) {
          final file = File(reference);
          if (!file.isAbsolute || !await file.exists()) continue;
          final name = LocalImageHelper.getFileName(reference);
          final manifest = await messenger.prepareEncryptedAttachment(fileName: name,
            mimeType: _inferAttachmentMimeType(name), rawBytes: await file.readAsBytes());
          await messenger.objectChunkRepo.linkAttachment(messageId: message.id,
            objectId: manifest.objectId, fileName: name, ordinal: ordinal);
        }
      }
    } catch (e) {
      debugPrint('[NixState] Aviso ao persistir mensagem no banco local: $e');
    }
  }

  void acceptContactRequest(String requestId) {
    final idx = _contactRequests.indexWhere((r) => r.id == requestId);
    if (idx == -1) return;
    final req = _contactRequests.removeAt(idx);
    _peerHover.reset();
    final newDm = DirectMessageThread(
      id: 'dm_${DateTime.now().millisecondsSinceEpoch}',
      peerName: req.peerName,
      peerPublicId: req.peerPublicId,
      statusText: 'Contato verificado recém-adicionado',
      isOnline: true,
      isVerified: true,
      trustLevel: NixTrustLevel.level3Green,
      messages: [
        Message(
          id: 'dm_init_${DateTime.now().millisecondsSinceEpoch}',
          channelId: req.id,
          senderName: req.peerName,
          senderFingerprint: req.peerPublicId.replaceFirst('NIX-', ''),
          isMe: false,
          text: req.note,
          timestamp: DateTime.now(),
        ),
      ],
    );
    _directMessages.insert(1, newDm);
    notifyListeners();
  }

  void declineContactRequest(String requestId) {
    _contactRequests.removeWhere((r) => r.id == requestId);
    _peerHover.reset();
    notifyListeners();
  }

  // ================= MONERO P2P MARKETPLACE (FASE 7) =================

  ({int socksPort, int controlPort, String cookiePath}) get tradeTorConnection => (
    socksPort: _embeddedTor.socksPort,
    controlPort: _embeddedTor.controlPort,
    cookiePath: '${_embeddedTor.dataDirectory}/control_auth_cookie',
  );

  bool get canOpenOnionVoice => !_disposed && _panicWipe == null &&
      !_isStrictOffGridMode && securityGate.isTorAnonymityReady &&
      _currentChannel.type == ChannelType.voice && !_isLocallyBanned(_currentChannel);

  bool get canOpenPrivateTradeRoom =>
      !_disposed && _panicWipe == null && !_isStrictOffGridMode &&
      securityGate.isTorAnonymityReady;

  void setMoneroSide(MoneroP2pSide side) {
    _moneroFilters.setSelectedSide(side);
    notifyListeners();
  }

  void setMoneroFiat(String fiat) {
    _moneroFilters.setSelectedFiat(fiat);
    notifyListeners();
  }

  void setMoneroPaymentMethod(String method) {
    _moneroFilters.setSelectedPaymentMethod(method);
    notifyListeners();
  }

  void setMoneroSearchQuery(String query) {
    _moneroFilters.setSearchQuery(query);
    notifyListeners();
  }

  void createMoneroOrder(MoneroP2pOrder order) {
    _moneroOrders.insert(0, order);
    _moneroFilters.updateOrders(_moneroOrders);
    notifyListeners();
  }

  /// Cria, valida, assina criptograficamente com Ed25519 (identidade financeira isolada da Seed A)
  /// e persiste um anúncio Monero P2P com estado honesto (`local_signed`).
  Future<MoneroP2pOrder> createAndSignMoneroOrder({
    required MoneroP2pSide side,
    required String fiatCurrency,
    required double pricePerXmr,
    required double minFiatLimit,
    required double maxFiatLimit,
    required String paymentMethod,
    required String notes,
    Duration ttl = const Duration(hours: 24),
  }) async {
    SignedMoneroAd.validatePriceAndLimits(
      pricePerXmr: pricePerXmr,
      minFiatLimit: minFiatLimit,
      maxFiatLimit: maxFiatLimit,
      paymentMethod: paymentMethod,
    );

    // Cada anúncio tem uma chave e um nome próprios, sem vínculo com o perfil.
    final isolatedSigner = await NixIdentity.generate();
    final orderId = 'xmr_ad_${base64Url.encode(SecretKeyData.random(length: 16).bytes).replaceAll('=', '')}';
    final alias = isolatedSigner.ed25519PublicHex.substring(0, 8).toUpperCase();
    final signedAd = await SignedMoneroAd.createSigned(
      signer: isolatedSigner,
      orderId: orderId,
      traderName: 'Parte-$alias',
      side: side,
      fiatCurrency: fiatCurrency,
      pricePerXmr: pricePerXmr,
      minFiatLimit: minFiatLimit,
      maxFiatLimit: maxFiatLimit,
      paymentMethod: paymentMethod.trim(),
      notes: notes.trim(),
      publicationState: 'local_signed',
      ttl: ttl,
    );

    final order = signedAd.order.copyWith(
      trustLevel: NixTrustLevel.level2Yellow,
      completedTrades: 0,
      reputationScore: 100.0,
    );

    final verified = await SignedMoneroAd.verifyOrderCryptographically(order);
    if (!verified) {
      throw StateError(
        '[Fail-Closed] Falha na autoverificação Ed25519 do anúncio Monero gerado.',
      );
    }

    _moneroOrders.insert(0, order);
    _moneroFilters.updateOrders(_moneroOrders);
    if (_preferencesRepo != null) {
      final localOrders = _moneroOrders
          .where((o) => o.publicationState == 'local_signed')
          .map((o) => o.toJson())
          .toList();
      await _preferencesRepo!.setOption(
        'monero_local_orders_v1',
        localOrders,
      );
    }
    notifyListeners();
    return order;
  }

  // ================= GITHUB DISCOVERY (STARWIRE) =================

  void setGithubSearchQuery(String query) {
    _starwireFilters.setSearchQuery(query);
    notifyListeners();
  }

  void setGithubTopic(String topic) {
    _starwireFilters.setSelectedTopic(topic);
    notifyListeners();
  }

  void setGithubLanguage(String language) {
    _starwireFilters.setSelectedLanguage(language);
    notifyListeners();
  }

  void setGithubSortBy(String sortBy) {
    _starwireFilters.setSortBy(sortBy);
    notifyListeners();
  }

  void toggleSaveRepoInAcervo(String repoId) {
    final idx = _githubRepos.indexWhere((r) => r.id == repoId);
    if (idx == -1) return;

    final repo = _githubRepos[idx];
    final isNowSaved = !repo.isSavedInAcervo;
    _githubRepos[idx] = repo.copyWith(isSavedInAcervo: isNowSaved);
    _starwireFilters.updateRepos(_githubRepos);

    if (isNowSaved) {
      _savedAcervoIds.add(repo.id);
      final culturalItem = CulturalItem(
        id: 'repo_${repo.name}',
        title: repo.name,
        creatorOrYear: '${repo.language} · ${repo.owner}',
        category: CulturalCategory.github,
        rating: repo.formattedStars,
        monogram: repo.name.length >= 2 ? repo.name.substring(0, 2).toUpperCase() : 'GH',
        toneShade: 75,
        isPublicInCardId: false, // Acervo privado por padrão (Seção 16)
        repositoryUrl: repo.htmlUrl,
        starsCount: repo.starsCount,
        language: repo.language,
        license: repo.license,
        updatedDate: repo.updatedDate,
      );
      addCulturalItem(culturalItem);
    } else {
      _savedAcervoIds.remove(repo.id);
      if (_mediaRepo != null) {
        unawaited(_mediaRepo!.deleteMediaItem('repo_${repo.name}'));
      }
      _userProfile = _userProfile.copyWith(
        culturalItems: _userProfile.culturalItems
            .where((i) => i.id != 'repo_${repo.name}' && i.id != repo.id)
            .toList(),
      );
    }
    if (_preferencesRepo != null) {
      unawaited(
        _preferencesRepo!.setOption(
          NixPreferenceStore.savedAcervoKey,
          _savedAcervoIds.toList(),
        ),
      );
    }
    _persistState();
    notifyListeners();
  }

  // ================= OVERLAY DE PERFIL, CARD ID & CONFIGURAÇÕES =================

  bool _settingsOpenedFromPager = false;

  void openProfileOverlay({bool startInSettings = false, SettingsCategory? category}) {
    _settingsOpenedFromPager = false;
    _isProfileOverlayOpen = true;
    _isSettingsOpenInOverlay = startInSettings;
    _requestedOverlaySettingsCategory = startInSettings ? category : null;
    if (category != null) {
      _activeSettingsCategory = category;
    }
    notifyListeners();
  }

  void closeProfileOverlay() {
    _settingsOpenedFromPager = false;
    _isProfileOverlayOpen = false;
    _isSettingsOpenInOverlay = false;
    _requestedOverlaySettingsCategory = null;
    notifyListeners();
  }

  void transitionToSettings({SettingsCategory? category}) {
    if (!_isSettingsOpenInOverlay) _settingsOpenedFromPager = _isProfileOverlayOpen;
    _isProfileOverlayOpen = true;
    _isSettingsOpenInOverlay = true;
    _requestedOverlaySettingsCategory = category;
    if (category != null) {
      _activeSettingsCategory = category;
    }
    notifyListeners();
  }

  void backFromOverlaySettings() {
    if (_settingsOpenedFromPager) {
      transitionBackToCardId();
    } else {
      closeProfileOverlay();
    }
  }

  void transitionBackToCardId() {
    _settingsOpenedFromPager = false;
    _isSettingsOpenInOverlay = false;
    _requestedOverlaySettingsCategory = null;
    notifyListeners();
  }

  void selectSettingsCategory(SettingsCategory category) {
    _activeSettingsCategory = category;
    notifyListeners();
  }

  // ================= ATUALIZAÇÃO DO PERFIL & PASSAPORTE CULTURAL =================

  PagerPlaylist? get pagerPlaylist {
    final repository = _preferencesRepo;
    if (_disposed || _panicWipe != null || repository == null ||
        _localDatabase?.cipherInfo.isEncrypted != true) return null;
    return PagerPlaylist(repository);
  }

  void updateProfile({
    String? displayName,
    String? bio,
    String? currentActivity,
    String? avatarStyle,
    String? customAvatarPath,
    bool clearCustomAvatar = false,
    double? avatarCropScale,
    double? avatarCropOffsetX,
    double? avatarCropOffsetY,
  }) {
    final cleanBio = bio != null
        ? (bio.trim().length > 180 ? bio.trim().substring(0, 180) : bio.trim())
        : null;
    final cleanName = displayName != null
        ? (displayName.trim().length > 32
            ? displayName.trim().substring(0, 32)
            : displayName.trim())
        : null;

    _userProfile = _userProfile.copyWith(
      displayName: cleanName,
      bio: cleanBio,
      currentActivity: currentActivity,
      avatarStyle: avatarStyle,
      customAvatarPath: customAvatarPath,
      clearCustomAvatar: clearCustomAvatar,
      avatarCropScale: avatarCropScale,
      avatarCropOffsetX: avatarCropOffsetX,
      avatarCropOffsetY: avatarCropOffsetY,
    );
    if (_localDatabase != null &&
        _identityRepo != null &&
        _userProfile.publicId.isNotEmpty) {
      unawaited(_identityRepo!.saveProfile(
        identityId: _userProfile.publicId,
        displayName: _userProfile.effectiveDisplayName,
        bio: _userProfile.bio,
        avatarObjectId: _userProfile.avatarStyle,
      ));
    }
    unawaited(_persistState());
    notifyListeners();
  }

  /// Restaura conta e identidade Seed A a partir da frase mnemônica de 24 palavras.
  Future<NixIdentity> recoverAccountFromMnemonic({
    required List<String> words,
    required String passphrase,
    String displayName = 'Soberano',
    String? customDbPath,
    String? customVaultPath,
    bool bindToOsKeyring = false,
  }) async {
    final identity = await SeedRecoveryManager.deriveIdentityFromMnemonic(words);
    final ok = await initializeEncryptedDatabase(
      passphrase: passphrase,
      customDbPath: customDbPath,
      customVaultPath: customVaultPath,
      bindToOsKeyring: bindToOsKeyring,
    );
    if (!ok) {
      throw StateError('Falha ao inicializar banco SQLCipher na recuperação Seed A.');
    }
    await persistPrimaryIdentity(
      identity: identity,
      displayName: displayName,
    );
    return identity;
  }

  String _mapMediaKind(CulturalCategory category) {
    switch (category) {
      case CulturalCategory.movies:
        return 'film';
      case CulturalCategory.series:
        return 'series';
      case CulturalCategory.anime:
        return 'anime';
      case CulturalCategory.manga:
        return 'manga';
      case CulturalCategory.books:
        return 'book';
      case CulturalCategory.music:
        return 'album';
      case CulturalCategory.github:
        return 'repository';
    }
  }

  /// Grava o formulário antes de fechar o editor e publicar a mudança local.
  Future<void> saveCulturalItem(CulturalItem item) async {
    final media = _mediaRepo;
    if (media == null || _panicWipe != null) {
      throw StateError('Desbloqueie o cofre antes de salvar o item.');
    }
    await media.upsertMediaItem(
      id: item.id,
      kind: _mapMediaKind(item.category),
      title: item.title,
      metadata: item.toJson(),
      source: 'local_acervo',
      sourceId: item.id,
    );
    if (_disposed || _panicWipe != null) return;
    final items = List<CulturalItem>.of(_userProfile.culturalItems);
    final index = items.indexWhere((saved) => saved.id == item.id);
    if (index < 0) {
      items.insert(0, item);
    } else {
      items[index] = item;
    }
    _userProfile = _userProfile.copyWith(culturalItems: items);
    notifyListeners();
  }

  void addCulturalItem(CulturalItem item) {
    final updated = List<CulturalItem>.from(_userProfile.culturalItems)..insert(0, item);
    _userProfile = _userProfile.copyWith(culturalItems: updated);
    if (_mediaRepo != null) {
      unawaited(_mediaRepo!.upsertMediaItem(
        id: item.id,
        kind: _mapMediaKind(item.category),
        title: item.title,
        metadata: item.toJson(),
        source: 'local_acervo',
        sourceId: item.id,
      ));
    }
    _persistState();
    notifyListeners();
  }

  void updateCulturalItem(CulturalItem updatedItem) {
    final updated = _userProfile.culturalItems.map((item) {
      return item.id == updatedItem.id ? updatedItem : item;
    }).toList();
    _userProfile = _userProfile.copyWith(culturalItems: updated);
    if (_mediaRepo != null) {
      unawaited(_mediaRepo!.upsertMediaItem(
        id: updatedItem.id,
        kind: _mapMediaKind(updatedItem.category),
        title: updatedItem.title,
        metadata: updatedItem.toJson(),
        source: 'local_acervo',
        sourceId: updatedItem.id,
      ));
    }
    _persistState();
    notifyListeners();
  }

  void removeCulturalItem(String itemId) {
    final updated = _userProfile.culturalItems.where((i) => i.id != itemId).toList();
    _userProfile = _userProfile.copyWith(culturalItems: updated);
    if (_mediaRepo != null) {
      unawaited(_mediaRepo!.deleteMediaItem(itemId));
    }
    _persistState();
    notifyListeners();
  }

  void toggleItemCardIdVisibility(String itemId) {
    CulturalItem? modified;
    final updated = _userProfile.culturalItems.map((item) {
      if (item.id == itemId) {
        modified = item.copyWith(isPublicInCardId: !item.isPublicInCardId);
        return modified!;
      }
      return item;
    }).toList();
    _userProfile = _userProfile.copyWith(culturalItems: updated);
    if (modified != null && _mediaRepo != null) {
      unawaited(_mediaRepo!.upsertMediaItem(
        id: modified!.id,
        kind: _mapMediaKind(modified!.category),
        title: modified!.title,
        metadata: modified!.toJson(),
        source: 'local_acervo',
        sourceId: modified!.id,
      ));
    }
    _persistState();
    notifyListeners();
  }

  /// Busca local no catálogo de mídia via [MediaCatalogService] (`MediaOperationStage.localCatalogSearch`).
  Future<List<Map<String, dynamic>>> searchCulturalCatalog(String query) async {
    final q = query.trim();
    if (_mediaCatalogService != null) {
      return _mediaCatalogService!.searchOfflineCatalog(q);
    }
    if (q.isEmpty) {
      return _userProfile.culturalItems.map((i) => i.toJson()).toList();
    }
    final lower = q.toLowerCase();
    return _userProfile.culturalItems
        .where((i) =>
            i.title.toLowerCase().contains(lower) ||
            i.creatorOrYear.toLowerCase().contains(lower))
        .map((i) => i.toJson())
        .toList();
  }

  /// Consulta conector externo opt-in via [MediaCatalogService] (`MediaOperationStage.remoteOptInQuery`),
  /// impondo opt-in explícito e política de transporte Tor fail-closed.
  Future<List<Map<String, dynamic>>> queryOptInMediaConnector({
    required OptInMediaConnectorKind connector,
    required String query,
    Future<List<Map<String, dynamic>>> Function(String query)? transportExecutor,
  }) async {
    if (_isStrictOffGridMode) {
      throw const TransportBlockedException(
        '[Modo Off-Grid Estrito] Conectores externos de rede/Wi-Fi estão bloqueados.',
      );
    }
    final svc = _mediaCatalogService;
    if (svc == null) {
      throw StateError('[Fail-Closed] MediaCatalogService requer banco SQLCipher ativo.');
    }
    return svc.queryRemoteOptInConnector(
      connector: connector,
      query: query,
      isFailClosedTorActive: isTorFailClosed,
      hasActiveTorSocksCircuit: _isTorRunning,
      transportExecutor: transportExecutor,
    );
  }

  // ================= CONFIGURAÇÕES, TEMAS & JANELA =================

  static ImageProvider get pagerWallpaperImage => ResizeImage(
        FileImage(LocalImageHelper.pagerWallpaper),
        width: 1440,
        height: 1440,
        policy: ResizeImagePolicy.fit,
      );

  int _pagerWallpaperRevision = 0;
  int get pagerWallpaperRevision => _pagerWallpaperRevision;

  Future<bool>? _pagerWallpaperChange;

  Future<bool> updatePagerWallpaper(String? sourcePath) async {
    if (_disposed || _panicWipe != null || _pagerWallpaperChange != null) {
      return false;
    }
    final change = _setPagerWallpaper(sourcePath);
    _pagerWallpaperChange = change;
    try {
      return await change;
    } finally {
      _pagerWallpaperChange = null;
    }
  }

  Future<bool> _setPagerWallpaper(String? sourcePath) async {
    try {
      final wallpaper = LocalImageHelper.pagerWallpaper;
      if (sourcePath == null) {
        if (await wallpaper.exists()) await wallpaper.delete();
      } else if (!await LocalImageHelper.storePagerWallpaper(sourcePath)) {
        return false;
      }
      await pagerWallpaperImage.evict();
      _pagerWallpaperRevision++;
      if (!_disposed && _panicWipe == null) notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void updatePagerAvatarVisibility(bool showAvatar) {
    if (_disposed || _panicWipe != null) return;
    updateSettings(_settings.copyWith(hidePagerAvatar: !showAvatar));
  }

  void updateThemeMode(NixThemeMode mode) {
    _settings = _settings.copyWith(themeMode: mode);
    NixColors.sync(NixSurfaceScheme.resolve(mode), currentPalette);
    _persistState();
    notifyListeners();
  }

  void updatePalette(NixPaletteType type, [int? customColor]) {
    _settings = _settings.copyWith(
      paletteType: type,
      customPaletteColor: customColor ?? _settings.customPaletteColor,
    );
    NixColors.sync(NixSurfaceScheme.resolve(_settings.themeMode), currentPalette);
    _persistState();
    notifyListeners();
  }

  void updateWindowGeometry({
    double? width,
    double? height,
    double? offsetX,
    double? offsetY,
  }) {
    _settings = _settings.copyWith(
      windowWidth: width,
      windowHeight: height,
      windowOffsetX: offsetX,
      windowOffsetY: offsetY,
    );
    if (_settings.persistWindowGeometry) {
      _persistState();
    }
    notifyListeners();
  }

  double get dockWidth => _settings.dockWidth;
  double get sidebarWidth => _settings.sidebarWidth;

  void updateDockWidth(double width) {
    final clamped = width.clamp(64.0, 110.0);
    if ((clamped - _settings.dockWidth).abs() > 0.5) {
      _settings = _settings.copyWith(dockWidth: clamped);
      _persistState();
      notifyListeners();
    }
  }

  void updateSidebarWidth(double width) {
    final clamped = width.clamp(220.0, 480.0);
    if ((clamped - _settings.sidebarWidth).abs() > 0.5) {
      _settings = _settings.copyWith(sidebarWidth: clamped);
      _persistState();
      notifyListeners();
    }
  }

  void resetDockWidth() {
    _settings = _settings.copyWith(dockWidth: 78.0);
    _persistState();
    notifyListeners();
  }

  void resetSidebarWidth() {
    _settings = _settings.copyWith(sidebarWidth: 288.0);
    _persistState();
    notifyListeners();
  }

  void toggleWindowMaximized() {
    _isWindowMaximized = !_isWindowMaximized;
    notifyListeners();
  }

  void updateCardIdVisibility(String visibility) {
    _settings = _settings.copyWith(cardIdVisibility: visibility);
    _persistState();
    notifyListeners();
  }

  void toggleFloatingWindowMode(bool isFloating) {
    _settings = _settings.copyWith(floatingWindowMode: isFloating);
    _persistState();
    notifyListeners();
  }

  void updateSettings(UserSettings newSettings) {
    _settings = newSettings;
    NixColors.sync(NixSurfaceScheme.resolve(_settings.themeMode), currentPalette);
    _persistState();
    notifyListeners();
  }

  void toggleConnector(String connectorId) {
    final updated = _settings.connectors.map((c) {
      if (c.id == connectorId) {
        return c.copyWith(isEnabled: !c.isEnabled);
      }
      return c;
    }).toList();
    updateSettings(_settings.copyWith(connectors: updated));
  }

  void unblockUser(String publicId) {
    final updated = _settings.blockedUserIds.where((id) => id != publicId).toList();
    updateSettings(_settings.copyWith(blockedUserIds: updated));
  }

  void blockNewUser(String publicId) {
    if (publicId.trim().isEmpty) return;
    final updated = List<String>.from(_settings.blockedUserIds)..add(publicId.trim());
    updateSettings(_settings.copyWith(blockedUserIds: updated));
  }

  void authorizeDevice(String deviceName, String fingerprint) {
    final newDev = AuthorizedDevice(
      id: 'dev_${DateTime.now().millisecondsSinceEpoch}',
      deviceName: deviceName.trim().isNotEmpty ? deviceName.trim() : 'Novo Dispositivo Nix',
      clientVersion: 'Nix Client v0.4.0-dev',
      lastSeenLabel: 'Agora',
      isCurrent: false,
      fingerprint: fingerprint.trim().isNotEmpty ? fingerprint.trim() : 'NX-7700-AA21',
    );
    final updated = List<AuthorizedDevice>.from(_settings.devices)..add(newDev);
    updateSettings(_settings.copyWith(devices: updated));
  }

  void revokeDevice(String deviceId) {
    final updated = _settings.devices.where((d) => d.id != deviceId).toList();
    updateSettings(_settings.copyWith(devices: updated));
  }

  // ================= ESPAÇOS, PASTAS (FOLDERS) & EXPLORAR =================

  void selectSpace(Space space) {
    _activeArea = NixActiveArea.spaces;
    _clearTransientMessageModes();
    if (channelsInActiveFolder(space).isEmpty) _activeFolderId = 'all';
    if (_currentSpace.id == space.id) {
      notifyListeners();
      return;
    }
    _currentSpace = space;
    if (space.channels.isNotEmpty) {
      _currentChannel = (channelsInActiveFolder(space).firstOrNull ?? space.channels.first);
    }
    notifyListeners();
  }

  void toggleFolderExpanded(String folderId) {
    if (_workspaceFolders.toggleExpanded(folderId)) notifyListeners();
  }

  void createSpaceFolder(
    String name,
    List<String> spaceIds, {
    String iconName = 'folder',
    int colorValue = 0xFFFFC928,
    List<String> conversationIds = const [],
  }) {
    if (!_workspaceFolders.create(name, spaceIds, iconName: iconName,
        colorValue: colorValue, conversationIds: conversationIds)) {
      return;
    }
    _persistState(workspaceChanged: true);
    notifyListeners();
  }

  void updateSpaceFolder(SpaceFolder folder) {
    if (!_workspaceFolders.replace(folder)) return;
    _persistState(workspaceChanged: true);
    notifyListeners();
  }

  void reorderFolders(int oldIndex, int newIndex) {
    if (!_workspaceFolders.reorder(oldIndex, newIndex)) return;
    _persistState(workspaceChanged: true);
    notifyListeners();
  }

  bool isWorkspaceItem(String id) => _spaces.any((space) => space.id == id || space.channels.any((channel) => channel.id == id)) ||
      _directMessages.any((thread) => thread.id == id && !thread.isSavedMessages);

  void combineSpacesIntoFolder(String sourceSpaceId, String targetSpaceId, [String? folderName]) {
    if (sourceSpaceId == targetSpaceId || !isWorkspaceItem(sourceSpaceId) || !isWorkspaceItem(targetSpaceId)) return;
    final ids = [targetSpaceId, sourceSpaceId];
    final spaces = ids.where((id) => _spaces.any((space) => space.id == id)).toList();
    final names = ids.map((id) => _spaces.where((space) => space.id == id).firstOrNull?.initials ??
        _spaces.expand((space) => space.channels).where((channel) => channel.id == id).firstOrNull?.name ?? 'Chat');
    for (final id in ids) { _removeFolderMembership(id); }
    createSpaceFolder(folderName ?? names.join(' & '), spaces,
      conversationIds: ids.where((id) => !spaces.contains(id)).toList());
  }

  void _removeFolderMembership(String id) {
    _workspaceFolders.removeMembership(id);
    _resetMissingFolder();
  }

  void _resetMissingFolder() {
    if (_activeFolderId != 'private' &&
        _workspaceFolders.find(_activeFolderId) == null) {
      _activeFolderId = 'all';
    }
  }

  void ungroupWorkspaceItem(String id) {
    if (!isWorkspaceItem(id)) return;
    _removeFolderMembership(id);
    _persistState(workspaceChanged: true);
    notifyListeners();
  }

  void moveWorkspaceFolder(String id, String targetId) {
    if (id == targetId || !_workspaceFolders.move(id, targetId)) return;
    _persistState(workspaceChanged: true);
    notifyListeners();
  }

  void addSpaceToFolder(String spaceId, String folderId) => assignItemToFolder(spaceId, folderId);

  void assignItemToFolder(String itemId, String folderId) {
    if (!isWorkspaceItem(itemId)) return;
    final isSpace = _spaces.any((space) => space.id == itemId);
    if (!_workspaceFolders.assign(itemId, folderId, isSpace: isSpace)) return;
    _resetMissingFolder();
    _persistState(workspaceChanged: true);
    notifyListeners();
  }

  /// Exclui apenas a pasta mantendo intactas todas as conversas e espaços (Seção 4).
  void dissolveFolder(String folderId) {
    _workspaceFolders.dissolve(folderId);
    if (_activeFolderId == folderId) {
      _activeFolderId = 'all';
    }
    _persistState(workspaceChanged: true);
    notifyListeners();
  }

  void setExploreSortAscending(bool ascending) {
    _exploreSortAscending = ascending;
    notifyListeners();
  }

  void setExploreSearchQuery(String query) {
    _exploreSearchQuery = query;
    notifyListeners();
  }

  bool joinDiscoverableSpace(Space candidate) {
    // Resolve o registro canônico, mesmo quando um item antigo da UI ainda está visível.
    final published = _publishedSpaces.where((space) => space.id == candidate.id).firstOrNull;
    if (published == null) return false;
    final local = _spaces.where((space) => space.id == published.id).firstOrNull;
    if (local != null) {
      final allowed = published.channels.where((channel) =>
          !channel.permissions.requireApproval || canManageChannelSettings(channel.id));
      if (allowed.isNotEmpty) {
        selectChannel(allowed.first);
        return true;
      }
      if (_isMockMode && published.channels.isEmpty) {
        selectSpace(local);
        return true;
      }
      return false;
    }
    // Sem convite validado, o cliente só abre as comunidades de demonstração.
    if (!_isMockMode || published.channels.isNotEmpty) return false;
    final demo = published.copyWith(channels: [
      Channel(
        id: 'ch_${published.id}_geral',
        spaceId: published.id,
        name: 'geral',
        topic: published.description,
        type: ChannelType.text,
        category: 'COMUNIDADE',
        permissions: const ChannelPermissions(isPublic: true),
      ),
    ]);
    _spaces.add(demo);
    selectSpace(demo);
    return true;
  }

  // ================= CANAIS, MENSAGENS, EDIÇÃO, FIXAÇÃO & SELEÇÃO =================

  void selectChannel(Channel channel) {
    final stored = _findChannel(channel.id);
    if (stored == null || stored.spaceId != channel.spaceId ||
        stored.bannedMembers.contains(_ownWorkspaceIdentity)) return;
    channel = stored;
    _activeArea = NixActiveArea.spaces;
    _currentChannel = channel.copyWith(unreadCount: 0);
    // Zera badge de não lidas no espaço
    final sIdx = _spaces.indexWhere((s) => s.id == channel.spaceId);
    if (sIdx != -1) {
      final chans = _spaces[sIdx].channels.map((c) {
        return c.id == channel.id ? c.copyWith(unreadCount: 0) : c;
      }).toList();
      _spaces[sIdx] = _spaces[sIdx].copyWith(channels: chans);
      _currentSpace = _spaces[sIdx];
      if (!channelsInActiveFolder(_currentSpace).any((entry) => entry.id == channel.id)) {
        _activeFolderId = 'all';
      }
    }
    if (_selectedForumPost?.channelId != channel.id) {
      _selectedForumPost = currentForumPosts.firstOrNull;
    }
    _clearTransientMessageModes();
    notifyListeners();
  }

  void togglePinChannel(String channelId) {
    for (int s = 0; s < _spaces.length; s++) {
      final chans = _spaces[s].channels;
      final cIdx = chans.indexWhere((c) => c.id == channelId);
      if (cIdx != -1) {
        final updated = List<Channel>.from(chans);
        updated[cIdx] = updated[cIdx].copyWith(isPinned: !updated[cIdx].isPinned);
        _spaces[s] = _spaces[s].copyWith(channels: updated);
        if (_currentChannel.id == channelId) _currentChannel = updated[cIdx];
        notifyListeners();
        return;
      }
    }
  }

  void toggleMuteChannel(String channelId) {
    for (int s = 0; s < _spaces.length; s++) {
      final chans = _spaces[s].channels;
      final cIdx = chans.indexWhere((c) => c.id == channelId);
      if (cIdx != -1) {
        final updated = List<Channel>.from(chans);
        updated[cIdx] = updated[cIdx].copyWith(isMuted: !updated[cIdx].isMuted);
        _spaces[s] = _spaces[s].copyWith(channels: updated);
        if (_currentChannel.id == channelId) _currentChannel = updated[cIdx];
        notifyListeners();
        return;
      }
    }
  }

  void _clearTransientMessageModes() {
    _replyingToMessage = null;
    _editingMessage = null;
    _selectedMessageIds.clear();
    _highlightedMessageId = null;
  }

  void startReplyTo(Message message) {
    _editingMessage = null;
    _replyingToMessage = message;
    notifyListeners();
  }

  void cancelReply() {
    _replyingToMessage = null;
    notifyListeners();
  }

  void startEditMessage(Message message) {
    if (!message.isMe) return;
    if (_activeArea == NixActiveArea.spaces && !_currentChannel.permissions.allowEditing) return;
    _replyingToMessage = null;
    _editingMessage = message;
    notifyListeners();
  }

  void cancelEditMessage() {
    _editingMessage = null;
    notifyListeners();
  }

  void saveEditedMessage(String messageId, String newText) {
    editMessage(messageId, newText);
  }

  void editMessage(String messageId, String newText) {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;

    final channelMsgs = _messages[_currentChannel.id];
    if (channelMsgs != null) {
      final idx = channelMsgs.indexWhere((m) => m.id == messageId);
      if (idx != -1 && channelMsgs[idx].isMe && _currentChannel.permissions.allowEditing) {
        channelMsgs[idx] = channelMsgs[idx].copyWith(
          text: trimmed,
          editedAt: DateTime.now(),
        );
        _editingMessage = null;
        notifyListeners();
        return;
      }
    }

    for (int t = 0; t < _directMessages.length; t++) {
      final thread = _directMessages[t];
      final mIdx = thread.messages.indexWhere((m) => m.id == messageId);
      if (mIdx != -1 && thread.messages[mIdx].isMe) {
        final updatedMsgs = List<Message>.from(thread.messages);
        updatedMsgs[mIdx] = updatedMsgs[mIdx].copyWith(
          text: trimmed,
          editedAt: DateTime.now(),
        );
        _directMessages[t] = thread.copyWith(messages: updatedMsgs);
        if (_selectedDm?.id == thread.id) {
          _selectedDm = _directMessages[t];
        }
        _editingMessage = null;
        notifyListeners();
        return;
      }
    }
  }

  void togglePinMessage(String messageId) {
    final channelMsgs = _messages[_currentChannel.id];
    if (channelMsgs != null) {
      final idx = channelMsgs.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        channelMsgs[idx] = channelMsgs[idx].copyWith(isPinned: !channelMsgs[idx].isPinned);
        notifyListeners();
        return;
      }
    }

    for (int t = 0; t < _directMessages.length; t++) {
      final thread = _directMessages[t];
      final mIdx = thread.messages.indexWhere((m) => m.id == messageId);
      if (mIdx != -1) {
        final updatedMsgs = List<Message>.from(thread.messages);
        updatedMsgs[mIdx] = updatedMsgs[mIdx].copyWith(isPinned: !updatedMsgs[mIdx].isPinned);
        _directMessages[t] = thread.copyWith(messages: updatedMsgs);
        if (_selectedDm?.id == thread.id) {
          _selectedDm = _directMessages[t];
        }
        notifyListeners();
        return;
      }
    }
  }

  void highlightMessage(String? messageId) {
    _highlightedMessageId = messageId;
    notifyListeners();
  }

  void toggleMessageSelection(String messageId) {
    if (_selectedMessageIds.contains(messageId)) {
      _selectedMessageIds.remove(messageId);
    } else {
      _selectedMessageIds.add(messageId);
    }
    notifyListeners();
  }

  void clearMessageSelection() {
    _selectedMessageIds.clear();
    notifyListeners();
  }

  void deleteSelectedMessages({bool forEveryone = false}) {
    final ids = List<String>.from(_selectedMessageIds);
    for (final id in ids) {
      deleteMessage(id, forEveryone: forEveryone);
    }
    _selectedMessageIds.clear();
    notifyListeners();
  }

  void forwardSelectedMessages({required String targetId, required bool isChannel}) {
    final msgs = activeConversationMessages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();
    for (final m in msgs) {
      forwardMessage(m, targetId: targetId, isChannel: isChannel);
    }
    _selectedMessageIds.clear();
    notifyListeners();
  }

  void toggleConversationInfoPanel([bool? open]) {
    _isConversationInfoOpen = open ?? !_isConversationInfoOpen;
    notifyListeners();
  }

  void setConversationHistorySearch(String query) {
    _conversationHistorySearch = query;
    notifyListeners();
  }

  bool sendMessage(String text, {List<String> attachments = const []}) {
    if (_panicWipe != null || (text.trim().isEmpty && attachments.isEmpty)) return false;
    if (!_currentChannel.permissions.allowMessages) return false;
    if (attachments.isNotEmpty && !_currentChannel.permissions.allowFiles) return false;
    final myFp = _securityContext.myFingerprint;
    final myId = _userProfile.publicId;
    if (_currentChannel.bannedMembers.contains(myFp) ||
        (myId.isNotEmpty && _currentChannel.bannedMembers.contains(myId)) ||
        _currentChannel.mutedMembers.contains(myFp) ||
        (myId.isNotEmpty && _currentChannel.mutedMembers.contains(myId))) {
      return false;
    }

    if (_editingMessage != null) {
      editMessage(_editingMessage!.id, text);
      return true;
    }

    final reply = _replyingToMessage;
    final newMessage = Message(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      channelId: _currentChannel.id,
      senderName: _userProfile.effectiveDisplayName,
      senderFingerprint: _securityContext.myFingerprint,
      isMe: true,
      text: text.trim(),
      timestamp: DateTime.now(),
      ephemeralSeconds: _selectedEphemeralTimer,
      remainingSeconds: _selectedEphemeralTimer,
      isVerified: true,
      deliveryState: _currentChannel.type == ChannelType.voice ? 'saved' : 'queued',
      attachments: attachments,
      replyToMessageId: reply?.id,
      replyToSenderName: reply?.senderName,
      replyToExcerpt: reply?.text,
    );

    if (!_messages.containsKey(_currentChannel.id)) {
      _messages[_currentChannel.id] = [];
    }
    _messages[_currentChannel.id]!.add(newMessage);
    _replyingToMessage = null;
    notifyListeners();
    return true;
  }

  void toggleMessageReaction(String messageId, String emoji) {
    final channelMsgs = _messages[_currentChannel.id];
    if (channelMsgs != null) {
      final idx = channelMsgs.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        if (!_currentChannel.permissions.allowReactions) return;
        channelMsgs[idx] = _toggleReactionOnMessage(channelMsgs[idx], emoji);
        notifyListeners();
        return;
      }
    }

    for (int t = 0; t < _directMessages.length; t++) {
      final thread = _directMessages[t];
      final mIdx = thread.messages.indexWhere((m) => m.id == messageId);
      if (mIdx != -1) {
        final updatedMsgs = List<Message>.from(thread.messages);
        updatedMsgs[mIdx] = _toggleReactionOnMessage(updatedMsgs[mIdx], emoji);
        _directMessages[t] = thread.copyWith(messages: updatedMsgs);
        if (_selectedDm?.id == thread.id) {
          _selectedDm = _directMessages[t];
        }
        notifyListeners();
        return;
      }
    }

    for (int p = 0; p < _forumPosts.length; p++) {
      final post = _forumPosts[p];
      final cIdx = post.comments.indexWhere((m) => m.id == messageId);
      if (cIdx != -1) {
        if (post.channelId != _currentChannel.id || _isLocallyBanned(_currentChannel) ||
            !_currentChannel.permissions.allowReactions) return;
        final updatedComments = List<Message>.from(post.comments);
        updatedComments[cIdx] = _toggleReactionOnMessage(updatedComments[cIdx], emoji);
        _forumPosts[p] = post.copyWith(comments: updatedComments);
        if (_selectedForumPost?.id == post.id) {
          _selectedForumPost = _forumPosts[p];
        }
        _persistForum();
        notifyListeners();
        return;
      }
    }
  }

  Message _toggleReactionOnMessage(Message msg, String emoji) {
    final currentReactions = Map<String, int>.from(msg.reactions);
    final currentMyReactions = Set<String>.from(msg.myReactions);

    if (currentMyReactions.contains(emoji)) {
      currentMyReactions.remove(emoji);
      final count = (currentReactions[emoji] ?? 1) - 1;
      if (count <= 0) {
        currentReactions.remove(emoji);
      } else {
        currentReactions[emoji] = count;
      }
    } else {
      currentMyReactions.add(emoji);
      currentReactions[emoji] = (currentReactions[emoji] ?? 0) + 1;
    }

    return msg.copyWith(
      reactions: currentReactions,
      myReactions: currentMyReactions,
    );
  }

  void deleteMessage(String messageId, {bool forEveryone = false}) {
    final channelMsgs = _messages[_currentChannel.id];
    if (channelMsgs != null) {
      final idx = channelMsgs.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        if (forEveryone && !_currentChannel.permissions.allowDeletion) return;
        channelMsgs.removeAt(idx);
        notifyListeners();
        return;
      }
    }

    for (int t = 0; t < _directMessages.length; t++) {
      final thread = _directMessages[t];
      final mIdx = thread.messages.indexWhere((m) => m.id == messageId);
      if (mIdx != -1) {
        final updatedMsgs = List<Message>.from(thread.messages)..removeAt(mIdx);
        _directMessages[t] = thread.copyWith(messages: updatedMsgs);
        if (_selectedDm?.id == thread.id) {
          _selectedDm = _directMessages[t];
        }
        notifyListeners();
        return;
      }
    }
  }

  bool forwardMessage(Message original, {required String targetId, required bool isChannel}) {
    if (_activeArea == NixActiveArea.spaces &&
        (!_currentChannel.permissions.allowForwarding || _currentChannel.permissions.restrictExport)) {
      return false;
    }

    final fwdMsg = Message(
      id: 'fwd_${DateTime.now().millisecondsSinceEpoch}_${original.id.hashCode.abs()}',
      channelId: targetId,
      senderName: _userProfile.effectiveDisplayName,
      senderFingerprint: _securityContext.myFingerprint,
      isMe: true,
      text: original.text,
      timestamp: DateTime.now(),
      forwardedFrom: original.senderName,
      attachments: original.attachments,
    );

    if (isChannel) {
      if (!_messages.containsKey(targetId)) {
        _messages[targetId] = [];
      }
      _messages[targetId]!.add(fwdMsg);
    } else {
      final tIdx = _directMessages.indexWhere((d) => d.id == targetId);
      if (tIdx != -1) {
        final updatedMsgs = List<Message>.from(_directMessages[tIdx].messages)..add(fwdMsg);
        _directMessages[tIdx] = _directMessages[tIdx].copyWith(messages: updatedMsgs);
        if (_selectedDm?.id == targetId) {
          _selectedDm = _directMessages[tIdx];
        }
      }
    }
    notifyListeners();
    return true;
  }

  Channel? _findChannel(String id) =>
      _spaces.expand((space) => space.channels).where((channel) => channel.id == id).firstOrNull;

  bool canManageChannelSettings(String channelId) {
    final channel = _findChannel(channelId);
    if (channel == null) return false;
    final identities = {
      _ownWorkspaceIdentity,
      _securityContext.myFingerprint,
      if (_isMockMode) _userProfile.publicId.replaceFirst('NIX-', ''),
    }..remove('');
    return identities.contains(channel.ownerFingerprint) ||
        channel.admins.any(identities.contains) ||
        channel.spaceId == 'local_space' && channel.id == 'general_saved';
  }

  bool canChangeGroupFormat(String channelId) {
    final channel = _findChannel(channelId);
    if (channel == null || !canManageChannelSettings(channelId)) return false;
    final group = _spaces.where((space) => space.id == channel.spaceId).firstOrNull;
    return group?.usesGroupFormat == true && group?.channels.length == 1 &&
        (channel.type == ChannelType.text || channel.type == ChannelType.forum);
  }

  Future<bool> updateChannelSettings(Channel updatedChannel) async {
    final previous = _findChannel(updatedChannel.id);
    if (previous == null || previous.spaceId != updatedChannel.spaceId ||
        !canManageChannelSettings(updatedChannel.id)) return false;

    if (previous.type != updatedChannel.type &&
        (!canChangeGroupFormat(previous.id) ||
            (updatedChannel.type != ChannelType.text && updatedChannel.type != ChannelType.forum))) {
      return false;
    }
    final mayChangeImage = canEditChannelImage(previous);
    final updated = previous.copyWith(
      name: updatedChannel.name,
      topic: updatedChannel.topic,
      type: updatedChannel.type,
      description: updatedChannel.description,
      permissions: updatedChannel.permissions,
      customImagePath: mayChangeImage ? updatedChannel.customImagePath : null,
      clearCustomImage: mayChangeImage && updatedChannel.customImagePath == null,
      admins: updatedChannel.admins,
      moderators: updatedChannel.moderators,
      mutedMembers: updatedChannel.mutedMembers,
      bannedMembers: updatedChannel.bannedMembers,
      auditLogs: updatedChannel.auditLogs,
    );
    _replaceChannel(updated);
    notifyListeners();
    try {
      await _persistState(workspaceChanged: true, reportErrors: true);
      return true;
    } catch (_) {
      if (!_disposed && identical(_findChannel(updated.id), updated)) {
        _replaceChannel(previous);
        notifyListeners();
      }
      return false;
    }
  }

  void _replaceChannel(Channel updated) {
    final index = _spaces.indexWhere((space) => space.id == updated.spaceId);
    if (index == -1) return;
    final space = _spaces[index];
    final replacement = space.copyWith(channels: [
      for (final channel in space.channels)
        channel.id == updated.id ? updated : channel,
    ]);
    _spaces[index] = replacement;
    if (_currentSpace.id == replacement.id) _currentSpace = replacement;
    if (_currentChannel.id == updated.id) _currentChannel = updated;
  }

  final Map<String, int> _channelSenderKeyEpochs = {};

  /// Retorna a época criptográfica atual (Sender Keys) do canal ou grupo.
  int getChannelSenderKeyEpoch(String channelId) =>
      _channelSenderKeyEpochs[channelId] ?? 1;

  /// Rotaciona a época de Sender Keys de um grupo/canal via [SovereignMessenger]
  /// (revogando membros expulsos ou banidos das próximas mensagens).
  Future<int> rotateChannelSenderKeyEpoch({
    required Channel channel,
    String? removedMemberFingerprint,
  }) async {
    final nextEpoch = getChannelSenderKeyEpoch(channel.id) + 1;
    _channelSenderKeyEpochs[channel.id] = nextEpoch;
    final messenger = _sovereignMessenger;
    if (messenger != null && _primaryIdentity != null) {
      final activeMembers = <({String publicId, SimplePublicKey x25519PublicKey})>[
        (
          publicId: _primaryIdentity!.publicId,
          x25519PublicKey: _primaryIdentity!.x25519PublicKey,
        ),
      ];
      final res = await messenger.createOrRotateGroupEpoch(
        groupId: channel.id,
        title: channel.name,
        activeMembers: activeMembers,
        removeMemberPublicId: removedMemberFingerprint,
      );
      _channelSenderKeyEpochs[channel.id] = res.epoch;
      return res.epoch;
    }
    return nextEpoch;
  }

  void applyAdminAction(Channel channel, {required String targetFingerprint, required String action}) {
    final stored = _findChannel(channel.id);
    if (stored == null || !canManageChannelSettings(stored.id)) return;
    channel = stored;
    final admins = List<String>.from(channel.admins);
    final moderators = List<String>.from(channel.moderators);
    final muted = List<String>.from(channel.mutedMembers);
    final banned = List<String>.from(channel.bannedMembers);
    final logs = List<String>.from(channel.auditLogs);

    switch (action) {
      case 'toggle_admin':
        if (admins.contains(targetFingerprint)) {
          admins.remove(targetFingerprint);
          logs.insert(0, 'Administração revogada para $targetFingerprint.');
        } else {
          admins.add(targetFingerprint);
          logs.insert(0, 'Promovido a Administrador: $targetFingerprint.');
        }
        break;
      case 'toggle_mod':
        if (moderators.contains(targetFingerprint)) {
          moderators.remove(targetFingerprint);
          logs.insert(0, 'Moderação revogada para $targetFingerprint.');
        } else {
          moderators.add(targetFingerprint);
          logs.insert(0, 'Promovido a Moderador: $targetFingerprint.');
        }
        break;
      case 'toggle_mute':
        if (muted.contains(targetFingerprint)) {
          muted.remove(targetFingerprint);
          logs.insert(0, 'Silenciamento removido para $targetFingerprint.');
        } else {
          muted.add(targetFingerprint);
          logs.insert(0, 'Membro silenciado: $targetFingerprint.');
        }
        break;
      case 'kick':
        final newEpoch = getChannelSenderKeyEpoch(channel.id) + 1;
        _channelSenderKeyEpochs[channel.id] = newEpoch;
        unawaited(
          rotateChannelSenderKeyEpoch(
            channel: channel,
            removedMemberFingerprint: targetFingerprint,
          ),
        );
        logs.insert(
          0,
          'Membro expulso do canal: $targetFingerprint · Sender Key rotacionada para Época #$newEpoch.',
        );
        break;
      case 'ban':
        if (!banned.contains(targetFingerprint)) {
          banned.add(targetFingerprint);
        }
        final newEpoch = getChannelSenderKeyEpoch(channel.id) + 1;
        _channelSenderKeyEpochs[channel.id] = newEpoch;
        unawaited(
          rotateChannelSenderKeyEpoch(
            channel: channel,
            removedMemberFingerprint: targetFingerprint,
          ),
        );
        logs.insert(
          0,
          'Banimento criptográfico aplicado: $targetFingerprint · Sender Key rotacionada para Época #$newEpoch.',
        );
        break;
    }

    updateChannelSettings(channel.copyWith(
      admins: admins,
      moderators: moderators,
      mutedMembers: muted,
      bannedMembers: banned,
      auditLogs: logs,
    ));
  }

  // ================= ARQUIVO CANÔNICO & PUBLICAÇÕES ASSINADAS (FASE 9.1) =================

  NixIdentity? _fallbackArchiveIdentity;
  final Map<String, Map<String, dynamic>> _inMemoryArchiveObjects = {};

  Future<NixIdentity> _getOrCreateArchiveSignerIdentity() async {
    if (_primaryIdentity != null) return _primaryIdentity!;
    _fallbackArchiveIdentity ??= await NixIdentity.generate();
    return _fallbackArchiveIdentity!;
  }

  /// Cria ou edita (via `supersedesHash`) um artigo canônico assinado com Ed25519,
  /// sanitizando HTML/RichText com o tokenizador determinístico de [NixArchiveService].
  Future<Publication> publishCanonicalArticle({
    required String channelId,
    required String title,
    required String rawContent,
    List<String> claimTexts = const [],
    String? supersedesHash,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw ArgumentError('O título do artigo não pode ser vazio.');
    }
    final sanitizedContent = NixArchiveService.sanitizeRichTextHtml(rawContent.trim());
    final cleanClaims = claimTexts
        .map((c) => NixArchiveService.sanitizeRichTextHtml(c.trim()))
        .where((c) => c.isNotEmpty)
        .toList();
    final claimRecords = <({String claimId, String text})>[
      for (int i = 0; i < cleanClaims.length; i++)
        (claimId: 'c${i + 1}', text: cleanClaims[i]),
    ];

    final previous = supersedesHash == null ? null :
        await _archiveRepo?.getObject(supersedesHash) ?? _inMemoryArchiveObjects[supersedesHash];
    final visibility = _findChannel(channelId)?.permissions.isPublic == true &&
        (supersedesHash == null || previous?['visibility'] == 'public')
        ? 'public' : 'restricted';
    final signer = await _getOrCreateArchiveSignerIdentity();
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    String cidHash;

    if (_archiveService != null) {
      cidHash = await _archiveService!.publishArticle(
        author: signer,
        title: cleanTitle,
        rawHtmlBody: sanitizedContent,
        claims: claimRecords,
        supersedesHash: supersedesHash,
        createdAtMs: nowMs,
        visibility: visibility,
      );
    } else {
      final canonicalObj = <String, dynamic>{
        'schema': NixArchiveService.articleSchemaV1,
        'title': cleanTitle,
        'bodyHtml': sanitizedContent,
        'authorEd25519': signer.ed25519PublicHex,
        'visibility': visibility,
        'createdAt': nowMs,
        if (supersedesHash != null) 'supersedes': supersedesHash,
        'claims': claimRecords
            .map((c) => {'claimId': c.claimId, 'text': c.text})
            .toList(),
      };
      final canonicalBytes = NixArchiveService.canonicalizeJsonBytes(canonicalObj);
      cidHash = NixArchiveService.computeContentHashHex(canonicalBytes);
      final sig = await signer.sign(canonicalBytes);
      _inMemoryArchiveObjects[cidHash] = {
        'hash': cidHash,
        'kind': 'article',
        'visibility': visibility,
        'canonical_bytes': canonicalBytes,
        'author_public': Uint8List.fromList(signer.ed25519PublicKey.bytes),
        'signature': Uint8List.fromList(sig),
        'supersedes_hash': supersedesHash,
        'created_at': nowMs,
      };
    }

    final pub = Publication(
      id: 'pub_$nowMs',
      channelId: channelId,
      title: cleanTitle,
      authorPersona: _userProfile.effectiveDisplayName,
      authorFingerprint: signer.publicId,
      contentMarkdown: sanitizedContent,
      claimsCount: cleanClaims.length,
      refutationsCount: 0,
      cidHash: cidHash,
      publishedAt: DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
      isVerifiedSignature: true,
      supersedesHash: supersedesHash,
      claims: cleanClaims,
    );

    final updatedList = List<Publication>.from(_publications[channelId] ?? const []);
    updatedList.insert(0, pub);
    _publications[channelId] = updatedList;
    notifyListeners();
    return pub;
  }

  /// Publica uma refutação criptograficamente vinculada (`targetCidHash`, `targetClaimId`).
  Future<String> refuteCanonicalArticle({
    required String channelId,
    required String targetCidHash,
    required String targetClaimId,
    required String rationale,
  }) async {
    final cleanRationale = NixArchiveService.sanitizeRichTextHtml(rationale.trim());
    if (cleanRationale.isEmpty) {
      throw ArgumentError('A fundamentação da refutação não pode ser vazia.');
    }
    final target = await _archiveRepo?.getObject(targetCidHash) ??
        _inMemoryArchiveObjects[targetCidHash];
    final visibility = _findChannel(channelId)?.permissions.isPublic == true &&
        target?['visibility'] == 'public' ? 'public' : 'restricted';
    final signer = await _getOrCreateArchiveSignerIdentity();
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    String refHash;

    if (_archiveService != null &&
        await _archiveRepo?.getObject(targetCidHash) != null) {
      refHash = await _archiveService!.publishRefutation(
        author: signer,
        targetHash: targetCidHash,
        targetClaimId: targetClaimId,
        rationaleHtml: cleanRationale,
        createdAtMs: nowMs,
        visibility: visibility,
      );
    } else {
      final canonicalObj = <String, dynamic>{
        'schema': NixArchiveService.refutationSchemaV1,
        'targetHash': targetCidHash,
        'targetClaimId': targetClaimId,
        'rationaleHtml': cleanRationale,
        'authorEd25519': signer.ed25519PublicHex,
        'visibility': visibility,
        'createdAt': nowMs,
      };
      final canonicalBytes = NixArchiveService.canonicalizeJsonBytes(canonicalObj);
      refHash = NixArchiveService.computeContentHashHex(canonicalBytes);
      final sig = await signer.sign(canonicalBytes);
      _inMemoryArchiveObjects[refHash] = {
        'hash': refHash,
        'kind': 'refutation',
        'visibility': visibility,
        'canonical_bytes': canonicalBytes,
        'author_public': Uint8List.fromList(signer.ed25519PublicKey.bytes),
        'signature': Uint8List.fromList(sig),
        'supersedes_hash': null,
        'created_at': nowMs,
      };
    }

    final list = List<Publication>.from(_publications[channelId] ?? const []);
    final idx = list.indexWhere((p) => p.cidHash == targetCidHash);
    if (idx != -1) {
      final target = list[idx];
      final summary =
          '[$targetClaimId] $cleanRationale (Ref CID: ${refHash.substring(0, 10)})';
      list[idx] = target.copyWith(
        refutationsCount: target.refutationsCount + 1,
        refutationSummaries: [...target.refutationSummaries, summary],
      );
      _publications[channelId] = list;
    }
    notifyListeners();
    return refHash;
  }

  /// Verifica criptograficamente o hash SHA-256 canônico e a assinatura Ed25519 do artigo.
  Future<bool> verifyCanonicalArticleIntegrity(String cidHash) async {
    if (_archiveService != null) {
      final row = await _archiveRepo?.getObject(cidHash);
      if (row != null) {
        return _archiveService!.verifyStoredObject(cidHash);
      }
    }
    final mem = _inMemoryArchiveObjects[cidHash];
    if (mem == null) return false;
    final bytes = mem['canonical_bytes'] as List<int>;
    final authorPub = mem['author_public'] as List<int>;
    final sig = mem['signature'] as List<int>;
    final actualHash = NixArchiveService.computeContentHashHex(bytes);
    if (actualHash != cidHash) return false;
    return NixIdentity.verify(
      message: bytes,
      signatureBytes: sig,
      ed25519PublicKey: SimplePublicKey(authorPub, type: KeyPairType.ed25519),
    );
  }

  /// Retorna a cadeia histórica de revisões (`supersedes`) a partir de `cidHash`.
  Future<List<Map<String, dynamic>>> getCanonicalArticleHistory(
    String cidHash,
  ) async {
    if (_archiveService != null) {
      final dbChain = await _archiveService!.getRevisionHistory(cidHash);
      if (dbChain.isNotEmpty) return dbChain;
    }
    final chain = <Map<String, dynamic>>[];
    String? cursor = cidHash;
    final visited = <String>{};
    while (cursor != null && cursor.isNotEmpty && !visited.contains(cursor)) {
      visited.add(cursor);
      final mem = _inMemoryArchiveObjects[cursor];
      if (mem != null) {
        chain.add(mem);
        cursor = mem['supersedes_hash'] as String?;
        continue;
      }
      // Fallback para fixtures de publicação carregadas sem banco
      Publication? pubMatch;
      for (final list in _publications.values) {
        for (final p in list) {
          if (p.cidHash == cursor) {
            pubMatch = p;
            break;
          }
        }
        if (pubMatch != null) break;
      }
      if (pubMatch == null) break;
      chain.add({
        'hash': pubMatch.cidHash,
        'kind': 'article',
        'supersedes_hash': pubMatch.supersedesHash,
      });
      cursor = pubMatch.supersedesHash;
    }
    return chain;
  }

  void selectForumPost(ForumPost? post) {
    final canonical = post == null
        ? null
        : currentForumPosts.where((entry) => entry.id == post.id).firstOrNull;
    if (post != null && canonical == null) return;
    _selectedForumPost = canonical;
    notifyListeners();
  }

  bool addForumComment(String postId, String text) {
    final clean = text.trim();
    if (clean.isEmpty || clean.length > 4000 || !canWriteForum) return false;
    final idx = _forumPosts.indexWhere(
      (post) => post.id == postId && post.channelId == _currentChannel.id,
    );
    if (idx == -1) return false;
    final newComment = Message(
      id: 'fmsg_${DateTime.now().microsecondsSinceEpoch}',
      channelId: postId,
      senderName: _userProfile.effectiveDisplayName,
      senderFingerprint: _securityContext.myFingerprint,
      isMe: true,
      text: clean,
      deliveryState: 'saved',
      timestamp: DateTime.now(),
    );
    final updatedComments = List<Message>.from(_forumPosts[idx].comments)..add(newComment);
    _forumPosts[idx] = _forumPosts[idx].copyWith(comments: updatedComments);
    if (_selectedForumPost?.id == postId) {
      _selectedForumPost = _forumPosts[idx];
    }
    _persistForum();
    notifyListeners();
    return true;
  }

  final _forumTags = <String, Map<String, String>>{};

  Map<String, String> forumTagsFor(String channelId) =>
      Map.unmodifiable(_forumTags[channelId] ?? const <String, String>{});

  bool _isLocallyBanned(Channel channel) =>
      channel.bannedMembers.contains(_ownWorkspaceIdentity) ||
      channel.bannedMembers.contains(_securityContext.myFingerprint);

  bool get canWriteForum =>
      !_disposed && _panicWipe == null &&
      (_isMockMode || _forumStore != null) &&
      _currentChannel.type == ChannelType.forum &&
      _currentChannel.permissions.allowMessages &&
      !_isLocallyBanned(_currentChannel) &&
      !_currentChannel.mutedMembers.contains(_ownWorkspaceIdentity) &&
      !_currentChannel.mutedMembers.contains(_securityContext.myFingerprint);

  bool get canManageForumTags {
    if (_disposed || _panicWipe != null || _currentChannel.type != ChannelType.forum ||
        (!_isMockMode && _forumStore == null) || _isLocallyBanned(_currentChannel)) return false;
    final identity = _userProfile.publicId;
    final fingerprint = _securityContext.myFingerprint;
    return [identity, fingerprint].where((id) => id.isNotEmpty).any(
      (id) => _currentChannel.ownerFingerprint == id ||
          _currentChannel.admins.contains(id),
    );
  }

  bool createForumTag(String name, String icon) {
    final clean = name.trim();
    final symbol = icon.trim();
    if (!canManageForumTags || clean.isEmpty || clean.length > 32 ||
        clean.toLowerCase() == 'todos' || symbol.length > 16) {
      return false;
    }
    final tags = _forumTags.putIfAbsent(_currentChannel.id, () => {});
    if (tags.keys.any((tag) => tag.toLowerCase() == clean.toLowerCase())) return false;
    tags[clean] = symbol.isEmpty ? '🏷️' : symbol;
    _persistForum();
    notifyListeners();
    return true;
  }

  bool createForumPost({
    required String title,
    required String description,
    required List<String> tags,
    List<ArchiveImage> images = const [],
  }) {
    final cleanTitle = title.trim();
    final detail = description.trim();
    if (!canWriteForum || cleanTitle.isEmpty || cleanTitle.length > 120 ||
        detail.length > 8000 || tags.length > 8 ||
        tags.any((tag) => !forumTagsFor(_currentChannel.id).containsKey(tag))) return false;
    try {
      ArchiveImage.validateLimits(images);
    } on FormatException {
      return false;
    }
    final newPost = ForumPost(
      id: 'post_${DateTime.now().microsecondsSinceEpoch}',
      channelId: _currentChannel.id,
      title: cleanTitle,
      authorName: _userProfile.effectiveDisplayName,
      authorFingerprint: _securityContext.myFingerprint,
      createdAt: DateTime.now(),
      tags: List.unmodifiable(tags),
      description: detail,
      images: List.unmodifiable(images.indexed.map((entry) =>
          ForumImageSpec(label: 'Imagem ${entry.$1 + 1}', subtitle: '', code: '', image: entry.$2))),
      comments: const [],
    );
    _forumPosts.insert(0, newPost);
    _selectedForumPost = newPost;
    _persistForum();
    notifyListeners();
    return true;
  }

  void setEphemeralTimer(int seconds) {
    _selectedEphemeralTimer = seconds;
    notifyListeners();
  }

  // ================= CHAMADAS DE VOZ (DELEGADAS PARA CALLVIEWMODEL) =================

  List<Message> messagesForChannel(String channelId) =>
      List.unmodifiable(_messages[channelId] ?? const []);

  void joinCall(Channel channel) {
    final stored = _findChannel(channel.id);
    if (_disposed || _panicWipe != null || stored == null ||
        stored.type != ChannelType.voice || _isLocallyBanned(stored)) return;
    final localIdentity = _ownWorkspaceIdentity;
    _calls.joinCall(stored, onlineMembers: [
      Member(
        id: localIdentity,
        name: _userProfile.effectiveDisplayName,
        roleName: 'Você',
        role: MemberRole.member,
        fingerprint: _securityContext.myFingerprint,
        isVerified: primaryIdentity != null,
      ),
    ]);
  }

  void leaveCall() {
    _calls.leaveCall();
  }

  void toggleMute() {
    _calls.toggleMute();
    updateSettings(_settings.copyWith(microphoneMuted: _calls.isMuted));
  }

  void toggleDeafen() {
    _calls.toggleDeafen();
  }

  void toggleMembersPanel() {
    _isMembersPanelOpen = !_isMembersPanelOpen;
    notifyListeners();
  }

  // ================= CRIAÇÃO DE CANAIS & ESPAÇOS =================

  bool canEditSpaceImage(Space space) => space.ownerFingerprint == _ownWorkspaceIdentity ||
      (space.ownerFingerprint == null && space.id == 'local_space');

  bool canEditChannelImage(Channel channel) => channel.ownerFingerprint == _ownWorkspaceIdentity ||
      (channel.spaceId == 'local_space' && channel.id == 'general_saved');

  String get _ownWorkspaceIdentity => _userProfile.publicId.isNotEmpty ? _userProfile.publicId : _securityContext.myFingerprint;

  void editSpaceImage(String spaceId, String? path) {
    final idx = _spaces.indexWhere((space) => space.id == spaceId);
    if (idx < 0 || !canEditSpaceImage(_spaces[idx])) return;
    final updated = _spaces[idx].copyWith(customImagePath: path, clearCustomImage: path == null);
    _spaces[idx] = updated;
    if (_currentSpace.id == spaceId) _currentSpace = updated;
    _persistState(workspaceChanged: true);
    notifyListeners();
  }

  void editChannelImage(String channelId, String? path) {
    final channel = _spaces.expand((space) => space.channels).where((channel) => channel.id == channelId).firstOrNull;
    if (channel == null || !canEditChannelImage(channel)) return;
    updateChannelSettings(channel.copyWith(customImagePath: path, clearCustomImage: path == null));
  }

  void createChannel({
    required String name,
    required ChannelType type,
    required String topic,
    required String category,
    String? customImagePath,
  }) {
    if (_currentSpace.isSingleChat) return;
    final cleanName = name.replaceAll(' ', '-').toLowerCase();
    final newChannel = Channel(
      id: 'ch_${DateTime.now().millisecondsSinceEpoch}',
      spaceId: _currentSpace.id,
      name: cleanName,
      topic: topic.isNotEmpty ? topic : 'Novo tópico de discussão segura.',
      type: type,
      category: category,
      ownerFingerprint: _ownWorkspaceIdentity,
      customImagePath: customImagePath,
    );

    final updatedChannels = List<Channel>.from(_currentSpace.channels)..add(newChannel);
    final updatedSpace = _currentSpace.copyWith(channels: updatedChannels);

    final spaceIndex = _spaces.indexWhere((s) => s.id == _currentSpace.id);
    if (spaceIndex != -1) {
      _spaces[spaceIndex] = updatedSpace;
      _currentSpace = updatedSpace;
      _currentChannel = newChannel;
    }

    _persistState(workspaceChanged: true);
    notifyListeners();
  }

  void createSpace({
    required String name,
    required String description,
    required String emoji,
    String? customImagePath,
    bool? withTopics,
  }) {
    final initials = name
        .trim()
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();
    final spaceId = 'space_${DateTime.now().millisecondsSinceEpoch}';
    final newSpace = Space(
      id: spaceId,
      name: name.trim(),
      initials: initials.isNotEmpty ? initials : 'NX',
      description: description,
      isPublic: false,
      usesGroupFormat: withTopics != null,
      iconEmoji: emoji.isNotEmpty ? emoji : 'NX',
      customImagePath: customImagePath,
      ownerFingerprint: _ownWorkspaceIdentity,
      channels: [
        Channel(
          id: 'ch_geral_${DateTime.now().millisecondsSinceEpoch}',
          spaceId: spaceId,
          name: 'geral',
          topic: 'Tópico principal deste espaço.',
          type: withTopics == true ? ChannelType.forum : ChannelType.text,
          category: 'COMUNIDADE',
          ownerFingerprint: _ownWorkspaceIdentity,
        ),
      ],
    );

    _spaces.add(newSpace);
    _currentSpace = newSpace;
    _currentChannel = newSpace.channels.first;
    _activeArea = NixActiveArea.spaces;
    _persistState(workspaceChanged: true);
    notifyListeners();
  }

  // ChangeNotifier.dispose é síncrono. A limpeza continua sem bloquear a UI;
  // falhas de um serviço não impedem os demais nem deixam o cofre desbloqueado.
  Future<void> _disposeServices() async {
    await flushPreferences();
    try {
      await _catalogOpen;
      await _catalogDatabase?.close();
    } catch (_) {
      // O catálogo público tem um ciclo de vida independente do cofre.
    }
    _activeRelayClient = null;
    _activeMailboxCredentials = null;
    try {
      _embeddedTor.dispose();
    } catch (_) {
      // Continua a liberação dos recursos locais mesmo se o Tor falhar.
    }
    try {
      await _hardwareRadioBridge.stopNativeBleMesh();
      await _hardwareRadioBridge.disconnectRNode();
    } catch (_) {}
    try {
      _bluetoothMesh.setMeshEnabled(false);
      _bluetoothMesh.dispose();
    } catch (_) {
      // Continua o fechamento do banco mesmo se a malha falhar.
    }
    await _scheduledRun;
    await _interactiveDirectSend;
    try {
      await _localDatabase?.close();
    } catch (_) {
      // O bloqueio do cofre é obrigatório mesmo se o fechamento falhar.
    } finally {
      if (_activeMasterKey != null) {
        _activeMasterKey!.fillRange(0, _activeMasterKey!.length, 0);
        _activeMasterKey = null;
      }
      _localDatabase = null;
      _identityRepo = null;
      _keyVault.lock();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scheduledWakeup?.cancel();
    _calls.dispose();
    _peerHover.dispose();
    _starwireFilters.dispose();
    _moneroFilters.dispose();
    _navigation.dispose();
    _settingsVm.dispose();
    _chatVm.dispose();
    _identityVm.dispose();
    _mediaVm.dispose();
    _archiveVm.dispose();
    _torWatchdogTimer?.cancel();
    _torBootstrapSub?.cancel();
    _blePeerSub?.cancel();
    _bleRxSub?.cancel();
    unawaited(_disposeServices());
    super.dispose();
  }
}
