import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/models/cultural_item.dart';
import '../../core/security/platform_runtime.dart';

enum CulturalFrameType {
  auto,
  closedBook,
  mangaVolume,
  vinyl,
  cinemaPoster,
  pixelArt,
}

class CulturalCoverArt extends StatelessWidget {
  const CulturalCoverArt({
    super.key,
    required this.item,
    required this.width,
    this.frameType = CulturalFrameType.auto,
    this.fit,
    this.forceFlat = false,
  });

  final CulturalItem item;
  final double width;
  final CulturalFrameType frameType;
  final BoxFit? fit;
  final bool forceFlat;

  CulturalFrameType get effectiveFrame {
    if (forceFlat) return CulturalFrameType.cinemaPoster;
    if (frameType != CulturalFrameType.auto) return frameType;
    if (item.isVinyl) return CulturalFrameType.vinyl;
    if (item.category == CulturalCategory.manga) return CulturalFrameType.mangaVolume;
    if (item.category == CulturalCategory.books) return CulturalFrameType.closedBook;
    return CulturalFrameType.cinemaPoster;
  }

  @override
  Widget build(BuildContext context) {
    final frame = effectiveFrame;
    final isBook = frame == CulturalFrameType.closedBook || frame == CulturalFrameType.mangaVolume;

    return Semantics(
      image: true,
      label: frame == CulturalFrameType.vinyl
          ? 'Disco de vinil'
          : isBook
              ? 'Livro físico fechado 2.5D'
              : 'Pôster cultural',
      child: SizedBox(
        width: width,
        height: width *
            (frame == CulturalFrameType.vinyl
                ? 1.0
                : frame == CulturalFrameType.mangaVolume
                    ? 1.45
                    : frame == CulturalFrameType.closedBook
                        ? 1.50
                        : 1.50),
        child: switch (frame) {
          CulturalFrameType.vinyl => _vinyl(),
          CulturalFrameType.closedBook => _closedBook(isManga: false),
          CulturalFrameType.mangaVolume => _closedBook(isManga: true),
          CulturalFrameType.pixelArt => _pixelArtFrame(),
          CulturalFrameType.cinemaPoster || CulturalFrameType.auto => _cinemaPoster(),
        },
      ),
    );
  }

  String? _resolveCoverReference() {
    // 1. localImagePath direto
    final p = item.localImagePath;
    if (p != null && p.isNotEmpty) {
      if (p.startsWith('http://') || p.startsWith('https://') || p.startsWith('data:image/')) {
        return p;
      }
      if (File(p).existsSync()) return p;
    }

    // 2. Arquivo em cache local no diretório persistente de capas
    final safeId = item.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final coversDir = NixPlatformPaths.coversDirectory;
    for (final ext in ['jpg', 'png', 'webp', 'jpeg']) {
      final f = File('$coversDir/$safeId.$ext');
      if (f.existsSync() && f.lengthSync() > 0) {
        return f.path;
      }
    }

    // 2.1 Verificar search_id no diretório de capas (quando adicionado via busca online)
    final searchId = item.externalIds['search_id'] as String?;
    if (searchId != null && searchId.isNotEmpty) {
      final safeSearchId = searchId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      for (final ext in ['jpg', 'png', 'webp', 'jpeg']) {
        final f = File('$coversDir/$safeSearchId.$ext');
        if (f.existsSync() && f.lengthSync() > 0) {
          return f.path;
        }
      }
    }

    // 3. URLs externas persistidas em externalIds ou storeLinks
    final extUrl = item.externalIds['cover_url'] as String? ??
        item.externalIds['cover'] as String? ??
        item.storeLinks?['cover'];
    if (extUrl != null && extUrl.isNotEmpty) {
      _cacheRemoteImageLocally(extUrl, safeId);
      return extUrl;
    }

    // 4. coverMotif se for URL
    if (item.coverMotif != null &&
        (item.coverMotif!.startsWith('http://') || item.coverMotif!.startsWith('https://'))) {
      _cacheRemoteImageLocally(item.coverMotif!, safeId);
      return item.coverMotif;
    }

    return null;
  }

