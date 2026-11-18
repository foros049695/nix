import 'dart:async';
import 'package:flutter/material.dart';
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
import '../core/security/security_context.dart';
import 'mock_data.dart';

enum NixActiveArea {
  homePrivate, // Área Inicial de Conversas Privadas (Friends, Requests, Transações, Updates + Card ID quando vazia)
  spaces,      // Espaços / Servidores e Canais (Texto, Fórum, Call, Publicação)
  explore,     // Explorar Canais e Grupos Públicos (do menos populoso ao mais populoso)
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
  UserSettings _settings = const UserSettings();

  CallState _callState = const CallState();
  final SecurityContext _securityContext = const SecurityContext(myPersona: 'GUS');

  NixActiveArea _activeArea = NixActiveArea.spaces;
  HomeSubTab _homeSubTab = HomeSubTab.cardId; // Quando vazio, preenchido pelo Card ID
  DirectMessageThread? _selectedDm;
  ForumPost? _selectedForumPost;

  bool _isProfileOverlayOpen = false;
  bool _isSettingsOpenInOverlay = false;
  SettingsCategory _activeSettingsCategory = SettingsCategory.notifications;

  bool _isMembersPanelOpen = false;
  int _selectedEphemeralTimer = 0;
  bool _exploreSortAscending = true; // Padrão: do menos populoso ao mais populoso
  String _exploreSearchQuery = '';
  Timer? _callTimer;

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

  NixActiveArea get activeArea => _activeArea;
  HomeSubTab get homeSubTab => _homeSubTab;
  List<DirectMessageThread> get directMessages => _directMessages;
  DirectMessageThread? get selectedDm => _selectedDm;
  List<ContactRequest> get contactRequests => _contactRequests;
  List<XmrTransactionRecord> get transactions => _transactions;
  List<SystemUpdateRecord> get systemUpdates => _systemUpdates;

  bool get isProfileOverlayOpen => _isProfileOverlayOpen;
  bool get isSettingsOpenInOverlay => _isSettingsOpenInOverlay;
  SettingsCategory get activeSettingsCategory => _activeSettingsCategory;
  bool get isMembersPanelOpen => _isMembersPanelOpen;
  int get selectedEphemeralTimer => _selectedEphemeralTimer;
  bool get exploreSortAscending => _exploreSortAscending;
  String get exploreSearchQuery => _exploreSearchQuery;

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

  void selectHomeSubTab(HomeSubTab tab) {
    _activeArea = NixActiveArea.homePrivate;
    _homeSubTab = tab;
    if (tab != HomeSubTab.directChat) {
      _selectedDm = null;
    }
    notifyListeners();
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
      senderName: _userProfile.displayName,
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
    final newDm = DirectMessageThread(
      id: 'dm_${DateTime.now().millisecondsSinceEpoch}',
      peerName: req.peerName,
      peerPublicId: req.peerPublicId,
      statusText: 'Contato verificado recém-adicionado',
      isOnline: true,
      isVerified: true,
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
    // Limite seguro de tamanho e sanitização
    final cleanBio = bio != null
        ? (bio.trim().length > 180 ? bio.trim().substring(0, 180) : bio.trim())
        : null;
    final cleanName = displayName != null && displayName.trim().isNotEmpty
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
    // Remove esses espaços de outras pastas antes de agrupar
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
      senderName: _userProfile.displayName,
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
    final list = _messages[_currentChannel.id];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    final currentReactions = Map<String, int>.from(list[idx].reactions);
    currentReactions[emoji] = (currentReactions[emoji] ?? 0) + 1;
    list[idx] = list[idx].copyWith(reactions: currentReactions);
    notifyListeners();
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
      senderName: _userProfile.displayName,
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
      authorName: _userProfile.displayName,
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
