import 'package:flutter/material.dart';
import '../../core/theme/nix_colors.dart';
import 'offline_location_picker_dialog.dart';

class OfflineLocationCard extends StatelessWidget {
  final OfflineLocationData data;

  const OfflineLocationCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: const Color(0xFF0C141B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mini-mapa vetorial estático
          Container(
            height: 110,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _MiniTacticalGridPainter(
                      lat: data.lat,
                      lng: data.lng,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'OFFLINE MAP',
                        style: TextStyle(
                          color: Colors.tealAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.place_rounded, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        data.title,
                        style: TextStyle(
                          color: NixColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${data.lat >= 0 ? '+' : ''}${data.lat.toStringAsFixed(4)}°,  ${data.lng >= 0 ? '+' : ''}${data.lng.toStringAsFixed(4)}°',
                  style: const TextStyle(
                    color: Colors.tealAccent,
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: OutlinedButton.icon(
                    key: Key('open_tactical_map_${data.lat}_${data.lng}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.tealAccent,
                      side: BorderSide(color: Colors.teal.withValues(alpha: 0.6)),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () {
                      OfflineLocationPickerDialog.show(
                        context,
                        initialLat: data.lat,
                        initialLng: data.lng,
                        initialTitle: data.title,
                        readOnly: true,
                      );
                    },
                    icon: const Icon(Icons.explore_outlined, size: 15),
                    label: const Text('Ver no Mapa Tático', style: TextStyle(fontSize: 11.5)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTacticalGridPainter extends CustomPainter {
  final double lat;
  final double lng;

  const _MiniTacticalGridPainter({required this.lat, required this.lng});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.teal.withValues(alpha: 0.15)
      ..strokeWidth = 0.8;

    for (double x = 0; x < size.width; x += 24.0) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 24.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final relX = ((lng + 180.0) / 360.0).clamp(0.1, 0.9);
    final relY = (1.0 - (lat + 90.0) / 180.0).clamp(0.1, 0.9);
    final pin = Offset(size.width * relX, size.height * relY);

    canvas.drawCircle(
      pin,
      12,
      Paint()
        ..color = Colors.tealAccent.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      pin,
      4.5,
      Paint()..color = Colors.redAccent,
    );
    canvas.drawCircle(
      pin,
      4.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_MiniTacticalGridPainter oldDelegate) =>
      lat != oldDelegate.lat || lng != oldDelegate.lng;
}
