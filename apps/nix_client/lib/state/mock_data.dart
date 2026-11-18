import '../core/models/space.dart';
import '../core/models/channel.dart';
import '../core/models/message.dart';
import '../core/models/member.dart';
import '../core/models/publication.dart';
import '../core/models/forum_post.dart';
import '../core/models/cultural_item.dart';
import '../core/models/user_profile.dart';
import '../core/models/direct_message.dart';

class MockData {
  static UserProfile getInitialUserProfile() {
    return const UserProfile(
      publicId: 'NIX-7E3A-9F01-C45B-289D',
      displayName: 'GUS',
      bio: 'Arquitetura descentralizada, criptografia aplicada, cinema clássico e acervo cultural privado.',
      currentActivity: 'Assistindo: Mobile Suit Gundam Hathaway',
      memberSinceYear: '26',
      avatarStyle: 'nyx_emblem',
      culturalItems: [
        // Filmes
        CulturalItem(
          id: 'cult_1',
          title: 'Mobile Suit Gundam Hathaway',
          creatorOrYear: '2021 · Murase',
          category: CulturalCategory.movies,
          rating: '9.6',
          monogram: 'MH',
          toneShade: 52,
          isFeatured: true,
        ),
        CulturalItem(
          id: 'cult_2',
          title: 'Ghost Dog: The Way of the Samurai',
          creatorOrYear: '1999 · Jarmusch',
          category: CulturalCategory.movies,
          rating: '9.4',
          monogram: 'GD',
          toneShade: 36,
        ),
        CulturalItem(
          id: 'cult_3',
          title: '12 Angry Men',
          creatorOrYear: '1957 · Lumet',
          category: CulturalCategory.movies,
          rating: '9.8',
          monogram: '12',
          toneShade: 48,
        ),
        CulturalItem(
          id: 'cult_4',
          title: 'Black Lizard',
          creatorOrYear: '1968 · Fukasaku',
          category: CulturalCategory.movies,
          rating: '9.1',
          monogram: 'BL',
          toneShade: 30,
        ),
        // Álbuns Musicais (Discos de Vinil)
        CulturalItem(
          id: 'cult_m1',
          title: 'RZA — Ghost Dog OST',
          creatorOrYear: 'Vinil 33 RPM · 1999',
          category: CulturalCategory.music,
          rating: '9.7',
          monogram: 'RZ',
          toneShade: 65,
        ),
        CulturalItem(
          id: 'cult_m2',
          title: 'Ryuichi Sakamoto — Async',
          creatorOrYear: 'Vinil Duplo · 2017',
          category: CulturalCategory.music,
          rating: '9.8',
          monogram: 'RS',
          toneShade: 80,
        ),
        CulturalItem(
          id: 'cult_m3',
          title: 'Miles Davis — Kind of Blue',
          creatorOrYear: 'Edição Mono · 1959',
          category: CulturalCategory.music,
          rating: '9.9',
          monogram: 'MD',
          toneShade: 55,
        ),
        CulturalItem(
          id: 'cult_m4',
          title: 'Yoko Kanno — Cowboy Bebop',
          creatorOrYear: 'LP Pressing · 1998',
          category: CulturalCategory.music,
          rating: '9.8',
          monogram: 'YK',
          toneShade: 72,
        ),
        // Séries & Animes
        CulturalItem(
          id: 'cult_s1',
          title: 'Great Teacher Onizuka (GTO)',
          creatorOrYear: '1999 · Pierrot',
          category: CulturalCategory.anime,
          rating: '9.5',
          monogram: 'GT',
          toneShade: 44,
        ),
        CulturalItem(
          id: 'cult_s2',
          title: 'Galaxy Express 999',
          creatorOrYear: '1978 · Matsumoto',
          category: CulturalCategory.anime,
          rating: '9.4',
          monogram: '99',
          toneShade: 38,
        ),
        CulturalItem(
          id: 'cult_s3',
          title: 'Mr. Robot',
          creatorOrYear: '2015 · Esmail',
          category: CulturalCategory.series,
          rating: '9.5',
          monogram: 'MR',
          toneShade: 28,
        ),
        CulturalItem(
          id: 'cult_s4',
          title: 'True Detective (S1)',
          creatorOrYear: '2014 · Pizzolatto',
          category: CulturalCategory.series,
          rating: '9.7',
          monogram: 'TD',
          toneShade: 40,
        ),
        // Mangás & Livros
        CulturalItem(
          id: 'cult_b1',
          title: 'Sousou no Frieren ~Zensou~',
          creatorOrYear: '2024 · Kanehito Yamada',
          category: CulturalCategory.manga,
          rating: '9.6',
          monogram: 'FR',
          toneShade: 70,
          isFeatured: true,
        ),
        CulturalItem(
          id: 'cult_b2',
          title: 'Ad Astra: Scipio to Hannibal',
          creatorOrYear: 'Mihachi Kagano',
          category: CulturalCategory.manga,
          rating: '9.3',
          monogram: 'AA',
          toneShade: 50,
        ),
        CulturalItem(
          id: 'cult_b3',
          title: 'The Fall of Rome',
          creatorOrYear: 'R. A. Lafferty',
          category: CulturalCategory.books,
          rating: '9.5',
          monogram: 'FR',
          toneShade: 46,
        ),
        CulturalItem(
          id: 'cult_b4',
          title: 'Cryptography Engineering',
          creatorOrYear: 'Ferguson, Schneier & Kohno',
          category: CulturalCategory.books,
          rating: '9.9',
          monogram: 'CE',
          toneShade: 60,
        ),
      ],
    );
  }

