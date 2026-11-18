import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';

class CreateChannelDialog extends StatefulWidget {
  final String? defaultCategory;

  const CreateChannelDialog({super.key, this.defaultCategory});

  @override
  State<CreateChannelDialog> createState() => _CreateChannelDialogState();
}

class _CreateChannelDialogState extends State<CreateChannelDialog> {
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();
  ChannelType _selectedType = ChannelType.text;
  late String _selectedCategory;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.defaultCategory ?? '💬 TÓPICOS DE TEXTO';
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
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TIPO DE SALA',
                style: TextStyle(color: NixColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildTypeOption(
                type: ChannelType.text,
                title: 'Sala de Texto / Tópico',
                subtitle: 'Troca de mensagens E2EE, mídias e arquivos temporários.',
                icon: Icons.tag,
                categoryDefault: '💬 TÓPICOS DE TEXTO',
              ),
              const SizedBox(height: 6),
              _buildTypeOption(
                type: ChannelType.voice,
                title: 'Sala de Call & Áudio',
                subtitle: 'Comunicação por voz criptografada fim a fim via Onion v3.',
                icon: Icons.volume_up_rounded,
                categoryDefault: '🔊 SALAS DE VOZ & CALL',
              ),
              const SizedBox(height: 6),
              _buildTypeOption(
                type: ChannelType.publication,
                title: 'Sala de Publicação (Nix Archive)',
                subtitle: 'Artigos canônicos Markdown, afirmações (claims) e refutações.',
                icon: Icons.auto_stories_rounded,
                categoryDefault: '📜 NIX ARCHIVE (PUBLICAÇÕES)',
              ),
              const SizedBox(height: 16),
              const Text(
                'NOME DA SALA',
                style: TextStyle(color: NixColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: _selectedType == ChannelType.voice ? 'ex: Call Tática 01' : 'ex: desenvolvimento-core',
                  prefixIcon: Icon(
                    _selectedType == ChannelType.text ? Icons.tag : (_selectedType == ChannelType.voice ? Icons.volume_up : Icons.auto_stories),
                    size: 18,
                    color: NixColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'TÓPICO / DESCRIÇÃO (OPCIONAL)',
                style: TextStyle(color: NixColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
              ),
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
          child: const Text('Cancelar', style: TextStyle(color: NixColors.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: NixColors.accentGreen,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            if (_nameController.text.trim().isNotEmpty) {
              nixState.createChannel(
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? NixColors.surfaceCardHover : NixColors.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? NixColors.accentGreen : NixColors.surfaceBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? NixColors.accentGreen : NixColors.textSecondary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : NixColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: NixColors.textMuted, fontSize: 11),
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
