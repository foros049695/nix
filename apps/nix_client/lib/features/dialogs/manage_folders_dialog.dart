import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/space.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Mapeamento central de ícones para Pastas estilo Telegram Desktop.
IconData folderIconFromName(String name) {
  switch (name) {
    case 'shield':
      return Icons.shield_outlined;
    case 'code':
      return Icons.code_rounded;
    case 'chat':
      return Icons.chat_bubble_outline_rounded;
    case 'star':
      return Icons.star_outline_rounded;
    case 'lock':
      return Icons.lock_outline_rounded;
    case 'bookmark':
      return Icons.bookmark_outline_rounded;
    case 'folder':
    default:
      return Icons.folder_outlined;
  }
}

/// Modal completo para Criar, Nomear, Escolher Ícone/Cor, Editar, Reordenar e Excluir Pastas.
/// Excluir uma pasta jamais exclui as conversas ou espaços vinculados (Seção 4).
class ManageFoldersDialog extends StatefulWidget {
  const ManageFoldersDialog({super.key});

  @override
  State<ManageFoldersDialog> createState() => _ManageFoldersDialogState();
}

class _ManageFoldersDialogState extends State<ManageFoldersDialog> {
  final TextEditingController _folderNameController = TextEditingController();
  final Set<String> _selectedSpaceIds = {};
  final Set<String> _selectedConvIds = {};
  String _selectedIcon = 'folder';
  int _selectedColorValue = 0xFFFFC928;
  String? _editingFolderId;

  static const _icons = [
    ('folder', 'Pasta', Icons.folder_outlined),
    ('shield', 'Segurança', Icons.shield_outlined),
    ('code', 'Código', Icons.code_rounded),
    ('chat', 'Chats', Icons.chat_bubble_outline_rounded),
    ('star', 'Favoritos', Icons.star_outline_rounded),
    ('lock', 'Privado', Icons.lock_outline_rounded),
    ('bookmark', 'Acervo', Icons.bookmark_outline_rounded),
  ];

  static const _colors = [
    0xFFFFC928, // Nix Yellow
    0xFF38BDF8, // Sky
    0xFF10B981, // Emerald
    0xFF8B5CF6, // Violet
    0xFFF43F5E, // Rose
    0xFFF59E0B, // Amber
  ];

  @override
  void dispose() {
    _folderNameController.dispose();
    super.dispose();
  }

  void _startEditing(SpaceFolder folder) {
    setState(() {
      _editingFolderId = folder.id;
      _folderNameController.text = folder.name;
      _selectedIcon = folder.iconName;
      _selectedColorValue = folder.colorValue;
      _selectedSpaceIds
        ..clear()
        ..addAll(folder.spaceIds);
      _selectedConvIds
        ..clear()
        ..addAll(folder.conversationIds);
    });
  }

