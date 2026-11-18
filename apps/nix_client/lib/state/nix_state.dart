import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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
import '../core/theme/nix_palette.dart';
import '../core/security/security_context.dart';
import 'mock_data.dart';

enum NixActiveArea {
  homePrivate, // Área Inicial de Conversas Privadas (Friends, Requests, Transações, Updates + Card ID quando vazia)
  spaces,      // Espaços / Servidores e Canais (Texto, Fórum, Call, Publicação)
  explore,     // Explorar Canais e Grupos Públicos (do menos populoso ao mais populoso)
  github,      // Aba GitHub Discovery (Inspirada no starwire.foo)
  moneroP2p,   // Aba Monero P2P Marketplace (Inspirada no Trocador.app)
}

class NixState extends ChangeNotifier {
  late List<Space> _spaces;
  late List<SpaceFolder> _folders;
  late List<Space> _discoverableSpaces;
  late Space _currentSpace;
  late Channel _currentChannel;
  late Map<String, List<Message>> _messages;
  late Map<String, List<Publication>> _publications;
  late List<ForumPost> _forumPosts;
  late List<Member> _members;
  late UserProfile _userProfile;
  late List<DirectMessageThread> _directMessages;
  late List<ContactRequest> _contactRequests;
  late List<XmrTransactionRecord> _transactions;
  late List<SystemUpdateRecord> _systemUpdates;
  late List<MoneroP2pOrder> _moneroOrders;
  late List<GithubRepository> _githubRepos;
  UserSettings _settings = const UserSettings();

  CallState _callState = const CallState();
  final SecurityContext _securityContext = const SecurityContext(myPersona: 'GUS');

  NixActiveArea _activeArea = NixActiveArea.spaces;
  HomeSubTab _homeSubTab = HomeSubTab.cardId; // Quando vazio, preenchido pelo Card ID
  DirectMessageThread? _selectedDm;
  ForumPost? _selectedForumPost;

  // Hover preview de Card ID em Solicitações
  ContactRequest? _hoveredContactRequest;

  bool _isProfileOverlayOpen = false;
  bool _isSettingsOpenInOverlay = false;
  SettingsCategory _activeSettingsCategory = SettingsCategory.appearance;

  bool _isMembersPanelOpen = false;
  int _selectedEphemeralTimer = 0;
  bool _exploreSortAscending = true; // Padrão: do menos populoso ao mais populoso
  String _exploreSearchQuery = '';

  // Filtros GitHub Discovery
  String _githubSearchQuery = '';
  String _githubSelectedTopic = 'Todos';
  String _githubSelectedLanguage = 'Todas';
  String _githubSortBy = 'stars'; // 'stars', 'updated'

  // Filtros Monero P2P
  MoneroP2pSide _moneroSelectedSide = MoneroP2pSide.sell; // Default: Quero comprar XMR (vendo fiat)
  String _moneroSelectedFiat = 'BRL'; // 'BRL', 'USD', 'EUR'
  String _moneroSelectedPaymentMethod = 'Todos'; // 'Todos', 'PIX', 'Dinheiro', 'SEPA', 'TED'
  String _moneroSearchQuery = '';

  Timer? _callTimer;

  // Estado Tor Onion
  final String _onionAddress = 'gpoun4vo5v5h3cmcfdxtudm3nlzxri3qzjd7fhbvy6oep2ap67g4qvyd.onion';
  final bool _isTorRunning = true;

  NixState() {
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
    _githubRepos = MockData.getInitialGithubRepos();
    loadStarwireRepos();
  }