  void _cacheRemoteImageLocally(String url, String safeId) {
    try {
      final coversDir = Directory(NixPlatformPaths.coversDirectory);
      if (!coversDir.existsSync()) {
        coversDir.createSync(recursive: true);
      }
      final file = File('${coversDir.path}/$safeId.jpg');
      if (file.existsSync() && file.lengthSync() > 0) return;

      HttpClient().getUrl(Uri.parse(url)).then((req) {
        req.followRedirects = true;
        req.maxRedirects = 5;
        return req.close();
      }).then((res) {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final bb = BytesBuilder();
          res.listen((chunk) => bb.add(chunk), onDone: () async {
            try {
              await file.writeAsBytes(bb.toBytes());
            } catch (_) {}
          });
        }
      }).catchError((_) {});
    } catch (_) {}
  }

  Widget _art() {
    final fallback = CustomPaint(
      painter: _DesignedCoverPainter(item.coverMotif ?? item.title, item.category),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.monogram,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: width * .20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: (width * .09).clamp(8.0, 12.0),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final ref = _resolveCoverReference();
    if (ref == null || ref.isEmpty) return fallback;

    final effectiveFit = fit ?? (item.coverMotif == 'contain' ? BoxFit.contain : BoxFit.cover);

    // Caso 1: Data URI base64
    if (ref.startsWith('data:image/')) {
      final comma = ref.indexOf(',');
      if (comma != -1) {
        try {
          final bytes = base64Decode(ref.substring(comma + 1));
          return ClipRect(
            child: Transform.scale(
              scale: item.cropScale.clamp(1, 2.2),
              child: Image.memory(
                bytes,
                fit: effectiveFit,
                cacheWidth: 600,
                errorBuilder: (_, __, ___) => fallback,
              ),
            ),
          );
        } catch (_) {}
      }
    }

    // Caso 2: URL HTTP/HTTPS
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return ClipRect(
        child: Transform.scale(
          scale: item.cropScale.clamp(1, 2.2),
          child: Image.network(
            ref,
            fit: effectiveFit,
            cacheWidth: 600,
            errorBuilder: (_, __, ___) => fallback,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                color: const Color(0xFF1E1B2E),
                child: Center(
                  child: SizedBox(
                    width: width * 0.2,
                    height: width * 0.2,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    // Caso 3: Arquivo Local verificado
    final file = File(ref);
    if (!file.existsSync()) return fallback;

    return ClipRect(
      child: Transform.scale(
        scale: item.cropScale.clamp(1, 2.2),
        child: Image.file(
          file,
          fit: effectiveFit,
          cacheWidth: 600,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }

  /// Modelo limpo e autêntico de livro ou mangá com proporções preservadas e sem páginas falsas.
  Widget _closedBook({required bool isManga}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            offset: Offset(0, 5),
            blurRadius: 12,
          ),
          BoxShadow(
            color: Color(0x22000000),
            offset: Offset(0, 1),
            blurRadius: 3,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: _art(),
      ),
    );
  }

  Widget _vinyl() => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              offset: const Offset(0, 5),
              blurRadius: 10,
            ),
          ],
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.9),
            width: 2.2,
          ),
        ),
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _art(),
              const CustomPaint(painter: _VinylGrooveOverlayPainter()),
              Center(
                child: Container(
                  width: width * 0.12,
                  height: width * 0.12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF100F16),
                    border: Border.all(color: Colors.white70, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _cinemaPoster() => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.55),
              offset: const Offset(0, 6),
              blurRadius: 14,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              offset: const Offset(0, 2),
              blurRadius: 4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _art(),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0x22FFFFFF),
                      Colors.transparent,
                      Color(0x35000000),
                    ],
                    stops: [0, .45, 1],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _pixelArtFrame() => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF181528),
          border: Border.all(color: Colors.purpleAccent, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Colors.purpleAccent,
              offset: Offset(2, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(4),
        child: ClipRect(child: _art()),
      );
}



class _DesignedCoverPainter extends CustomPainter {
  const _DesignedCoverPainter(this.motif, this.category);
  final String motif;
  final CulturalCategory category;

  @override
  void paint(Canvas canvas, Size s) {
    final hash = motif.codeUnits
        .fold<int>(0, (value, unit) => (value * 31 + unit) % 10007);
    final hue = (hash + category.index * 29) % 360;
    final color = HSLColor.fromAHSL(1, hue.toDouble(), .40, .34).toColor();
    final accent =
        HSLColor.fromAHSL(1, ((hue + 35) % 360).toDouble(), .55, .66).toColor();
    final bounds = Offset.zero & s;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, const Color(0xFF161622)],
        ).createShader(bounds),
    );
    canvas.save();
    canvas.clipRect(bounds);
    final diameter = s.shortestSide * .64;
    final center = Offset(s.width * (.55 + (hash % 4) * .05), s.height * .36);
    final paint = Paint()
      ..color = accent.withValues(alpha: .63)
      ..strokeWidth = 1;
    if (hash.isEven) {
      paint.style = PaintingStyle.stroke;
      for (var line = 0; line < 7; line++) {
        canvas.drawCircle(center, diameter * (.35 + line * .12), paint);
      }
    } else {
      for (var line = 0; line < 5; line++) {
        final offset = line * diameter * .19;
        final path = Path()
          ..moveTo(-s.width * .1, s.height * .94 - offset)
          ..lineTo(center.dx, s.height * .39 - offset)
          ..lineTo(s.width * 1.1, s.height * .89 - offset);
        paint.style = PaintingStyle.stroke;
        canvas.drawPath(path, paint);
      }
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(Offset(center.dx * .79, math.max(6, center.dy * .65)),
          diameter * .22, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DesignedCoverPainter oldDelegate) =>
      motif != oldDelegate.motif || category != oldDelegate.category;
}

class _VinylGrooveOverlayPainter extends CustomPainter {
  const _VinylGrooveOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    final paintGroove = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (double r = maxR * 0.35; r < maxR * 0.95; r += 7.0) {
      canvas.drawCircle(center, r, paintGroove);
    }

    final shinePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.transparent,
          Colors.black.withValues(alpha: 0.22),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawCircle(center, maxR, shinePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
