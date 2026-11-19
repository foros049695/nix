import 'package:nix_client/core/security/anti_forensic_shredder.dart';

Future<void> main(List<String> args) async {
  await AntiForensicShredder.panicWipeAccount(customBaseDir: args.single);
}
