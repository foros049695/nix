import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'local_image_helper.dart';
import 'platform_runtime.dart';

/// Utilitário para downloads seguros de arquivos recebidos via chat,
/// garantindo aviso de segurança obrigatório, verificação SHA-256 e
/// sanitização de caminhos contra path traversal.
class SecureFileDownloadHelper {
  /// Diálogo obrigatório de confirmação de segurança para downloads de terceiros.
  static Future<bool> confirmDownload(
    BuildContext context, {
    required String fileName,
    int? byteSize,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.shield_outlined, color: Colors.amber, size: 22),
            SizedBox(width: 8),
            Text(
              'Aviso de Segurança',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Arquivos recebidos de terceiros podem conter conteúdo malicioso. '
              'Confira a origem antes de baixar ou abrir. '
              'O Nix não garante que os arquivos externos sejam seguros. Deseja continuar?',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.attachment, size: 16, color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (byteSize != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      LocalImageHelper.formatFileSize(byteSize),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('download_cancel_button'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('download_confirm_button'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Baixar mesmo assim'),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Sanitiza o nome do arquivo contra path traversal e caracteres perigosos.
  static String sanitizeFileName(String original) {
    var name = original.replaceAll('\\', '/').split('/').last;
    name = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_').trim();
    if (name.isEmpty || name == '.' || name == '..') {
      name = 'nix_download_${DateTime.now().millisecondsSinceEpoch}';
    }
    return name;
  }

  /// Salva arquivo com validação SHA-256 pré e pós gravação em pasta segura, sem auto-execução.
  static Future<File> saveFileSafely({
    required Uint8List bytes,
    required String rawFileName,
    String? expectedSha256Hex,
  }) async {
    // 1. Verificação de integridade local inicial
    final preHash = sha256.convert(bytes).toString();
    if (expectedSha256Hex != null &&
        expectedSha256Hex.isNotEmpty &&
        preHash.toLowerCase() != expectedSha256Hex.toLowerCase()) {
      throw StateError('Hash SHA-256 recebido diverge do hash esperado.');
    }

    // 2. Diretório seguro de downloads
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final downloadsDir = Directory(
      home.isNotEmpty ? '$home/Downloads' : NixPlatformPaths.resolveDataFile('downloads'),
    );
    await downloadsDir.create(recursive: true);

    // 3. Sanitização do nome do arquivo
    final cleanName = sanitizeFileName(rawFileName);
    final targetFile = File('${downloadsDir.path}/$cleanName');

    // 4. Gravação segura
    await targetFile.writeAsBytes(bytes, flush: true);

    // 5. Verificação pós-gravação
    final savedBytes = await targetFile.readAsBytes();
    final postHash = sha256.convert(savedBytes).toString();
    if (postHash != preHash) {
      await targetFile.delete();
      throw StateError('Corrupção detectada durante a gravação em disco.');
    }

    return targetFile;
  }
}