  static List<SpaceFolder> getInitialFolders() {
    return const [
      SpaceFolder(
        id: 'folder_infra',
        name: 'Redes & Criptografia',
        spaceIds: ['space_offgrid', 'space_monero'],
        isExpanded: false,
      ),
    ];
  }

  static List<Space> getInitialSpaces() {
    return [
      Space(
        id: 'space_qg',
        name: 'QG Nix',
        initials: 'NX',
        description: 'Comunidade central de arquitetura, tópicos interativos, chamadas e documentação do Nix.',
        iconEmoji: 'NX',
        unreadCount: 3,
        memberCount: 48,
        onlineCount: 19,
        isPublic: true,
        categoryTag: 'Arquitetura & Core',
        channels: const [
          Channel(
            id: 'ch_geral',
            spaceId: 'space_qg',
            name: 'geral',
            topic: 'Discussões gerais, coordenação e status do ecossistema Nix.',
            type: ChannelType.text,
            category: 'COMUNIDADE',
            unreadCount: 2,
          ),
          Channel(
            id: 'ch_dev',
            spaceId: 'space_qg',
            name: 'desenvolvimento-core',
            topic: 'Discussões de código Go, Flutter, SQLCipher e módulos.',
            type: ChannelType.text,
            category: 'COMUNIDADE',
          ),
          Channel(
            id: 'ch_forum_achados',
            spaceId: 'space_qg',
            name: 'topicos-e-achados',
            topic: 'Fórum interativo de análises, equipamentos, declarações e reviews com chat lateral.',
            type: ChannelType.forum,
            category: 'TÓPICOS INTERATIVOS',
            unreadCount: 4,
          ),
          Channel(
            id: 'ch_anuncios',
            spaceId: 'space_qg',
            name: 'avisos-oficiais',
            topic: 'Comunicados de segurança e marcos de release.',
            type: ChannelType.announcement,
            category: 'COMUNIDADE',
          ),
          Channel(
            id: 'ch_call_geral',
            spaceId: 'space_qg',
            name: 'Call Geral Segura',
            topic: 'Sala de áudio criptografada fim a fim via Onion v3.',
            type: ChannelType.voice,
            category: 'CHATS DE VOZ',
          ),
          Channel(
            id: 'ch_call_briefing',
            spaceId: 'space_qg',
            name: 'Voz 2 · Alinhamento',
            topic: 'Canal de voz reservado para revisão técnica.',
            type: ChannelType.voice,
            category: 'CHATS DE VOZ',
          ),
          Channel(
            id: 'ch_pub_dossies',
            spaceId: 'space_qg',
            name: 'Dossiês Canônicos',
            topic: 'Artigos canônicos versionados com hash CID e claims auditáveis.',
            type: ChannelType.publication,
            category: 'NIX ARCHIVE',
          ),
          Channel(
            id: 'ch_pub_specs',
            spaceId: 'space_qg',
            name: 'Especificações de Cripto',
            topic: 'Documentos do protocolo Double Ratchet, PQXDH e retenção.',
            type: ChannelType.publication,
            category: 'NIX ARCHIVE',
          ),
        ],
      ),
      Space(
        id: 'space_offgrid',
        name: 'Malha Off-Grid',
        initials: 'RF',
        description: 'Coordenação técnica de nós de rádio LoRa, Reticulum e mapas offline MBTiles.',
        iconEmoji: 'RF',
        unreadCount: 5,
        memberCount: 19,
        onlineCount: 7,
        isPublic: true,
        categoryTag: 'Rádio & Hardware',
        channels: const [
          Channel(
            id: 'ch_lora_sync',
            spaceId: 'space_offgrid',
            name: 'frequencia-915mhz',
            topic: 'Pacotes serializados em radio.proto (< 240 bytes). Sem mídia.',
            type: ChannelType.text,
            category: 'COMUNIDADE',
            unreadCount: 5,
          ),
          Channel(
            id: 'ch_call_radio',
            spaceId: 'space_offgrid',
            name: 'Conferência de Rádio IP',
            topic: 'Canal de voz sob transporte IP.',
            type: ChannelType.voice,
            category: 'CHATS DE VOZ',
          ),
          Channel(
            id: 'ch_pub_manuals',
            spaceId: 'space_offgrid',
            name: 'Manuais de Antena e Firmware',
            topic: 'Guias de montagem de RAK4631 e nós Reticulum.',
            type: ChannelType.publication,
            category: 'NIX ARCHIVE',
          ),
        ],
      ),
      Space(
        id: 'space_monero',
        name: 'Círculo Monero',
        initials: 'XM',
        description: 'Liquidação P2P não custodial em XMR, subendereços e operação de daemons onion.',
        iconEmoji: 'XM',
        unreadCount: 1,
        memberCount: 34,
        onlineCount: 11,
        isPublic: true,
        categoryTag: 'Finanças XMR',
        channels: const [
          Channel(
            id: 'ch_mural_p2p',
            spaceId: 'space_monero',
            name: 'mural-ofertas-p2p',
            topic: 'Ofertas efêmeras ponto a ponto com liquidação exclusiva em XMR.',
            type: ChannelType.text,
            category: 'COMUNIDADE',
            unreadCount: 1,
          ),
          Channel(
            id: 'ch_nos_onion',
            spaceId: 'space_monero',
            name: 'daemons-onion',
            topic: 'Compartilhamento de nós remotos verificados via Tor.',
            type: ChannelType.text,
            category: 'COMUNIDADE',
          ),
        ],
      ),
      Space(
        id: 'space_cultura',
        name: 'Acervo & Cinema',
        initials: 'AC',
        description: 'Curadoria de livros raros, cinema clássico, mangás e prensagens em vinil.',
        iconEmoji: 'AC',
        unreadCount: 0,
        memberCount: 14,
        onlineCount: 4,
        isPublic: true,
        categoryTag: 'Cultura & Mídia',
        channels: const [
          Channel(
            id: 'ch_acervo_debate',
            spaceId: 'space_cultura',
            name: 'curadoria-cultural',
            topic: 'Debates sobre cinema, literatura e música sem algoritmos comerciais.',
            type: ChannelType.text,
            category: 'COMUNIDADE',
          ),
        ],
      ),
    ];
  }

