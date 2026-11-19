import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/archive/nix_archive_service.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/media/media_catalog_service.dart';
import 'package:nix_client/core/messaging/sovereign_messenger.dart';
import 'package:nix_client/core/models/github_repo.dart';
import 'package:nix_client/core/models/monero_order.dart';
import 'package:nix_client/core/p2p/monero_ad_verifier.dart';
import 'package:nix_client/core/security/file_picker_adapter.dart';
import 'package:nix_client/core/security/key_vault.dart';
import 'package:nix_client/core/security/local_image_helper.dart';
import 'package:nix_client/core/security/os_key_storage.dart';
import 'package:nix_client/features/discovery/github_discovery_view.dart';
import 'package:nix_client/features/offline/share_app_offline_dialog.dart';
import 'package:nix_client/features/onboarding/sovereign_onboarding_flow.dart';
import 'package:nix_client/features/onboarding/sovereign_onboarding_model.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:nix_transport/nix_transport.dart';
import 'package:provider/provider.dart';

class _RealLoopbackHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fase 5: SQLCipher, KeyVault, Backup Cifrado e Indicadores Honestos', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_phase5_vault_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Rejeita frase-passe vazia, bloqueia banco não cifrado com requireEncryption=true e valida ausência de texto claro', () async {
      final dbPath = '${tempDir.path}/plain_rejected.db';
      // 1. Sem chave raw -> SQLite não cifrado -> requireEncryption=true DEVE falhar fechado
      await expectLater(
        () => LocalDatabase.open(
          path: dbPath,
          rawCipherKey: null,
          requireEncryption: true,
        ),
        throwsA(isA<StateError>()),
      );
      expect(File(dbPath).existsSync(), isFalse);

      // 2. NixState rejeita frase-passe vazia (sem frase-passe padrão fixa)
      final state = NixState(
        loadMockData: false,
        keyVault: KeyVault(osKeyStorage: InMemoryOsKeyStorage()),
      );
      addTearDown(state.dispose);
      final emptyOk = await state.initializeEncryptedDatabase(
        passphrase: '   ',
        customDbPath: '${tempDir.path}/empty.db',
        customVaultPath: '${tempDir.path}/empty_vault.json',
      );
      expect(emptyOk, isFalse);
      expect(state.isDatabaseReady, isFalse);

      // 3. Abertura com KeyVault real + SQLCipher (se biblioteca SQLCipher presente, confirma ausência de plaintext)
      final secureDbPath = '${tempDir.path}/sovereign.db';
      final secureVaultPath = '${tempDir.path}/sovereign_vault.json';
      final ok = await state.initializeEncryptedDatabase(
        passphrase: 'Strong-Audit-Passphrase-2026!',
        customDbPath: secureDbPath,
        customVaultPath: secureVaultPath,
      );
      expect(ok, isTrue);
      expect(
        state.securityContext.isSqlCipherUnlocked,
        equals(state.localDatabase!.cipherInfo.isEncrypted),
      );

      final identity = await NixIdentity.generate();
      await state.persistPrimaryIdentity(
        identity: identity,
        displayName: 'Operador Auditoria',
      );
      await state.messageRepo!.insertMessage(
        id: 'secret_msg_001',
        conversationId: 'dm_saved_messages',
        authorKey: identity.publicId,
        deviceId: state.localDeviceId,
        body: 'SEGREDO_ULTRA_CONFIDENCIAL_FASE_5_NUNCA_EM_CLARO',
        deliveryState: 'received',
      );
      await state.localDatabase!.close();