  void _resetForm() {
    setState(() {
      _editingFolderId = null;
      _folderNameController.clear();
      _selectedIcon = 'folder';
      _selectedColorValue = 0xFFFFC928;
      _selectedSpaceIds.clear();
      _selectedConvIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final spaces = nixState.spaces;
    final dms = nixState.directMessages.where((d) => !d.isSavedMessages).toList();
    final folders = nixState.folders;
    final accent = context.accentColor;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.folder_copy_outlined, color: context.accentTextColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _editingFolderId != null ? 'Editar Pasta de Conversas' : 'Gerenciar Pastas & Grupos',
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Organize espaços, canais e conversas privadas em pastas personalizáveis. Excluir uma pasta nunca apaga suas conversas.',
                style: TextStyle(color: NixColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Text('NOME DA PASTA', style: NixTokens.labelUppercase()),
              const SizedBox(height: 6),
              TextField(
                key: const Key('folder_name_input'),
                controller: _folderNameController,
                style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'ex: Estudos, Infraestrutura, Privado...',
                ),
              ),
              const SizedBox(height: 14),
              Text('ÍCONE DA PASTA', style: NixTokens.labelUppercase()),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _icons.map((item) {
                  final active = _selectedIcon == item.$1;
                  return InkWell(
                    onTap: () => setState(() => _selectedIcon = item.$1),
                    borderRadius: NixTokens.borderSm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: active ? accent.withValues(alpha: 0.2) : NixColors.surfaceElevated,
                        borderRadius: NixTokens.borderSm,
                        border: Border.all(
                          color: active ? accent : NixColors.surfaceBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.$3,
                            size: 15,
                            color: active ? Color(_selectedColorValue) : NixColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            item.$2,
                            style: TextStyle(
                              color: active ? NixColors.textPrimary : NixColors.textSecondary,
                              fontSize: 11.5,
                              fontWeight: active ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text('COR DO INDICADOR', style: NixTokens.labelUppercase()),
              const SizedBox(height: 6),
              Row(
                children: _colors.map((cVal) {
                  final active = _selectedColorValue == cVal;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () => setState(() => _selectedColorValue = cVal),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Color(cVal),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: active ? NixColors.textPrimary : Colors.transparent,
                            width: 2.2,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text('ESPAÇOS E GRUPOS', style: NixTokens.labelUppercase()),
              ...spaces.map((sp) {
                final checked = _selectedSpaceIds.contains(sp.id);
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: checked,
                  title: Text(
                    sp.name,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
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
              const SizedBox(height: 8),
              Text('CONVERSAS PRIVADAS INCLUÍDAS', style: NixTokens.labelUppercase()),
              ...dms.map((dm) {
                final checked = _selectedConvIds.contains(dm.id);
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: checked,
                  title: Text(
                    dm.peerName,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedConvIds.add(dm.id);
                      } else {
                        _selectedConvIds.remove(dm.id);
                      }
                    });
                  },
                );
              }),
              if (folders.isNotEmpty) ...[
                Divider(height: 24, color: NixColors.surfaceBorder),
                Text('PASTAS EXISTENTES (${folders.length})', style: NixTokens.labelUppercase()),
                const SizedBox(height: 8),
                ...List.generate(folders.length, (index) {
                  final f = folders[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: NixColors.surfaceElevated,
                      borderRadius: NixTokens.borderSm,
                      border: Border.all(color: NixColors.surfaceBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(folderIconFromName(f.iconName), size: 16, color: Color(f.colorValue)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${f.name} · ${f.spaceIds.length} espaços · ${f.conversationIds.length} chats',
                            style: TextStyle(color: NixColors.textPrimary, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.arrow_upward_rounded, size: 15, color: NixColors.textMuted),
                          tooltip: 'Subir ordem',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          onPressed: index > 0
                              ? () => nixState.reorderFolders(index, index - 1)
                              : null,
                        ),
                        IconButton(
                          icon: Icon(Icons.arrow_downward_rounded, size: 15, color: NixColors.textMuted),
                          tooltip: 'Descer ordem',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          onPressed: index < folders.length - 1
                              ? () => nixState.reorderFolders(index, index + 2)
                              : null,
                        ),
                        IconButton(
                          icon: Icon(Icons.edit_outlined, size: 15, color: context.accentTextColor),
                          tooltip: 'Editar pasta',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          onPressed: () => _startEditing(f),
                        ),
                        IconButton(
                          key: Key('delete_folder_${f.id}'),
                          icon: Icon(Icons.delete_outline_rounded, size: 15, color: NixColors.accentDanger),
                          tooltip: 'Excluir pasta (preserva conversas)',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          onPressed: () => nixState.dissolveFolder(f.id),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_editingFolderId != null)
          TextButton(
            onPressed: _resetForm,
            child: Text('Limpar Edição', style: TextStyle(color: NixColors.textSecondary)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Fechar', style: TextStyle(color: NixColors.textMuted)),
        ),
        ElevatedButton(
          key: const Key('save_folder_button'),
          onPressed: (_selectedSpaceIds.isEmpty && _selectedConvIds.isEmpty) ||
                  _folderNameController.text.trim().isEmpty
              ? null
              : () {
                  if (_editingFolderId != null) {
                    nixState.updateSpaceFolder(
                      SpaceFolder(
                        id: _editingFolderId!,
                        name: _folderNameController.text.trim(),
                        iconName: _selectedIcon,
                        colorValue: _selectedColorValue,
                        spaceIds: _selectedSpaceIds.toList(),
                        conversationIds: _selectedConvIds.toList(),
                        isExpanded: true,
                      ),
                    );
                    _resetForm();
                  } else {
                    nixState.createSpaceFolder(
                      _folderNameController.text.trim(),
                      _selectedSpaceIds.toList(),
                      iconName: _selectedIcon,
                      colorValue: _selectedColorValue,
                      conversationIds: _selectedConvIds.toList(),
                    );
                    _resetForm();
                  }
                },
          child: Text(_editingFolderId != null ? 'Salvar Alterações' : 'Criar Pasta'),
        ),
      ],
    );
  }
}
