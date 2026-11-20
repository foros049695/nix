import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nix_surfaces.dart';
import '../navigation/workspace_image.dart';
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
  final bool fullScreen;

  const ChannelSettingsDialog({super.key, required this.channel, this.fullScreen = false});

  static Future<void> show(BuildContext context, Channel channel) {
    if (MediaQuery.sizeOf(context).width < nixDesktopBreakpoint) {
      return Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChannelSettingsDialog(channel: channel, fullScreen: true),
      ));
    }
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => ChannelSettingsDialog(channel: channel),
    );
  }

  @override
  State<ChannelSettingsDialog> createState() => _ChannelSettingsDialogState();
}

class _ChannelSettingsDialogState extends State<ChannelSettingsDialog> {
  _SettingsTab _activeTab = _SettingsTab.identity;
  _SettingsTab? _compactTab;
  late String? _imagePath = widget.channel.customImagePath;

  static const _sections = [
    (_SettingsTab.identity, Icons.vpn_key_outlined, 'Identidade e acesso'),
    (_SettingsTab.permissions, Icons.chat_bubble_outline_rounded, 'Permissões de Mensagens'),
    (_SettingsTab.contentProtection, Icons.shield_outlined, 'Proteção de Conteúdo'),
    (_SettingsTab.admin, Icons.admin_panel_settings_outlined, 'Membros, Admin & Logs'),
    (_SettingsTab.security, Icons.security_rounded, 'Limites & Anti-Spam'),
  ];

  late TextEditingController _nameController;
  late TextEditingController _topicController;
  late TextEditingController _descController;
  bool _saving = false;
  late bool _topics = widget.channel.type == ChannelType.forum;

  late ChannelPermissions _perms;
  late List<String> _admins;
  late List<String> _moderators;
  late List<String> _mutedMembers;
  late List<String> _bannedMembers;
  late List<String> _auditLogs;

