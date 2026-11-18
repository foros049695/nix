import '../core/models/space.dart';
import '../core/models/channel.dart';
import '../core/models/message.dart';
import '../core/models/member.dart';
import '../core/models/publication.dart';

class MockData {
  static List<Space> getInitialSpaces() {
    return [
      Space(
        id: 'space_qg',
        name: 'QG Nix',
        initials: 'NX',
        description: 'Servidor central soberano para coordenação técnica e desenvolvimento do Nix.',
        iconEmoji: '🏴‍☠️',
        channels: [
          const Channel(
            id: 'ch_geral',
            spaceId: 'space_qg',
            name: 'geral',
            topic: 'Discussões gerais, coordenação e status do ecossistema Nix.',
            type: ChannelType.text,
            category: '💬 TÓPICOS DE TEXTO',
            unreadCount: 2,
          ),
          const Channel(
            id: 'ch_dev',
            spaceId: 'space_qg',
            name: 'desenvolvimento-core',
            topic: 'Discussões de código Go, Flutter, SQLCipher e libs nativas.',
            type: ChannelType.text,
            category: '💬 TÓPICOS DE TEXTO',
          ),
          const Channel(
            id: 'ch_anuncios',
            spaceId: 'space_qg',
            name: 'avisos-taticos',
            topic: 'Comunicados de segurança e marcos de release (Fase 1).',
            type: ChannelType.announcement,
            category: '💬 TÓPICOS DE TEXTO',
          ),
          const Channel(
            id: 'ch_call_geral',
            spaceId: 'space_qg',
            name: 'Call Geral Segura',
            topic: 'Sala de áudio criptografada fim a fim com sinalização via Onion v3.',
            type: ChannelType.voice,
            category: '🔊 SALAS DE VOZ & CALL',
          ),
          const Channel(
            id: 'ch_call_briefing',
            spaceId: 'space_qg',
            name: 'Briefing Tático',
            topic: 'Canal de voz reservado para alinhamento rápido de operações.',
            type: ChannelType.voice,
            category: '🔊 SALAS DE VOZ & CALL',
          ),
          const Channel(
            id: 'ch_pub_dossies',
            spaceId: 'space_qg',
            name: 'Dossiês Canônicos',
            topic: 'Artigos canônicos versionados com hash CID e claims auditáveis.',
            type: ChannelType.publication,
            category: '📜 NIX ARCHIVE (PUBLICAÇÕES)',
          ),
          const Channel(
            id: 'ch_pub_specs',
            spaceId: 'space_qg',
            name: 'Especificações de Cripto',
            topic: 'Documentos do protocolo Double Ratchet, PQXDH e retenção.',
            type: ChannelType.publication,
            category: '📜 NIX ARCHIVE (PUBLICAÇÕES)',
          ),
        ],
      ),
      Space(
        id: 'space_offgrid',
        name: 'Resistência Off-Grid',
        initials: 'RF',
        description: 'Coordenação tática de nós de rádio LoRa, Reticulum e telemetria ATAK-CIV.',
        iconEmoji: '📡',
        channels: [
          const Channel(
            id: 'ch_lora_sync',
            spaceId: 'space_offgrid',
            name: 'frequencia-915mhz',
            topic: 'Pacotes serializados em radio.proto (< 240 bytes). Sem mídia.',
            type: ChannelType.text,
            category: '💬 TÓPICOS DE TEXTO',
          ),
          const Channel(
            id: 'ch_call_radio',
            spaceId: 'space_offgrid',
            name: 'Frequência de Rádio IP',
            topic: 'Canal de voz bridging via IP (voz não é transmitida via LoRa).',
            type: ChannelType.voice,
            category: '🔊 SALAS DE VOZ & CALL',
          ),
          const Channel(
            id: 'ch_pub_manuals',
            spaceId: 'space_offgrid',
            name: 'Manuais de Antena e Firmware',
            topic: 'Guias de montagem de RAK4631 e nós Reticulum.',
            type: ChannelType.publication,
            category: '📜 NIX ARCHIVE (PUBLICAÇÕES)',
          ),
        ],
      ),
      Space(
        id: 'space_monero',
        name: 'Círculo Monero',
        initials: 'XMR',
        description: 'Discussões e mural P2P de ofertas em XMR sem custódia central.',
        iconEmoji: '🪙',
        channels: [
          const Channel(
            id: 'ch_mural_p2p',
            spaceId: 'space_monero',
            name: 'mural-ofertas-p2p',
            topic: 'Ofertas efêmeras de troca física e serviços com liquidação XMR.',
            type: ChannelType.text,
            category: '💬 TÓPICOS DE TEXTO',
          ),
          const Channel(
            id: 'ch_nos_onion',
            spaceId: 'space_monero',
            name: 'daemons-onion',
            topic: 'Compartilhamento de nós remotos confiáveis via Tor.',
            type: ChannelType.text,
            category: '💬 TÓPICOS DE TEXTO',
          ),
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
          text: 'Sejam bem-vindos ao Nix Messenger. Conexão roteada exclusivamente via Tor Onion Service (v3).',
          timestamp: now.subtract(const Duration(minutes: 25)),
          isVerified: true,
        ),
        Message(
          id: 'msg_2',
          channelId: 'ch_geral',
          senderName: 'CipherGhost',
          senderFingerprint: 'F891-72A0-B3E4-998C',
          isMe: false,
          text: 'Repositório GitHub oficial online e sincronizado! Estrutura de canais por tópicos operando.',
          timestamp: now.subtract(const Duration(minutes: 18)),
          isVerified: true,
        ),
        Message(
          id: 'msg_3',
          channelId: 'ch_geral',
          senderName: 'Operador-01',
          senderFingerprint: '7E3A-9F01-C45B-289D',
          isMe: true,
          text: 'Excelente. O cliente está estruturado com salas de texto, salas de call táticas e publicações do Nix Archive.',
          timestamp: now.subtract(const Duration(minutes: 5)),
          isVerified: true,
          ephemeralSeconds: 300,
          remainingSeconds: 240,
        ),
        Message(
          id: 'msg_4',
          channelId: 'ch_geral',
          senderName: 'ShadowOps',
          senderFingerprint: '445D-119A-B882-3C0F',
          isMe: false,
          text: 'Testando envelope E2EE Double Ratchet. Anexos estão passando por remoção de metadados EXIF antes da cifra.',
          timestamp: now.subtract(const Duration(minutes: 2)),
          isVerified: true,
        ),
      ],
      'ch_dev': [
        Message(
          id: 'msg_dev_1',
          channelId: 'ch_dev',
          senderName: 'GoRelayDev',
          senderFingerprint: '1290-CC78-45FA-00E1',
          isMe: false,
          text: 'O AutoPruner com histerese (75%, 85%, 92%) foi compilado em Go. Consumo de RSS medido em < 120 MB em repouso.',
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
          text: '📢 [MARCO DE SEGURANÇA]: A Matriz de Privacidade foi validada nos portões L-S, I-S e I-A. Zero telemetria presente.',
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
          text: 'Oferta P2P #882: Venda de hardware LoRa RAK4631 lacrado. Pagamento exclusivo em XMR via subendereço descartável.',
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
        name: 'Operador-01 (Você)',
        roleName: 'Operador Local',
        role: MemberRole.operator,
        isVerified: true,
        fingerprint: '7E3A-9F01-C45B-289D',
        isOnline: true,
      ),
      Member(
        id: 'mem_2',
        name: 'Sentinela-Alpha',
        roleName: 'Administrador de Chave',
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
        name: 'ShadowOps',
        roleName: 'Comunicações RF',
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

> *A integridade deste documento pode ser verificada contra o CID canônico.*
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
