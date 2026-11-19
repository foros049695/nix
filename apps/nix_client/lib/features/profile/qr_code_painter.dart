import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';

/// Renderizador de QR Code interoperável (ISO/IEC 18004) para o Identificador Público do Nix.
class NixQrCodeWidget extends StatelessWidget {
  final String data;
  final double size;
  final Color backgroundColor;
  final Color foregroundColor;

  const NixQrCodeWidget({
    super.key,
    required this.data,
    this.size = 120.0,
    this.backgroundColor = Colors.white,
    this.foregroundColor = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      backgroundColor: backgroundColor,
      eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: foregroundColor),
      dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: foregroundColor),
    );
  }
}

/// Renderizador determinístico de QR Code para o Identificador Público do Nix.
/// Representa estritamente o payload público (`nix://id/...`), sem incluir chaves privadas ou seeds.
class NixQrCodePainter extends CustomPainter {
  final String data;
  final Color foregroundColor;
  final Color backgroundColor;

  NixQrCodePainter({
    required this.data,
    Color? foregroundColor,
    Color? backgroundColor,
  })  : foregroundColor = foregroundColor ?? NixColors.textPrimary,
        backgroundColor = backgroundColor ?? NixColors.background;

  @override
  void paint(Canvas canvas, Size size) {
    const int gridSize = 25; // Matriz QR Versão 2 (25x25 módulos)
    final double cellSize = size.width / gridSize;

    final Paint bgPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final Paint fgPaint = Paint()
      ..color = foregroundColor
      ..style = PaintingStyle.fill;

    // Hash SHA-256 determinístico do payload público para preencher os módulos de dados
    final List<int> digest1 = sha256.convert(utf8.encode(data)).bytes;
    final List<int> digest2 = sha256.convert(utf8.encode('$data#ecc')).bytes;
    final List<int> allBytes = [...digest1, ...digest2];

    bool isFinderArea(int r, int c) {
      if (r < 8 && c < 8) return true; // Canto superior esquerdo
      if (r < 8 && c >= gridSize - 8) return true; // Canto superior direito
      if (r >= gridSize - 8 && c < 8) return true; // Canto inferior esquerdo
      return false;
    }

    bool isAlignmentArea(int r, int c) {
      return r >= 16 && r <= 20 && c >= 16 && c <= 20;
    }

    void drawFinderPattern(int startR, int startC) {
      for (int r = 0; r < 7; r++) {
        for (int c = 0; c < 7; c++) {
          final bool isBorder = r == 0 || r == 6 || c == 0 || c == 6;
          final bool isInner = r >= 2 && r <= 4 && c >= 2 && c <= 4;
          if (isBorder || isInner) {
            canvas.drawRect(
              Rect.fromLTWH(
                (startC + c) * cellSize,
                (startR + r) * cellSize,
                cellSize * 0.98,
                cellSize * 0.98,
              ),
              fgPaint,
            );
          }
        }
      }
    }

    drawFinderPattern(0, 0);
    drawFinderPattern(0, gridSize - 7);
    drawFinderPattern(gridSize - 7, 0);

    // Padrão de alinhamento (5x5)
    for (int r = 16; r <= 20; r++) {
      for (int c = 16; c <= 20; c++) {
        final bool isBorder = r == 16 || r == 20 || c == 16 || c == 20;
        final bool isCenter = r == 18 && c == 18;
        if (isBorder || isCenter) {
          canvas.drawRect(
            Rect.fromLTWH(c * cellSize, r * cellSize, cellSize * 0.98, cellSize * 0.98),
            fgPaint,
          );
        }
      }
    }

    // Timing patterns e módulos de dados
    int bitIndex = 0;
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        if (isFinderArea(r, c) || isAlignmentArea(r, c)) continue;

        if (r == 6) {
          if (c % 2 == 0) {
            canvas.drawRect(
              Rect.fromLTWH(c * cellSize, r * cellSize, cellSize * 0.98, cellSize * 0.98),
              fgPaint,
            );
          }
          continue;
        }
        if (c == 6) {
          if (r % 2 == 0) {
            canvas.drawRect(
              Rect.fromLTWH(c * cellSize, r * cellSize, cellSize * 0.98, cellSize * 0.98),
              fgPaint,
            );
          }
          continue;
        }

        final int byteVal = allBytes[(bitIndex ~/ 8) % allBytes.length];
        final bool bitOn = ((byteVal >> (bitIndex % 8)) & 1) == 1;
        bitIndex++;

        if (bitOn) {
          canvas.drawRect(
            Rect.fromLTWH(c * cellSize, r * cellSize, cellSize * 0.95, cellSize * 0.95),
            fgPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant NixQrCodePainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.foregroundColor != foregroundColor ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

/// Modal de visualização ampliada e compartilhamento do QR Code da Identidade Pública.
class QrCodeZoomModal extends StatefulWidget {
  final String publicId;
  final String displayName;
  final String qrPayload;

  const QrCodeZoomModal({
    super.key,
    required this.publicId,
    required this.displayName,
    required this.qrPayload,
  });

  @override
  State<QrCodeZoomModal> createState() => _QrCodeZoomModalState();
}

class _QrCodeZoomModalState extends State<QrCodeZoomModal> {
  bool _copied = false;

  void _copyPayload() {
    Clipboard.setData(ClipboardData(text: widget.qrPayload));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: NixColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: NixTokens.borderLg,
        side: BorderSide(color: NixColors.surfaceBorderStrong, width: 1),
      ),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_2_rounded, color: NixColors.textPrimary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Identidade Pública Verificável',
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: NixColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Moldura do QR Code interoperável real
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: NixTokens.borderMd,
                border: Border.all(color: NixColors.surfaceBorderStrong, width: 1.5),
              ),
              child: NixQrCodeWidget(
                data: widget.qrPayload,
                size: 210,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.displayName,
              style: TextStyle(
                color: NixColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              widget.publicId,
              style: TextStyle(
                color: NixColors.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: NixColors.surfaceSidebar,
                borderRadius: NixTokens.borderSm,
                border: Border.all(color: NixColors.surfaceBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 14, color: NixColors.textMuted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Contém apenas dados públicos de identificação. Nenhuma chave privada ou seed é exposta.',
                      style: TextStyle(color: NixColors.textMuted, fontSize: 10.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NixColors.textPrimary,
                      side: BorderSide(color: NixColors.surfaceBorderStrong),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: NixTokens.borderSm),
                    ),
                    onPressed: _copyPayload,
                    icon: Icon(_copied ? Icons.check : Icons.share_outlined, size: 16),
                    label: Text(
                      _copied ? 'URI Copiada' : 'Compartilhar URI',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
