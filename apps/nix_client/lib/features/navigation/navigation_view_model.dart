import 'package:flutter/foundation.dart';
import '../../core/models/direct_message.dart';
import '../../core/models/user_settings.dart';
import '../../state/nix_state.dart';

/// ViewModel desacoplado para navegação, áreas ativas, painéis laterais e overlays (Fase 17 / Etapa 8).
class NavigationViewModel extends ChangeNotifier {
  NixActiveArea _activeArea;
  HomeSubTab _homeSubTab;
  String _activeFolderId;
  ConversationFilter _conversationFilter;
  String _conversationSearchQuery = '';
  bool _isWindowMaximized = false;
  bool _isProfileOverlayOpen = false;
  bool _isSettingsOpenInOverlay = false;
  SettingsCategory _activeSettingsCategory = SettingsCategory.appearance;
  bool _isMembersPanelOpen = false;
  bool _isConversationInfoOpen = false;
  String _conversationHistorySearch = '';
  int _selectedEphemeralTimer = 0;
  bool _exploreSortAscending = true;
  String _exploreSearchQuery = '';

  NavigationViewModel({
    NixActiveArea initialArea = NixActiveArea.spaces,
    HomeSubTab initialSubTab = HomeSubTab.cardId,
    String initialFolderId = 'all',
    ConversationFilter initialFilter = ConversationFilter.all,
  })  : _activeArea = initialArea,
        _homeSubTab = initialSubTab,
        _activeFolderId = initialFolderId,
        _conversationFilter = initialFilter;

  // Getters
  NixActiveArea get activeArea => _activeArea;
  HomeSubTab get homeSubTab => _homeSubTab;
  String get activeFolderId => _activeFolderId;
  ConversationFilter get conversationFilter => _conversationFilter;
  String get conversationSearchQuery => _conversationSearchQuery;
  bool get isWindowMaximized => _isWindowMaximized;
  bool get isProfileOverlayOpen => _isProfileOverlayOpen;
  bool get isSettingsOpenInOverlay => _isSettingsOpenInOverlay;
  SettingsCategory get activeSettingsCategory => _activeSettingsCategory;
  bool get isMembersPanelOpen => _isMembersPanelOpen;
  bool get isConversationInfoOpen => _isConversationInfoOpen;
  String get conversationHistorySearch => _conversationHistorySearch;
  int get selectedEphemeralTimer => _selectedEphemeralTimer;
  bool get exploreSortAscending => _exploreSortAscending;
  String get exploreSearchQuery => _exploreSearchQuery;

  // Setters & Actions
  void setActiveArea(NixActiveArea area) {
    if (_activeArea != area) {
      _activeArea = area;
      notifyListeners();
    }
  }

  void setHomeSubTab(HomeSubTab tab) {
    if (_homeSubTab != tab) {
      _homeSubTab = tab;
      notifyListeners();
    }
  }

  void setActiveFolderId(String folderId) {
    if (_activeFolderId != folderId) {
      _activeFolderId = folderId;
      notifyListeners();
    }
  }

  void setConversationFilter(ConversationFilter filter) {
    if (_conversationFilter != filter) {
      _conversationFilter = filter;
      notifyListeners();
    }
  }

  void setConversationSearchQuery(String query) {
    if (_conversationSearchQuery != query) {
      _conversationSearchQuery = query;
      notifyListeners();
    }
  }

  void toggleWindowMaximized() {
    _isWindowMaximized = !_isWindowMaximized;
    notifyListeners();
  }

  void setProfileOverlayOpen(bool open) {
    if (_isProfileOverlayOpen != open) {
      _isProfileOverlayOpen = open;
      notifyListeners();
    }
  }

  void setSettingsOpenInOverlay(bool open, {SettingsCategory? category}) {
    bool changed = false;
    if (_isSettingsOpenInOverlay != open) {
      _isSettingsOpenInOverlay = open;
      changed = true;
    }
    if (category != null && _activeSettingsCategory != category) {
      _activeSettingsCategory = category;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void setActiveSettingsCategory(SettingsCategory category) {
    if (_activeSettingsCategory != category) {
      _activeSettingsCategory = category;
      notifyListeners();
    }
  }

  void setMembersPanelOpen(bool open) {
    if (_isMembersPanelOpen != open) {
      _isMembersPanelOpen = open;
      notifyListeners();
    }
  }

  void setConversationInfoOpen(bool open) {
    if (_isConversationInfoOpen != open) {
      _isConversationInfoOpen = open;
      notifyListeners();
    }
  }

  void setConversationHistorySearch(String query) {
    if (_conversationHistorySearch != query) {
      _conversationHistorySearch = query;
      notifyListeners();
    }
  }

  void setSelectedEphemeralTimer(int seconds) {
    if (_selectedEphemeralTimer != seconds) {
      _selectedEphemeralTimer = seconds;
      notifyListeners();
    }
  }

  void setExploreSearchQuery(String query) {
    if (_exploreSearchQuery != query) {
      _exploreSearchQuery = query;
      notifyListeners();
    }
  }

  void toggleExploreSort() {
    _exploreSortAscending = !_exploreSortAscending;
    notifyListeners();
  }
}
