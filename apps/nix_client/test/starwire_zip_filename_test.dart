import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/features/discovery/github_discovery_view.dart';

void main() {
  group('buildStarwireZipFilename & resolveStarwireZipFile', () {
    late Directory tempOutDir;

    setUp(() {
      tempOutDir =
          Directory.systemTemp.createTempSync('nix_starwire_zip_test_');
    });

    tearDown(() {
      if (tempOutDir.existsSync()) {
        tempOutDir.deleteSync(recursive: true);
      }
    });

    test('preserva caracteres válidos [A-Za-z0-9._-] e ponto interno como .github', () {
      expect(
        buildStarwireZipFilename('torproject', 'arti-core_1.2'),
        'torproject_arti-core_1.2.zip',
      );
      expect(
        buildStarwireZipFilename('dono', '.github'),
        'dono_.github.zip',
      );
      expect(
        buildStarwireZipFilename('.org', '.github'),
        '_org_.github.zip',
      );

      final uncreatedDir = Directory('${tempOutDir.path}/nested/downloads');
      final outFile = resolveStarwireZipFile(
        uncreatedDir,
        'dono',
        '.github',
      );
      expect(outFile.parent.absolute.path, uncreatedDir.absolute.path);
      expect(outFile.uri.pathSegments.last, 'dono_.github.zip');
    });

    test('neutraliza traversal com ../ e separadores de diretório', () {
      final fromTraversal = resolveStarwireZipFile(
        tempOutDir,
        '../../etc',
        'passwd',
      );
      expect(fromTraversal.parent.absolute.path, tempOutDir.absolute.path);
      expect(fromTraversal.uri.pathSegments.last.contains('..'), isFalse);

      final fromSlash = resolveStarwireZipFile(tempOutDir, 'nix', 'a/b');
      expect(fromSlash.parent.absolute.path, tempOutDir.absolute.path);
      expect(fromSlash.uri.pathSegments.last, 'nix_a_b.zip');

      final fromTrailingDot = resolveStarwireZipFile(
        tempOutDir,
        'dono',
        'repo.',
      );
      expect(fromTrailingDot.uri.pathSegments.last, 'dono_repo_.zip');
      expect(fromTrailingDot.uri.pathSegments.last.contains('..'), isFalse);

      final fromBackslash = resolveStarwireZipFile(
        tempOutDir,
        r'..\win\system32',
        'c:d?e*f',
      );
      expect(fromBackslash.parent.absolute.path, tempOutDir.absolute.path);
      expect(
        RegExp(r'^[A-Za-z0-9._-]+\.zip$')
            .hasMatch(fromBackslash.uri.pathSegments.last),
        isTrue,
      );
    });

    test('recusa owner ou name vazios ou compostos apenas por pontos', () {
      for (final invalid in ['', '   ', '.', '..', '...']) {
        expect(
          () => buildStarwireZipFilename(invalid, 'repo'),
          throwsFormatException,
          reason: 'owner inválido deveria falhar: "$invalid"',
        );
        expect(
          () => buildStarwireZipFilename('owner', invalid),
          throwsFormatException,
          reason: 'name inválido deveria falhar: "$invalid"',
        );
        expect(
          () => resolveStarwireZipFile(tempOutDir, invalid, 'repo'),
          throwsFormatException,
        );
      }
    });
  });
}
