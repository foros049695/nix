import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/security/anti_forensic_shredder.dart';

void main() {
  for (final name in [
    'storage',
    'sanitized_media',
    'encrypted_objects',
    'tor_data',
    'downloads'
  ]) {
    test('pânico remove $name sem seguir links externos', () async {
      final root = await Directory.systemTemp.createTemp('nix_dirs_probe_');
      addTearDown(() => root.delete(recursive: true));
      final base = await Directory('${root.path}/account').create();
      final outside = File('${root.path}/sentinel');
      await outside.writeAsString('preservar');
      final dir =
          await Directory('${base.path}/$name/nested').create(recursive: true);
      await File('${dir.path}/data').writeAsString('descartar');
      await Link('${dir.path}/link').create(outside.path);
      final report = await AntiForensicShredder.panicWipeAccount(
        customBaseDir: base.path,
      );
      expect(report.errors, isEmpty);
      expect(await Directory('${base.path}/$name').exists(), isFalse);
      expect(report.filesOverwritten, 1);
      expect(await outside.readAsString(), 'preservar');
    });

    test('pânico remove link na raiz de $name sem seguir destino', () async {
      final root = await Directory.systemTemp.createTemp('nix_links_probe_');
      addTearDown(() => root.delete(recursive: true));
      final base = await Directory('${root.path}/account').create();
      final outside = await Directory('${root.path}/outside').create();
      final sentinel = File('${outside.path}/sentinel');
      await sentinel.writeAsString('preservar');
      final link = await Link('${base.path}/$name').create(outside.path);
      final report = await AntiForensicShredder.panicWipeAccount(
        customBaseDir: base.path,
      );
      expect(report.errors, isEmpty);
      expect(await link.exists(), isFalse);
      expect(await sentinel.readAsString(), 'preservar');
    });
  }
}
