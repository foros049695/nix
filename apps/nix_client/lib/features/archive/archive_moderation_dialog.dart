import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/archive/nix_archive_service.dart';

class ArchiveModerationDialog extends StatefulWidget {
  final NixArchiveService service;
  final VoidCallback onChanged;

  const ArchiveModerationDialog({
    super.key,
    required this.service,
    required this.onChanged,
  });

  @override
  State<ArchiveModerationDialog> createState() =>
      _ArchiveModerationDialogState();
}

class _ArchiveModerationDialogState extends State<ArchiveModerationDialog> {
  late Future<List<Map<String, dynamic>>> _authors =
      widget.service.archiveRepo.listModeratedAuthors();
  bool _saving = false;
  String? _error;

  Future<void> _restore(Uint8List author) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.unmoderateAuthor(author);
      widget.onChanged();
      if (!mounted) return;
      setState(
          () => _authors = widget.service.archiveRepo.listModeratedAuthors());
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Falha ao remover a moderação local.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('Autores silenciados ou bloqueados'),
        content: SizedBox(
          width: 420,
          child: FutureBuilder(
            future: _authors,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('Falha ao carregar a moderação do cofre.');
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final authors = snapshot.data ?? [];
              if (authors.isEmpty) {
                return const Text('Nenhum autor silenciado ou bloqueado.');
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in authors) _authorRow(row),
                  if (_error != null) Text(_error!),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      );

  Widget _authorRow(Map<String, dynamic> row) {
    final author = Uint8List.fromList(row['author_public'] as List<int>);
    final fingerprint =
        author.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row['status'] == 'blocked' ? 'Bloqueado' : 'Silenciado'),
          SelectableText(fingerprint,
              style: const TextStyle(fontFamily: 'monospace')),
          TextButton(
            onPressed: _saving ? null : () => _restore(author),
            child: const Text('Remover moderação'),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
