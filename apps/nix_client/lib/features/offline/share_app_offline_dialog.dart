import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import '../../core/security/fail_closed_http_overrides.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../profile/qr_code_painter.dart';

/// Compartilhar Nix Offline — Inspirado no Briar (Seção 18 / Fase 9.4).
/// Disponibiliza apenas o pacote APK preparado e criptograficamente autenticado
/// (SHA-256 + manifesto assinado Ed25519 via [SignedReleaseManifest]) em servidor
/// HTTP efêmero na rede local/hotspot, encerrando a exposição ao fechar a sessão.
class ShareAppOfflineDialog extends StatefulWidget {
  final Uint8List? customApkBytes;
  final SignedReleaseManifest? customManifest;
  final SimplePublicKey? trustedPublisherKey;

  const ShareAppOfflineDialog({
    super.key,
    this.customApkBytes,
    this.customManifest,
    this.trustedPublisherKey,
  });

  /// Verifica criptograficamente a integridade SHA-256 e a assinatura Ed25519
  /// do pacote APK contra a chave pública confiável do publicador.
  static Future<bool> verifyOfflineApkAuthenticity({
    required List<int> apkBytes,
    required SignedReleaseManifest manifest,
    required SimplePublicKey trustedReleaseKey,
  }) {
    return manifest.verifyArtifactBytes(
      apkBytes,
      trustedReleaseKey: trustedReleaseKey,
    );
  }

  /// Baixa o APK e o manifesto `/nix.apk.sig.json` de um par na rede local
  /// e valida tanto o digest SHA-256 quanto a assinatura Ed25519 do publicador.
  static Future<({Uint8List apkBytes, SignedReleaseManifest manifest, bool verified})>
      downloadAndVerifyFromPeer({
    required Uri apkUrl,
    required SimplePublicKey trustedReleaseKey,
  }) async {
    return NixFailClosedHttpOverrides.runWithExplicitOfflineLanPeer(
      allowedLanHost: apkUrl.host,
      action: () async {
        final client = HttpClient();
        try {
          final apkReq = await client.getUrl(apkUrl);
          final apkRes = await apkReq.close();
          if (apkRes.statusCode != HttpStatus.ok) {
            throw HttpException('Falha HTTP ${apkRes.statusCode} ao baixar APK.');
          }
          final builder = BytesBuilder(copy: false);
          await for (final chunk in apkRes) {
            builder.add(chunk);
          }
          final apkBytes = builder.toBytes();

          final manifestUrl = apkUrl.replace(path: '/nix.apk.sig.json');
          final manReq = await client.getUrl(manifestUrl);
          final manRes = await manReq.close();
          if (manRes.statusCode != HttpStatus.ok) {
            throw HttpException('Falha HTTP ${manRes.statusCode} ao baixar manifesto Ed25519.');
          }
          final manBody = await utf8.decoder.bind(manRes).join();
          final manifest = SignedReleaseManifest.fromJson(
            jsonDecode(manBody) as Map<String, dynamic>,
          );

          final verified = await verifyOfflineApkAuthenticity(
            apkBytes: apkBytes,
            manifest: manifest,
            trustedReleaseKey: trustedReleaseKey,
          );
          return (apkBytes: apkBytes, manifest: manifest, verified: verified);
        } finally {
          client.close(force: true);
        }
      },
    );
  }

  @override
  State<ShareAppOfflineDialog> createState() => _ShareAppOfflineDialogState();
}

