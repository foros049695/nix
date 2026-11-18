import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import 'qr_code_painter.dart';
import 'cultural_showcase.dart';

/// CARD ID — Cartão de Identidade Pública Soberana em Metal AMOLED Black Reluzente.
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
      displayName: _nameController.text,
      bio: _bioController.text,
    );
    setState(() => _isEditingBio = false);
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final profile = nixState.userProfile;

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
                              // Botão QR Code Rápido
                              Tooltip(
                                message: 'Ampliar QR Code da Identidade Pública',
                                child: InkWell(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => QrCodeZoomModal(
                                        publicId: profile.publicId,
                                        displayName: profile.displayName,
                                        qrPayload: profile.qrPublicPayload,
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white24, width: 0.8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 15),
                                        SizedBox(width: 5),
                                        Text(
                                          'QR ID',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // E. Engrenagem integrada ao Card ID -> Transição suave para Configurações
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
                                      color: Colors.white.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white24, width: 0.8),
                                    ),
                                    child: const Icon(
                                      Icons.settings_outlined,
                                      color: NixColors.textPrimary,
                                      size: 17,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),

                          // Centro do Cartão: Chip Metálico + Foto/Emblema Nyx + Dados do Titular + Mini QR
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
                                  // B. Foto de Perfil com Edição/Remoção
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
                                          child: _buildAvatarContent(profile.avatarStyle, profile.displayName),
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
                                  // Nome, Status Cultural e Member Since
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
                                                profile.displayName,
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
                                        const SizedBox(height: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: NixColors.surfaceBorder),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.movie_filter_outlined,
                                                  size: 12, color: NixColors.textSecondary),
                                              const SizedBox(width: 5),
                                              Flexible(
                                                child: Text(
                                                  profile.currentActivity,
                                                  style: const TextStyle(
                                                    color: NixColors.textSecondary,
                                                    fontSize: 11,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              // Mini QR Code Incorporado no Canto Direito do Cartão
                              InkWell(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => QrCodeZoomModal(
                                      publicId: profile.publicId,
                                      displayName: profile.displayName,
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
                                    size: const Size(62, 62),
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

                          // C. Biografia Editável
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
                                          labelText: 'Nome de Exibição / Pseudônimo',
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
                                            child: const Text('Cancelar',
                                                style: TextStyle(color: NixColors.textMuted, fontSize: 12)),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: NixColors.textPrimary,
                                              foregroundColor: Colors.black,
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
                                            Text('BIOGRAFIA & INTERESSES', style: NixTokens.labelUppercase()),
                                            const SizedBox(height: 4),
                                            Text(
                                              profile.bio.isEmpty
                                                  ? 'Sem biografia definida. Clique em editar para adicionar.'
                                                  : profile.bio,
                                              style: const TextStyle(
                                                color: NixColors.textSecondary,
                                                fontSize: 12.5,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 16, color: NixColors.textMuted),
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

                          // A. Identificador Público Destacado + Botão Copiar com Feedback Visual
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
                                          color: NixColors.textMuted,
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

  Widget _buildAvatarContent(String avatarStyle, String displayName) {
    if (avatarStyle == 'none') {
      return const Center(
        child: Icon(Icons.person_outline_rounded, color: NixColors.textSecondary, size: 34),
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
    // Padrão: Medalhão Oficial Nyx
    return Image.asset(
      'assets/images/nix_logo_128.png',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.shield_moon_outlined, color: Colors.white, size: 32),
      ),
    );
  }

  void _showAvatarEditorModal(BuildContext context, NixState state) {
    showDialog(
      context: context,
      builder: (ctx) {
        final currentStyle = state.userProfile.avatarStyle;
        return AlertDialog(
          title: const Text('Imagem de Perfil do Card ID'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selecione ou remova a representação visual da sua identidade pública. Metadados EXIF são sempre removidos.',
                  style: TextStyle(color: NixColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _avatarOptionTile(
                  ctx: ctx,
                  state: state,
                  styleKey: 'nyx_emblem',
                  title: 'Medalhão Clássico Nyx (Oficial)',
                  subtitle: 'Gravura da deusa Nyx em alta definição',
                  isSelected: currentStyle == 'nyx_emblem',
                ),
                const SizedBox(height: 8),
                _avatarOptionTile(
                  ctx: ctx,
                  state: state,
                  styleKey: 'monogram',
                  title: 'Monograma Tipográfico Metálico',
                  subtitle: 'Iniciais gravadas em fundo preto AMOLED',
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
                const SizedBox(height: 8),
                _avatarOptionTile(
                  ctx: ctx,
                  state: state,
                  styleKey: 'none',
                  title: 'Remover Foto de Perfil',
                  subtitle: 'Manter silhueta neutra anônima',
                  isSelected: currentStyle == 'none',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar', style: TextStyle(color: NixColors.textSecondary)),
            ),
          ],
        );
      },
    );
  }

  Widget _avatarOptionTile({
    required BuildContext ctx,
    required NixState state,
    required String styleKey,
    required String title,
    required String subtitle,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () {
        state.updateProfile(avatarStyle: styleKey);
        Navigator.pop(ctx);
      },
      borderRadius: NixTokens.borderSm,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? NixColors.surfaceActive : NixColors.surfaceSidebar,
          borderRadius: NixTokens.borderSm,
          border: Border.all(
            color: isSelected ? NixColors.textPrimary : NixColors.surfaceBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: isSelected ? Colors.white : NixColors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: const TextStyle(color: NixColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip metálico estilizado (inspirado nas referências 5 e 6 de cartão de metal preto).
class _MetallicChipWidget extends StatelessWidget {
  const _MetallicChipWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFD6CFC2),
            Color(0xFF9E9689),
            Color(0xFFE5DFD3),
            Color(0xFF8A8275),
          ],
        ),
        border: Border.all(color: Colors.black54, width: 1),
      ),
      child: CustomPaint(
        painter: _ChipContactsPainter(),
      ),
    );
  }
}

class _ChipContactsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black45
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(size.width * 0.33, 0), Offset(size.width * 0.33, size.height), paint);
    canvas.drawLine(Offset(size.width * 0.66, 0), Offset(size.width * 0.66, size.height), paint);
    canvas.drawLine(Offset(0, size.height * 0.35), Offset(size.width * 0.33, size.height * 0.35), paint);
    canvas.drawLine(Offset(0, size.height * 0.65), Offset(size.width * 0.33, size.height * 0.65), paint);
    canvas.drawLine(
        Offset(size.width * 0.66, size.height * 0.35), Offset(size.width, size.height * 0.35), paint);
    canvas.drawLine(
        Offset(size.width * 0.66, size.height * 0.65), Offset(size.width, size.height * 0.65), paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: size.width * 0.28,
          height: size.height * 0.52,
        ),
        const Radius.circular(3),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BrushedMetalPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.018)
      ..strokeWidth = 0.6;

    for (double y = 4; y < size.height; y += 5) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
