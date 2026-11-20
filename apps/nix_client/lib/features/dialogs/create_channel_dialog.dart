import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../navigation/workspace_image.dart';
import '../../core/models/channel.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

class CreateChannelDialog extends StatefulWidget {
  final String? defaultCategory;

  const CreateChannelDialog({super.key, this.defaultCategory});

  @override
  State<CreateChannelDialog> createState() => _CreateChannelDialogState();
}

class _CreateChannelDialogState extends State<CreateChannelDialog> {
  String? _imagePath;
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();
  ChannelType _selectedType = ChannelType.text;
  late String _selectedCategory;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.defaultCategory ?? 'COMUNIDADE';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.read<NixState>();

    return AlertDialog(
      title: const Text('Criar Nova Sala / Tópico'),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TIPO DE SALA', style: NixTokens.labelUppercase()),
              const SizedBox(height: 8),
              _buildTypeOption(
                type: ChannelType.text,
                title: 'Sala de Texto Padrão',
                subtitle: 'Conversas E2EE em fluxo contínuo, mídias e arquivos temporários.',
                icon: Icons.tag_rounded,
                categoryDefault: 'COMUNIDADE',
              ),
              const SizedBox(height: 6),
              _buildTypeOption(
                type: ChannelType.forum,
                title: 'Fórum / Tópicos Interativos',
                subtitle: 'Grade de cartões com imagens 2x2 e chat lateral dividido (Split-Chat).',
                icon: Icons.forum_outlined,
                categoryDefault: 'TÓPICOS INTERATIVOS',
              ),
              const SizedBox(height: 6),
              _buildTypeOption(
                type: ChannelType.voice,
                title: 'Sala de Call & Voz',
                subtitle: 'Comunicação por áudio criptografada fim a fim via Onion v3.',
                icon: Icons.volume_up_outlined,
                categoryDefault: 'CHATS DE VOZ',
              ),
              const SizedBox(height: 6),
              _buildTypeOption(
                type: ChannelType.publication,
                title: 'Sala de Publicação (Nix Archive)',
                subtitle: 'Artigos canônicos Markdown, afirmações (claims) e refutações.',
                icon: Icons.menu_book_outlined,
                categoryDefault: 'NIX ARCHIVE',
              ),
              const SizedBox(height: 12),
              WorkspaceImageField(path: _imagePath, onChanged: (path) => setState(() => _imagePath = path)),
              const SizedBox(height: 16),
              Text('NOME DA SALA', style: NixTokens.labelUppercase()),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: _selectedType == ChannelType.voice
                      ? 'ex: Voz 3 · Alinhamento'
                      : 'ex: analises-e-achados',
                  prefixIcon: Icon(Icons.tag_rounded, size: 18, color: NixColors.textSecondary),
                ),
              ),
              const SizedBox(height: 14),
              Text('TÓPICO / DESCRIÇÃO (OPCIONAL)', style: NixTokens.labelUppercase()),
              const SizedBox(height: 6),
              TextField(
                controller: _topicController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Defina a finalidade desta sala para os membros...',
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
            backgroundColor: NixColors.textPrimary,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: NixTokens.borderSm),
          ),
          onPressed: () {
            if (_nameController.text.trim().isNotEmpty) {
              nixState.createChannel(
                customImagePath: _imagePath,
                name: _nameController.text.trim(),
                type: _selectedType,
                topic: _topicController.text.trim(),
                category: _selectedCategory,
              );
              Navigator.pop(context);
            }
          },
          child: const Text('Criar Sala', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildTypeOption({
    required ChannelType type,
    required String title,
    required String subtitle,
    required IconData icon,
    required String categoryDefault,
  }) {
    final isSelected = _selectedType == type;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedType = type;
          _selectedCategory = categoryDefault;
        });
      },
      borderRadius: NixTokens.borderSm,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? NixColors.surfaceActive : NixColors.surfaceSidebar,
          borderRadius: NixTokens.borderSm,
          border: Border.all(
            color: isSelected ? NixColors.textPrimary : NixColors.surfaceBorder,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? NixColors.textPrimary : NixColors.textSecondary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? NixColors.textPrimary : NixColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
