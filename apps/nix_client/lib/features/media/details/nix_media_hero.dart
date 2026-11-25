import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/models/cultural_item.dart';
import '../../../core/security/platform_runtime.dart';

class NixMediaHero extends StatelessWidget {
  final CulturalItem item;
  final bool isInAcervo;
  final VoidCallback onToggleAcervo;

  const NixMediaHero({
    super.key,
    required this.item,
    required this.isInAcervo,
    required this.onToggleAcervo,
  });

  String? _resolveBackdropPath() {
    if (item.bannerPath != null && item.bannerPath!.isNotEmpty) {
      if (item.bannerPath!.startsWith('http') || File(item.bannerPath!).existsSync()) {
        return item.bannerPath;
      }
    }
    final bgUrl = item.externalIds['backdrop_url'] as String? ??
        item.externalIds['backdrop'] as String? ??
        item.externalIds['banner'] as String?;
    if (bgUrl != null && bgUrl.isNotEmpty) return bgUrl;

    // Fallback: se localImagePath for válido
    if (item.localImagePath != null && File(item.localImagePath!).existsSync()) {
      return item.localImagePath;
    }
    final safeId = item.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final coversDir = NixPlatformPaths.coversDirectory;
    for (final ext in ['jpg', 'png', 'webp', 'jpeg']) {
      final f = File('$coversDir/$safeId.$ext');
      if (f.existsSync() && f.lengthSync() > 0) return f.path;
    }
    return null;
  }

  String? _resolveLogoPath() {
    final logo = item.externalIds['logo_url'] as String? ??
        item.externalIds['logo'] as String?;
    return logo;
  }

  @override
  Widget build(BuildContext context) {
    final backdrop = _resolveBackdropPath();
    final logo = _resolveLogoPath();

    return Stack(
      children: [
        // 1. Imagem de backdrop com aspect ratio cinematográfico 16:10
        AspectRatio(
          aspectRatio: 16 / 10,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (backdrop != null) ...[
                if (backdrop.startsWith('http'))
                  Image.network(
                    backdrop,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildFallbackBackdrop(),
                  )
                else
                  Image.file(
                    File(backdrop),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildFallbackBackdrop(),
                  ),
              ] else
                _buildFallbackBackdrop(),

              // Gradiente suave que transiciona perfeitamente para o fundo preto da ficha
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.1),
                        Colors.black.withValues(alpha: 0.65),
                        const Color(0xFF08080C),
                      ],
                      stops: const [0.0, 0.4, 0.75, 1.0],
                    ),
                  ),
                ),
              ),

              // Logo oficial transparente ou título estilizado
              Positioned(
                left: 20,
                right: 20,
                bottom: 12,
                child: Center(
                  child: logo != null && logo.isNotEmpty
                      ? (logo.startsWith('http')
                          ? Image.network(
                              logo,
                              height: 64,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => _buildHeroTitle(),
                            )
                          : Image.file(
                              File(logo),
                              height: 64,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => _buildHeroTitle(),
                            ))
                      : _buildHeroTitle(),
                ),
              ),
            ],
          ),
        ),

        // 2. Metadados e botão de ação posicionados logo abaixo do backdrop
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildFallbackBackdrop() {
    return Container(
      color: const Color(0xFF14121F),
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          size: 64,
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
    );
  }

  Widget _buildHeroTitle() {
    return Text(
      item.title,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.5,
        shadows: [
          Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}
