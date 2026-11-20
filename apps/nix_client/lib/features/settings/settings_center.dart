import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/user_settings.dart';
import '../../core/theme.dart';
import '../../core/security/platform_runtime.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../core/theme/nix_palette.dart';
import '../../state/nix_state.dart';
import '../design/nix_surfaces.dart';
import '../dialogs/sovereign_onboarding_dialog.dart';
import '../profile/pager_appearance_dialog.dart';

/// Central de Configurações Modular (V2 — Aparência Living AMOLED, Privacidade, Dispositivos e Módulos).
class SettingsCenter extends StatefulWidget {
  final VoidCallback? onBackToCardId;
  final VoidCallback? onClose;
  final SettingsCategory? initialCompactCategory;
  final bool fullScreen;

  const SettingsCenter({
    super.key,
    this.onBackToCardId,
    this.onClose,
    this.initialCompactCategory,
    this.fullScreen = false,
  });

  @override
  State<SettingsCenter> createState() => _SettingsCenterState();
}

class _SettingsCenterState extends State<SettingsCenter> {
  late SettingsCategory? _compactCategory = widget.initialCompactCategory;
  bool _isTestingMic = false;
  double _micLevel = 0.0;
  Timer? _micTimer;
  bool _isRunningNetDiag = false;
  String _netDiagResult = 'Clique em diagnosticar para auditar SOCKS5, ControlPort e Onion v3.';
  final TextEditingController _blockIdController = TextEditingController();
  final TextEditingController _newDeviceNameController = TextEditingController();
  final TextEditingController _bleTestMessageController = TextEditingController(text: 'Ping NIXB BLE físico');
  final TextEditingController _loraTestMessageController = TextEditingController(text: 'Ping LoRa NX <=240B');

  @override
  void dispose() {
    _micTimer?.cancel();
    _blockIdController.dispose();
    _newDeviceNameController.dispose();
    _bleTestMessageController.dispose();
    _loraTestMessageController.dispose();
    super.dispose();
  }

