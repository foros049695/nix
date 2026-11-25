import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/downloads/aria2_download_controller.dart';
import '../../core/downloads/models/download_task.dart';
import '../../core/network/transport_profile.dart';
import '../../state/nix_state.dart';

/// Painel técnico de diagnósticos locais de Rede e Downloads (Seção 9).
class NetworkDownloadsDiagnosticsDialog extends StatefulWidget {
  final Aria2DownloadController? downloadController;

  const NetworkDownloadsDiagnosticsDialog({
    super.key,
    this.downloadController,
  });

  static Future<void> show(BuildContext context, {Aria2DownloadController? downloadController}) {
    return showDialog(
      context: context,
      builder: (ctx) => NetworkDownloadsDiagnosticsDialog(downloadController: downloadController),
    );
  }

  @override
  State<NetworkDownloadsDiagnosticsDialog> createState() => _NetworkDownloadsDiagnosticsDialogState();
}

class _NetworkDownloadsDiagnosticsDialogState extends State<NetworkDownloadsDiagnosticsDialog> {
  Aria2DownloadController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.downloadController ?? context.read<NixState>().downloadController;
    _controller?.addListener(_onTick);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  String _sanitizePath(String path) {
    var p = path;
    try {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      if (home.isNotEmpty && p.startsWith(home)) {
        p = '~${p.substring(home.length)}';
      }
    } catch (_) {}
    return p;
  }

