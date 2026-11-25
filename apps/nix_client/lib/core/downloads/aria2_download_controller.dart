import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'dart_segmented_downloader.dart';
import 'models/download_task.dart';

typedef DownloadStatusChangeNotifier = void Function(List<DownloadTask> tasks);

/// Perfis de desempenho para downloads diretos HTTP/HTTPS.
enum DownloadPerformanceProfile {
  conservative('conservative', 'Conservador', 2, 2, 35, '512K'),
  balanced('balanced', 'Equilibrado (Recomendado)', 4, 4, 20, '256K'),
  highPerformance('highPerformance', 'Alto Desempenho', 8, 8, 15, '256K'),
  turbo('turbo', 'Turbo Sustentado', 16, 16, 10, '128K');

  final String slug;
  final String label;
  final int maxConnections;
  final int split;
  final int timeoutSeconds;
  final String minSplitSize;

  const DownloadPerformanceProfile(
    this.slug,
    this.label,
    this.maxConnections,
    this.split,
    this.timeoutSeconds,
    this.minSplitSize,
  );
}

/// Controlador soberano do mecanismo Nix Downloads.
///
/// REGRAS INEGOCIÁVEIS:
/// 1. Utilização do aria2 EXCLUSIVAMENTE para downloads diretos HTTP e HTTPS.
/// 2. Proibido: BitTorrent, DHT, Peer Exchange, Trackers e Seeding através do aria2.
/// 3. Loopback RPC estritamente protegido com token secreto aleatório gerado em tempo de execução.
/// 4. Fallback transparente para o `DartSegmentedDownloader` caso o binário `aria2c` não esteja presente.
/// 5. Pausa real persistente: polling, reinício ou trocas de aba NUNCA retomam downloads pausados pelo usuário.
class Aria2DownloadController extends ChangeNotifier {
  String _downloadDir;
  final int rpcPort;
  int _actualRpcPort = 6800;
  final String? customBinaryPath;
  final bool enableFallback;
  final String? storageFilePath;

  Process? _process;
  String _rpcSecret = '';
  bool _isDaemonRunning = false;
  Timer? _pollingTimer;

  final Map<String, DownloadTask> _tasks = {};
  final DartSegmentedDownloader _fallbackDownloader = DartSegmentedDownloader();
  final Set<String> _fallbackTaskIds = {};
  final Set<String> _removedTaskIds = {};
  final Set<String> _manuallyPausedTaskIds = {};
  DownloadStatusChangeNotifier? onTasksUpdated;

  DownloadPerformanceProfile _performanceProfile = DownloadPerformanceProfile.balanced;
  DownloadPerformanceProfile get performanceProfile => _performanceProfile;

  static const String defaultUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  final List<String> _recentLogs = [];
  List<String> get recentLogs => List.unmodifiable(_recentLogs);

  void _log(String message) {
    final entry = '[${DateTime.now().toIso8601String()}] $message';
    _recentLogs.add(entry);
    if (_recentLogs.length > 50) {
      _recentLogs.removeAt(0);
    }
  }

  void setPerformanceProfile(DownloadPerformanceProfile profile) {
    _performanceProfile = profile;
    _log('Perfil de desempenho alterado para ${profile.label} (${profile.split} fatias)');
    if (_process != null && _rpcSecret.isNotEmpty) {
      unawaited(_rpcCall('aria2.changeGlobalOption', [
        'token:$_rpcSecret',
        {
          'max-connection-per-server': '${profile.maxConnections}',
          'split': '${profile.split}',
          'min-split-size': profile.minSplitSize,
        }
      ]));
    }
    notifyListeners();
  }

  void _notify() {
    onTasksUpdated?.call(tasks);
    notifyListeners();
  }

  Aria2DownloadController({
    String? downloadDir,
    this.rpcPort = 6800,
    this.customBinaryPath,
    this.enableFallback = true,
    this.storageFilePath,
    this.onTasksUpdated,
  }) : _downloadDir = downloadDir ?? defaultDownloadDirectory(),
       _actualRpcPort = rpcPort {
    _loadTasks();
    if (_resolveAria2cBinary() != null) {
      unawaited(startDaemon());
    }
  }

