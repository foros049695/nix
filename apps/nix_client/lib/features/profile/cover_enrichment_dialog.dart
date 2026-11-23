import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/media/cover_enrichment_service.dart';
import '../../core/models/cultural_item.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

class CoverEnrichmentDialog extends StatefulWidget {
  final List<CulturalItem>? targetItems;

  const CoverEnrichmentDialog({super.key, this.targetItems});

  static Future<void> show(BuildContext context, {List<CulturalItem>? targetItems}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CoverEnrichmentDialog(targetItems: targetItems),
    );
  }

  @override
  State<CoverEnrichmentDialog> createState() => _CoverEnrichmentDialogState();
}

class _CoverEnrichmentDialogState extends State<CoverEnrichmentDialog> {
  final CoverEnrichmentService _service = CoverEnrichmentService();
  StreamSubscription? _sub;

  bool _onlyWithoutCovers = true;
  bool _includeMetadata = true;
  bool _authorizedConsent = false;
  bool _inProgress = false;
  bool _completed = false;

  int _total = 0;
  int _processed = 0;
  int _success = 0;
  int _failed = 0;
  String? _currentTitle;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _sub = _service.progressStream.listen((data) {
      if (!mounted) return;
      setState(() {
        _total = data['total'] as int? ?? 0;
        _processed = data['completed'] as int? ?? 0;
        _success = data['success'] as int? ?? 0;
        _failed = data['failed'] as int? ?? 0;
        _isPaused = data['isPaused'] as bool? ?? false;
        _currentTitle = data['currentTitle'] as String?;
        if (data['isRunning'] == false && _inProgress) {
          _inProgress = false;
          _completed = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_service.isRunning) {
      _service.cancel();
    }
    super.dispose();
  }

  List<CulturalItem> _filterTargetItems(List<CulturalItem> all) {
    if (_onlyWithoutCovers) {
      return all
          .where((i) =>
              (i.localImagePath == null || i.localImagePath!.isEmpty) &&
              (i.coverMotif == null || i.coverMotif!.isEmpty))
          .toList();
    }
    return all;
  }

  Future<void> _startEnrichment() async {
    final state = context.read<NixState>();
    final allItems = widget.targetItems ?? state.userProfile.culturalItems;
    final toProcess = _filterTargetItems(allItems);

    if (toProcess.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma obra elegível para enriquecimento.')),
      );
      Navigator.pop(context);
      return;
    }

    setState(() {
      _inProgress = true;
      _completed = false;
      _total = toProcess.length;
      _processed = 0;
      _success = 0;
      _failed = 0;
    });

    final isTorReady = state.securityGate.isTorAnonymityReady;

    await _service.enrichBatch(
      items: toProcess,
      userConsent: true,
      isTorReady: isTorReady,
      onItemUpdated: (updatedItem) async {
        state.addCulturalItem(updatedItem);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final allItems = widget.targetItems ?? state.userProfile.culturalItems;
    final withoutCoversCount = allItems
        .where((i) =>
            (i.localImagePath == null || i.localImagePath!.isEmpty) &&
            (i.coverMotif == null || i.coverMotif!.isEmpty))
        .length;

    return Dialog(
      backgroundColor: NixColors.surfaceElevatedHigh,
      shape: RoundedRectangleBorder(
        borderRadius: NixTokens.borderModal,
        side: BorderSide(color: NixColors.surfaceBorderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabeçalho
              Row(
                children: [
                  const Icon(Icons.auto_fix_high_rounded, color: Colors.cyanAccent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Enriquecimento de Capas e Metadados',
                      style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (!_inProgress)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),
              const Divider(height: 20),

              if (!_inProgress && !_completed) ...[
                Text(
                  'Identificamos $withoutCoversCount obra(s) sem imagem de capa no seu Acervo.',
                  style: TextStyle(color: NixColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),

                // Opções de seleção
                RadioListTile<bool>(
                  title: Text('Somente obras sem capa ($withoutCoversCount obras)',
                      style: const TextStyle(fontSize: 13)),
                  value: true,
                  groupValue: _onlyWithoutCovers,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _onlyWithoutCovers = v ?? true),
                ),
                RadioListTile<bool>(
                  title: Text('Todas as obras da coleção (${allItems.length} obras)',
                      style: const TextStyle(fontSize: 13)),
                  value: false,
                  groupValue: _onlyWithoutCovers,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _onlyWithoutCovers = v ?? false),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Buscar também sinopses e metadados ausentes',
                      style: TextStyle(fontSize: 13)),
                  value: _includeMetadata,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _includeMetadata = v ?? true),
                ),
                const SizedBox(height: 12),

                // Aviso de Privacidade e Fornecedores Abertos (Seção 4.3 e 4.4)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.shield_outlined, size: 16, color: Colors.amber),
                          SizedBox(width: 6),
                          Text(
                            'Privacidade e Roteamento Tor',
                            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Fontes abertas: Open Library (livros), Wikidata (filmes/animes) e MusicBrainz.\n'
                        'Todas as consultas são isoladas circuito a circuito no Tor. Nenhuma telemetria '
                        'nem cookies são transmitidos. Fornecedores externos podem correlacionar os títulos '
                        'pesquisados ao responder.',
                        style: TextStyle(color: NixColors.textSecondary, fontSize: 11, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                CheckboxListTile(
                  key: const Key('consent_cover_enrichment_checkbox'),
                  title: const Text(
                    'Autorizo a consulta externa via Tor para enriquecimento das obras selecionadas.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  value: _authorizedConsent,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _authorizedConsent = v ?? false),
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const Key('start_cover_enrichment_button'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.cyanAccent.shade700,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: _authorizedConsent ? _startEnrichment : null,
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Autorizar e Iniciar Busca',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ] else if (_inProgress) ...[
                // Estado em execução com barra de progresso e controles (Seção 4.2)
                Text(
                  'Processando obras via circuito Tor...',
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                if (_currentTitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Pesquisando: $_currentTitle',
                    style: TextStyle(color: NixColors.textMuted, fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: _total > 0 ? (_processed / _total).clamp(0.0, 1.0) : null,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent.shade400),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$_processed de $_total processadas',
                        style: TextStyle(color: NixColors.textSecondary, fontSize: 12)),
                    Text('$_success obtidas · $_failed sem capa',
                        style: TextStyle(color: Colors.cyanAccent.shade200, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!_isPaused)
                      OutlinedButton.icon(
                        onPressed: _service.pause,
                        icon: const Icon(Icons.pause_rounded, size: 16),
                        label: const Text('Pausar'),
                      )
                    else
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.cyanAccent.shade700,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: _service.resume,
                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: const Text('Retomar'),
                      ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                      onPressed: _service.cancel,
                      icon: const Icon(Icons.stop_rounded, size: 16),
                      label: const Text('Cancelar'),
                    ),
                  ],
                ),
              ] else if (_completed) ...[
                // Relatório final de conclusão (Seção 4.1)
                const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Enriquecimento Concluído!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_success capa(s) e metadados obtidos e salvos no cache local.\n'
                  '$_failed obra(s) não tiveram correspondência exata.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: NixColors.textSecondary, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Concluir'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
