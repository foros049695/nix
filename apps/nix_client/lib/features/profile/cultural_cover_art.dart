import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/cultural_item.dart';

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
  });

  final CulturalItem item;
  final double width;
  final CulturalFrameType frameType;
  final BoxFit? fit;

  CulturalFrameType get effectiveFrame {
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
                    ? 1.48
                    : frame == CulturalFrameType.closedBook
                        ? 1.54
                        : 1.40),
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

  Widget _art() {
    final fallback = CustomPaint(
      painter: _DesignedCoverPainter(item.coverMotif ?? item.title, item.category),
      child: Center(
        child: Text(
          item.monogram,
          maxLines: 1,
          style: TextStyle(
            color: Colors.white,
            fontSize: width * .21,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    final path = item.localImagePath;
    if (path == null || path.isEmpty) return fallback;
    final file = File(path);
    if (!file.existsSync()) return fallback;
    final effectiveFit = fit ?? (item.coverMotif == 'contain' ? BoxFit.contain : BoxFit.cover);
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

  /// Modelo 2.5D de livro físico fechado com lombada realista e bloco de páginas.
  Widget _closedBook({required bool isManga}) {
    final spineRatio = isManga ? 0.075 : 0.085;
    final paperEdgeRatio = isManga ? 0.055 : 0.065;
    final bottomPaperRatio = 0.035;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Bloco de páginas e sombra física projetada
        CustomPaint(
          painter: _ClosedBookPagesPainter(
            spineWidthRatio: spineRatio,
            paperEdgeRatio: paperEdgeRatio,
            bottomPaperRatio: bottomPaperRatio,
            isManga: isManga,
          ),
        ),

        // 2. Capa frontal com vinco da lombada e moldura física
        Positioned(
          left: width * spineRatio,
          top: 0,
          right: width * paperEdgeRatio,
          bottom: width * (isManga ? 1.48 : 1.54) * bottomPaperRatio,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topRight: const Radius.circular(3),
                bottomRight: const Radius.circular(3),
                topLeft: Radius.circular(isManga ? 1 : 2),
                bottomLeft: Radius.circular(isManga ? 1 : 2),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x35000000),
                  offset: Offset(2, 2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(3),
                bottomRight: Radius.circular(3),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Imagem de arte da capa
                  _art(),

                  // Borda com relevo e moldura clássica de encadernação
                  Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                        width: 1.0,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Vinco sutil de dobra da capa sobre a lombada (groove)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: width * 0.035,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0x75000000),
                            Color(0x18000000),
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Brilho acetinado diagonal na capa
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0x22FFFFFF),
                          Colors.transparent,
                          Color(0x28000000),
                        ],
                        stops: [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 3. Lombada (Spine) cilíndrica à esquerda
        Positioned(
          left: 0,
          top: 0,
          bottom: width * (isManga ? 1.48 : 1.54) * bottomPaperRatio,
          width: width * spineRatio,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(3)),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1E1B18),
                  item.category == CulturalCategory.manga
                      ? const Color(0xFF453D37)
                      : const Color(0xFF332B25),
                  const Color(0xFF181512),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
      ],
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
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x540A0711),
              offset: Offset(1, 5),
              blurRadius: 10,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
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
                      Color(0x27FFFFFF),
                      Colors.transparent,
                      Color(0x40000000),
                    ],
                    stops: [0, .41, 1],
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

/// Desenha o bloco físico de folhas de papel cortadas na borda direita e inferior do livro fechado.
class _ClosedBookPagesPainter extends CustomPainter {
  final double spineWidthRatio;
  final double paperEdgeRatio;
  final double bottomPaperRatio;
  final bool isManga;

  const _ClosedBookPagesPainter({
    required this.spineWidthRatio,
    required this.paperEdgeRatio,
    required this.bottomPaperRatio,
    required this.isManga,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final spineW = size.width * spineWidthRatio;
    final paperW = size.width * paperEdgeRatio;
    final bottomH = size.height * bottomPaperRatio;

    // Sombra projetada do livro no plano de fundo
    final dropShadowPath = Path()
      ..moveTo(spineW, 6)
      ..lineTo(size.width + 2, 6)
      ..lineTo(size.width + 2, size.height + 2)
      ..lineTo(spineW, size.height + 2)
      ..close();
    canvas.drawShadow(dropShadowPath, Colors.black, 6.0, false);

    // Bloco de papel lateral direito
    final rightPaperRect = Rect.fromLTWH(
      size.width - paperW - 1,
      4,
      paperW,
      size.height - bottomH - 4,
    );
    final paperGradient = const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color(0xFFC7BBAA),
        Color(0xFFEBE2D4),
        Color(0xFFD4C8B5),
      ],
      stops: [0.0, 0.45, 1.0],
    ).createShader(rightPaperRect);

    final paperPaint = Paint()..shader = paperGradient;
    canvas.drawRect(rightPaperRect, paperPaint);

    // Linhas de páginas (folhas agrupadas) na borda direita
    final linePaint = Paint()
      ..color = const Color(0x608D7E6B)
      ..strokeWidth = 0.65;
    for (double x = rightPaperRect.left + 2; x < rightPaperRect.right; x += 2.2) {
      canvas.drawLine(
        Offset(x, rightPaperRect.top + 1),
        Offset(x, rightPaperRect.bottom - 1),
        linePaint,
      );
    }

    // Bloco de papel inferior
    final bottomPaperRect = Rect.fromLTWH(
      spineW + 2,
      size.height - bottomH,
      size.width - spineW - paperW,
      bottomH,
    );
    final bottomPaperPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFB5A998),
          Color(0xFFDFD6C7),
        ],
      ).createShader(bottomPaperRect);
    canvas.drawRect(bottomPaperRect, bottomPaperPaint);

    // Linhas horizontais de folhas na borda inferior
    for (double y = bottomPaperRect.top + 1.5; y < bottomPaperRect.bottom; y += 2.0) {
      canvas.drawLine(
        Offset(bottomPaperRect.left, y),
        Offset(bottomPaperRect.right, y),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ClosedBookPagesPainter oldDelegate) =>
      isManga != oldDelegate.isManga;
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