  static String defaultDownloadDirectory() {
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return '$home/Downloads/Nix';
      }
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        return '$userProfile\\Downloads\\Nix';
      }
    } else if (Platform.isAndroid) {
      return '/storage/emulated/0/Download/Nix';
    }
    return '${Directory.systemTemp.path}/nix_downloads';
  }

  String get downloadDir => _downloadDir;

  void setDownloadDir(String path) {
    if (path.trim().isEmpty) return;
    _downloadDir = path.trim();
    final d = Directory(_downloadDir);
    if (!d.existsSync()) {
      try {
        d.createSync(recursive: true);
      } catch (_) {}
    }
  }

  bool get isDaemonRunning => _isDaemonRunning;
  String get rpcSecret => _rpcSecret;
  int get actualRpcPort => _actualRpcPort;
  List<DownloadTask> get tasks => _tasks.values.toList();

  static Future<int> _findAvailablePort(int preferred) async {
    try {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, preferred);
      final p = s.port;
      await s.close();
      return p;
    } catch (_) {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final p = s.port;
      await s.close();
      return p;
    }
  }

  Future<bool>? _startingDaemonFuture;

  /// Inicializa o daemon local aria2c em modo isolado com proteção contra chamadas concorrentes.
  Future<bool> startDaemon() async {
    if (_isDaemonRunning && _process != null) return true;
    if (_startingDaemonFuture != null) return _startingDaemonFuture!;

    _startingDaemonFuture = _startDaemonInternal();
    try {
      return await _startingDaemonFuture!;
    } finally {
      _startingDaemonFuture = null;
    }
  }

  Future<bool> _startDaemonInternal() async {
    if (_isDaemonRunning && _process != null) return true;

    // Localiza o binário aria2c
    final binary = _resolveAria2cBinary();
    if (binary == null) {
      // Binário não encontrado: ativa modo nativo via fallback Dart
      _isDaemonRunning = true;
      return true;
    }

    _actualRpcPort = await _findAvailablePort(rpcPort);
    _rpcSecret = _generateRandomToken(32);

    final dir = Directory(downloadDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Gerenciamento explícito de processo: encerra apenas o daemon anterior pertencente ao Nix
    _terminatePreviousNixDaemon();

    final sessionPath = _resolveNixDataPath('aria2.session');
    final sessionFile = File(sessionPath);
    final hasSession = sessionFile.existsSync() && sessionFile.lengthSync() > 0;

    try {
      final env = <String, String>{
        'LD_LIBRARY_PATH': '/home/gus/.local/lib:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
        ...Platform.environment,
      };

      _process = await Process.start(
        binary,
        [
          '--enable-rpc=true',
          '--rpc-listen-all=false',
          '--rpc-listen-port=$_actualRpcPort',
          '--rpc-secret=$_rpcSecret',
          '--rpc-allow-origin-all=false',
          // DESATIVAÇÃO COMPLETA DE BITTORRENT, DHT, PEERS E MAGNETS
          '--enable-dht=false',
          '--enable-peer-exchange=false',
          '--follow-torrent=false',
          '--follow-metalink=false',
          // EVITA TIMEOUTS EM ROTAS IPV6 INALCANÇÁVEIS (EX: VPN / WIREGUARD) E ASYNC DNS
          '--disable-ipv6=true',
          '--async-dns=false',
          '--user-agent=$defaultUserAgent',
          // ACELERAÇÃO MÁXIMA SUSTENTADA DE MULTI-CONEXÕES E I/O DIRETO
          '--max-connection-per-server=${_performanceProfile.maxConnections}',
          '--split=${_performanceProfile.split}',
          '--min-split-size=${_performanceProfile.minSplitSize}',
          '--optimize-concurrent-downloads=true',
          '--conditional-get=true',
          '--remote-time=true',
          '--auto-file-renaming=false',
          '--allow-overwrite=true',
          '--piece-length=1M',
          '--disk-cache=64M',
          '--enable-mmap=true',
          '--file-allocation=${Platform.isLinux ? "falloc" : "none"}',
          '--stream-piece-selector=default',
          '--uri-selector=adaptive',
          '--lowest-speed-limit=10K',
          '--max-resume-failure-tries=10',
          '--connect-timeout=15',
          '--timeout=20',
          '--max-tries=10',
          '--retry-wait=2',
          '--continue=true',
          '--dir=$downloadDir',
          '--check-integrity=false',
          '--summary-interval=1',
          '--max-overall-download-limit=0',
          '--max-download-limit=0',
          '--save-session=$sessionPath',
          '--save-session-interval=30',
          if (hasSession) '--input-file=$sessionPath',
        ],
        environment: env,
      );

      // Registra PID do daemon isolado do Nix e credenciais RPC seguras (modo 0600)
      try {
        final pidFile = File(_resolveNixDataPath('aria2.pid'));
        pidFile.writeAsStringSync('${_process!.pid}\n');

        final rpcFile = File(_resolveNixDataPath('aria2_rpc.json'));
        rpcFile.writeAsStringSync(jsonEncode({
          'port': _actualRpcPort,
          'pid': _process!.pid,
          'token': _rpcSecret,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        }));
        if (Platform.isLinux || Platform.isMacOS) {
          try {
            Process.runSync('chmod', ['600', rpcFile.path]);
          } catch (_) {}
        }
      } catch (_) {}

      _process!.exitCode.then((code) {
        if (_process != null) {
          _isDaemonRunning = false;
          _process = null;
        }
      });

      // Aguarda ativamente o daemon aria2c estar pronto e respondendo RPC (até 6s com 60 tentativas)
      bool isReady = false;
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_process == null) break;
        final res = await _rpcCall('aria2.getVersion', ['token:$_rpcSecret']);
        if (res != null && res['result'] != null) {
          isReady = true;
          break;
        }
      }

      if (!isReady && _process != null) {
        _log('Daemon aria2c não respondeu ao RPC em 6s. Ativando fallback Dart nativo.');
        try {
          _process!.kill(ProcessSignal.sigterm);
        } catch (_) {}
        _process = null;
        if (enableFallback) {
          _isDaemonRunning = true;
          return true;
        }
        return false;
      }

      _isDaemonRunning = true;
      _log('Daemon aria2c pronto e operando na porta $_actualRpcPort.');
      _startPolling();
      return true;
    } catch (_) {
      if (enableFallback) {
        _isDaemonRunning = true;
        return true;
      }
      return false;
    }
  }

  /// Finaliza o processo do daemon e limpa credenciais temporárias.
  Future<void> stopDaemon() async {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    if (_process != null) {
      _process!.kill(ProcessSignal.sigterm);
      _process = null;
    }
    try {
      final pidFile = File(_resolveNixDataPath('aria2.pid'));
      if (pidFile.existsSync()) pidFile.deleteSync();
    } catch (_) {}
    try {
      final rpcFile = File(_resolveNixDataPath('aria2_rpc.json'));
      if (rpcFile.existsSync()) rpcFile.deleteSync();
    } catch (_) {}
    _isDaemonRunning = false;
  }

  static String _resolveNixDataPath(String fileName) {
    String basePath;
    if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      basePath = home.isNotEmpty ? '$home/.local/share/nix' : Directory.systemTemp.path;
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? '';
      basePath = appData.isNotEmpty ? '$appData\\nix' : Directory.systemTemp.path;
    } else {
      basePath = Directory.systemTemp.path;
    }
    final dir = Directory(basePath);
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {}
    }
    return '$basePath${Platform.pathSeparator}$fileName';
  }

  static void _terminatePreviousNixDaemon() {
    try {
      final pidFile = File(_resolveNixDataPath('aria2.pid'));
      if (pidFile.existsSync()) {
        final content = pidFile.readAsStringSync().trim();
        final pid = int.tryParse(content);
        if (pid != null && pid > 0) {
          if (Platform.isLinux) {
            final cmdlineFile = File('/proc/$pid/cmdline');
            if (cmdlineFile.existsSync()) {
              final cmdline = cmdlineFile.readAsStringSync();
              if (cmdline.contains('aria2') && cmdline.contains('rpc-secret')) {
                Process.killPid(pid, ProcessSignal.sigterm);
                sleep(const Duration(milliseconds: 100));
                if (cmdlineFile.existsSync()) {
                  Process.killPid(pid, ProcessSignal.sigkill);
                }
              }
            }
          } else {
            Process.killPid(pid, ProcessSignal.sigterm);
          }
        }
        try {
          pidFile.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Adiciona uma nova tarefa de download direto HTTP/HTTPS.
  Future<DownloadTask> addDownload({
    required String url,
    String? customFileName,
    String? sha256Expected,
    bool allowClearnet = false,
    String transportProfile = 'tor_socks5',
  }) async {
    final cleanUrl = url.trim();
    _assertValidHttpUrl(cleanUrl);

    final uri = Uri.parse(cleanUrl);
    final fileName = (customFileName != null && customFileName.trim().isNotEmpty)
        ? DartSegmentedDownloader.sanitizeFileName(customFileName)
        : _extractFileName(uri);
    final targetPath = DartSegmentedDownloader.resolveConfinedDestination(
      downloadDir: downloadDir,
      sanitizedFileName: fileName,
    );
    final confinedDir = File(targetPath).parent.path;
    final taskId = 'dl_${DateTime.now().microsecondsSinceEpoch}';

    final resolvedProfile = (allowClearnet && transportProfile == 'tor_socks5')
        ? 'direct_https'
        : transportProfile;

    _removedTaskIds.remove(taskId);
    _manuallyPausedTaskIds.remove(taskId);
    _log('Download adicionado: $fileName (Perfil: $resolvedProfile)');

    var task = DownloadTask(
      id: taskId,
      url: cleanUrl,
      destinationPath: targetPath,
      fileName: fileName,
      sha256Expected: sha256Expected,
      status: DownloadStatus.starting,
      allowClearnet: allowClearnet,
      isUserPaused: false,
      downloadEngine: _process != null ? 'aria2' : 'dart_range',
      transportProfile: resolvedProfile,
      createdAt: DateTime.now(),
    );

    _tasks[taskId] = task;
    _persistTasks();
    _notify();

    if (_process == null) {
      await startDaemon();
    }

    if (_process == null) {
      _fallbackTaskIds.add(taskId);
      unawaited(_runFallbackDownload(task));
      return task;
    }

    try {
      final downloadOptions = <String, String>{
        'dir': confinedDir,
        'out': fileName,
        'split': '${_performanceProfile.split}',
        'max-connection-per-server': '${_performanceProfile.maxConnections}',
        'min-split-size': _performanceProfile.minSplitSize,
        'optimize-concurrent-downloads': 'true',
        'conditional-get': 'true',
        'remote-time': 'true',
        'auto-file-renaming': 'false',
        'allow-overwrite': 'true',
        'piece-length': '1M',
        'disk-cache': '64M',
        'enable-mmap': 'true',
        'file-allocation': Platform.isLinux ? 'falloc' : 'none',
        'max-tries': '10',
        'continue': 'true',
        'user-agent': defaultUserAgent,
      };
      if (task.allowClearnet || resolvedProfile == 'direct_https') {
        downloadOptions['all-proxy'] = '';
      }

      Map<String, dynamic>? rpcRes;
      for (var attempt = 0; attempt < 3; attempt++) {
        rpcRes = await _rpcCall('aria2.addUri', [
          'token:$_rpcSecret',
          [cleanUrl],
          downloadOptions,
        ]);
        if (rpcRes != null && rpcRes['result'] != null) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (rpcRes != null && rpcRes['result'] != null) {
        final ariaGid = rpcRes['result'].toString();
        _removedTaskIds.remove(ariaGid);
        _manuallyPausedTaskIds.remove(ariaGid);

        task = task.copyWith(
          id: ariaGid,
          status: DownloadStatus.downloading,
          downloadEngine: 'aria2',
        );
        _tasks.remove(taskId);
        _tasks[ariaGid] = task;
        _persistTasks();
        _notify();
        return task;
      } else {
        throw Exception('Resposta inesperada do RPC aria2: $rpcRes');
      }
    } catch (e) {
      _log('Falha ao submeter tarefa ao aria2 RPC: $e. Ativando fallback Dart...');
      _fallbackTaskIds.add(taskId);
      task = task.copyWith(downloadEngine: 'dart_range');
      _tasks[taskId] = task;
      _persistTasks();
      unawaited(_runFallbackDownload(task));
      return task;
    }
  }

  /// Retenta um download permitindo conexão fora da rede Tor (Clearnet).
  Future<void> retryDownloadWithClearnet(String taskId) async {
    final stored = _tasks[taskId];
    if (stored == null) return;
    final task = _withSafeDestination(stored);

    _manuallyPausedTaskIds.remove(taskId);
    final updated = task.copyWith(
      status: DownloadStatus.starting,
      allowClearnet: true,
      transportProfile: 'direct_https',
      errorMessage: null,
      isUserPaused: false,
    );
    _tasks[taskId] = updated;
    _notify();

    if (_process == null) {
      await startDaemon();
    }

    if (_process != null) {
      try {
        final downloadOptions = <String, String>{
          'dir': File(updated.destinationPath).parent.path,
          'out': updated.fileName,
          'split': '${_performanceProfile.split}',
          'max-connection-per-server': '${_performanceProfile.maxConnections}',
          'min-split-size': _performanceProfile.minSplitSize,
          'continue': 'true',
          'all-proxy': '',
          'user-agent': defaultUserAgent,
        };
        final rpcRes = await _rpcCall('aria2.addUri', [
          'token:$_rpcSecret',
          [updated.url],
          downloadOptions,
        ]);
        if (rpcRes != null && rpcRes['result'] != null) {
          final ariaGid = rpcRes['result'].toString();
          _removedTaskIds.remove(ariaGid);
          _manuallyPausedTaskIds.remove(ariaGid);

          _tasks.remove(taskId);
          _tasks[ariaGid] = updated.copyWith(
            id: ariaGid,
            status: DownloadStatus.downloading,
            downloadEngine: 'aria2',
          );
          _persistTasks();
          _notify();
          return;
        }
      } catch (_) {}
    }

    _fallbackTaskIds.add(taskId);
    unawaited(_runFallbackDownload(updated));
  }

  /// Pausa real e definitiva de uma transferência (máquina de estados: DOWNLOADING -> PAUSING -> PAUSED).
  Future<void> pauseDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || task.status.isTerminal || task.status.isPausedOrPausing) return;
    _log('Pausa solicitada para a tarefa: $taskId');

    // 1. Registra a intenção explícita do usuário
    _manuallyPausedTaskIds.add(taskId);

    // 2. Transiciona para PAUSING
    _tasks[taskId] = task.copyWith(
      status: DownloadStatus.pausing,
      isUserPaused: true,
      speedBytesPerSec: 0,
      clearEta: true,
    );
    _notify();

    // 3. Executa a pausa no motor correto
    if (_fallbackTaskIds.contains(taskId) || task.id.startsWith('dl_')) {
      _fallbackDownloader.pause(taskId);
      _tasks[taskId] = _tasks[taskId]?.copyWith(
        status: DownloadStatus.paused,
        isUserPaused: true,
        speedBytesPerSec: 0,
        clearEta: true,
      ) ?? task;
      _persistTasks();
      _notify();
      return;
    }

    if (_process != null) {
      try {
        final pauseRes = await _rpcCall('aria2.pause', ['token:$_rpcSecret', taskId]);
        if (pauseRes == null || pauseRes['error'] != null) {
          // Se aria2.pause retornar erro de que não está ativo ou demorar, avalia forcePause
          await _rpcCall('aria2.forcePause', ['token:$_rpcSecret', taskId]);
        }
      } catch (_) {
        try {
          await _rpcCall('aria2.forcePause', ['token:$_rpcSecret', taskId]);
        } catch (_) {}
      }

      // Confirmação do estado no daemon
      try {
        final statusRes = await _rpcCall('aria2.tellStatus', ['token:$_rpcSecret', taskId]);
        final s = statusRes?['result']?['status']?.toString();
        if (s == 'active') {
          // Ainda não pausou: força imediatamente
          await _rpcCall('aria2.forcePause', ['token:$_rpcSecret', taskId]);
        }
      } catch (_) {}
    }

    // 4. Confirma estado PAUSED e persiste
    _tasks[taskId] = (_tasks[taskId] ?? task).copyWith(
      status: DownloadStatus.paused,
      isUserPaused: true,
      speedBytesPerSec: 0,
      clearEta: true,
    );
    _persistTasks();
    _notify();
  }

  /// Retomada explícita de uma transferência pelo usuário (PAUSED -> RESUMING -> DOWNLOADING).
  Future<void> resumeDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || (!task.status.isPausedOrPausing && task.status != DownloadStatus.failed)) {
      return;
    }
    _log('Retomada solicitada para a tarefa: $taskId');

    final sanitizedTask = _withSafeDestination(task);
    final safeFileName = sanitizedTask.fileName;
    final confinedDir = File(sanitizedTask.destinationPath).parent.path;

    // 1. Remove a flag de pausa manual
    _manuallyPausedTaskIds.remove(taskId);

    // 2. Transiciona para RESUMING
    _tasks[taskId] = sanitizedTask.copyWith(
      status: DownloadStatus.resuming,
      isUserPaused: false,
      errorMessage: null,
    );
    _notify();

    // 3. Garante que o daemon nativo aria2c esteja ativo
    if ((_process == null || !_isDaemonRunning) && _resolveAria2cBinary() != null) {
      await startDaemon();
    }

    // 4. Se o daemon aria2c estiver disponível, PRIORIZA SEMPRE O MOTOR ARIA2 (MÁXIMA VELOCIDADE)
    if (_process != null) {
      _fallbackDownloader.pause(taskId);
      _fallbackTaskIds.remove(taskId);

      // Se já era um GID nativo do aria2c, tenta retomar via RPC
      if (!taskId.startsWith('dl_')) {
        try {
          await _rpcCall('aria2.changeOption', [
            'token:$_rpcSecret',
            taskId,
            {
              'user-agent': defaultUserAgent,
              'max-connection-per-server': '${_performanceProfile.maxConnections}',
              'split': '${_performanceProfile.split}',
              'min-split-size': _performanceProfile.minSplitSize,
            }
          ]);
        } catch (_) {}

        final res = await _rpcCall('aria2.unpause', ['token:$_rpcSecret', taskId]);
        if (res != null && res['result'] != null) {
          _tasks[taskId] = sanitizedTask.copyWith(
            status: DownloadStatus.downloading,
            isUserPaused: false,
            downloadEngine: 'aria2',
          );
          _persistTasks();
          _notify();
          return;
        }
      }

      // Se aria2c não encontrou o GID ou se a tarefa estava no fallback Dart,
      // MIGRA E RETOMA NO ARIA2C com continue: true aproveitando os dados em disco
      try {
        final downloadOptions = <String, dynamic>{
          'dir': confinedDir,
          'out': safeFileName,
          'continue': 'true',
          'max-connection-per-server': '${_performanceProfile.maxConnections}',
          'split': '${_performanceProfile.split}',
          'min-split-size': _performanceProfile.minSplitSize,
          'optimize-concurrent-downloads': 'true',
          'conditional-get': 'true',
          'remote-time': 'true',
          'auto-file-renaming': 'false',
          'allow-overwrite': 'true',
          'piece-length': '1M',
          'disk-cache': '64M',
          'enable-mmap': 'true',
          'file-allocation': Platform.isLinux ? 'falloc' : 'none',
          'max-tries': '10',
          'user-agent': defaultUserAgent,
        };
        if (task.allowClearnet || task.transportProfile == 'direct_https') {
          downloadOptions['all-proxy'] = '';
        }

        final rpcRes = await _rpcCall('aria2.addUri', [
          'token:$_rpcSecret',
          [sanitizedTask.url],
          downloadOptions,
        ]);
        if (rpcRes != null && rpcRes['result'] != null) {
          final newGid = rpcRes['result'].toString();
          _tasks.remove(taskId);
          final updated = sanitizedTask.copyWith(
            id: newGid,
            status: DownloadStatus.downloading,
            isUserPaused: false,
            downloadEngine: 'aria2',
          );
          _tasks[newGid] = updated;
          _persistTasks();
          _notify();
          _log('Tarefa $taskId migrada com sucesso para aria2c nativo (GID: $newGid)');
          return;
        } else {
          _log('aria2.addUri retornou: $rpcRes');
        }
      } catch (err) {
        _log('Erro ao retomar no aria2c: $err. Avaliando fallback...');
      }
    }

    // 5. Fallback Dart SOMENTE se aria2c não estiver presente ou falhar
    if (enableFallback) {
      _fallbackTaskIds.add(taskId);
      _tasks[taskId] = sanitizedTask.copyWith(
        status: DownloadStatus.downloading,
        isUserPaused: false,
        downloadEngine: 'dart_range',
      );
      _persistTasks();
      _notify();
      unawaited(_runFallbackDownload(sanitizedTask));
    }
  }

  Future<void> cancelDownload(String taskId) async {
    await removeDownload(taskId, deleteFile: false);
  }

  /// Remove permanentemente uma tarefa da fila e da memória,
  /// encerrando o processo de download no aria2 ou no fallback Dart.
  Future<void> removeDownload(String taskId, {bool deleteFile = false}) async {
    _log('Removendo tarefa da fila: $taskId (deleteFile=$deleteFile)');
    _removedTaskIds.add(taskId);
    _manuallyPausedTaskIds.remove(taskId);
    final task = _tasks[taskId];
    if (task != null && task.id != taskId) {
      _removedTaskIds.add(task.id);
      _manuallyPausedTaskIds.remove(task.id);
    }

    if (_fallbackTaskIds.contains(taskId)) {
      _fallbackDownloader.cancel(taskId);
      _fallbackTaskIds.remove(taskId);
    }

    if (_process != null) {
      try {
        await _rpcCall('aria2.forceRemove', ['token:$_rpcSecret', taskId]);
      } catch (_) {}
      try {
        await _rpcCall('aria2.remove', ['token:$_rpcSecret', taskId]);
      } catch (_) {}
      try {
        await _rpcCall('aria2.removeDownloadResult', ['token:$_rpcSecret', taskId]);
      } catch (_) {}
    }

    if (task != null) {
      try {
        if (deleteFile) {
          final f = File(task.destinationPath);
          if (await f.exists()) await f.delete();
        }
        // Sempre limpa arquivos de controle e partes temporárias ao remover
        final part = File('${task.destinationPath}.part');
        if (await part.exists()) await part.delete();
        final aria2File = File('${task.destinationPath}.aria2');
        if (await aria2File.exists()) await aria2File.delete();
        for (var i = 0; i < 32; i++) {
          final seg = File('${task.destinationPath}.part$i');
          if (await seg.exists()) await seg.delete();
        }
      } catch (_) {}
    }

    _tasks.remove(taskId);
    _persistTasks();
    _notify();
  }

  void _loadTasks() {
    try {
      final file = _resolveStorageFile();
      if (file == null || !file.existsSync()) return;
      final content = file.readAsStringSync();
      if (content.trim().isEmpty) return;
      final decoded = jsonDecode(content);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final t = DownloadTask.fromMap(item);
            // Nenhuma tarefa que estava pausada pode ser retomada automaticamente
            if (t.isUserPaused || t.status.isPausedOrPausing) {
              _manuallyPausedTaskIds.add(t.id);
              _tasks[t.id] = t.copyWith(
                status: DownloadStatus.paused,
                isUserPaused: true,
                speedBytesPerSec: 0,
                clearEta: true,
              );
            } else if (t.status == DownloadStatus.downloading || t.status == DownloadStatus.starting) {
              // Se o app foi encerrado durante transferência, recupera como pausado preservando os dados
              _tasks[t.id] = t.copyWith(
                status: DownloadStatus.paused,
                speedBytesPerSec: 0,
                clearEta: true,
              );
            } else {
              _tasks[t.id] = t;
            }
          }
        }
      }
    } catch (_) {}
  }

  void _persistTasks() {
    try {
      final file = _resolveStorageFile();
      if (file == null) return;
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      final list = _tasks.values.map((t) => t.toMap()).toList();
      file.writeAsStringSync(jsonEncode(list));
    } catch (_) {}
  }

  File? _resolveStorageFile() {
    if (storageFilePath != null && storageFilePath!.isNotEmpty) {
      return File(storageFilePath!);
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return File('$home/.local/share/nix/downloads_tasks.json');
    }
    return null;
  }

  Future<void> _runFallbackDownload(DownloadTask task) async {
    DateTime lastPersist = DateTime.now();
    await _fallbackDownloader.download(
      task: task,
      splitCount: _performanceProfile.split,
      onProgress: (updated) {
        // Bloqueia ressurreição de tarefas removidas
        if (_removedTaskIds.contains(updated.id) ||
            _removedTaskIds.contains(task.id) ||
            !_tasks.containsKey(updated.id)) {
          return;
        }

        // Se o usuário pausou manualmente, NUNCA permite que o callback reverta para downloading
        if (_manuallyPausedTaskIds.contains(updated.id) &&
            updated.status == DownloadStatus.downloading) {
          return;
        }

        _tasks[updated.id] = updated;
        final now = DateTime.now();
        if (now.difference(lastPersist).inSeconds >= 4 ||
            updated.status != DownloadStatus.downloading) {
          lastPersist = now;
          _persistTasks();
        }
        _notify();
      },
    );
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_process == null || !_isDaemonRunning) return;
      await _syncAriaTasks();
    });
  }

  Future<void> _syncAriaTasks() async {
    try {
      final active = await _rpcCall('aria2.tellActive', ['token:$_rpcSecret']);
      final waiting = await _rpcCall('aria2.tellWaiting', ['token:$_rpcSecret', 0, 50]);
      final stopped = await _rpcCall('aria2.tellStopped', ['token:$_rpcSecret', 0, 50]);

      final allResults = <dynamic>[
        if (active?['result'] is List) ...(active!['result'] as List),
        if (waiting?['result'] is List) ...(waiting!['result'] as List),
        if (stopped?['result'] is List) ...(stopped!['result'] as List),
      ];

      for (final item in allResults) {
        if (item is! Map) continue;
        final gid = item['gid']?.toString();
        if (gid == null) continue;

        if (_removedTaskIds.contains(gid)) {
          try {
            await _rpcCall('aria2.removeDownloadResult', ['token:$_rpcSecret', gid]);
          } catch (_) {}
          continue;
        }

        var existing = _tasks[gid];
        if (existing == null) {
          continue;
        }

        final statusStr = item['status']?.toString();
        final totalLength = int.tryParse(item['totalLength']?.toString() ?? '') ?? 0;
        final completedLength = int.tryParse(item['completedLength']?.toString() ?? '') ?? 0;
        final downloadSpeed = int.tryParse(item['downloadSpeed']?.toString() ?? '') ?? 0;
        final realConnections = int.tryParse(item['connections']?.toString() ?? '');

        // Se o usuário pausou a tarefa manualmente, o polling JAMAIS pode sobrescrever para downloading
        if (_manuallyPausedTaskIds.contains(gid) || existing.isUserPaused) {
          if (statusStr == 'active') {
            try {
              await _rpcCall('aria2.pause', ['token:$_rpcSecret', gid]);
            } catch (_) {}
          }
          _tasks[gid] = existing.copyWith(
            status: DownloadStatus.paused,
            isUserPaused: true,
            downloadedBytes: completedLength,
            fileSizeBytes: totalLength > 0 ? totalLength : existing.fileSizeBytes,
            speedBytesPerSec: 0,
            clearEta: true,
          );
          continue;
        }

        DownloadStatus status;
        switch (statusStr) {
          case 'active':
            if (totalLength > 0 && completedLength >= totalLength) {
              status = DownloadStatus.finalizing;
            } else {
              status = DownloadStatus.downloading;
            }
            break;
          case 'waiting':
            status = DownloadStatus.queued;
            break;
          case 'paused':
            status = DownloadStatus.paused;
            break;
          case 'complete':
            status = DownloadStatus.completed;
            break;
          case 'error':
            status = DownloadStatus.failed;
            break;
          case 'removed':
            status = DownloadStatus.cancelled;
            break;
          default:
            status = DownloadStatus.downloading;
            break;
        }

        // Rastreamento preciso do tempo em transferência ativa
        var activeSec = existing.activeTransferSeconds;
        if (status == DownloadStatus.downloading && downloadSpeed > 0) {
          activeSec += 1;
        }

        // Suavização EMA para evitar oscilações instantâneas para 0 KB/s entre bursts de TCP/Tor
        final prevSpeed = existing.speedBytesPerSec.toDouble();
        double smoothedSpeed;
        if (prevSpeed == 0) {
          smoothedSpeed = downloadSpeed.toDouble();
        } else if (downloadSpeed > 0) {
          smoothedSpeed = (0.35 * downloadSpeed) + (0.65 * prevSpeed);
        } else {
          smoothedSpeed = prevSpeed * 0.72;
          if (smoothedSpeed < 512) smoothedSpeed = 0;
        }
        final finalSpeed = status == DownloadStatus.downloading ? smoothedSpeed.round() : 0;

        // Velocidade média calculada EXCLUSIVAMENTE sobre o tempo de transferência ativa
        final avgSpeed = (activeSec > 0 && completedLength > 0)
            ? (completedLength / activeSec)
            : finalSpeed.toDouble();

        // Pico real observado
        final peakSpeed = max(existing.peakSpeedBytesPerSec, downloadSpeed);

        // Amostras recentes para velocidade sustentada (janela dos últimos 20 segundos)
        final samples = List<int>.from(existing.recentSpeedSamples);
        if (status == DownloadStatus.downloading && downloadSpeed > 0) {
          samples.add(downloadSpeed);
          if (samples.length > 20) samples.removeAt(0);
        }

        final remaining = totalLength - completedLength;
        final eta = (status == DownloadStatus.downloading && finalSpeed > 0 && remaining > 0)
            ? (remaining / finalSpeed).ceil()
            : null;

        final realOrProfileSegments = (realConnections != null && realConnections > 0)
            ? realConnections
            : (status == DownloadStatus.downloading ? _performanceProfile.split : 0);

        _tasks[gid] = existing.copyWith(
          fileSizeBytes: totalLength > 0 ? totalLength : existing.fileSizeBytes,
          downloadedBytes: completedLength,
          speedBytesPerSec: finalSpeed,
          averageSpeedBytesPerSec: avgSpeed,
          peakSpeedBytesPerSec: peakSpeed,
          activeTransferSeconds: activeSec,
          recentSpeedSamples: samples,
          actualConnections: realConnections,
          activeSegments: realOrProfileSegments,
          etaSeconds: eta,
          clearEta: (status != DownloadStatus.downloading || finalSpeed <= 0),
          status: status,
          downloadEngine: 'aria2',
          completedAt: status == DownloadStatus.completed ? (existing.completedAt ?? DateTime.now()) : null,
        );
      }
      _persistTasks();
      _notify();
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _rpcCall(String method, List<dynamic> params) async {
    // Bloqueia tentativas de invocar métodos de torrent no aria2
    if (method.toLowerCase().contains('torrent') || method.toLowerCase().contains('metalink')) {
      throw UnsupportedError('Métodos BitTorrent/Metalink foram desabilitados permanentemente.');
    }

    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 800);
    try {
      final req = await client.postUrl(Uri.parse('http://127.0.0.1:$_actualRpcPort/jsonrpc'));
      final payload = jsonEncode({
        'jsonrpc': '2.0',
        'id': 'nix_${DateTime.now().microsecondsSinceEpoch}',
        'method': method,
        'params': params,
      });
      final bytes = utf8.encode(payload);
      req.headers.contentType = ContentType.json;
      req.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close().timeout(const Duration(milliseconds: 1200));
      final body = await utf8.decodeStream(res).timeout(const Duration(milliseconds: 1200));
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  String? _resolveAria2cBinary() {
    if (customBinaryPath != null && File(customBinaryPath!).existsSync()) {
      return customBinaryPath;
    }
    final home = Platform.environment['HOME'];
    final candidates = [
      if (home != null) '$home/.local/bin/aria2c-wrapper',
      if (home != null) '$home/.local/bin/aria2c-bin',
      if (home != null) '$home/.local/bin/aria2c',
      '/home/gus/.local/bin/aria2c-wrapper',
      '/home/gus/.local/bin/aria2c-bin',
      '/home/gus/.local/bin/aria2c',
      '/usr/bin/aria2c',
      '/usr/local/bin/aria2c',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  static void _assertValidHttpUrl(String url) {
    final lower = url.trim().toLowerCase();
    if (lower.startsWith('magnet:') || lower.contains('.torrent') || lower.startsWith('dht://')) {
      throw ArgumentError(
        'Operação Proibida: O Nix Downloads utiliza aria2 exclusivamente para downloads diretos HTTP e HTTPS. '
        'Qualquer integração com BitTorrent, DHT ou Trackers é terminantemente vedada.',
      );
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError('Apenas conexões diretas HTTP e HTTPS são permitidas no Nix Downloads.');
    }
  }

  /// Mantém o diretório já gravado na tarefa; só recalcula o destino no diretório
  /// atual quando o nome ou o caminho persistido não forem seguros.
  DownloadTask _withSafeDestination(DownloadTask task) {
    final safeName = DartSegmentedDownloader.sanitizeFileName(task.fileName);
    final segments = task.destinationPath.split(RegExp(r'[/\\]'));
    if (safeName == task.fileName &&
        segments.last == safeName &&
        !segments.contains('.') &&
        !segments.contains('..')) {
      return task;
    }
    return task.copyWith(
      fileName: safeName,
      destinationPath: DartSegmentedDownloader.resolveConfinedDestination(
        downloadDir: _downloadDir,
        sanitizedFileName: safeName,
      ),
    );
  }

  static String _extractFileName(Uri uri) {
    if (uri.pathSegments.isNotEmpty && uri.pathSegments.last.trim().isNotEmpty) {
      // uri.pathSegments já retorna segmentos decodificados; evita dupla decodificação.
      return DartSegmentedDownloader.sanitizeFileName(uri.pathSegments.last);
    }
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

  static String _generateRandomToken(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}
