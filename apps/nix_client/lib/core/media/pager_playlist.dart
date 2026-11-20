import '../database/repositories.dart';

class PagerTrack {
  final String uri;
  final String name;

  const PagerTrack({required this.uri, required this.name});

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
    if (uri == null ||
        uri.scheme != 'content' ||
        !const {
          'com.android.externalstorage.documents',
          'com.android.providers.media.documents',
        }.contains(uri.authority)) {
      throw const FormatException('Escolha uma faixa no armazenamento local.');
    }
    return PagerTrack(
      uri: uri.toString(),
      name: rawName.trim().isEmpty ? 'Faixa' : rawName.trim(),
    );
  }

  Map<String, String> toMap() => {'uri': uri, 'name': name};
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
