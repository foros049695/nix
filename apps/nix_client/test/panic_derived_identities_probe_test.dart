import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/monero_order.dart';
import 'package:nix_client/core/p2p/monero_ad_verifier.dart';
import 'package:nix_client/core/security/key_vault.dart';
import 'package:nix_client/core/security/os_key_storage.dart';
import 'package:nix_client/state/nix_state.dart';

Future<MoneroP2pOrder> signLocalOrder(NixState state) =>
    state.createAndSignMoneroOrder(
      side: MoneroP2pSide.sell,
      fiatCurrency: 'BRL',
      pricePerXmr: 950,
      minFiatLimit: 100,
      maxFiatLimit: 500,
      paymentMethod: 'PIX',
      notes: 'Anúncio sintético local para teste de ciclo de conta.',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory accountDir;
  late NixState state;

  setUp(() {
    accountDir = Directory.systemTemp.createTempSync('nix_panic_identities_');
    state = NixState(
      loadMockData: false,
      keyVault: KeyVault(osKeyStorage: InMemoryOsKeyStorage()),
    );
  });

  tearDown(() async {
    await state.localDatabase?.close();
    state.dispose();
    state.keyVault.lock();
    if (await accountDir.exists()) {
      await accountDir.delete(recursive: true);
    }
  });

  Future<void> createAccount() async {
    expect(
      await state.initializeEncryptedDatabase(
        passphrase: 'senha-sintetica-panic-probe',
        customDbPath: '${accountDir.path}/nix_local_v4.db',
        customVaultPath: '${accountDir.path}/vault_bootstrap.json',
      ),
      isTrue,
    );
  }

  Future<void> wipeAccount() async {
    final report = await state.panicWipeAllData(customBaseDir: accountDir.path);
    expect(report.errors, isEmpty);
    expect(state.keyVault.isUnlocked, isFalse);
  }

  test('panic wipe renova o signatário de anúncios na nova conta', () async {
    await createAccount();
    final oldOrder = await signLocalOrder(state);
    expect(await SignedMoneroAd.verifyOrderCryptographically(oldOrder), isTrue);

    await wipeAccount();
    expect(
        File('${accountDir.path}/vault_bootstrap.json').existsSync(), isFalse);
    await createAccount();
    final newOrder = await signLocalOrder(state);

    expect(await SignedMoneroAd.verifyOrderCryptographically(newOrder), isTrue);
    expect(newOrder.signedManifestHash, isNot(oldOrder.signedManifestHash));
    expect(newOrder.traderPublicId, isNot(oldOrder.traderPublicId));
  });

  test('panic wipe renova o signatário de arquivo sem banco', () async {
    final oldArticle = await state.publishCanonicalArticle(
      channelId: 'general_saved',
      title: 'Antes',
      rawContent: '<p>Conteúdo sintético anterior.</p>',
    );
    expect(await state.verifyCanonicalArticleIntegrity(oldArticle.cidHash),
        isTrue);

    await wipeAccount();
    final newArticle = await state.publishCanonicalArticle(
      channelId: 'general_saved',
      title: 'Depois',
      rawContent: '<p>Conteúdo sintético posterior.</p>',
    );

    expect(await state.verifyCanonicalArticleIntegrity(newArticle.cidHash),
        isTrue);
    expect(newArticle.authorFingerprint, isNot(oldArticle.authorFingerprint));
  });

  test('panic wipe remove objetos e histórico de arquivo em memória', () async {
    final article = await state.publishCanonicalArticle(
      channelId: 'general_saved',
      title: 'Arquivo temporário',
      rawContent: '<p>Conteúdo que pertence à conta apagada.</p>',
    );
    expect(
        await state.getCanonicalArticleHistory(article.cidHash), hasLength(1));
    expect(
        await state.verifyCanonicalArticleIntegrity(article.cidHash), isTrue);

    await wipeAccount();

    expect(await state.getCanonicalArticleHistory(article.cidHash), isEmpty);
    expect(
        await state.verifyCanonicalArticleIntegrity(article.cidHash), isFalse);
  });

  test('panic wipe reinicia o cache de nonces consumidos da conta', () async {
    final order = await signLocalOrder(state);
    expect(state.verifyMoneroOrder(order), isTrue);
    // Fixture pré-verificada: exercita somente o cache de replay do NixState,
    // sem substituir os testes criptográficos de SignedMoneroAd.
    final conflictingOrder = order.copyWith(id: 'synthetic-other-order');
    SignedMoneroAd.registerPreVerifiedOrder(conflictingOrder);
    expect(state.verifyMoneroOrder(conflictingOrder), isFalse);

    await wipeAccount();

    expect(state.verifyMoneroOrder(conflictingOrder), isTrue);
    expect(state.verifyMoneroOrder(order), isFalse);
  });
}
