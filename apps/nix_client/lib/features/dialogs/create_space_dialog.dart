import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import 'nix_symbol_picker.dart';

class CreateSpaceDialog extends StatefulWidget {
  const CreateSpaceDialog({super.key});

  @override
  State<CreateSpaceDialog> createState() => _CreateSpaceDialogState();
}

class _CreateSpaceDialogState extends State<CreateSpaceDialog> {
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
