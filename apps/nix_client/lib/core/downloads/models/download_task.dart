/// Status operacional de uma tarefa de download direto HTTP/HTTPS.
enum DownloadStatus {
  queued('queued', 'Na fila'),
  starting('starting', 'Iniciando'),
  downloading('downloading', 'Baixando'),
  pausing('pausing', 'Pausando...'),
  paused('paused', 'Pausado'),
  resuming('resuming', 'Retomando...'),
  finalizing('finalizing', 'Finalizando'),
  completed('completed', 'Concluído'),
  failed('failed', 'Falhou'),
  cancelled('cancelled', 'Cancelado');

  final String slug;
  final String label;
  const DownloadStatus(this.slug, this.label);

  /// Valida se a transição para [next] é estritamente permitida na máquina de estados.
  bool canTransitionTo(DownloadStatus next) {
    if (this == next) return true;
    switch (this) {
      case DownloadStatus.queued:
        return next == DownloadStatus.starting || next == DownloadStatus.cancelled;
      case DownloadStatus.starting:
        return next == DownloadStatus.downloading ||
            next == DownloadStatus.pausing ||
            next == DownloadStatus.paused ||
            next == DownloadStatus.failed ||
            next == DownloadStatus.cancelled;
      case DownloadStatus.downloading:
        return next == DownloadStatus.pausing ||
            next == DownloadStatus.paused ||
            next == DownloadStatus.finalizing ||
            next == DownloadStatus.completed ||
            next == DownloadStatus.failed ||
            next == DownloadStatus.cancelled;
      case DownloadStatus.pausing:
        return next == DownloadStatus.paused ||
            next == DownloadStatus.downloading ||
            next == DownloadStatus.failed ||
            next == DownloadStatus.cancelled;
      case DownloadStatus.paused:
        return next == DownloadStatus.resuming ||
            next == DownloadStatus.downloading ||
            next == DownloadStatus.cancelled ||
            next == DownloadStatus.failed;
      case DownloadStatus.resuming:
        return next == DownloadStatus.downloading ||
            next == DownloadStatus.pausing ||
            next == DownloadStatus.paused ||
            next == DownloadStatus.failed ||
            next == DownloadStatus.cancelled;
      case DownloadStatus.finalizing:
        return next == DownloadStatus.completed ||
            next == DownloadStatus.failed ||
            next == DownloadStatus.cancelled;
      case DownloadStatus.completed:
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        // Estados terminais podem transicionar apenas para starting/queued em caso de retentativa explícita
        return next == DownloadStatus.starting || next == DownloadStatus.queued;
    }
  }

  bool get isTerminal =>
      this == DownloadStatus.completed ||
      this == DownloadStatus.failed ||
      this == DownloadStatus.cancelled;

  bool get isActive =>
      this == DownloadStatus.downloading ||
      this == DownloadStatus.starting ||
      this == DownloadStatus.resuming ||
      this == DownloadStatus.finalizing;

