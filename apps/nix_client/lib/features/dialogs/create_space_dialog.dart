import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';

class CreateSpaceDialog extends StatefulWidget {
  const CreateSpaceDialog({super.key});

  @override
  State<CreateSpaceDialog> createState() => _CreateSpaceDialogState();
}

class _CreateSpaceDialogState extends State<CreateSpaceDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedEmoji = '🛡️';

  final List<String> _emojis = ['🏴‍☠️', '🛡️', '📡', '🪙', '🔒', '⚡', '🌐', '🦊', '🦉', '⚔️'];

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
                style: TextStyle(color: NixColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _emojis.map((emoji) {
                  final isSelected = _selectedEmoji == emoji;
                  return InkWell(
                    onTap: () => setState(() => _selectedEmoji = emoji),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected ? NixColors.surfaceCardHover : NixColors.surfaceCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? NixColors.accentGreen : NixColors.surfaceBorder,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(
                'NOME DO ESPAÇO',
                style: TextStyle(color: NixColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
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
                style: TextStyle(color: NixColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
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
            backgroundColor: NixColors.accentGreen,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
          child: const Text('Criar Espaço', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