  /// Lista completa de grupos e canais públicos para a aba Explorar (ordenáveis do menos populoso ao mais populoso).
  static List<Space> getDiscoverablePublicSpaces() {
    return [
      const Space(
        id: 'pub_lab_pq',
        name: 'Laboratório Pós-Quântico',
        initials: 'PQ',
        description: 'Grupo de estudo focado em PQXDH, ML-KEM-768 e resistência a downgrade.',
        memberCount: 8,
        onlineCount: 3,
        isPublic: true,
        categoryTag: 'Criptografia',
        channels: [],
      ),
      const Space(
        id: 'space_cultura',
        name: 'Acervo & Cinema',
        initials: 'AC',
        description: 'Curadoria de livros raros, cinema clássico, mangás e prensagens em vinil.',
        memberCount: 14,
        onlineCount: 4,
        isPublic: true,
        categoryTag: 'Cultura & Mídia',
        channels: [],
      ),
      const Space(
        id: 'space_offgrid',
        name: 'Malha Off-Grid',
        initials: 'RF',
        description: 'Coordenação técnica de nós de rádio LoRa, Reticulum e mapas offline MBTiles.',
        memberCount: 19,
        onlineCount: 7,
        isPublic: true,
        categoryTag: 'Rádio & Hardware',
        channels: [],
      ),
      const Space(
        id: 'pub_selfhost',
        name: 'Auto-Hospedagem Enxuta',
        initials: 'SH',
        description: 'Operadores de VPS de 2 vCPU / 2 GB RAM com Alpine Linux, nftables e MinIO.',
        memberCount: 27,
        onlineCount: 9,
        isPublic: true,
        categoryTag: 'Infraestrutura',
        channels: [],
      ),
      const Space(
        id: 'space_monero',
        name: 'Círculo Monero',
        initials: 'XM',
        description: 'Liquidação P2P não custodial em XMR, subendereços e operação de daemons onion.',
        memberCount: 34,
        onlineCount: 11,
        isPublic: true,
        categoryTag: 'Finanças XMR',
        channels: [],
      ),
      const Space(
        id: 'space_qg',
        name: 'QG Nix',
        initials: 'NX',
        description: 'Comunidade central de arquitetura, tópicos interativos, chamadas e documentação do Nix.',
        memberCount: 48,
        onlineCount: 19,
        isPublic: true,
        categoryTag: 'Arquitetura & Core',
        channels: [],
      ),
    ];
  }

