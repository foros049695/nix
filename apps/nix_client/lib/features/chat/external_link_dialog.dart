import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';

/// Diálogo seguro de confirmação para abertura de links externos e Onion.
/// Preserva a política de segurança e fail-closed do Nix, alertando o usuário
/// sobre possíveis vazamentos de IP caso abra links clearnet fora da rede Tor.
class ExternalLinkDialog extends StatelessWidget {
  final String url;

  const ExternalLinkDialog({super.key, required this.url});

  static Future<void> show(BuildContext context, String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => ExternalLinkDialog(url: trimmed),
    );
  }

  bool get _isOnion =>
      url.toLowerCase().contains('.onion') || url.toLowerCase().startsWith('onion:');

  Future<void> _openExternal(BuildContext context) async {
    Navigator.of(context).pop();
    try {
      if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('powershell.exe', ['Start-Process', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else {
        await Clipboard.setData(ClipboardData(text: url));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Link copiado. Abra no navegador com suporte Tor.'),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir o link externamente: $e')),
        );
      }
    }
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link copiado com segurança para a área de transferência.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnion = _isOnion;

    return Dialog(
      backgroundColor: NixColors.surfaceElevatedHigh,
      shape: RoundedRectangleBorder(
        borderRadius: NixTokens.borderCard,
        side: BorderSide(color: NixColors.surfaceBorderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isOnion ? Icons.shield_outlined : Icons.warning_amber_rounded,
                    color: isOnion ? Colors.cyanAccent : Colors.amberAccent,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isOnion ? 'Endereço Onion Detectado' : 'Link Externo (Clearnet)',
                      style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Destino selecionado:',
                style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: NixColors.surfaceElevated,
                  borderRadius: NixTokens.borderSm,
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: SelectableText(
                  url,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFF64B5F6),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isOnion ? Colors.cyan : Colors.amber).withValues(alpha: 0.1),
                  borderRadius: NixTokens.borderSm,
                  border: Border.all(
                    color: (isOnion ? Colors.cyan : Colors.amber).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  isOnion
                      ? 'Este endereço pertence à rede Tor (.onion). Para manter o isolamento criptográfico do Nix, recomendamos abrir este link exclusivamente no Tor Browser ou via proxy SOCKS5 local.'
                      : 'Aviso de Privacidade: Ao abrir links comuns fora do Nix, seu endereço IP real e tráfego DNS podem ficar visíveis ao servidor de destino e à operadora se o navegador padrão não estiver roteado pelo Tor.',
                  style: TextStyle(
                    color: NixColors.textSecondary,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancelar', style: TextStyle(color: NixColors.textMuted)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copyToClipboard(context),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copiar Link'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openExternal(context),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Abrir Navegador'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
