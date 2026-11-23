import '../models/indexer_source_config.dart';
import '../models/torrent_record.dart';

/// Interface abstrata para conectores de indexadores externos no Nix.
/// Permite acrescentar novas fontes sem modificar o núcleo do indexador.
abstract class NixIndexerAdapter {
  String get sourceId;
  String get sourceName;
  String get baseUrl;
  IndexerSourceType get type;

  /// Pesquisa registros na fonte externa.
  /// Retorna lista de registros com metadados estritamente reais fornecidos pela fonte.
  Future<List<TorrentIndexRecord>> search(
    String query, {
    TorrentCategory? category,
    int limit = 25,
  });

  /// Busca registros recentes ou populares da fonte.
  Future<List<TorrentIndexRecord>> fetchRecent({int limit = 25});

  /// Testa a conectividade com a fonte sem realizar buscas invasivas.
  Future<bool> testConnection();
}
