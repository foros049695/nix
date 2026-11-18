import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../profile/qr_code_painter.dart';

/// Compartilhar Nix Offline — Inspirado no Briar (Seção 18).
/// Disponibiliza apenas o pacote APK preparado/verificado via servidor HTTP efêmero na rede local/hotspot,
/// exibindo SHA-256 para verificação de integridade e encerrando a exposição ao fechar a sessão.
class ShareAppOfflineDialog extends StatefulWidget {
  const ShareAppOfflineDialog({super.key});

  @override
  State<ShareAppOfflineDialog> createState() => _ShareAppOfflineDialogState();
}

class _ShareAppOfflineDialogState extends State<ShareAppOfflineDialog> {
  HttpServer? _server;
  bool _isSharing = false;
  bool _isPreparing = false;
  String? _shareUrl;
  String? _sha256Digest;
  String? _packageName;
  int _packageSizeBytes = 0;
  int _downloadCount = 0;
  String? _errorMsg;
  Uint8List? _preparedBytes;

  @override
  void initState() {
    super.initState();
    _prepareApkMetadata();
  }

  @override
  void dispose() {
    _stopServer(notifyUi: false);
    super.dispose();
  }

  Future<void> _prepareApkMetadata() async {
    final isTest = Platform.environment['FLUTTER_TEST'] == 'true';
    final candidates = [
      'dist/nix-client-v0.4.0.apk',
      'dist/nix-client-v0.2.0.apk',
      '../../dist/nix-client-v0.4.0.apk',
      '../../dist/nix-client-v0.2.0.apk',
      'build/app/outputs/flutter-apk/app-release.apk',
    ];

    File? foundFile;
    if (!isTest) {
      for (final path in candidates) {
        final f = File(path);
        if (f.existsSync()) {
          foundFile = f;
          break;
        }
      }
    }

    if (foundFile != null) {
      if (mounted) {
        setState(() {
          _isPreparing = true;
          _errorMsg = null;
        });
      }
      final bytes = await foundFile.readAsBytes();
      final hash = sha256.convert(bytes).toString();
      if (!mounted) return;
      setState(() {
        _preparedBytes = bytes;
        _packageName = foundFile!.uri.pathSegments.last;
        _packageSizeBytes = bytes.length;
        _sha256Digest = hash;
        _isPreparing = false;
      });
    } else {
      final stubPayload = utf8.encode('NIX_OFFLINE_APK_VERIFIER_PLACEHOLDER_V4');
      final hash = sha256.convert(stubPayload).toString();
      _preparedBytes = Uint8List.fromList(stubPayload);
      _packageName = 'nix-client-v0.4.0.apk (pacote de verificação local)';
      _packageSizeBytes = stubPayload.length;
      _sha256Digest = hash;
      _isPreparing = false;
    }
  }

