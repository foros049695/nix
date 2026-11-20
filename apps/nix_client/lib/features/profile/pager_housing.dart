import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/pager_appearance.dart';
import '../../core/security/sovereign_security_gate.dart';

const pagerInk = Color(0xFF10262D);
const pagerDisplayFont = 'PixelifySans';
const pagerRule = Color(0x4D10262D);

ColorFilter? pagerCaseFilter(PagerCaseColor color) {
  if (color == PagerCaseColor.violet) return null;
  final tint = Color(color.rgb);
  List<double> row(double channel) {
    final gain = .60 + channel * .80;
    return [.2126 * gain, .7152 * gain, .0722 * gain, 0, (channel - .5) * 27];
  }

  return ColorFilter.matrix([
    ...row(tint.r),
    ...row(tint.g),
    ...row(tint.b),
    0,
    0,
    0,
    1,
    0,
  ]);
}

String pagerNetworkLabel(SovereignSecurityGateStatus status) {
  if (status.isStrictOffGridMode) return 'Off-grid';
  if (status.isTorAnonymityReady) return 'Tor Onion v3';
  if (status.isBootstrapping) return 'Conectando Tor';
  return 'Sem rede';
}

/// Carcaça renderizada do protótipo do Pager em 1000 × 650.
/// Só as laterais do LCD se estendem para acomodar formulários e texto ampliado.
class PagerHousing extends StatefulWidget {
  final bool reducedMotion;
  final Widget screen;
  final Widget? wallpaper;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onMenu;
  final String nextLabel;
  final double minDisplayHeight;
  final PagerCaseColor caseColor;
  final PagerLcdColor lcdColor;

  const PagerHousing({
    super.key,
    required this.reducedMotion,
    required this.screen,
    this.wallpaper,
    this.onPrevious,
    this.onNext,
    this.onMenu,
    this.nextLabel = 'Próxima tela',
    this.minDisplayHeight = 224,
    this.caseColor = PagerCaseColor.violet,
    this.lcdColor = PagerLcdColor.cyan,
  });

  @override
  State<PagerHousing> createState() => _PagerHousingState();
}

class _PagerHousingState extends State<PagerHousing> {
  Offset _tilt = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final reducesMotion =
        widget.reducedMotion || MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (width <= 0) return const SizedBox.shrink();
      final scale = width / 1000;
      final displayHeight = math.max(306 * scale, widget.minDisplayHeight);
      final extension = displayHeight - 306 * scale;
      final height = 650 * scale + extension;

      void setTilt(Offset tilt) {
        if (_tilt != tilt) setState(() => _tilt = tilt);
      }