  static List<ForumPost> getInitialForumPosts() {
    final now = DateTime.now();
    return [
      ForumPost(
        id: 'post_1',
        channelId: 'ch_forum_achados',
        title: 'Kit Transceiver LoRa RAK4631 + Antena 915MHz',
        authorName: 'Eduardo.Op',
        authorFingerprint: '445D-119A-B882-3C0F',
        createdAt: now.subtract(const Duration(hours: 3)),
        tags: const ['Hardware', 'Eletrônicos', 'Reviews'],
        description:
            'Inspeção das placas recebidas no lote revisado.\nPeso com case: 185g · Conector SMA verificado.\nFirmware Meshtastic testado em bancada sem perda de pacotes.',
        images: const [
          ForumImageSpec(label: 'VISTA SUPERIOR PCB', subtitle: 'RAK4631 Core', code: 'IMG-01'),
          ForumImageSpec(label: 'CONECTOR & ANTENA', subtitle: 'VSWR < 1.3', code: 'IMG-02'),
          ForumImageSpec(label: 'CASE DE ALUMÍNIO', subtitle: 'Vedação IP65', code: 'IMG-03'),
          ForumImageSpec(label: 'BATERIA LIPO 3000MAH', subtitle: 'Proteção BMS', code: 'IMG-04'),
        ],
        endorsements: 12,
        comments: [
          Message(
            id: 'fmsg_1',
            channelId: 'post_1',
            senderName: 'CipherGhost',
            senderFingerprint: 'F891-72A0-B3E4-998C',
            isMe: false,
            text: 'Excelente acabamento do case. Qual foi o alcance médio em visada direta?',
            timestamp: now.subtract(const Duration(hours: 2)),
          ),
          Message(
            id: 'fmsg_2',
            channelId: 'post_1',
            senderName: 'Eduardo.Op',
            senderFingerprint: '445D-119A-B882-3C0F',
            isMe: false,
            text: 'Conseguimos 6.4 km em área urbana densa mantendo pacotes Protobuf abaixo de 180 bytes.',
            timestamp: now.subtract(const Duration(hours: 1)),
          ),
        ],
      ),
      ForumPost(
        id: 'post_2',
        channelId: 'ch_forum_achados',
        title: 'Water Cooler 240mm Silencioso para Nó Local',
        authorName: 'rehzin',
        authorFingerprint: '90A1-BC42-771E-0922',
        createdAt: now.subtract(const Duration(hours: 6)),
        tags: const ['Hardware', 'Eletrônicos'],
        description:
            'Montagem de servidor silencioso doméstico para rodar daemon Monero e réplica do Nix Archive 24/7 sem ruído térmico.',
        images: const [
          ForumImageSpec(label: 'RADIADOR 240MM', subtitle: 'Alumínio Preto', code: 'WC-01'),
          ForumImageSpec(label: 'FANS PWM 120MM', subtitle: '18 dBA Máx', code: 'WC-02'),
          ForumImageSpec(label: 'BLOCO DE COBRE', subtitle: 'Base Micro-aletas', code: 'WC-03'),
          ForumImageSpec(label: 'KIT DE MONTAGEM', subtitle: 'AM5 / LGA1700', code: 'WC-04'),
        ],
        endorsements: 8,
        comments: [
          Message(
            id: 'fmsg_3',
            channelId: 'post_2',
            senderName: 'Sentinela-Alpha',
            senderFingerprint: 'A1B2-C3D4-E5F6-001A',
            isMe: false,
            text: 'Temperatura estabilizou em quantos graus sincronizando os blocos?',
            timestamp: now.subtract(const Duration(hours: 4)),
          ),
        ],
      ),
      ForumPost(
        id: 'post_3',
        channelId: 'ch_forum_achados',
        title: 'Mouse Óptico Leve Sem Telemetria de Driver',
        authorName: 'tonhyk',
        authorFingerprint: '112B-887C-4490-AA12',
        createdAt: now.subtract(const Duration(hours: 9)),
        tags: const ['Eletrônicos', 'Reviews', 'Segurança'],
        description:
            'Periférico com configuração totalmente embarcada via switches físicos no chassi, dispensando softwares proprietários que abrem conexões de rede em segundo plano.',
        images: const [
          ForumImageSpec(label: 'CHASSI MATTE BLACK', subtitle: '54 gramas', code: 'MS-01'),
          ForumImageSpec(label: 'SWITCHES DE DPI', subtitle: 'Configuração Hardware', code: 'MS-02'),
          ForumImageSpec(label: 'RECEPTOR 2.4GHZ', subtitle: 'Cabo Paracord', code: 'MS-03'),
          ForumImageSpec(label: 'SKATES PTFE PURO', subtitle: 'Baixo Atrito', code: 'MS-04'),
        ],
        endorsements: 19,
        comments: const [],
      ),
      ForumPost(
        id: 'post_4',
        channelId: 'ch_forum_achados',
        title: 'Prensagem Japonesa em Vinil — Trilha Sonora Clássica',
        authorName: 'Archivist',
        authorFingerprint: 'ED25-9981-FA23-01BC',
        createdAt: now.subtract(const Duration(hours: 14)),
        tags: const ['Audiovisual', 'Outros', 'Reviews'],
        description:
            'Edição com Obi original preservado, capa gatefold de gramatura pesada e encarte técnico completo.',
        images: const [
          ForumImageSpec(label: 'CAPA GATEFOLD', subtitle: 'Com Obi Original', code: 'LP-01'),
          ForumImageSpec(label: 'DISCO 180G PRETO', subtitle: 'Zero Ruído deFundo', code: 'LP-02'),
          ForumImageSpec(label: 'ENCARTE TÉCNICO', subtitle: '4 Páginas', code: 'LP-03'),
          ForumImageSpec(label: 'SELO CENTRAL', subtitle: 'Primeira Tiragem', code: 'LP-04'),
        ],
        endorsements: 15,
        comments: const [],
      ),
    ];
  }

