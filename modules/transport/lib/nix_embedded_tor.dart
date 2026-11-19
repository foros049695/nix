import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'nix_transport.dart'
    show TorControlClient, TorDiagnostics, TransportPolicy;

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
  int _activeSocksPort;
  int _activeControlPort;
  final String? customDataDir;
  final String? Function()? dataDirResolver;
  final String? customTorBinary;
  final List<String> Function()? extraBinaryCandidatesResolver;

  // Injetáveis para testar sem sondar portas ou executar o Tor do sistema.
  final Future<bool> Function(String, int) _portProbe;
  final Future<Process> Function(String, List<String>,
      {Map<String, String>? environment}) _processStarter;

  Process? _torProcess;
  EmbeddedTorStatus _status = EmbeddedTorStatus.stopped;
  int _currentProgress = 0;
  String _lastSummary = 'Não iniciado';
  String? _activeOnionV3Address;
  String? _torVersion;
  String? _resolvedBinaryPath;

  final _bootstrapController = StreamController<TorBootstrapEvent>.broadcast();

  EmbeddedTorManager({
    int socksPort = 9050,
    int controlPort = 9051,
    this.customDataDir,
    this.dataDirResolver,
    this.customTorBinary,
    this.extraBinaryCandidatesResolver,
    Future<bool> Function(String, int)? portProbe,
    Future<Process> Function(String, List<String>,
            {Map<String, String>? environment})?
        processStarter,
  })  : _activeSocksPort = socksPort,
        _activeControlPort = controlPort,
        _portProbe = portProbe ?? _isPortListening,
        _processStarter = processStarter ?? Process.start;

  int get socksPort => _activeSocksPort;
  int get controlPort => _activeControlPort;
  EmbeddedTorStatus get status => _status;
  int get currentProgress => _currentProgress;
  String get lastSummary => _lastSummary;
  String? get activeOnionV3Address => _activeOnionV3Address;
  String? get torVersion => _torVersion;
  String? get resolvedBinaryPath => _resolvedBinaryPath;
  bool get isReady => _status == EmbeddedTorStatus.ready;
  Stream<TorBootstrapEvent> get onBootstrapProgress =>
      _bootstrapController.stream;

  /// Retorna o diretório isolado de dados (DataDirectory) do Tor.
  String get dataDirectory {
    if (customDataDir != null && customDataDir!.isNotEmpty) {
      return customDataDir!;
    }
    final resolved = dataDirResolver?.call();
    if (resolved != null && resolved.isNotEmpty) {
      return resolved;
    }
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return '.nix_tor_data';
    return '$home/.local/share/nix/tor_data';
  }

  /// Procura o executável do Tor embutido no bundle da aplicação ou nos caminhos padrão do sistema.
  Future<String?> locateTorBinary() async {
    if (customTorBinary != null) {
      if (await File(customTorBinary!).exists()) {
        _resolvedBinaryPath = customTorBinary;
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
    final extra = extraBinaryCandidatesResolver?.call() ?? const <String>[];

    // Candidatos ordenados: extras (Android nativeLibraryDir/libtor.so) > pacote local > ~/.local > sistema
    final candidates = [
      ...extra,
      if (exeDir.isNotEmpty) '$exeDir/tor',
      if (exeDir.isNotEmpty) '$exeDir/data/tor',
      if (home.isNotEmpty) '$home/.local/share/nix/bundle/tor',
      if (home.isNotEmpty) '$home/.local/bin/tor',
      '/usr/bin/tor',
      '/usr/local/bin/tor',
      // Android / JNI fallback paths
      '/data/data/com.projetonix.nix_client/app_bin/tor',
      '/data/data/com.projetonix.nix_client/lib/libtor.so',
    ];

    for (final path in candidates) {
      if (path.trim().isEmpty) continue;
      final file = File(path);
      if (await file.exists()) {
        try {
          // Em Android nativeLibraryDir é somente leitura e já executável pelo SO.
          if (!Platform.isWindows && !Platform.isAndroid) {
            await Process.run('chmod', ['+x', path]);
          }
        } catch (_) {}
        _resolvedBinaryPath = path;
        return path;
      }
    }

    // Procura no PATH (desktop POSIX)
    if (!Platform.isAndroid) {
      try {
        final res = await Process.run('which', ['tor']);
        if (res.exitCode == 0) {
          final path = res.stdout.toString().trim();
          if (path.isNotEmpty && await File(path).exists()) {
            _resolvedBinaryPath = path;
            return path;
          }
        }
      } catch (_) {}
    }

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
      ..writeln(
        'SocksPort 127.0.0.1:$_activeSocksPort IsolateClientAddr IsolateClientProtocol IsolateDestPort IsolateDestAddr',
      )
      ..writeln('ControlPort 127.0.0.1:$_activeControlPort')
      ..writeln('DataDirectory ${dir.path}')
      ..writeln('CookieAuthentication 1')
      ..writeln('ClientOnly 1')
      ..writeln('SafeSocks 1')
      ..writeln('TestSocks 1')
      ..writeln('WarnUnsafeSocks 1')
      ..writeln('AvoidDiskWrites 1')
      ..writeln('HiddenServiceSingleHopMode 0')
      ..writeln('HiddenServiceNonAnonymousMode 0');

    await torrcFile.writeAsString(configContent.toString());
    return torrcFile;
  }

  /// Inicia o processo Tor em segundo plano e monitora o bootstrap dos circuitos Onion.
  Future<bool> startEmbeddedTor({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_status == EmbeddedTorStatus.ready) {
      final op = await verifyOperationalState();
      if (op.daemonSocksActive && op.circuitOperational) {
        return true;
      }
      _status = EmbeddedTorStatus.stopped;
    }

    // Se já houver um listener respondendo na porta SOCKS, somente reutiliza
    // se pertencer ao nosso DataDirectory (control_auth_cookie autenticado e PROGRESS=100).
    // Caso outra instância não auditável ocupe a porta 9050, inicia daemon isolado em portas próprias.
    if (await _portProbe('127.0.0.1', _activeSocksPort)) {
      final cookieFile = File('$dataDirectory/control_auth_cookie');
      if (await cookieFile.exists()) {
        final diag = await TorDiagnostics.diagnose(
          host: '127.0.0.1',
          socksPort: _activeSocksPort,
          controlPort: _activeControlPort,
          controlCookiePath: cookieFile.path,
        );
        final bootstrapped100 = diag.socksReachable &&
            diag.controlPortReachable &&
            (diag.bootstrapStatus?.contains('PROGRESS=100') ?? false);
        if (bootstrapped100) {
          _status = EmbeddedTorStatus.ready;
          _currentProgress = 100;
          _lastSummary = 'Conectado ao túnel Tor Onion v3 auditado (100%)';
          _bootstrapController.add(TorBootstrapEvent(
            progressPercent: 100,
            stepSummary: _lastSummary,
            status: EmbeddedTorStatus.ready,
          ));
          return true;
        }
      }
      // Porta ocupada por outro daemon sem cookie auditável do Nix -> isola em portas dedicadas.
      if (_activeSocksPort == 9050) {
        _activeSocksPort = 19050;
        _activeControlPort = 19051;
      } else {
        _activeSocksPort += 2;
        _activeControlPort += 2;
      }
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
    _lastSummary = 'Iniciando processo Tor isolado (Onion v3)...';
    _bootstrapController.add(TorBootstrapEvent(
      progressPercent: _currentProgress,
      stepSummary: _lastSummary,
      status: _status,
    ));

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

  /// Verifica ControlPort autenticado, circuito BUILT em 100% e provisiona serviço efêmero Onion v3.
  Future<
      ({
        bool socksActive,
        bool circuitOperational,
        bool onionV3Ready,
        String? onionV3Address,
        String? torVersion,
        String detail,
      })> verifyAndProvisionOnionV3({
    int virtualPort = 80,
    int targetPort = 18080,
  }) async {
    final socksOk = await _portProbe('127.0.0.1', _activeSocksPort);
    if (!socksOk) {
      return (
        socksActive: false,
        circuitOperational: false,
        onionV3Ready: false,
        onionV3Address: null,
        torVersion: _torVersion,
        detail:
            'Porta SOCKS5 127.0.0.1:$_activeSocksPort inativa ou protocolo inválido.',
      );
    }

    final cookieFile = File('$dataDirectory/control_auth_cookie');
    if (!await cookieFile.exists()) {
      return (
        socksActive: true,
        circuitOperational: false,
        onionV3Ready: false,
        onionV3Address: null,
        torVersion: _torVersion,
        detail:
            'Cookie ControlPort ausente em $dataDirectory — não é possível auditar bootstrap Onion v3.',
      );
    }

    TorControlClient? ctrl;
    try {
      ctrl = await TorControlClient.connect(
        host: '127.0.0.1',
        port: _activeControlPort,
        timeout: const Duration(seconds: 4),
      );
      await ctrl.authenticateCookieFile(cookieFile.path);

      final bootstrap = await ctrl.getInfo('status/bootstrap-phase');
      final bootstrapped100 = bootstrap.contains('PROGRESS=100');

      try {
        _torVersion = (await ctrl.getInfo('version')).trim();
      } catch (_) {}

      bool hasBuiltCircuit = false;
      try {
        final liveness = (await ctrl.getInfo('network-liveness')).trim().toLowerCase();
        hasBuiltCircuit = liveness == 'up';
      } catch (_) {}
      if (!hasBuiltCircuit) {
        try {
          final circuits = await ctrl.getInfo('circuit-status');
          hasBuiltCircuit = circuits.contains('BUILT');
        } catch (_) {}
      }

      final circuitOk = bootstrapped100 && hasBuiltCircuit;
      if (!circuitOk) {
        return (
          socksActive: true,
          circuitOperational: false,
          onionV3Ready: false,
          onionV3Address: _activeOnionV3Address,
          torVersion: _torVersion,
          detail: 'Tor ainda sem circuito 100% operacional ($bootstrap).',
        );
      }

      if (_activeOnionV3Address == null ||
          !TransportPolicy.isValidOnionV3Host(_activeOnionV3Address!)) {
        final created = await ctrl.addOnionV3(
          virtualPort: virtualPort,
          targetPort: targetPort,
          detach: true,
        );
        final candidate = '${created.serviceId}.onion';
        if (TransportPolicy.isValidOnionV3Host(candidate)) {
          _activeOnionV3Address = candidate;
        }
      }

      final onionReady = _activeOnionV3Address != null &&
          TransportPolicy.isValidOnionV3Host(_activeOnionV3Address!);

      return (
        socksActive: true,
        circuitOperational: true,
        onionV3Ready: onionReady,
        onionV3Address: _activeOnionV3Address,
        torVersion: _torVersion,
        detail: onionReady
            ? 'Tor ${_torVersion ?? ""} 100% · Circuito BUILT · Onion v3: $_activeOnionV3Address'
            : 'Circuito Tor 100%, porém serviço Onion v3 não pôde ser confirmado.',
      );
    } catch (e) {
      return (
        socksActive: true,
        circuitOperational: false,
        onionV3Ready: false,
        onionV3Address: _activeOnionV3Address,
        torVersion: _torVersion,
        detail: 'Falha ao auditar Tor ControlPort em 127.0.0.1:$_activeControlPort: $e',
      );
    } finally {
      try {
        await ctrl?.close();
      } catch (_) {}
    }
  }

  /// Diferencia daemon SOCKS5 ativo de circuito Tor 100% operacional.
  Future<({bool daemonSocksActive, bool circuitOperational, String detail})>
      verifyOperationalState() async {
    final socksOk = await _portProbe('127.0.0.1', _activeSocksPort);
    if (!socksOk) {
      return (
        daemonSocksActive: false,
        circuitOperational: false,
        detail:
            'Porta SOCKS5 127.0.0.1:$_activeSocksPort inativa ou protocolo inválido.',
      );
    }
    final cookieFile = File('$dataDirectory/control_auth_cookie');
    if (await cookieFile.exists()) {
      final diag = await TorDiagnostics.diagnose(
        host: '127.0.0.1',
        socksPort: _activeSocksPort,
        controlPort: _activeControlPort,
        controlCookiePath: cookieFile.path,
      );
      final circuitOk = diag.socksReachable &&
          diag.controlPortReachable &&
          (diag.bootstrapStatus?.contains('PROGRESS=100') ?? false);
      return (
        daemonSocksActive: true,
        circuitOperational: circuitOk,
        detail: diag.message,
      );
    }
    final circuitOk = _status == EmbeddedTorStatus.ready && _currentProgress == 100;
    return (
      daemonSocksActive: true,
      circuitOperational: circuitOk,
      detail: circuitOk
          ? 'SOCKS5 Tor operacional e bootstrap em 100%.'
          : 'Daemon SOCKS5 ativo, porém circuito Tor ainda não confirmou 100% de bootstrap.',
    );
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
    _activeOnionV3Address = null;
    _lastSummary = 'Parado';
  }

  void dispose() {
    stop();
    _bootstrapController.close();
  }
}
