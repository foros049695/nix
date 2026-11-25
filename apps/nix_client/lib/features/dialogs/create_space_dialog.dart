import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../navigation/workspace_image.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import 'nix_symbol_picker.dart';

class CreateSpaceDialog extends StatefulWidget {
  const CreateSpaceDialog({super.key});

  @override
  State<CreateSpaceDialog> createState() => _CreateSpaceDialogState();
}

class _CreateSpaceDialogState extends State<CreateSpaceDialog> {
  String? _imagePath;
  String _format = 'conventional';
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedEmoji = 'i:shield';

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.read<NixState>();

    return AlertDialog(
      title: const Text('Criar Novo Espaço / Comunidade'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: _format,
                decoration: const InputDecoration(labelText: 'Formato do espaço'),
                items: const [
                  DropdownMenuItem(value: 'conventional', child: Text('Grupo convencional')),
                  DropdownMenuItem(value: 'topics', child: Text('Grupo com tópicos')),
                  DropdownMenuItem(value: 'announcement', child: Text('Canal de transmissão')),
                ],
                onChanged: (value) => setState(() => _format = value ?? 'conventional'),
              ),
              if (_format == 'announcement') ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: NixColors.accentCyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: NixColors.accentCyan.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.campaign_outlined, size: 16, color: NixColors.accentCyan),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Canal estilo Telegram: somente administradores autorizados publicam. Membros acompanham e reagem.',
                          style: TextStyle(color: NixColors.accentCyan, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'ÍCONE DO ESPAÇO',
                style: TextStyle(
                    color: NixColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final value =
                      await showNixSymbolPicker(context, _selectedEmoji);
                  if (mounted && value != null) {
                    setState(() => _selectedEmoji = value);
                  }
                },
                icon: NixSymbol(_selectedEmoji),
                label: const Text('Escolher ícone ou emoji'),
              ),
              const SizedBox(height: 12),
              WorkspaceImageField(path: _imagePath, onChanged: (path) => setState(() => _imagePath = path)),
              const SizedBox(height: 16),
              Text(
                'NOME DO ESPAÇO',
                style: TextStyle(
                    color: NixColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'ex: Célula Tática Sul',
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'DESCRIÇÃO / FINALIDADE',
                style: TextStyle(
                    color: NixColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _descController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Descreva os objetivos deste espaço soberano...',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancelar', style: TextStyle(color: NixColors.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            if (_nameController.text.trim().isNotEmpty) {
              nixState.createSpace(
                customImagePath: _imagePath,
                withTopics: _format == 'topics',
                isAnnouncementChannel: _format == 'announcement',
                name: _nameController.text.trim(),
                description: _descController.text.trim(),
                emoji: _selectedEmoji,
              );
              Navigator.pop(context);
            }
          },
          child: const Text('Criar Espaço',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
