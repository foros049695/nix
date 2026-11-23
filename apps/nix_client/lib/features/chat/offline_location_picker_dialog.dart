import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
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
  Offset _pinRelative = const Offset(0.5, 0.5);

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lng = widget.initialLng;
    _titleController = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _updateFromOffset(Offset localPos, Size size) {
    if (widget.readOnly) return;
    final relX = (localPos.dx / size.width).clamp(0.05, 0.95);
    final relY = (localPos.dy / size.height).clamp(0.05, 0.95);
    setState(() {
      _pinRelative = Offset(relX, relY);
      // Converte coordenadas normalizadas em latitude (-90 a 90) e longitude (-180 a 180)
      _lat = double.parse(((1.0 - relY) * 180.0 - 90.0).toStringAsFixed(4));
      _lng = double.parse((relX * 360.0 - 180.0).toStringAsFixed(4));
    });
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
                  const Icon(Icons.explore_outlined, size: 20, color: Colors.tealAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.readOnly ? 'Mapa Tático Offline' : 'Definir Localização Offline',
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
                      'ZERO GPS · FAIL-CLOSED',
                      style: TextStyle(color: Colors.tealAccent, fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Marcador posicionado manualmente no mapa vetorial isolado, sem telemetria nem consultas externas.',
                style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              // Grid tático interativo
              LayoutBuilder(
                builder: (context, constraints) {
                  final mapHeight = (constraints.maxWidth * 0.6).clamp(180.0, 260.0);
                  return GestureDetector(
                    onPanDown: (details) => _updateFromOffset(details.localPosition, Size(constraints.maxWidth, mapHeight)),
                    onPanUpdate: (details) => _updateFromOffset(details.localPosition, Size(constraints.maxWidth, mapHeight)),
                    child: Container(
                      height: mapHeight,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C141B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CustomPaint(
                          painter: _TacticalGridPainter(
                            pinOffset: _pinRelative,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              // Exibição de Coordenadas e Título
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'LAT: ${_lat >= 0 ? '+' : ''}$_lat°  ·  LNG: ${_lng >= 0 ? '+' : ''}$_lng°',
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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

/// Desenha a malha tática vetorial offline com anéis concêntricos e mira de posição.
class _TacticalGridPainter extends CustomPainter {
  final Offset pinOffset;

  const _TacticalGridPainter({required this.pinOffset});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.teal.withValues(alpha: 0.18)
      ..strokeWidth = 1.0;

    // Linhas verticais e horizontais da grade
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Anéis táticos concêntricos de alcance a partir do centro
    final center = Offset(size.width / 2, size.height / 2);
    final ringPaint = Paint()
      ..color = Colors.teal.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var r = 40.0; r < math.max(size.width, size.height); r += 45.0) {
      canvas.drawCircle(center, r, ringPaint);
    }

    // Eixos centrais táticos
    final axisPaint = Paint()
      ..color = Colors.teal.withValues(alpha: 0.3)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), axisPaint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), axisPaint);

    // Marcador tático do usuário
    final pinPos = Offset(size.width * pinOffset.dx, size.height * pinOffset.dy);

    // Pulso do marcador
    final pulsePaint = Paint()
      ..color = Colors.tealAccent.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pinPos, 18, pulsePaint);

    // Círculo central do pino
    final targetPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pinPos, 6, targetPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(pinPos, 6, borderPaint);

    // Cruz de mira sobre o pino
    final crossPaint = Paint()
      ..color = Colors.tealAccent
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(pinPos.dx - 12, pinPos.dy), Offset(pinPos.dx + 12, pinPos.dy), crossPaint);
    canvas.drawLine(Offset(pinPos.dx, pinPos.dy - 12), Offset(pinPos.dx, pinPos.dy + 12), crossPaint);
  }

  @override
  bool shouldRepaint(_TacticalGridPainter oldDelegate) =>
      pinOffset != oldDelegate.pinOffset;
}
