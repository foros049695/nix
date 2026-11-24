import 'dart:async';
import 'dart:io';
import 'package:nix_transport/nix_transport.dart';
import 'media_index_updater.dart';

/// Status de cada camada de diagnóstico do catálogo.
enum DiagnosticStatus {
  passed('passed', 'Operacional', 'A camada respondeu com sucesso aos testes de integridade.'),
  failed('failed', 'Falha', 'A camada falhou no teste de conectividade ou validação.'),
  warning('warning', 'Alerta / Offline', 'A camada local está operando, mas o destino remoto está inacessível.'),
  skipped('skipped', 'Não Executado', 'O teste desta camada depende de etapas anteriores.');

  final String id;
  final String label;
  final String description;

  const DiagnosticStatus(this.id, this.label, this.description);
}

/// Relatório estruturado de diagnóstico em 7 camadas para serviços Onion e Catálogo.
class CatalogDiagnosticReport {
  final DiagnosticStatus torDaemon;
  final String torDaemonDetails;

  final DiagnosticStatus socks5Handshake;
  final String socks5HandshakeDetails;

  final DiagnosticStatus remoteOnion;
  final String remoteOnionDetails;
  final bool isPlaceholderOnion;

  final DiagnosticStatus manifestFetch;
  final String manifestFetchDetails;

  final DiagnosticStatus ed25519Signature;
  final String ed25519SignatureDetails;

  final DiagnosticStatus antiRollback;
  final String antiRollbackDetails;

  final DateTime timestamp;

  const CatalogDiagnosticReport({
    required this.torDaemon,
    required this.torDaemonDetails,
    required this.socks5Handshake,
    required this.socks5HandshakeDetails,
    required this.remoteOnion,
    required this.remoteOnionDetails,
    this.isPlaceholderOnion = false,
    required this.manifestFetch,
    required this.manifestFetchDetails,
    required this.ed25519Signature,
    required this.ed25519SignatureDetails,
    required this.antiRollback,
    required this.antiRollbackDetails,
    required this.timestamp,
  });

  bool get isAllPassed =>
      torDaemon == DiagnosticStatus.passed &&
      socks5Handshake == DiagnosticStatus.passed &&
      remoteOnion == DiagnosticStatus.passed &&
      manifestFetch == DiagnosticStatus.passed &&
      ed25519Signature == DiagnosticStatus.passed &&
      antiRollback == DiagnosticStatus.passed;

  String toSanitizedSummary() {
    final buf = StringBuffer();
    buf.writeln('=== DIAGNÓSTICO EM CAMADAS: SERVIÇOS ONION & CATÁLOGO NIX ===');
    buf.writeln('Data/Hora: ${timestamp.toIso8601String()}');
    buf.writeln('[1] Daemon Tor Local: [${torDaemon.label}] $torDaemonDetails');
    buf.writeln('[2] Túnel SOCKS5 (127.0.0.1): [${socks5Handshake.label}] $socks5HandshakeDetails');
    buf.writeln('[3] Serviço Onion Remoto: [${remoteOnion.label}] $remoteOnionDetails');
    buf.writeln('[4] Download do Manifesto: [${manifestFetch.label}] $manifestFetchDetails');
    buf.writeln('[5] Assinatura Ed25519: [${ed25519Signature.label}] $ed25519SignatureDetails');
    buf.writeln('[6] Proteção Anti-Rollback: [${antiRollback.label}] $antiRollbackDetails');
    buf.writeln('===========================================================');
    return buf.toString();
  }
}

/// Executor soberano do diagnóstico em camadas.
class CatalogDiagnostics {
  static const String knownPlaceholderOnion =
      'nixcatalog234567abcdefghijklmnopqrstuvwxyz234567abcdefaa.onion';

