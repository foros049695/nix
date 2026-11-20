import '../core/models/space.dart';

/// Organiza pastas sem ter acesso a navegação, arquivos ou ao cofre.
class WorkspaceFolderStore {
  List<SpaceFolder> folders = [];

  SpaceFolder? find(String id) =>
      folders.where((folder) => folder.id == id).firstOrNull;

  bool toggleExpanded(String id) {
    final folder = find(id);
    if (folder == null) return false;
    return replace(folder.copyWith(isExpanded: !folder.isExpanded));
  }

  bool create(
    String name,
    List<String> spaceIds, {
    required String iconName,
    required int colorValue,
    required List<String> conversationIds,
  }) {
    final cleaned = name.trim();
    if (cleaned.isEmpty || (spaceIds.isEmpty && conversationIds.isEmpty)) {
      return false;
    }
    folders.add(SpaceFolder(
      id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
      name: cleaned,
      iconName: iconName,
      colorValue: colorValue,
      spaceIds: spaceIds.toSet().toList(),
      conversationIds: conversationIds.toSet().toList(),
      isExpanded: true,
    ));
    return true;
  }

  bool replace(SpaceFolder folder) {
    final index = folders.indexWhere((entry) => entry.id == folder.id);
    if (index < 0) return false;
    folders[index] = folder.copyWith(
      spaceIds: folder.spaceIds.toSet().toList(),
      conversationIds: folder.conversationIds.toSet().toList(),
    );
    return true;
  }

  bool reorder(int oldIndex, int newIndex) {
    return _move(oldIndex, newIndex > oldIndex ? newIndex - 1 : newIndex);
  }

  bool move(String id, String targetId) => _move(
        folders.indexWhere((folder) => folder.id == id),
        folders.indexWhere((folder) => folder.id == targetId),
      );

  bool _move(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= folders.length ||
        newIndex < 0 ||
        newIndex >= folders.length) {
      return false;
    }
    final moved = folders.removeAt(oldIndex);
    folders.insert(newIndex, moved);
    return true;
  }

  void removeMembership(String id) {
    folders = folders.expand((folder) {
      if (!folder.spaceIds.contains(id) &&
          !folder.conversationIds.contains(id)) {
        return [folder];
      }
      final updated = folder.copyWith(
        spaceIds: folder.spaceIds.where((entry) => entry != id).toList(),
        conversationIds:
            folder.conversationIds.where((entry) => entry != id).toList(),
      );
      return [
        if (folder.id == 'all' ||
            updated.spaceIds.isNotEmpty ||
            updated.conversationIds.isNotEmpty)
          updated,
      ];
    }).toList();
  }

  bool assign(String itemId, String folderId, {required bool isSpace}) {
    final destination = find(folderId);
    if (destination == null ||
        destination.spaceIds.contains(itemId) ||
        destination.conversationIds.contains(itemId)) {
      return false;
    }
    removeMembership(itemId);
    return replace(destination.copyWith(
      spaceIds: [...destination.spaceIds, if (isSpace) itemId],
      conversationIds: [...destination.conversationIds, if (!isSpace) itemId],
      isExpanded: true,
    ));
  }

  void dissolve(String id) => folders.removeWhere((folder) => folder.id == id);
}
