enum CulturalStage {
  planned('Pretendo'),
  active('Em andamento'),
  paused('Em pausa'),
  finished('Concluído'),
  dropped('Abandonado'),
  revisiting('Revisitando');

  const CulturalStage(this.label);
  final String label;
}

/// Dados particulares de acompanhamento. O perfil público pode revelar a capa
/// se autorizado, mas deve omitir estas informações.
class CulturalTracking {
  final CulturalStage? stage;
  final int? current;
  final int? total;
  final int? seasonOrVolume;
  final bool favorite;
  final List<String> tags;
  final String collection;
  final String review;
  final String privateNotes;

  const CulturalTracking({
    this.stage,
    this.current,
    this.total,
    this.seasonOrVolume,
    this.favorite = false,
    this.tags = const [],
    this.collection = '',
    this.review = '',
    this.privateNotes = '',
  });

  double? get fraction {
    final value = current;
    final limit = total;
    return value == null || limit == null || limit <= 0
        ? null
        : (value / limit).clamp(0.0, 1.0);
  }

  Map<String, Object?> toJson() => {
        'stage': stage?.name,
        'current': current,
        'total': total,
        'seasonOrVolume': seasonOrVolume,
        'favorite': favorite,
        'tags': tags,
        'collection': collection,
        'review': review,
        'privateNotes': privateNotes,
      };

  factory CulturalTracking.fromJson(Map<String, dynamic> json) {
    final tags = json['tags'];
    return CulturalTracking(
      stage: CulturalStage.values
          .where((v) => v.name == json['stage'])
          .firstOrNull,
      current: json['current'] as int?,
      total: json['total'] as int?,
      seasonOrVolume: json['seasonOrVolume'] as int?,
      favorite: json['favorite'] == true,
      tags:
          tags is List ? List.unmodifiable(tags.whereType<String>()) : const [],
      collection: json['collection'] as String? ?? '',
      review: json['review'] as String? ?? '',
      privateNotes: json['privateNotes'] as String? ?? '',
    );
  }

  CulturalTracking copyWith({
    CulturalStage? stage,
    int? current,
    int? total,
    int? seasonOrVolume,
    bool? favorite,
    List<String>? tags,
    String? collection,
    String? review,
    String? privateNotes,
  }) {
    return CulturalTracking(
      stage: stage ?? this.stage,
      current: current ?? this.current,
      total: total ?? this.total,
      seasonOrVolume: seasonOrVolume ?? this.seasonOrVolume,
      favorite: favorite ?? this.favorite,
      tags: tags ?? this.tags,
      collection: collection ?? this.collection,
      review: review ?? this.review,
      privateNotes: privateNotes ?? this.privateNotes,
    );
  }
}