  /// Carrega o catálogo real Starwire (4.188 repositórios) do asset JSON em background
  Future<void> loadStarwireRepos() async {
    try {
      final jsonString = await rootBundle.loadString('assets/data/starwire_repos.json');
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is List) {
        final parsed = decoded
            .map((item) => GithubRepository.fromStarwireJson(item as Map<String, dynamic>))
            .toList();
        if (parsed.isNotEmpty) {
          _githubRepos = parsed;
          notifyListeners();
        }
      }
    } catch (_) {
      // Fallback gracioso para dados locais quando em testes unitários sem asset bundle
    }
  }

  // Getters principais
  List<Space> get spaces => _spaces;
  List<SpaceFolder> get folders => _folders;
  Space get currentSpace => _currentSpace;
  Channel get currentChannel => _currentChannel;
  List<Message> get currentMessages => _messages[_currentChannel.id] ?? [];
  List<Publication> get currentPublications => _publications[_currentChannel.id] ?? [];
  List<ForumPost> get currentForumPosts =>
      _forumPosts.where((p) => p.channelId == _currentChannel.id).toList();
  ForumPost? get selectedForumPost => _selectedForumPost;
  List<Member> get members => _members;
  CallState get callState => _callState;
  SecurityContext get securityContext => _securityContext;
  UserProfile get userProfile => _userProfile;
  UserSettings get settings => _settings;

  NixPalette get currentPalette => NixPalette.fromType(
        _settings.paletteType,
        _settings.customPaletteColor != null ? Color(_settings.customPaletteColor!) : null,
      );

  NixActiveArea get activeArea => _activeArea;
  HomeSubTab get homeSubTab => _homeSubTab;
  List<DirectMessageThread> get directMessages => _directMessages;
  DirectMessageThread? get selectedDm => _selectedDm;
  List<ContactRequest> get contactRequests => _contactRequests;
  ContactRequest? get hoveredContactRequest => _hoveredContactRequest;
  List<XmrTransactionRecord> get transactions => _transactions;
  List<SystemUpdateRecord> get systemUpdates => _systemUpdates;
  List<MoneroP2pOrder> get moneroOrders => _moneroOrders;
  List<GithubRepository> get githubRepos => _githubRepos;

  bool get isProfileOverlayOpen => _isProfileOverlayOpen;
  bool get isSettingsOpenInOverlay => _isSettingsOpenInOverlay;
  SettingsCategory get activeSettingsCategory => _activeSettingsCategory;
  bool get isMembersPanelOpen => _isMembersPanelOpen;
  int get selectedEphemeralTimer => _selectedEphemeralTimer;
  bool get exploreSortAscending => _exploreSortAscending;
  String get exploreSearchQuery => _exploreSearchQuery;

  // Getters Tor Onion
  String get onionAddress => _onionAddress;
  bool get isTorRunning => _isTorRunning;
  bool get isTorFailClosed => _settings.transportProfile.contains('Fail-Closed');

  // Getters Filtros GitHub
  String get githubSearchQuery => _githubSearchQuery;
  String get githubSelectedTopic => _githubSelectedTopic;
  String get githubSelectedLanguage => _githubSelectedLanguage;
  String get githubSortBy => _githubSortBy;

  List<GithubRepository> get filteredGithubRepos {
    final q = _githubSearchQuery.trim().toLowerCase();
    final filtered = _githubRepos.where((repo) {
      if (q.isNotEmpty) {
        final matchesName = repo.name.toLowerCase().contains(q);
        final matchesOwner = repo.owner.toLowerCase().contains(q);
        final matchesDesc = repo.description.toLowerCase().contains(q);
        if (!matchesName && !matchesOwner && !matchesDesc) return false;
      }
      if (_githubSelectedTopic != 'Todos') {
        if (!repo.topics.contains(_githubSelectedTopic.toLowerCase())) return false;
      }
      if (_githubSelectedLanguage != 'Todas') {
        if (repo.language != _githubSelectedLanguage) return false;
      }
      return true;
    }).toList();

    if (_githubSortBy == 'stars') {
      filtered.sort((a, b) => b.starsCount.compareTo(a.starsCount));
    } else {
      filtered.sort((a, b) => b.updatedDate.compareTo(a.updatedDate));
    }
    return filtered;
  }

  // Getters Filtros Monero P2P
  MoneroP2pSide get moneroSelectedSide => _moneroSelectedSide;
  String get moneroSelectedFiat => _moneroSelectedFiat;
  String get moneroSelectedPaymentMethod => _moneroSelectedPaymentMethod;
  String get moneroSearchQuery => _moneroSearchQuery;

  List<MoneroP2pOrder> get filteredMoneroOrders {
    final q = _moneroSearchQuery.trim().toLowerCase();
    return _moneroOrders.where((order) {
      if (order.side != _moneroSelectedSide) return false;
      if (order.fiatCurrency != _moneroSelectedFiat) return false;
      if (_moneroSelectedPaymentMethod != 'Todos') {
        if (!order.paymentMethod.toLowerCase().contains(_moneroSelectedPaymentMethod.toLowerCase())) {
          return false;
        }
      }
      if (q.isNotEmpty) {
        final matchesTrader = order.traderName.toLowerCase().contains(q);
        final matchesMethod = order.paymentMethod.toLowerCase().contains(q);
        final matchesNotes = order.notes.toLowerCase().contains(q);
        if (!matchesTrader && !matchesMethod && !matchesNotes) return false;
      }
      return true;
    }).toList();
  }

  /// Lista de grupos públicos filtrada e ordenada (padrão: do menos populoso ao mais populoso).
  List<Space> get filteredDiscoverableSpaces {
    final query = _exploreSearchQuery.trim().toLowerCase();
    final filtered = _discoverableSpaces.where((s) {
      if (query.isEmpty) return true;
      return s.name.toLowerCase().contains(query) ||
          s.description.toLowerCase().contains(query) ||
          s.categoryTag.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) => _exploreSortAscending
        ? a.memberCount.compareTo(b.memberCount)
        : b.memberCount.compareTo(a.memberCount));
    return filtered;
  }

  // ================= NAVEGAÇÃO DE ÁREAS =================

  void openHomePrivateArea({bool resetToCardId = false}) {
    _activeArea = NixActiveArea.homePrivate;
    if (resetToCardId) {
      _homeSubTab = HomeSubTab.cardId;
      _selectedDm = null;
    }
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

  void openMoneroP2pArea() {
    _activeArea = NixActiveArea.moneroP2p;
    notifyListeners();
  }

  void selectHomeSubTab(HomeSubTab tab) {
    if (tab == HomeSubTab.moneroP2p) {
      openMoneroP2pArea();
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
    notifyListeners();
  }

  void setHoveredContactRequest(ContactRequest? req) {
    if (_hoveredContactRequest?.id != req?.id) {
      _hoveredContactRequest = req;
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
    notifyListeners();
  }

  void sendDirectMessage(String text) {
    if (_selectedDm == null || text.trim().isEmpty) return;
    final newMsg = Message(
      id: 'dm_msg_${DateTime.now().millisecondsSinceEpoch}',
      channelId: _selectedDm!.id,
      senderName: _userProfile.effectiveDisplayName,
      senderFingerprint: _securityContext.myFingerprint,
      isMe: true,
      text: text.trim(),
      timestamp: DateTime.now(),
      ephemeralSeconds: _selectedEphemeralTimer,
      remainingSeconds: _selectedEphemeralTimer,
    );
    final idx = _directMessages.indexWhere((d) => d.id == _selectedDm!.id);
    if (idx != -1) {
      final updatedMsgs = List<Message>.from(_directMessages[idx].messages)..add(newMsg);
      _directMessages[idx] = _directMessages[idx].copyWith(messages: updatedMsgs);
      _selectedDm = _directMessages[idx];
      notifyListeners();
    }
  }

  void acceptContactRequest(String requestId) {
    final idx = _contactRequests.indexWhere((r) => r.id == requestId);
    if (idx == -1) return;
    final req = _contactRequests.removeAt(idx);
    _hoveredContactRequest = null;
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
    _directMessages.insert(0, newDm);
    notifyListeners();
  }

  void declineContactRequest(String requestId) {
    _contactRequests.removeWhere((r) => r.id == requestId);
    _hoveredContactRequest = null;
    notifyListeners();
  }

  // ================= MONERO P2P MARKETPLACE =================

  void setMoneroSide(MoneroP2pSide side) {
    _moneroSelectedSide = side;
    notifyListeners();
  }

  void setMoneroFiat(String fiat) {
    _moneroSelectedFiat = fiat;
    notifyListeners();
  }

  void setMoneroPaymentMethod(String method) {
    _moneroSelectedPaymentMethod = method;
    notifyListeners();
  }

  void setMoneroSearchQuery(String query) {
    _moneroSearchQuery = query;
    notifyListeners();
  }

  void createMoneroOrder(MoneroP2pOrder order) {
    _moneroOrders.insert(0, order);
    notifyListeners();
  }

  void openTradeWithOrder(MoneroP2pOrder order) {
    // Abre canal direto E2EE com o anunciante
    final existingDm = _directMessages.firstWhere(
      (dm) => dm.peerPublicId == order.traderPublicId,
      orElse: () {
        final newDm = DirectMessageThread(
          id: 'dm_trade_${DateTime.now().millisecondsSinceEpoch}',
          peerName: order.traderName,
          peerPublicId: order.traderPublicId,
          statusText: 'Negociação P2P Monero: ${order.formattedPrice}',
          isOnline: order.isOnline,
          isVerified: true,
          trustLevel: order.trustLevel,
          messages: [
            Message(
              id: 'dm_trade_init_${DateTime.now().millisecondsSinceEpoch}',
              channelId: 'trade_${order.id}',
              senderName: order.traderName,
              senderFingerprint: order.traderPublicId.replaceFirst('NIX-', ''),
              isMe: false,
              text: 'Iniciando negociação da oferta #${order.id.split('_').last}: ${order.notes}\nLimite: ${order.formattedLimits}',
              timestamp: DateTime.now(),
            ),
          ],
        );
        _directMessages.insert(0, newDm);
        return newDm;
      },
    );
    selectDirectMessage(existingDm);
  }

  // ================= GITHUB DISCOVERY =================

  void setGithubSearchQuery(String query) {
    _githubSearchQuery = query;
    notifyListeners();
  }

  void setGithubTopic(String topic) {
    _githubSelectedTopic = topic;
    notifyListeners();
  }

  void setGithubLanguage(String language) {
    _githubSelectedLanguage = language;
    notifyListeners();
  }

  void setGithubSortBy(String sortBy) {
    _githubSortBy = sortBy;
    notifyListeners();
  }

  void toggleSaveRepoInAcervo(String repoId) {
    final idx = _githubRepos.indexWhere((r) => r.id == repoId);
    if (idx == -1) return;

    final repo = _githubRepos[idx];
    final isNowSaved = !repo.isSavedInAcervo;
    _githubRepos[idx] = repo.copyWith(isSavedInAcervo: isNowSaved);

    if (isNowSaved) {
      // Adiciona ao acervo do perfil
      final culturalItem = CulturalItem(
        id: 'repo_${repo.name}',
        title: repo.name,
        creatorOrYear: '${repo.language} · ${repo.owner}',
        category: CulturalCategory.github,
        rating: repo.formattedStars,
        monogram: repo.name.length >= 2 ? repo.name.substring(0, 2).toUpperCase() : 'GH',
        toneShade: 75,
        isPublicInCardId: true,
        repositoryUrl: repo.htmlUrl,
        starsCount: repo.starsCount,
        language: repo.language,
        license: repo.license,
        updatedDate: repo.updatedDate,
      );
      addCulturalItem(culturalItem);
    } else {
      // Remove do acervo
      _userProfile = _userProfile.copyWith(
        culturalItems: _userProfile.culturalItems
            .where((i) => i.id != 'repo_${repo.name}' && i.id != repo.id)
            .toList(),
      );
    }
    notifyListeners();
  }

  // ================= OVERLAY DE PERFIL, CARD ID & CONFIGURAÇÕES =================

  void openProfileOverlay({bool startInSettings = false, SettingsCategory? category}) {
    _isProfileOverlayOpen = true;
    _isSettingsOpenInOverlay = startInSettings;
    if (category != null) {
      _activeSettingsCategory = category;
    }
    notifyListeners();
  }

  void closeProfileOverlay() {
    _isProfileOverlayOpen = false;
    _isSettingsOpenInOverlay = false;
    notifyListeners();
  }

  void transitionToSettings({SettingsCategory? category}) {
    _isProfileOverlayOpen = true;
    _isSettingsOpenInOverlay = true;
    if (category != null) {
      _activeSettingsCategory = category;
    }
    notifyListeners();
  }

  void transitionBackToCardId() {
    _isSettingsOpenInOverlay = false;
    notifyListeners();
  }

  void selectSettingsCategory(SettingsCategory category) {
    _activeSettingsCategory = category;
    notifyListeners();
  }

  // ================= ATUALIZAÇÃO DO PERFIL & PASSAPORTE CULTURAL =================

  void updateProfile({
    String? displayName,
    String? bio,
    String? currentActivity,
    String? avatarStyle,
    String? customAvatarPath,
    bool clearCustomAvatar = false,
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
    );
    notifyListeners();
  }

  void addCulturalItem(CulturalItem item) {
    final updated = List<CulturalItem>.from(_userProfile.culturalItems)..insert(0, item);
    _userProfile = _userProfile.copyWith(culturalItems: updated);
    notifyListeners();
  }

  void removeCulturalItem(String itemId) {
    final updated = _userProfile.culturalItems.where((i) => i.id != itemId).toList();
    _userProfile = _userProfile.copyWith(culturalItems: updated);
    notifyListeners();
  }

  void toggleItemCardIdVisibility(String itemId) {
    final updated = _userProfile.culturalItems.map((item) {
      if (item.id == itemId) {
        return item.copyWith(isPublicInCardId: !item.isPublicInCardId);
      }
      return item;
    }).toList();
    _userProfile = _userProfile.copyWith(culturalItems: updated);
    notifyListeners();
  }

  // ================= CONFIGURAÇÕES & DISPOSITIVOS =================

  void updatePalette(NixPaletteType type, [int? customColor]) {
    _settings = _settings.copyWith(
      paletteType: type,
      customPaletteColor: customColor,
    );
    notifyListeners();
  }

  void updateCardIdVisibility(String visibility) {
    _settings = _settings.copyWith(cardIdVisibility: visibility);
    notifyListeners();
  }

  void toggleFloatingWindowMode(bool isFloating) {
    _settings = _settings.copyWith(floatingWindowMode: isFloating);
    notifyListeners();
  }

  void updateSettings(UserSettings newSettings) {
    _settings = newSettings;
    notifyListeners();
  }

  void toggleConnector(String connectorId) {
    final updated = _settings.connectors.map((c) {
      if (c.id == connectorId) {
        return c.copyWith(isEnabled: !c.isEnabled);
      }
      return c;
    }).toList();
    _settings = _settings.copyWith(connectors: updated);
    notifyListeners();
  }

  void unblockUser(String publicId) {
    final updated = _settings.blockedUserIds.where((id) => id != publicId).toList();
    _settings = _settings.copyWith(blockedUserIds: updated);
    notifyListeners();
  }

  void blockNewUser(String publicId) {
    if (publicId.trim().isEmpty) return;
    final updated = List<String>.from(_settings.blockedUserIds)..add(publicId.trim());
    _settings = _settings.copyWith(blockedUserIds: updated);
    notifyListeners();
  }

  void authorizeDevice(String deviceName, String fingerprint) {
    final newDev = AuthorizedDevice(
      id: 'dev_${DateTime.now().millisecondsSinceEpoch}',
      deviceName: deviceName.trim().isNotEmpty ? deviceName.trim() : 'Novo Dispositivo Nix',
      clientVersion: 'Nix Client v0.2.0',
      lastSeenLabel: 'Agora',
      isCurrent: false,
      fingerprint: fingerprint.trim().isNotEmpty ? fingerprint.trim() : 'NX-7700-AA21',
    );
    final updated = List<AuthorizedDevice>.from(_settings.devices)..add(newDev);
    _settings = _settings.copyWith(devices: updated);
    notifyListeners();
  }

  void revokeDevice(String deviceId) {
    final updated = _settings.devices.where((d) => d.id != deviceId).toList();
    _settings = _settings.copyWith(devices: updated);
    notifyListeners();
  }

  // ================= ESPAÇOS, PASTAS (FOLDERS) & EXPLORAR =================

  void selectSpace(Space space) {
    _activeArea = NixActiveArea.spaces;
    if (_currentSpace.id == space.id) {
      notifyListeners();
      return;
    }
    _currentSpace = space;
    if (space.channels.isNotEmpty) {
      _currentChannel = space.channels.first;
    }
    notifyListeners();
  }

  void toggleFolderExpanded(String folderId) {
    final idx = _folders.indexWhere((f) => f.id == folderId);
    if (idx != -1) {
      _folders[idx] = _folders[idx].copyWith(isExpanded: !_folders[idx].isExpanded);
      notifyListeners();
    }
  }

  void createSpaceFolder(String name, List<String> spaceIds) {
    if (name.trim().isEmpty || spaceIds.isEmpty) return;
    _folders = _folders
        .map((f) => f.copyWith(
              spaceIds: f.spaceIds.where((id) => !spaceIds.contains(id)).toList(),
            ))
        .where((f) => f.spaceIds.isNotEmpty)
        .toList();

    _folders.add(SpaceFolder(
      id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      spaceIds: spaceIds,
      isExpanded: true,
    ));
    notifyListeners();
  }

  /// Arrastar um espaço sobre outro para agrupá-los em uma nova pasta (estilo Discord/Android)
  void combineSpacesIntoFolder(String sourceSpaceId, String targetSpaceId, [String? folderName]) {
    if (sourceSpaceId == targetSpaceId) return;

    // Remove ambos de outras pastas se já estiverem
    _folders = _folders
        .map((f) => f.copyWith(
              spaceIds: f.spaceIds
                  .where((id) => id != sourceSpaceId && id != targetSpaceId)
                  .toList(),
            ))
        .where((f) => f.spaceIds.isNotEmpty)
        .toList();

    final sourceSpace = _spaces.firstWhere((s) => s.id == sourceSpaceId, orElse: () => _spaces.first);
    final targetSpace = _spaces.firstWhere((s) => s.id == targetSpaceId, orElse: () => _spaces.first);

    final defaultName = folderName ?? '${targetSpace.initials} & ${sourceSpace.initials}';

    _folders.add(SpaceFolder(
      id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
      name: defaultName,
      spaceIds: [targetSpaceId, sourceSpaceId],
      isExpanded: true,
    ));
    notifyListeners();
  }

  /// Arrastar um espaço para dentro de uma pasta existente
  void addSpaceToFolder(String spaceId, String folderId) {
    final fIdx = _folders.indexWhere((f) => f.id == folderId);
    if (fIdx == -1) return;

    // Se já estiver na pasta, não duplica
    if (_folders[fIdx].spaceIds.contains(spaceId)) return;

    // Remove de outras pastas
    _folders = _folders
        .map((f) => f.copyWith(
              spaceIds: f.spaceIds.where((id) => id != spaceId).toList(),
            ))
        .where((f) => f.spaceIds.isNotEmpty)
        .toList();

    final targetIdx = _folders.indexWhere((f) => f.id == folderId);
    if (targetIdx != -1) {
      final updatedList = List<String>.from(_folders[targetIdx].spaceIds)..add(spaceId);
      _folders[targetIdx] = _folders[targetIdx].copyWith(spaceIds: updatedList, isExpanded: true);
    }
    notifyListeners();
  }

  void dissolveFolder(String folderId) {
    _folders.removeWhere((f) => f.id == folderId);
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

  void joinDiscoverableSpace(Space discovered) {
    final existingIdx = _spaces.indexWhere((s) => s.id == discovered.id);
    if (existingIdx != -1) {
      selectSpace(_spaces[existingIdx]);
      return;
    }
    final newSpace = discovered.copyWith(
      channels: [
        Channel(
          id: 'ch_${discovered.id}_geral',
          spaceId: discovered.id,
          name: 'geral',
          topic: discovered.description,
          type: ChannelType.text,
          category: 'COMUNIDADE',
        ),
      ],
    );
    _spaces.add(newSpace);
    selectSpace(newSpace);
  }

  // ================= CANAIS, MENSAGENS, REAÇÕES & FÓRUM =================

  void selectChannel(Channel channel) {
    _activeArea = NixActiveArea.spaces;
    _currentChannel = channel;
    if (channel.type == ChannelType.forum) {
      final posts = currentForumPosts;
      if (posts.isNotEmpty && (_selectedForumPost == null || _selectedForumPost!.channelId != channel.id)) {
        _selectedForumPost = posts.first;
      }
    }
    notifyListeners();
  }

  void sendMessage(String text) {
    if (text.trim().isEmpty) return;

    final newMessage = Message(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      channelId: _currentChannel.id,
      senderName: _userProfile.effectiveDisplayName,
      senderFingerprint: _securityContext.myFingerprint,
      isMe: true,
      text: text.trim(),
      timestamp: DateTime.now(),
      ephemeralSeconds: _selectedEphemeralTimer,
      remainingSeconds: _selectedEphemeralTimer,
      isVerified: true,
    );

    if (!_messages.containsKey(_currentChannel.id)) {
      _messages[_currentChannel.id] = [];
    }
    _messages[_currentChannel.id]!.add(newMessage);
    notifyListeners();
  }

  void toggleMessageReaction(String messageId, String emoji) {
    // 1. Procura nas mensagens do canal ativo
    final channelMsgs = _messages[_currentChannel.id];
    if (channelMsgs != null) {
      final idx = channelMsgs.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        channelMsgs[idx] = _toggleReactionOnMessage(channelMsgs[idx], emoji);
        notifyListeners();
        return;
      }
    }

    // 2. Procura nas mensagens diretas (DM)
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

    // 3. Procura nos comentários do fórum
    for (int p = 0; p < _forumPosts.length; p++) {
      final post = _forumPosts[p];
      final cIdx = post.comments.indexWhere((m) => m.id == messageId);
      if (cIdx != -1) {
        final updatedComments = List<Message>.from(post.comments);
        updatedComments[cIdx] = _toggleReactionOnMessage(updatedComments[cIdx], emoji);
        _forumPosts[p] = post.copyWith(comments: updatedComments);
        if (_selectedForumPost?.id == post.id) {
          _selectedForumPost = _forumPosts[p];
        }
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
    // 1. Canal ativo
    final channelMsgs = _messages[_currentChannel.id];
    if (channelMsgs != null) {
      final idx = channelMsgs.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        channelMsgs.removeAt(idx);
        notifyListeners();
        return;
      }
    }

    // 2. DM
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

  void forwardMessage(Message original, {required String targetId, required bool isChannel}) {
    final fwdMsg = Message(
      id: 'fwd_${DateTime.now().millisecondsSinceEpoch}',
      channelId: targetId,
      senderName: _userProfile.effectiveDisplayName,
      senderFingerprint: _securityContext.myFingerprint,
      isMe: true,
      text: original.text,
      timestamp: DateTime.now(),
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
  }

  void updateChannelSettings(Channel updatedChannel) {
    for (int s = 0; s < _spaces.length; s++) {
      final space = _spaces[s];
      final cIdx = space.channels.indexWhere((c) => c.id == updatedChannel.id);
      if (cIdx != -1) {
        final updatedChannels = List<Channel>.from(space.channels);
        updatedChannels[cIdx] = updatedChannel;
        _spaces[s] = space.copyWith(channels: updatedChannels);
        if (_currentChannel.id == updatedChannel.id) {
          _currentChannel = updatedChannel;
        }
        notifyListeners();
        return;
      }
    }
  }

  void selectForumPost(ForumPost? post) {
    _selectedForumPost = post;
    notifyListeners();
  }

  void addForumComment(String postId, String text) {
    if (text.trim().isEmpty) return;
    final idx = _forumPosts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;
    final newComment = Message(
      id: 'fmsg_${DateTime.now().millisecondsSinceEpoch}',
      channelId: postId,
      senderName: _userProfile.effectiveDisplayName,
      senderFingerprint: _securityContext.myFingerprint,
      isMe: true,
      text: text.trim(),
      timestamp: DateTime.now(),
    );
    final updatedComments = List<Message>.from(_forumPosts[idx].comments)..add(newComment);
    _forumPosts[idx] = _forumPosts[idx].copyWith(comments: updatedComments);
    if (_selectedForumPost?.id == postId) {
      _selectedForumPost = _forumPosts[idx];
    }
    notifyListeners();
  }

  void createForumPost({
    required String title,
    required String description,
    required List<String> tags,
  }) {
    if (title.trim().isEmpty) return;
    final newPost = ForumPost(
      id: 'post_${DateTime.now().millisecondsSinceEpoch}',
      channelId: _currentChannel.id,
      title: title.trim(),
      authorName: _userProfile.effectiveDisplayName,
      authorFingerprint: _securityContext.myFingerprint,
      createdAt: DateTime.now(),
      tags: tags.isEmpty ? const ['Discussão'] : tags,
      description: description.trim().isEmpty ? 'Tópico aberto para análise da comunidade.' : description.trim(),
      images: const [
        ForumImageSpec(label: 'ANEXO #01', subtitle: 'EXIF Removido', code: 'ATT-01'),
        ForumImageSpec(label: 'ANEXO #02', subtitle: 'Hash Verificado', code: 'ATT-02'),
      ],
      comments: const [],
    );
    _forumPosts.insert(0, newPost);
    _selectedForumPost = newPost;
    notifyListeners();
  }

  void setEphemeralTimer(int seconds) {
    _selectedEphemeralTimer = seconds;
    notifyListeners();
  }

  // ================= CHAMADAS DE VOZ =================

  void joinCall(Channel channel) {
    if (_callState.isConnected && _callState.activeChannelId == channel.id) {
      return;
    }

    _callTimer?.cancel();
    _callState = CallState(
      activeChannelId: channel.id,
      activeChannelName: channel.name,
      isConnected: true,
      isMuted: false,
      isDeafened: false,
      participants: _members.where((m) => m.isOnline).toList(),
      durationSeconds: 0,
    );

    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _callState = _callState.copyWith(
        durationSeconds: _callState.durationSeconds + 1,
      );
      notifyListeners();
    });

    notifyListeners();
  }

  void leaveCall() {
    _callTimer?.cancel();
    _callState = const CallState();
    notifyListeners();
  }

  void toggleMute() {
    _callState = _callState.copyWith(isMuted: !_callState.isMuted);
    notifyListeners();
  }

  void toggleDeafen() {
    _callState = _callState.copyWith(
      isDeafened: !_callState.isDeafened,
      isMuted: !_callState.isDeafened ? true : _callState.isMuted,
    );
    notifyListeners();
  }

  void toggleMembersPanel() {
    _isMembersPanelOpen = !_isMembersPanelOpen;
    notifyListeners();
  }

  // ================= CRIAÇÃO DE CANAIS & ESPAÇOS =================

  void createChannel({
    required String name,
    required ChannelType type,
    required String topic,
    required String category,
  }) {
    final cleanName = name.replaceAll(' ', '-').toLowerCase();
    final newChannel = Channel(
      id: 'ch_${DateTime.now().millisecondsSinceEpoch}',
      spaceId: _currentSpace.id,
      name: cleanName,
      topic: topic.isNotEmpty ? topic : 'Novo tópico de discussão segura.',
      type: type,
      category: category,
    );

    final updatedChannels = List<Channel>.from(_currentSpace.channels)..add(newChannel);
    final updatedSpace = _currentSpace.copyWith(channels: updatedChannels);

    final spaceIndex = _spaces.indexWhere((s) => s.id == _currentSpace.id);
    if (spaceIndex != -1) {
      _spaces[spaceIndex] = updatedSpace;
      _currentSpace = updatedSpace;
      _currentChannel = newChannel;
    }

    notifyListeners();
  }

  void createSpace({
    required String name,
    required String description,
    required String emoji,
  }) {
    final initials = name
        .trim()
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();
    final newSpace = Space(
      id: 'space_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      initials: initials.isNotEmpty ? initials : 'NX',
      description: description,
      iconEmoji: emoji.isNotEmpty ? emoji : 'NX',
      channels: [
        Channel(
          id: 'ch_geral_${DateTime.now().millisecondsSinceEpoch}',
          spaceId: 'space_${DateTime.now().millisecondsSinceEpoch}',
          name: 'geral',
          topic: 'Tópico principal deste espaço.',
          type: ChannelType.text,
          category: 'COMUNIDADE',
        ),
      ],
    );

    _spaces.add(newSpace);
    _discoverableSpaces.add(newSpace);
    _currentSpace = newSpace;
    _currentChannel = newSpace.channels.first;
    _activeArea = NixActiveArea.spaces;
    notifyListeners();
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    super.dispose();
  }
}
