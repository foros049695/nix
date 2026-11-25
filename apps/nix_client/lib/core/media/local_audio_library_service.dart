import 'dart:convert';
import 'dart:io';

import '../security/platform_runtime.dart';
import 'pager_playlist.dart';

/// Serviço de indexação, extração real de metadados e persistência da biblioteca musical local (Seções 1, 2, 3 e 6).
class LocalAudioLibraryService {
  static const List<String> supportedExtensions = [
    'mp3',
    'flac',
    'wav',
    'ogg',
    'opus',
    'm4a',
    'aac',
  ];

  static const String _libraryFileName = 'nix_local_music_library.json';

  /// Extrai metadados reais de um arquivo de áudio local sem estimativas artificiais.
  Future<PagerTrack?> extractMetadata(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final stat = await file.stat();
    if (stat.size <= 0) return null;

    final pathLower = file.path.toLowerCase();
    final ext = pathLower.contains('.') ? pathLower.split('.').last : '';
    if (!supportedExtensions.contains(ext)) return null;

    // Tenta primeiro via ffprobe real instalado no sistema operacional
    try {
      final probeResult = await _extractViaFfprobe(file.path);
      if (probeResult != null) return probeResult;
    } catch (_) {}

    // Fallback puro Dart para leitura de cabeçalhos e tags básicas
    return await _extractPureDart(file, ext);
  }

  /// Extração através de ffprobe (precisão técnica e integridade garantida).
  Future<PagerTrack?> _extractViaFfprobe(String filePath) async {
    final res = await Process.run('ffprobe', [
      '-v',
      'quiet',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      filePath,
    ]);

    if (res.exitCode != 0 || (res.stdout as String).trim().isEmpty) return null;

    final map = jsonDecode(res.stdout as String) as Map<String, dynamic>;
    final format = map['format'] as Map<String, dynamic>? ?? {};
    final streams = (map['streams'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    final audioStream = streams.firstWhere(
      (s) => s['codec_type'] == 'audio',
      orElse: () => {},
    );

    final tags = (format['tags'] as Map<String, dynamic>?) ??
        (audioStream['tags'] as Map<String, dynamic>?) ??
        {};

    final file = File(filePath);
    final fallbackTitle = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '')
        : 'Faixa Desconhecida';

    final title = _findTag(tags, ['title', 'TITLE', 'Title']) ?? fallbackTitle;
    final artist = _findTag(tags, ['artist', 'ARTIST', 'Artist', 'album_artist', 'ALBUM_ARTIST']) ??
        'Artista desconhecido';
    final album = _findTag(tags, ['album', 'ALBUM', 'Album']) ?? 'Álbum local';
    final trackNumStr = _findTag(tags, ['track', 'TRACK', 'tracknumber', 'TRACKNUMBER']);
    final trackNum = trackNumStr != null ? int.tryParse(trackNumStr.split('/').first) : null;

    final durSec = (double.tryParse(format['duration']?.toString() ?? '') ??
            double.tryParse(audioStream['duration']?.toString() ?? '') ??
            0)
        .round();

    final codecName = (audioStream['codec_name']?.toString() ??
            format['format_name']?.toString() ??
            'AUDIO')
        .toUpperCase();

    // Frequência de amostragem
    final rawSampleRate = int.tryParse(audioStream['sample_rate']?.toString() ?? '');
    final sampleRateStr = rawSampleRate != null
        ? '${(rawSampleRate / 1000).toStringAsFixed(1).replaceAll('.0', '')} kHz'
        : '';

    // Profundidade de bits
    final rawBits = int.tryParse(audioStream['bits_per_raw_sample']?.toString() ?? '') ??
        int.tryParse(audioStream['bits_per_sample']?.toString() ?? '');
    final bitDepthStr = rawBits != null && rawBits > 0 ? '$rawBits-bit' : '';

    // Bitrate
    final rawBitrate = int.tryParse(format['bit_rate']?.toString() ?? '') ??
        int.tryParse(audioStream['bit_rate']?.toString() ?? '');
    final bitRateKbps = rawBitrate != null && rawBitrate > 0 ? (rawBitrate / 1000).round() : 0;

    // Extrai capa embutida do arquivo se existir
    String? coverPath;
    final hasCover = streams.any((s) =>
        s['codec_type'] == 'video' ||
        s['disposition']?['attached_pic'] == 1 ||
        s['disposition']?['attached_pic'] == '1');

    if (hasCover) {
      coverPath = await _extractCoverViaFfmpeg(filePath);
    }

    return PagerTrack(
      uri: file.uri.toString(),
      name: title,
      artist: artist,
      album: album,
      durationSeconds: durSec,
      coverPath: coverPath,
      trackNumber: trackNum,
      audioFormat: codecName,
      sampleRate: sampleRateStr,
      bitDepth: bitDepthStr,
      bitRateKbps: bitRateKbps,
    );
  }

  String? _findTag(Map<String, dynamic> tags, List<String> candidates) {
    for (final c in candidates) {
      if (tags.containsKey(c) && tags[c] != null && tags[c].toString().trim().isNotEmpty) {
        return tags[c].toString().trim();
      }
    }
    return null;
  }

  /// Extrai capa embutida em disco usando ffmpeg de forma atômica e estável.
  Future<String?> _extractCoverViaFfmpeg(String audioFilePath) async {
    try {
      final coversDir = Directory(NixPlatformPaths.coversDirectory);
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }
      final safeHash = audioFilePath.hashCode.abs().toRadixString(16);
      final outPath = '${coversDir.path}/music_embedded_$safeHash.jpg';
      final outFile = File(outPath);
      if (await outFile.exists() && await outFile.length() > 0) {
        return outPath;
      }

      final proc = await Process.run('ffmpeg', [
        '-y',
        '-i',
        audioFilePath,
        '-an',
        '-vcodec',
        'mjpeg',
        '-frames:v',
        '1',
        outPath,
      ]);

      if (proc.exitCode == 0 && await outFile.exists() && await outFile.length() > 0) {
        return outPath;
      }
    } catch (_) {}
    return null;
  }

