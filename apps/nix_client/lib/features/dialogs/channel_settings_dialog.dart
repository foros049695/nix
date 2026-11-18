import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';

enum _SettingsTab {
  identity,
  permissions,
  contentProtection,
  admin,
  security,
}

class ChannelSettingsDialog extends StatefulWidget {
  final Channel channel;

  const ChannelSettingsDialog({super.key, required this.channel});

  static Future<void> show(BuildContext context, Channel channel) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (_) => ChannelSettingsDialog(channel: channel),
    );
  }

  @override
  State<ChannelSettingsDialog> createState() => _ChannelSettingsDialogState();
}

class _ChannelSettingsDialogState extends State<ChannelSettingsDialog> {
  _SettingsTab _activeTab = _SettingsTab.identity;

  late TextEditingController _nameController;
  late TextEditingController _topicController;
  late TextEditingController _descController;
  late TextEditingController _inviteLinkController;

  late ChannelPermissions _perms;
  late List<String> _admins;
  late List<String> _moderators;
  late List<String> _bannedMembers;
  late List<String> _auditLogs;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.channel.name);
    _topicController = TextEditingController(text: widget.channel.topic);
    _descController = TextEditingController(text: widget.channel.description);
    _inviteLinkController = TextEditingController(
      text: 'nix://onion/v3/7e3a9f01c45b289d.onion/c/${widget.channel.id}',
    );

    _perms = widget.channel.permissions;
    _admins = List<String>.from(widget.channel.admins);
    _moderators = List<String>.from(widget.channel.moderators);
    _bannedMembers = List<String>.from(widget.channel.bannedMembers);
    _auditLogs = List<String>.from(widget.channel.auditLogs);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    _descController.dispose();
    _inviteLinkController.dispose();
    super.dispose();
  }

  void _save(NixState state) {
    final updated = widget.channel.copyWith(
      name: _nameController.text.trim(),
      topic: _topicController.text.trim(),
      description: _descController.text.trim(),
      permissions: _perms,
      admins: _admins,
      moderators: _moderators,
      bannedMembers: _bannedMembers,
      auditLogs: [
        '${DateTime.now().toIso8601String().substring(11, 19)}: Configurações do canal atualizadas pelo administrador.',
        ..._auditLogs,
      ],
    );
    state.updateChannelSettings(updated);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: NixColors.surfaceCard,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Configurações de #${updated.name} salvas com sucesso!',
          style: const TextStyle(color: NixColors.textPrimary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final accent = context.accentColor;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 720,
          height: 600,
          decoration: BoxDecoration(
            color: NixColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent.withValues(alpha: 0.35),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.9),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
                ),
                child: Row(
                  children: [
                    Icon(widget.channel.icon, color: accent, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Configurações Avançadas · #${widget.channel.name}',
                      style: const TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: NixColors.textMuted),
                      tooltip: 'Fechar (Esc)',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Corpo Principal: Navegação de Categorias + Conteúdo da Aba
              Expanded(
                child: Row(
                  children: [
                    // Coluna de Abas
                    Container(
                      width: 200,
                      decoration: const BoxDecoration(
                        color: NixColors.surfaceSidebar,
                        border: Border(right: BorderSide(color: NixColors.surfaceBorder)),
                      ),
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        children: [
                          _buildTabItem(
                            tab: _SettingsTab.identity,
                            label: 'Identidade e Acesso',
                            icon: Icons.vpn_key_outlined,
                            accent: accent,
                          ),
                          _buildTabItem(
                            tab: _SettingsTab.permissions,
                            label: 'Permissões de Mensagens',
                            icon: Icons.chat_bubble_outline_rounded,
                            accent: accent,
                          ),
                          _buildTabItem(
                            tab: _SettingsTab.contentProtection,
                            label: 'Proteção de Conteúdo',
                            icon: Icons.shield_outlined,
                            accent: accent,
                          ),
                          _buildTabItem(
                            tab: _SettingsTab.admin,
                            label: 'Administração & Logs',
                            icon: Icons.admin_panel_settings_outlined,
                            accent: accent,
                          ),
                          _buildTabItem(
                            tab: _SettingsTab.security,
                            label: 'Segurança & Anti-Spam',
                            icon: Icons.security_rounded,
                            accent: accent,
                          ),
                        ],
                      ),
                    ),

                    // Conteúdo da Categoria Ativa
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        color: NixColors.background,
                        child: _buildActiveTabContent(accent),
                      ),
                    ),
                  ],
                ),
              ),

              // Footer com Ações
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                  border: Border(top: BorderSide(color: NixColors.surfaceBorder)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar', style: TextStyle(color: NixColors.textSecondary)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _save(nixState),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.save_rounded, size: 16),
                          SizedBox(width: 6),
                          Text('Salvar Alterações', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required _SettingsTab tab,
    required String label,
    required IconData icon,
    required Color accent,
  }) {
    final isSelected = _activeTab == tab;
    return InkWell(
      onTap: () => setState(() => _activeTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.12) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? accent : NixColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? NixColors.textPrimary : NixColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(Color accent) {
    switch (_activeTab) {
      case _SettingsTab.identity:
        return _buildIdentityTab(accent);
      case _SettingsTab.permissions:
        return _buildPermissionsTab(accent);
      case _SettingsTab.contentProtection:
        return _buildContentProtectionTab(accent);
      case _SettingsTab.admin:
        return _buildAdminTab(accent);
      case _SettingsTab.security:
        return _buildSecurityTab(accent);
    }
  }

  Widget _buildIdentityTab(Color accent) {
    return ListView(
      children: [
        _buildSectionTitle('IDENTIDADE DO CANAL'),
        const SizedBox(height: 12),
        _buildTextField('Nome do Canal', _nameController, prefixText: '# '),
        const SizedBox(height: 12),
        _buildTextField('Tópico Curto', _topicController),
        const SizedBox(height: 12),
        _buildTextField('Descrição Detalhada', _descController, maxLines: 3),
        const SizedBox(height: 20),

        _buildSectionTitle('ACESSO & CONVITES'),
        const SizedBox(height: 12),
        _buildSwitchTile(
          'Canal Público na Rede Nix',
          'Permite descoberta via catálogo Onion v3.',
          _perms.isPublic,
          (val) => setState(() => _perms = _perms.copyWith(isPublic: val)),
          accent,
        ),
        _buildSwitchTile(
          'Exigir Aprovação de Entrada',
          'Novos membros precisam de autorização de um moderador.',
          _perms.requireApproval,
          (val) => setState(() => _perms = _perms.copyWith(requireApproval: val)),
          accent,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTextField('Link de Convite Onion v3', _inviteLinkController, readOnly: true),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.copy_rounded, color: NixColors.textSecondary),
              tooltip: 'Copiar Link',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _inviteLinkController.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Link de convite Onion copiado!'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPermissionsTab(Color accent) {
    return ListView(
      children: [
        _buildSectionTitle('PERMISSÕES DE MENSAGENS E CONTEÚDO'),
        const SizedBox(height: 12),
        _buildSwitchTile(
          'Enviar Mensagens de Texto',
          'Permitir que membros enviem mensagens comuns.',
          _perms.allowMessages,
          (v) => setState(() => _perms = _perms.copyWith(allowMessages: v)),
          accent,
        ),
        _buildSwitchTile(
          'Enviar Imagens',
          'Permitir upload de fotografias e figuras.',
          _perms.allowImages,
          (v) => setState(() => _perms = _perms.copyWith(allowImages: v)),
          accent,
        ),
        _buildSwitchTile(
          'Enviar Arquivos e Documentos',
          'Permitir anexos binários, PDFs e arquivos canônicos.',
          _perms.allowFiles,
          (v) => setState(() => _perms = _perms.copyWith(allowFiles: v)),
          accent,
        ),
        _buildSwitchTile(
          'Enviar Áudios e Mensagens de Voz',
          'Permitir notas de voz criptografadas.',
          _perms.allowAudio,
          (v) => setState(() => _perms = _perms.copyWith(allowAudio: v)),
          accent,
        ),
        _buildSwitchTile(
          'Permitir Links Externos',
          'Permitir compartilhamento de URLs clearnet e onion.',
          _perms.allowLinks,
          (v) => setState(() => _perms = _perms.copyWith(allowLinks: v)),
          accent,
        ),
        _buildSwitchTile(
          'Permitir Encaminhamento de Mensagens',
          'Membros podem encaminhar mensagens deste canal para outros destinos.',
          _perms.allowForwarding,
          (v) => setState(() => _perms = _perms.copyWith(allowForwarding: v)),
          accent,
        ),
        _buildSwitchTile(
          'Permitir Reações com Emojis',
          'Ativar reações em mensagens.',
          _perms.allowReactions,
          (v) => setState(() => _perms = _perms.copyWith(allowReactions: v)),
          accent,
        ),
        _buildSwitchTile(
          'Permitir Edição de Mensagens',
          'Autores podem editar mensagens enviadas.',
          _perms.allowEditing,
          (v) => setState(() => _perms = _perms.copyWith(allowEditing: v)),
          accent,
        ),
        _buildSwitchTile(
          'Permitir Deleção de Mensagens',
          'Autores podem remover mensagens enviadas.',
          _perms.allowDeletion,
          (v) => setState(() => _perms = _perms.copyWith(allowDeletion: v)),
          accent,
        ),
      ],
    );
  }

  Widget _buildContentProtectionTab(Color accent) {
    return ListView(
      children: [
        _buildSectionTitle('POLÍTICAS DE PROTEÇÃO DE CONTEÚDO'),
        const SizedBox(height: 12),
        _buildSwitchTile(
          'Restringir Encaminhamento & Cópia',
          'Desativa ações de exportar e encaminhar dados confidenciais do canal.',
          _perms.restrictExport,
          (v) => setState(() => _perms = _perms.copyWith(restrictExport: v)),
          accent,
        ),
        _buildSwitchTile(
          'Bloquear Salvamento Local de Mídias',
          'Mídias só podem ser visualizadas na memória volátil, sem persistência em disco.',
          _perms.restrictMediaSaving,
          (v) => setState(() => _perms = _perms.copyWith(restrictMediaSaving: v)),
          accent,
        ),
        _buildSwitchTile(
          'Proteção Contra Capturas de Tela (FLAG_SECURE)',
          'No Android, ativa FLAG_SECURE impedindo screenshots e visualização em alternador de apps.',
          _perms.requestScreenshotProtection,
          (v) => setState(() => _perms = _perms.copyWith(requestScreenshotProtection: v)),
          accent,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: NixColors.textMuted),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nota de Segurança Multiplataforma:\n'
                  '• Android: FLAG_SECURE garante proteção física pelo gerenciador de janelas do sistema operacional.\n'
                  '• Desktop (Linux/Windows/macOS): Proteção técnica absoluta contra gravação de tela não é viável sob X11/Wayland sem permissões de kernel; o Nix ofusca a janela ao perder foco.',
                  style: TextStyle(color: NixColors.textMuted, fontSize: 11, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('RETENÇÃO EFÊMERA DE MENSAGENS'),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: _perms.ephemeralRetentionMinutes,
          dropdownColor: NixColors.surfaceCard,
          decoration: InputDecoration(
            labelText: 'Tempo de Retenção Automática',
            labelStyle: const TextStyle(color: NixColors.textMuted),
            filled: true,
            fillColor: NixColors.surfaceCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Permanente (Sem auto-destruição)', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 5, child: Text('5 minutos', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 60, child: Text('1 hora', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 1440, child: Text('24 horas (1 dia)', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 10080, child: Text('7 dias (Padrão Relay)', style: TextStyle(color: Colors.white))),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _perms = _perms.copyWith(ephemeralRetentionMinutes: val));
            }
          },
        ),
      ],
    );
  }

  Widget _buildAdminTab(Color accent) {
    return ListView(
      children: [
        _buildSectionTitle('ADMINISTRADORES E MODERADORES'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dono do Canal: ${widget.channel.ownerFingerprint}', style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Administradores (${_admins.length}): ${_admins.join(', ')}', style: const TextStyle(color: NixColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 4),
              Text('Moderadores (${_moderators.length}): ${_moderators.join(', ')}', style: const TextStyle(color: NixColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 4),
              Text('Membros Banidos (${_bannedMembers.length}): ${_bannedMembers.isEmpty ? 'Nenhum' : _bannedMembers.join(', ')}', style: const TextStyle(color: NixColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('LOGS DE AUDITORIA CRIPTOGRÁFICA'),
        const SizedBox(height: 8),
        Container(
          height: 180,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: NixColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: ListView.separated(
            itemCount: _auditLogs.length,
            separatorBuilder: (_, __) => const Divider(height: 8, color: NixColors.surfaceBorder),
            itemBuilder: (ctx, idx) {
              return Text(
                _auditLogs[idx],
                style: const TextStyle(
                  color: NixColors.textSecondary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityTab(Color accent) {
    return ListView(
      children: [
        _buildSectionTitle('SEGURANÇA E COMBATE A SPAM'),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: _perms.slowModeSeconds,
          dropdownColor: NixColors.surfaceCard,
          decoration: InputDecoration(
            labelText: 'Modo Lento (Slow Mode) - Intervalo entre Mensagens',
            labelStyle: const TextStyle(color: NixColors.textMuted),
            filled: true,
            fillColor: NixColors.surfaceCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Desativado (Tempo real)', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 5, child: Text('5 segundos', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 15, child: Text('15 segundos', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 30, child: Text('30 segundos', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 60, child: Text('1 minuto', style: TextStyle(color: Colors.white))),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _perms = _perms.copyWith(slowModeSeconds: val));
            }
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          value: _perms.maxFileSizeMb,
          dropdownColor: NixColors.surfaceCard,
          decoration: InputDecoration(
            labelText: 'Tamanho Máximo Permitido por Arquivo',
            labelStyle: const TextStyle(color: NixColors.textMuted),
            filled: true,
            fillColor: NixColors.surfaceCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: const [
            DropdownMenuItem(value: 10, child: Text('10 MB (Máxima rapidez sobre Tor)', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 50, child: Text('50 MB (Recomendado)', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 100, child: Text('100 MB (Limite máximo)', style: TextStyle(color: Colors.white))),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _perms = _perms.copyWith(maxFileSizeMb: val));
            }
          },
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: NixColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    String? prefixText,
    int maxLines = 1,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      readOnly: readOnly,
      style: const TextStyle(color: NixColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: NixColors.textMuted, fontSize: 12),
        prefixText: prefixText,
        prefixStyle: const TextStyle(color: NixColors.textMuted),
        filled: true,
        fillColor: NixColors.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: NixColors.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: NixColors.surfaceBorder),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
    Color accent,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NixColors.surfaceBorder),
      ),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(color: NixColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(color: NixColors.textMuted, fontSize: 11)),
        value: value,
        activeColor: accent,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      ),
    );
  }
}
