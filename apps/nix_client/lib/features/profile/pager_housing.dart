import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/security/sovereign_security_gate.dart';

const pagerInk = Color(0xFF10262D);
const pagerLcd = Color(0xFFAEE9ED);
const pagerDisplayFont = 'PixelifySans';

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
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onMenu;
  final String nextLabel;
  final double minDisplayHeight;

  const PagerHousing({
    super.key,
    required this.reducedMotion,
    required this.screen,
    this.onPrevious,
    this.onNext,
    this.onMenu,
    this.nextLabel = 'Próxima tela',
    this.minDisplayHeight = 224,
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
            child: DecoratedBox(
              key: const Key('pager_rendered_shell'),
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: const AssetImage('assets/images/pager_shell.webp'),
                  fit: BoxFit.fill,
                  scale: 1 / scale,
                  centerSlice: Rect.fromLTRB(
                    133 * scale,
                    143 * scale,
                    867 * scale,
                    395 * scale,
                  ),
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 133 * scale,
                    right: 133 * scale,
                    top: 114 * scale,
                    height: displayHeight,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(23 * scale),
                      child: ColoredBox(
                        color: pagerLcd,
                        child: Material(
                          type: MaterialType.transparency,
                          child: widget.screen,
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

  const PagerGuide({
    super.key,
    required this.message,
    this.reducedMotion = false,
    this.actions,
    this.portraitSize,
  });

  @override
  Widget build(BuildContext context) {
    final reducesMotion =
        reducedMotion || MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final size =
          portraitSize ?? (constraints.maxWidth * .235).clamp(48.0, 108.0);
      return Row(
        children: [
          Image.asset(
            'assets/images/pager_assistant.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
            semanticLabel: 'Assistente Nix em pixel art',
          ),
          SizedBox(width: constraints.maxWidth >= 340 ? 20 : 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                              child: Text('${message}_', style: _textStyle)),
                          Text(
                            '${message.substring(0, (message.length * fraction).floor())}_',
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
            ),
          ),
        ],
      );
    });
  }

  static const _textStyle = TextStyle(
    color: pagerInk,
    fontFamily: pagerDisplayFont,
    fontSize: 17,
    height: 1.3,
  );
}
