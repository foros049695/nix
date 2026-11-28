import 'package:flutter/material.dart';

import '../../core/models/cultural_item.dart';
import 'cultural_cover_art.dart';

/// Card interativo com motion graphics inspirado no HomeGus (motion.css) e PassportDex.
/// Fornece entrada em cascata (staggered fade-up), elevação e brilho ao passar o cursor,
/// distintivo de formato (CBZ, EPUB, PDF), estado de volumes faltantes e barra de progresso.
class CulturalMotionCoverCard extends StatefulWidget {
  final CulturalItem item;
  final double width;
  final int index;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const CulturalMotionCoverCard({
    super.key,
    required this.item,
    required this.width,
    this.index = 0,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<CulturalMotionCoverCard> createState() => _CulturalMotionCoverCardState();
}

class _CulturalMotionCoverCardState extends State<CulturalMotionCoverCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );

    // Curva idêntica a --hg-ease-out do HomeGus cubic-bezier(.16, 1, .3, 1)
    final curve = CurvedAnimation(
      parent: _animController,
      curve: const Cubic(0.16, 1.0, 0.3, 1.0),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curve);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(curve);

    // Entrada em cascata com atraso baseado no índice do cartão
    final delay = Duration(milliseconds: (widget.index * 40).clamp(0, 400));
    Future.delayed(delay, () {
      if (mounted) {
        _animController.forward();
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final isBookOrManga = widget.item.isBookOrManga;
    final formatStr = widget.item.format?.toUpperCase();
    final missingCount = widget.item.missingVolumes.length;
    final hasMissing = widget.item.totalVolumes != null && missingCount > 0;
    final fraction = widget.item.tracking.fraction;

    Widget cardBody = MouseRegion(
      onEnter: reduceMotion ? null : (_) => setState(() => _isHovered = true),
      onExit: reduceMotion ? null : (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
        curve: const Cubic(0.22, 0.61, 0.36, 1.0), // --hg-ease
        transform: Matrix4.identity()
          ..translate(0.0, _isHovered && !reduceMotion ? -4.0 : 0.0)
          ..scale(_isHovered && !reduceMotion ? 1.025 : 1.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(isBookOrManga ? 6 : 10),
          boxShadow: _isHovered && !reduceMotion
              ? [
                  BoxShadow(
                    color: const Color(0xFFF1AB45).withValues(alpha: 0.30),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.65),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.40),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isBookOrManga ? 6 : 10),
          child: Stack(
            children: [
              // Arte da capa 2.5D ou Pôster
              CulturalCoverArt(
                item: widget.item,
                width: widget.width,
              ),

              // Brilho specular ao passar o cursor (HomeGus pp-cover-shine)
              if (!reduceMotion)
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _isHovered ? 0.45 : 0.0,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(-0.3, -0.4),
                          radius: 0.85,
                          colors: [
                            Color(0x88FFFFFF),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Badges superiores: Formato (CBZ, EPUB, PDF) e Volumes Faltantes (BookManager style)
              Positioned(
                top: 5,
                left: 5,
                right: 5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Badge de formato de arquivo (CBZ, CBR, EPUB, PDF)
                    if (formatStr != null && formatStr.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xCC0E0E14),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0x44FFFFFF)),
                        ),
                        child: Text(
                          formatStr,
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      )
                    else if (isBookOrManga && widget.item.currentVolume != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xCC0E0E14),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0x44FFFFFF)),
                        ),
                        child: Text(
                          'Vol. ${widget.item.currentVolume}',
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),

                    // Indicador de volumes faltantes (se for coleção incompleta)
                    if (hasMissing)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xDD78350F), // Âmbar escuro
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFF59E0B)),
                        ),
                        child: Text(
                          '-$missingCount vol',
                          style: const TextStyle(
                            color: Color(0xFFFDE68A),
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else if (widget.item.tracking.favorite)
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xCC0E0E14),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0x44FBBF24)),
                        ),
                        child: const Icon(Icons.star_rounded, size: 10, color: Color(0xFFFBBF24)),
                      ),
                  ],
                ),
              ),

              // Barra sutil de progresso na base do cartão (se houver leitura/progresso ativo)
              if (fraction != null && fraction > 0.0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 3,
                    color: Colors.black45,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction.clamp(0.0, 1.0),
                      child: Container(
                        color: fraction >= 1.0
                            ? const Color(0xFF10B981) // Verde conluído
                            : const Color(0xFF06B6D4), // Ciano em andamento
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (reduceMotion) {
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: cardBody,
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: cardBody,
        ),
      ),
    );
  }
}
