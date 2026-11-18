import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Modal para unir grupos/espaços em Pastas (Folders) no Dock Lateral (Estilo Discord / Android).
class ManageFoldersDialog extends StatefulWidget {
  const ManageFoldersDialog({super.key});

  @override
  State<ManageFoldersDialog> createState() => _ManageFoldersDialogState();
}

class _ManageFoldersDialogState extends State<ManageFoldersDialog> {
  final TextEditingController _folderNameController =
      TextEditingController(text: 'Pasta de Operações');
  final Set<String> _selectedSpaceIds = {};

  @override
  void dispose() {
    _folderNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final spaces = nixState.spaces;
    final folders = nixState.folders;

    return AlertDialog(
      title: const Text('Unir Grupos em Pasta'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Agrupe duas ou mais comunidades em uma pasta expansível no dock lateral.',
                style: TextStyle(color: NixColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Text('NOME DA PASTA', style: NixTokens.labelUppercase()),
              const SizedBox(height: 6),
              TextField(
                controller: _folderNameController,
                decoration: const InputDecoration(
                  hintText: 'ex: Infraestrutura & Cripto',
                ),
              ),
              const SizedBox(height: 16),
              Text('SELECIONE OS GRUPOS PARA UNIR', style: NixTokens.labelUppercase()),
              const SizedBox(height: 8),
              ...spaces.map((sp) {
                final checked = _selectedSpaceIds.contains(sp.id);
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: Colors.white,
                  checkColor: Colors.black,
                  value: checked,
                  title: Text(
                    sp.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    sp.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: NixColors.textMuted, fontSize: 11),
                  ),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedSpaceIds.add(sp.id);
                      } else {
                        _selectedSpaceIds.remove(sp.id);
                      }
                    });
                  },
                );
              }),
              if (folders.isNotEmpty) ...[
                const Divider(height: 24, color: NixColors.surfaceBorder),
                Text('PASTAS EXISTENTES (${folders.length})', style: NixTokens.labelUppercase()),
                const SizedBox(height: 8),
                ...folders.map((f) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: NixColors.surfaceSidebar,
                        borderRadius: NixTokens.borderSm,
                        border: Border.all(color: NixColors.surfaceBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_outlined, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${f.name} (${f.spaceIds.length} grupos)',
                              style: const TextStyle(color: Colors.white, fontSize: 12.5),
                            ),
                          ),
                          TextButton(
                            onPressed: () => nixState.dissolveFolder(f.id),
                            child: const Text(
                              'Desagrupar',
                              style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: NixColors.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: NixTokens.borderSm),
          ),
          onPressed: _selectedSpaceIds.isEmpty
              ? null
              : () {
                  nixState.createSpaceFolder(
                    _folderNameController.text,
                    _selectedSpaceIds.toList(),
                  );
                  Navigator.pop(context);
                },
          child: const Text('Criar Pasta', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
