import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Estado de inicialização e ciclo de vida do daemon Tor embutido.
enum EmbeddedTorStatus {
  stopped,
  starting,
  bootstrapping,
  ready,
  error,
}

/// Evento de progresso de conexão aos circuitos da rede Tor.
class TorBootstrapEvent {
  final int progressPercent;
  final String stepSummary;
  final EmbeddedTorStatus status;

  const TorBootstrapEvent({
    required this.progressPercent,
    required this.stepSummary,
    required this.status,
  });

  @override
  String toString() => 'TorBootstrapEvent($progressPercent%: $stepSummary [$status])';
}

/// Gerenciador de Daemon Tor Embutido (Embedded Tor / Zero-Configuration) para Projeto Nix.
///
/// Permite que os aplicativos Desktop (Linux/Windows/macOS) e Mobile (Android) executem
/// a infraestrutura Tor nativamente em segundo plano sem exigir Orbot ou configurações manuais do usuário.
class EmbeddedTorManager {
  final int socksPort;
  final int controlPort;
  final String? customDataDir;
  final String? customTorBinary;

  Process? _torProcess;
  EmbeddedTorStatus _status = EmbeddedTorStatus.stopped;
  int _currentProgress = 0;
  String _lastSummary = 'Não iniciado';

  final _bootstrapController = StreamController<TorBootstrapEvent>.broadcast();

  EmbeddedTorManager({
    this.socksPort = 9050,
    this.controlPort = 9051,
    this.customDataDir,
    this.customTorBinary,
  });

  EmbeddedTorStatus get status => _status;
  int get currentProgress => _currentProgress;
  String get lastSummary => _lastSummary;
  bool get isReady => _status == EmbeddedTorStatus.ready;
  Stream<TorBootstrapEvent> get onBootstrapProgress => _bootstrapController.stream;

  /// Retorna o diretório isolado de dados (DataDirectory) do Tor.
  String get dataDirectory {
    if (customDataDir != null) return customDataDir!;
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return '.nix_tor_data';
    return '$home/.local/share/nix/tor_data';
  }

  /// Procura o executável do Tor embutido no bundle da aplicação ou nos caminhos padrão do sistema.
  Future<String?> locateTorBinary() async {
    if (customTorBinary != null && await File(customTorBinary!).exists()) {
      return customTorBinary;
    }
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }

    // Candidatos no pacote da aplicação e no SO
    final candidates = [
      // Linux Bundle local
      '${Platform.environment['HOME']}/.local/share/nix/bundle/tor',
      '${Platform.environment['HOME']}/.local/bin/tor',
      '/usr/bin/tor',
      '/usr/local/bin/tor',
      // Android / Termux / JNI paths
      '/data/data/com.projetonix.nix_client/app_bin/tor',
      '/data/data/com.projetonix.nix_client/lib/libtor.so',
    ];

    for (final path in candidates) {
      if (await File(path).exists()) {
        return path;
      }
    }

