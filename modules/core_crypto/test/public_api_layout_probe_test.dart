import 'dart:io';

import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:nix_core_crypto/nix_pqxdh.dart' as pq;
import 'package:test/test.dart';

void main() {
  test('o barrel mantém todos os tipos públicos existentes', () {
    final types = <Type>[
      NixIdentity,
      NixPublicBundle,
      SealedPayload,
      SealedEnvelope,
      PassphraseKdf,
      SignedPreKeyBundle,
      X3dh,
      RatchetHeader,
      RatchetCiphertext,
      DoubleRatchet,
      SignedRecord,
      ReplayGuard,
      PqKemProvider,
      PqxdhCombiner,
      SignedReleaseManifest,
    ];
    expect(types.toSet(), hasLength(15));
  });

  test('a entrada pública PQXDH mantém a identidade dos tipos', () {
    expect(pq.PqKemProvider, PqKemProvider);
    expect(pq.PqxdhCombiner, PqxdhCombiner);
    expect(pq.SignedReleaseManifest, SignedReleaseManifest);
  });

  test('implementações ficam em src sem depender dos barrels públicos', () {
    for (final name in ['nix_core_crypto.dart', 'nix_pqxdh.dart']) {
      final source = File('lib/$name').readAsStringSync();
      expect(source, isNot(contains(RegExp(r'^class ', multiLine: true))));
      expect(source, contains("export 'src/"));
    }
    final implementations = Directory('lib/src')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    expect(implementations, isNotEmpty);
    for (final file in implementations) {
      expect(file.readAsStringSync(), isNot(contains("../nix_")),
          reason: 'Implementações não podem importar os barrels públicos.');
    }
  });
}
