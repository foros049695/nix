import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/media/local_audio_library_service.dart';
import '../../core/media/nix_music_player_controller.dart';
import '../../core/media/pager_playlist.dart';
import '../../core/security/file_picker_adapter.dart';
import '../../state/nix_state.dart';

/// Tela principal do Player Musical Avançado inspirado no LastWave e AutoEQ (Seção 15).
/// Comporta 3 visualizações sincronizadas:
/// 1. Now Playing (Reprodução Ativa com arte ampla, desfoque e scrubber)
/// 2. Library & Playlists (Acervo, botão play em destaque e mini-player)
/// 3. Audio Settings & AutoEQ DSP (Equalizador paramétrico/gráfico de 15 bandas e calibração de fones)
class LastWaveMusicPlayerScreen extends StatefulWidget {
  final NixMusicPlayerController controller;
  final int initialTabIndex;

  const LastWaveMusicPlayerScreen({
    super.key,
    required this.controller,
    this.initialTabIndex = 0,
  });

  static Future<void> open(BuildContext context, NixMusicPlayerController controller, {int initialTab = 0}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LastWaveMusicPlayerScreen(
          controller: controller,
          initialTabIndex: initialTab,
        ),
      ),
    );
  }

  @override
  State<LastWaveMusicPlayerScreen> createState() => _LastWaveMusicPlayerScreenState();
}

