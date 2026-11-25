import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/hybrid_network_coordinator.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Diálogo interativo da "Central de Conectividade" do Nix (Seções 10, 11 e 12).
/// Exibe o estado medido real das 7 camadas de transporte (A–G), filas offline e failover.
class ConnectivityCenterDialog extends StatelessWidget {
  const ConnectivityCenterDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const ConnectivityCenterDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final coordinator = nixState.networkCoordinator;
    final layers = coordinator.activeLayers;
    final pendingCount = coordinator.pendingQueueCount;

    return AlertDialog(
      backgroundColor: NixColors.surfaceElevatedHigh,
      shape: RoundedRectangleBorder(
        borderRadius: NixTokens.borderModal,
        side: BorderSide(color: NixColors.surfaceBorderStrong),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: NixColors.accentCyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: NixColors.accentCyan.withValues(alpha: 0.3)),
            ),
            child: Icon(Icons.hub_outlined, size: 20, color: NixColors.accentCyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Central de Conectividade',
                  style: TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Arquitetura Híbrida Resiliente (Camadas A–G)',
                  style: TextStyle(color: NixColors.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Fechar',
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Banner de Diagnóstico e Fila Offline
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      pendingCount > 0 ? Icons.schedule_rounded : Icons.check_circle_outline_rounded,
                      color: pendingCount > 0 ? Colors.amber : NixColors.accentGreen,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pendingCount > 0
                                ? '$pendingCount envelope(s) aguardando conexão com o destinatário'
                                : 'Todas as mensagens sincronizadas e entregues',
                            style: TextStyle(
                              color: NixColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Failover multipath: preserva envelopes cifrados na fila local e entrega assim que surgir rota.',
                            style: TextStyle(color: NixColors.textMuted, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    if (pendingCount > 0) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: NixColors.accentCyan,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        onPressed: () => coordinator.processPendingQueue(),
                        icon: const Icon(Icons.refresh_rounded, size: 15),
                        label: const Text('Tentar Agora', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 14),
              Text(
                'CAMADAS DE TRANSPORTE E ESTADO MEDIDO',
                style: NixTokens.labelUppercase(),
              ),
              const SizedBox(height: 8),

              // Lista das 7 Camadas (A–G)
              for (final layer in layers) ...[
                _buildLayerTile(context, coordinator, layer),
                const SizedBox(height: 6),
              ],

              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: NixColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: NixColors.surfaceBorderStrong),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, size: 16, color: NixColors.accentPrimary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Privacidade Estrita Fail-Closed: conexões remotas prioritariamente utilizam isolamento Tor Onion v3. Trocas de rede (como Wi-Fi ou Bluetooth) jamais reduzem a segurança E2EE do envelope.',
                        style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }

  Widget _buildLayerTile(
    BuildContext context,
    HybridNetworkCoordinator coordinator,
    TransportLayerInfo layer,
  ) {
    final statusColor = switch (layer.status) {
      TransportStatus.connected => NixColors.accentGreen,
      TransportStatus.available => NixColors.accentCyan,
      TransportStatus.verified => const Color(0xFF38BDF8),
      TransportStatus.waiting => Colors.amber,
      TransportStatus.unavailable => NixColors.textMuted,
      TransportStatus.disabled => Colors.grey,
      TransportStatus.noHardware => const Color(0xFF64748B),
      TransportStatus.noPermission => Colors.deepOrange,
      TransportStatus.failed => Colors.redAccent,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: layer.status == TransportStatus.connected
              ? NixColors.accentGreen.withValues(alpha: 0.4)
              : NixColors.surfaceBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Badge da Letra da Camada (A a G)
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: NixColors.surfaceDock,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: NixColors.surfaceBorderStrong),
                ),
                child: Text(
                  layer.code,
                  style: TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      layer.name,
                      style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      layer.subtitle,
                      style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),

              // Pílula de Status Medido
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      layer.status.label,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),
              // Switch de Ativação
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: layer.isEnabled,
                  activeColor: NixColors.accentCyan,
                  onChanged: (val) => coordinator.toggleLayerEnabled(layer.id, val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            layer.description,
            style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
          ),
          if (layer.sentCount > 0 || layer.receivedCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Enviados: ${layer.sentCount} · Recebidos: ${layer.receivedCount}',
              style: TextStyle(color: NixColors.textMuted, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}
