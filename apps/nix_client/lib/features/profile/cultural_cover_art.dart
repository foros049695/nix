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
        height: width * (item.isVinyl ? 1 : 1.39),
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

  Widget _book() => CustomPaint(
        painter: const _BookEdgesPainter(),
        child: ClipPath(
            clipper: const _BookFrontClipper(),
            child: Stack(fit: StackFit.expand, children: [
              Padding(
                  padding: EdgeInsets.only(right: width * .12), child: _art()),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: width * .115,
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [
                      Color(0x9A12121A),
                      Color(0x33FFFFFF),
                      Colors.transparent
                    ], stops: [
                      0,
                      .22,
                      1
                    ])),
                  )),
            ])),
      );

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

Path _front(Size s) => Path()
  ..moveTo(0, s.height * .055)
  ..lineTo(s.width * .87, 0)
  ..lineTo(s.width * .87, s.height * .93)
  ..lineTo(0, s.height * .99)
  ..close();

class _BookFrontClipper extends CustomClipper<Path> {
  const _BookFrontClipper();
  @override
  Path getClip(Size size) => _front(size);
  @override
  bool shouldReclip(_BookFrontClipper oldClipper) => false;
}

class _BookEdgesPainter extends CustomPainter {
  const _BookEdgesPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final spine = s.width * .87;
    final edge = s.width * .98;
    final pages = Path()
      ..moveTo(spine, 0)
      ..lineTo(edge, s.height * .065)
      ..lineTo(edge, s.height * .987)
      ..lineTo(spine, s.height)
      ..lineTo(0, s.height * .99)
      ..lineTo(spine, s.height * .93)
      ..close();
    canvas.drawShadow(pages, const Color(0x8C100B17), 5, false);
    canvas.drawPath(
        pages,
        Paint()
          ..shader = const LinearGradient(colors: [
            Color(0xFF81756B),
            Color(0xFFF3EDE4),
            Color(0xFFB6ABA0)
          ]).createShader(Rect.fromLTRB(spine, 0, edge, s.height)));
    final leaf = Paint()
      ..color = const Color(0x70877A6E)
      ..strokeWidth = .55;
    for (final factor in [.19, .38, .57, .76]) {
      final x = spine + (edge - spine) * factor;
      canvas.drawLine(Offset(x, s.height * .065 * factor),
          Offset(x, s.height * .944 + s.height * .036 * factor), leaf);
    }
    canvas.drawLine(
        Offset(edge, s.height * .987),
        Offset(0, s.height * .99),
        Paint()
          ..color = const Color(0xFF352736)
          ..strokeWidth = 1.8);
  }

  @override
  bool shouldRepaint(_BookEdgesPainter oldDelegate) => false;
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