      return MouseRegion(
        onHover: reducesMotion
            ? null
            : (event) => setTilt(Offset(
                  (event.localPosition.dx / width - .5).clamp(-.5, .5),
                  (event.localPosition.dy / height - .5).clamp(-.5, .5),
                )),
        onExit: (_) => setTilt(Offset.zero),
        child: TweenAnimationBuilder<Offset>(
          duration:
              reducesMotion ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          tween: Tween(end: reducesMotion ? Offset.zero : _tilt),
          builder: (_, tilt, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .00085)
              ..rotateX(tilt.dy * .10)
              ..rotateY(tilt.dx * -.12),
            child: child,
          ),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 1000,
                    maxWidth: 1000,
                    minHeight: height / scale,
                    maxHeight: height / scale,
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.topLeft,
                      child: DecoratedBox(
                        key: const Key('pager_rendered_shell'),
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: const AssetImage(
                                'assets/images/pager_shell.webp'),
                            colorFilter: pagerCaseFilter(widget.caseColor),
                            fit: BoxFit.fill,
                            centerSlice:
                                const Rect.fromLTRB(133, 143, 867, 395),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 133 * scale,
                  right: 133 * scale,
                  top: 114 * scale,
                  height: displayHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(23 * scale),
                    child: ColoredBox(
                      color: Color(widget.lcdColor.rgb),
                      child: Material(
                        type: MaterialType.transparency,
                        child: widget.wallpaper == null
                            ? widget.screen
                            : Stack(
                                fit: StackFit.expand,
                                children: [widget.wallpaper!, widget.screen],
                              ),
                      ),
                    ),
                  ),
                ),
                _positionKey(
                  scale,
                  extension,
                  261,
                  128,
                  'Anterior',
                  widget.onPrevious,
                ),
                _positionKey(
                  scale,
                  extension,
                  398,
                  204,
                  widget.nextLabel,
                  widget.onNext,
                ),
                _positionKey(
                  scale,
                  extension,
                  611,
                  128,
                  'Menu do Pager',
                  widget.onMenu,
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _positionKey(
    double scale,
    double extension,
    double left,
    double width,
    String label,
    VoidCallback? action,
  ) {
    final height = math.max(44.0, 80 * scale);
    return Positioned(
      left: left * scale,
      width: width * scale,
      top: 499 * scale + extension - height / 2,
      height: height,
      child: Semantics(
        label: label,
        button: true,
        enabled: action != null,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: action,
              borderRadius: BorderRadius.circular(9),
              focusColor: const Color(0x88FFFFFF),
              hoverColor: const Color(0x27FFFFFF),
              splashColor: const Color(0x44160D25),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mensagem da assistente no LCD. A leitura assistiva recebe a frase completa.
class PagerGuide extends StatelessWidget {
  final String message;
  final bool reducedMotion;

  final Widget? actions;
  final double? portraitSize;
  final bool centered;

  const PagerGuide({
    super.key,
    required this.message,
    this.reducedMotion = false,
    this.actions,
    this.portraitSize,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final reducesMotion =
        reducedMotion || MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final size =
          portraitSize ?? (constraints.maxWidth * .27).clamp(48.0, 142.0);
      final portrait = _PagerPortrait(size: size, animate: !reducesMotion);
      final copy = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Semantics(
            label: message,
            child: ExcludeSemantics(
              child: TweenAnimationBuilder<double>(
                key: ValueKey(message),
                tween: Tween(begin: reducesMotion ? 1 : 0, end: 1),
                duration: reducesMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 600),
                builder: (context, fraction, _) => Stack(
                  children: [
                    Opacity(
                        opacity: 0,
                        child: Text('${message}_',
                            textAlign: centered ? TextAlign.center : null,
                            style: _textStyle)),
                    Text(
                      '${message.substring(0, (message.length * fraction).floor())}_',
                      textAlign: centered ? TextAlign.center : null,
                      style: _textStyle,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (actions != null) ...[
            const SizedBox(height: 7),
            actions!,
          ],
        ],
      );
      if (centered) {
        return SizedBox(
          width: double.infinity,
          child: Column(children: [portrait, const SizedBox(height: 8), copy]),
        );
      }
      return Row(children: [
        portrait,
        SizedBox(width: constraints.maxWidth >= 340 ? 20 : 10),
        Expanded(child: copy),
      ]);
    });
  }

  static const _textStyle = TextStyle(
    color: pagerInk,
    fontFamily: pagerDisplayFont,
    fontSize: 17,
    height: 1.3,
  );
}

class _PagerPortrait extends StatefulWidget {
  const _PagerPortrait({required this.size, required this.animate});

  final double size;
  final bool animate;

  @override
  State<_PagerPortrait> createState() => _PagerPortraitState();
}

class _PagerPortraitState extends State<_PagerPortrait> {
  static const _open = AssetImage('assets/images/pager_assistant.png');
  static const _closed = AssetImage('assets/images/pager_assistant_blink.png');
  Timer? _timer;
  bool _blinking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleBlink();
  }

  @override
  void didUpdateWidget(_PagerPortrait oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _scheduleBlink();
  }

  void _scheduleBlink() {
    _timer?.cancel();
    if (!widget.animate || !TickerMode.of(context)) {
      _blinking = false;
      return;
    }
    _timer = Timer(const Duration(milliseconds: 3700), () {
      setState(() => _blinking = true);
      _timer = Timer(const Duration(milliseconds: 150), () {
        setState(() => _blinking = false);
        _scheduleBlink();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.size,
        child: Semantics(
          label: 'Assistente Nix em pixel art',
          image: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(
                  image: _open,
                  opacity: _blinking ? const AlwaysStoppedAnimation(0) : null,
                  filterQuality: FilterQuality.none,
                  excludeFromSemantics: true),
              if (widget.animate)
                Image(
                    image: _closed,
                    opacity: AlwaysStoppedAnimation(_blinking ? 1.0 : 0.0),
                    filterQuality: FilterQuality.none,
                    excludeFromSemantics: true),
            ],
          ),
        ),
      );
}
