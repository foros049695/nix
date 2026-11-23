import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/media/collection_importer.dart';
import '../../core/security/file_picker_adapter.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

class CollectionImportDialog extends StatefulWidget {
  final String? initialContent;
  final String? initialFileName;

  const CollectionImportDialog({
    super.key,
    this.initialContent,
    this.initialFileName,
  });

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const CollectionImportDialog(),
    );
  }

  @override
  State<CollectionImportDialog> createState() => _CollectionImportDialogState();
}

class _CollectionImportDialogState extends State<CollectionImportDialog> {
  ImportedCollectionPreview? _preview;
  String? _errorMessage;
  bool _busy = false;
  bool _skipDuplicates = true;
  String? _loadedFileName;

  @override
  void initState() {
    super.initState();
    if (widget.initialContent != null && widget.initialContent!.isNotEmpty) {
      _processContent(
        widget.initialContent!,
        widget.initialFileName ?? 'export.csv',
      );
    }
  }

  void _processContent(String content, String fileName) {
    setState(() {
      _busy = true;
      _errorMessage = null;
      _loadedFileName = fileName;
    });

    try {
      final state = context.read<NixState>();
      final preview = CollectionImporter.parse(
        rawContent: content,
        fileName: fileName,
        existingItems: state.userProfile.culturalItems,
      );

      setState(() {
        _preview = preview;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _preview = null;
        _errorMessage = e.toString().replaceFirst('FormatException: ', '');
        _busy = false;
      });
    }
  }

  Future<void> _pickFile() async {
    setState(() => _busy = true);
    try {
      final choices = await const CrossPlatformFilePickerAdapter().pickAttachments(
        allowedExtensions: const ['csv', 'html', 'htm', 'xml', 'txt'],
        allowMultiple: false,
      );

      if (choices.isEmpty) {
        setState(() => _busy = false);
        return;
      }

      final path = choices.single;
      final file = File(path);
      if (!await file.exists()) {
        throw const FormatException('O arquivo selecionado não foi encontrado no dispositivo.');
      }

      final fileName = file.uri.pathSegments.last;
      final content = await file.readAsString();
      _processContent(content, fileName);
    } catch (e) {
      setState(() {
        _errorMessage = 'Falha ao ler arquivo: $e';
        _busy = false;
      });
    }
  }

  void _confirmImport() {
    final preview = _preview;
    if (preview == null || preview.items.isEmpty) return;

    final state = context.read<NixState>();
    final itemsToImport = preview.items.map((i) => i.toCulturalItem()).toList();
    final count = state.importCulturalItems(
      itemsToImport,
      skipDuplicates: _skipDuplicates,
    );

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? '$count obras importadas com sucesso para o seu Acervo Pessoal!'
              : 'Nenhuma nova obra adicionada (todas já existiam no acervo).',
        ),
        backgroundColor: NixColors.surfaceElevatedHigh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: NixColors.surfaceElevatedHigh,
      shape: RoundedRectangleBorder(borderRadius: NixTokens.borderLg),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabeçalho
              Row(
                children: [
                  const Icon(Icons.file_upload_outlined, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Importar Coleção Cultural',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Letterboxd, Goodreads, MyAnimeList ou CSV/HTML local',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 20),

              // Erro ou Carregando
              if (_busy) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ] else if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NixColors.accentDanger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: NixColors.accentDanger.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: NixColors.accentDanger, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: NixColors.accentDanger, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Estado inicial: selecionar arquivo
              if (_preview == null && !_busy) ...[
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open_rounded, size: 48, color: NixColors.textMuted),
                        const SizedBox(height: 12),
                        const Text(
                          'Selecione um arquivo de exportação',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Suporte nativo offline a CSV e HTML sem envio a servidores externos.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: const Key('pick_import_file_button'),
                          onPressed: _pickFile,
                          icon: const Icon(Icons.attach_file_rounded, size: 18),
                          label: const Text('Escolher arquivo CSV ou HTML'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Visualização dos dados analisados
              if (_preview != null && !_busy) ...[
                // Banner com fonte e estatísticas
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: NixColors.surfaceCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: NixColors.surfaceBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: NixColors.accentCyan.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _preview!.sourceLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: NixColors.accentCyan,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_loadedFileName != null)
                            Expanded(
                              child: Text(
                                _loadedFileName!,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          TextButton.icon(
                            onPressed: _pickFile,
                            icon: const Icon(Icons.refresh_rounded, size: 14),
                            label: const Text('Trocar', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_preview!.items.length} obras encontradas'
                        '${_preview!.duplicateCount > 0 ? ' · ${_preview!.duplicateCount} já existentes no seu acervo' : ''}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      if (_preview!.detectedColumns.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Campos mapeados: ${_preview!.detectedColumns.take(6).join(', ')}${_preview!.detectedColumns.length > 6 ? '...' : ''}',
                          style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Checkbox para ignorar duplicatas
                if (_preview!.duplicateCount > 0)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Ignorar obras que já estão no meu Acervo',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _skipDuplicates,
                    onChanged: (val) => setState(() => _skipDuplicates = val ?? true),
                  ),

                // Lista de Itens Pré-visualizados
                const SizedBox(height: 6),
                const Text(
                  'Pré-visualização das obras:',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),

                Expanded(
                  child: ListView.separated(
                    itemCount: _preview!.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 6),
                    itemBuilder: (context, idx) {
                      final item = _preview!.items[idx];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: NixColors.surfaceCard,
                          child: Text(
                            item.title.isNotEmpty ? item.title[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          item.title,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${item.category.name} · ${item.creatorOrYear}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.isPotentialDuplicate)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Já no acervo',
                                  style: TextStyle(fontSize: 9.5, color: Colors.amber, fontWeight: FontWeight.bold),
                                ),
                              ),
                            Text(
                              '★ ${item.rating}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 12),
                // Botões de Ação
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const Key('confirm_collection_import_button'),
                      onPressed: _confirmImport,
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: Text('Importar para o Acervo (${_skipDuplicates ? _preview!.items.length - _preview!.duplicateCount : _preview!.items.length})'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
