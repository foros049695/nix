import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/media/voice_note.dart';
import '../../core/models/message.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import 'desktop_voice_audio.dart';
import 'voice_note_dialog.dart';

/// Cartão de reprodução de áudio / mensagem de voz integrado no padrão Telegram.
/// Apresenta botão circular de Play/Pause, barras de forma de onda (waveform),
/// duração, tamanho do arquivo e carimbo de data/hora inline no balão de mensagem.
class TelegramAudioCard extends StatefulWidget {
  final Message message;
  final int index;
  final Future<VoiceNote?> Function() load;

  const TelegramAudioCard({
    super.key,
    required this.message,
    required this.index,
    required this.load,
  });

  @override
  State<TelegramAudioCard> createState() => _TelegramAudioCardState();
}

class _TelegramAudioCardState extends State<TelegramAudioCard> {
  late final _desktop = switch (defaultTargetPlatform) {
    TargetPlatform.linux || TargetPlatform.windows when !Platform.environment.containsKey('FLUTTER_TEST') =>
      DesktopVoiceAudio(),
    _ => null,
  };

  VoiceNote? _note;
  bool _isLoading = false;
  bool _isPlaying = false;
  double _progress = 0.0;
  int _currentPositionMs = 0;
  Timer? _playbackTimer;
  List<double> _waveform = const [];

  @override
  void initState() {
    super.initState();
    _waveform = _generateWaveform(widget.message.id.hashCode);
    _prefetch();
  }

  Future<void> _prefetch() async {
    try {
      final note = await widget.load();
      if (!mounted || note == null) return;
      setState(() {
        _note = note;
        _waveform = _calculateRealWaveform(note.pcm, 34);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _stopAudio();
    super.dispose();
  }

  List<double> _generateWaveform(int seed) {
    final rand = math.Random(seed);
    return List<double>.generate(34, (i) {
      final base = 0.2 + 0.8 * math.sin((i / 34) * math.pi);
      final jitter = (rand.nextDouble() - 0.5) * 0.4;
      return (base + jitter).clamp(0.18, 1.0);
    });
  }

  List<double> _calculateRealWaveform(Uint8List pcm, int barCount) {
    if (pcm.length < barCount * 2) return _generateWaveform(widget.message.id.hashCode);
    final shorts = pcm.buffer.asInt16List(pcm.offsetInBytes, pcm.length ~/ 2);
    final chunkSize = (shorts.length / barCount).floor();
    if (chunkSize <= 0) return _generateWaveform(widget.message.id.hashCode);

    final bars = <double>[];
    double maxAmp = 1.0;
    for (int b = 0; b < barCount; b++) {
      int sum = 0;
      final start = b * chunkSize;
      final end = math.min(start + chunkSize, shorts.length);
      for (int i = start; i < end; i++) {
        sum += shorts[i].abs();
      }
      final avg = sum / (end - start);
      bars.add(avg);
      if (avg > maxAmp) maxAmp = avg;
    }
    return bars.map((a) => (a / maxAmp).clamp(0.18, 1.0)).toList();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _pauseAudio();
      return;
    }

    if (_note == null) {
      setState(() => _isLoading = true);
      try {
        _note = await widget.load();
        if (_note != null) {
          _waveform = _calculateRealWaveform(_note!.pcm, 34);
        }
      } catch (_) {}
      if (mounted) setState(() => _isLoading = false);
    }

    final note = _note;
    if (note == null) return;

    await _startAudio(note);
  }

  Future<void> _startAudio(VoiceNote note) async {
    _playbackTimer?.cancel();
    final desktop = _desktop;
    try {
      if (desktop != null) {
        await desktop.play(note.pcm);
      } else {
        await VoiceNoteDialog.channel.invokeMethod<void>('play', note.pcm);
      }
    } catch (_) {
      return;
    }

    final durationMs = math.max(100, note.durationMs);
    final startTime = DateTime.now().subtract(Duration(milliseconds: _currentPositionMs));

    setState(() => _isPlaying = true);

    _playbackTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsed >= durationMs) {
        timer.cancel();
        _stopAudio();
        setState(() {
          _isPlaying = false;
          _progress = 0.0;
          _currentPositionMs = 0;
        });
      } else {
        setState(() {
          _currentPositionMs = elapsed;
          _progress = (elapsed / durationMs).clamp(0.0, 1.0);
        });
      }
    });
  }

  Future<void> _pauseAudio() async {
    _playbackTimer?.cancel();
    final desktop = _desktop;
    try {
      if (desktop != null) {
        await desktop.stopPlayback();
      } else {
        await VoiceNoteDialog.channel.invokeMethod<void>('stopPlayback');
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _isPlaying = false);
    }
  }

  Future<void> _stopAudio() async {
    _playbackTimer?.cancel();
    final desktop = _desktop;
    try {
      if (desktop != null) {
        await desktop.stopPlayback();
      } else {
        await VoiceNoteDialog.channel.invokeMethod<void>('stopPlayback');
      }
    } catch (_) {}
  }

  String _formatDuration(int ms) {
    final totalSec = (ms / 1000).ceil();
    final minutes = totalSec ~/ 60;
    final seconds = totalSec % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '7,7 KB';
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(1).replaceAll('.', ',')} KB';
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    final totalMs = _note?.durationMs ?? 3000;
    final displayDuration = _isPlaying
        ? _formatDuration(_currentPositionMs)
        : _formatDuration(totalMs);
    final fileSizeStr = _formatSize(_note?.pcm.length ?? 0);
    final isMe = widget.message.isMe;

    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Botão circular Play / Pause no estilo Telegram
          InkWell(
            onTap: _isLoading ? null : _togglePlay,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.onAccentColor,
                        ),
                      )
                    : Icon(
                        _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: context.onAccentColor,
                        size: 26,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Coluna: Forma de onda e rodapé com duração e tamanho
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Barras de áudio interativas (Waveform)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final localX = details.localPosition.dx;
                    final newProgress = (localX / 180).clamp(0.0, 1.0);
                    setState(() {
                      _progress = newProgress;
                      _currentPositionMs = (newProgress * totalMs).round();
                    });
                  },
                  child: SizedBox(
                    height: 26,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(_waveform.length, (i) {
                        final barRatio = i / _waveform.length;
                        final isPlayed = barRatio <= _progress;
                        final barHeight = 4.0 + 19.0 * _waveform[i];

                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1.0),
                            height: barHeight,
                            decoration: BoxDecoration(
                              color: isPlayed
                                  ? (isMe ? Colors.white : accent)
                                  : (isMe
                                      ? Colors.white.withValues(alpha: 0.35)
                                      : Colors.white.withValues(alpha: 0.22)),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Informações: Duração, Tamanho e Status
                Row(
                  children: [
                    Text(
                      '$displayDuration, $fileSizeStr',
                      style: TextStyle(
                        color: isMe ? Colors.white70 : NixColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.done_all_rounded,
                        size: 14,
                        color: Colors.white70,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
