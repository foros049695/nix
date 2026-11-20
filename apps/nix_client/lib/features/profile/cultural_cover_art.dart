import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/cultural_item.dart';

class CulturalCoverArt extends StatelessWidget {
  const CulturalCoverArt({super.key, required this.item, required this.width});

  final CulturalItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    final book = item.category == CulturalCategory.books ||
        item.category == CulturalCategory.manga;
    return Semantics(
      image: true,
      label: item.isVinyl
          ? 'Disco de vinil'
          : book
              ? 'Livro em 3D'
              : 'Pôster',
      child: SizedBox(
        width: width,
        height: width *
            (item.isVinyl
                ? 1
                : item.category == CulturalCategory.manga
                    ? 1.52
                    : book
                        ? 1.57
                        : 1.39),
        child: item.isVinyl
            ? _vinyl()
            : book
                ? _book()
                : _poster(),
      ),
    );
  }

  Widget _art() {
    final fallback = CustomPaint(
      painter:
          _DesignedCoverPainter(item.coverMotif ?? item.title, item.category),
      child: Center(
          child: Text(
        item.monogram,
        maxLines: 1,
        style: TextStyle(
            color: Colors.white,
            fontSize: width * .21,
            fontWeight: FontWeight.w700),
      )),
    );
    final path = item.localImagePath;
    if (path == null || path.isEmpty) return fallback;
    return ClipRect(
        child: Transform.scale(
      scale: item.cropScale.clamp(1, 2.2),
      child: Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: 600,
        errorBuilder: (_, __, ___) => fallback,
      ),
    ));
  }

  Widget _vinyl() => Stack(fit: StackFit.expand, children: [
        const CustomPaint(painter: _VinylPainter()),
        Center(
            child: ClipOval(
                child: SizedBox.square(dimension: width * .43, child: _art()))),
        Center(
            child: DecoratedBox(
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF100F16),
              border: Border.all(color: Colors.white54)),
          child: SizedBox.square(dimension: width * .055),
        )),
      ]);

  Widget _book() {
    final manga = item.category == CulturalCategory.manga;
    return CustomPaint(
      painter: _BookEdgesPainter(manga),
      child: ClipPath(
        clipper: _BookFrontClipper(manga),
        child: Stack(fit: StackFit.expand, children: [
          Padding(
            padding: EdgeInsets.only(
              left: width * (manga ? .04 : .09),
              right: width * .045,
              bottom: width * .045,
            ),
            child: _art(),
          ),
          Positioned(
            left: width * (manga ? .06 : .10),
            top: 0,
            bottom: 0,
            width: width * (manga ? .045 : .09),
            child: const DecoratedBox(
                decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Color(0x70171315),
                Color(0x36FFFFFF),
                Colors.transparent,
              ], stops: [
                0,
                .38,
                1
              ]),
            )),
          ),
        ]),
      ),
    );
  }

  Widget _poster() => DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x540A0711),
                  offset: Offset(1, 5),
                  blurRadius: 10),
            ]),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(fit: StackFit.expand, children: [
              _art(),
              const DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0x27FFFFFF),
                  Colors.transparent,
                  Color(0x40000000)
                ],
                stops: [0, .41, 1],
              ))),
            ])),
      );
}

List<Offset> _bookCorners(Size size, bool manga) => [
      Offset(
          size.width * (manga ? .04 : .10), size.height * (manga ? .105 : .02)),
      Offset(
          size.width * (manga ? .90 : .92), size.height * (manga ? .016 : .10)),
      Offset(size.width * .94, size.height * .945),
      Offset(size.width * (manga ? .065 : .055), size.height * .967),
    ];

class _BookFrontClipper extends CustomClipper<Path> {
  const _BookFrontClipper(this.manga);
  final bool manga;

  @override
  Path getClip(Size size) =>
      Path()..addPolygon(_bookCorners(size, manga), true);
  @override
  bool shouldReclip(_BookFrontClipper oldClipper) => manga != oldClipper.manga;
}

class _BookEdgesPainter extends CustomPainter {
  const _BookEdgesPainter(this.manga);
  final bool manga;

  @override
  void paint(Canvas canvas, Size size) {
    final corners = _bookCorners(size, manga);
    final depth =
        Offset(-size.width * (manga ? .026 : .053), size.height * .024);
    final outline = Path()
      ..addPolygon([
        corners[0] + depth,
        corners[0],
        corners[1],
        corners[2],
        corners[2] + depth,
        corners[3] + depth,
      ], true);
    canvas.drawShadow(
        outline, const Color(0xC31F1A18), size.width * .068, false);
    final edgePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3D3935), Color(0xFFB6A897), Color(0xFFF1E9DB)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(outline, edgePaint);
    final paper = Paint()
      ..strokeWidth = .55
      ..color = const Color(0x80928877);
    for (final factor in [.28, .58, .84]) {
      canvas.drawLine(
          corners[3] + depth * factor, corners[2] + depth * factor, paper);
    }
  }

  @override
  bool shouldRepaint(_BookEdgesPainter oldDelegate) =>
      manga != oldDelegate.manga;
}

class _VinylPainter extends CustomPainter {
  const _VinylPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final center = s.center(Offset.zero);
    final radius = s.shortestSide / 2 - 3;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawShadow(Path()..addOval(rect), const Color(0x9F100B17), 5, false);
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = const SweepGradient(
            colors: [
              Color(0xFF080A11),
              Color(0xFF272B37),
              Color(0xFF11121C),
              Color(0xFF393C49),
              Color(0xFF080A11)
            ],
            stops: [0, .18, .48, .72, 1],
          ).createShader(rect));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6;
    for (var i = 0; i < 25; i++) {
      groove.color =
          i % 5 == 0 ? const Color(0x4A9399AD) : const Color(0x25838A9E);
      canvas.drawCircle(center, radius * (.47 + i * .021), groove);
    }
  }

  @override
  bool shouldRepaint(_VinylPainter oldDelegate) => false;
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
          ).createShader(bounds));
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