class _ShareAppOfflineDialogState extends State<ShareAppOfflineDialog> {
  HttpServer? _server;
  bool _isSharing = false;
  bool _isPreparing = false;
  bool _isAuthenticityVerified = false;
  String? _shareUrl;
  String? _sha256Digest;
  String? _signerEd25519Hex;
  String? _signatureHex;
  SignedReleaseManifest? _releaseManifest;
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
    if (widget.customApkBytes != null &&
        widget.customManifest != null &&
        widget.trustedPublisherKey != null) {
      final bytes = widget.customApkBytes!;
      final manifest = widget.customManifest!;
      final ok = await ShareAppOfflineDialog.verifyOfflineApkAuthenticity(
        apkBytes: bytes,
        manifest: manifest,
        trustedReleaseKey: widget.trustedPublisherKey!,
      );
      if (!mounted) return;
      setState(() {
        _preparedBytes = ok ? bytes : null;
        _packageName = manifest.artifactName;
        _packageSizeBytes = bytes.length;
        _sha256Digest = sha256.convert(bytes).toString();
        _releaseManifest = manifest;
        _signerEd25519Hex = manifest.signerEd25519Hex;
        _signatureHex = manifest.signatureHex;
        _isAuthenticityVerified = ok;
        _isPreparing = false;
        _errorMsg = ok
            ? null
            : '[Fail-Closed] Assinatura Ed25519 ou hash SHA-256 inválido para o APK informado.';
      });
      return;
    }

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
      final sigFile = File('${foundFile.path}.sig.json');
      SignedReleaseManifest? manifest;
      bool verified = false;
      String? err;
      if (sigFile.existsSync()) {
        try {
          manifest = SignedReleaseManifest.fromJson(
            jsonDecode(await sigFile.readAsString()) as Map<String, dynamic>,
          );
          final trustedKey = widget.trustedPublisherKey ?? _configuredPublisherKey();
          if (trustedKey == null) {
            throw StateError('Chave pública de distribuição não configurada.');
          }
          verified = await manifest.verifyArtifactBytes(
            bytes,
            trustedReleaseKey: trustedKey,
          );
          if (!verified) {
            err = '[Fail-Closed] Assinatura Ed25519 do manifesto .sig.json inválida.';
          }
        } catch (e) {
          err = '[Fail-Closed] Manifesto .sig.json corrompido: $e';
        }
      } else {
        err =
            '[Fail-Closed] Manifesto assinado (${foundFile.uri.pathSegments.last}.sig.json) ausente. O Nix exige assinatura Ed25519 além do SHA-256.';
      }
      if (!mounted) return;
      setState(() {
        _preparedBytes = verified ? bytes : null;
        _packageName = foundFile!.uri.pathSegments.last;
        _packageSizeBytes = bytes.length;
        _sha256Digest = hash;
        _releaseManifest = manifest;
        _signerEd25519Hex = manifest?.signerEd25519Hex;
        _signatureHex = manifest?.signatureHex;
        _isAuthenticityVerified = verified;
        _isPreparing = false;
        _errorMsg = err;
      });
    } else if (isTest) {
      final stubPayload = Uint8List.fromList(
        utf8.encode('NIX_OFFLINE_APK_VERIFIER_PLACEHOLDER_V4'),
      );
      final hash = sha256.convert(stubPayload).toString();
      final testSigner = await NixIdentity.fromSeeds(
        ed25519Seed: List<int>.generate(32, (i) => (i + 17) & 0xff),
        x25519PrivateBytes: List<int>.generate(32, (i) => (i + 49) & 0xff),
      );
      final manifest = await SignedReleaseManifest.signArtifact(
        signer: testSigner,
        version: '0.4.0',
        artifactName: 'nix-client-v0.4.0.apk',
        artifactBytes: stubPayload,
        issuedAtUnix: 1795046400,
      );
      final verified = await manifest.verifyArtifactBytes(
        stubPayload,
        trustedReleaseKey: testSigner.ed25519PublicKey,
      );
      if (!mounted) return;
      setState(() {
        _preparedBytes = stubPayload;
        _packageName = 'nix-client-v0.4.0.apk (modo teste)';
        _packageSizeBytes = stubPayload.length;
        _sha256Digest = hash;
        _releaseManifest = manifest;
        _signerEd25519Hex = manifest.signerEd25519Hex;
        _signatureHex = manifest.signatureHex;
        _isAuthenticityVerified = verified;
        _isPreparing = false;
      });
    } else {
      if (!mounted) return;
      setState(() {
        _preparedBytes = null;
        _packageName = null;
        _packageSizeBytes = 0;
        _sha256Digest = null;
        _isAuthenticityVerified = false;
        _isPreparing = false;
        _errorMsg =
            'Nenhum APK/pacote de release assinado encontrado em dist/ ou build/. Gere e assine um pacote antes de compartilhar.';
      });
    }
  }

  static SimplePublicKey? _configuredPublisherKey() {
    const hex = String.fromEnvironment('NIX_RELEASE_PUBLISHER_KEY_HEX');
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) return null;
    return SimplePublicKey(
      List.generate(32, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)),
      type: KeyPairType.ed25519,
    );
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
    if (_preparedBytes == null ||
        _sha256Digest == null ||
        !_isAuthenticityVerified ||
        _releaseManifest == null) {
      setState(() {
        _errorMsg =
            '[Fail-Closed] Compartilhamento recusado: pacote sem assinatura Ed25519 verificada.';
      });
      return;
    }
    try {
      setState(() => _errorMsg = null);
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final localIp = await _resolveLocalIp();
      final url = 'http://$localIp:${server.port}/nix.apk';
      final bytes = _preparedBytes!;
      final digest = _sha256Digest!;
      final manifest = _releaseManifest!;
      final pkgName = _packageName ?? 'nix.apk';

      server.listen((HttpRequest req) async {
        // Política de escopo estrito: NUNCA expõe arquivos pessoais nem percorre diretórios.
        if (req.uri.path == '/nix.apk') {
          req.response.headers.contentType =
              ContentType('application', 'vnd.android.package-archive');
          req.response.headers.set('Content-Disposition', 'attachment; filename="nix-client.apk"');
          req.response.headers.set('X-Nix-Sha256', digest);
          req.response.headers.set('X-Nix-Signer-Ed25519', manifest.signerEd25519Hex);
          req.response.headers.set('X-Nix-Signature-Ed25519', manifest.signatureHex);
          req.response.contentLength = bytes.length;
          req.response.add(bytes);
          await req.response.close();
          if (mounted) setState(() => _downloadCount++);
        } else if (req.uri.path == '/nix.apk.sig.json') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(manifest.toJson()));
          await req.response.close();
        } else if (req.uri.path == '/' || req.uri.path == '/index.html') {
          req.response.headers.contentType = ContentType.html;
          req.response.write(
            '<html><body style="background:#08090B;color:#FFF;font-family:sans-serif;padding:24px;">'
            '<h2 style="color:#FFC928;">Nix Offline Installer</h2>'
            '<p>Arquivo: $pkgName</p>'
            '<p>SHA-256: <code>$digest</code></p>'
            '<p>Assinante Ed25519: <code>${manifest.signerEd25519Hex}</code></p>'
            '<p><a href="/nix.apk" style="display:inline-block;background:#FFC928;color:#17191E;padding:12px 18px;border-radius:8px;font-weight:bold;text-decoration:none;">Baixar Nix APK</a></p>'
            '<p><a href="/nix.apk.sig.json" style="color:#FFC928;">Baixar Manifesto Assinado (.sig.json)</a></p>'
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
                Text('PACOTE PREPARADO · VERIFICAÇÃO SHA-256 & ED25519', style: NixTokens.labelUppercase()),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_packageName ?? 'nix.apk'} (${(_packageSizeBytes / 1024).toStringAsFixed(1)} KB)',
                              style: TextStyle(
                                color: NixColors.textPrimary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            key: const Key('offline_apk_authenticity_badge'),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (_isAuthenticityVerified
                                      ? NixColors.accentGreen
                                      : NixColors.accentDanger)
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: (_isAuthenticityVerified
                                        ? NixColors.accentGreen
                                        : NixColors.accentDanger)
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              _isAuthenticityVerified
                                  ? 'ED25519 VERIFICADO'
                                  : 'NÃO VERIFICADO',
                              style: TextStyle(
                                color: _isAuthenticityVerified
                                    ? NixColors.accentGreen
                                    : NixColors.accentDanger,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
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
                      if (_signerEd25519Hex != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Publicador Ed25519: ${_signerEd25519Hex!.substring(0, 16)}...',
                          style: NixTokens.monoCode(size: 10, color: NixColors.textMuted),
                        ),
                      ],
                      if (_signatureHex != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Assinatura Ed25519: ${_signatureHex!.substring(0, 20)}...',
                          style: NixTokens.monoCode(size: 10, color: NixColors.textMuted),
                        ),
                      ],
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
