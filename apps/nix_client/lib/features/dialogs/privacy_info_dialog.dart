import 'package:flutter/material.dart';
import '../../core/theme/nix_colors.dart';

class PrivacyInfoDialog extends StatelessWidget {
  const PrivacyInfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: NixColors.accentGreen.withOpacity(0.4)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/images/nix_logo_128.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Text('🏴‍☠️'),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Painel de Soberania & Privacidade'),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusCard(
                icon: Icons.vpn_lock_rounded,
                iconColor: NixColors.accentTor,
                title: 'Roteamento Tor Onion v3 Ativo',
                subtitle: 'Conexão ponto a ponto através de Hidden Service. Política Fail-Closed ativa: zero vazamento de IP clearnet.',
                tag: 'FAIL-CLOSED',
                tagColor: NixColors.accentTor,
              ),
              const SizedBox(height: 10),
              _buildStatusCard(
                icon: Icons.enhanced_encryption_rounded,
                iconColor: NixColors.accentGreen,
                title: 'Criptografia Double Ratchet & XChaCha20',
                subtitle: 'Forward Secrecy e Post-Compromise Security em todas as sessões par a par. Anexos limpos de metadados EXIF.',
                tag: 'VERIFICADO',
                tagColor: NixColors.accentGreen,
              ),
              const SizedBox(height: 10),
              _buildStatusCard(
                icon: Icons.storage_rounded,
                iconColor: NixColors.accentCyan,
                title: 'Banco de Dados SQLCipher Local (256-bit)',
                subtitle: 'Cofre cifrado em disco derivado via Argon2id. Isolamento absoluto da Seed B (Monero XMR).',
                tag: 'LOCAL-FIRST',
                tagColor: NixColors.accentCyan,
              ),
              const SizedBox(height: 10),
              _buildStatusCard(
                icon: Icons.auto_delete_rounded,
                iconColor: NixColors.accentWarning,
                title: 'Relay Temporário & AutoPruner',
                subtitle: 'Retenção base de 7 dias com histerese progressiva (75%, 85%, 92%). Zero logs com identificadores pessoais.',
                tag: 'TTL 7 DIAS',
                tagColor: NixColors.accentWarning,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCardHover,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_user_outlined, color: NixColors.accentGreen, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Matriz The Hated One: 21 critérios de auditoria em conformidade contínua.',
                        style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: NixColors.surfaceCardHover,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }

  Widget _buildStatusCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String tag,
    required Color tagColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NixColors.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: NixColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: tagColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: tagColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          color: tagColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: NixColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
