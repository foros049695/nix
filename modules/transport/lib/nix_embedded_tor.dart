import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'nix_transport.dart' show TorDiagnostics;

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
  String toString() =>
      'TorBootstrapEvent($progressPercent%: $stepSummary [$status])';
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

  // Injetáveis para testar sem sondar portas ou executar o Tor do sistema.
  final Future<bool> Function(String, int) _portProbe;
  final Future<Process> Function(String, List<String>,
      {Map<String, String>? environment}) _processStarter;

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
    Future<bool> Function(String, int)? portProbe,
    Future<Process> Function(String, List<String>,
            {Map<String, String>? environment})?
        processStarter,
  })  : _portProbe = portProbe ?? _isPortListening,
        _processStarter = processStarter ?? Process.start;

  EmbeddedTorStatus get status => _status;
  int get currentProgress => _currentProgress;
  String get lastSummary => _lastSummary;
  bool get isReady => _status == EmbeddedTorStatus.ready;
  Stream<TorBootstrapEvent> get onBootstrapProgress =>
      _bootstrapController.stream;

  /// Retorna o diretório isolado de dados (DataDirectory) do Tor.
  String get dataDirectory {
    if (customDataDir != null) return customDataDir!;
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return '.nix_tor_data';
    return '$home/.local/share/nix/tor_data';
  }

  /// Procura o executável do Tor embutido no bundle da aplicação ou nos caminhos padrão do sistema.
  Future<String?> locateTorBinary() async {
    if (customTorBinary != null) {
      if (await File(customTorBinary!).exists()) {
        return customTorBinary;
      }
      return null;
    }
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }

    // Diretório base do executável atual (bundle)
    String exeDir = '';
    try {
      exeDir = File(Platform.resolvedExecutable).parent.path;
    } catch (_) {}

    final home = Platform.environment['HOME'] ?? '';

    // Candidatos ordenados: pacote local do app > ~/.local > sistema
    final candidates = [
      if (exeDir.isNotEmpty) '$exeDir/tor',
      if (exeDir.isNotEmpty) '$exeDir/data/tor',
      if (home.isNotEmpty) '$home/.local/share/nix/bundle/tor',
      if (home.isNotEmpty) '$home/.local/bin/tor',
      '/usr/bin/tor',
      '/usr/local/bin/tor',
      // Android / Termux / JNI paths
      '/data/data/com.projetonix.nix_client/app_bin/tor',
      '/data/data/com.projetonix.nix_client/lib/libtor.so',
    ];

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) {
        try {
          // Garante permissão de execução em ambientes POSIX
          if (!Platform.isWindows) {
            await Process.run('chmod', ['+x', path]);
          }
        } catch (_) {}
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
    // Tor exige permissão estrita 0700 no DataDirectory
    try {
      if (!Platform.isWindows) {
        await Process.run('chmod', ['0700', dir.path]);
      }
    } catch (_) {}

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
    if (await _portProbe('127.0.0.1', socksPort)) {
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
      final binDir = File(binary).parent.path;
      final home = Platform.environment['HOME'] ?? '';
      final ldPath =
          '$binDir/lib:$binDir:$home/.local/lib:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}';

      final process = await _processStarter(
        binary,
        ['-f', torrc.path],
        environment: {'LD_LIBRARY_PATH': ldPath},
      );
      _torProcess = process;

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (identical(_torProcess, process)) {
          _parseTorLogLine(line, completer);
        }
      });

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (identical(_torProcess, process)) {
          _parseTorLogLine(line, completer);
        }
      });

      process.exitCode.then((code) {
        if (!identical(_torProcess, process)) return;
        _torProcess = null;
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
        onTimeout: () async {
          if (completer.isCompleted) return completer.future;
          // Retira o processo antes de matar: logs/exit tardios não mudam o erro.
          _torProcess = null;
          completer.complete(false);
          await _terminateProcess(process);
          _status = EmbeddedTorStatus.error;
          _lastSummary =
              'Tempo limite de bootstrap excedido (${timeout.inMilliseconds}ms).';
          return false;
        },
      );
    } catch (e) {
      final process = _torProcess;
      _torProcess = null;
      if (process != null) await _terminateProcess(process);
      _status = EmbeddedTorStatus.error;
      _lastSummary = 'Erro ao lançar processo Tor: $e';
      return false;
    }
  }

  /// Analisa linhas de log do Tor procurando eventos de progresso de bootstrap.
  void _parseTorLogLine(String line, Completer<bool> completer) {
    if (line.contains('Bootstrapped ')) {
      final percentMatch = RegExp(r'Bootstrapped (\d+)%').firstMatch(line);
      if (percentMatch != null) {
        final percent =
            int.tryParse(percentMatch.group(1) ?? '0') ?? _currentProgress;
        String summary = 'Conectando à rede Onion...';
        final colonIdx = line.lastIndexOf(': ');
        if (colonIdx != -1 && colonIdx + 2 < line.length) {
          summary = line.substring(colonIdx + 2).trim();
        }

        _currentProgress = percent;
        _lastSummary = summary;
        _status = percent == 100
            ? EmbeddedTorStatus.ready
            : EmbeddedTorStatus.bootstrapping;

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

  /// Verifica se já existe um proxy SOCKS5 Tor respondendo ao greeting RFC 1928.
  static Future<bool> _isPortListening(String host, int port) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return false;
    }
    return TorDiagnostics.probeSocks5Proxy(
      host,
      port,
      timeout: const Duration(milliseconds: 700),
    );
  }

  static Future<void> _terminateProcess(Process process) async {
    process.kill(ProcessSignal.sigterm);
    await process.exitCode.timeout(const Duration(seconds: 1),
        onTimeout: () async {
      process.kill(ProcessSignal.sigkill);
      return process.exitCode;
    });
  }

  /// Encerra o processo Tor embutido e aguarda sua saída.
  Future<void> stop() async {
    final process = _torProcess;
    _torProcess = null;
    if (process != null) await _terminateProcess(process);
    _status = EmbeddedTorStatus.stopped;
    _currentProgress = 0;
    _lastSummary = 'Parado';
  }

  void dispose() {
    stop();
    _bootstrapController.close();
  }
}