    // Procura no PATH
    try {
      final res = await Process.run('which', ['tor']);
      if (res.exitCode == 0) {
        final path = res.stdout.toString().trim();
        if (path.isNotEmpty && await File(path).exists()) {
          return path;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Gera a configuração mínima e endurecida (`torrc`) para isolamento e fail-closed.
  Future<File> generateHardenedTorrc() async {
    final dir = Directory(dataDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final torrcFile = File('${dir.path}/torrc');
    final configContent = StringBuffer()
      ..writeln('# Torrc gerado automaticamente pelo Projeto Nix')
      ..writeln('SocksPort 127.0.0.1:$socksPort')
      ..writeln('ControlPort 127.0.0.1:$controlPort')
      ..writeln('DataDirectory ${dir.path}')
      ..writeln('CookieAuthentication 1')
      ..writeln('ClientOnly 1')
      ..writeln('SafeSocks 1')
      ..writeln('TestSocks 1')
      ..writeln('WarnUnsafeSocks 1')
      ..writeln('AvoidDiskWrites 1');

    await torrcFile.writeAsString(configContent.toString());
    return torrcFile;
  }

  /// Inicia o processo Tor em segundo plano e monitora o bootstrap dos circuitos Onion.
  Future<bool> startEmbeddedTor({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_status == EmbeddedTorStatus.ready) return true;

    // Se já houver um Tor rodando na porta SOCKS 9050, reutiliza o túnel ativo
    if (await _isPortListening('127.0.0.1', socksPort)) {
      _status = EmbeddedTorStatus.ready;
      _currentProgress = 100;
      _lastSummary = 'Conectado a túnel SOCKS5 Tor ativo';
      _bootstrapController.add(TorBootstrapEvent(
        progressPercent: 100,
        stepSummary: _lastSummary,
        status: EmbeddedTorStatus.ready,
      ));
      return true;
    }

    final binary = await locateTorBinary();
    if (binary == null) {
      _status = EmbeddedTorStatus.error;
      _lastSummary = 'Executável Tor não encontrado no bundle ou sistema.';
      return false;
    }

    final torrc = await generateHardenedTorrc();
    _status = EmbeddedTorStatus.starting;
    _currentProgress = 5;
    _lastSummary = 'Iniciando processo Tor isolado...';

    final completer = Completer<bool>();

    try {
      _torProcess = await Process.start(binary, ['-f', torrc.path]);

      _torProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _parseTorLogLine(line, completer);
      });

      _torProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _parseTorLogLine(line, completer);
      });

      _torProcess!.exitCode.then((code) {
        if (!completer.isCompleted) {
          _status = EmbeddedTorStatus.error;
          _lastSummary = 'Processo Tor encerrou com código $code.';
          completer.complete(false);
        } else {
          _status = EmbeddedTorStatus.stopped;
        }
      });

      // Timeout de segurança para o bootstrap
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          if (!completer.isCompleted) {
            _status = EmbeddedTorStatus.error;
            _lastSummary = 'Tempo limite de bootstrap excedido (45s).';
            return false;
          }
          return completer.future;
        },
      );
    } catch (e) {
      _status = EmbeddedTorStatus.error;
      _lastSummary = 'Erro ao lançar processo Tor: $e';
      return false;
    }
  }

  /// Analisa linhas de log do Tor procurando eventos de progresso de bootstrap.
  void _parseTorLogLine(String line, Completer<bool> completer) {
    if (line.contains('Bootstrapped')) {
      // Exemplo: [notice] Bootstrapped 50% (loading_descriptors): Loading relay descriptors
      final regex = RegExp(r'Bootstrapped (\d+)% (?:\((.*?)\): )?(.*)');
      final match = regex.firstMatch(line);
      if (match != null) {
        final percent = int.tryParse(match.group(1) ?? '0') ?? _currentProgress;
        final summary = match.group(3) ?? match.group(2) ?? 'Conectando à rede Onion...';

        _currentProgress = percent;
        _lastSummary = summary.trim();
        _status = percent == 100 ? EmbeddedTorStatus.ready : EmbeddedTorStatus.bootstrapping;

        _bootstrapController.add(TorBootstrapEvent(
          progressPercent: percent,
          stepSummary: _lastSummary,
          status: _status,
        ));

        if (percent == 100 && !completer.isCompleted) {
          completer.complete(true);
        }
      }
    }
  }

  /// Testa se a porta de escuta local está aceitando sockets.
  Future<bool> _isPortListening(String host, int port) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return false;
    }
    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(milliseconds: 500));
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Encerra o processo Tor embutido.
  Future<void> stop() async {
    if (_torProcess != null) {
      _torProcess!.kill(ProcessSignal.sigterm);
      _torProcess = null;
    }
    _status = EmbeddedTorStatus.stopped;
    _currentProgress = 0;
    _lastSummary = 'Parado';
  }

  void dispose() {
    stop();
    _bootstrapController.close();
  }
}