  static List<DirectMessageThread> getInitialDirectMessages() {
    final now = DateTime.now();
    return [
      DirectMessageThread(
        id: 'dm_sentinela',
        peerName: 'Sentinela-Alpha',
        peerPublicId: 'NIX-A1B2-C3D4-E5F6-001A',
        statusText: 'Online · Circuito Onion Verificado',
        isOnline: true,
        isVerified: true,
        unreadCount: 1,
        messages: [
          Message(
            id: 'dm_m1',
            channelId: 'dm_sentinela',
            senderName: 'Sentinela-Alpha',
            senderFingerprint: 'A1B2-C3D4-E5F6-001A',
            isMe: false,
            text: 'Verifiquei a assinatura do seu Card ID via QR Code. Sessão par a par validada.',
            timestamp: now.subtract(const Duration(minutes: 14)),
            reactions: const {'🛡️': 1},
          ),
        ],
      ),
      DirectMessageThread(
        id: 'dm_cipher',
        peerName: 'CipherGhost',
        peerPublicId: 'NIX-F891-72A0-B3E4-998C',
        statusText: 'Auditando schemas Protobuf',
        isOnline: true,
        isVerified: true,
        unreadCount: 0,
        messages: [
          Message(
            id: 'dm_m2',
            channelId: 'dm_cipher',
            senderName: 'GUS',
            senderFingerprint: '7E3A-9F01-C45B-289D',
            isMe: true,
            text: 'Os pacotes de rádio estão limitados a 240 bytes no radio.proto.',
            timestamp: now.subtract(const Duration(hours: 2)),
          ),
        ],
      ),
      DirectMessageThread(
        id: 'dm_archivist',
        peerName: 'Arquivista-01',
        peerPublicId: 'NIX-ED25-9981-FA23-01BC',
        statusText: 'Sincronizando réplica opt-in',
        isOnline: false,
        isVerified: true,
        unreadCount: 0,
        messages: [
          Message(
            id: 'dm_m3',
            channelId: 'dm_archivist',
            senderName: 'Arquivista-01',
            senderFingerprint: 'ED25-9981-FA23-01BC',
            isMe: false,
            text: 'Novo objeto nix.archive.article.v1 fixado na réplica secundária.',
            timestamp: now.subtract(const Duration(days: 1)),
          ),
        ],
      ),
    ];
  }