  bool get isPausedOrPausing =>
      this == DownloadStatus.paused || this == DownloadStatus.pausing;
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
  final double averageSpeedBytesPerSec;
  final int? etaSeconds;
  final DownloadStatus status;
  final String? errorMessage;
  final String? sha256Expected;
  final String? sha256Actual;
  final bool isRangeSupported;
  final int splitCount;
  final int? activeSegments;
  final int? actualConnections;
  final int peakSpeedBytesPerSec;
  final int activeTransferSeconds;
  final List<int> recentSpeedSamples;
  final bool allowClearnet;
  final bool isUserPaused;
  final String downloadEngine; // 'aria2' ou 'dart_range'
  final String transportProfile; // 'onion_v3_strict', 'tor_socks5', 'custom_socks5', 'direct_https'
  final String? lastEtag;
  final String? lastModified;
  final String? pauseReason;
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
    this.averageSpeedBytesPerSec = 0.0,
    this.etaSeconds,
    this.status = DownloadStatus.queued,
    this.errorMessage,
    this.sha256Expected,
    this.sha256Actual,
    this.isRangeSupported = false,
    this.splitCount = 1,
    this.activeSegments = 0,
    this.actualConnections,
    this.peakSpeedBytesPerSec = 0,
    this.activeTransferSeconds = 0,
    this.recentSpeedSamples = const [],
    this.allowClearnet = false,
    this.isUserPaused = false,
    this.downloadEngine = 'aria2',
    this.transportProfile = 'tor_socks5',
    this.lastEtag,
    this.lastModified,
    this.pauseReason,
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
    if (status == DownloadStatus.finalizing) return 'Finalizando...';
    if (status == DownloadStatus.pausing) return 'Pausando...';
    if (status == DownloadStatus.resuming) return 'Retomando...';
    if (status != DownloadStatus.downloading || speedBytesPerSec <= 0) return '0 KB/s';
    if (speedBytesPerSec >= 1024 * 1024) {
      return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    }
    return '${(speedBytesPerSec / 1024).toStringAsFixed(0)} KB/s';
  }

  /// Velocidade média formatada.
  String get formattedAverageSpeed {
    if (averageSpeedBytesPerSec <= 0) return formattedSpeed;
    if (averageSpeedBytesPerSec >= 1024 * 1024) {
      return '${(averageSpeedBytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    }
    return '${(averageSpeedBytesPerSec / 1024).toStringAsFixed(0)} KB/s';
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

  /// Velocidade sustentada estimada baseada na janela recente (últimos 15-30s).
  double get sustainedSpeedBytesPerSec {
    if (recentSpeedSamples.isEmpty) return speedBytesPerSec.toDouble();
    return recentSpeedSamples.reduce((a, b) => a + b) / recentSpeedSamples.length;
  }

  /// Velocidade sustentada formatada.
  String get formattedSustainedSpeed {
    if (sustainedSpeedBytesPerSec <= 0) return formattedSpeed;
    if (sustainedSpeedBytesPerSec >= 1024 * 1024) {
      return '${(sustainedSpeedBytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    }
    return '${(sustainedSpeedBytesPerSec / 1024).toStringAsFixed(0)} KB/s';
  }

  /// Pico de velocidade observado.
  String get formattedPeakSpeed {
    if (peakSpeedBytesPerSec <= 0) return '0 KB/s';
    if (peakSpeedBytesPerSec >= 1024 * 1024) {
      return '${(peakSpeedBytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    }
    return '${(peakSpeedBytesPerSec / 1024).toStringAsFixed(0)} KB/s';
  }

  /// Conexões reais ativas estabelecidas com o servidor.
  String get formattedConnections {
    if (actualConnections != null && actualConnections! > 0) {
      return '$actualConnections conexões';
    }
    if (activeSegments != null && activeSegments! > 0) {
      return '$activeSegments seg';
    }
    return 'Não informado';
  }

  DownloadTask copyWith({
    String? id,
    String? url,
    String? destinationPath,
    String? fileName,
    int? fileSizeBytes,
    int? downloadedBytes,
    int? speedBytesPerSec,
    double? averageSpeedBytesPerSec,
    int? etaSeconds,
    bool clearEta = false,
    DownloadStatus? status,
    String? errorMessage,
    String? sha256Expected,
    String? sha256Actual,
    bool? isRangeSupported,
    int? splitCount,
    int? activeSegments,
    int? actualConnections,
    int? peakSpeedBytesPerSec,
    int? activeTransferSeconds,
    List<int>? recentSpeedSamples,
    bool? allowClearnet,
    bool? isUserPaused,
    String? downloadEngine,
    String? transportProfile,
    String? lastEtag,
    String? lastModified,
    String? pauseReason,
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
      averageSpeedBytesPerSec: averageSpeedBytesPerSec ?? this.averageSpeedBytesPerSec,
      etaSeconds: clearEta ? null : (etaSeconds ?? this.etaSeconds),
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      sha256Expected: sha256Expected ?? this.sha256Expected,
      sha256Actual: sha256Actual ?? this.sha256Actual,
      isRangeSupported: isRangeSupported ?? this.isRangeSupported,
      splitCount: splitCount ?? this.splitCount,
      activeSegments: activeSegments ?? this.activeSegments,
      actualConnections: actualConnections ?? this.actualConnections,
      peakSpeedBytesPerSec: peakSpeedBytesPerSec ?? this.peakSpeedBytesPerSec,
      activeTransferSeconds: activeTransferSeconds ?? this.activeTransferSeconds,
      recentSpeedSamples: recentSpeedSamples ?? this.recentSpeedSamples,
      allowClearnet: allowClearnet ?? this.allowClearnet,
      isUserPaused: isUserPaused ?? this.isUserPaused,
      downloadEngine: downloadEngine ?? this.downloadEngine,
      transportProfile: transportProfile ?? this.transportProfile,
      lastEtag: lastEtag ?? this.lastEtag,
      lastModified: lastModified ?? this.lastModified,
      pauseReason: pauseReason ?? this.pauseReason,
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
    'averageSpeedBytesPerSec': averageSpeedBytesPerSec,
    if (etaSeconds != null) 'etaSeconds': etaSeconds,
    'status': status.slug,
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (sha256Expected != null) 'sha256Expected': sha256Expected,
    if (sha256Actual != null) 'sha256Actual': sha256Actual,
    'isRangeSupported': isRangeSupported ? 1 : 0,
    'splitCount': splitCount,
    if (activeSegments != null) 'activeSegments': activeSegments,
    if (actualConnections != null) 'actualConnections': actualConnections,
    'peakSpeedBytesPerSec': peakSpeedBytesPerSec,
    'activeTransferSeconds': activeTransferSeconds,
    'recentSpeedSamples': recentSpeedSamples,
    'allowClearnet': allowClearnet ? 1 : 0,
    'isUserPaused': isUserPaused ? 1 : 0,
    'downloadEngine': downloadEngine,
    'transportProfile': transportProfile,
    if (lastEtag != null) 'lastEtag': lastEtag,
    if (lastModified != null) 'lastModified': lastModified,
    if (pauseReason != null) 'pauseReason': pauseReason,
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
      averageSpeedBytesPerSec: (map['averageSpeedBytesPerSec'] as num?)?.toDouble() ?? 0.0,
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
      activeSegments: map['activeSegments'] as int? ?? 0,
      actualConnections: map['actualConnections'] as int?,
      peakSpeedBytesPerSec: map['peakSpeedBytesPerSec'] as int? ?? 0,
      activeTransferSeconds: map['activeTransferSeconds'] as int? ?? 0,
      recentSpeedSamples: (map['recentSpeedSamples'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? const [],
      allowClearnet: (map['allowClearnet'] as int? ?? 0) == 1,
      isUserPaused: (map['isUserPaused'] as int? ?? 0) == 1,
      downloadEngine: map['downloadEngine'] as String? ?? 'aria2',
      transportProfile: map['transportProfile'] as String? ?? 'tor_socks5',
      lastEtag: map['lastEtag'] as String?,
      lastModified: map['lastModified'] as String?,
      pauseReason: map['pauseReason'] as String?,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      completedAt: map['completedAt'] != null
          ? DateTime.tryParse(map['completedAt'] as String)
          : null,
    );
  }
}
