import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/security/local_image_helper.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';

class OfflineLocationData {
  final double lat;
  final double lng;
  final String title;

  const OfflineLocationData({
    required this.lat,
    required this.lng,
    required this.title,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'title': title,
      };

  static OfflineLocationData? tryParse(String raw) {
    if (!raw.startsWith('[NIX_LOC]:')) return null;
    try {
      final jsonStr = raw.substring('[NIX_LOC]:'.length).trim();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final lat = (map['lat'] as num?)?.toDouble() ?? 0.0;
      final lng = (map['lng'] as num?)?.toDouble() ?? 0.0;
      final title = (map['title'] as String?)?.trim() ?? 'Localização Marcada';
      return OfflineLocationData(lat: lat, lng: lng, title: title);
    } catch (_) {
      return null;
    }
  }

  String toMessageText() => '[NIX_LOC]:${jsonEncode(toJson())}';
}

class OfflineLocationPickerDialog extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final String initialTitle;
  final bool readOnly;

  const OfflineLocationPickerDialog({
    super.key,
    this.initialLat = -23.5505,
    this.initialLng = -46.6333,
    this.initialTitle = 'Ponto de encontro',
    this.readOnly = false,
  });

  static Future<OfflineLocationData?> show(
    BuildContext context, {
    double initialLat = -23.5505,
    double initialLng = -46.6333,
    String initialTitle = 'Ponto de encontro',
    bool readOnly = false,
  }) {
    return showDialog<OfflineLocationData>(
      context: context,
      barrierDismissible: true,
      builder: (_) => OfflineLocationPickerDialog(
        initialLat: initialLat,
        initialLng: initialLng,
        initialTitle: initialTitle,
        readOnly: readOnly,
      ),
    );
  }

  @override
  State<OfflineLocationPickerDialog> createState() =>
      _OfflineLocationPickerDialogState();
}

