/// Status operacional de uma tarefa de download direto HTTP/HTTPS.
enum DownloadStatus {
  queued('queued', 'Na fila'),
  starting('starting', 'Iniciando'),
  downloading('downloading', 'Baixando'),
  paused('paused', 'Pausado'),
  completed('completed', 'Concluído'),
  failed('failed', 'Falhou'),
  cancelled('cancelled', 'Cancelado');

  final String slug;
  final String label;
  const DownloadStatus(this.slug, this.label);
}

/// Representa uma tarefa de download direto HTTP/HTTPS gerenciada pelo Nix Downloads (aria2/Range).
class DownloadTask {
  final String id;
  final String url;
  final String destinationPath;
  final String fileName;
  final int? fileSizeBytes;
  final int downloadedBytes;
  final int speedBytesPerSec;
  final int? etaSeconds;
  final DownloadStatus status;
  final String? errorMessage;
  final String? sha256Expected;
  final String? sha256Actual;
  final bool isRangeSupported;
  final int splitCount;
  final bool allowClearnet;
  final DateTime createdAt;
  final DateTime? completedAt;

  const DownloadTask({
    required this.id,
    required this.url,
    required this.destinationPath,
    required this.fileName,
    this.fileSizeBytes,
    this.downloadedBytes = 0,
    this.speedBytesPerSec = 0,
    this.etaSeconds,
    this.status = DownloadStatus.queued,
    this.errorMessage,
    this.sha256Expected,
    this.sha256Actual,
    this.isRangeSupported = false,
    this.splitCount = 1,
    this.allowClearnet = false,
    required this.createdAt,
    this.completedAt,
  });

  /// Progresso percentual entre 0.0 e 1.0.
  double get progressFraction {
    if (fileSizeBytes == null || fileSizeBytes! <= 0) return 0.0;
    return (downloadedBytes / fileSizeBytes!).clamp(0.0, 1.0);
  }

  /// Progresso de 0 a 100%.
  int get progressPercent => (progressFraction * 100).toInt();

  /// Velocidade formatada em KB/s ou MB/s.
  String get formattedSpeed {
    if (status != DownloadStatus.downloading || speedBytesPerSec <= 0) return '0 KB/s';
    if (speedBytesPerSec >= 1024 * 1024) {
      return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    }
    return '${(speedBytesPerSec / 1024).toStringAsFixed(0)} KB/s';
  }

  /// Tamanho baixado / total formatado.
  String get formattedProgressBytes {
    final downStr = _formatBytes(downloadedBytes);
    if (fileSizeBytes != null && fileSizeBytes! > 0) {
      return '$downStr / ${_formatBytes(fileSizeBytes!)}';
    }
    return downStr;
  }

  /// Estimativa de tempo restante.
  String get formattedEta {
    if (status != DownloadStatus.downloading || speedBytesPerSec <= 0 || etaSeconds == null || etaSeconds! <= 0) {
      return '--:--';
    }
    final sec = etaSeconds!;
    if (sec >= 3600) {
      final h = sec ~/ 3600;
      final m = (sec % 3600) ~/ 60;
      return '${h}h ${m}m';
    }
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Indica se o arquivo possui extensão potencialmente executável.
  bool get isExecutable {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.exe') ||
        lower.endsWith('.sh') ||
        lower.endsWith('.bat') ||
        lower.endsWith('.cmd') ||
        lower.endsWith('.apk') ||
        lower.endsWith('.bin') ||
        lower.endsWith('.msi') ||
        lower.endsWith('.deb');
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  DownloadTask copyWith({
    String? id,
    String? url,
    String? destinationPath,
    String? fileName,
    int? fileSizeBytes,
    int? downloadedBytes,
    int? speedBytesPerSec,
    int? etaSeconds,
    bool clearEta = false,
    DownloadStatus? status,
    String? errorMessage,
    String? sha256Expected,
    String? sha256Actual,
    bool? isRangeSupported,
    int? splitCount,
    bool? allowClearnet,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      url: url ?? this.url,
      destinationPath: destinationPath ?? this.destinationPath,
      fileName: fileName ?? this.fileName,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      etaSeconds: clearEta ? null : (etaSeconds ?? this.etaSeconds),
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      sha256Expected: sha256Expected ?? this.sha256Expected,
      sha256Actual: sha256Actual ?? this.sha256Actual,
      isRangeSupported: isRangeSupported ?? this.isRangeSupported,
      splitCount: splitCount ?? this.splitCount,
      allowClearnet: allowClearnet ?? this.allowClearnet,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'url': url,
    'destinationPath': destinationPath,
    'fileName': fileName,
    if (fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
    'downloadedBytes': downloadedBytes,
    'speedBytesPerSec': speedBytesPerSec,
    if (etaSeconds != null) 'etaSeconds': etaSeconds,
    'status': status.slug,
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (sha256Expected != null) 'sha256Expected': sha256Expected,
    if (sha256Actual != null) 'sha256Actual': sha256Actual,
    'isRangeSupported': isRangeSupported ? 1 : 0,
    'splitCount': splitCount,
    'allowClearnet': allowClearnet ? 1 : 0,
    'createdAt': createdAt.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
  };

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    return DownloadTask(
      id: map['id'] as String? ?? '',
      url: map['url'] as String? ?? '',
      destinationPath: map['destinationPath'] as String? ?? '',
      fileName: map['fileName'] as String? ?? '',
      fileSizeBytes: map['fileSizeBytes'] as int?,
      downloadedBytes: map['downloadedBytes'] as int? ?? 0,
      speedBytesPerSec: map['speedBytesPerSec'] as int? ?? 0,
      etaSeconds: map['etaSeconds'] as int?,
      status: DownloadStatus.values.firstWhere(
        (s) => s.slug == map['status'],
        orElse: () => DownloadStatus.queued,
      ),
      errorMessage: map['errorMessage'] as String?,
      sha256Expected: map['sha256Expected'] as String?,
      sha256Actual: map['sha256Actual'] as String?,
      isRangeSupported: (map['isRangeSupported'] as int? ?? 0) == 1,
      splitCount: map['splitCount'] as int? ?? 1,
      allowClearnet: (map['allowClearnet'] as int? ?? 0) == 1,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      completedAt: map['completedAt'] != null
          ? DateTime.tryParse(map['completedAt'] as String)
          : null,
    );
  }
}
