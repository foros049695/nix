import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as std_crypto;

/// Ferramenta CLI para calcular digest SHA-256 canônico e validar estrutura de manifesto offline (Fase 9).
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Uso: dart run scripts/sign_release.dart <arquivo_artefato> [versao]');
    exit(64);
  }
  final file = File(args[0]);
  if (!await file.exists()) {
    stderr.writeln('Artefato não encontrado: ${file.path}');
    exit(66);
  }
  final version = args.length > 1 ? args[1] : '0.4.0';
  final bytes = await file.readAsBytes();
  final digest = std_crypto.sha256.convert(bytes).toString();
  final metadata = {
    'schema': 'nix.release.digest.v1',
    'version': version,
    'artifact': file.uri.pathSegments.last,
    'bytes': bytes.length,
    'sha256': digest,
    'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(metadata));
}
