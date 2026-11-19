import 'package:flutter/foundation.dart';
import '../../core/archive/nix_archive_service.dart';
import '../../core/database/repositories.dart';
import '../../core/models/publication.dart';
import '../../core/replication/replication_coordinator.dart';

/// Status de verificação criptográfica em cache para a interface do Archive.
enum ArchiveCryptoStatus {
  verified,
  invalidSignature,
  notVerified,
  verificationError,
}

/// ViewModel desacoplado para o Nix Archive, publicações, revisões, comentários e refutações (Etapa 8).
class ArchiveViewModel extends ChangeNotifier {
  NixArchiveService? _archiveService;
  ArchiveRepository? _archiveRepo;
  NixReplicationCoordinator? _replicationCoordinator;

  final Map<String, List<Publication>> _publications = {};
  final Map<String, ArchiveCryptoStatus> _verificationCache = {};
  final Map<String, List<Map<String, dynamic>>> _commentsCache = {};
  final Map<String, List<Map<String, dynamic>>> _refutationsCache = {};

  // Rascunho persistido em memória / auto-save
  String? _draftTitle;
  String? _draftContent;
  List<String> _draftClaims = [];
  String? _draftChannelId;

  ArchiveViewModel({
    NixArchiveService? archiveService,
    ArchiveRepository? archiveRepo,
    NixReplicationCoordinator? replicationCoordinator,
    Map<String, List<Publication>>? initialPublications,
  })  : _archiveService = archiveService,
        _archiveRepo = archiveRepo,
        _replicationCoordinator = replicationCoordinator {
    if (initialPublications != null) {
      _publications.addAll(initialPublications);
    }
  }

  // Getters
  Map<String, List<Publication>> get publications => Map.unmodifiable(_publications);
  Map<String, ArchiveCryptoStatus> get verificationCache =>
      Map.unmodifiable(_verificationCache);

  String? get draftTitle => _draftTitle;
  String? get draftContent => _draftContent;
  List<String> get draftClaims => List.unmodifiable(_draftClaims);
  String? get draftChannelId => _draftChannelId;
  bool get hasDraft => (_draftTitle?.isNotEmpty ?? false) || (_draftContent?.isNotEmpty ?? false);

  NixArchiveService? get archiveService => _archiveService;
  ArchiveRepository? get archiveRepo => _archiveRepo;
  NixReplicationCoordinator? get replicationCoordinator => _replicationCoordinator;

  void attachServices({
    NixArchiveService? archiveService,
    ArchiveRepository? archiveRepo,
    NixReplicationCoordinator? replicationCoordinator,
  }) {
    if (archiveService != null) _archiveService = archiveService;
    if (archiveRepo != null) _archiveRepo = archiveRepo;
    if (replicationCoordinator != null) _replicationCoordinator = replicationCoordinator;
    notifyListeners();
  }

  List<Publication> getPublicationsForChannel(String channelId) =>
      _publications[channelId] ?? const [];

  void setPublications(String channelId, List<Publication> pubs) {
    _publications[channelId] = List.from(pubs);
    notifyListeners();
  }

  void addPublication(String channelId, Publication pub) {
    final list = List<Publication>.from(_publications[channelId] ?? const []);
    list.insert(0, pub);
    _publications[channelId] = list;
    _verificationCache[pub.cidHash] = pub.isVerifiedSignature
        ? ArchiveCryptoStatus.verified
        : ArchiveCryptoStatus.notVerified;
    notifyListeners();
  }

  void saveDraft({
    required String title,
    required String content,
    List<String> claims = const [],
    String? channelId,
  }) {
    _draftTitle = title;
    _draftContent = content;
    _draftClaims = List.from(claims);
    _draftChannelId = channelId;
    notifyListeners();
  }

  void clearDraft() {
    _draftTitle = null;
    _draftContent = null;
    _draftClaims = [];
    _draftChannelId = null;
    notifyListeners();
  }

  /// Verifica e cacheia o status criptográfico de um objeto do Archive.
  Future<ArchiveCryptoStatus> verifyObject(String cidHash) async {
    if (_verificationCache.containsKey(cidHash)) {
      return _verificationCache[cidHash]!;
    }

    if (_archiveService == null) {
      _verificationCache[cidHash] = ArchiveCryptoStatus.notVerified;
      notifyListeners();
      return ArchiveCryptoStatus.notVerified;
    }

    try {
      final isValid = await _archiveService!.verifyStoredObject(cidHash);
      final status = isValid
          ? ArchiveCryptoStatus.verified
          : ArchiveCryptoStatus.invalidSignature;
      _verificationCache[cidHash] = status;
      notifyListeners();
      return status;
    } catch (_) {
      _verificationCache[cidHash] = ArchiveCryptoStatus.verificationError;
      notifyListeners();
      return ArchiveCryptoStatus.verificationError;
    }
  }

  Future<List<Map<String, dynamic>>> getThreadedComments(String articleCid) async {
    if (_commentsCache.containsKey(articleCid)) {
      return _commentsCache[articleCid]!;
    }
    if (_archiveService != null) {
      final comments = await _archiveService!.getThreadedComments(articleCid);
      _commentsCache[articleCid] = comments;
      return comments;
    }
    return const [];
  }

  void addCommentToCache(String articleCid, Map<String, dynamic> comment) {
    final list = List<Map<String, dynamic>>.from(_commentsCache[articleCid] ?? const []);
    list.add(comment);
    _commentsCache[articleCid] = list;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getRefutations(String articleCid) async {
    if (_refutationsCache.containsKey(articleCid)) {
      return _refutationsCache[articleCid]!;
    }
    if (_archiveService != null) {
      final refs = await _archiveService!.listRefutationsForTarget(articleCid);
      _refutationsCache[articleCid] = refs;
      return refs;
    }
    return const [];
  }

  void addRefutationToCache(String articleCid, Map<String, dynamic> refutation) {
    final list = List<Map<String, dynamic>>.from(_refutationsCache[articleCid] ?? const []);
    list.add(refutation);
    _refutationsCache[articleCid] = list;
    notifyListeners();
  }

  void clearCache() {
    _verificationCache.clear();
    _commentsCache.clear();
    _refutationsCache.clear();
    notifyListeners();
  }
}
