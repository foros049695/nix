import '../models/indexer_source_config.dart';
import '../models/torrent_record.dart';
import 'nix_indexer_adapter.dart';
import 'nyaa_rss_adapter.dart';
import 'rss_index_adapter.dart';
import 'torznab_adapter.dart';
import 'tracker_1337x_adapter.dart';
import 'yts_api_adapter.dart';

/// Gerenciador de fontes e adaptadores do Nix Torrent Index.
/// Controla quais conectores estão ativos, testa conexões reais e mantém contadores.
class IndexerSourcesManager {
  final Map<String, TorrentIndexerSourceConfig> _configs = {};
  final Map<String, NixIndexerAdapter> _adapters = {};
  final TorrentHttpRequester? _requester;

  IndexerSourcesManager({TorrentHttpRequester? requester}) : _requester = requester {
    _registerDefaultSources();
  }

  void _registerDefaultSources() {
    // 1. Nyaa.si (RSS oficial, anime e literatura aberta)
    final nyaa = NyaaRssAdapter(requester: _requester);
    _adapters[nyaa.sourceId] = nyaa;
    _configs[nyaa.sourceId] = const TorrentIndexerSourceConfig(
      id: 'nyaa',
      name: 'Nyaa.si (Anime / Mangás / Mídia)',
      url: 'https://nyaa.si',
      type: IndexerSourceType.rss,
      isEnabled: true,
      isAvailable: true,
      supportedCategories: [TorrentCategory.anime, TorrentCategory.manga, TorrentCategory.music],
    );

    // 2. YTS.mx (API REST oficial, filmes)
    final yts = YtsApiAdapter(requester: _requester);
    _adapters[yts.sourceId] = yts;
    _configs[yts.sourceId] = const TorrentIndexerSourceConfig(
      id: 'yts',
      name: 'YTS.mx (Filmes)',
      url: 'https://yts.mx/api/v2',
      type: IndexerSourceType.api,
      isEnabled: true,
      isAvailable: true,
      supportedCategories: [TorrentCategory.movies],
    );

    // 3. 1337x (Catálogo geral / espelho)
    final tracker1337x = Tracker1337xAdapter(requester: _requester);
    _adapters[tracker1337x.sourceId] = tracker1337x;
    _configs[tracker1337x.sourceId] = const TorrentIndexerSourceConfig(
      id: '1337x',
      name: '1337x (Geral / Espelho)',
      url: 'https://1337x.to',
      type: IndexerSourceType.api,
      isEnabled: true,
      isAvailable: true,
      supportedCategories: [
        TorrentCategory.movies,
        TorrentCategory.tv,
        TorrentCategory.games,
        TorrentCategory.software,
        TorrentCategory.music,
      ],
    );

    // 4. Torznab (Opcional - integração personalizada do usuário)
    final torznab = TorznabAdapter(url: 'http://127.0.0.1:9696/1/api', requester: _requester);
    _adapters['torznab_custom'] = torznab;
    _configs['torznab_custom'] = const TorrentIndexerSourceConfig(
      id: 'torznab_custom',
      name: 'Torznab / Prowlarr Local (Opcional)',
      url: 'http://127.0.0.1:9696',
      type: IndexerSourceType.torznab,
      isEnabled: false, // Desabilitado por padrão (Jackett/Prowlarr não são obrigatórios)
      isAvailable: false,
      requiresAuth: true,
      statusMessage: 'Conector opcional para servidores locais do usuário.',
    );
  }

  List<TorrentIndexerSourceConfig> listSources() => _configs.values.toList();

  TorrentIndexerSourceConfig? getSourceConfig(String id) => _configs[id];

  NixIndexerAdapter? getAdapter(String id) => _adapters[id];

  List<NixIndexerAdapter> get activeAdapters {
    return _adapters.entries
        .where((e) => _configs[e.key]?.isEnabled ?? false)
        .map((e) => e.value)
        .toList();
  }

  void setSourceEnabled(String id, bool enabled) {
    if (_configs.containsKey(id)) {
      _configs[id] = _configs[id]!.copyWith(isEnabled: enabled);
    }
  }

  void updateSourceRecordCount(String id, int count) {
    if (_configs.containsKey(id)) {
      _configs[id] = _configs[id]!.copyWith(recordCount: count);
    }
  }

  Future<bool> testSource(String id) async {
    final adapter = _adapters[id];
    if (adapter == null) return false;

    final success = await adapter.testConnection();
    if (_configs.containsKey(id)) {
      _configs[id] = _configs[id]!.copyWith(
        isAvailable: success,
        lastCheckedAt: DateTime.now(),
        statusMessage: success ? 'Conexão testada com sucesso.' : 'Falha na resposta do indexador.',
      );
    }
    return success;
  }

  void addCustomRssSource({
    required String id,
    required String name,
    required String feedUrl,
    TorrentCategory defaultCategory = TorrentCategory.other,
  }) {
    final adapter = RssIndexAdapter(
      id: id,
      name: name,
      feedUrl: feedUrl,
      defaultCategory: defaultCategory,
      requester: _requester,
    );
    _adapters[id] = adapter;
    _configs[id] = TorrentIndexerSourceConfig(
      id: id,
      name: name,
      url: feedUrl,
      type: IndexerSourceType.rss,
      isEnabled: true,
      isAvailable: true,
      supportedCategories: [defaultCategory],
    );
  }

  void removeCustomSource(String id) {
    if (id != 'nyaa' && id != 'yts' && id != '1337x' && id != 'torznab_custom') {
      _adapters.remove(id);
      _configs.remove(id);
    }
  }
}