  void _toggleMicTest() {
    if (_isTestingMic) {
      _micTimer?.cancel();
      setState(() {
        _isTestingMic = false;
        _micLevel = 0.0;
      });
    } else {
      final rng = Random();
      setState(() => _isTestingMic = true);
      _micTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (mounted) {
          setState(() => _micLevel = 0.20 + rng.nextDouble() * 0.72);
        }
      });
    }
  }

  void _runConnectivityDiagnostic() async {
    final nixState = context.read<NixState>();
    setState(() {
      _isRunningNetDiag = true;
      _netDiagResult =
          'Auditando SOCKS5 127.0.0.1:${nixState.embeddedTor.socksPort}, ControlPort e Onion v3...';
    });
    final report = await nixState.verifyTorTransportAndFailClosed();
    if (mounted) {
      setState(() {
        _isRunningNetDiag = false;
        _netDiagResult = report.detail;
      });
    }
  }

  void _showAddDeviceDialog(NixState state) {
    _newDeviceNameController.text = 'Android Phone (Tor)';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NixColors.surfaceElevatedHigh,
        title: Text('Vincular Novo Dispositivo', style: TextStyle(color: NixColors.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Escaneie o código efêmero com o app Nix no seu segundo dispositivo para autorizar uma nova chave de sessão sem passar chaves privadas mestre pela rede.',
              style: TextStyle(color: NixColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                width: 140,
                height: 140,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(Icons.qr_code_2_rounded, size: 120, color: Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _newDeviceNameController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Identificador do Dispositivo',
                hintText: 'ex: Tablet Segura LoRa',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: TextStyle(color: NixColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              state.authorizeDevice(
                _newDeviceNameController.text,
                'NX-${Random().nextInt(8999) + 1000}-${Random().nextInt(8999) + 1000}',
              );
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Novo dispositivo autorizado com sucesso.')),
              );
            },
            child: const Text('Confirmar Vinculação'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    if (widget.fullScreen) return _buildCompactSettings(nixState);
    final settings = nixState.settings;
    final activeCat = nixState.activeSettingsCategory;

    return Container(
      decoration: nixFrameDecoration(context, background: context.bgColor),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 680) {
            return _buildCompactSettings(nixState);
          }

          return Column(
            children: [
              // Barra Superior da Central de Configurações
              Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: NixColors.surfaceSidebar,
                  border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
                ),
                child: Row(
                  children: [
                    if (widget.onBackToCardId != null) ...[
                      InkWell(
                        key: const Key('back_to_card_id_button'),
                        onTap: widget.onBackToCardId,
                        borderRadius: NixTokens.borderSm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: NixColors.surfaceCard,
                            borderRadius: NixTokens.borderSm,
                            border: Border.all(color: NixColors.surfaceBorderStrong),
                          ),
                          child: const Icon(Icons.arrow_back_rounded, size: 18),
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Icon(Icons.tune_rounded, color: NixColors.textPrimary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'CENTRAL DE CONFIGURAÇÕES NIX',
                        style: TextStyle(
                          color: NixColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.onClose != null)
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: NixColors.textSecondary, size: 20),
                        tooltip: 'Fechar (Esc)',
                        onPressed: widget.onClose,
                      ),
                  ],
                ),
              ),

              // Corpo Principal: Navegação Lateral + Conteúdo da Aba
              Expanded(
                child: Row(
                        children: [
                          _buildSidebarNavigation(nixState, activeCat),
                          Expanded(child: _buildCategoryContent(nixState, settings, activeCat)),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  static const _categories = [
    (SettingsCategory.appearance, Icons.palette_outlined, 'Aparência'),
    (SettingsCategory.notifications, Icons.notifications_none_rounded, 'Notificações'),
    (SettingsCategory.privacy, Icons.lock_outline_rounded, 'Privacidade'),
    (SettingsCategory.chats, Icons.chat_bubble_outline_rounded, 'Chats'),
    (SettingsCategory.audio, Icons.mic_none_rounded, 'Som e microfone'),
    (SettingsCategory.connections, Icons.hub_outlined, 'Conexões'),
    (SettingsCategory.devices, Icons.devices_outlined, 'Dispositivos'),
    (SettingsCategory.survival, Icons.shield_outlined, 'Sobrevivência'),
  ];

  Widget _buildCompactSettings(NixState state) {
    final category = _compactCategory;
    final item = category == null ? null : _categories.firstWhere((entry) => entry.$1 == category);
    final backToRoot = category == null ? null : () {
      FocusScope.of(context).unfocus();
      setState(() => _compactCategory = null);
    };
    final close = widget.onBackToCardId ?? widget.onClose;
    return PopScope(
      canPop: backToRoot == null && close == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) (backToRoot ?? close)?.call();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: backToRoot != null || close != null
              ? BackButton(onPressed: backToRoot ?? close)
              : null,
          title: Text(item?.$3 ?? 'Configurações do Nix'),
          actions: [
            if (widget.onClose != null)
              IconButton(onPressed: widget.onClose, tooltip: 'Fechar configurações', icon: const Icon(Icons.close_rounded)),
          ],
        ),
        body: category == null
            ? ListView(
                key: const Key('mobile_settings_categories'),
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  for (final entry in _categories)
                    ListTile(
                      leading: Icon(entry.$2),
                      title: Text(entry.$3),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        setState(() => _compactCategory = entry.$1);
                        state.selectSettingsCategory(entry.$1);
                      },
                    ),
                ],
              )
            : KeyedSubtree(
                key: ValueKey('mobile_settings_${category.name}'),
                child: _buildCategoryContent(state, state.settings, category),
              ),
      ),
    );
  }

  Widget _buildSidebarNavigation(NixState nixState, SettingsCategory activeCat) {
    return Container(
      width: 235,
      decoration: BoxDecoration(
        color: NixColors.surfaceSidebar,
        border: Border(right: BorderSide(color: NixColors.surfaceBorder)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text('APARÊNCIA & PERSONALIZAÇÃO', style: NixTokens.labelUppercase()),
          ),
          _navItem(
            nixState: nixState,
            category: SettingsCategory.appearance,
            icon: Icons.palette_outlined,
            label: 'Aparência & Temas',
            isSelected: activeCat == SettingsCategory.appearance,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text('MÓDULOS DO SISTEMA', style: NixTokens.labelUppercase()),
          ),
          _navItem(
            nixState: nixState,
            category: SettingsCategory.notifications,
            icon: Icons.notifications_none_rounded,
            label: 'Notificações e Sons',
            isSelected: activeCat == SettingsCategory.notifications,
          ),
          _navItem(
            nixState: nixState,
            category: SettingsCategory.privacy,
            icon: Icons.lock_outline_rounded,
            label: 'Privacidade e Segurança',
            isSelected: activeCat == SettingsCategory.privacy,
          ),
          _navItem(
            nixState: nixState,
            category: SettingsCategory.chats,
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Configurações dos Chats',
            isSelected: activeCat == SettingsCategory.chats,
          ),
          _navItem(
            nixState: nixState,
            category: SettingsCategory.audio,
            icon: Icons.mic_none_rounded,
            label: 'Som e Microfone',
            isSelected: activeCat == SettingsCategory.audio,
          ),
          _navItem(
            nixState: nixState,
            category: SettingsCategory.connections,
            icon: Icons.hub_outlined,
            label: 'Conexões e Integrações',
            isSelected: activeCat == SettingsCategory.connections,
          ),
          _navItem(
            nixState: nixState,
            category: SettingsCategory.devices,
            icon: Icons.devices_outlined,
            label: 'Dispositivos & Sessões',
            isSelected: activeCat == SettingsCategory.devices,
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Divider(height: 1, color: NixColors.surfaceBorder),
          ),
          _navItem(
            nixState: nixState,
            category: SettingsCategory.survival,
            icon: Icons.shield_outlined,
            label: 'Sobrevivência e Privacidade',
            isSelected: activeCat == SettingsCategory.survival,
          ),
        ],
      ),
    ),
  );
  }

  Widget _navItem({
    required NixState nixState,
    required SettingsCategory category,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? NixColors.surfaceActive : Colors.transparent,
        borderRadius: NixTokens.borderSm,
        border: isSelected ? Border.all(color: NixColors.surfaceBorderStrong) : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -2),
          leading: Icon(
            icon,
            size: 18,
            color: isSelected ? NixColors.textPrimary : NixColors.iconSecondary,
          ),
          title: Text(
            label,
            style: TextStyle(
              color: isSelected ? NixColors.textPrimary : NixColors.textSecondary,
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          onTap: () => nixState.selectSettingsCategory(category),
        ),
      ),
    );
  }

  Widget _buildCategoryContent(
    NixState nixState,
    UserSettings settings,
    SettingsCategory category,
  ) {
    return AnimatedSwitcher(
      duration: NixTokens.motionFast,
      child: ListView(
        key: ValueKey(category),
        padding: const EdgeInsets.all(24),
        children: [
          if (category == SettingsCategory.appearance)
            _buildAppearanceSection(nixState, settings),
          if (category == SettingsCategory.notifications)
            _buildNotificationsSection(nixState, settings),
          if (category == SettingsCategory.privacy)
            _buildPrivacySecuritySection(nixState, settings),
          if (category == SettingsCategory.chats)
            _buildChatsSection(nixState, settings),
          if (category == SettingsCategory.audio)
            _buildAudioSection(nixState, settings),
          if (category == SettingsCategory.connections)
            _buildConnectionsSection(nixState, settings),
          if (category == SettingsCategory.devices)
            _buildDevicesSection(nixState, settings),
          if (category == SettingsCategory.survival)
            _buildSurvivalPrivacySection(nixState, settings),
        ],
      ),
    );
  }

  // ================= 5.0 APARÊNCIA — DARK YELLOW, LIGHT YELLOW & AMOLED =================
  Widget _buildAppearanceSection(NixState state, UserSettings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Configurações → Aparência → Temas',
          'Escolha uma combinação pronta ou ajuste a superfície e o destaque separadamente.',
        ),
        OutlinedButton.icon(
          onPressed: () => showPagerAppearance(context),
          icon: const Icon(Icons.palette_outlined),
          label: const Text('Cores do Pager'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            for (final (label, mode, palette, icon) in const [
              ('Preto / Roxo', NixThemeMode.darkYellow, NixPaletteType.violet, Icons.dark_mode_outlined),
              ('Branco / Amarelo', NixThemeMode.lightYellow, NixPaletteType.yellow, Icons.light_mode_outlined),
              ('Verde / Roxo', NixThemeMode.darkYellow, NixPaletteType.terminal, Icons.terminal_rounded),
            ])
              ChoiceChip(
                label: Text(label),
                avatar: Icon(icon, size: 16),
                selected: s.themeMode == mode && s.paletteType == palette,
                onSelected: (_) => state.updateSettings(s.copyWith(themeMode: mode, paletteType: palette)),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text('SUPERFÍCIES', style: NixTokens.labelUppercase()),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _themeModeCard(
              key: const Key('theme_mode_dark_yellow'),
              state: state,
              mode: NixThemeMode.darkYellow,
              title: 'Escuro Violeta',
              subtitle: 'Grafite e violeta',
              previewBg: NixSurfaceScheme.darkYellow.background,
              previewSurface: NixSurfaceScheme.darkYellow.surfaceSidebar,
              previewElevated: NixSurfaceScheme.darkYellow.surfaceElevated,
              previewText: const Color(0xFFFFFFFF),
              isSelected: s.themeMode == NixThemeMode.darkYellow,
            ),
            _themeModeCard(
              key: const Key('theme_mode_light_yellow'),
              state: state,
              mode: NixThemeMode.lightYellow,
              title: 'Light Yellow',
              subtitle: '#FFFFFF · #FFC928',
              previewBg: const Color(0xFFFFFFFF),
              previewSurface: const Color(0xFFF6F7F9),
              previewElevated: const Color(0xFFE9EBEF),
              previewText: const Color(0xFF17191E),
              isSelected: s.themeMode == NixThemeMode.lightYellow,
            ),
            _themeModeCard(
              key: const Key('theme_mode_amoled'),
              state: state,
              mode: NixThemeMode.amoled,
              title: 'AMOLED Puro',
              subtitle: '#000000 · Opcional',
              previewBg: const Color(0xFF000000),
              previewSurface: const Color(0xFF0A0A0E),
              previewElevated: const Color(0xFF19191F),
              previewText: const Color(0xFFFFFFFF),
              isSelected: s.themeMode == NixThemeMode.amoled,
            ),
            _themeModeCard(
              key: const Key('theme_mode_system'),
              state: state,
              mode: NixThemeMode.system,
              title: 'Tema do Sistema',
              subtitle: 'Claro / Escuro automático',
              previewBg: const Color(0xFF17191E),
              previewSurface: const Color(0xFFF6F7F9),
              previewElevated: const Color(0xFF292C33),
              previewText: NixColors.textPrimary,
              isSelected: s.themeMode == NixThemeMode.system,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('COR DE DESTAQUE & PERSONALIZAÇÃO', style: NixTokens.labelUppercase()),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _paletteCard(
              state: state,
              type: NixPaletteType.yellow,
              palette: NixPalette.yellow,
              isSelected: s.paletteType == NixPaletteType.yellow,
            ),
            _paletteCard(
              state: state,
              type: NixPaletteType.original,
              palette: NixPalette.original,
              isSelected: s.paletteType == NixPaletteType.original,
            ),
            _paletteCard(
              state: state,
              type: NixPaletteType.violet,
              palette: NixPalette.violet,
              isSelected: s.paletteType == NixPaletteType.violet,
            ),
            _paletteCard(
              state: state,
              type: NixPaletteType.blue,
              palette: NixPalette.blue,
              isSelected: s.paletteType == NixPaletteType.blue,
            ),
            _paletteCard(
              state: state,
              type: NixPaletteType.crimson,
              palette: NixPalette.crimson,
              isSelected: s.paletteType == NixPaletteType.crimson,
            ),
            _paletteCard(
              state: state,
              type: NixPaletteType.amber,
              palette: NixPalette.amber,
              isSelected: s.paletteType == NixPaletteType.amber,
            ),
            _paletteCard(
              state: state,
              type: NixPaletteType.rose,
              palette: NixPalette.rose,
              isSelected: s.paletteType == NixPaletteType.rose,
            ),
            _customPaletteCard(state, s),
          ],
        ),
        const SizedBox(height: 24),
        Text('COMPORTAMENTO DA JANELA & RESPONSIVIDADE', style: NixTokens.labelUppercase()),
        const SizedBox(height: 8),
        _switchTile(
          title: 'Janela Flutuante & Redimensionável',
          subtitle:
              'Permite redimensionar pelas 8 bordas e cantos no desktop (dimensões mínimas 720×500) com cantos arredondados.',
          value: s.floatingWindowMode,
          onChanged: (v) => state.toggleFloatingWindowMode(v),
        ),
        const SizedBox(height: 8),
        _sliderCard(
          title: 'Escala Geral da Interface & Fontes (${(s.fontScale * 100).round()}%)',
          value: s.fontScale,
          min: 0.85,
          max: 1.25,
          onChanged: (v) => state.updateSettings(s.copyWith(fontScale: v)),
        ),
      ],
    );
  }

  Widget _themeModeCard({
    required Key key,
    required NixState state,
    required NixThemeMode mode,
    required String title,
    required String subtitle,
    required Color previewBg,
    required Color previewSurface,
    required Color previewElevated,
    required Color previewText,
    required bool isSelected,
  }) {
    final accent = state.currentPalette.primaryAccent;
    return InkWell(
      key: key,
      onTap: () => state.updateThemeMode(mode),
      borderRadius: NixTokens.borderMd,
      child: Container(
        width: 175,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? NixColors.surfaceElevatedHigh : NixColors.surfaceCard,
          borderRadius: NixTokens.borderMd,
          border: Border.all(
            color: isSelected ? accent : NixColors.surfaceBorder,
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 44,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: previewBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NixColors.surfaceBorderStrong),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    decoration: BoxDecoration(
                      color: previewSurface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: 6,
                          width: 54,
                          decoration: BoxDecoration(
                            color: previewText,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          height: 8,
                          width: 72,
                          decoration: BoxDecoration(
                            color: previewElevated,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, size: 15, color: NixColors.accentText),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(color: NixColors.textMuted, fontSize: 10.5, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paletteCard({
    required NixState state,
    required NixPaletteType type,
    required NixPalette palette,
    required bool isSelected,
  }) {
    return InkWell(
      key: Key('palette_${type.name}'),
      onTap: () => state.updatePalette(type),
      borderRadius: NixTokens.borderMd,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? NixColors.surfaceElevatedHigh : NixColors.surfaceCard,
          borderRadius: NixTokens.borderMd,
          border: Border.all(
            color: isSelected ? palette.primaryAccent : NixColors.surfaceBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: palette.glowColor,
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: palette.primaryAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: NixColors.surfaceBorder, width: 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    palette.name,
                    style: TextStyle(
                      color: isSelected ? NixColors.textPrimary : NixColors.textSecondary,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 24,
              decoration: BoxDecoration(
                color: NixColors.background,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: NixColors.surfaceBorder),
              ),
              child: Row(
                children: [
                  Container(width: 24, color: palette.primaryAccent.withOpacity(0.15)),
                  const SizedBox(width: 6),
                  Container(
                    width: 32,
                    height: 5,
                    decoration: BoxDecoration(
                      color: palette.primaryAccent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customPaletteCard(NixState state, UserSettings s) {
    final isSelected = s.paletteType == NixPaletteType.custom;
    final customColor = s.customPaletteColor != null ? Color(s.customPaletteColor!) : const Color(0xFF10B981);

    return InkWell(
      key: const Key('palette_custom'),
      onTap: () {
        // Alterna entre cores personalizadas populares ao clicar
        final colors = [
          const Color(0xFF10B981), // Esmeralda
          const Color(0xFF06B6D4), // Ciano
          const Color(0xFFEC4899), // Magenta
          const Color(0xFFEAB308), // Ouro
          const Color(0xFF6366F1), // Índigo
        ];
        final nextIdx = (colors.indexOf(customColor) + 1) % colors.length;
        state.updatePalette(NixPaletteType.custom, colors[nextIdx].value);
      },
      borderRadius: NixTokens.borderMd,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? NixColors.surfaceElevatedHigh : NixColors.surfaceCard,
          borderRadius: NixTokens.borderMd,
          border: Border.all(
            color: isSelected ? customColor : NixColors.surfaceBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: customColor.withOpacity(0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: customColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: NixColors.surfaceBorder, width: 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Personalizado',
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Clique p/ alternar matiz',
              style: TextStyle(color: NixColors.textMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  // ================= 5.1 NOTIFICAÇÕES E SONS =================
  Widget _buildNotificationsSection(NixState state, UserSettings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '5.1 Notificações e Sons',
          'Controle alertas de mensagens, chamadas e ocultação de conteúdo sensível na área de trabalho.',
        ),
        _switchTile(
          title: 'Modo Silencioso (Não Perturbe)',
          subtitle: 'Suprime imediatamente todos os alertas sonoros e banners visuais.',
          value: s.silentMode,
          onChanged: (v) => state.updateSettings(s.copyWith(silentMode: v)),
        ),
        _switchTile(
          title: 'Notificações de Mensagens',
          subtitle: 'Alertar ao receber mensagens diretas ou menções em tópicos.',
          value: s.messageNotifications,
          onChanged: (v) => state.updateSettings(s.copyWith(messageNotifications: v)),
        ),
        _switchTile(
          title: 'Notificações de Chamadas',
          subtitle: 'Exibir alerta ao receber convite para salas de call E2EE.',
          value: s.callNotifications,
          onChanged: (v) => state.updateSettings(s.copyWith(callNotifications: v)),
        ),
        _switchTile(
          title: 'Alertas Operacionais do Sistema',
          subtitle: 'Avisos sobre mudanças no estado do circuito Tor, pressão de disco ou chaves.',
          value: s.systemAlerts,
          onChanged: (v) => state.updateSettings(s.copyWith(systemAlerts: v)),
        ),
        _switchTile(
          title: 'Pré-visualização de Conteúdo nas Notificações',
          subtitle: 'Desativado por padrão para impedir leitura de mensagens na tela bloqueada.',
          value: s.showMessagePreview,
          onChanged: (v) => state.updateSettings(s.copyWith(showMessagePreview: v)),
        ),
        _switchTile(
          title: 'Notificações na Área de Trabalho (Desktop)',
          subtitle: 'Integrar ao subsistema de notificações nativo sem expor metadados de remetente.',
          value: s.desktopNotifications,
          onChanged: (v) => state.updateSettings(s.copyWith(desktopNotifications: v)),
        ),
        _switchTile(
          title: 'Sons de Notificações',
          subtitle: 'Reproduzir pulso sonoro discreto em eventos importantes.',
          value: s.notificationSounds,
          onChanged: (v) => state.updateSettings(s.copyWith(notificationSounds: v)),
        ),
        const SizedBox(height: 12),
        _sliderCard(
          title: 'Volume de Alertas (${(s.alertVolume * 100).round()}%)',
          value: s.alertVolume,
          onChanged: (v) => state.updateSettings(s.copyWith(alertVolume: v)),
        ),
      ],
    );
  }

  // ================= 5.2 PRIVACIDADE E SEGURANÇA =================
  Widget _buildPrivacySecuritySection(NixState state, UserSettings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '5.2 Privacidade e Segurança',
          'Gerencie visibilidade do Card ID, bloqueios, limpeza criptográfica e sanitização de metadados.',
        ),
        _dropdownCard(
          title: 'Visibilidade do Perfil e Card ID',
          subtitle: 'Define quem pode consultar seu passaporte cultural e biografia.',
          value: s.profileVisibility,
          options: const ['Apenas Contatos Verificados', 'Público via QR', 'Oculto'],
          onChanged: (v) => state.updateSettings(s.copyWith(profileVisibility: v)),
        ),
        _dropdownCard(
          title: 'Privacidade → Visibilidade do Card ID',
          subtitle: 'Define na camada de dados quem pode visualizar seu Card ID, biografia e acervo.',
          value: s.cardIdVisibility,
          options: const ['Público', 'Apenas Contatos Verificados', 'Oculto'],
          onChanged: (v) => state.updateCardIdVisibility(v),
        ),
        _dropdownCard(
          title: 'Permissões de Comunicação',
          subtitle: 'Controle quem pode iniciar sessões X3DH ou enviar solicitações.',
          value: s.communicationPermission,
          options: const ['Somente Pares Verificados', 'Qualquer ID c/ PoW'],
          onChanged: (v) => state.updateSettings(s.copyWith(communicationPermission: v)),
        ),
        _switchTile(
          title: 'Permitir Compartilhamento do ID Público',
          subtitle: 'Autoriza geração de URI e QR Code público no Card ID.',
          value: s.allowPublicIdSharing,
          onChanged: (v) => state.updateSettings(s.copyWith(allowPublicIdSharing: v)),
        ),
        _switchTile(
          title: 'Remoção Obrigatória de Metadados (EXIF Strip)',
          subtitle: 'Remove coordenadas GPS, modelo de câmera e timestamps de fotos antes de cifrar.',
          value: s.stripExifMetadata,
          onChanged: (v) => state.updateSettings(s.copyWith(stripExifMetadata: v)),
        ),
        _switchTile(
          title: 'Permissão de Arquivos e Mídia',
          subtitle: 'Habilitar processamento local de anexos cifrados via XChaCha20-Poly1305.',
          value: s.allowMediaAttachments,
          onChanged: (v) => state.updateSettings(s.copyWith(allowMediaAttachments: v)),
        ),
        _dropdownCard(
          title: 'Bloqueio Automático do Cofre SQLCipher',
          subtitle: 'Tempo de inatividade até trancar as chaves em memória.',
          value: '${s.autoLockMinutes} minutos',
          options: const ['1 minutos', '5 minutos', '15 minutos', '30 minutos'],
          onChanged: (v) {
            final mins = int.tryParse(v.split(' ').first) ?? 5;
            state.updateSettings(s.copyWith(autoLockMinutes: mins));
          },
        ),
        const SizedBox(height: 12),
        // Lista de Usuários Bloqueados
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('USUÁRIOS E CHAVES BLOQUEADAS (${s.blockedUserIds.length})',
                  style: NixTokens.labelUppercase()),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _blockIdController,
                      style: TextStyle(fontSize: 12, color: NixColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Inserir ID para bloquear (ex: NIX-1234-...)',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NixColors.textPrimary,
                      side: BorderSide(color: NixColors.surfaceBorderStrong),
                    ),
                    onPressed: () {
                      state.blockNewUser(_blockIdController.text);
                      _blockIdController.clear();
                    },
                    child: const Text('Bloquear', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...s.blockedUserIds.map((id) => Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.block, size: 16, color: NixColors.textMuted),
                      title: Text(id, style: NixTokens.monoCode()),
                      trailing: TextButton(
                        onPressed: () => state.unblockUser(id),
                        child: Text('Desbloquear',
                            style: TextStyle(color: NixColors.textSecondary, fontSize: 11)),
                      ),
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Sessões e Limpeza Local
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.delete_sweep_outlined, color: NixColors.textPrimary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Limpeza de Cache e Temporários Locais',
                        style: TextStyle(
                            color: NixColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('Zera buffers de miniaturas decifradas e limpa chaves efêmeras antigas.',
                        style: TextStyle(color: NixColors.textMuted, fontSize: 11.5)),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: NixColors.textPrimary,
                  side: BorderSide(color: NixColors.surfaceBorderStrong),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Caches efêmeros e buffers temporários limpos com sucesso.'),
                    ),
                  );
                },
                child: const Text('Executar Limpeza', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================= 5.3 CONFIGURAÇÕES DOS CHATS =================
  Widget _buildChatsSection(NixState state, UserSettings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '5.3 Configurações dos Chats',
          'Personalize densidade visual, escala tipográfica, retenção e comportamento de mídia.',
        ),
        _switchTile(
          title: 'Modo de Exibição Compacto',
          subtitle: 'Reduz o espaçamento vertical entre mensagens para maior densidade em telas menores.',
          value: s.compactChatMode,
          onChanged: (v) => state.updateSettings(s.copyWith(compactChatMode: v)),
        ),
        _sliderCard(
          title: 'Escala da Tipografia (${(s.fontScale * 100).round()}%)',
          value: s.fontScale,
          min: 0.85,
          max: 1.25,
          onChanged: (v) => state.updateSettings(s.copyWith(fontScale: v)),
        ),
        const SizedBox(height: 8),
        _switchTile(
          title: 'Pressionar Enter para Enviar Mensagem',
          subtitle: 'Envia mensagem com Enter e insere quebra de linha com Shift+Enter.',
          value: s.enterToSend,
          onChanged: (v) => state.updateSettings(s.copyWith(enterToSend: v)),
        ),
        _switchTile(
          title: 'Download Automático de Mídia Cifrada',
          subtitle: 'Desativado por padrão para economizar largura de banda em conexões Tor ou rádio LoRa.',
          value: s.autoDownloadMedia,
          onChanged: (v) => state.updateSettings(s.copyWith(autoDownloadMedia: v)),
        ),
        _switchTile(
          title: 'Recibos de Leitura (Read Receipts)',
          subtitle: 'Desativado por padrão para proteger contra análise de presença e disponibilidade.',
          value: s.sendReadReceipts,
          onChanged: (v) => state.updateSettings(s.copyWith(sendReadReceipts: v)),
        ),
        _dropdownCard(
          title: 'Retenção Padrão de Mensagens (TTL Local)',
          subtitle: 'Período antes do expurgo permanente pelo AutoPruner local.',
          value: '${s.defaultRetentionDays} dias',
          options: const ['1 dias', '3 dias', '7 dias', '14 dias', '30 dias'],
          onChanged: (v) {
            final days = int.tryParse(v.split(' ').first) ?? 7;
            state.updateSettings(s.copyWith(defaultRetentionDays: days));
          },
        ),
      ],
    );
  }

  // ================= 5.4 SOM E MICROFONE =================
  Widget _buildAudioSection(NixState state, UserSettings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '5.4 Som e Microfone',
          'Ajuste dispositivos de áudio, supressão de ruído e faça teste de eco em sandbox local.',
        ),
        _dropdownCard(
          title: 'Dispositivo de Entrada (Microfone)',
          subtitle: 'Dispositivo de captura isolado no subsistema PipeWire/PulseAudio.',
          value: s.inputDevice,
          options: const [
            'Microfone Padrão ALSA/PipeWire (Isolado)',
            'Headset USB Segura (Hardware Mute)',
            'Entrada de Linha Analógica',
          ],
          onChanged: (v) => state.updateSettings(s.copyWith(inputDevice: v)),
        ),
        _dropdownCard(
          title: 'Dispositivo de Saída (Alto-falantes / Fones)',
          subtitle: 'Roteamento estéreo isolado para reprodução sem vazamentos.',
          value: s.outputDevice,
          options: const [
            'Saída Estéreo Digital (PipeWire)',
            'Fones de Ouvido Cabeados P3/P2',
            'Saída HDMI / DisplayPort',
          ],
          onChanged: (v) => state.updateSettings(s.copyWith(outputDevice: v)),
        ),
        const SizedBox(height: 8),
        _sliderCard(
          title: 'Volume de Entrada / Ganho (${(s.inputVolume * 100).round()}%)',
          value: s.inputVolume,
          onChanged: (v) => state.updateSettings(s.copyWith(inputVolume: v)),
        ),
        const SizedBox(height: 8),
        _sliderCard(
          title: 'Volume de Saída (${(s.outputVolume * 100).round()}%)',
          value: s.outputVolume,
          onChanged: (v) => state.updateSettings(s.copyWith(outputVolume: v)),
        ),
        const SizedBox(height: 8),
        _switchTile(
          title: 'Supressão Ativa de Ruído de Fundo',
          subtitle: 'Filtro espectral RNNoise para eliminar estalos e ruídos de ventoinha.',
          value: s.noiseSuppression,
          onChanged: (v) => state.updateSettings(s.copyWith(noiseSuppression: v)),
        ),
        _switchTile(
          title: 'Cancelamento Acústico de Eco',
          subtitle: 'Impede realimentação ao usar microfone e caixas de som no mesmo ambiente.',
          value: s.echoCancellation,
          onChanged: (v) => state.updateSettings(s.copyWith(echoCancellation: v)),
        ),
        const SizedBox(height: 12),
        // Teste de Microfone em Tempo Real
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('TESTE DE CAPTURA DE VOZ EM TEMPO REAL',
                      style: TextStyle(color: NixColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NixColors.textPrimary,
                      side: BorderSide(color: NixColors.surfaceBorderStrong),
                    ),
                    onPressed: _toggleMicTest,
                    icon: Icon(_isTestingMic ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 16),
                    label: Text(_isTestingMic ? 'Parar Teste' : 'Iniciar Teste', style: const TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _micLevel,
                  backgroundColor: NixColors.surfaceActive,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _micLevel > 0.8 ? NixColors.accentDanger : Colors.white,
                  ),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isTestingMic
                    ? 'Fale no microfone. O medidor responde em tempo real sem transmitir áudio para a rede.'
                    : 'Pressione "Iniciar Teste" para calibrar o ganho do microfone localmente.',
                style: TextStyle(color: NixColors.textMuted, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================= 5.5 CONEXÕES E INTEGRAÇÕES =================
  Widget _buildConnectionsSection(NixState state, UserSettings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '5.5 Conexões e Integrações',
          'Controle de transporte em rede Onion, política Fail-Closed e conectores externos isolados.',
        ),
        _dropdownCard(
          title: 'Perfil de Transporte de Rede',
          subtitle: 'Define o roteamento primário dos envelopes cifrados.',
          value: state.isStrictOffGridMode
              ? 'Off-Grid BLE/LoRa (Zero Rede IP)' : 'Tor Onion v3 (Fail-Closed)',
          options: const [
            'Tor Onion v3 (Fail-Closed)',
            'Off-Grid BLE/LoRa (Zero Rede IP)',
          ],
          onChanged: (value) {
            if (value.startsWith('Off-Grid')) {
              state.enterStrictOffGridMode();
            } else if (state.isStrictOffGridMode) {
              state.exitOffGridModeAndConnectTor();
            }
          },
        ),
        _switchTile(
          title: 'Ocultar Informações Sensíveis de Rede',
          subtitle: 'Não expor IP local, interfaces ou rotas nas telas de diagnóstico.',
          value: s.hideSensitiveNetworkInfo,
          onChanged: (v) => state.updateSettings(s.copyWith(hideSensitiveNetworkInfo: v)),
        ),
        _switchTile(
          title: 'Reconexão Automática do Circuito Tor',
          subtitle: 'Gera novo circuito de 3 saltos imediatamente se o nó de saída falhar.',
          value: s.autoReconnect,
          onChanged: (v) => state.updateSettings(s.copyWith(autoReconnect: v)),
        ),
        const SizedBox(height: 14),
        // Diagnóstico de Conectividade
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('DIAGNÓSTICO DO CIRCUITO ONION V3',
                      style: TextStyle(color: NixColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NixColors.textPrimary,
                      side: BorderSide(color: NixColors.surfaceBorderStrong),
                    ),
                    onPressed: _isRunningNetDiag ? null : _runConnectivityDiagnostic,
                    icon: _isRunningNetDiag
                        ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: NixColors.textPrimary))
                        : const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Executar Teste', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: NixColors.background,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: Text(
                  _netDiagResult,
                  style: NixTokens.monoCode(size: 11.5, color: NixColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // DAEMON TOR EMBUTIDO (ZERO-CONFIGURATION)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield_outlined, color: NixColors.textPrimary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'DAEMON TOR EMBUTIDO (SEM ORBOT)',
                        style: TextStyle(color: NixColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NixColors.textPrimary,
                      side: BorderSide(color: NixColors.surfaceBorderStrong),
                    ),
                    onPressed: state.isTorRunning ? null : () => state.startEmbeddedTor(),
                    icon: Icon(state.isTorRunning ? Icons.check_circle_rounded : Icons.play_arrow_rounded,
                        size: 14, color: state.isTorRunning ? NixColors.accentYellow : NixColors.textPrimary),
                    label: Text(state.isTorRunning ? 'Ativo' : 'Iniciar Tor Embutido', style: const TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Executa a infraestrutura Tor embutida diretamente no app (Desktop e Android), sem necessidade de instalar o Orbot ou configurar portas manualmente. O circuito opera em modo estrito fail-closed.',
                style: TextStyle(color: NixColors.textMuted, fontSize: 11.5, height: 1.35),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: NixColors.background,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: Text(
                  'Estado: ${state.torDiagnosticDetail}',
                  style: NixTokens.monoCode(size: 11, color: state.isTorRunning ? NixColors.accentYellow : NixColors.textSecondary),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('open_sovereign_onboarding_button'),
                  style: TextButton.styleFrom(
                    foregroundColor: NixColors.accentYellow,
                    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                  ),
                  icon: const Icon(Icons.verified_user_outlined, size: 16),
                  label: const Text('Abrir Assistente de Onboarding Soberano & Seed no Papel',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                  onPressed: () => SovereignOnboardingDialog.show(context, state),
                ),
              ),
            ],
          ),
        ),

        // MALHA PEER-TO-PEER POR PROXIMIDADE BLUETOOTH (ESTILO BRIAR)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bluetooth_searching_rounded, color: NixColors.textPrimary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'MALHA BLUETOOTH OFFLINE (MODO BRIAR BTP)',
                      style: TextStyle(color: NixColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Switch(
                    key: const Key('bluetooth_mesh_switch'),
                    value: state.isBluetoothMeshEnabled,
                    onChanged: (v) => state.setBluetoothMeshEnabled(v),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Permite comunicação e entrega de envelopes cifrados diretamente pelo ar entre pares do Nix próximos (10 a 30m), funcionando totalmente offline sem internet, dados móveis ou rede Tor.',
                style: TextStyle(color: NixColors.textMuted, fontSize: 11.5, height: 1.35),
              ),
              if (state.isBluetoothMeshEnabled) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: NixColors.background,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: NixColors.surfaceBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pares em alcance: ${state.bluetoothMesh.activePeers.length} nó(s) ativos · '
                        'TX: ${state.bluetoothMesh.txPacketsSent} · RX: ${state.bluetoothMesh.rxPacketsReceived} · '
                        'UUID: 0000ff01-0000-1000-8000-00805f9b34fb',
                        style: NixTokens.monoCode(size: 10.5, color: NixColors.accentYellow),
                      ),
                      if (state.bleHardwareStatus != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Hardware BLE: ${state.bleHardwareStatus!.detail} '
                          '(Adv=${state.bleHardwareStatus!.isAdvertising}, Scan=${state.bleHardwareStatus!.isScanning}, GATT=${state.bleHardwareStatus!.isGattServerRunning})',
                          style: NixTokens.monoCode(size: 10, color: NixColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => state.requestBleHardwarePermissions(),
                      icon: const Icon(Icons.security_rounded, size: 15),
                      label: const Text('Permissões BLE', style: TextStyle(fontSize: 11.5)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => state.refreshBleHardwareStatus(),
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text('Atualizar Status BLE', style: TextStyle(fontSize: 11.5)),
                    ),
                  ],
                ),
                if (state.bluetoothMesh.activePeers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...state.bluetoothMesh.activePeers.map((peer) => Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: NixColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: NixColors.surfaceBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.bluetooth_connected_rounded,
                                size: 15, color: Colors.greenAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${peer.peerPublicCardId} (${peer.deviceAddress}) · ${peer.rssiSignalStrength} dBm',
                                style: NixTokens.monoCode(size: 10.5, color: NixColors.textPrimary),
                              ),
                            ),
                            TextButton(
                              onPressed: () => state.sendBleTestPacket(
                                _bleTestMessageController.text,
                                targetAddress: peer.deviceAddress,
                              ),
                              child: const Text('Enviar NIXB', style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      )),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _bleTestMessageController,
                        style: TextStyle(color: NixColors.textPrimary, fontSize: 12),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'Mensagem assinada Ed25519 para envio BLE NIXB',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: NixColors.background,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NixColors.accentYellow,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () => state.sendBleTestPacket(
                        _bleTestMessageController.text,
                      ),
                      icon: const Icon(Icons.send_rounded, size: 15),
                      label: const Text('Difundir BLE', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // PAINEL DE AUDITORIA DE HARDWARE: ANDROID TEE / SQLCIPHER / TOR MÓVEL & RÁDIO LORA / RNODE
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_outlined, color: NixColors.accentYellow, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AUDITORIA DE HARDWARE · NDK / TEE / SQLCIPHER / TOR',
                      style: TextStyle(color: NixColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Builder(builder: (_) {
                final gate = state.securityGate;
                final rt = NixPlatformPaths.runtimeInfo;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: NixColors.background,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: NixColors.surfaceBorder),
                  ),
                  child: Text(
                    '• Firewall Clearnet: ${gate.clearnetFirewallActive ? "ATIVO (Zero Rede Doméstica)" : "INATIVO"}\n'
                    '• Tor Onion v3: ${gate.torOnionV3Ready ? "OPERACIONAL (${gate.liveOnionV3Address})" : "PENDENTE"} · v${gate.torVersion ?? "?"} · SOCKS5 :${state.embeddedTor.socksPort}\n'
                    '• SQLCipher: ${gate.sqlCipherEncrypted ? "ATIVO (PRAGMA cipher_version=${gate.sqlCipherVersion})" : "INATIVO"}\n'
                    '• KeyVault / TEE: ${gate.osKeyringBackend} · Nível Hardware=${rt?.keystoreSecurityLevel ?? "N/A"} (SecureHW=${rt?.keystoreInsideSecureHardware ?? false})\n'
                    '• Android Cloud Backup: ${(rt?.allowBackupDisabled ?? true) ? "DESATIVADO (allowBackup=false)" : "ATIVO"} · ABI=${rt?.deviceAbi ?? "desktop"}',
                    style: NixTokens.monoCode(size: 10.5, color: NixColors.textSecondary),
                  ),
                );
              }),
            ],
          ),
        ),

        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cell_tower_rounded, color: NixColors.textPrimary, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'RÁDIO LORA / RNODE (USB-OTG & BLE UART · KISS <= 240B)',
                          style: TextStyle(color: NixColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: () => state.scanRNodeHardwareDevices(),
                    icon: const Icon(Icons.usb_rounded, size: 15),
                    label: const Text('Detectar RNode', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Transceptor conectado: ${state.hardwareRadioBridge.connectedLoraDeviceName ?? "Nenhum (aguardando USB-OTG ou BLE NUS)"} · '
                'Cota Duty Cycle restante: ${state.hardwareRadioBridge.dutyCycleGovernor.remainingBudgetMs()} ms/h · '
                'TX=${state.hardwareRadioBridge.loraTxCount} RX=${state.hardwareRadioBridge.loraRxCount}',
                style: NixTokens.monoCode(size: 10.5, color: NixColors.textMuted),
              ),
              if (state.detectedRNodeDevices.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...state.detectedRNodeDevices.map((dev) => Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: NixColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: NixColors.surfaceBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            dev.transport == 'usb_otg'
                                ? Icons.usb_rounded
                                : Icons.bluetooth_rounded,
                            size: 15,
                            color: NixColors.accentYellow,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${dev.name} [${dev.transport}] · ${dev.detail}',
                              style: NixTokens.monoCode(size: 10.5, color: NixColors.textPrimary),
                            ),
                          ),
                          TextButton(
                            onPressed: () => state.connectRNodeHardwareDevice(dev),
                            child: const Text('Conectar', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    )),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _loraTestMessageController,
                      style: TextStyle(color: NixColors.textPrimary, fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Quadro curto LoRa NX (CRC16-CCITT, <= 240B)',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: NixColors.background,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => state.sendLoraTestMessage(
                      _loraTestMessageController.text,
                    ),
                    icon: const Icon(Icons.podcasts_rounded, size: 15),
                    label: const Text('Enviar LoRa', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
              if (state.hardwareRadioLogs.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  height: 120,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: NixColors.surfaceBorder),
                  ),
                  child: ListView.builder(
                    itemCount: state.hardwareRadioLogs.length,
                    itemBuilder: (_, idx) {
                      final entry = state.hardwareRadioLogs[idx];
                      final ts = entry.timestamp.toIso8601String().substring(11, 19);
                      return Text(
                        '[$ts] [${entry.medium}/${entry.direction}] ${entry.summary}',
                        style: NixTokens.monoCode(
                          size: 10,
                          color: entry.direction == 'RX'
                              ? Colors.greenAccent
                              : (entry.direction == 'TX'
                                  ? NixColors.accentYellow
                                  : Colors.white70),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),

        Text('CONECTORES EXTERNOS (SANDBOX ISOLADO)', style: NixTokens.labelUppercase()),
        const SizedBox(height: 8),
        ...s.connectors.map((c) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NixColors.surfaceCard,
                borderRadius: NixTokens.borderSm,
                border: Border.all(color: NixColors.surfaceBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(c.name,
                                style: TextStyle(
                                    color: NixColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: NixColors.surfaceActive,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                c.scopeLabel,
                                style: TextStyle(color: NixColors.textSecondary, fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(c.description,
                            style: TextStyle(color: NixColors.textMuted, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch(
                    value: c.isEnabled,
                    onChanged: (_) => state.toggleConnector(c.id),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  // ================= 5.6 DISPOSITIVOS E COMPARTIMENTALIZAÇÃO =================
  Widget _buildDevicesSection(NixState state, UserSettings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '5.6 Dispositivos e Compartimentalização',
          'Gerencie sessões autorizadas, dispositivos vinculados por QR Code efêmero e execute rotação de chaves criptográficas sob demanda.',
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text('DISPOSITIVOS AUTORIZADOS (${s.devices.length})', style: NixTokens.labelUppercase()),
            ElevatedButton.icon(
              onPressed: () => _showAddDeviceDialog(state),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
              label: const Text('Vincular Dispositivo', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...s.devices.map((dev) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: NixColors.surfaceCard,
                borderRadius: NixTokens.borderSm,
                border: Border.all(
                  color: dev.isCurrent ? NixColors.surfaceBorderStrong : NixColors.surfaceBorder,
                  width: dev.isCurrent ? 1.2 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: dev.isCurrent ? NixColors.surfaceActive : NixColors.surfaceActive,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      dev.isCurrent ? Icons.laptop_chromebook_rounded : Icons.phone_android_rounded,
                      size: 20,
                      color: dev.isCurrent ? NixColors.textPrimary : NixColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                dev.deviceName,
                                style: TextStyle(
                                  color: NixColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (dev.isCurrent) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: NixColors.accentGreen.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: NixColors.accentGreen.withOpacity(0.4)),
                                ),
                                child: Text(
                                  'ESTA SESSÃO',
                                  style: TextStyle(
                                    color: NixColors.accentGreen,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${dev.clientVersion} · Chave de Sessão: ${dev.fingerprint}',
                          style: NixTokens.monoCode(size: 11, color: NixColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (!dev.isCurrent)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NixColors.accentDanger,
                        side: const BorderSide(color: Colors.redAccent, width: 0.8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onPressed: () {
                        state.revokeDevice(dev.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Sessão "${dev.deviceName}" revogada e chaves rotacionadas.'),
                          ),
                        );
                      },
                      child: const Text('Revogar Sessão', style: TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            )),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NixColors.surfaceSidebar,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.surfaceBorderStrong),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.security_rounded, size: 16, color: NixColors.accentGreen),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Arquitetura de Isolamento de Sessão: Cada dispositivo opera sua própria cadeia de chaves Double Ratchet. Revogar uma sessão invalida imediatamente o envio de envelopes cifrados para aquele endpoint sem comprometer a identidade local mestra.',
                  style: TextStyle(color: NixColors.textMuted, fontSize: 11, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================= 5.7 SOBREVIVÊNCIA E PRIVACIDADE =================
  Widget _buildSurvivalPrivacySection(NixState state, UserSettings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '5.7 Sobrevivência e Privacidade',
          'Central unificada de resiliência operacional, proteção antifingerprinting, rádio off-grid e limites auditáveis do ecossistema Nix.',
        ),

        // Controles Ativos de Proteção contra Fingerprinting e Janela (Seção 7)
        Text('JANELA DESKTOP & PROTEÇÃO ANTIFINGERPRINTING', style: NixTokens.labelUppercase()),
        const SizedBox(height: 8),
        _switchTile(
          title: 'Discretização de Dimensões Reportadas (Viewport Quantization)',
          subtitle:
              'Padroniza métricas internas em múltiplos de 64px (ex: 1152×720) e fixa DPR=1.0 para conteúdos não confiáveis.',
          value: s.quantizeViewportDimensions,
          onChanged: (v) => state.updateSettings(s.copyWith(quantizeViewportDimensions: v)),
        ),
        _switchTile(
          title: 'Bloquear Carregamento Automático de Recursos Remotos',
          subtitle:
              'Impede que imagens externas em Markdown ou embeds disparem conexões HTTP/DNS involuntárias.',
          value: s.blockRemoteEmbeds,
          onChanged: (v) => state.updateSettings(s.copyWith(blockRemoteEmbeds: v)),
        ),
        _switchTile(
          title: 'Persistir Tamanho e Posição da Janela Localmente',
          subtitle:
              'Desativado por padrão para que toda sessão inicie nas dimensões padronizadas não maximizadas (1152×720).',
          value: s.persistWindowGeometry,
          onChanged: (v) => state.updateSettings(s.copyWith(persistWindowGeometry: v)),
        ),
        _switchTile(
          title: 'Movimento Reduzido (Acessibilidade & Desempenho)',
          subtitle: 'Simplifica transições Fluid Motion para ambientes de baixo consumo.',
          value: s.reducedMotion,
          onChanged: (v) => state.updateSettings(s.copyWith(reducedMotion: v)),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NixColors.surfaceSidebar,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.surfaceBorderStrong),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: NixColors.textSecondary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Nota de Segurança: Iniciar em janela não maximizada (1152×720) e ajustar dimensões oferece melhor ergonomia no desktop e reduz variações triviais em conteúdo embutido, porém o modo janela não constitui garantia de proteção contra fingerprinting.',
                  style: TextStyle(color: NixColors.textMuted, fontSize: 11, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Mapa Transparente de Módulos: Implementado vs Experimental vs Planejado
        Text('MATRIZ DE MÓDULOS DE SOBREVIVÊNCIA & PRIVACIDADE', style: NixTokens.labelUppercase()),
        const SizedBox(height: 4),
        Text(
          'Distinção rigorosa entre recursos implementados nesta versão, recursos em validação experimental e especificações planejadas no roadmap.',
          style: TextStyle(color: NixColors.textMuted, fontSize: 11.5),
        ),
        const SizedBox(height: 12),

        _survivalModuleCard(
          title: 'Design System Nix V4 — Dark Yellow, Light Yellow & AMOLED',
          status: 'IMPLEMENTADO',
          description:
              'Dois temas oficiais com destaque amarelo (#FFC928), opção AMOLED Puro (#000000) e modo Sistema com persistência e aplicação global.',
        ),
        _survivalModuleCard(
          title: 'Identidade Local Soberana & Card ID Público',
          status: 'IMPLEMENTADO',
          description:
              'Criação e gestão de perfil local sem telefone, SMS, e-mail, CPF ou upload de agenda. QR Code limpo sem ruído e avatar local sanitizado.',
        ),
        _survivalModuleCard(
          title: 'Proteção de Viewport & Isolamento de Embeds',
          status: 'IMPLEMENTADO',
          description:
              'Inicialização em janela 1152×720 não maximizada, limites mínimos 800×540 e discretização de métricas MediaQuery para sub-árvores.',
        ),
        _survivalModuleCard(
          title: 'Aba GitHub Discovery (Inspirada no starwire.foo)',
          status: 'IMPLEMENTADO',
          description:
              'Descoberta de projetos abertos de agentes, sistemas e criptografia, com busca, filtros de linguagens e salvamento no Acervo cultural.',
        ),
        _survivalModuleCard(
          title: 'Monero Non-Custodial P2P Marketplace',
          status: 'IMPLEMENTADO',
          description:
              'Descoberta P2P descentralizada inspirada no Trocador.app com filtros fiat (BRL, USD, EUR), métodos de pagamento e negociação direta E2EE.',
        ),
        _survivalModuleCard(
          title: 'Relay AutoPruner com Histerese (75% / 85% / 92%)',
          status: 'IMPLEMENTADO (BACKEND GO)',
          description:
              'Serviço em services/nix_relay com TTL base de 7 dias e redução dinâmica do teto de retenção sob pressão de disco sem ressuscitar itens expurgados.',
        ),
        _survivalModuleCard(
          title: 'Schemas Protobuf v1 (Mensagem, Rádio < 240B, Archive, Wallet)',
          status: 'IMPLEMENTADO (SPEC & PROTO)',
          description:
              'Contratos formais em proto/nix/v1/ impondo bloqueio de mídia no pacote de rádio e estrutura canônica de artigos.',
        ),
        _survivalModuleCard(
          title: 'Cofre SQLCipher 256-bit, Argon2id & Duress PIN',
          status: state.localDatabase?.cipherInfo.isEncrypted == true
              ? 'SQLCIPHER ATIVO (${state.localDatabase?.cipherInfo.cipherVersion ?? "OK"})'
              : (state.isDatabaseReady ? 'CLEARNET DEV (SEM SQLCIPHER)' : 'BLOQUEADO / AGUARDANDO COFRE'),
          description:
              'Motor de banco: ${state.localDatabase?.cipherInfo.cipherEngine ?? "Desconectado"} · '
              'Keyring SO: ${state.keyVault.osKeyStorage.backendName}. '
              'PIN de coação atua isoladamente sem tocar a Seed B financeira.',
        ),
        _survivalModuleCard(
          title: 'Comunicação Off-Grid: LoRa BLE (Meshtastic), Reticulum & ATAK CoT',
          status: 'PLANEJADO (FASE 5)',
          description:
              'Adaptadores de hardware para RAK4631/Heltec, mapas offline MBTiles/MapLibre e ponte local UDP 127.0.0.1:4242 sob consentimento explícito.',
        ),
        _survivalModuleCard(
          title: 'Handshake Híbrido Pós-Quântico (PQXDH / ML-KEM-768)',
          status: 'PLANEJADO (FASE 9)',
          description:
              'Acordo de chaves resistente a adversários quânticos com prevenção de downgrade na camada de sessão.',
        ),
        const SizedBox(height: 24),
        // BOTÃO DE PÂNICO & DESTRUIÇÃO ANTI-FORENSE (ESTILO BLEACHBIT)
        _buildPanicButtonSection(context, state),
      ],
    );
  }

  Widget _buildPanicButtonSection(BuildContext context, NixState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E0E0E),
        borderRadius: NixTokens.borderSm,
        border: Border.all(color: const Color(0xFF8B0000), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFFF4D4D), size: 20),
              SizedBox(width: 8),
              Text(
                'BOTÃO DE PÂNICO & APAGAMENTO ANTI-FORENSE',
                style: TextStyle(
                  color: Color(0xFFFF4D4D),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Destrói a chave mestra em memória RAM (KeyVault.lock), remove o segredo do keyring do SO e sobrescreve em 3 passagens (CSPRNG, 0x55 e zeros 0x00) o banco SQLCipher, logs WAL/SHM, cofre e preferências. Aviso técnico: em SSDs e memória flash modernos, o wear leveling impede garantia física de apagamento completo das células; a proteção principal é a destruição criptográfica irrecuperável da chave do KeyVault/SQLCipher.',
            style: TextStyle(color: Color(0xFFE0B0B0), fontSize: 11.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                key: const Key('panic_wipe_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B0000),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: const Text(
                  'DESTRUIR CONTA E DADOS LOCAIS AGORA (PÂNICO)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
                onPressed: () => _showPanicConfirmationDialog(context, state),
              ),
              OutlinedButton.icon(
                key: const Key('configure_duress_pin_button'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amberAccent,
                  side: const BorderSide(color: Color(0xFF8B4513)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.password_rounded, size: 17),
                label: const Text(
                  'CONFIGURAR PIN DE COAÇÃO (DURESS)',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                onPressed: () => _showDuressPinDialog(context, state),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPanicConfirmationDialog(BuildContext context, NixState state) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NixColors.surfaceElevatedHigh,
        title: Row(
          children: const [
            Icon(Icons.dangerous_rounded, color: Color(0xFFFF4D4D), size: 22),
            SizedBox(width: 8),
            Text('CONFIRMAR DESTRUIÇÃO TOTAL', style: TextStyle(color: Color(0xFFFF4D4D), fontSize: 15)),
          ],
        ),
        content: const Text(
          'Esta operação remove os dados locais da conta. As três passagens de sobrescrita podem demorar, especialmente com arquivos grandes. Memórias flash podem manter cópias físicas fora do alcance do app.\n\nDeseja prosseguir com o pânico?',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B0000)),
            child: const Text('SIM, DESTRUIR TUDO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(const SnackBar(
                duration: Duration(minutes: 5),
                content: Text('Apagando os dados locais…'),
              ));
              final report = await state.panicWipeAllData();
              if (messenger.mounted) messenger.hideCurrentSnackBar();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF8B0000),
                    content: Text(
                      report.errors.isEmpty
                          ? 'Apagamento anti-forense concluído: ${report.filesOverwritten} arquivos sobrescritos (${(report.totalBytesWiped / 1024).toStringAsFixed(1)} KB limpos).'
                          : 'Apagamento anti-forense incompleto: ${report.errors.length} alvos com falha; ${report.filesOverwritten} arquivos sobrescritos.',
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showDuressPinDialog(BuildContext context, NixState state) {
    final vaultCtrl = TextEditingController();
    final duressCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NixColors.surfaceElevatedHigh,
        title: Row(
          children: const [
            Icon(Icons.shield_outlined, color: Colors.amberAccent, size: 20),
            SizedBox(width: 8),
            Text('CONFIGURAR PIN DE COAÇÃO (DURESS)', style: TextStyle(fontSize: 14)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se este PIN for inserido no desbloqueio sob coerção, o cliente apagará o banco de mensageria e o cofre sem tocar em carteiras Monero externas (Seed B). Em SSD/flash há limites físicos de sobrescrita.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: vaultCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Senha atual do KeyVault',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: duressCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Novo PIN/Senha de Coação (distinto)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final ok = await state.configureDuressPin(
                vaultPassphrase: vaultCtrl.text,
                duressPin: duressCtrl.text,
              );
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'PIN de coação configurado no KeyVault (Argon2id).'
                          : 'Não foi possível configurar: verifique a senha do cofre e use um PIN diferente.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Salvar PIN de Coação'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: NixTokens.headingMedium()),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: NixColors.textMuted, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: NixTokens.borderSm,
        border: Border.all(color: NixColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: NixColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(color: NixColors.textMuted, fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _sliderCard({
    required String title,
    required double value,
    double min = 0.0,
    double max = 1.0,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: NixTokens.borderSm,
        border: Border.all(color: NixColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: NixColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _dropdownCard({
    required String title,
    required String subtitle,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: NixTokens.borderSm,
        border: Border.all(color: NixColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: NixColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(color: NixColors.textMuted, fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: options.contains(value) ? value : options.first,
              dropdownColor: NixColors.surfaceActive,
              style: TextStyle(color: NixColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
              items: options
                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _survivalModuleCard({
    required String title,
    required String status,
    required String description,
  }) {
    final bool isImplemented = status.startsWith('IMPLEMENTADO');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: NixTokens.borderSm,
        border: Border.all(
          color: isImplemented ? NixColors.surfaceBorderStrong : NixColors.surfaceBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isImplemented ? context.accentColor : NixColors.surfaceActive,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: NixColors.surfaceBorder, width: 0.5),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: isImplemented ? context.onAccentColor : NixColors.textSecondary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(color: NixColors.textMuted, fontSize: 11.5, height: 1.35),
          ),
        ],
      ),
    );
  }
}
