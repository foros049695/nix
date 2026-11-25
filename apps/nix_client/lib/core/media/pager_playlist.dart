import '../database/repositories.dart';

class PagerTrack {
  final String uri;
  final String name;
  final String artist;
  final String album;
  final int durationSeconds;
  final String? coverPath;
  final int? trackNumber;
  final String? musicBrainzId;
  final String audioFormat;
  final String sampleRate;
  final String bitDepth;
  final int bitRateKbps;

  const PagerTrack({
    required this.uri,
    required this.name,
    this.artist = 'Artista desconhecido',
    this.album = 'Álbum desconhecido',
    this.durationSeconds = 0,
    this.coverPath,
    this.trackNumber,
    this.musicBrainzId,
    this.audioFormat = 'Áudio',
    this.sampleRate = '',
    this.bitDepth = '',
    this.bitRateKbps = 0,
  });

  String get formattedDuration {
    if (durationSeconds <= 0) return '--:--';
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get audioQualityBadge {
    final parts = <String>[];
    if (audioFormat.isNotEmpty && audioFormat != 'Áudio') {
      parts.add(audioFormat);
    }
    if (bitDepth.isNotEmpty && bitDepth != 'Não identificada') {
      parts.add(bitDepth);
    }
    if (sampleRate.isNotEmpty && sampleRate != 'Não identificada') {
      parts.add(sampleRate);
    }
    if (bitRateKbps > 0) {
      parts.add('$bitRateKbps kbps');
    }
    if (parts.isEmpty) return 'Áudio local';
    if ((bitDepth == '24-bit' || bitDepth == '32-bit') &&
        (sampleRate.contains('96') || sampleRate.contains('192') || sampleRate.contains('88.2'))) {
      return 'Hi-Res · ${parts.join(' · ')}';
    }
    return parts.join(' · ');
  }

  static PagerTrack fromMap(Map<Object?, Object?> data) {
    final rawUri = data['uri'];
    final rawName = data['name'];
    if (rawUri is! String ||
        rawUri.length > 2048 ||
        rawName is! String ||
        rawName.length > 160) {
      throw const FormatException('Faixa local inválida.');
    }
    final uri = Uri.tryParse(rawUri);
    final localAndroid = uri?.scheme == 'content' &&
        const {
          'com.android.externalstorage.documents',
          'com.android.providers.media.documents',
        }.contains(uri?.authority);

    final pathLower = uri?.path.toLowerCase() ?? '';
    final localDesktop = uri?.scheme == 'file' &&
        uri!.authority.isEmpty &&
        uri.path.startsWith('/') &&
        !uri.path.startsWith('//') &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        pathLower.endsWith('.wav');

    if (uri == null || (!localAndroid && !localDesktop)) {
      throw const FormatException('O seletor de áudio do Pager aceita apenas arquivos WAV locais.');
    }

    final ext = pathLower.contains('.') ? pathLower.split('.').last.toUpperCase() : 'ÁUDIO';

    return PagerTrack(
      uri: uri.toString(),
      name: rawName.trim().isEmpty ? 'Faixa' : rawName.trim(),
      artist: (data['artist'] as String?)?.trim().isNotEmpty == true
          ? (data['artist'] as String).trim()
          : 'Artista desconhecido',
      album: (data['album'] as String?)?.trim().isNotEmpty == true
          ? (data['album'] as String).trim()
          : 'Álbum desconhecido',
      durationSeconds: (data['durationSeconds'] as num?)?.toInt() ?? 0,
      coverPath: data['coverPath'] as String?,
      trackNumber: (data['trackNumber'] as num?)?.toInt(),
      musicBrainzId: data['musicBrainzId'] as String?,
      audioFormat: (data['audioFormat'] as String?)?.isNotEmpty == true
          ? data['audioFormat'] as String
          : ext,
      sampleRate: (data['sampleRate'] as String?)?.isNotEmpty == true
          ? data['sampleRate'] as String
          : '',
      bitDepth: (data['bitDepth'] as String?)?.isNotEmpty == true
          ? data['bitDepth'] as String
          : '',
      bitRateKbps: (data['bitRateKbps'] as num?)?.toInt() ?? 0,
    );
  }

  PagerTrack copyWith({
    String? uri,
    String? name,
    String? artist,
    String? album,
    int? durationSeconds,
    String? coverPath,
    int? trackNumber,
    String? musicBrainzId,
    String? audioFormat,
    String? sampleRate,
    String? bitDepth,
    int? bitRateKbps,
  }) {
    return PagerTrack(
      uri: uri ?? this.uri,
      name: name ?? this.name,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      coverPath: coverPath ?? this.coverPath,
      trackNumber: trackNumber ?? this.trackNumber,
      musicBrainzId: musicBrainzId ?? this.musicBrainzId,
      audioFormat: audioFormat ?? this.audioFormat,
      sampleRate: sampleRate ?? this.sampleRate,
      bitDepth: bitDepth ?? this.bitDepth,
      bitRateKbps: bitRateKbps ?? this.bitRateKbps,
    );
  }

  Map<String, dynamic> toMap() => {
        'uri': uri,
        'name': name,
        'artist': artist,
        'album': album,
        'durationSeconds': durationSeconds,
        if (coverPath != null) 'coverPath': coverPath,
        if (trackNumber != null) 'trackNumber': trackNumber,
        if (musicBrainzId != null) 'musicBrainzId': musicBrainzId,
        'audioFormat': audioFormat,
        'sampleRate': sampleRate,
        'bitDepth': bitDepth,
        'bitRateKbps': bitRateKbps,
      };
}

class PagerPlaylist {
  const PagerPlaylist(this.preferences);

  static const maxTracks = 16;
  static const _key = 'profile.pager_playlist.v1';
  final PreferencesRepository preferences;

  Future<List<PagerTrack>> load() async {
    final saved = await preferences.getOption(_key);
    if (saved == null) return [];
    return (saved as List)
        .map((row) => PagerTrack.fromMap(row as Map))
        .toList();
  }

  Future<void> save(List<PagerTrack> tracks) async {
    if (tracks.length > maxTracks ||
        tracks.map((track) => track.uri).toSet().length != tracks.length) {
      throw const FormatException('A lista admite até 16 faixas distintas.');
    }
    final normalized = tracks.map((track) => PagerTrack.fromMap(track.toMap()));
    await preferences.setOption(
        _key, normalized.map((track) => track.toMap()).toList());
  }
}
