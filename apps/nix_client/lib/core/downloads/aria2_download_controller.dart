import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'dart_segmented_downloader.dart';
import 'models/download_task.dart';

typedef DownloadStatusChangeNotifier = void Function(List<DownloadTask> tasks);

/// Controlador soberano do mecanismo Nix Downloads.
///
/// REGRAS INEGOCIÁVEIS:
/// 1. Utilização do aria2 EXCLUSIVAMENTE para downloads diretos HTTP e HTTPS.
/// 2. Proibido: BitTorrent, DHT, Peer Exchange, Trackers e Seeding através do aria2.
/// 3. Loopback RPC estritamente protegido com token secreto aleatório gerado em tempo de execução.
/// 4. Fallback transparente para o `DartSegmentedDownloader` caso o binário `aria2c` não esteja presente.
class Aria2DownloadController extends ChangeNotifier {
  String _downloadDir;
  final int rpcPort;
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
  DownloadStatusChangeNotifier? onTasksUpdated;

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
  }) : _downloadDir = downloadDir ?? defaultDownloadDirectory() {
    _loadTasks();
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
  List<DownloadTask> get tasks => _tasks.values.toList();

  /// Inicializa o daemon local aria2c em modo isolado.
  Future<bool> startDaemon() async {
    if (_isDaemonRunning) return true;

    // Localiza o binário aria2c
    final binary = _resolveAria2cBinary();
    if (binary == null) {
      // Binário não encontrado: ativa modo de operação nativo via fallback Dart
      _isDaemonRunning = true;
      return true;
    }

    _rpcSecret = _generateRandomToken(32);

    final dir = Directory(downloadDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    try {
      _process = await Process.start(binary, [
        '--enable-rpc=true',
        '--rpc-listen-all=false',
        '--rpc-listen-port=$rpcPort',
        '--rpc-secret=$_rpcSecret',
        '--rpc-allow-origin-all=false',
        // DESATIVAÇÃO COMPLETA DE BITTORRENT, DHT, PEERS E MAGNETS
        '--enable-dht=false',
        '--enable-peer-exchange=false',
        '--follow-torrent=false',
        '--follow-metalink=false',
        '--max-connection-per-server=4',
        '--split=4',
        '--min-split-size=1M',
        '--continue=true',
        '--dir=$downloadDir',
        '--check-integrity=true',
        '--summary-interval=1',
      ]);

      _isDaemonRunning = true;
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

  /// Finaliza o processo do daemon.
  Future<void> stopDaemon() async {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    if (_process != null) {
      _process!.kill(ProcessSignal.sigterm);
      _process = null;
    }
    _isDaemonRunning = false;
  }

  /// Adiciona uma nova tarefa de download direto HTTP/HTTPS.
  /// Lança [ArgumentError] se a URL for magnet ou protocolo não permitido.
  Future<DownloadTask> addDownload({
    required String url,
    String? customFileName,
    String? sha256Expected,
    bool allowClearnet = false,
  }) async {
    final cleanUrl = url.trim();
    _assertValidHttpUrl(cleanUrl);

    final uri = Uri.parse(cleanUrl);
    final fileName = customFileName ?? _extractFileName(uri);
    final targetPath = '$downloadDir/$fileName';
    final taskId = 'dl_${DateTime.now().microsecondsSinceEpoch}';

    var task = DownloadTask(
      id: taskId,
      url: cleanUrl,
      destinationPath: targetPath,
      fileName: fileName,
      sha256Expected: sha256Expected,
      status: DownloadStatus.starting,
      allowClearnet: allowClearnet,
      createdAt: DateTime.now(),
    );

    _tasks[taskId] = task;
    _persistTasks();
    _notify();

    // Se o aria2c não estiver executando processo nativo, utiliza o fallback Dart
    if (_process == null) {
      _fallbackTaskIds.add(taskId);
      unawaited(_runFallbackDownload(task));
      return task;
    }

    try {
      final downloadOptions = <String, String>{
        'dir': downloadDir,
        'out': fileName,
        'split': '4',
        'max-connection-per-server': '4',
      };
      if (task.allowClearnet) {
        downloadOptions['all-proxy'] = '';
      }

      // Submete a URL via JSON-RPC protegido
      final rpcRes = await _rpcCall('aria2.addUri', [
        'token:$_rpcSecret',
        [cleanUrl],
        downloadOptions,
      ]);

      if (rpcRes != null && rpcRes['result'] != null) {
        final ariaGid = rpcRes['result'].toString();
        task = task.copyWith(id: ariaGid, status: DownloadStatus.downloading);
        _tasks.remove(taskId);
        _tasks[ariaGid] = task;
        _notify();
        return task;
      } else {
        throw Exception('Resposta inesperada do RPC aria2: $rpcRes');
      }
    } catch (_) {
      // Fallback em caso de erro no RPC
      _fallbackTaskIds.add(taskId);
      unawaited(_runFallbackDownload(task));
      return task;
    }
  }

  /// Retenta um download que falhou permitindo conexão fora da rede Tor (Clearnet).
  Future<void> retryDownloadWithClearnet(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;
    final updated = task.copyWith(
      status: DownloadStatus.starting,
      allowClearnet: true,
      errorMessage: null,
    );
    _tasks[taskId] = updated;
    _notify();
    _fallbackTaskIds.add(taskId);
    unawaited(_runFallbackDownload(updated));
  }

  Future<void> pauseDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;

    if (_fallbackTaskIds.contains(taskId)) {
      _fallbackDownloader.pause(taskId);
    } else if (_process != null) {
      try {
        await _rpcCall('aria2.pause', ['token:$_rpcSecret', taskId]);
      } catch (_) {}
    }

    _tasks[taskId] = task.copyWith(
      status: DownloadStatus.paused,
      speedBytesPerSec: 0,
    );
    _persistTasks();
    _notify();
  }

  Future<void> resumeDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;

    if (_fallbackTaskIds.contains(taskId)) {
      _tasks[taskId] = task.copyWith(status: DownloadStatus.downloading);
      _notify();
      unawaited(_runFallbackDownload(task));
      return;
    }

    if (_process != null) {
      final res = await _rpcCall('aria2.unpause', ['token:$_rpcSecret', taskId]);
      if (res != null && res['result'] != null) {
        _tasks[taskId] = task.copyWith(status: DownloadStatus.downloading);
        _persistTasks();
        _notify();
        return;
      }

      // Se aria2c não encontrou o GID (ex: app reiniciado ou nova sessão do daemon),
      // readiciona ao aria2c com opção continue: true para retomar o arquivo local
      try {
        final downloadOptions = <String, dynamic>{
          'dir': _downloadDir,
          'continue': 'true',
          'max-connection-per-server': '4',
          'split': '4',
        };
        if (task.fileName.isNotEmpty) {
          downloadOptions['out'] = task.fileName;
        }
        if (task.allowClearnet) {
          downloadOptions['all-proxy'] = '';
        }

        final rpcRes = await _rpcCall('aria2.addUri', [
          'token:$_rpcSecret',
          [task.url],
          downloadOptions,
        ]);
        if (rpcRes != null && rpcRes['result'] != null) {
          final newGid = rpcRes['result'].toString();
          _tasks.remove(taskId);
          final updated = task.copyWith(id: newGid, status: DownloadStatus.downloading);
          _tasks[newGid] = updated;
          _persistTasks();
          _notify();
          return;
        }
      } catch (_) {}
    }

    // Fallback puro Dart caso aria2 não consiga
    _fallbackTaskIds.add(taskId);
    _tasks[taskId] = task.copyWith(status: DownloadStatus.downloading);
    _notify();
    unawaited(_runFallbackDownload(task));
  }

  Future<void> cancelDownload(String taskId) async {
    await removeDownload(taskId, deleteFile: false);
  }

  /// Remove permanentemente uma tarefa da fila e da memória,
  /// encerrando o processo de download no aria2 ou no fallback Dart.
  Future<void> removeDownload(String taskId, {bool deleteFile = false}) async {
    final task = _tasks[taskId];
    if (_fallbackTaskIds.contains(taskId)) {
      _fallbackDownloader.cancel(taskId);
      _fallbackTaskIds.remove(taskId);
    }

    if (_process != null) {
      try {
        await _rpcCall('aria2.remove', ['token:$_rpcSecret', taskId]);
      } catch (_) {}
      try {
        await _rpcCall('aria2.removeDownloadResult', ['token:$_rpcSecret', taskId]);
      } catch (_) {}
    }

    if (deleteFile && task != null) {
      try {
        final f = File(task.destinationPath);
        if (await f.exists()) await f.delete();
        final part = File('${task.destinationPath}.part');
        if (await part.exists()) await part.delete();
        final aria2File = File('${task.destinationPath}.aria2');
        if (await aria2File.exists()) await aria2File.delete();
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
            // Se o app foi encerrado durante transferência, recupera como pausado para permitir retomar com 1 clique
            final restored = (t.status == DownloadStatus.downloading || t.status == DownloadStatus.starting)
                ? t.copyWith(status: DownloadStatus.paused, speedBytesPerSec: 0)
                : t;
            _tasks[t.id] = restored;
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
    await _fallbackDownloader.download(
      task: task,
      splitCount: 4,
      onProgress: (updated) {
        _tasks[updated.id] = updated;
        _persistTasks();
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

        final statusStr = item['status']?.toString();
        final totalLength = int.tryParse(item['totalLength']?.toString() ?? '') ?? 0;
        final completedLength = int.tryParse(item['completedLength']?.toString() ?? '') ?? 0;
        final downloadSpeed = int.tryParse(item['downloadSpeed']?.toString() ?? '') ?? 0;

        DownloadStatus status;
        switch (statusStr) {
          case 'active':
            status = DownloadStatus.downloading;
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

        final remaining = totalLength - completedLength;
        final eta = (status == DownloadStatus.downloading && downloadSpeed > 0 && remaining > 0)
            ? (remaining / downloadSpeed).ceil()
            : null;

        var existing = _tasks[gid];
        if (existing != null) {
          _tasks[gid] = existing.copyWith(
            fileSizeBytes: totalLength > 0 ? totalLength : existing.fileSizeBytes,
            downloadedBytes: completedLength,
            speedBytesPerSec: downloadSpeed,
            etaSeconds: eta,
            status: status,
            completedAt: status == DownloadStatus.completed ? (existing.completedAt ?? DateTime.now()) : null,
          );
        }
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

    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('http://127.0.0.1:$rpcPort/jsonrpc'));
      req.headers.contentType = ContentType.json;
      final payload = jsonEncode({
        'jsonrpc': '2.0',
        'id': 'nix_${DateTime.now().microsecondsSinceEpoch}',
        'method': method,
        'params': params,
      });
      req.write(payload);
      final res = await req.close();
      final body = await utf8.decodeStream(res);
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
    // Verifica caminhos comuns no Linux e PATH
    final home = Platform.environment['HOME'];
    final candidates = [
      if (home != null) '$home/.local/bin/aria2c',
      '/home/gus/.local/bin/aria2c',
      '/usr/bin/aria2c',
      '/usr/local/bin/aria2c',
      'aria2c',
    ];
    for (final c in candidates) {
      try {
        final res = Process.runSync(c, ['--version']);
        if (res.exitCode == 0) return c;
      } catch (_) {}
    }
    return null;
  }

  static void _assertValidHttpUrl(String url) {
    if (url.startsWith('magnet:?') || url.startsWith('dht:') || url.startsWith('torrent:')) {
      throw ArgumentError(
        'O Nix Downloads utiliza aria2 exclusivamente para downloads diretos HTTP e HTTPS.\n'
        'Transferências BitTorrent e magnets via Tor foram desabilitadas para proteger a privacidade e evitar vazamento de IP.',
      );
    }
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError('Apenas URLs com protocolo HTTP ou HTTPS são suportadas.');
    }
  }

  static String _extractFileName(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty) {
      return segments.last;
    }
    return 'download_${DateTime.now().millisecondsSinceEpoch}.bin';
  }

  static String _generateRandomToken(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
