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
  late Directory externalDir;
  late NixState state;

  setUp(() {
    accountDir = Directory.systemTemp.createTempSync('nix_panic_identities_');
    externalDir = Directory.systemTemp.createTempSync('nix_external_keep_');
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
    if (await externalDir.exists()) {
      await externalDir.delete(recursive: true);
    }
  });

  Future<void> createAccount({String passphrase = 'senha-sintetica-panic-probe'}) async {
    expect(
      await state.initializeEncryptedDatabase(
        passphrase: passphrase,
        customDbPath: '${accountDir.path}/nix_local_v4.db',
        customVaultPath: '${accountDir.path}/vault_bootstrap.json',
        overwriteExistingVault: true,
      ),
      isTrue,
    );
  }

  Future<void> wipeAccount() async {
    final report = await state.panicWipeAllData(customBaseDir: accountDir.path);
    expect(report.errors, isEmpty);
    expect(state.keyVault.isUnlocked, isFalse);
  }

  test('1 a 6. Ciclo de vida completo: criação, Monero isolado, Archive, wipe e inacessibilidade', () async {
    // 1. Criação de conta e banco cifrado
    await createAccount();
    expect(state.localDatabase, isNotNull);

    // 2. Assinatura de anúncio Monero gerando _moneroMarketIdentity isolada
    final oldOrder = await signLocalOrder(state);
    expect(await SignedMoneroAd.verifyOrderCryptographically(oldOrder), isTrue);

    // 3. Criação de publicação no Archive gerando publicação canônica
    final article = await state.publishCanonicalArticle(
      channelId: 'general_saved',
      title: 'Artigo Pré-Wipe',
      rawContent: '<p>Conteúdo confidencial a ser destruído.</p>',
    );
    expect(await state.verifyCanonicalArticleIntegrity(article.cidHash), isTrue);

    // 4. População de caches e nonces
    expect(state.verifyMoneroOrder(oldOrder), isTrue);

    // 5. Limpeza de conta confina destruição ao customBaseDir
    await wipeAccount();

    // 6. Ausência de identidades antigas acessíveis pelo estado
    expect(File('${accountDir.path}/vault_bootstrap.json').existsSync(), isFalse);
    expect(File('${accountDir.path}/nix_local_v4.db').existsSync(), isFalse);
    expect(state.localDatabase, isNull);
    expect(state.primaryIdentity, isNull);
    expect(await state.getCanonicalArticleHistory(article.cidHash), isEmpty);
    expect(await state.verifyCanonicalArticleIntegrity(article.cidHash), isFalse);
  });

  test('7 e 8. Reprovisionamento de nova conta e ausência de reutilização de caches/chaves antigas', () async {
    await createAccount();
    final firstOrder = await signLocalOrder(state);
    final firstTraderId = firstOrder.traderPublicId;

    await wipeAccount();

    // 7. Reprovisiona uma nova conta
    await createAccount(passphrase: 'nova-frase-passe-reprovisionada');
    final secondOrder = await signLocalOrder(state);

    // 8. O novo signatário possui chave e Public ID estritamente novos
    expect(await SignedMoneroAd.verifyOrderCryptographically(secondOrder), isTrue);
    expect(secondOrder.traderPublicId, isNot(equals(firstTraderId)));
    expect(secondOrder.signedManifestHash, isNot(equals(firstOrder.signedManifestHash)));

    // Nonces antigos não colidem na nova conta
    expect(state.verifyMoneroOrder(secondOrder), isTrue);
  });

  test('9. Preservação de arquivos em diretórios externos vizinhos', () async {
    final externalSentinel = File('${externalDir.path}/backup_legitimo.txt');
    await externalSentinel.writeAsString('dados_importantes_do_usuario_que_nao_devem_sumir');

    await createAccount();
    await wipeAccount();

    // O sentinela externo deve permanecer intacto
    expect(await externalSentinel.exists(), isTrue);
    expect(await externalSentinel.readAsString(), 'dados_importantes_do_usuario_que_nao_devem_sumir');
  });

  test('10. Comportamento determinístico e fail-closed em falhas parciais', () async {
    await createAccount();

    // Cria um arquivo não relacionado ou inexistente e executa wipe
    final nonExistentBaseDir = '${accountDir.path}/subdiretorio_inexistente';
    final report = await state.panicWipeAllData(customBaseDir: nonExistentBaseDir);
    expect(report.memoryWiped, isTrue);

    // O estado em memória é zerado incondicionalmente mesmo se o diretório do disco falhar
    expect(state.keyVault.isUnlocked, isFalse);
    expect(state.localDatabase, isNull);
    expect(state.primaryIdentity, isNull);
  });
}
