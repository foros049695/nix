import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln(
      'Uso: sign_release.dart <artefato> <versão> <arquivo-seed-ed25519-hex>',
    );
    exitCode = 64;
    return;
  }

  final artifact = File(args[0]);
  final seedHex = (await File(args[2]).readAsString()).trim();
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(seedHex)) {
    stderr.writeln('O arquivo de chave deve conter uma seed Ed25519 hexadecimal de 32 bytes.');
    exitCode = 65;
    return;
  }
  final signer = await NixIdentity.fromSeeds(
    ed25519Seed: List.generate(
      32,
      (index) => int.parse(seedHex.substring(index * 2, index * 2 + 2), radix: 16),
    ),
    x25519PrivateBytes: SecretKeyData.random(length: 32).bytes,
  );
  final manifest = await SignedReleaseManifest.signArtifact(
    signer: signer,
    version: args[1],
    artifactName: artifact.uri.pathSegments.last,
    artifactBytes: await artifact.readAsBytes(),
  );
  final output = File('${artifact.path}.sig.json');
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n',
    flush: true,
  );
  stdout.writeln(output.path);
}
