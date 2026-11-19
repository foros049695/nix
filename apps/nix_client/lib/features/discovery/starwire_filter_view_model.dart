import 'package:flutter/foundation.dart';
import '../../core/models/github_repo.dart';

/// ViewModel desacoplado para filtragem, busca e ordenação do catálogo Starwire (GitHub Discovery).
/// Isola as alterações de busca e seleção de chips de tópico/linguagem, prevenindo reconstruções
/// da casca global do aplicativo.
class StarwireFilterViewModel extends ChangeNotifier {
  List<GithubRepository> _allRepos = const [];
  String _searchQuery = '';
  String _selectedTopic = 'Todos';
  String _selectedLanguage = 'Todas';
  String _sortBy = 'stars'; // 'stars', 'trending', 'updated'
  bool _disposed = false;

  StarwireFilterViewModel({List<GithubRepository> initialRepos = const []})
      : _allRepos = initialRepos;

  String get searchQuery => _searchQuery;
  String get selectedTopic => _selectedTopic;
  String get selectedLanguage => _selectedLanguage;
  String get sortBy => _sortBy;

  void updateRepos(List<GithubRepository> repos) {
    if (_disposed) return;
    _allRepos = repos;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    if (_disposed) return;
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
  }

  void setSelectedTopic(String topic) {
    if (_disposed) return;
    if (_selectedTopic == topic) return;
    _selectedTopic = topic;
    notifyListeners();
  }

  void setSelectedLanguage(String language) {
    if (_disposed) return;
    if (_selectedLanguage == language) return;
    _selectedLanguage = language;
    notifyListeners();
  }

  void setSortBy(String sort) {
    if (_disposed) return;
    if (_sortBy == sort) return;
    _sortBy = sort;
    notifyListeners();
  }

  void resetFilters() {
    if (_disposed) return;
    _searchQuery = '';
    _selectedTopic = 'Todos';
    _selectedLanguage = 'Todas';
    _sortBy = 'stars';
    notifyListeners();
  }

  List<GithubRepository> get filteredRepos {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _allRepos.where((repo) {
      if (q.isNotEmpty) {
        final matchesName = repo.name.toLowerCase().contains(q);
        final matchesOwner = repo.owner.toLowerCase().contains(q);
        final matchesDesc = repo.description.toLowerCase().contains(q);
        final matchesTopic = repo.topics.any((t) => t.toLowerCase().contains(q));
        if (!matchesName && !matchesOwner && !matchesDesc && !matchesTopic) return false;
      }
      if (_selectedTopic != 'Todos') {
        if (!repo.topics.any((t) => t.toLowerCase() == _selectedTopic.toLowerCase()) &&
            repo.category.toLowerCase() != _selectedTopic.toLowerCase()) {
          return false;
        }
      }
      if (_selectedLanguage != 'Todas') {
        if (repo.language != _selectedLanguage) return false;
      }
      return true;
    }).toList();

    if (_sortBy == 'trending') {
      filtered.sort((a, b) => b.starsThisWeek.compareTo(a.starsThisWeek));
    } else if (_sortBy == 'stars') {
      filtered.sort((a, b) => b.starsCount.compareTo(a.starsCount));
    } else {
      filtered.sort((a, b) => b.updatedDate.compareTo(a.updatedDate));
    }
    return filtered;
  }

  Map<String, int> get languageCounts {
    final counts = <String, int>{};
    for (final r in _allRepos) {
      final lang = r.language.trim().isEmpty ? 'Markdown' : r.language.trim();
      counts[lang] = (counts[lang] ?? 0) + 1;
    }
    final sortedEntries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map<String, int>.fromEntries(sortedEntries.take(8));
  }

  Map<String, int> get categoryCounts {
    final counts = <String, int>{};
    for (final r in _allRepos) {
      final cat = r.category.trim().isEmpty ? 'Open Source' : r.category.trim();
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
    final sortedEntries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map<String, int>.fromEntries(sortedEntries.take(6));
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
