import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:nix_client/core/media/catalog_diagnostics.dart';
import 'package:nix_client/core/media/media_index_updater.dart';
import 'package:nix_client/core/security/fail_closed_http_overrides.dart';

void main() {
  HttpOverrides.global = null;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late KeyPair keyPair;
  late String pubKeyHex;
  late CatalogPublisherKeyring keyring;

  setUpAll(() async {
    final ed = Ed25519();
    keyPair = await ed.newKeyPair();
    final pubKey = await keyPair.extractPublicKey() as SimplePublicKey;
    pubKeyHex = SignedCatalogManifest.bytesToHex(pubKey.bytes);
    keyring = CatalogPublisherKeyring(
      trustedKeysHex: {pubKeyHex},
      allowTestFixtureKey: true,
      isProductionMode: false,
    );
  });

  group('CatalogDiagnostics 6-Layer Verification', () {
    test('Camadas 4, 5 e 6 executam com sucesso quando manifesto é válido e assinado', () async {
      final manifest = await SignedCatalogManifest.signArtifact(
        signerKeyPair: keyPair,
        version: 5,
        artifactName: 'catalog_v5.db',
        artifactBytes: utf8.encode('NIX-TEST-CATALOG-DATA'),
        entryCount: 42,
      );

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(manifest.toJson()));
        req.response.close();
      });

      try {
        final uri = Uri.parse('http://127.0.0.1:${server.port}/manifest.json');
        final report = await CatalogDiagnostics.runDiagnostics(
          manifestUri: uri,
          keyring: keyring,
          installedVersion: 3,
        );

        // Camada 3: HTTPS mirror
        expect(report.remoteOnion, equals(DiagnosticStatus.passed));

        // Camada 4: Manifesto obtido
        expect(report.manifestFetch, equals(DiagnosticStatus.passed));
        expect(report.manifestFetchDetails, contains('Manifesto v5 obtido com sucesso'));

        // Camada 5: Assinatura Ed25519 válida
        expect(report.ed25519Signature, equals(DiagnosticStatus.passed));
        expect(report.ed25519SignatureDetails, contains('Assinatura Ed25519 válida'));

        // Camada 6: Anti-rollback aprovado (v5 >= v3)
        expect(report.antiRollback, equals(DiagnosticStatus.passed));
        expect(report.antiRollbackDetails, contains('Anti-Rollback verificado'));
      } finally {
        await server.close(force: true);
      }
    });

    test('Camada 6 rejeita tentativa de rollback quando versão remota é inferior', () async {
      final manifest = await SignedCatalogManifest.signArtifact(
        signerKeyPair: keyPair,
        version: 2,
        artifactName: 'catalog_v2.db',
        artifactBytes: utf8.encode('NIX-TEST-CATALOG-DATA'),
        entryCount: 10,
      );

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(manifest.toJson()));
        req.response.close();
      });

      try {
        final uri = Uri.parse('http://127.0.0.1:${server.port}/manifest.json');
        final report = await CatalogDiagnostics.runDiagnostics(
          manifestUri: uri,
          keyring: keyring,
          installedVersion: 4, // Instalada v4 > Remota v2 (Tentativa de Rollback!)
        );

        expect(report.manifestFetch, equals(DiagnosticStatus.passed));
        expect(report.ed25519Signature, equals(DiagnosticStatus.passed));

        // Camada 6 deve acusar violação Anti-Rollback
        expect(report.antiRollback, equals(DiagnosticStatus.failed));
        expect(report.antiRollbackDetails, contains('Tentativa de rollback detectada'));
      } finally {
        await server.close(force: true);
      }
    });

    test('Camada 4 obtém manifesto com sucesso mesmo com fail-closed HTTP overrides global ativo', () async {
      NixFailClosedHttpOverrides.install();

      final manifest = await SignedCatalogManifest.signArtifact(
        signerKeyPair: keyPair,
        version: 1,
        artifactName: 'catalog_v1.db',
        artifactBytes: utf8.encode('NIX-CLEAN-MANIFEST-DATA'),
        entryCount: 50,
      );

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(manifest.toJson()));
        req.response.close();
      });

      try {
        final uri = Uri.parse('http://127.0.0.1:${server.port}/manifest.json');
        final report = await CatalogDiagnostics.runDiagnostics(
          manifestUri: uri,
          keyring: keyring,
          installedVersion: 1,
        );

        expect(report.manifestFetch, equals(DiagnosticStatus.passed));
        expect(report.ed25519Signature, equals(DiagnosticStatus.passed));
        expect(report.antiRollback, equals(DiagnosticStatus.passed));
      } finally {
        await server.close(force: true);
      }
    });
  });
}