      if (state.localDatabase!.cipherInfo.isEncrypted) {
        final rawFileBytes = await File(secureDbPath).readAsBytes();
        final headerAscii = ascii.decode(
          rawFileBytes.take(16).toList(),
          allowInvalid: true,
        );
        expect(headerAscii.startsWith('SQLite format 3'), isFalse);
        final rawLatin = latin1.decode(rawFileBytes);
        expect(
          rawLatin.contains('SEGREDO_ULTRA_CONFIDENCIAL_FASE_5_NUNCA_EM_CLARO'),
          isFalse,
        );
      }
    });

    test('KeyVault exporta e restaura backup cifrado validando frase-passe', () async {
      final vaultPath = '${tempDir.path}/orig_vault.json';
      final restoredPath = '${tempDir.path}/restored_vault.json';
      final vault = KeyVault(osKeyStorage: InMemoryOsKeyStorage());
      final originalKey = await vault.initialize(
        passphrase: 'Backup-Master-Pass-99!',
        customPath: vaultPath,
        bindToOsKeyring: true,
      );
      expect(vault.lastKeyringBindSucceeded, isTrue);

      final backupBundle = await vault.exportEncryptedBackupBundle(
        customPath: vaultPath,
      );
      expect(jsonEncode(backupBundle).contains('Backup-Master-Pass-99!'), isFalse);

      final restoreVault = KeyVault(osKeyStorage: InMemoryOsKeyStorage());
      // Frase-passe incorreta deve ser rejeitada
      await expectLater(
        () => restoreVault.importEncryptedBackupBundle(
          backupBundle,
          passphrase: 'Wrong-Passphrase',
          customPath: restoredPath,
        ),
        throwsA(anything),
      );
      expect(File(restoredPath).existsSync(), isFalse);

      // Frase-passe correta restaura exatamente a mesma masterKey de 32 bytes
      final restoredKey = await restoreVault.importEncryptedBackupBundle(
        backupBundle,
        passphrase: 'Backup-Master-Pass-99!',
        customPath: restoredPath,
      );
      expect(restoredKey, equals(originalKey));
      expect(File(restoredPath).existsSync(), isTrue);
    });
  });

  group('Fase 6: Onboarding Fail-Closed, Pré-requisitos, Snapshot Atômico e Tor', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_phase6_onboarding_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('completeOnboarding impede conclusão sem identidade Seed A em produção e verifyTorTransportAndFailClosed valida bloqueio clearnet + SOCKS5 real', () async {
      final state = NixState(
        loadMockData: false,
        keyVault: KeyVault(osKeyStorage: InMemoryOsKeyStorage()),
      );
      addTearDown(state.dispose);

      // Sem identidade: deve falhar fechado
      await expectLater(
        () => state.completeOnboarding(),
        throwsA(isA<StateError>()),
      );
      expect(state.isOnboarded, isFalse);

      // Porta fechada -> socksActive=false, circuitOperational=false, failClosedVerified=true
      final closedRes = await state.verifyTorTransportAndFailClosed(
        customSocksPort: 1,
        customControlPort: 2,
      );
      expect(closedRes.failClosedVerified, isTrue);
      expect(closedRes.socksActive, isFalse);
      expect(closedRes.circuitOperational, isFalse);

      // Servidor SOCKS5 real em loopback -> socksActive=true
      final socksServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => socksServer.close());
      socksServer.listen((client) {
        client.listen((data) {
          if (data.isNotEmpty && data[0] == 0x05) {
            client.add(const [0x05, 0x00]);
            client.flush();
          }
        });
      });

      final openRes = await state.verifyTorTransportAndFailClosed(
        customSocksPort: socksServer.port,
        customControlPort: 2,
      );
      expect(openRes.failClosedVerified, isTrue);
      expect(openRes.socksActive, isTrue);
    });

    test('OnboardingStateSnapshot persiste atomicamente sem deixar arquivos .tmp', () async {
      final snapPath = '${tempDir.path}/onboarding_state.json';
      const snap = OnboardingStateSnapshot(
        currentStep: OnboardingStep.publicId,
        torConsentAccepted: true,
        torBootstrapped: true,
        torVerified: true,
        identityGenerated: true,
        backupConfirmed: true,
        publicIdDerived: true,
        publicId: 'NIX-ABCD-1234-5678-EF90',
      );
      await OnboardingStateSnapshot.save(snap, customPath: snapPath);
      expect(File(snapPath).existsSync(), isTrue);
      expect(File('$snapPath.tmp').existsSync(), isFalse);

      final loaded = await OnboardingStateSnapshot.load(customPath: snapPath);
      expect(loaded.currentStep, equals(OnboardingStep.publicId));
      expect(loaded.publicId, equals('NIX-ABCD-1234-5678-EF90'));
      expect(loaded.torVerified, isTrue);
    });

    testWidgets('SovereignOnboardingFlow renderiza em janelas pequenas (800x600) e grandes (1440x900) sem overflow', (tester) async {
      final state = NixState(
        loadMockData: false,
        keyVault: KeyVault(osKeyStorage: InMemoryOsKeyStorage()),
      );
      addTearDown(state.dispose);

      for (final size in const [Size(800, 600), Size(1440, 900)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ChangeNotifierProvider<NixState>.value(
            value: state,
            child: MaterialApp(
              home: SovereignOnboardingFlow(
                nixState: state,
                onComplete: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SovereignOnboardingFlow), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('Fase 7: Mercado Monero P2P Realmente Assinado, Isolado e Não Custodial', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_phase7_monero_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Assina com Ed25519 isolado da Seed A, valida limites/expiração/anti-replay/adulteração e persiste localmente', () async {
      final dbPath = '${tempDir.path}/monero.db';
      final vaultPath = '${tempDir.path}/monero_vault.json';
      final state = NixState(
        loadMockData: false,
        keyVault: KeyVault(osKeyStorage: InMemoryOsKeyStorage()),
      );
      expect(
        await state.initializeEncryptedDatabase(
          passphrase: 'Monero-Phase7-Audit-2026!',
          customDbPath: dbPath,
          customVaultPath: vaultPath,
        ),
        isTrue,
      );
      final messagingIdentity = await NixIdentity.generate();
      await state.persistPrimaryIdentity(
        identity: messagingIdentity,
        displayName: 'Trader Auditoria',
      );

      // Rótulo honesto não custodial (nunca exibe saldo fictício 4.825 XMR)
      expect(state.moneroWalletBalanceLabel.contains('4.825'), isFalse);
      expect(state.moneroWalletStatusLabel.contains('Sem Custódia'), isTrue);

      // Rejeita preço/limites inválidos
      await expectLater(
        () => state.createAndSignMoneroOrder(
          side: MoneroP2pSide.sell,
          fiatCurrency: 'BRL',
          pricePerXmr: -10,
          minFiatLimit: 100,
          maxFiatLimit: 500,
          paymentMethod: 'PIX',
          notes: 'Inválido',
        ),
        throwsArgumentError,
      );
      await expectLater(
        () => state.createAndSignMoneroOrder(
          side: MoneroP2pSide.sell,
          fiatCurrency: 'BRL',
          pricePerXmr: 950,
          minFiatLimit: 1000,
          maxFiatLimit: 500,
          paymentMethod: 'PIX',
          notes: 'Max < Min',
        ),
        throwsArgumentError,
      );

      // Cria anúncio realmente assinado com Ed25519 isolado da Seed A
      final order = await state.createAndSignMoneroOrder(
        side: MoneroP2pSide.sell,
        fiatCurrency: 'BRL',
        pricePerXmr: 960.50,
        minFiatLimit: 200,
        maxFiatLimit: 2500,
        paymentMethod: 'PIX',
        notes: 'Troca P2P não custodial via carteira externa.',
      );
      expect(order.publicationState, equals('local_signed'));
      expect(order.traderPublicId, isNot(equals(messagingIdentity.publicId)));
      expect(order.signedManifestHash.length, equals(64));
      expect(order.signatureHex!.length, equals(128));
      expect(await SignedMoneroAd.verifyOrderCryptographically(order), isTrue);
      expect(state.verifyMoneroOrder(order), isTrue);

      // Adulteração de preço DEVE falhar verificação criptográfica e síncrona
      final tampered = order.copyWith(pricePerXmr: 1.00);
      expect(await SignedMoneroAd.verifyOrderCryptographically(tampered), isFalse);
      expect(state.verifyMoneroOrder(tampered), isFalse);

      // Expiração DEVE falhar verificação
      final expired = order.copyWith(
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      expect(state.verifyMoneroOrder(expired), isFalse);

      // Replay do mesmo nonce sob outro ID de ordem DEVE falhar
      final replayed = order.copyWith(id: 'xmr_replay_attack_id');
      SignedMoneroAd.registerPreVerifiedOrder(replayed);
      expect(state.verifyMoneroOrder(replayed), isFalse);

      // Persistência após reinicialização
      state.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final restarted = NixState(
        loadMockData: false,
        keyVault: KeyVault(osKeyStorage: InMemoryOsKeyStorage()),
      );
      addTearDown(restarted.dispose);
      await restarted.unlockWithPassphrase(
        'Monero-Phase7-Audit-2026!',
        customDbPath: dbPath,
        customVaultPath: vaultPath,
      );
      expect(restarted.moneroOrders.any((o) => o.id == order.id), isTrue);
    });
  });

  group('Fase 8: FilePickerAdapter Portátil, Cancelamento de Anexos e Sender Keys em Grupos', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_phase8_files_');
    });

    tearDown(() async {
      LocalImageHelper.filePickerAdapter = const CrossPlatformFilePickerAdapter();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('ProgrammableFilePickerAdapter dispensa zenity/kdialog e cancelamento de anexo limpa chunks temporários', () async {
      final dummyFile = File('${tempDir.path}/sample.txt');
      await dummyFile.writeAsString('conteudo-anexo-portatil');
      LocalImageHelper.filePickerAdapter = ProgrammableFilePickerAdapter(
        nextAttachments: [dummyFile.path],
      );
      final picked = await LocalImageHelper.pickAttachmentsNativeDesktop();
      expect(picked, equals([dummyFile.path]));

      // Cancelamento cooperativo no preparo de anexo cifrado deve limpar chunks no disco e no banco
      final dbKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 7));
      final db = await LocalDatabase.open(
        path: '${tempDir.path}/att.db',
        rawCipherKey: dbKey,
      );
      addTearDown(() => db.close());
      final id = await NixIdentity.generate();
      final storageDir = '${tempDir.path}/persistent_encrypted_objects';
      final messenger = SovereignMessenger(
        database: db,
        identity: id,
        vaultMasterKey: dbKey,
        storageRootDir: storageDir,
      );

      var calls = 0;
      final largeBytes = Uint8List.fromList(List<int>.filled(200000, 0x42));
      await expectLater(
        () => messenger.prepareEncryptedAttachment(
          fileName: 'cancel_test.bin',
          mimeType: 'application/octet-stream',
          rawBytes: largeBytes,
          chunkSize: 32768,
          isCancelled: () {
            calls++;
            return calls >= 2;
          },
        ),
        throwsStateError,
      );
      final chunksDir = Directory('$storageDir/chunks');
      if (chunksDir.existsSync()) {
        expect(chunksDir.listSync(), isEmpty);
      }
      final objectRows = await db.rawDatabase.query('objects');
      expect(objectRows, isEmpty);

      // Limpeza explícita de arquivo de staging
      final stagingFile = File('${tempDir.path}/staging.tmp');
      await stagingFile.writeAsString('temp');
      final deleted = await messenger.cleanupTemporaryStagingFiles([stagingFile.path]);
      expect(deleted, equals(1));
      expect(stagingFile.existsSync(), isFalse);
    });

    test('applyAdminAction (kick/ban) rotaciona época de Sender Keys e bloqueia envio de silenciados/banidos', () async {
      final state = NixState(loadMockData: true);
      addTearDown(state.dispose);
      final ch = state.currentChannel;
      final initialEpoch = state.getChannelSenderKeyEpoch(ch.id);

      state.applyAdminAction(
        ch,
        targetFingerprint: 'NX-INTRUDER-99',
        action: 'kick',
      );
      expect(state.getChannelSenderKeyEpoch(ch.id), greaterThan(initialEpoch));

      final epochAfterKick = state.getChannelSenderKeyEpoch(ch.id);
      state.applyAdminAction(
        state.currentChannel,
        targetFingerprint: state.securityContext.myFingerprint,
        action: 'ban',
      );
      expect(state.getChannelSenderKeyEpoch(ch.id), greaterThan(epochAfterKick));
      // Membro banido não pode enviar mensagens no canal
      expect(state.sendMessage('Tentativa após banimento'), isFalse);
    });
  });

  group('Fase 9: Archive XSS/Fluxo Canônico, MediaCatalog Opt-In, Starwire Fail-Closed e APK Ed25519', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_phase9_features_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('9.1 NixArchiveService sanitiza payloads XSS adversariais e NixState executa criar/editar/refutar/verificar/histórico', () async {
      final adversarialInputs = [
        '<script>alert(1)</script><p>Texto Seguro</p>',
        '<svg/onload=alert(2)><strong>Ok</strong>',
        '<img src=x onerror="fetch(1)"><em>Limpo</em>',
        '<a href="java&#x09;script:alert(3)">Link Malicioso</a>',
        '<a href="javascript&#58;alert(4)">Link 2</a>',
        '<a href="https://nix.example/doc">Link Válido</a>',
        '<iframe src="https://evil.test"></iframe>',
        '<!-- comentario <script> -->Texto<script>unclosed',
      ];
      for (final payload in adversarialInputs) {
        final clean = NixArchiveService.sanitizeRichTextHtml(payload);
        expect(clean.toLowerCase(), isNot(contains('<script')));
        expect(clean.toLowerCase(), isNot(contains('<svg')));
        expect(clean.toLowerCase(), isNot(contains('<iframe')));
        expect(clean.toLowerCase(), isNot(contains('onerror')));
        expect(clean.toLowerCase(), isNot(contains('onload')));
        expect(clean.toLowerCase(), isNot(contains('javascript:')));
      }
      expect(
        NixArchiveService.sanitizeRichTextHtml(
          '<a href="https://nix.example/doc">Link Válido</a>',
        ),
        equals('<a href="https://nix.example/doc">Link Válido</a>'),
      );

      // Fluxo completo com SQLCipher: criar -> editar (supersedes) -> refutar -> verificar -> histórico
      final state = NixState(
        loadMockData: false,
        keyVault: KeyVault(osKeyStorage: InMemoryOsKeyStorage()),
      );
      addTearDown(state.dispose);
      await state.initializeEncryptedDatabase(
        passphrase: 'Archive-Phase9-Audit-2026!',
        customDbPath: '${tempDir.path}/archive.db',
        customVaultPath: '${tempDir.path}/archive_vault.json',
      );
      final id = await NixIdentity.generate();
      await state.persistPrimaryIdentity(identity: id, displayName: 'Autora Archive');

      final pubV1 = await state.publishCanonicalArticle(
        channelId: 'ch_pub',
        title: 'Relatório Técnico v1',
        rawContent: '<p>Conteúdo inicial</p><script>alert(1)</script>',
        claimTexts: ['Afirmação A'],
      );
      expect(pubV1.contentMarkdown, equals('<p>Conteúdo inicial</p>'));
      expect(await state.verifyCanonicalArticleIntegrity(pubV1.cidHash), isTrue);

      final pubV2 = await state.publishCanonicalArticle(
        channelId: 'ch_pub',
        title: 'Relatório Técnico v2',
        rawContent: '<p>Revisão corrigida</p>',
        claimTexts: ['Afirmação A revisada'],
        supersedesHash: pubV1.cidHash,
      );
      expect(pubV2.supersedesHash, equals(pubV1.cidHash));
      expect(await state.verifyCanonicalArticleIntegrity(pubV2.cidHash), isTrue);

      final refHash = await state.refuteCanonicalArticle(
        channelId: 'ch_pub',
        targetCidHash: pubV2.cidHash,
        targetClaimId: 'c1',
        rationale: 'Contra-evidência reproduzível <img src=x onerror=alert(1)>',
      );
      expect(await state.verifyCanonicalArticleIntegrity(refHash), isTrue);

      final history = await state.getCanonicalArticleHistory(pubV2.cidHash);
      expect(history.length, equals(2));
      expect(history[0]['hash'], equals(pubV2.cidHash));
      expect(history[1]['hash'], equals(pubV1.cidHash));
    });

    test('9.2 MediaCatalogService separa busca local FTS5, conectores externos opt-in fail-closed e gate magnet', () async {
      final db = await LocalDatabase.open(
        path: '${tempDir.path}/media.db',
        rawCipherKey: Uint8List.fromList(List<int>.generate(32, (i) => i + 3)),
      );
      addTearDown(() => db.close());
      final state = NixState(
        loadMockData: false,
        keyVault: KeyVault(osKeyStorage: InMemoryOsKeyStorage()),
      );
      addTearDown(state.dispose);
      await state.initializeEncryptedDatabase(
        passphrase: 'Media-Phase9-Audit-2026!',
        customDbPath: '${tempDir.path}/media_state.db',
        customVaultPath: '${tempDir.path}/media_vault.json',
      );
      final svc = state.mediaCatalogService!;
      await svc.saveOfflineCatalogEntry(
        id: 'film_01',
        kind: 'film',
        title: 'Ghost in the Shell 1995',
      );
      final localHits = await state.searchCulturalCatalog('Ghost');
      expect(localHits.length, equals(1));

      // Conector externo desabilitado por padrão -> StateError
      await expectLater(
        () => svc.queryRemoteOptInConnector(
          connector: OptInMediaConnectorKind.tmdb,
          query: 'Akira',
          isFailClosedTorActive: true,
          hasActiveTorSocksCircuit: true,
        ),
        throwsStateError,
      );

      // Habilitado, porém Tor fail-closed sem circuito SOCKS5 -> bloqueado
      svc.setConnectorEnabled(OptInMediaConnectorKind.tmdb, true);
      await expectLater(
        () => svc.queryRemoteOptInConnector(
          connector: OptInMediaConnectorKind.tmdb,
          query: 'Akira',
          isFailClosedTorActive: true,
          hasActiveTorSocksCircuit: false,
        ),
        throwsA(isA<TorrentClearnetLeakBlockedException>()),
      );

      // Habilitado com circuito Tor SOCKS5 ativo -> executa e persiste localmente
      final remoteHits = await svc.queryRemoteOptInConnector(
        connector: OptInMediaConnectorKind.tmdb,
        query: 'Akira',
        isFailClosedTorActive: true,
        hasActiveTorSocksCircuit: true,
        transportExecutor: (q) async => [
          {'id': 'tmdb_149', 'kind': 'anime', 'title': 'Akira (1988)'},
        ],
      );
      expect(remoteHits.length, equals(1));
      expect((await svc.searchOfflineCatalog('Akira')).length, equals(1));
    });

    test('9.3 GitHub Discovery proíbe bypass clearnet sob Tor estrito, valida nomes ZIP e persiste favoritos', () async {
      expect(
        () => enforceStarwireDownloadTransport(
          strictTorMode: true,
          allowClearnetBypass: true,
        ),
        throwsA(isA<TransportBlockedException>()),
      );
      final strictPolicy = enforceStarwireDownloadTransport(
        strictTorMode: true,
        allowClearnetBypass: false,
      );
      expect(
        () => strictPolicy.assertAllowedUri(Uri.parse('https://github.com/org/repo/archive/HEAD.zip')),
        throwsA(isA<TransportBlockedException>()),
      );
      expect(
        () => buildStarwireZipFilename('..', 'repo'),
        throwsFormatException,
      );

      // Persistência de favoritos em SQLCipher após reinicialização
      final dbPath = '${tempDir.path}/starwire.db';
      final vaultPath = '${tempDir.path}/starwire_vault.json';
      final state = NixState(
        loadMockData: false,
        keyVault: KeyVault(osKeyStorage: InMemoryOsKeyStorage()),
      );
      await state.initializeEncryptedDatabase(
        passphrase: 'Starwire-Phase9-2026!',
        customDbPath: dbPath,
        customVaultPath: vaultPath,
      );
      final id = await NixIdentity.generate();
      await state.persistPrimaryIdentity(identity: id, displayName: 'Dev Nix');
      state.githubRepos.add(
        GithubRepository(
          id: 'gh_test_1',
          owner: 'nix-org',
          name: 'nix-core',
          description: 'Core repo',
          language: 'Dart',
          starsCount: 100,
          forksCount: 10,
          topics: const ['privacy'],
          license: 'MIT',
          htmlUrl: 'https://github.com/nix-org/nix-core',
          updatedDate: DateTime.now().toUtc(),
        ),
      );
      state.toggleSaveRepoInAcervo('gh_test_1');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      state.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final reloaded = NixState(
        loadMockData: false,
        keyVault: KeyVault(osKeyStorage: InMemoryOsKeyStorage()),
      );
      addTearDown(reloaded.dispose);
      await reloaded.unlockWithPassphrase(
        'Starwire-Phase9-2026!',
        customDbPath: dbPath,
        customVaultPath: vaultPath,
      );
      expect(
        reloaded.userProfile.culturalItems.any((i) => i.id == 'repo_nix-core'),
        isTrue,
      );
    });

    test('9.4 ShareAppOfflineDialog valida assinatura Ed25519 além do SHA-256 e transfere via HTTP local', () async {
      final publisher = await NixIdentity.generate();
      final untrusted = await NixIdentity.generate();
      final apkBytes = Uint8List.fromList(utf8.encode('PK_SIGNED_NIX_RELEASE_BINARY_V040'));

      final manifest = await SignedReleaseManifest.signArtifact(
        signer: publisher,
        version: '0.4.0',
        artifactName: 'nix-client-v0.4.0.apk',
        artifactBytes: apkBytes,
      );

      // 1. Pacote íntegro + chave do publicador -> VÁLIDO
      expect(
        await ShareAppOfflineDialog.verifyOfflineApkAuthenticity(
          apkBytes: apkBytes,
          manifest: manifest,
          trustedReleaseKey: publisher.ed25519PublicKey,
        ),
        isTrue,
      );

      // 2. Pacote adulterado -> REJEITADO
      final tamperedBytes = Uint8List.fromList([...apkBytes, 0x00]);
      expect(
        await ShareAppOfflineDialog.verifyOfflineApkAuthenticity(
          apkBytes: tamperedBytes,
          manifest: manifest,
          trustedReleaseKey: publisher.ed25519PublicKey,
        ),
        isFalse,
      );

      // 3. Chave pública de publicador não confiável -> REJEITADO
      expect(
        await ShareAppOfflineDialog.verifyOfflineApkAuthenticity(
          apkBytes: apkBytes,
          manifest: manifest,
          trustedReleaseKey: untrusted.ed25519PublicKey,
        ),
        isFalse,
      );

      // 4. Transferência HTTP real entre servidor local e cliente par verificador
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        try {
          server.listen((req) async {
            if (req.uri.path == '/nix.apk') {
              req.response.add(apkBytes);
            } else if (req.uri.path == '/nix.apk.sig.json') {
              req.response.write(jsonEncode(manifest.toJson()));
            } else {
              req.response.statusCode = HttpStatus.notFound;
            }
            await req.response.close();
          });

          final transfer = await ShareAppOfflineDialog.downloadAndVerifyFromPeer(
            apkUrl: Uri.parse('http://127.0.0.1:${server.port}/nix.apk'),
            trustedReleaseKey: publisher.ed25519PublicKey,
          );
          expect(transfer.verified, isTrue);
          expect(transfer.apkBytes, equals(apkBytes));
          expect(
            transfer.manifest.signerEd25519Hex,
            equals(publisher.ed25519PublicHex),
          );
        } finally {
          await server.close(force: true);
        }
      }, _RealLoopbackHttpOverrides());
    });
  });
}