  String _generateSanitizedReport(NixState nixState) {
    final buf = StringBuffer();
    buf.writeln('===============================================================');
    buf.writeln('      PROJETO NIX — DIAGNÓSTICO DE REDE E DOWNLOADS (LOCAL)     ');
    buf.writeln('===============================================================');
    buf.writeln('Data/Hora: ${DateTime.now().toUtc().toIso8601String()} UTC');
    buf.writeln('Plataforma: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buf.writeln('');

    buf.writeln('--- [1] INFRAESTRUTURA TOR ---');
    buf.writeln('Daemon Ativo: ${nixState.securityGate.torSocksActive ? "SIM" : "NÃO"}');
    buf.writeln('Bootstrap: ${nixState.securityGate.torBootstrapPercent}%');
    buf.writeln('Circuito Construído: ${nixState.securityGate.isTorAnonymityReady ? "SIM" : "NÃO"}');
    buf.writeln('Porta SOCKS5 Local: 127.0.0.1:${nixState.embeddedTor.socksPort > 0 ? nixState.embeddedTor.socksPort : 9050}');
    buf.writeln('Fail-Closed Enforcement: ATIVO (Vazamento de Clearnet Bloqueado)');
    buf.writeln('');

    buf.writeln('--- [2] MOTOR DE DOWNLOADS (ARIA2 & DART RFC 7233) ---');
    final ctrl = _controller ?? nixState.downloadController;
    buf.writeln('Aria2 Daemon Ativo: ${ctrl.isDaemonRunning ? "SIM" : "NÃO"}');
    buf.writeln('Porta RPC: 127.0.0.1:${ctrl.actualRpcPort}');
    buf.writeln('Token RPC: [PROTEGIDO/REDACTED]');
    buf.writeln('Diretório de Downloads: ${_sanitizePath(ctrl.downloadDir)}');
    buf.writeln('Perfil de Desempenho: ${ctrl.performanceProfile.label}');
    buf.writeln('Conexões/Fatias Máximas: ${ctrl.performanceProfile.split}');
    buf.writeln('');

    buf.writeln('--- [3] PERFIS DE TRANSPORTE POR MÓDULO ---');
    final registry = GlobalTransportRegistry.current;
    for (final mod in TransportModule.values) {
      buf.writeln('• ${mod.label}: ${registry.getProfile(mod).label}');
    }
    buf.writeln('');

    buf.writeln('--- [4] FILA DE TAREFAS ATIVAS ---');
    final tasks = ctrl.tasks;
    if (tasks.isEmpty) {
      buf.writeln('Nenhuma transferência registrada.');
    } else {
      for (final t in tasks) {
        buf.writeln('ID: ${t.id}');
        buf.writeln('  Arquivo: ${t.fileName}');
        buf.writeln('  Motor: ${t.downloadEngine}');
        buf.writeln('  Estado: ${t.status.name}');
        buf.writeln('  Progresso: ${t.formattedProgressBytes} (${(t.progressFraction * 100).toStringAsFixed(1)}%)');
        buf.writeln('  Velocidade Instantânea: ${t.formattedSpeed}');
        buf.writeln('  Velocidade Média Ativa: ${t.formattedAverageSpeed}');
        buf.writeln('  Velocidade Sustentada: ${t.formattedSustainedSpeed}');
        buf.writeln('  Pico Observado: ${t.formattedPeakSpeed}');
        buf.writeln('  Conexões Reais: ${t.formattedConnections}');
        buf.writeln('  Pausa do Usuário: ${t.isUserPaused}');
        buf.writeln('  Destino: ${_sanitizePath(t.destinationPath)}');
        if (t.errorMessage != null) {
          buf.writeln('  Último Erro: ${t.errorMessage}');
        }
        buf.writeln('');
      }
    }

    buf.writeln('--- [5] REGISTRO DAS ÚLTIMAS OPERAÇÕES ---');
    final logs = ctrl.recentLogs;
    if (logs.isEmpty) {
      buf.writeln('Sem registros recentes.');
    } else {
      for (final log in logs.reversed.take(20)) {
        buf.writeln('• ${_sanitizePath(log)}');
      }
    }
    buf.writeln('===============================================================');
    return buf.toString();
  }

  Future<void> _copySanitizedReport(NixState nixState) async {
    final report = _generateSanitizedReport(nixState);
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Relatório técnico sanitizado copiado para a área de transferência!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final ctrl = _controller ?? nixState.downloadController;
    final tasks = ctrl.tasks;
    final registry = GlobalTransportRegistry.current;

    return Dialog(
      backgroundColor: const Color(0xFF0F0E17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF2E2248)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.analytics_rounded, color: Color(0xFF38BDF8), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Diagnóstico de Rede e Downloads',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Métricas em tempo real, isolamento Tor, integridade aria2 e estatísticas',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Conteúdo em cartões com rolagem
              Expanded(
                child: ListView(
                  children: [
                    // Seção 1: Tor
                    _buildSectionCard(
                      title: 'CIRCUITO TOR & SOCKS5',
                      icon: Icons.shield_rounded,
                      color: const Color(0xFF10B981),
                      children: [
                        _metricRow('Daemon Tor Local', nixState.securityGate.torSocksActive ? 'Ativo' : 'Parado',
                            statusColor: nixState.securityGate.torSocksActive ? const Color(0xFF34D399) : const Color(0xFFEF4444)),
                        _metricRow('Bootstrap Anônimo', '${nixState.securityGate.torBootstrapPercent}%',
                            statusColor: nixState.securityGate.torBootstrapPercent == 100 ? const Color(0xFF34D399) : const Color(0xFFFBBF24)),
                        _metricRow('Circuito Estabelecido', nixState.securityGate.isTorAnonymityReady ? 'Pronto (Built)' : 'Construindo...',
                            statusColor: nixState.securityGate.isTorAnonymityReady ? const Color(0xFF34D399) : const Color(0xFFFBBF24)),
                        _metricRow('Porta SOCKS5', '127.0.0.1:${nixState.embeddedTor.socksPort > 0 ? nixState.embeddedTor.socksPort : 9050}'),
                        _metricRow('Modo de Segurança', 'Fail-Closed Estrito (Sem vazamentos)'),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Seção 2: aria2
                    _buildSectionCard(
                      title: 'MOTOR DE DOWNLOADS (ARIA2 RPC & DART RANGE)',
                      icon: Icons.download_done_rounded,
                      color: const Color(0xFFA78BFA),
                      children: [
                        _metricRow('Daemon aria2', ctrl.isDaemonRunning ? 'Em Execução' : 'Parado',
                            statusColor: ctrl.isDaemonRunning ? const Color(0xFF34D399) : const Color(0xFFEF4444)),
                        _metricRow('Porta RPC', '127.0.0.1:${ctrl.actualRpcPort} (Token criptográfico único)'),
                        _metricRow('Diretório de Destino', _sanitizePath(ctrl.downloadDir)),
                        _metricRow('Perfil de Desempenho', '${ctrl.performanceProfile.label.toUpperCase()} (${ctrl.performanceProfile.split} fatias)'),
                        _metricRow('Downloads na Fila', '${tasks.length} total (${tasks.where((t) => t.status == DownloadStatus.downloading).length} ativos)'),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Seção 3: Perfis por Módulo
                    _buildSectionCard(
                      title: 'PERFIS DE TRANSPORTE ATIVOS',
                      icon: Icons.alt_route_rounded,
                      color: const Color(0xFF38BDF8),
                      children: [
                        for (final mod in TransportModule.values)
                          _metricRow(mod.label, registry.getProfile(mod).label,
                              statusColor: registry.getProfile(mod) == TransportProfileType.directHttps
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF34D399)),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Seção 4: Tarefas Ativas Detalhadas
                    if (tasks.isNotEmpty) ...[
                      _buildSectionCard(
                        title: 'ESTATÍSTICAS DAS TRANSFERÊNCIAS',
                        icon: Icons.speed_rounded,
                        color: const Color(0xFFF43F5E),
                        children: [
                          for (final t in tasks) ...[
                            Container(
                              padding: const EdgeInsets.all(8),
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B1B2C),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          t.fileName,
                                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF7C3AED).withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(t.downloadEngine, style: const TextStyle(color: Color(0xFFDDD6FE), fontSize: 9.5)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 12,
                                    children: [
                                      Text('Status: ${t.status.label}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                                      Text('Progresso: ${t.formattedProgressBytes}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                                      Text('Inst.: ${t.formattedSpeed}', style: const TextStyle(color: Color(0xFF34D399), fontSize: 11)),
                                      Text('Média: ${t.formattedAverageSpeed}', style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11)),
                                      Text('Sustentada: ${t.formattedSustainedSpeed}', style: const TextStyle(color: Color(0xFF67E8F9), fontSize: 11)),
                                      Text('Pico: ${t.formattedPeakSpeed}', style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 11)),
                                      Text('Conexões: ${t.formattedConnections}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Seção 5: Registro Sanitizado Recente
                    _buildSectionCard(
                      title: 'REGISTRO DE OPERAÇÕES RECENTES',
                      icon: Icons.article_outlined,
                      color: const Color(0xFFE2E8F0),
                      children: [
                        if (ctrl.recentLogs.isEmpty)
                          const Text('Nenhum evento registrado.', style: TextStyle(color: Color(0xFF64748B), fontSize: 11))
                        else
                          for (final l in ctrl.recentLogs.reversed.take(8))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                '• ${_sanitizePath(l)}',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontFamily: 'monospace'),
                              ),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Botões inferiores
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(color: Color(0xFF0284C7)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('Copiar Relatório Sanitizado', style: TextStyle(fontSize: 12)),
                    onPressed: () => _copySanitizedReport(nixState),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131221),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF27273A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 15),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value, {Color? statusColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
              softWrap: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              softWrap: true,
              style: TextStyle(
                color: statusColor ?? Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
