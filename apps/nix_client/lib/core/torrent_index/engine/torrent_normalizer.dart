/// Normalizador de metadados, títulos, hashes BitTorrent e magnets.
class TorrentNormalizer {
  static final RegExp _hex40Regex = RegExp(r'^[0-9a-fA-F]{40}$');
  static final RegExp _hex64Regex = RegExp(r'^[0-9a-fA-F]{64}$');
  static final RegExp _btihMagnetRegex = RegExp(r'xt=urn:btih:([0-9a-zA-Z]{32,40})', caseSensitive: false);
  static final RegExp _dnMagnetRegex = RegExp(r'dn=([^&]+)', caseSensitive: false);

  /// Valida e normaliza um InfoHash BitTorrent v1 (40 caracteres hexadecimais em minúsculas).
  /// Se fornecido em Base32 (32 caracteres), converte para Hex 40.
  static String? normalizeInfoHashV1(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (_hex40Regex.hasMatch(trimmed)) {
      return trimmed.toLowerCase();
    }
    // Caso seja base32 de 32 caracteres (RFC 4648 Base32)
    if (trimmed.length == 32 && RegExp(r'^[2-7a-zA-Z]{32}$').hasMatch(trimmed)) {
      return _base32ToHex(trimmed.toUpperCase());
    }
    return null;
  }

  /// Valida InfoHash BitTorrent v2 (64 caracteres hexadecimais SHA-256).
  static String? normalizeInfoHashV2(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (_hex64Regex.hasMatch(trimmed)) {
      return trimmed.toLowerCase();
    }
    return null;
  }

  /// Normaliza títulos de lançamentos removendo ruídos superficiais mantendo nome, ano e qualidade.
  static String normalizeTitle(String rawTitle) {
    var title = rawTitle.trim();
    if (title.isEmpty) return 'Sem título';

    // Substitui múltiplos pontos ou underlines por espaços se parecer um nome de release estilo cena
    if (title.contains('.') && !title.contains(' ')) {
      title = title.replaceAll('.', ' ');
    }
    if (title.contains('_') && !title.contains(' ')) {
      title = title.replaceAll('_', ' ');
    }

    // Remove espaços repetidos
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title;
  }

  /// Extrai o InfoHash v1 a partir de uma URI magnet.
  static String? extractInfoHashFromMagnet(String? magnetUri) {
    if (magnetUri == null || !magnetUri.startsWith('magnet:?')) return null;
    final match = _btihMagnetRegex.firstMatch(magnetUri);
    if (match != null && match.groupCount >= 1) {
      return normalizeInfoHashV1(match.group(1));
    }
    return null;
  }

  /// Extrai o nome de exibição (`dn`) a partir de uma URI magnet.
  static String? extractDisplayNameFromMagnet(String? magnetUri) {
    if (magnetUri == null || !magnetUri.startsWith('magnet:?')) return null;
    final match = _dnMagnetRegex.firstMatch(magnetUri);
    if (match != null && match.groupCount >= 1) {
      try {
        return Uri.decodeComponent(match.group(1)!.replaceAll('+', ' '));
      } catch (_) {
        return match.group(1);
      }
    }
    return null;
  }

  /// Constrói uma URI magnet canônica a partir do hash e do título.
  static String buildCanonicalMagnet({
    required String infoHashV1,
    String? title,
    List<String> trackers = const [],
  }) {
    final cleanHash = normalizeInfoHashV1(infoHashV1) ?? infoHashV1.toLowerCase();
    final buffer = StringBuffer('magnet:?xt=urn:btih:$cleanHash');
    if (title != null && title.trim().isNotEmpty) {
      buffer.write('&dn=${Uri.encodeComponent(title.trim())}');
    }
    for (final tr in trackers) {
      if (tr.trim().isNotEmpty) {
        buffer.write('&tr=${Uri.encodeComponent(tr.trim())}');
      }
    }
    return buffer.toString();
  }

  /// Conversão segura de Base32 para Hexadecimal de 40 dígitos.
  static String? _base32ToHex(String b32) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final bits = StringBuffer();
    for (var i = 0; i < b32.length; i++) {
      final val = alphabet.indexOf(b32[i]);
      if (val == -1) return null;
      bits.write(val.toRadixString(2).padLeft(5, '0'));
    }
    final bitStr = bits.toString();
    final hex = StringBuffer();
    for (var i = 0; i + 4 <= bitStr.length && hex.length < 40; i += 4) {
      final nibble = int.parse(bitStr.substring(i, i + 4), radix: 2);
      hex.write(nibble.toRadixString(16));
    }
    final result = hex.toString();
    return result.length == 40 ? result.toLowerCase() : null;
  }
}
