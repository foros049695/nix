import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/user_profile.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';

/// Widget unificado e reativo para renderizar o avatar do perfil do usuário em toda a aplicação
/// (Card ID, SpacesDock topo/rodapé, ChannelsSidebar, HomeSidebar, ProfileOverlay e Diálogos).
///
/// Sincroniza instantaneamente quando a foto/estilo de avatar é alterado no Card ID.
class NixUserAvatar extends StatelessWidget {
  final double size;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;
  final bool showStatus;
  final bool isOnline;
  final VoidCallback? onTap;

  const NixUserAvatar({
    super.key,
    this.size = 36.0,
    this.showBorder = true,
    this.borderColor,
    this.borderWidth = 1.2,
    this.showStatus = false,
    this.isOnline = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final profile = nixState.userProfile;
    final frameStyle = nixState.settings.avatarFrameStyle;
    final userBorderWidth = nixState.settings.avatarBorderWidth;
    final effectiveWidth = borderWidth != 1.2 ? borderWidth : userBorderWidth;

    Color effectiveBorderColor = borderColor ?? NixColors.surfaceBorderStrong;
    if (borderColor == null && nixState.settings.avatarFrameColorHex.isNotEmpty) {
      try {
        final hex = nixState.settings.avatarFrameColorHex.replaceAll('#', '');
        effectiveBorderColor = Color(int.parse('FF$hex', radix: 16));
      } catch (_) {}
    }

    final isSquare = frameStyle == 'roundedSquare' || nixState.settings.roundedSquareAvatar;
    final isPixel = frameStyle == 'pixelArt';
    final isNeon = frameStyle == 'cyberpunkNeon';
    final isGold = frameStyle == 'goldenBorder';
    final isPurple = frameStyle == 'nixPurple';
    final isTactical = frameStyle == 'tactical';

    if (isNeon) {
      effectiveBorderColor = Colors.cyanAccent;
    } else if (isGold) {
      effectiveBorderColor = const Color(0xFFFFD700);
    } else if (isPurple) {
      effectiveBorderColor = const Color(0xFFB388FF);
    } else if (isTactical) {
      effectiveBorderColor = Colors.tealAccent;
    }

    final corners = BorderRadius.circular(
      size * (isPixel ? 0.12 : (isSquare || isNeon || isTactical ? 0.26 : 0.5)),
    );

    Widget avatarCore = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: (!isSquare && !isPixel && !isNeon && !isTactical)
            ? BoxShape.circle
            : BoxShape.rectangle,
        borderRadius: (!isSquare && !isPixel && !isNeon && !isTactical) ? null : corners,
        color: NixColors.surfaceCard,
        border: showBorder
            ? Border.all(
                color: effectiveBorderColor,
                width: effectiveWidth,
              )
            : null,
        boxShadow: isNeon
            ? [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : (isGold
                ? [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                      blurRadius: 5,
                    ),
                  ]
                : null),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildAvatarContent(context, profile),
    );

    if (showStatus) {
      final dotSize = (size * 0.28).clamp(8.0, 14.0);
      avatarCore = Stack(
        clipBehavior: Clip.none,
        children: [
          avatarCore,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOnline ? NixColors.accentGreen : NixColors.textMuted,
                border: Border.all(color: NixColors.surfaceDock, width: 2.0),
              ),
            ),
          ),
        ],
      );
    }

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: corners,
        child: avatarCore,
      );
    }

    return avatarCore;
  }

  Widget _buildAvatarContent(BuildContext context, UserProfile profile) {
    final style = profile.avatarStyle;
    final customPath = profile.customAvatarPath;

    if (style == 'none') {
      return Center(
        child: Icon(
          Icons.person_outline_rounded,
          color: NixColors.textMuted,
          size: size * 0.55,
        ),
      );
    }

    if (style == 'monogram') {
      final name = profile.effectiveDisplayName;
      final initials = name.isNotEmpty
          ? (name.length >= 2
              ? name.substring(0, 2).toUpperCase()
              : name.toUpperCase())
          : 'NX';
      return Center(
        child: Text(
          initials,
          style: TextStyle(
            color: NixColors.platinumAccent,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
      );
    }

    if (style == 'sentinel') {
      return Center(
        child: Icon(
          Icons.security_rounded,
          color: context.accentTextColor,
          size: size * 0.52,
        ),
      );
    }

    if (style == 'local_file' && customPath != null && customPath.isNotEmpty) {
      final file = File(customPath);
      if (file.existsSync()) {
        final offsetFactor = size * 0.25;
        return Transform.translate(
          offset: Offset(
            profile.avatarCropOffsetX * offsetFactor,
            profile.avatarCropOffsetY * offsetFactor,
          ),
          child: Transform.scale(
            scale: profile.avatarCropScale.clamp(1.0, 2.5),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: NixColors.textMuted,
                  size: size * 0.5,
                ),
              ),
            ),
          ),
        );
      }
    }

    // Padrão: Emblema Oficial Vetorizado Nix
    return Padding(
      padding: EdgeInsets.all(size * 0.12),
      child: Image.asset(
        context.brandLogoAsset128,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(
            Icons.shield_moon_outlined,
            color: context.accentTextColor,
            size: size * 0.5,
          ),
        ),
      ),
    );
  }
}
