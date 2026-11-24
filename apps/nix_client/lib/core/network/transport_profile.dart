import 'package:flutter/foundation.dart';

/// Tipos de perfil de transporte e privacidade suportados pelo Projeto Nix.
enum TransportProfileType {
  /// Perfil A: Tráfego restrito estritamente a serviços Onion v3 via Tor.
  /// Qualquer destino clearnet (.com, .org, IP) é terminantemente bloqueado no firewall local.
  onionV3Strict(
    id: 'onion_v3_strict',
    label: 'Perfil A: Onion v3 Estrito',
    shortLabel: 'Onion v3 Estrito',
    description: 'Opera exclusivamente em serviços ocultos .onion via Tor. Tráfego clearnet bloqueado no firewall.',
    isTorBased: true,
    requiresOnion: true,
  ),

  /// Perfil B: Roteamento de privacidade via túnel SOCKS5 do Tor embutido (127.0.0.1:9050).
  /// Suporta domínios .onion e hosts clearnet sob isolamento e fail-closed (sem vazamento DNS).
  torSocks5(
    id: 'tor_socks5',
    label: 'Perfil B: Tor SOCKS5 Isolado',
    shortLabel: 'Tor SOCKS5',
    description: 'Túnel anônimo de 3 saltos via daemon Tor embutido. Fail-closed ativo: zero vazamento de IP doméstico.',
    isTorBased: true,
    requiresOnion: false,
  ),

  /// Perfil C: Proxy SOCKS5 personalizado configurado pelo usuário (SSH dinâmico, proxy corporativo ou rede mesh).
  customSocks5(
    id: 'custom_socks5',
    label: 'Perfil C: SOCKS5 Personalizado',
    shortLabel: 'SOCKS5 Custom',
    description: 'Encaminha as requisições por um proxy SOCKS5 customizado definido pelo operador.',
    isTorBased: false,
    requiresOnion: false,
  ),

  /// Perfil D: Conexão direta HTTPS (Clearnet) sem túnel de anonimato.
  /// Exige consentimento explícito do usuário, desativando o isolamento do módulo selecionado.
  directHttps(
    id: 'direct_https',
    label: 'Perfil D: Conexão Direta HTTPS',
    shortLabel: 'HTTPS Direto',
    description: 'Conexão direta pelo provedor de internet (Clearnet). Requer autorização explícita do usuário.',
    isTorBased: false,
    requiresOnion: false,
  );

  final String id;
  final String label;
  final String shortLabel;
  final String description;
  final bool isTorBased;
  final bool requiresOnion;

  const TransportProfileType({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.description,
    required this.isTorBased,
    required this.requiresOnion,
  });

  static TransportProfileType fromId(String? id) {
    return TransportProfileType.values.firstWhere(
      (p) => p.id == id,
      orElse: () => TransportProfileType.torSocks5,
    );
  }
}

/// Módulos com configuração independente de perfil de transporte e privacidade.
enum TransportModule {
  downloads('downloads', 'Nix Downloads (aria2 / Dart Range)'),
  torrents('torrents', 'Buscador de Torrents (Indexadores)'),
  catalog('catalog', 'Catálogo Cultural Offline (Manifesto)'),
  music('music', 'Música e Metadados (Streams e Artistas)');

  final String id;
  final String label;

  const TransportModule(this.id, this.label);
}

/// Configuração unificada e independente dos perfis de transporte por módulo.
@immutable
class ModuleTransportPreferences {
  final Map<TransportModule, TransportProfileType> profiles;
  final String customSocksHost;
  final int customSocksPort;
  final String? customSocksUsername;
  final String? customSocksPassword;

  const ModuleTransportPreferences({
    this.profiles = const {
      TransportModule.downloads: TransportProfileType.torSocks5,
      TransportModule.torrents: TransportProfileType.torSocks5,
      TransportModule.catalog: TransportProfileType.torSocks5,
      TransportModule.music: TransportProfileType.torSocks5,
    },
    this.customSocksHost = '127.0.0.1',
    this.customSocksPort = 1080,
    this.customSocksUsername,
    this.customSocksPassword,
  });