class _LastWaveMusicPlayerScreenState extends State<LastWaveMusicPlayerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final Set<String> _favoriteUris = {};
  bool _isAutoEqTab = true; // Alterna entre AutoEQ/PEQ e 15-Band Graphic

  // Lista de calibrações de fones populares para demonstração do AutoEQ
  static const List<Map<String, String>> _headphoneProfiles = [
    {
      'name': 'CMF by Nothing Buds Pro 2',
      'source': 'Rtings · Bruel & Kjaer 5128',
    },
    {
      'name': 'Sony WH-1000XM5',
      'source': 'Oratory1990 · GRAS 45CA',
    },
    {
      'name': 'Sennheiser HD 600',
      'source': 'Crinacle · 711 Coupler',
    },
    {
      'name': 'Apple AirPods Pro 2 (USB-C)',
      'source': 'Rtings · Bruel & Kjaer 5128',
    },
    {
      'name': 'Moondrop Chu II',
      'source': 'Super* Review · IEC60318-4',
    },
  ];

  String? _selectedHeadphone;
  String _selectedHeadphoneSource = 'Saída Padrão do Sistema (Automático)';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    widget.controller.addListener(_onPlayerStateChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPlayerStateChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onPlayerStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.controller.currentTrack;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900 escuro audiophile
      body: Stack(
        children: [
          // Fundo com gradiente e desfoque ambiental baseado na faixa ativa
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1E1B4B), // Indigo profundo
                    Color(0xFF0F172A), // Slate 900
                    Color(0xFF090D16), // Preto quase total
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Barra de navegação superior entre as 3 telas
                _buildTopTabBar(),
                // Conteúdo das 3 telas
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildNowPlayingScreen(track),
                      _buildLibraryScreen(),
                      _buildAudioDspScreen(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTabBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 28),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Fechar Player',
          ),
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: const Color(0xFF38BDF8).withOpacity(0.2),
                    border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.6)),
                  ),
                  labelColor: const Color(0xFF38BDF8),
                  unselectedLabelColor: Colors.white60,
                  labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(text: 'Now Playing'),
                    Tab(text: 'Biblioteca'),
                    Tab(text: 'AutoEQ DSP'),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
            onPressed: () => _showTrackOptionsModal(),
            tooltip: 'Opções',
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 15.1. TELA 1: NOW PLAYING
  // ===========================================================================
  Widget _buildNowPlayingScreen(PagerTrack? track) {
    if (track == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.04),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Icon(Icons.music_off_rounded, size: 46, color: Colors.white38),
              ),
              const SizedBox(height: 20),
              const Text(
                'Nenhuma música em reprodução',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Nenhuma música adicionada. Selecione uma pasta ou importe arquivos de áudio.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: const Color(0xFF0F172A),
                    ),
                    onPressed: _pickAudioFiles,
                    icon: const Icon(Icons.audio_file_rounded, size: 18),
                    label: const Text('Importar Áudio', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: _scanMusicFolder,
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('Escanear Pasta'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final isFav = _favoriteUris.contains(track.uri);
    final hasRealCover = track.coverPath != null && File(track.coverPath!).existsSync();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 12),
          // Arte da capa em grande formato com cantos suaves e sombra profunda
          Center(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF38BDF8).withOpacity(0.18),
                    blurRadius: 36,
                    spreadRadius: 2,
                    offset: const Offset(0, 16),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF334155), Color(0xFF1E293B)],
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  alignment: Alignment.center,
                  fit: StackFit.expand,
                  children: [
                    if (hasRealCover)
                      Image.file(File(track.coverPath!), fit: BoxFit.cover)
                    else
                      Container(
                        color: const Color(0xFF1E293B),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.album_rounded, size: 90, color: Color(0xFF38BDF8)),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  track.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          track.audioFormat,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Título e Artista com botão de Favorito e Letras
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${track.artist} · ${track.album}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFav ? const Color(0xFFF43F5E) : Colors.white60,
                  size: 26,
                ),
                onPressed: () {
                  setState(() {
                    if (isFav) {
                      _favoriteUris.remove(track.uri);
                    } else {
                      _favoriteUris.add(track.uri);
                    }
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.format_quote_rounded, color: Colors.white60, size: 24),
                onPressed: () => _showLyricsDialog(track),
                tooltip: 'Letras e Ficha Musical',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Badge técnica de qualidade Hi-Res Lossless
          Center(
            child: InkWell(
              onTap: () => _tabController.animateTo(2),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.graphic_eq_rounded, size: 14, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 8),
                    Text(
                      track.audioQualityBadge,
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white38),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Scrubber / Linha de progresso com tempo percorrido e restante
          Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: const Color(0xFF38BDF8),
                  inactiveTrackColor: Colors.white.withOpacity(0.12),
                  thumbColor: Colors.white,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  value: widget.controller.position.inSeconds.toDouble().clamp(
                        0.0,
                        math.max(1.0, widget.controller.duration.inSeconds.toDouble()),
                      ),
                  min: 0.0,
                  max: math.max(1.0, widget.controller.duration.inSeconds.toDouble()),
                  onChanged: (newSec) {
                    widget.controller.seek(Duration(seconds: newSec.toInt()));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(widget.controller.position),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    Text(
                      '-${_formatDuration(widget.controller.duration - widget.controller.position)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Controles de reprodução: Previous, Play/Pause, Next
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 36,
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                onPressed: () => widget.controller.previous(),
              ),
              const SizedBox(width: 24),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.3),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: IconButton(
                  iconSize: 42,
                  color: const Color(0xFF0F172A),
                  icon: Icon(
                    widget.controller.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  onPressed: () => widget.controller.togglePlayPause(),
                ),
              ),
              const SizedBox(width: 24),
              IconButton(
                iconSize: 36,
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                onPressed: () => widget.controller.next(),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Barra inferior de utilidades: Shuffle, Volume, Dispositivo, Repetição
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: widget.controller.isShuffle
                      ? const Color(0xFF38BDF8)
                      : Colors.white38,
                ),
                onPressed: () => widget.controller.toggleShuffle(),
                tooltip: 'Modo Aleatório',
              ),
              IconButton(
                icon: const Icon(Icons.volume_up_rounded, color: Colors.white70),
                onPressed: () => _showVolumeSliderDialog(),
                tooltip: 'Ajustar Volume',
              ),
              IconButton(
                icon: const Icon(Icons.speaker_group_outlined, color: Colors.white70),
                onPressed: () => _showOutputDeviceModal(),
                tooltip: 'Dispositivo de Saída',
              ),
              IconButton(
                icon: Icon(
                  Icons.repeat_rounded,
                  color: widget.controller.isRepeat
                      ? const Color(0xFF38BDF8)
                      : Colors.white38,
                ),
                onPressed: () => widget.controller.toggleRepeat(),
                tooltip: 'Repetir Faixa',
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ===========================================================================
  // 15.2. TELA 2: BIBLIOTECA & PLAYLIST
  // ===========================================================================
  Widget _buildLibraryScreen() {
    final playlist = widget.controller.playlist;
    final currentTrack = widget.controller.currentTrack;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            // Cabeçalho da Biblioteca Soberana
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                      ),
                    ),
                    child: const Icon(Icons.library_music_rounded, color: Colors.white, size: 38),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Biblioteca Musical Local',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Arquivos Locais e Armazenados',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${playlist.length} faixas disponíveis',
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Ações: Importar Arquivos, Escanear Pasta, Play All
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.audio_file_rounded, size: 18),
                    label: const Text('Importar Áudio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: _pickAudioFiles,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('Escanear Pasta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: _scanMusicFolder,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Filtro e contagem
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Faixas da Fila',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${playlist.length} faixas',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (playlist.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(28),
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.music_off_rounded, size: 48, color: Colors.white24),
                    const SizedBox(height: 14),
                    const Text(
                      'Nenhuma música adicionada.',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Selecione uma pasta ou importe arquivos de áudio (.flac, .mp3, .wav, .ogg, .opus, .m4a).',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ] else ...[
              for (int i = 0; i < playlist.length; i++) ...[
                _buildTrackTile(playlist[i], i, isCurrent: i == widget.controller.currentIndex),
                const SizedBox(height: 6),
              ],
            ],
          ],
        ),

        // Mini player flutuante no rodapé
        if (currentTrack != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _buildFloatingMiniPlayer(currentTrack),
          ),
      ],
    );
  }

  Widget _buildTrackTile(PagerTrack track, int index, {required bool isCurrent}) {
    final hasRealCover = track.coverPath != null && File(track.coverPath!).existsSync();

    return Container(
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFF38BDF8).withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: isCurrent ? Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)) : null,
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isCurrent ? const Color(0xFF38BDF8) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: hasRealCover
                ? Image.file(File(track.coverPath!), fit: BoxFit.cover)
                : Icon(
                    isCurrent
                        ? (widget.controller.isPlaying ? Icons.equalizer_rounded : Icons.play_arrow_rounded)
                        : Icons.music_note_rounded,
                    color: isCurrent ? Colors.white : Colors.white60,
                  ),
          ),
        ),
        title: Text(
          track.name,
          style: TextStyle(
            color: isCurrent ? const Color(0xFF38BDF8) : Colors.white,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${track.artist} · ${track.audioFormat}${track.bitDepth.isNotEmpty ? " · ${track.bitDepth}" : ""}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              track.formattedDuration,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
              onPressed: () => _showTrackContextMenu(track, index),
            ),
          ],
        ),
        onTap: () {
          widget.controller.playTrack(track);
        },
      ),
    );
  }

  Future<void> _pickAudioFiles() async {
    try {
      final choices = await const CrossPlatformFilePickerAdapter().pickAttachments(
        allowedExtensions: const ['mp3', 'flac', 'wav', 'ogg', 'opus', 'm4a', 'aac'],
        allowMultiple: true,
      );
      if (choices.isEmpty) return;
      final service = LocalAudioLibraryService();
      final tracks = <PagerTrack>[];
      for (final path in choices) {
        final t = await service.extractMetadata(path);
        if (t != null) tracks.add(t);
      }
      if (tracks.isNotEmpty && mounted) {
        final state = context.read<NixState>();
        await state.addTracksToAudioLibrary(tracks);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tracks.length} música(s) importada(s) com metadados reais!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao importar áudio: $e')),
        );
      }
    }
  }

  Future<void> _scanMusicFolder() async {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = [
      if (home.isNotEmpty) '$home/Música',
      if (home.isNotEmpty) '$home/Music',
      if (home.isNotEmpty) '$home/Downloads/Nix',
    ];
    Directory? chosen;
    for (final c in candidates) {
      final d = Directory(c);
      if (d.existsSync()) {
        chosen = d;
        break;
      }
    }
    if (chosen == null) {
      await _pickAudioFiles();
      return;
    }
    try {
      final service = LocalAudioLibraryService();
      final tracks = await service.scanDirectory(chosen);
      if (tracks.isNotEmpty && mounted) {
        final state = context.read<NixState>();
        await state.addTracksToAudioLibrary(tracks);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tracks.length} música(s) catalogada(s) de ${chosen.path}!')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nenhum arquivo de áudio encontrado em ${chosen.path}.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao escanear pasta: $e')),
        );
      }
    }
  }

  Widget _buildFloatingMiniPlayer(PagerTrack track) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withOpacity(0.85),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF38BDF8),
                child: const Icon(Icons.music_note_rounded, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => _tabController.animateTo(0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        track.artist,
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  widget.controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
                onPressed: () => widget.controller.togglePlayPause(),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white70),
                onPressed: () => widget.controller.next(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 15.3. TELA 3: CONFIGURAÇÕES DE ÁUDIO & AUTOEQ DSP
  // ===========================================================================
  Widget _buildAudioDspScreen() {
    final dsp = widget.controller.dspSettings;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        // Topo: Switch master AutoEQ
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.equalizer_rounded,
                      color: dsp.autoEqEnabled ? const Color(0xFF38BDF8) : Colors.white38,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Motor AutoEQ / DSP',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Calibração de precisão e resposta harmônica',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: dsp.autoEqEnabled,
                activeColor: const Color(0xFF38BDF8),
                onChanged: (val) {
                  widget.controller.updateDspSettings(dsp.copyWith(autoEqEnabled: val));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Abas: "AutoEQ / PEQ" e "Equalizador Gráfico 15 Bandas"
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _isAutoEqTab = true),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _isAutoEqTab ? const Color(0xFF38BDF8).withOpacity(0.25) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: _isAutoEqTab ? Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)) : null,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.headphones_rounded,
                            size: 16,
                            color: _isAutoEqTab ? const Color(0xFF38BDF8) : Colors.white54,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'AutoEQ / PEQ',
                            style: TextStyle(
                              color: _isAutoEqTab ? const Color(0xFF38BDF8) : Colors.white60,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _isAutoEqTab = false),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: !_isAutoEqTab ? const Color(0xFF38BDF8).withOpacity(0.25) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: !_isAutoEqTab ? Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)) : null,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 16,
                            color: !_isAutoEqTab ? const Color(0xFF38BDF8) : Colors.white54,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '15-Band Graphic',
                            style: TextStyle(
                              color: !_isAutoEqTab ? const Color(0xFF38BDF8) : Colors.white60,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_isAutoEqTab) ...[
          // Card de Headphone selecionado com botão para trocar
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFF38BDF8),
                  radius: 20,
                  child: Icon(Icons.headphones_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedHeadphone ?? 'Saída Padrão do Sistema',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedHeadphoneSource,
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () => _showHeadphonePickerModal(),
                  child: const Text('Trocar Fone', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Gráfico de Resposta de Frequência interativo
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Resposta de Frequência (Frequency Response)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      dsp.autoEqEnabled ? 'Ativo' : 'Bypass',
                      style: TextStyle(
                        color: dsp.autoEqEnabled ? const Color(0xFF38BDF8) : Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Custom painter das curvas
                SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _FrequencyResponseCurvePainter(
                      bassDb: dsp.bassGainDb,
                      trebleDb: dsp.trebleGainDb,
                      enabled: dsp.autoEqEnabled,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Legenda de cores do LastWave
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: const [
                    _CurveLegendItem(label: 'EQ', color: Color(0xFFEAB308)),
                    _CurveLegendItem(label: 'Medido', color: Color(0xFF94A3B8)),
                    _CurveLegendItem(label: 'Target Harman', color: Color(0xFF10B981)),
                    _CurveLegendItem(label: 'Corrigido', color: Color(0xFFF97316)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Seletor de Target Curve
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Curva Alvo (Target Curve)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ajuste calibrado comparado ao perfil laboratorial Harman-style target.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: dsp.activeTarget,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    items: const [
                      DropdownMenuItem(
                        value: 'Harman-style Target (AutoEQ default)',
                        child: Text('Harman-style Target (AutoEQ default)'),
                      ),
                      DropdownMenuItem(
                        value: 'Harman In-Ear 2019v2',
                        child: Text('Harman In-Ear 2019v2'),
                      ),
                      DropdownMenuItem(
                        value: 'Harman Over-Ear 2018',
                        child: Text('Harman Over-Ear 2018'),
                      ),
                      DropdownMenuItem(
                        value: 'Diffuse Field (Flat Studio Reference)',
                        child: Text('Diffuse Field (Flat Studio Reference)'),
                      ),
                      DropdownMenuItem(
                        value: 'Nix Custom Bass Boost Profile',
                        child: Text('Nix Custom Bass Boost Profile'),
                      ),
                    ],
                    onChanged: (newTarget) {
                      if (newTarget != null) {
                        widget.controller.updateDspSettings(dsp.copyWith(activeTarget: newTarget));
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Sliders: Bass e Tilt
          _buildGainSlider(
            title: 'Graves (Bass Gain)',
            value: dsp.bassGainDb,
            min: -12.0,
            max: 12.0,
            unit: 'dB',
            onChanged: (val) {
              widget.controller.updateDspSettings(dsp.copyWith(bassGainDb: val));
            },
          ),
          const SizedBox(height: 12),
          _buildGainSlider(
            title: 'Inclinação Tonal (Tilt)',
            value: dsp.tiltDbPerOct,
            min: -3.0,
            max: 3.0,
            unit: 'dB/oct',
            onChanged: (val) {
              widget.controller.updateDspSettings(dsp.copyWith(tiltDbPerOct: val));
            },
          ),
          const SizedBox(height: 12),
          _buildGainSlider(
            title: 'Agudos (Treble Gain)',
            value: dsp.trebleGainDb,
            min: -12.0,
            max: 12.0,
            unit: 'dB',
            onChanged: (val) {
              widget.controller.updateDspSettings(dsp.copyWith(trebleGainDb: val));
            },
          ),
        ] else ...[
          // Equalizador gráfico de 15 bandas completo
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Equalizador Gráfico de 15 Bandas (ISO)',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    TextButton(
                      onPressed: () {
                        widget.controller.updateDspSettings(
                          dsp.copyWith(graphicEq15Bands: List.filled(15, 0.0)),
                        );
                      },
                      child: const Text('Zerar Bandas', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 240,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: SizedBox(
                      width: math.max(480.0, MediaQuery.of(context).size.width - 72),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (int i = 0; i < AudioDspSettings.bandFrequenciesHz.length; i++) ...[
                            _buildSingleEqBand(
                              freqHz: AudioDspSettings.bandFrequenciesHz[i],
                              gainDb: dsp.graphicEq15Bands[i],
                              onChanged: (newGain) {
                                final updated = List<double>.from(dsp.graphicEq15Bands);
                                updated[i] = newGain;
                                widget.controller.updateDspSettings(dsp.copyWith(graphicEq15Bands: updated));
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),
        // Normalização de Volume (ReplayGain / EBU R128)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Normalização de Volume (EBU R128)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    'Evita saltos abruptos de volume entre faixas',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
              Switch(
                value: dsp.volumeNormalization,
                activeColor: const Color(0xFF38BDF8),
                onChanged: (val) {
                  widget.controller.updateDspSettings(dsp.copyWith(volumeNormalization: val));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildGainSlider({
    required String title,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    final displaySign = value > 0 ? '+' : '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              Text(
                '$displaySign${value.toStringAsFixed(1)} $unit',
                style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: const Color(0xFF38BDF8),
              inactiveTrackColor: Colors.white.withOpacity(0.12),
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleEqBand({
    required int freqHz,
    required double gainDb,
    required ValueChanged<double> onChanged,
  }) {
    final label = freqHz >= 1000 ? '${(freqHz / 1000).toStringAsFixed(freqHz % 1000 == 0 ? 0 : 1)}k' : '$freqHz';
    final sign = gainDb > 0 ? '+' : '';

    return Column(
      children: [
        Text(
          '$sign${gainDb.toStringAsFixed(0)}',
          style: TextStyle(
            color: gainDb != 0 ? const Color(0xFF38BDF8) : Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: const Color(0xFF38BDF8),
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              ),
              child: Slider(
                value: gainDb.clamp(-12.0, 12.0),
                min: -12.0,
                max: 12.0,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 10),
        ),
      ],
    );
  }

  // ===========================================================================
  // MODAIS E DIÁLOGOS DE SUPORTE
  // ===========================================================================
  void _showVolumeSliderDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            final vol = widget.controller.volume;
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('Volume de Reprodução', style: TextStyle(color: Colors.white)),
              content: Row(
                children: [
                  const Icon(Icons.volume_down_rounded, color: Colors.white60),
                  Expanded(
                    child: Slider(
                      value: vol,
                      min: 0.0,
                      max: 1.0,
                      activeColor: const Color(0xFF38BDF8),
                      onChanged: (val) {
                        widget.controller.setVolume(val);
                        setDlgState(() {});
                      },
                    ),
                  ),
                  Text(
                    '${(vol * 100).toInt()}%',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK', style: TextStyle(color: Color(0xFF38BDF8))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showOutputDeviceModal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dispositivo de Saída de Áudio',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.laptop_rounded, color: Color(0xFF38BDF8)),
                title: const Text('Padrão do Sistema (PipeWire / ALSA)', style: TextStyle(color: Colors.white)),
                trailing: const Icon(Icons.check_rounded, color: Color(0xFF38BDF8)),
                onTap: () => Navigator.pop(ctx),
              ),
              ListTile(
                leading: const Icon(Icons.headphones_rounded, color: Colors.white70),
                title: const Text('Fones Conectados / Saída Analógica', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showHeadphonePickerModal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Selecionar Perfil Calibrado (AutoEQ Database)',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (final hp in _headphoneProfiles)
              ListTile(
                leading: const Icon(Icons.headphones_rounded, color: Color(0xFF38BDF8)),
                title: Text(hp['name']!, style: const TextStyle(color: Colors.white)),
                subtitle: Text(hp['source']!, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () {
                  setState(() {
                    _selectedHeadphone = hp['name']!;
                    _selectedHeadphoneSource = hp['source']!;
                  });
                  Navigator.pop(ctx);
                },
              ),
          ],
        );
      },
    );
  }

  void _showTrackContextMenu(PagerTrack track, int index) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_arrow_rounded, color: Color(0xFF38BDF8)),
            title: const Text('Reproduzir Agora', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(ctx);
              widget.controller.playTrack(track);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            title: const Text('Remover da Playlist', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(ctx);
              widget.controller.removeTrackAt(index);
            },
          ),
        ],
      ),
    );
  }

  void _showTrackOptionsModal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.tune_rounded, color: Color(0xFF38BDF8)),
            title: const Text('Abrir Ajustes AutoEQ DSP', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(ctx);
              _tabController.animateTo(2);
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_play_rounded, color: Colors.white),
            title: const Text('Ver Fila de Reprodução', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(ctx);
              _tabController.animateTo(1);
            },
          ),
        ],
      ),
    );
  }

  void _showLyricsDialog(PagerTrack track) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(track.name, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Artista: ${track.artist}', style: const TextStyle(color: Colors.white70)),
            Text('Álbum: ${track.album}', style: const TextStyle(color: Colors.white70)),
            Text('Formato: ${track.audioQualityBadge}', style: const TextStyle(color: Color(0xFF38BDF8))),
            const SizedBox(height: 16),
            const Text(
              'Letra sincronizada não disponível no cache local offline.',
              style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar', style: TextStyle(color: Color(0xFF38BDF8))),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return '0:00';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// =============================================================================
// PAINTER DA RESPOSTA DE FREQUÊNCIA (CURVAS AUTOEQ)
// =============================================================================
class _FrequencyResponseCurvePainter extends CustomPainter {
  final double bassDb;
  final double trebleDb;
  final bool enabled;

  _FrequencyResponseCurvePainter({
    required this.bassDb,
    required this.trebleDb,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Linhas de grade sutis
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 1. Curva Medida (Cinza)
    final measuredPaint = Paint()
      ..color = const Color(0xFF94A3B8).withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final measuredPath = Path();
    measuredPath.moveTo(0, size.height * 0.7);
    for (double x = 0; x <= size.width; x += 5) {
      final normX = x / size.width;
      final y = size.height * 0.65 -
          math.sin(normX * math.pi * 3) * 12 +
          math.cos(normX * math.pi * 5) * 8;
      measuredPath.lineTo(x, y);
    }
    canvas.drawPath(measuredPath, measuredPaint);

    // 2. Curva Target Harman (Verde)
    final targetPaint = Paint()
      ..color = const Color(0xFF10B981).withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final targetPath = Path();
    targetPath.moveTo(0, size.height * 0.5);
    for (double x = 0; x <= size.width; x += 5) {
      final normX = x / size.width;
      final y = size.height * 0.5 + (normX * 25) - math.sin(normX * math.pi * 2) * 6;
      targetPath.lineTo(x, y);
    }
    canvas.drawPath(targetPath, targetPaint);

    // 3. Curva EQ (Dourado/Amarelo)
    final eqPaint = Paint()
      ..color = enabled ? const Color(0xFFEAB308) : Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final eqPath = Path();
    final bassOffset = (bassDb / 12.0) * 18;
    final trebleOffset = (trebleDb / 12.0) * 18;

    eqPath.moveTo(0, size.height * 0.5 - bassOffset);
    for (double x = 0; x <= size.width; x += 5) {
      final normX = x / size.width;
      final dynamicGain = (1 - normX) * bassOffset + normX * trebleOffset;
      final y = size.height * 0.5 - dynamicGain;
      eqPath.lineTo(x, y);
    }
    canvas.drawPath(eqPath, eqPaint);

    // 4. Curva Corrigida Final (Laranja)
    final correctedPaint = Paint()
      ..color = enabled ? const Color(0xFFF97316) : Colors.white38
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final correctedPath = Path();
    correctedPath.moveTo(0, size.height * 0.5);
    for (double x = 0; x <= size.width; x += 5) {
      final normX = x / size.width;
      final y = size.height * 0.52 + math.sin(normX * math.pi * 4) * 4;
      correctedPath.lineTo(x, y);
    }
    canvas.drawPath(correctedPath, correctedPaint);
  }

  @override
  bool shouldRepaint(covariant _FrequencyResponseCurvePainter oldDelegate) {
    return oldDelegate.bassDb != bassDb ||
        oldDelegate.trebleDb != trebleDb ||
        oldDelegate.enabled != enabled;
  }
}

class _CurveLegendItem extends StatelessWidget {
  final String label;
  final Color color;

  const _CurveLegendItem({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }
}
