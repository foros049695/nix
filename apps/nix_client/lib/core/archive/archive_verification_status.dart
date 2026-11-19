import 'package:flutter/material.dart';

/// Estados de verificação criptográfica do Nix Archive (Fase 19 / Etapa 1.3).
enum ArchiveCryptoVerificationStatus {
  verified,
  invalidSignature,
  notVerified,
  verificationError;

  String get label => switch (this) {
        ArchiveCryptoVerificationStatus.verified => 'VERIFIED',
        ArchiveCryptoVerificationStatus.invalidSignature => 'INVALID_SIGNATURE',
        ArchiveCryptoVerificationStatus.notVerified => 'NOT_VERIFIED',
        ArchiveCryptoVerificationStatus.verificationError => 'VERIFICATION_ERROR',
      };

  Color get color => switch (this) {
        ArchiveCryptoVerificationStatus.verified => Colors.greenAccent,
        ArchiveCryptoVerificationStatus.invalidSignature => Colors.redAccent,
        ArchiveCryptoVerificationStatus.notVerified => Colors.grey,
        ArchiveCryptoVerificationStatus.verificationError => Colors.orangeAccent,
      };

  IconData get icon => switch (this) {
        ArchiveCryptoVerificationStatus.verified => Icons.verified_rounded,
        ArchiveCryptoVerificationStatus.invalidSignature => Icons.gpp_bad_rounded,
        ArchiveCryptoVerificationStatus.notVerified => Icons.help_outline_rounded,
        ArchiveCryptoVerificationStatus.verificationError => Icons.warning_amber_rounded,
      };
}

/// Widget reutilizável para exibição padronizada do selo criptográfico do Nix Archive.
class ArchiveCryptoBadge extends StatelessWidget {
  final ArchiveCryptoVerificationStatus status;
  final double iconSize;
  final double fontSize;

  const ArchiveCryptoBadge({
    super.key,
    required this.status,
    this.iconSize = 14,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: status.color.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: iconSize, color: status.color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              color: status.color,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
