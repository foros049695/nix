import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/security/local_image_helper.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

void showProfileAvatarEditor(BuildContext context, NixState state) {
  var selectedPath = state.userProfile.customAvatarPath ?? '';
  var pathRevision = 0;
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
        final accent = context.accentColor;
        return AlertDialog(
          backgroundColor: NixColors.surfaceElevatedHigh,
          shape: RoundedRectangleBorder(
            borderRadius: NixTokens.borderModal,
            side: BorderSide(color: NixColors.surfaceBorderStrong),
          ),
          title: Text(
            'Imagem de perfil do Pager',
            style: TextStyle(
              color: NixColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selecione PNG, JPEG ou WebP do dispositivo. Os metadados EXIF/IPTC são removidos automaticamente antes do armazenamento local.',
                    style:
                        TextStyle(color: NixColors.textSecondary, fontSize: 12),
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
                      color: NixColors.surfaceCard,
                      borderRadius: NixTokens.borderSm,
                      border: Border.all(
                        color: currentStyle == 'local_file'
                            ? accent
                            : NixColors.surfaceBorderStrong,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('IMAGEM LOCAL (PNG / JPEG / WebP)',
                            style: NixTokens.labelUppercase()),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: pathRevision == 0
                                    ? const Key('avatar_local_path_input')
                                    : ValueKey(
                                        'avatar_local_path_input_$pathRevision'),
                                initialValue: selectedPath,
                                onChanged: (value) => selectedPath = value,
                                style: TextStyle(
                                    color: NixColors.textPrimary, fontSize: 12),
                                decoration: const InputDecoration(
                                  hintText: '/caminho/para/avatar.png',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: NixColors.textPrimary,
                                side: BorderSide(
                                    color: NixColors.surfaceBorderStrong),
                              ),
                              onPressed: () async {
                                try {
                                  final picked = await LocalImageHelper
                                      .pickImageNativeDesktop();
                                  if (picked == null || !context.mounted)
                                    return;
                                  setModalState(() {
                                    selectedPath = picked;
                                    pathRevision++;
                                    previewPath = picked;
                                    statusMsg = null;
                                  });
                                } on PlatformException catch (error) {
                                  if (context.mounted) {
                                    setModalState(() => statusMsg = error
                                            .message ??
                                        'Não foi possível importar a imagem.');
                                  }
                                }
                              },
                              icon: const Icon(Icons.folder_open_rounded,
                                  size: 15),
                              label: const Text('Procurar',
                                  style: TextStyle(fontSize: 11.5)),
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
                                  border: Border.all(color: accent, width: 2.0),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Transform.translate(
                                  offset: Offset(offsetX * 16, offsetY * 16),
                                  child: Transform.scale(
                                    scale: cropScale,
                                    child: Image.file(File(previewPath!),
                                        fit: BoxFit.cover),
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
                                      style: TextStyle(
                                          color: NixColors.textPrimary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    Slider(
                                      value: cropScale,
                                      min: 1.0,
                                      max: 2.4,
                                      activeColor: accent,
                                      onChanged: (v) =>
                                          setModalState(() => cropScale = v),
                                    ),
                                    Row(
                                      children: [
                                        Text('X',
                                            style: TextStyle(
                                                color: NixColors.textMuted,
                                                fontSize: 10)),
                                        Expanded(
                                          child: Slider(
                                            value: offsetX,
                                            min: -1.0,
                                            max: 1.0,
                                            activeColor: accent,
                                            onChanged: (v) => setModalState(
                                                () => offsetX = v),
                                          ),
                                        ),
                                        Text('Y',
                                            style: TextStyle(
                                                color: NixColors.textMuted,
                                                fontSize: 10)),
                                        Expanded(
                                          child: Slider(
                                            value: offsetY,
                                            min: -1.0,
                                            max: 1.0,
                                            activeColor: accent,
                                            onChanged: (v) => setModalState(
                                                () => offsetY = v),
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
                              style: TextStyle(
                                  color: NixColors.accentDanger, fontSize: 11)),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: context.onAccentColor,
                              ),
                              onPressed: () async {
                                final raw = selectedPath.trim();
                                if (!LocalImageHelper.isSupportedExtension(
                                    raw)) {
                                  setModalState(() => statusMsg =
                                      'Use apenas PNG, JPEG ou WebP.');
                                  return;
                                }
                                final cleaned = await LocalImageHelper
                                    .sanitizeAndStoreImage(raw);
                                if (!context.mounted) return;
                                if (cleaned == null) {
                                  setModalState(() => statusMsg =
                                      'Arquivo não encontrado no caminho informado.');
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
                                      content: Text(
                                          'Avatar local aplicado com metadados EXIF sanitizados.'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.check_rounded, size: 15),
                              label: const Text('Aplicar & Sanitizar EXIF',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold)),
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
                                  style: TextStyle(
                                      color: NixColors.accentDanger,
                                      fontSize: 11.5),
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
              child: Text('Fechar',
                  style: TextStyle(
                      color: NixColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
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
        color: isSelected
            ? ctx.accentColor.withValues(alpha: 0.14)
            : NixColors.surfaceCard,
        borderRadius: NixTokens.borderSm,
        border: Border.all(
          color: isSelected ? ctx.accentColor : NixColors.surfaceBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 16,
            color: isSelected ? ctx.accentTextColor : NixColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(
                        color: NixColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
