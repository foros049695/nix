import 'torrent_record.dart';

/// Tipos de protocolo/formato de integração dos indexadores.
enum IndexerSourceType {
  api('api', 'API REST / JSON'),
  rss('rss', 'Feed RSS / Atom XML'),
  torznab('torznab', 'Padrão Torznab / Newznab XML');

  final String slug;
  final String label;
  const IndexerSourceType(this.slug, this.label);

  static IndexerSourceType fromSlug(String? slug) {
    if (slug == 'torznab') return IndexerSourceType.torznab;
    if (slug == 'rss') return IndexerSourceType.rss;
    return IndexerSourceType.api;
  }
}

/// Configuração e estado operacional de uma fonte indexadora externa.
class TorrentIndexerSourceConfig {
  final String id;
  final String name;
  final String url;
  final IndexerSourceType type;
  final bool isEnabled;
  final bool isAvailable;
  final bool requiresAuth;
  final List<TorrentCategory> supportedCategories;
  final DateTime? lastCheckedAt;
  final int recordCount;
  final String? statusMessage;
  final int rateLimitPerMin;

  const TorrentIndexerSourceConfig({
    required this.id,
    required this.name,
    required this.url,
    required this.type,
    this.isEnabled = true,
    this.isAvailable = true,
    this.requiresAuth = false,
    this.supportedCategories = const [],
    this.lastCheckedAt,
    this.recordCount = 0,
    this.statusMessage,
    this.rateLimitPerMin = 30,
  });

  TorrentIndexerSourceConfig copyWith({
    String? id,
    String? name,
    String? url,
    IndexerSourceType? type,
    bool? isEnabled,
    bool? isAvailable,
    bool? requiresAuth,
    List<TorrentCategory>? supportedCategories,
    DateTime? lastCheckedAt,
    int? recordCount,
    String? statusMessage,
    int? rateLimitPerMin,
  }) {
    return TorrentIndexerSourceConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      type: type ?? this.type,
      isEnabled: isEnabled ?? this.isEnabled,
      isAvailable: isAvailable ?? this.isAvailable,
      requiresAuth: requiresAuth ?? this.requiresAuth,
      supportedCategories: supportedCategories ?? this.supportedCategories,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      recordCount: recordCount ?? this.recordCount,
      statusMessage: statusMessage ?? this.statusMessage,
      rateLimitPerMin: rateLimitPerMin ?? this.rateLimitPerMin,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'type': type.slug,
      'isEnabled': isEnabled ? 1 : 0,
      'isAvailable': isAvailable ? 1 : 0,
      'requiresAuth': requiresAuth ? 1 : 0,
      'categories': supportedCategories.map((c) => c.slug).toList(),
      if (lastCheckedAt != null) 'lastCheckedAt': lastCheckedAt!.toIso8601String(),
      'recordCount': recordCount,
      if (statusMessage != null) 'statusMessage': statusMessage,
      'rateLimitPerMin': rateLimitPerMin,
    };
  }

  factory TorrentIndexerSourceConfig.fromMap(Map<String, dynamic> map) {
    final rawCats = map['categories'] as List<dynamic>? ?? const [];
    final categories = rawCats
        .map((s) => TorrentCategory.fromSlug(s.toString()))
        .toList();

    return TorrentIndexerSourceConfig(
      id: map['id'] as String? ?? 'unknown',
      name: map['name'] as String? ?? 'Fonte',
      url: map['url'] as String? ?? '',
      type: IndexerSourceType.fromSlug(map['type'] as String?),
      isEnabled: (map['isEnabled'] as int? ?? 1) == 1,
      isAvailable: (map['isAvailable'] as int? ?? 1) == 1,
      requiresAuth: (map['requiresAuth'] as int? ?? 0) == 1,
      supportedCategories: categories,
      lastCheckedAt: map['lastCheckedAt'] != null
          ? DateTime.tryParse(map['lastCheckedAt'] as String)
          : null,
      recordCount: map['recordCount'] as int? ?? 0,
      statusMessage: map['statusMessage'] as String?,
      rateLimitPerMin: map['rateLimitPerMin'] as int? ?? 30,
    );
  }
}
