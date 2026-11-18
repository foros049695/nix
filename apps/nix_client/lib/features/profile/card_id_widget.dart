import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/user_profile.dart';
import '../../core/security/local_image_helper.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import 'qr_code_painter.dart';
import 'cultural_showcase.dart';

/// CARD ID — Cartão de Identidade Pública Soberana em Metal Preto Reluzente.
/// Sem status "Assistindo", sem botão QR duplicado, com suporte a imagem local + recorte e sanitização EXIF.
class CardIdWidget extends StatefulWidget {
  final VoidCallback? onOpenSettings;
  final bool showCulturalPassport;

  const CardIdWidget({
    super.key,
    this.onOpenSettings,
    this.showCulturalPassport = true,
  });

  @override
  State<CardIdWidget> createState() => _CardIdWidgetState();
}

class _CardIdWidgetState extends State<CardIdWidget> {
  Offset _hoverAlign = Offset.zero;
  bool _isHovered = false;
  bool _idCopied = false;
  bool _isEditingBio = false;
  late TextEditingController _bioController;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final profile = context.read<NixState>().userProfile;
    _bioController = TextEditingController(text: profile.bio);
    _nameController = TextEditingController(text: profile.displayName);
  }

  @override
  void dispose() {
    _bioController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _copyPublicId(String publicId) {
    Clipboard.setData(ClipboardData(text: publicId));
    setState(() => _idCopied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Identificador público copiado para a área de transferência.'),
        duration: Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _idCopied = false);
    });
  }

  void _saveBioAndName(NixState state) {
    state.updateProfile(
      displayName: _nameController.text.trim(),
      bio: _bioController.text.trim(),
    );
    setState(() => _isEditingBio = false);
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final profile = nixState.userProfile;
    final effectiveName = profile.effectiveDisplayName;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ================= CARTÃO METÁLICO AMOLED BLACK RELUZENTE =================
              MouseRegion(
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() {
                  _isHovered = false;
                  _hoverAlign = Offset.zero;
                }),
                onHover: (event) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box != null && box.hasSize) {
                    final local = box.globalToLocal(event.position);
                    final dx = ((local.dx / box.size.width) * 2 - 1).clamp(-1.0, 1.0);
                    final dy = ((local.dy / 340) * 2 - 1).clamp(-1.0, 1.0);
                    setState(() => _hoverAlign = Offset(dx, dy));
                  }
                },
                child: AnimatedContainer(
                  duration: NixTokens.motionMedium,
                  curve: NixTokens.curveStandard,
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 680),
                  padding: const EdgeInsets.all(2), // Borda metálica chanfrada
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(NixTokens.radiusCardId),
                    gradient: LinearGradient(
                      begin: Alignment(-0.8 + _hoverAlign.dx * 0.4, -0.9 + _hoverAlign.dy * 0.4),
                      end: Alignment(0.8 - _hoverAlign.dx * 0.4, 0.9 - _hoverAlign.dy * 0.4),
                      colors: [
                        _isHovered ? const Color(0xFF757984) : const Color(0xFF484B52),
                        const Color(0xFF1C1D20),
                        _isHovered ? const Color(0xFF8C909C) : const Color(0xFF565962),
                        const Color(0xFF121315),
                      ],
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xDD000000),
                        blurRadius: 32,
                        spreadRadius: 2,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(NixTokens.radiusCardId - 2),
                      gradient: LinearGradient(
                        begin: Alignment(-0.9 + _hoverAlign.dx * 0.5, -0.8 + _hoverAlign.dy * 0.5),
                        end: Alignment(0.9 - _hoverAlign.dx * 0.5, 0.8 - _hoverAlign.dy * 0.5),
                        colors: const [
                          Color(0xFF050506),
                          Color(0xFF111215),
                          Color(0xFF222429),
                          Color(0xFF0E0F12),
                          Color(0xFF030304),
                        ],
                        stops: const [0.0, 0.28, 0.48, 0.72, 1.0],
                      ),
                    ),
                    child: CustomPaint(
                      painter: _BrushedMetalPatternPainter(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Topo do Cartão: Gravura NIX SOVEREIGN + Engrenagem de Configurações
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(Icons.shield_outlined, color: NixColors.platinumAccent, size: 16),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'N I X   S O V E R E I G N   C A R D   I D',
                                  style: TextStyle(
                                    color: NixColors.platinumAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2.2,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Engrenagem integrada ao Card ID -> Transição suave para Configurações (Sem botão QR duplicado)
                              Tooltip(
                                message: 'Abrir Central de Configurações',
                                child: InkWell(
                                  key: const Key('card_id_settings_gear'),
                                  onTap: () {
                                    if (widget.onOpenSettings != null) {
                                      widget.onOpenSettings!();
                                    } else {
                                      nixState.transitionToSettings();
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: context.accentColor.withValues(alpha: 0.45),
                                        width: 0.9,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.settings_outlined,
                                      color: context.accentColor,
                                      size: 17,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),

                          // Centro do Cartão: Chip Metálico + Foto/Emblema Nyx + Dados do Titular + Mini QR Limpo
                          Wrap(
                            spacing: 20,
                            runSpacing: 16,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              // Chip Metálico Escovado + Avatar Editável
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const _MetallicChipWidget(),
                                  const SizedBox(width: 18),
                                  // Foto de Perfil com Edição/Remoção e Suporte a Imagem Local
                                  InkWell(
                                    onTap: () => _showAvatarEditorModal(context, nixState),
                                    borderRadius: BorderRadius.circular(44),
                                    child: Stack(
                                      children: [
                                        Container(
                                          width: 78,
                                          height: 78,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFF0A0A0C),
                                            border: Border.all(
                                              color: NixColors.platinumAccent.withOpacity(0.65),
                                              width: 1.8,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black87,
                                                blurRadius: 12,
                                              ),
                                            ],
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: _buildAvatarContent(profile, effectiveName),
                                        ),
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: NixColors.surfaceActive,
                                              shape: BoxShape.circle,
                                              border: Border.all(color: Colors.white38),
                                            ),
                                            child: const Icon(Icons.camera_alt_outlined, size: 12, color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Nome de Usuário (Opcional com Fallback Determinístico NX-XXXX)
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 260),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                effectiveName,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 1.4,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.white12,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.white24, width: 0.5),
                                              ),
                                              child: Text(
                                                'SINCE ${profile.memberSinceYear}',
                                                style: const TextStyle(
                                                  color: NixColors.platinumAccent,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1.0,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Icon(Icons.verified_user_rounded, size: 12, color: NixColors.accentGreen),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                profile.displayName.isEmpty
                                                    ? 'Identidade Anônima Soberana'
                                                    : 'Identidade Criptográfica Verificada',
                                                style: TextStyle(
                                                  color: NixColors.textSecondary,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              // Mini QR Code Incorporado no Canto Direito do Cartão (limpo, sem textos poluídos)
                              InkWell(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => QrCodeZoomModal(
                                      publicId: profile.publicId,
                                      displayName: effectiveName,
                                      qrPayload: profile.qrPublicPayload,
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white30, width: 1),
                                  ),
                                  child: CustomPaint(
                                    size: const Size(64, 64),
                                    painter: NixQrCodePainter(
                                      data: profile.qrPublicPayload,
                                      foregroundColor: NixColors.platinumAccent,
                                      backgroundColor: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Biografia Editável
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.45),
                              borderRadius: NixTokens.borderSm,
                              border: Border.all(color: Colors.white12),
                            ),
                            child: _isEditingBio
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      TextField(
                                        controller: _nameController,
                                        maxLength: 32,
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                        decoration: const InputDecoration(
                                          labelText: 'Nome de Exibição / Pseudônimo (Deixe vazio para NX-XXXX anônimo)',
                                          counterText: '',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _bioController,
                                        maxLength: 180,
                                        maxLines: 2,
                                        style: const TextStyle(color: Colors.white, fontSize: 12.5),
                                        decoration: const InputDecoration(
                                          labelText: 'Biografia Curta (Máx 180 caracteres)',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: () => setState(() => _isEditingBio = false),
                                            child: Text('Cancelar',
                                                style: TextStyle(color: NixColors.textMuted, fontSize: 12)),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: context.accentColor,
                                              foregroundColor: context.onAccentColor,
                                              visualDensity: VisualDensity.compact,
                                            ),
                                            onPressed: () => _saveBioAndName(nixState),
                                            child: const Text('Salvar',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  )
                                : Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'BIOGRAFIA & INTERESSES',
                                              style: TextStyle(
                                                color: Color(0xFF9EA2AE),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 1.0,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              profile.bio.isEmpty
                                                  ? 'Sem biografia definida. Clique em editar para adicionar.'
                                                  : profile.bio,
                                              style: const TextStyle(
                                                color: Color(0xFFD5D8E0),
                                                fontSize: 12.5,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFFB7BAC4)),
                                        tooltip: 'Editar Biografia e Nome',
                                        onPressed: () {
                                          _bioController.text = profile.bio;
                                          _nameController.text = profile.displayName;
                                          setState(() => _isEditingBio = true);
                                        },
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 16),

                          // Identificador Público Destacado + Botão Copiar com Feedback Visual
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF08080A),
                              borderRadius: NixTokens.borderSm,
                              border: Border.all(color: Colors.white24, width: 1),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.fingerprint_rounded, color: NixColors.platinumAccent, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'IDENTIFICADOR PÚBLICO SOBERANO',
                                        style: TextStyle(
                                          color: Color(0xFF9EA2AE),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      SelectableText(
                                        profile.publicId,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'monospace',
                                          letterSpacing: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  key: const Key('copy_public_id_button'),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: _idCopied ? Colors.white : Colors.white.withOpacity(0.08),
                                    foregroundColor: _idCopied ? Colors.black : Colors.white,
                                    side: const BorderSide(color: Colors.white30),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  onPressed: () => _copyPublicId(profile.publicId),
                                  icon: Icon(_idCopied ? Icons.check_rounded : Icons.copy_rounded, size: 14),
                                  label: Text(
                                    _idCopied ? 'COPIADO' : 'COPIAR ID',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              if (widget.showCulturalPassport) ...[
                const SizedBox(height: 24),
                const CulturalShowcase(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarContent(UserProfile profile, String displayName) {
    final avatarStyle = profile.avatarStyle;
    final customPath = profile.customAvatarPath;

    if (avatarStyle == 'none') {
      return Center(
        child: Icon(Icons.person_outline_rounded, color: NixColors.platinumAccent, size: 34),
      );
    }
    if (avatarStyle == 'monogram') {
      return Center(
        child: Text(
          displayName.isNotEmpty ? displayName.substring(0, displayName.length >= 2 ? 2 : 1) : 'NX',
          style: const TextStyle(
            color: NixColors.platinumAccent,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      );
    }
    if (avatarStyle == 'sentinel') {
      return const Center(
        child: Icon(Icons.security_rounded, color: NixColors.platinumAccent, size: 34),
      );
    }
    if (avatarStyle == 'local_file' && customPath != null) {
      final file = File(customPath);
      if (file.existsSync()) {
        return Transform.translate(
          offset: Offset(profile.avatarCropOffsetX * 20, profile.avatarCropOffsetY * 20),
          child: Transform.scale(
            scale: profile.avatarCropScale.clamp(1.0, 2.5),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              width: 78,
              height: 78,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined, color: NixColors.platinumAccent, size: 30),
              ),
            ),
          ),
        );
      }
      return const Center(
        child: Icon(Icons.image_outlined, color: NixColors.platinumAccent, size: 36),
      );
    }
    // Padrão: Medalhão Vetorizado Oficial Nix sobre metal escuro
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Image.asset(
        'assets/images/nix_logo_light.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.shield_moon_outlined, color: Colors.white, size: 32),
        ),
      ),
    );
  }

  void _showAvatarEditorModal(BuildContext context, NixState state) {
    final pathCtrl = TextEditingController(text: state.userProfile.customAvatarPath ?? '');
    double cropScale = state.userProfile.avatarCropScale;
    double offsetX = state.userProfile.avatarCropOffsetX;
    double offsetY = state.userProfile.avatarCropOffsetY;
    String? previewPath = state.userProfile.customAvatarPath;
    String? statusMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final currentStyle = state.userProfile.avatarStyle;
          return AlertDialog(
            title: const Text('Imagem de Perfil do Card ID'),
            content: SizedBox(
              width: 430,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selecione PNG, JPEG ou WebP do dispositivo. Os metadados EXIF/IPTC são removidos automaticamente antes do armazenamento local.',
                      style: TextStyle(color: NixColors.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    _avatarOptionTile(
                      ctx: ctx,
                      state: state,
                      styleKey: 'nyx_emblem',
                      title: 'Emblema Vetorizado Nix (Oficial)',
                      subtitle: 'Nova gravura oficial em fundo transparente',
                      isSelected: currentStyle == 'nyx_emblem',
                    ),
                    const SizedBox(height: 8),
                    _avatarOptionTile(
                      ctx: ctx,
                      state: state,
                      styleKey: 'monogram',
                      title: 'Monograma Tipográfico Metálico',
                      subtitle: 'Iniciais gravadas em fundo escuro',
                      isSelected: currentStyle == 'monogram',
                    ),
                    const SizedBox(height: 8),
                    _avatarOptionTile(
                      ctx: ctx,
                      state: state,
                      styleKey: 'sentinel',
                      title: 'Selo Sentinela Monocromático',
                      subtitle: 'Ícone vetorial de segurança operacional',
                      isSelected: currentStyle == 'sentinel',
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: NixColors.surfaceElevated,
                        borderRadius: NixTokens.borderSm,
                        border: Border.all(
                          color: currentStyle == 'local_file'
                              ? context.accentColor
                              : NixColors.surfaceBorderStrong,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('IMAGEM LOCAL (PNG / JPEG / WebP)', style: NixTokens.labelUppercase()),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const Key('avatar_local_path_input'),
                                  controller: pathCtrl,
                                  style: TextStyle(color: NixColors.textPrimary, fontSize: 12),
                                  decoration: const InputDecoration(
                                    hintText: '/caminho/para/avatar.png',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final picked = await LocalImageHelper.pickImageNativeDesktop();
                                  if (picked != null) {
                                    pathCtrl.text = picked;
                                    setModalState(() {
                                      previewPath = picked;
                                      statusMsg = null;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.folder_open_rounded, size: 15),
                                label: const Text('Procurar', style: TextStyle(fontSize: 11.5)),
                              ),
                            ],
                          ),
                          if (previewPath != null &&
                              previewPath!.isNotEmpty &&
                              File(previewPath!).existsSync()) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: context.accentColor, width: 1.5),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Transform.translate(
                                    offset: Offset(offsetX * 16, offsetY * 16),
                                    child: Transform.scale(
                                      scale: cropScale,
                                      child: Image.file(File(previewPath!), fit: BoxFit.cover),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Recorte & Enquadramento (${cropScale.toStringAsFixed(1)}x)',
                                        style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                                      ),
                                      Slider(
                                        value: cropScale,
                                        min: 1.0,
                                        max: 2.4,
                                        onChanged: (v) => setModalState(() => cropScale = v),
                                      ),
                                      Row(
                                        children: [
                                          Text('X', style: TextStyle(color: NixColors.textMuted, fontSize: 10)),
                                          Expanded(
                                            child: Slider(
                                              value: offsetX,
                                              min: -1.0,
                                              max: 1.0,
                                              onChanged: (v) => setModalState(() => offsetX = v),
                                            ),
                                          ),
                                          Text('Y', style: TextStyle(color: NixColors.textMuted, fontSize: 10)),
                                          Expanded(
                                            child: Slider(
                                              value: offsetY,
                                              min: -1.0,
                                              max: 1.0,
                                              onChanged: (v) => setModalState(() => offsetY = v),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (statusMsg != null) ...[
                            const SizedBox(height: 6),
                            Text(statusMsg!,
                                style: TextStyle(color: NixColors.accentDanger, fontSize: 11)),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final raw = pathCtrl.text.trim();
                                  if (!LocalImageHelper.isSupportedExtension(raw)) {
                                    setModalState(() => statusMsg = 'Use apenas PNG, JPEG ou WebP.');
                                    return;
                                  }
                                  final cleaned = await LocalImageHelper.sanitizeAndStoreImage(raw);
                                  if (cleaned == null) {
                                    setModalState(() => statusMsg = 'Arquivo não encontrado no caminho informado.');
                                    return;
                                  }
                                  state.updateProfile(
                                    avatarStyle: 'local_file',
                                    customAvatarPath: cleaned,
                                    avatarCropScale: cropScale,
                                    avatarCropOffsetX: offsetX,
                                    avatarCropOffsetY: offsetY,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Avatar local aplicado com metadados EXIF sanitizados.'),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.check_rounded, size: 15),
                                label: const Text('Aplicar & Sanitizar EXIF', style: TextStyle(fontSize: 11.5)),
                              ),
                              if (state.userProfile.customAvatarPath != null) ...[
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () {
                                    state.updateProfile(
                                      avatarStyle: 'nyx_emblem',
                                      clearCustomAvatar: true,
                                    );
                                    Navigator.pop(ctx);
                                  },
                                  child: Text(
                                    'Remover Foto',
                                    style: TextStyle(color: NixColors.accentDanger, fontSize: 11.5),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _avatarOptionTile(
                      ctx: ctx,
                      state: state,
                      styleKey: 'none',
                      title: 'Sem Imagem (Máximo Anonimato)',
                      subtitle: 'Silhueta genérica sem traços visuais',
                      isSelected: currentStyle == 'none',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Fechar', style: TextStyle(color: NixColors.textSecondary)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _avatarOptionTile({
    required BuildContext ctx,
    required NixState state,
    required String styleKey,
    required String title,
    required String subtitle,
    required bool isSelected,
    VoidCallback? onSelectOverride,
  }) {
    return InkWell(
      onTap: () {
        if (onSelectOverride != null) {
          onSelectOverride();
        } else {
          state.updateProfile(avatarStyle: styleKey);
          Navigator.pop(ctx);
        }
      },
      borderRadius: NixTokens.borderSm,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? NixColors.surfaceActive : NixColors.surfaceCard,
          borderRadius: NixTokens.borderSm,
          border: Border.all(
            color: isSelected ? Colors.white38 : NixColors.surfaceBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 16,
              color: isSelected ? Colors.white : NixColors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: TextStyle(color: NixColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrushedMetalPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x08FFFFFF)
      ..strokeWidth = 1.0;

    for (double i = -size.height; i < size.width; i += 16) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height * 0.45, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MetallicChipWidget extends StatelessWidget {
  const _MetallicChipWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE2E4E8),
            Color(0xFFB0B4BC),
            Color(0xFF888C95),
            Color(0xFFB8BCC4),
          ],
        ),
        border: Border.all(color: const Color(0xFF6B6E76), width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _ChipLinesPainter(),
      ),
    );
  }
}

class _ChipLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF424449)
      ..strokeWidth = 0.8;

    canvas.drawLine(Offset(size.width * 0.35, 0), Offset(size.width * 0.35, size.height), paint);
    canvas.drawLine(Offset(size.width * 0.65, 0), Offset(size.width * 0.65, size.height), paint);
    canvas.drawLine(Offset(0, size.height * 0.5), Offset(size.width, size.height * 0.5), paint);

    final rect = Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height * 0.5),
      width: 14,
      height: 12,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