class _OfflineLocationPickerDialogState
    extends State<OfflineLocationPickerDialog> {
  late double _lat;
  late double _lng;
  late TextEditingController _titleController;
  late TextEditingController _latController;
  late TextEditingController _lngController;
  Offset _pinRelative = const Offset(0.5, 0.5);
  String? _loadedMbtilesPath;
  bool _isCheckingMaps = true;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lng = widget.initialLng;
    _titleController = TextEditingController(text: widget.initialTitle);
    _latController = TextEditingController(text: _lat.toStringAsFixed(4));
    _lngController = TextEditingController(text: _lng.toStringAsFixed(4));

    // Converte lat/lng iniciais para coordenadas relativas
    final relX = ((_lng + 180.0) / 360.0).clamp(0.05, 0.95);
    final relY = ((90.0 - _lat) / 180.0).clamp(0.05, 0.95);
    _pinRelative = Offset(relX, relY);

    _scanForInstalledMapPackage();
  }

  Future<void> _scanForInstalledMapPackage() async {
    try {
      final candidates = [
        Directory('${Directory.current.path}/maps'),
        Directory('${Platform.environment['HOME'] ?? ''}/.local/share/nix/maps'),
        Directory('/tmp/nix_maps'),
      ];

      for (final dir in candidates) {
        if (await dir.exists()) {
          final files = dir.listSync().whereType<File>();
          for (final f in files) {
            if (f.path.toLowerCase().endsWith('.mbtiles')) {
              if (mounted) {
                setState(() {
                  _loadedMbtilesPath = f.path;
                  _isCheckingMaps = false;
                });
              }
              return;
            }
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isCheckingMaps = false);
    }
  }

  Future<void> _pickMbtilesPackage() async {
    try {
      final picked = await LocalImageHelper.filePickerAdapter.pickAttachments(
        allowedExtensions: ['mbtiles', 'sqlite', 'db'],
        allowMultiple: false,
      );
      if (picked.isNotEmpty && mounted) {
        setState(() {
          _loadedMbtilesPath = picked.first;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Selecione um arquivo .mbtiles local válido: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _updateFromOffset(Offset localPos, Size size) {
    if (widget.readOnly) return;
    final relX = (localPos.dx / size.width).clamp(0.05, 0.95);
    final relY = (localPos.dy / size.height).clamp(0.05, 0.95);
    setState(() {
      _pinRelative = Offset(relX, relY);
      _lat = double.parse(((1.0 - relY) * 180.0 - 90.0).toStringAsFixed(4));
      _lng = double.parse((relX * 360.0 - 180.0).toStringAsFixed(4));
      _latController.text = _lat.toStringAsFixed(4);
      _lngController.text = _lng.toStringAsFixed(4);
    });
  }

  void _updateFromManualCoords() {
    final parsedLat = double.tryParse(_latController.text);
    final parsedLng = double.tryParse(_lngController.text);
    if (parsedLat != null && parsedLng != null) {
      setState(() {
        _lat = parsedLat.clamp(-90.0, 90.0);
        _lng = parsedLng.clamp(-180.0, 180.0);
        final relX = ((_lng + 180.0) / 360.0).clamp(0.05, 0.95);
        final relY = ((90.0 - _lat) / 180.0).clamp(0.05, 0.95);
        _pinRelative = Offset(relX, relY);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: NixColors.surfaceElevatedHigh,
      shape: RoundedRectangleBorder(
        borderRadius: NixTokens.borderModal,
        side: BorderSide(color: NixColors.surfaceBorderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.map_rounded, size: 20, color: Colors.tealAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.readOnly ? 'Mapa Geográfico Offline' : 'Definir Localização Geográfica',
                      style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade900,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'ZERO GPS · OFFLINE',
                      style: TextStyle(color: Colors.tealAccent, fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Posicionamento no mapa geográfico vetorial offline. Zero sinal de GPS ativado, sem telemetria nem requisições externas.',
                style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
              ),
              const SizedBox(height: 10),

              // Status de pacote de mapa offline
              if (!_isCheckingMaps && _loadedMbtilesPath == null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade900.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: Colors.amberAccent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Mapa offline não instalado. Use o grid geográfico base ou importe um pacote .mbtiles.',
                          style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: Colors.tealAccent,
                        ),
                        onPressed: _pickMbtilesPackage,
                        icon: const Icon(Icons.file_open_outlined, size: 14),
                        label: const Text('Importar', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ] else if (_loadedMbtilesPath != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade900.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.teal.shade700.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 15, color: Colors.tealAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Pacote ativo: ${_loadedMbtilesPath!.split('/').last}',
                          style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: _pickMbtilesPackage,
                        child: const Text('Trocar', style: TextStyle(color: Colors.white70, fontSize: 10.5, decoration: TextDecoration.underline)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Mapa geográfico interativo (Projeção Cilíndrica Equirretangular WGS 84)
              LayoutBuilder(
                builder: (context, constraints) {
                  final mapHeight = (constraints.maxWidth * 0.55).clamp(180.0, 240.0);
                  return GestureDetector(
                    onPanDown: (details) => _updateFromOffset(details.localPosition, Size(constraints.maxWidth, mapHeight)),
                    onPanUpdate: (details) => _updateFromOffset(details.localPosition, Size(constraints.maxWidth, mapHeight)),
                    child: Container(
                      height: mapHeight,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A131A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.withValues(alpha: 0.45)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CustomPaint(
                          painter: _GeographicOfflineMapPainter(
                            pinOffset: _pinRelative,
                            hasMbtilesPackage: _loadedMbtilesPath != null,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),

              // Exibição e ajuste fino de coordenadas
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latController,
                      enabled: !widget.readOnly,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      style: const TextStyle(color: Colors.tealAccent, fontFamily: 'monospace', fontSize: 12),
                      decoration: const InputDecoration(
                        labelText: 'Latitude (-90° a +90°)',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onChanged: (_) => _updateFromManualCoords(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _lngController,
                      enabled: !widget.readOnly,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      style: const TextStyle(color: Colors.tealAccent, fontFamily: 'monospace', fontSize: 12),
                      decoration: const InputDecoration(
                        labelText: 'Longitude (-180° a +180°)',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onChanged: (_) => _updateFromManualCoords(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!widget.readOnly)
                TextField(
                  key: const Key('location_title_input'),
                  controller: _titleController,
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Rótulo / Ponto de referência (opcional)',
                    prefixIcon: Icon(Icons.place_outlined, size: 18),
                    isDense: true,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: NixColors.surfaceCard,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _titleController.text.isNotEmpty ? _titleController.text : 'Localização Compartilhada',
                    style: TextStyle(color: NixColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: Text(widget.readOnly ? 'Fechar' : 'Cancelar'),
                  ),
                  if (!widget.readOnly) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const Key('confirm_share_location_button'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.tealAccent.shade700,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () {
                        final data = OfflineLocationData(
                          lat: _lat,
                          lng: _lng,
                          title: _titleController.text.trim().isNotEmpty
                              ? _titleController.text.trim()
                              : 'Ponto de encontro',
                        );
                        Navigator.pop(context, data);
                      },
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Compartilhar Localização'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Desenha o mapa geográfico cartográfico offline (projeção equirretangular WGS 84)
/// com paralelos, meridianos e marcador vetorial.
class _GeographicOfflineMapPainter extends CustomPainter {
  final Offset pinOffset;
  final bool hasMbtilesPackage;

  const _GeographicOfflineMapPainter({
    required this.pinOffset,
    required this.hasMbtilesPackage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fundo oceânico cartográfico
    final oceanPaint = Paint()..color = const Color(0xFF0D1822);
    canvas.drawRect(Offset.zero & size, oceanPaint);

    final linePaint = Paint()
      ..color = Colors.teal.withValues(alpha: 0.16)
      ..strokeWidth = 1.0;

    final equatorPaint = Paint()
      ..color = Colors.teal.withValues(alpha: 0.38)
      ..strokeWidth = 1.4;

    // Meridianos principais (Longitude: -180 a +180 a cada 30 graus = 12 divisões)
    for (int i = 0; i <= 12; i++) {
      final x = (size.width / 12) * i;
      final isGreenwich = i == 6; // 0 graus
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isGreenwich ? equatorPaint : linePaint,
      );
    }

    // Paralelos principais (Latitude: +90 a -90 a cada 30 graus = 6 divisões)
    for (int i = 0; i <= 6; i++) {
      final y = (size.height / 6) * i;
      final isEquator = i == 3; // Linha do Equador 0°
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        isEquator ? equatorPaint : linePaint,
      );
    }

    // Silhuetas continentais vetoriais simplificadas (Globo offline base)
    final landPaint = Paint()
      ..color = Colors.teal.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    // Américas (Norte e Sul)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.14, size.height * 0.18, size.width * 0.20, size.height * 0.35),
        const Radius.circular(8),
      ),
      landPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.24, size.height * 0.52, size.width * 0.14, size.height * 0.38),
        const Radius.circular(8),
      ),
      landPaint,
    );

    // Eurásia e África
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.44, size.height * 0.14, size.width * 0.42, size.height * 0.38),
        const Radius.circular(10),
      ),
      landPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.46, size.height * 0.48, size.width * 0.18, size.height * 0.38),
        const Radius.circular(8),
      ),
      landPaint,
    );

    // Oceania
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.74, size.height * 0.62, size.width * 0.14, size.height * 0.22),
        const Radius.circular(6),
      ),
      landPaint,
    );

    // Rótulo da escala cartográfica
    const scaleText = 'WGS 84 · CILÍNDRICA EQUIRRETANGULAR';
    final textPainter = TextPainter(
      text: const TextSpan(
        text: scaleText,
        style: TextStyle(color: Colors.white24, fontSize: 8.5, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(8, size.height - 14));

    // Marcador geográfico (Pin)
    final pinPos = Offset(size.width * pinOffset.dx, size.height * pinOffset.dy);

    // Halo de precisão
    final haloPaint = Paint()
      ..color = Colors.tealAccent.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pinPos, 16, haloPaint);

    // Pino geográfico
    final pinBodyPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pinPos, 6, pinBodyPaint);

    final pinCenterPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pinPos, 2.5, pinCenterPaint);

    // Retículo em cruz fino sobre a coordenada exata
    final crossPaint = Paint()
      ..color = Colors.tealAccent
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(pinPos.dx - 10, pinPos.dy), Offset(pinPos.dx + 10, pinPos.dy), crossPaint);
    canvas.drawLine(Offset(pinPos.dx, pinPos.dy - 10), Offset(pinPos.dx, pinPos.dy + 10), crossPaint);
  }

  @override
  bool shouldRepaint(_GeographicOfflineMapPainter oldDelegate) =>
      pinOffset != oldDelegate.pinOffset ||
      hasMbtilesPackage != oldDelegate.hasMbtilesPackage;
}