  static List<ContactRequest> getInitialContactRequests() {
    final now = DateTime.now();
    return [
      ContactRequest(
        id: 'req_1',
        peerName: 'NodeRunner-77',
        peerPublicId: 'NIX-5541-90AB-C112-88EF',
        note: 'Operador de relay parceiro. Solicitação de verificação de chave X3DH.',
        timestamp: now.subtract(const Duration(hours: 4)),
        isIncoming: true,
      ),
      ContactRequest(
        id: 'req_2',
        peerName: 'Kagano.Reader',
        peerPublicId: 'NIX-3310-FA91-002C-771B',
        note: 'Comunidade Acervo & Cinema — troca de catálogos locais.',
        timestamp: now.subtract(const Duration(days: 1)),
        isIncoming: true,
      ),
    ];
  }

  static List<XmrTransactionRecord> getInitialTransactions() {
    final now = DateTime.now();
    return [
      XmrTransactionRecord(
        id: 'tx_01',
        title: 'Renovação de Hospedagem VPS Relay (Sem KYC)',
        amountXmr: '-0.0485 XMR',
        subaddressPreview: '88a9...4f12 (Subendereço #14)',
        timestamp: now.subtract(const Duration(days: 2)),
        confirmations: 1240,
        isIncoming: false,
      ),
      XmrTransactionRecord(
        id: 'tx_02',
        title: 'Liquidação P2P #882 — Kit LoRa RAK4631',
        amountXmr: '+0.3200 XMR',
        subaddressPreview: '84c1...99b0 (Subendereço #15)',
        timestamp: now.subtract(const Duration(hours: 18)),
        confirmations: 540,
        isIncoming: true,
      ),
    ];
  }

