import 'package:flutter/material.dart';

const pagerInk = Color(0xFF10262D);
const pagerLcd = Color(0xFFAEE9ED);

class PagerHousing extends StatefulWidget {
  final bool reducedMotion;
  final Widget screen;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onMenu;

  const PagerHousing({
    super.key,
    required this.reducedMotion,
    required this.screen,
    required this.onPrevious,
    required this.onNext,
    required this.onMenu,
  });

  @override
  State<PagerHousing> createState() => _PagerHousingState();
}

class _PagerHousingState extends State<PagerHousing> {
  Offset _tilt = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: widget.reducedMotion
          ? null
          : (event) {
              final size = context.size;
              if (size == null || size.isEmpty) return;
              setState(() => _tilt = Offset(
                    (event.localPosition.dx / size.width - .5).clamp(-.5, .5),
                    (event.localPosition.dy / size.height - .5).clamp(-.5, .5),
                  ));
            },
      onExit: (_) {
        if (_tilt != Offset.zero) setState(() => _tilt = Offset.zero);
      },
      child: TweenAnimationBuilder<Offset>(
        duration: widget.reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        tween: Tween(end: widget.reducedMotion ? Offset.zero : _tilt),
        builder: (context, tilt, child) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .001)
            ..rotateX(tilt.dy * .12)
            ..rotateY(tilt.dx * -.13),
          child: child,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(31),
            border: Border.all(color: const Color(0xFF9381AC), width: 1.5),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF696179), Color(0xFF40384F), Color(0xFF262331)],
              stops: [0, .45, 1],
            ),
            boxShadow: const [
              BoxShadow(color: Color(0xFF24182D), offset: Offset(0, 5)),
              BoxShadow(color: Color(0xFF71528B), offset: Offset(0, 7)),
              BoxShadow(
                  color: Color(0x66090011),
                  offset: Offset(0, 12),
                  blurRadius: 14),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
            child: Column(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(21),
                    border:
                        Border.all(color: const Color(0xFFB09BC6), width: 1.5),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF372B42),
                        Color(0xFF735E8E),
                        Color(0xFF271E31)
                      ],
                    ),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0xCC201827),
                          offset: Offset(0, 3),
                          blurRadius: 3),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: ColoredBox(color: pagerLcd, child: widget.screen),
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      if (constraints.maxWidth > 250)
                        const Expanded(
                          child: Text('NIX',
                              style: TextStyle(
                                color: Color(0xFFF1E6FF),
                                fontFamily: 'PixelifySans',
                                fontSize: 14,
                              )),
                        ),
                      Expanded(
                        flex: 2,
                        child: _PagerKey(
                          label: 'Anterior',
                          icon: Icons.chevron_left_rounded,
                          onPressed: widget.onPrevious,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 3,
                        child: _PagerKey(
                          label: 'Próxima tela',
                          text: 'OK',
                          onPressed: widget.onNext,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 2,
                        child: _PagerKey(
                          label: 'Menu do Pager',
                          icon: Icons.menu_rounded,
                          onPressed: widget.onMenu,
                        ),
                      ),
                      if (constraints.maxWidth > 250)
                        const Expanded(
                          child: Icon(Icons.drag_handle_rounded,
                              size: 17, color: Color(0xFFABA0B7)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PagerKey extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? text;
  final VoidCallback? onPressed;

  const _PagerKey({required this.label, this.icon, this.text, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final prominent = text != null;
    return Tooltip(
      message: label,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor:
              prominent ? const Color(0xFFB095DF) : const Color(0xFF494255),
          foregroundColor:
              prominent ? const Color(0xFF251833) : const Color(0xFFF4EDFF),
          disabledBackgroundColor: const Color(0xFF3B3446),
          disabledForegroundColor: const Color(0xFFB6ACC3),
          minimumSize: const Size(0, 44),
          padding: EdgeInsets.zero,
          elevation: 3,
          shadowColor: const Color(0xFF140B1B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF816F96)),
          ),
        ),
        child: text != null
            ? Text(text!,
                style:
                    const TextStyle(fontFamily: 'PixelifySans', fontSize: 17))
            : Icon(icon, size: 20),
      ),
    );
  }
}