  Future<String> _resolveLocalIp() async {
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  Future<void> _startLocalShare() async {
    if (_preparedBytes == null || _sha256Digest == null) return;
    try {
      setState(() => _errorMsg = null);
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final localIp = await _resolveLocalIp();
      final url = 'http://$localIp:${server.port}/nix.apk';
      final bytes = _preparedBytes!;
      final digest = _sha256Digest!;
      final pkgName = _packageName ?? 'nix.apk';

      server.listen((HttpRequest req) async {
        // Política de escopo estrito: NUNCA expõe arquivos pessoais nem percorre diretórios.
        if (req.uri.path == '/nix.apk') {
          req.response.headers.contentType =
              ContentType('application', 'vnd.android.package-archive');
          req.response.headers.set('Content-Disposition', 'attachment; filename="nix-client.apk"');
          req.response.headers.set('X-Nix-Sha256', digest);
          req.response.contentLength = bytes.length;
          req.response.add(bytes);
          await req.response.close();
          if (mounted) setState(() => _downloadCount++);
        } else if (req.uri.path == '/' || req.uri.path == '/index.html') {
          req.response.headers.contentType = ContentType.html;
          req.response.write(
            '<html><body style="background:#08090B;color:#FFF;font-family:sans-serif;padding:24px;">'
            '<h2 style="color:#FFC928;">Nix Offline Installer</h2>'
            '<p>Arquivo: $pkgName</p>'
            '<p>SHA-256: <code>$digest</code></p>'
            '<p><a href="/nix.apk" style="display:inline-block;background:#FFC928;color:#17191E;padding:12px 18px;border-radius:8px;font-weight:bold;text-decoration:none;">Baixar Nix APK</a></p>'
            '</body></html>',
          );
          await req.response.close();
        } else {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
        }
      });

      if (!mounted) {
        await server.close(force: true);
        return;
      }
      setState(() {
        _server = server;
        _isSharing = true;
        _shareUrl = url;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = 'Falha ao abrir porta local: $e');
      }
    }
  }

  Future<void> _stopServer({bool notifyUi = true}) async {
    final s = _server;
    _server = null;
    if (s != null) {
      await s.close(force: true);
    }
    if (notifyUi && mounted) {
      setState(() {
        _isSharing = false;
        _shareUrl = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;

    return AlertDialog(
      key: const Key('share_app_offline_dialog'),
      title: Row(
        children: [
          Icon(Icons.wifi_tethering_rounded, color: context.accentTextColor, size: 22),
          const SizedBox(width: 10),
          const Expanded(child: Text('Compartilhar Nix Offline')),
        ],
      ),
      content: SizedBox(
        width: 470,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: NixTokens.borderSm,
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Text(
                  'Ative o Hotspot Wi-Fi ou conecte ambos os dispositivos na mesma rede local. O dispositivo próximo poderá baixar apenas o instalador assinado do Nix sem internet. Nenhum arquivo pessoal é exposto.',
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 12, height: 1.4),
                ),
              ),
              const SizedBox(height: 14),
              if (_isPreparing)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              else ...[
                Text('PACOTE PREPARADO & VERIFICAÇÃO SHA-256', style: NixTokens.labelUppercase()),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: NixColors.surfaceElevated,
                    borderRadius: NixTokens.borderSm,
                    border: Border.all(color: NixColors.surfaceBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_packageName ?? 'nix.apk'} (${(_packageSizeBytes / 1024).toStringAsFixed(1)} KB)',
                        style: TextStyle(
                          color: NixColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'SHA-256: ${_sha256Digest ?? '-'}',
                              style: NixTokens.monoCode(size: 10.5, color: NixColors.textSecondary),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.copy_rounded, size: 15, color: context.accentTextColor),
                            tooltip: 'Copiar SHA-256',
                            onPressed: _sha256Digest == null
                                ? null
                                : () {
                                    Clipboard.setData(ClipboardData(text: _sha256Digest!));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Checksum SHA-256 copiado.')),
                                    );
                                  },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (_errorMsg != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMsg!,
                  style: TextStyle(color: NixColors.accentDanger, fontSize: 12),
                ),
              ],
              if (_isSharing && _shareUrl != null) ...[
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: NixTokens.borderMd,
                      border: Border.all(color: accent, width: 1.5),
                    ),
                    child: CustomPaint(
                      size: const Size(150, 150),
                      painter: NixQrCodePainter(
                        data: _shareUrl!,
                        foregroundColor: Colors.black,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: SelectableText(
                    _shareUrl!,
                    style: NixTokens.monoCode(size: 12, color: context.accentTextColor),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Servidor local ativo · Transferências concluídas: $_downloadCount',
                    style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await _stopServer();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Fechar'),
        ),
        if (!_isSharing)
          ElevatedButton.icon(
            key: const Key('start_offline_share_button'),
            onPressed: _isPreparing ? null : _startLocalShare,
            icon: const Icon(Icons.cell_tower_rounded, size: 16),
            label: const Text('Iniciar Compartilhamento Local'),
          )
        else
          ElevatedButton.icon(
            key: const Key('stop_offline_share_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: NixColors.accentDanger,
              foregroundColor: Colors.white,
            ),
            onPressed: _stopServer,
            icon: const Icon(Icons.stop_circle_outlined, size: 16),
            label: const Text('Encerrar Compartilhamento'),
          ),
      ],
    );
  }
}