  static Future<CatalogDiagnosticReport> runDiagnostics({
    required Uri manifestUri,
    int socksPort = 9050,
    CatalogPublisherKeyring? keyring,
    int installedVersion = 0,
  }) async {
    final now = DateTime.now();
    DiagnosticStatus torDaemon = DiagnosticStatus.skipped;
    String torDaemonDetails = 'Não iniciado';

    DiagnosticStatus socks5 = DiagnosticStatus.skipped;
    String socks5Details = 'Aguardando teste do daemon';

    DiagnosticStatus remote = DiagnosticStatus.skipped;
    String remoteDetails = 'Aguardando SOCKS5';
    bool isPlaceholder = manifestUri.host.toLowerCase() == knownPlaceholderOnion;

    DiagnosticStatus manifestStatus = DiagnosticStatus.skipped;
    String manifestDetails = 'Aguardando conexão remota';

    DiagnosticStatus ed25519 = DiagnosticStatus.skipped;
    String ed25519Details = 'Aguardando manifesto';

    DiagnosticStatus rollback = DiagnosticStatus.skipped;
    String rollbackDetails = 'Aguardando versão';

    // Camada 1: Daemon Tor rodando na porta local
    Socket? daemonSocket;
    try {
      daemonSocket = await Socket.connect(
        '127.0.0.1',
        socksPort,
        timeout: const Duration(milliseconds: 1500),
      );
      torDaemon = DiagnosticStatus.passed;
      torDaemonDetails = 'Porta $socksPort aberta e escutando localmente (127.0.0.1).';
    } catch (e) {
      torDaemon = DiagnosticStatus.failed;
      torDaemonDetails = 'Falha ao conectar na porta local $socksPort: $e. O daemon Tor embutido está inativo.';
      return CatalogDiagnosticReport(
        torDaemon: torDaemon,
        torDaemonDetails: torDaemonDetails,
        socks5Handshake: DiagnosticStatus.failed,
        socks5HandshakeDetails: 'Daemon Tor offline',
        remoteOnion: DiagnosticStatus.skipped,
        remoteOnionDetails: 'Dependência Tor offline',
        isPlaceholderOnion: isPlaceholder,
        manifestFetch: DiagnosticStatus.skipped,
        manifestFetchDetails: 'Dependência Tor offline',
        ed25519Signature: DiagnosticStatus.skipped,
        ed25519SignatureDetails: 'Não executado',
        antiRollback: DiagnosticStatus.skipped,
        antiRollbackDetails: 'Não executado',
        timestamp: now,
      );
    } finally {
      daemonSocket?.destroy();
    }

    // Camada 2: Handshake SOCKS5 RFC 1928
    try {
      final s = await Socket.connect('127.0.0.1', socksPort, timeout: const Duration(seconds: 2));
      s.add([0x05, 0x01, 0x00]); // SOCKS5, 1 método, sem autenticação
      final reply = await s.first.timeout(const Duration(seconds: 2));
      s.destroy();

      if (reply.length >= 2 && reply[0] == 0x05 && reply[1] == 0x00) {
        socks5 = DiagnosticStatus.passed;
        socks5Details = 'SOCKS5 proxy respondendo conforme RFC 1928 (Handshake OK).';
      } else {
        socks5 = DiagnosticStatus.failed;
        socks5Details = 'Resposta inesperada do SOCKS5 local: $reply.';
      }
    } catch (e) {
      socks5 = DiagnosticStatus.failed;
      socks5Details = 'Falha no aperto de mão SOCKS5: $e.';
    }

    if (socks5 != DiagnosticStatus.passed) {
      return CatalogDiagnosticReport(
        torDaemon: torDaemon,
        torDaemonDetails: torDaemonDetails,
        socks5Handshake: socks5,
        socks5HandshakeDetails: socks5Details,
        remoteOnion: DiagnosticStatus.skipped,
        remoteOnionDetails: 'SOCKS5 inoperante',
        isPlaceholderOnion: isPlaceholder,
        manifestFetch: DiagnosticStatus.skipped,
        manifestFetchDetails: 'SOCKS5 inoperante',
        ed25519Signature: DiagnosticStatus.skipped,
        ed25519SignatureDetails: 'Não executado',
        antiRollback: DiagnosticStatus.skipped,
        antiRollbackDetails: 'Não executado',
        timestamp: now,
      );
    }

    // Camada 3: Serviço Onion Remoto Acessível vs Placeholder
    final isLoopback = TransportPolicy.isLoopbackHost(manifestUri.host);
    final isHttps = manifestUri.scheme == 'https' || isLoopback;
    if (!isHttps && manifestUri.host.endsWith('.onion')) {
      if (isPlaceholder) {
        remote = DiagnosticStatus.warning;
        remoteDetails = 'Endereço padrão de demonstração ($knownPlaceholderOnion) é um placeholder e não possui nó ativo na rede Tor.';
      } else {
        try {
          final connector = Socks5Connector(proxyHost: '127.0.0.1', proxyPort: socksPort);
          final port = manifestUri.hasPort ? manifestUri.port : 80;
          final conn = await connector.connectRaw(
            manifestUri.host,
            port,
            requireOnionV3: true,
            timeout: const Duration(seconds: 15),
          );
          conn.socket.close();
          remote = DiagnosticStatus.passed;
          remoteDetails = 'Serviço Onion v3 alcançado com sucesso através da rede Tor.';
        } catch (e) {
          remote = DiagnosticStatus.warning;
          remoteDetails = 'Túnel SOCKS5 Tor está ativo, mas o descritor Onion (${manifestUri.host}) não foi encontrado ou o publicador está offline: $e';
        }
      }
    } else if (isHttps) {
      remote = DiagnosticStatus.passed;
      remoteDetails = isLoopback
          ? 'Ambiente de teste loopback local.'
          : 'Espelho HTTPS seguro (${manifestUri.host}).';
    }

    // Camada 4: Download e parsing do Manifesto
    SignedCatalogManifest? parsedManifest;
    if (remote == DiagnosticStatus.passed) {
      try {
        final updateManager = CatalogUpdateManager(
          keyring: keyring,
          transportPolicy: TransportPolicy(
            mode: isLoopback ? TransportMode.loopbackTest : TransportMode.torFailClosed,
            socksPort: socksPort,
          ),
        );
        parsedManifest = await updateManager.fetchManifest(
          manifestUri,
          allowClearnet: isHttps,
        );
        manifestStatus = DiagnosticStatus.passed;
        manifestDetails = 'Manifesto v${parsedManifest.version} obtido com sucesso (${parsedManifest.entryCount} obras, ${(parsedManifest.byteSize / 1024 / 1024).toStringAsFixed(1)} MB).';
      } catch (e) {
        manifestStatus = DiagnosticStatus.failed;
        manifestDetails = 'Erro ao baixar ou interpretar manifesto: $e';
      }
    } else {
      manifestStatus = DiagnosticStatus.skipped;
      manifestDetails = isPlaceholder
          ? 'Publicador configurado é um endereço placeholder de exemplo.'
          : 'Publicador Onion indisponível ou inacessível via circuito Tor.';
    }

    // Camada 5: Assinatura Ed25519
    if (parsedManifest != null) {
      final kr = keyring ??
          CatalogPublisherKeyring(
            trustedKeysHex: {
              CatalogPublisherKeyring.officialPublisherKeyHex,
            },
            allowTestFixtureKey: true,
            isProductionMode: false,
          );
      try {
        final isValidSig = await parsedManifest.verifyManifest(kr);
        if (isValidSig) {
          ed25519 = DiagnosticStatus.passed;
          final signerShort = parsedManifest.signerEd25519Hex.length >= 16
              ? '${parsedManifest.signerEd25519Hex.substring(0, 16)}...'
              : parsedManifest.signerEd25519Hex;
          ed25519Details = 'Assinatura Ed25519 válida por autoridade confiável (Signer: $signerShort).';
        } else {
          ed25519 = DiagnosticStatus.failed;
          ed25519Details = 'Assinatura Ed25519 não corresponde ao digest do manifesto.';
        }
      } catch (e) {
        ed25519 = DiagnosticStatus.failed;
        ed25519Details = 'Falha na verificação da assinatura Ed25519: $e';
      }
    } else {
      ed25519 = DiagnosticStatus.skipped;
      ed25519Details = 'Aguardando obtenção do manifesto';
    }

    // Camada 6: Proteção Anti-Rollback
    if (parsedManifest != null) {
      if (parsedManifest.version >= installedVersion) {
        rollback = DiagnosticStatus.passed;
        rollbackDetails = 'Versão remota v${parsedManifest.version} compatível com versão local v$installedVersion. Anti-Rollback verificado.';
      } else {
        rollback = DiagnosticStatus.failed;
        rollbackDetails = 'Tentativa de rollback detectada: v${parsedManifest.version} < v$installedVersion!';
      }
    } else {
      rollback = DiagnosticStatus.skipped;
      rollbackDetails = 'Aguardando obtenção do manifesto';
    }

    return CatalogDiagnosticReport(
      torDaemon: torDaemon,
      torDaemonDetails: torDaemonDetails,
      socks5Handshake: socks5,
      socks5HandshakeDetails: socks5Details,
      remoteOnion: remote,
      remoteOnionDetails: remoteDetails,
      isPlaceholderOnion: isPlaceholder,
      manifestFetch: manifestStatus,
      manifestFetchDetails: manifestDetails,
      ed25519Signature: ed25519,
      ed25519SignatureDetails: ed25519Details,
      antiRollback: rollback,
      antiRollbackDetails: rollbackDetails,
      timestamp: now,
    );
  }
}