  @override
  void initState() {
    super.initState();
    final c = widget.channel;
    _nameController = TextEditingController(text: c.name);
    _topicController = TextEditingController(text: c.topic);
    _descController = TextEditingController(text: c.description);
    _perms = c.permissions;
    _admins = List<String>.from(c.admins);
    _moderators = List<String>.from(c.moderators);
    _mutedMembers = List<String>.from(c.mutedMembers);
    _bannedMembers = List<String>.from(c.bannedMembers);
    _auditLogs = List<String>.from(c.auditLogs);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save(NixState state) async {
    if (_saving || !state.canManageChannelSettings(widget.channel.id)) return;
    setState(() => _saving = true);
    if (_perms.isPublic != widget.channel.permissions.isPublic ||
        _perms.requireApproval != widget.channel.permissions.requireApproval) {
      final allowed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(_perms.isPublic ? 'Confirmar canal público' : 'Confirmar canal privado'),
          content: Text(_perms.isPublic
              ? 'O canal poderá aparecer em Explorar. ${_perms.requireApproval ? "Novas entradas exigem aprovação." : "A aprovação manual ficará desativada."}'
              : 'O canal será removido de Explorar. Cópias já compartilhadas continuam nos dispositivos de quem as recebeu.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Confirmar')),
          ],
        ),
      );
      if (!mounted) return;
      if (allowed != true) {
        setState(() => _saving = false);
        return;
      }
    }

    final updated = widget.channel.copyWith(
      name: _nameController.text.trim(),
      topic: _topicController.text.trim(),
      type: state.canChangeGroupFormat(widget.channel.id)
          ? (_topics ? ChannelType.forum : ChannelType.text) : widget.channel.type,
      description: _descController.text.trim(),
      permissions: _perms,
      customImagePath: state.canEditChannelImage(widget.channel) ? _imagePath : widget.channel.customImagePath,
      clearCustomImage: state.canEditChannelImage(widget.channel) && _imagePath == null,
      admins: _admins,
      moderators: _moderators,
      mutedMembers: _mutedMembers,
      bannedMembers: _bannedMembers,
      auditLogs: [
        '${DateTime.now().toIso8601String().substring(11, 19)}: Configurações de #${_nameController.text.trim()} atualizadas.',
        ..._auditLogs,
      ],
    );
    final saved = await state.updateChannelSettings(updated);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível salvar as configurações do canal.')),
      );
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: NixColors.surfaceCard,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Configurações de #${updated.name} salvas com sucesso!',
          style: TextStyle(color: NixColors.textPrimary),
        ),
      ),
    );
  }

  void _runMemberAction(NixState state, String fingerprint, String action) {
    if (!state.canManageChannelSettings(widget.channel.id)) return;
    state.applyAdminAction(
      widget.channel.copyWith(
        admins: _admins,
        moderators: _moderators,
        mutedMembers: _mutedMembers,
        bannedMembers: _bannedMembers,
        auditLogs: _auditLogs,
      ),
      targetFingerprint: fingerprint,
      action: action,
    );
    final allChannels = state.spaces.expand((s) => s.channels);
    final current = allChannels.firstWhere(
      (c) => c.id == widget.channel.id,
      orElse: () => widget.channel,
    );
    setState(() {
      _admins = List<String>.from(current.admins);
      _moderators = List<String>.from(current.moderators);
      _mutedMembers = List<String>.from(current.mutedMembers);
      _bannedMembers = List<String>.from(current.bannedMembers);
      _auditLogs = List<String>.from(current.auditLogs);
    });
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final accent = context.accentColor;
    final accentText = context.accentTextColor;

    if (widget.fullScreen) return _buildFullScreen(nixState, accent, accentText);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 760,
          height: 620,
          decoration: BoxDecoration(
            color: NixColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
                ),
                child: Row(
                  children: [
                    Icon(widget.channel.icon, color: accentText, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Configurações Avançadas · #${widget.channel.name}',
                        style: TextStyle(
                          color: NixColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 20, color: NixColors.textMuted),
                      tooltip: 'Fechar (Esc)',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 210,
                      decoration: BoxDecoration(
                        color: NixColors.surfaceSidebar,
                        border: Border(right: BorderSide(color: NixColors.surfaceBorder)),
                      ),
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        children: [
                          for (final section in _sections)
                            _buildTabItem(
                              tab: section.$1,
                              label: section.$3,
                              icon: section.$2,
                              accent: accent,
                              accentText: accentText,
                            ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        color: NixColors.background,
                        child: _buildActiveTabContent(nixState, accent, accentText),
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  border: Border(top: BorderSide(color: NixColors.surfaceBorder)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancelar', style: TextStyle(color: NixColors.textSecondary)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      key: const Key('save_channel_settings_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: context.onAccentColor,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _saving || !nixState.canManageChannelSettings(widget.channel.id) ? null : () => _save(nixState),
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: const Text('Salvar Alterações', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildFullScreen(NixState state, Color accent, Color accentText) {
    final current = _compactTab;
    final section = current == null ? null : _sections.firstWhere((entry) => entry.$1 == current);

    void back() {
      FocusScope.of(context).unfocus();
      setState(() => _compactTab = null);
    }

    return PopScope(
      canPop: current == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && current != null) back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: current == null ? () => Navigator.of(context).pop() : back),
          title: Text(section?.$3 ?? '#${widget.channel.name}'),
        ),
        body: SafeArea(
          bottom: false,
          child: current == null
              ? ListView(
                  key: const Key('mobile_channel_settings_categories'),
                  children: [
                    for (final entry in _sections)
                      ListTile(
                        leading: Icon(entry.$2),
                        title: Text(entry.$3),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => setState(() {
                          _compactTab = entry.$1;
                          _activeTab = entry.$1;
                        }),
                      ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  child: KeyedSubtree(key: ValueKey(current), child: _buildActiveTabContent(state, accent, accentText)),
                ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(15, 4, 15, 8),
          child: FilledButton.icon(
            key: const Key('save_channel_settings_button'),
            onPressed: _saving || !state.canManageChannelSettings(widget.channel.id) ? null : () => _save(state),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Salvar Alterações'),
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
    required Color accentText,
  }) {
    final isSelected = _activeTab == tab;
    return InkWell(
      onTap: () => setState(() => _activeTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.14) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? accentText : NixColors.textMuted),
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

  Widget _buildActiveTabContent(NixState state, Color accent, Color accentText) {
    switch (_activeTab) {
      case _SettingsTab.identity:
        return _buildIdentityTab(accent);
      case _SettingsTab.permissions:
        return _buildPermissionsTab(accent);
      case _SettingsTab.contentProtection:
        return _buildContentProtectionTab(accent);
      case _SettingsTab.admin:
        return _buildAdminTab(state, accent, accentText);
      case _SettingsTab.security:
        return _buildSecurityTab(accent);
    }
  }

  Widget _buildIdentityTab(Color accent) {
    return ListView(
      children: [
        if (context.read<NixState>().canEditChannelImage(widget.channel)) ...[
          WorkspaceImageField(path: _imagePath, onChanged: (path) => setState(() => _imagePath = path)),
          const SizedBox(height: 12),
        ],
        _buildSectionTitle('IDENTIDADE DO CANAL'),
        const SizedBox(height: 12),
        _buildTextField('Nome do Canal', _nameController, prefixText: '# '),
        const SizedBox(height: 12),
        _buildTextField('Tópico Curto', _topicController),
        const SizedBox(height: 12),
        _buildTextField('Descrição Detalhada', _descController, maxLines: 3),
        const SizedBox(height: 20),

        if (context.read<NixState>().canChangeGroupFormat(widget.channel.id))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Grupo com tópicos'),
            subtitle: const Text('O histórico de cada formato fica disponível ao reativá-lo.'),
            value: _topics,
            onChanged: _saving ? null : (value) => setState(() => _topics = value),
          ),
        _buildSectionTitle('ACESSO E VISIBILIDADE'),
        const SizedBox(height: 12),
        _buildSwitchTile(
          'Canal Público na Rede Nix',
          'Mostra este canal no catálogo Explorar deste dispositivo.',
          _perms.isPublic,
          (val) => setState(() => _perms = _perms.copyWith(isPublic: val)),
          accent,
        ),
        _buildSwitchTile(
          'Exigir Aprovação de Entrada',
          'Bloqueia novas entradas sem aprovação.',
          _perms.requireApproval,
          (val) => setState(() => _perms = _perms.copyWith(requireApproval: val)),
          accent,
        ),
        const SizedBox(height: 12),
        Text(
          _perms.isPublic
              ? 'A descoberta em outros dispositivos depende da publicação no catálogo da rede.'
              : 'Canal privado · fora de Explorar.',
        ),
      ],
    );
  }

  Widget _buildPermissionsTab(Color accent) {
    return ListView(
      children: [
        _buildSectionTitle('PERMISSÕES GRANULARES DE MENSAGENS'),
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
          'Enviar Vídeos',
          'Permitir envio de clipes e transmissões gravadas.',
          _perms.allowVideos,
          (v) => setState(() => _perms = _perms.copyWith(allowVideos: v)),
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
          'Membros podem encaminhar mensagens deste canal.',
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
          'Desativa ações de exportar e copiar dados confidenciais do canal.',
          _perms.restrictExport,
          (v) => setState(() => _perms = _perms.copyWith(restrictExport: v)),
          accent,
        ),
        _buildSwitchTile(
          'Bloquear Salvamento Local de Mídias',
          'Mídias são visualizadas apenas em memória volátil, sem gravação em disco.',
          _perms.restrictMediaSaving,
          (v) => setState(() => _perms = _perms.copyWith(restrictMediaSaving: v)),
          accent,
        ),
        _buildSwitchTile(
          'Proteger Pré-visualizações de Links e Mídias',
          'Evita busca automática de metadados externos para links publicados.',
          _perms.protectPreviews,
          (v) => setState(() => _perms = _perms.copyWith(protectPreviews: v)),
          accent,
        ),
        _buildSwitchTile(
          'Proteção Contra Capturas de Tela (FLAG_SECURE)',
          'No Android, solicita FLAG_SECURE ao gerenciador de janelas do sistema.',
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: NixColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nota Técnica de Proteção Multiplataforma:\n'
                  '• Android: FLAG_SECURE impede capturas/gravações via sistema na maioria dos aparelhos.\n'
                  '• Desktop (Linux/Windows/macOS): Nenhum app de usuário bloqueia totalmente capturas de tela externas ou foto física do monitor; tratamos isso como mitigação auxiliar, não garantia absoluta.',
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
          style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Tempo de Retenção Automática',
            labelStyle: TextStyle(color: NixColors.textMuted),
            filled: true,
            fillColor: NixColors.surfaceCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: [
            DropdownMenuItem(value: 0, child: Text('Permanente (Sem auto-destruição)', style: TextStyle(color: NixColors.textPrimary))),
            DropdownMenuItem(value: 5, child: Text('5 minutos', style: TextStyle(color: NixColors.textPrimary))),
            DropdownMenuItem(value: 60, child: Text('1 hora', style: TextStyle(color: NixColors.textPrimary))),
            DropdownMenuItem(value: 1440, child: Text('24 horas (1 dia)', style: TextStyle(color: NixColors.textPrimary))),
            DropdownMenuItem(value: 10080, child: Text('7 dias (Padrão Relay)', style: TextStyle(color: NixColors.textPrimary))),
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

  Widget _buildAdminTab(NixState state, Color accent, Color accentText) {
    final members = state.members;
    return ListView(
      children: [
        _buildSectionTitle('GESTÃO DE MEMBROS & CARGOS'),
        const SizedBox(height: 8),
        ...members.map((m) {
          final fp = m.fingerprint;
          final isAdmin = _admins.contains(fp);
          final isMod = _moderators.contains(fp);
          final isMuted = _mutedMembers.contains(fp);
          final isBanned = _bannedMembers.contains(fp);
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: NixColors.surfaceCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: NixColors.surfaceBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.name,
                        style: TextStyle(
                          color: NixColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$fp · ${isBanned ? 'Banido' : (isMuted ? 'Silenciado' : (isAdmin ? 'Admin' : (isMod ? 'Mod' : 'Membro')))}',
                        style: TextStyle(color: NixColors.textMuted, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: isAdmin ? 'Remover Admin' : 'Promover Admin',
                  icon: Icon(
                    Icons.admin_panel_settings_rounded,
                    size: 16,
                    color: isAdmin ? accentText : NixColors.textMuted,
                  ),
                  onPressed: () => _runMemberAction(state, fp, 'toggle_admin'),
                ),
                IconButton(
                  tooltip: isMod ? 'Remover Moderador' : 'Promover Moderador',
                  icon: Icon(
                    Icons.gavel_rounded,
                    size: 16,
                    color: isMod ? accentText : NixColors.textMuted,
                  ),
                  onPressed: () => _runMemberAction(state, fp, 'toggle_mod'),
                ),
                IconButton(
                  tooltip: isMuted ? 'Dessilenciar' : 'Silenciar Membro',
                  icon: Icon(
                    isMuted ? Icons.volume_off_rounded : Icons.volume_up_outlined,
                    size: 16,
                    color: isMuted ? NixColors.accentWarning : NixColors.textMuted,
                  ),
                  onPressed: () => _runMemberAction(state, fp, 'toggle_mute'),
                ),
                IconButton(
                  tooltip: isBanned ? 'Banido' : 'Banir Membro',
                  icon: Icon(
                    Icons.block_rounded,
                    size: 16,
                    color: isBanned ? NixColors.accentDanger : NixColors.textMuted,
                  ),
                  onPressed: () => _runMemberAction(state, fp, 'ban'),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
        _buildSectionTitle('LOGS DE AUDITORIA LOCAL'),
        const SizedBox(height: 8),
        Container(
          height: 140,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: NixColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: _auditLogs.isEmpty
              ? Center(
                  child: Text(
                    'Nenhum evento registrado neste canal.',
                    style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                  ),
                )
              : ListView.separated(
                  itemCount: _auditLogs.length,
                  separatorBuilder: (_, __) => Divider(height: 8, color: NixColors.surfaceBorder),
                  itemBuilder: (ctx, idx) {
                    return Text(
                      _auditLogs[idx],
                      style: TextStyle(
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
        _buildSectionTitle('SEGURANÇA, LIMITES E ANTI-SPAM'),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: _perms.slowModeSeconds,
          dropdownColor: NixColors.surfaceCard,
          style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Modo Lento (Slow Mode) - Intervalo entre Mensagens',
            labelStyle: TextStyle(color: NixColors.textMuted),
            filled: true,
            fillColor: NixColors.surfaceCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: [
            DropdownMenuItem(value: 0, child: Text('Desativado (Tempo real)', style: TextStyle(color: NixColors.textPrimary))),
            DropdownMenuItem(value: 5, child: Text('5 segundos', style: TextStyle(color: NixColors.textPrimary))),
            DropdownMenuItem(value: 15, child: Text('15 segundos', style: TextStyle(color: NixColors.textPrimary))),
            DropdownMenuItem(value: 30, child: Text('30 segundos', style: TextStyle(color: NixColors.textPrimary))),
            DropdownMenuItem(value: 60, child: Text('1 minuto', style: TextStyle(color: NixColors.textPrimary))),
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
          style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Tamanho Máximo Permitido por Arquivo',
            labelStyle: TextStyle(color: NixColors.textMuted),
            filled: true,
            fillColor: NixColors.surfaceCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: [
            DropdownMenuItem(value: 10, child: Text('10 MB (Máxima rapidez sobre Tor)', style: TextStyle(color: NixColors.textPrimary))),
            DropdownMenuItem(value: 50, child: Text('50 MB (Recomendado)', style: TextStyle(color: NixColors.textPrimary))),
            DropdownMenuItem(value: 100, child: Text('100 MB (Limite máximo)', style: TextStyle(color: NixColors.textPrimary))),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _perms = _perms.copyWith(maxFileSizeMb: val));
            }
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          value: _perms.inviteExpiryDays,
          dropdownColor: NixColors.surfaceCard,
          style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Expiração Automática de Convites',
            labelStyle: TextStyle(color: NixColors.textMuted),
            filled: true,
            fillColor: NixColors.surfaceCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: [
            DropdownMenuItem(value: 1, child: Text('24 horas', style: TextStyle(color: NixColors.textPrimary))),
            DropdownMenuItem(value: 7, child: Text('7 dias (Padrão Relay)', style: TextStyle(color: NixColors.textPrimary))),
            DropdownMenuItem(value: 30, child: Text('30 dias', style: TextStyle(color: NixColors.textPrimary))),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _perms = _perms.copyWith(inviteExpiryDays: val));
            }
          },
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
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
      style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: NixColors.textMuted, fontSize: 12),
        prefixText: prefixText,
        prefixStyle: TextStyle(color: NixColors.textMuted),
        filled: true,
        fillColor: NixColors.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: NixColors.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: NixColors.surfaceBorder),
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
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          title: Text(title, style: TextStyle(color: NixColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: TextStyle(color: NixColors.textMuted, fontSize: 11)),
          value: value,
          activeColor: accent,
          onChanged: onChanged,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        ),
      ),
    );
  }
}
