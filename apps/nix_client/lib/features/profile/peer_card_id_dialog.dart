import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/member.dart';
import '../../core/models/direct_message.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import 'qr_code_painter.dart';

class PeerCardIdDialog extends StatelessWidget {
  final String peerName;
  final String peerPublicId;
  final String peerFingerprint;
  final NixTrustLevel trustLevel;
  final bool hasCryptographicShield;
  final String bio;
  final List<String> culturalHighlights;
  final String visibility; // 'Público', 'Apenas Contatos Verificados', 'Oculto'
  final bool isVerifiedContact;

  const PeerCardIdDialog({
    super.key,
    required this.peerName,
    required this.peerPublicId,
    required this.peerFingerprint,
    required this.trustLevel,
    this.hasCryptographicShield = true,
    this.bio = 'Membro soberano da rede descentralizada Nix.',
    this.culturalHighlights = const [],
    this.visibility = 'Público',
    this.isVerifiedContact = false,
  });

  static void showForMember(BuildContext context, Member member) {
    final nixState = context.read<NixState>();
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => PeerCardIdDialog(
        peerName: member.name,
        peerPublicId: 'NIX-${member.fingerprint.replaceAll(' ', '').toUpperCase()}',
        peerFingerprint: member.fingerprint,
        trustLevel: member.trustLevel,
        hasCryptographicShield: member.hasCryptographicShield,
        bio: 'Ponto de comunicação cifrado no espaço privado Nix.',
        culturalHighlights: const ['Mobile Suit Gundam Hathaway', 'Sousou no Frieren', 'Reticulum Network'],
        visibility: member.name.contains('NX-7E3A')
            ? nixState.settings.cardIdVisibility
            : (member.isOnline ? 'Público' : 'Apenas Contatos Verificados'),
        isVerifiedContact: member.trustLevel == NixTrustLevel.level3Green,
      ),
    );
  }

  static void showForRequest(BuildContext context, ContactRequest request) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => PeerCardIdDialog(
        peerName: request.peerName,
        peerPublicId: request.peerPublicId,
        peerFingerprint: request.peerPublicId.replaceAll('NIX-', ''),
        trustLevel: request.trustLevel,
        hasCryptographicShield: true,
        bio: request.bio.isNotEmpty ? request.bio : request.note,
        culturalHighlights: request.culturalHighlights,
        visibility: request.cardIdVisibility,
        isVerifiedContact: request.trustLevel == NixTrustLevel.level3Green,
      ),
    );
  }

  static void showForDirectMessage(BuildContext context, DirectMessageThread dm) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => PeerCardIdDialog(
        peerName: dm.peerName,
        peerPublicId: dm.peerPublicId,
        peerFingerprint: dm.peerPublicId.replaceAll('NIX-', ''),
        trustLevel: dm.trustLevel,
        hasCryptographicShield: dm.isVerified,
        bio: 'Conversa privada par a par cifrada com Double Ratchet.',
        culturalHighlights: const ['Nix Sovereign Node', 'Sousou no Frieren', 'Vinyl Classic'],
        visibility: 'Público',
        isVerifiedContact: dm.isVerified,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final authorizedData = nixState.getAuthorizedPeerCardData(
      peerName: peerName,
      peerPublicId: peerPublicId,
      trustLevel: trustLevel,
      hasCryptographicShield: hasCryptographicShield,
      rawBio: bio,
      rawHighlights: culturalHighlights,
      ownerVisibility: visibility,
      isVerifiedContact: isVerifiedContact,
    );
    final accent = context.accentColor;
    final isHidden = !authorizedData.isAuthorized;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => Navigator.of(context).pop(),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                decoration: BoxDecoration(
                  gradient: NixTokens.amoledMetalGradient,
                  borderRadius: NixTokens.borderLg,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.5),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.18),
                      blurRadius: 32,
                      spreadRadius: 2,
                    ),
                    const BoxShadow(
                      color: Colors.black,
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header com Botão X
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'NIX SOVEREIGN CARD ID',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.6,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            key: const Key('peer_card_id_close_button'),
                            icon: Icon(Icons.close, size: 18, color: NixColors.textSecondary),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Fechar (Esc)',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: NixColors.surfaceBorderStrong),

                    if (isHidden) ...[
                      // Visibilidade Oculta
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.shield_outlined, size: 48, color: NixColors.textMuted),
                            const SizedBox(height: 16),
                            Text(
                              peerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Este usuário configurou seu Card ID como Oculto para pares não autorizados.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: NixColors.textSecondary, fontSize: 13),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: NixColors.surfaceActive,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: NixColors.surfaceBorder),
                              ),
                              child: Text(peerPublicId, style: NixTokens.monoCode()),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // Conteúdo Principal do Card ID
                      Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Avatar, Nome, Chip de Microprocessador e QR
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Avatar
                                Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    color: NixColors.surfaceCard,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.6),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: accent.withValues(alpha: 0.2),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                                      style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 24,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              peerName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.5,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _TrustDotBadge(level: trustLevel),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            hasCryptographicShield
                                                ? Icons.verified_user_rounded
                                                : Icons.shield_outlined,
                                            size: 13,
                                            color: hasCryptographicShield
                                                ? NixColors.accentGreen
                                                : NixColors.textMuted,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            hasCryptographicShield
                                                ? 'Chave X3DH Verificada'
                                                : 'Identidade Não Confirmada',
                                            style: TextStyle(
                                              color: hasCryptographicShield
                                                  ? NixColors.accentGreen
                                                  : NixColors.textMuted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // QR Code limpo
                                Container(
                                  width: 60,
                                  height: 60,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: CustomPaint(
                                    painter: NixQrCodePainter(
                                      data: peerPublicId,
                                      foregroundColor: Colors.black,
                                      backgroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // Biografia (filtrada pelo controle de privacidade do proprietário no estado)
                            const Text(
                              'BIOGRAFIA & INTERESSES',
                              style: TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              authorizedData.bio,
                              style: const TextStyle(
                                color: Color(0xFFB7BAC4),
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Destaques Culturais do Acervo
                            if (authorizedData.culturalHighlights.isNotEmpty) ...[
                              const Text(
                                'DESTAQUES CULTURAIS PÚBLICOS',
                                style: TextStyle(
                                  color: Color(0xFF9CA3AF),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: authorizedData.culturalHighlights.map((item) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E2026),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.bookmark_outline_rounded, size: 12, color: accent),
                                        const SizedBox(width: 4),
                                        Text(
                                          item,
                                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Identificador Público & Ação Copiar
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: NixColors.surfaceActive,
                                borderRadius: NixTokens.borderSm,
                                border: Border.all(color: NixColors.surfaceBorderStrong),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.fingerprint_rounded, size: 18, color: NixColors.textSecondary),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SelectableText(
                                      peerPublicId,
                                      style: NixTokens.monoCode(size: 11),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(text: peerPublicId));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('ID Soberano copiado para a área de transferência.'),
                                          duration: Duration(seconds: 2),
                                          backgroundColor: NixColors.surfaceElevatedHigh,
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      child: Row(
                                        children: [
                                          Icon(Icons.copy_rounded, size: 13, color: accent),
                                          const SizedBox(width: 4),
                                          Text(
                                            'COPIAR',
                                            style: TextStyle(
                                              color: accent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrustDotBadge extends StatelessWidget {
  final NixTrustLevel level;

  const _TrustDotBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    Color dotColor;
    int count;
    switch (level) {
      case NixTrustLevel.level1Red:
        dotColor = NixColors.trustLevel1Red;
        count = 1;
        break;
      case NixTrustLevel.level2Yellow:
        dotColor = NixColors.trustLevel2Yellow;
        count = 2;
        break;
      case NixTrustLevel.level3Green:
        dotColor = NixColors.trustLevel3Green;
        count = 3;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          count,
          (i) => Container(
            width: 5,
            height: 5,
            margin: EdgeInsets.only(left: i > 0 ? 2 : 0),
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}