  /// Perfil ativo para o módulo solicitado.
  TransportProfileType getProfile(TransportModule module) {
    return profiles[module] ?? TransportProfileType.torSocks5;
  }

  /// Retorna verdadeiro se a clearnet estiver expressamente autorizada para este módulo.
  bool isClearnetAuthorized(TransportModule module) {
    return getProfile(module) == TransportProfileType.directHttps;
  }

  /// Constrói cópia com valores atualizados.
  ModuleTransportPreferences copyWith({
    Map<TransportModule, TransportProfileType>? profiles,
    String? customSocksHost,
    int? customSocksPort,
    String? customSocksUsername,
    String? customSocksPassword,
  }) {
    return ModuleTransportPreferences(
      profiles: profiles ?? this.profiles,
      customSocksHost: customSocksHost ?? this.customSocksHost,
      customSocksPort: customSocksPort ?? this.customSocksPort,
      customSocksUsername: customSocksUsername ?? this.customSocksUsername,
      customSocksPassword: customSocksPassword ?? this.customSocksPassword,
    );
  }

  /// Cria cópia alterando o perfil de um único módulo.
  ModuleTransportPreferences setModuleProfile(TransportModule module, TransportProfileType profile) {
    final updated = Map<TransportModule, TransportProfileType>.from(profiles);
    updated[module] = profile;
    return copyWith(profiles: updated);
  }

  Map<String, dynamic> toJson() {
    return {
      'profiles': profiles.map((k, v) => MapEntry(k.id, v.id)),
      'customSocksHost': customSocksHost,
      'customSocksPort': customSocksPort,
      'customSocksUsername': customSocksUsername,
      'customSocksPassword': customSocksPassword,
    };
  }

  factory ModuleTransportPreferences.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ModuleTransportPreferences();

    final rawProfiles = json['profiles'] as Map<String, dynamic>?;
    final map = <TransportModule, TransportProfileType>{};
    if (rawProfiles != null) {
      for (final mod in TransportModule.values) {
        if (rawProfiles.containsKey(mod.id)) {
          map[mod] = TransportProfileType.fromId(rawProfiles[mod.id]?.toString());
        }
      }
    }

    return ModuleTransportPreferences(
      profiles: map.isNotEmpty
          ? map
          : const {
              TransportModule.downloads: TransportProfileType.torSocks5,
              TransportModule.torrents: TransportProfileType.torSocks5,
              TransportModule.catalog: TransportProfileType.torSocks5,
              TransportModule.music: TransportProfileType.torSocks5,
            },
      customSocksHost: json['customSocksHost']?.toString() ?? '127.0.0.1',
      customSocksPort: int.tryParse(json['customSocksPort']?.toString() ?? '1080') ?? 1080,
      customSocksUsername: json['customSocksUsername']?.toString(),
      customSocksPassword: json['customSocksPassword']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ModuleTransportPreferences &&
        mapEquals(other.profiles, profiles) &&
        other.customSocksHost == customSocksHost &&
        other.customSocksPort == customSocksPort &&
        other.customSocksUsername == customSocksUsername &&
        other.customSocksPassword == customSocksPassword;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(profiles.entries.map((e) => Object.hash(e.key, e.value))),
        customSocksHost,
        customSocksPort,
        customSocksUsername,
        customSocksPassword,
      );
}

/// Registro global estático das preferências de transporte para uso direto em adaptadores de rede.
class GlobalTransportRegistry {
  static ModuleTransportPreferences _current = const ModuleTransportPreferences();

  static ModuleTransportPreferences get current => _current;

  static void update(ModuleTransportPreferences preferences) {
    _current = preferences;
  }
}