  static List<SystemUpdateRecord> getInitialSystemUpdates() {
    return const [
      SystemUpdateRecord(
        id: 'upd_1',
        version: 'v0.2.0 — NIX AMOLED Design System',
        title: 'Identidade Monocromática, Card ID Metálico & Fórum Interativo',
        summary: 'Transição integral para o padrão visual AMOLED (#000000), Card ID em metal escovado, Passaporte Cultural e proteção antifingerprinting.',
        dateLabel: '18 Nov 2026',
        highlights: [
          'Paleta monocromática AMOLED absoluta (#000000 a #121212) sem ruído visual.',
          'Card ID interativo com QR Code público, biografia e Passaporte Cultural (Filmes, Séries, Animes, Mangás, Livros e Vinis).',
          'Pastas de grupos no dock lateral, aba Explorar (ordenada por população) e canais de Tópicos com Split-Chat.',
          'Central de Configurações com 6 módulos persistentes, incluindo Sobrevivência e Privacidade.',
        ],
      ),
      SystemUpdateRecord(
        id: 'upd_0',
        version: 'v0.1.0 — Fundação & Matriz de Privacidade',
        title: 'Especificação Inicial, Relay AutoPruner e Schemas Protobuf',
        summary: 'Estabelecimento dos 21 critérios verificáveis da Matriz The Hated One e estrutura de isolamento de sementes.',
        dateLabel: '17 Nov 2026',
        highlights: [
          'Política de transporte Fail-Closed sobre Tor Onion v3.',
          'AutoPruner dinâmico com histerese em 75%, 85% e 92% de ocupação.',
          'Isolamento estrito entre Seed A (Mensageiro) e Seed B (Monero XMR).',
        ],
      ),
    ];
  }

  static Map<String, List<Message>> getInitialMessages() {
    final now = DateTime.now();
    return {
      'ch_geral': [
        Message(
          id: 'msg_1',
          channelId: 'ch_geral',
          senderName: 'Sentinela-Alpha',
          senderFingerprint: 'A1B2-C3D4-E5F6-001A',
          isMe: false,
          text: 'Bem-vindos ao Nix. Interface atualizada para o padrão monocromático NIX AMOLED com roteamento Onion v3.',
          timestamp: now.subtract(const Duration(minutes: 25)),
          isVerified: true,
          reactions: const {'⚡': 3, '🛡️': 2},
        ),
        Message(
          id: 'msg_2',
          channelId: 'ch_geral',
          senderName: 'CipherGhost',
          senderFingerprint: 'F891-72A0-B3E4-998C',
          isMe: false,
          text: 'O novo Card ID em metal preto e os tópicos com split-chat ficaram extremamente limpos e rápidos.',
          timestamp: now.subtract(const Duration(minutes: 18)),
          isVerified: true,
        ),
        Message(
          id: 'msg_3',
          channelId: 'ch_geral',
          senderName: 'GUS',
          senderFingerprint: '7E3A-9F01-C45B-289D',
          isMe: true,
          text: 'Excelente. Toda a estética foi refinada para máxima discrição, mantendo nossas garantias criptográficas.',
          timestamp: now.subtract(const Duration(minutes: 5)),
          isVerified: true,
          ephemeralSeconds: 300,
          remainingSeconds: 240,
        ),
      ],
      'ch_dev': [
        Message(
          id: 'msg_dev_1',
          channelId: 'ch_dev',
          senderName: 'GoRelayDev',
          senderFingerprint: '1290-CC78-45FA-00E1',
          isMe: false,
          text: 'O AutoPruner com histerese (75%, 85%, 92%) está operando abaixo de 120 MB de RSS.',
          timestamp: now.subtract(const Duration(minutes: 40)),
          isVerified: true,
        ),
      ],
      'ch_anuncios': [
        Message(
          id: 'msg_anun_1',
          channelId: 'ch_anuncios',
          senderName: 'Coordenação Nix',
          senderFingerprint: '0000-A111-B222-C333',
          isMe: false,
          text: '[MARCO DE SEGURANÇA]: A Matriz de Privacidade foi validada nos portões estáticos L-S, I-S e I-A.',
          timestamp: now.subtract(const Duration(hours: 2)),
          isVerified: true,
        ),
      ],
      'ch_mural_p2p': [
        Message(
          id: 'msg_p2p_1',
          channelId: 'ch_mural_p2p',
          senderName: 'XMRTrader-09',
          senderFingerprint: '89AB-CDEF-0123-4567',
          isMe: false,
          text: 'Oferta P2P #882: Transceiver LoRa RAK4631 lacrado. Liquidação exclusiva em XMR via subendereço único.',
          timestamp: now.subtract(const Duration(minutes: 15)),
          isVerified: true,
        ),
      ],
    };
  }