  /// Leitura segura de fallback via Dart puro para sistemas sem ffprobe.
  Future<PagerTrack?> _extractPureDart(File file, String ext) async {
    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '')
        : 'Faixa';

    // Para WAV, lê cabeçalho RIFF simples
    if (ext == 'wav') {
      try {
        final bytes = await file.openRead(0, 44).expand((b) => b).toList();
        if (bytes.length >= 44 &&
            String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
            String.fromCharCodes(bytes.skip(8).take(4)) == 'WAVE') {
          final _ = bytes[22] | (bytes[23] << 8);
          final sampleRate = bytes[24] | (bytes[25] << 8) | (bytes[26] << 16) | (bytes[27] << 24);
          final byteRate = bytes[28] | (bytes[29] << 8) | (bytes[30] << 16) | (bytes[31] << 24);
          final bitsPerSample = bytes[34] | (bytes[35] << 8);
          final fileLength = await file.length();
          final durationSec = byteRate > 0 ? ((fileLength - 44) / byteRate).round() : 0;

          return PagerTrack(
            uri: file.uri.toString(),
            name: fileName,
            artist: 'Artista desconhecido',
            album: 'Álbum local',
            durationSeconds: durationSec,
            audioFormat: 'WAV',
            sampleRate: '${(sampleRate / 1000).toStringAsFixed(1)} kHz',
            bitDepth: '$bitsPerSample-bit',
            bitRateKbps: ((byteRate * 8) / 1000).round(),
          );
        }
      } catch (_) {}
    }

    return PagerTrack(
      uri: file.uri.toString(),
      name: fileName,
      artist: 'Artista desconhecido',
      album: 'Álbum local',
      durationSeconds: 0,
      audioFormat: ext.toUpperCase(),
      sampleRate: '',
      bitDepth: '',
      bitRateKbps: 0,
    );
  }

  /// Varre um diretório autorizado em busca de arquivos de áudio válidos.
  Future<List<PagerTrack>> scanDirectory(Directory dir, {void Function(int count, String file)? onProgress}) async {
    if (!await dir.exists()) return [];
    final tracks = <PagerTrack>[];

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final pathLower = entity.path.toLowerCase();
      final hasExt = supportedExtensions.any((e) => pathLower.endsWith('.$e'));
      if (!hasExt) continue;

      final track = await extractMetadata(entity.path);
      if (track != null) {
        tracks.add(track);
        onProgress?.call(tracks.length, entity.path);
      }
    }

    return tracks;
  }

  /// Salva biblioteca musical de forma persistente.
  Future<void> saveLibrary(List<PagerTrack> tracks) async {
    final file = File(NixPlatformPaths.resolveDataFile(_libraryFileName));
    await file.parent.create(recursive: true);
    final jsonList = tracks.map((t) => t.toMap()).toList();
    final jsonStr = jsonEncode(jsonList);
    final tmpFile = File('${file.path}.tmp');
    await tmpFile.writeAsString(jsonStr, flush: true);
    await tmpFile.rename(file.path);
  }

  /// Carrega a biblioteca musical salva pelo usuário.
  Future<List<PagerTrack>> loadLibrary() async {
    final file = File(NixPlatformPaths.resolveDataFile(_libraryFileName));
    if (!await file.exists()) return [];
    try {
      final jsonStr = await file.readAsString();
      final decoded = jsonDecode(jsonStr);
      if (decoded is! List) return [];
      final list = <PagerTrack>[];
      for (final item in decoded) {
        if (item is Map) {
          try {
            list.add(PagerTrack.fromMap(Map<Object?, Object?>.from(item)));
          } catch (_) {}
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }
}