  static List<Member> getInitialMembers() {
    return const [
      Member(
        id: 'mem_1',
        name: 'GUS (Você)',
        roleName: 'Arquiteto / Operador',
        role: MemberRole.operator,
        isVerified: true,
        fingerprint: '7E3A-9F01-C45B-289D',
        isOnline: true,
      ),
      Member(
        id: 'mem_2',
        name: 'Sentinela-Alpha',
        roleName: 'Guardião de Chaves',
        role: MemberRole.admin,
        isVerified: true,
        fingerprint: 'A1B2-C3D4-E5F6-001A',
        isOnline: true,
        isSpeaking: true,
      ),
      Member(
        id: 'mem_3',
        name: 'CipherGhost',
        roleName: 'Auditor Cripto',
        role: MemberRole.sentinel,
        isVerified: true,
        fingerprint: 'F891-72A0-B3E4-998C',
        isOnline: true,
      ),
      Member(
        id: 'mem_4',
        name: 'Eduardo.Op',
        roleName: 'Engenharia RF',
        role: MemberRole.member,
        isVerified: true,
        fingerprint: '445D-119A-B882-3C0F',
        isOnline: false,
      ),
    ];
  }

  static Map<String, List<Publication>> getInitialPublications() {
    return {
      'ch_pub_dossies': [
        Publication(
          id: 'pub_001',
          channelId: 'ch_pub_dossies',
          title: 'Análise de Resistência Contra Apreensão de VPS no Nix Relay',
          authorPersona: 'Persona Editorial: Arquivista-01',
          authorFingerprint: 'ED25-9981-FA23-01BC',
          contentMarkdown: '''
### Sumário da Avaliação de Ameaça

O Nix Relay opera estritamente como um **buffer transitório de envelopes cifrados**.

1. **Ausência de Plaintext:** Todo o conteúdo de mensagens e anexos é cifrado antes de deixar o dispositivo do remetente via XChaCha20-Poly1305.
2. **AutoPruner Dinâmico:** Ao atingir 75% de ocupação, o TTL decai progressivamente com histerese rígida.
3. **Memória Volátil:** Operações sensíveis são limpas via `sodium_memzero`.
          ''',
          claimsCount: 3,
          refutationsCount: 0,
          cidHash: 'bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi',
          publishedAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ],
      'ch_pub_specs': [
        Publication(
          id: 'pub_002',
          channelId: 'ch_pub_specs',
          title: 'Especificação do Handshake Híbrido Pós-Quântico (PQXDH)',
          authorPersona: 'Persona Editorial: CryptLab',
          authorFingerprint: 'PQ77-8812-BEEF-45A1',
          contentMarkdown: '''
### Visão Geral do Protocolo Híbrido

Combinação do acordo clássico **X25519** com o algoritmo KEM padronizado **ML-KEM-768**.

- **Proteção contra Downgrade:** Negociação de versão forçada no schema `message.proto`.
- **Forward Secrecy:** Garantido pela catraca simétrica Double Ratchet.
          ''',
          claimsCount: 2,
          refutationsCount: 1,
          cidHash: 'bafybeic2b7p3d26wzpt5gqfnl37t47k54a7s42gq2dfk3i64b73m2q',
          publishedAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ],
    };
  }
}
