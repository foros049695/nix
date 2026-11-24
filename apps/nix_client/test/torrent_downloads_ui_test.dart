import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/downloads/aria2_download_controller.dart';
import 'package:nix_client/core/torrent_index/adapters/indexer_sources_manager.dart';
import 'package:nix_client/core/torrent_index/database/torrent_index_database.dart';
import 'package:nix_client/features/downloads/torrent_downloads_stage.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

void main() {
  group('TorrentDownloadsStage UI Tests', () {
    late NixState nixState;
    late TorrentIndexDatabase inMemoryDb;
    late IndexerSourcesManager sourcesManager;
    late Aria2DownloadController downloadController;
    late Directory tempDir;

    setUp(() async {
      nixState = NixState();
      inMemoryDb = await TorrentIndexDatabase.open(inMemory: true);
      sourcesManager = IndexerSourcesManager();
      tempDir = await Directory.systemTemp.createTemp('nix_ui_test_');
      downloadController = Aria2DownloadController(downloadDir: tempDir.path);
    });

    tearDown(() async {
      nixState.dispose();
      await inMemoryDb.close();
      await downloadController.stopDaemon();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Widget createTestWidget() {
      return ChangeNotifierProvider<NixState>.value(
        value: nixState,
        child: MaterialApp(
          home: Scaffold(
            body: TorrentDownloadsStage(
              database: inMemoryDb,
              sourcesManager: sourcesManager,
              downloadController: downloadController,
            ),
          ),
        ),
      );
    }

    testWidgets('Renderiza cabeçalho terminal, abas e campo de pesquisa retrô', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Cabeçalho terminal
      expect(find.text('TORLINK // NIX INDEX'), findsOneWidget);
      expect(find.byKey(const ValueKey('transport_profile_badge')), findsOneWidget);

      // Abas de navegação
      expect(find.text('Buscador de Torrents'), findsOneWidget);
      expect(find.text('Nix Downloads (aria2)'), findsOneWidget);
      expect(find.text('Fontes & Conectores'), findsOneWidget);

      // Chips de modo
      expect(find.text('Modo Local'), findsOneWidget);
      expect(find.text('Índice Online'), findsOneWidget);
      expect(find.text('Ao Vivo'), findsOneWidget);

      // Prompt terminal
      expect(find.text('>'), findsOneWidget);
      expect(find.text('Pesquisar'), findsOneWidget);
    });

    testWidgets('Abre e fecha o painel de filtros de categoria', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final filterBtn = find.text('Filtros');
      expect(filterBtn, findsOneWidget);

      await tester.tap(filterBtn);
      await tester.pumpAndSettle();

      // Painel aberto com categorias
      expect(find.text('Filtrar por Categoria'), findsOneWidget);
      expect(find.text('Filmes'), findsOneWidget);
      expect(find.text('Animes'), findsOneWidget);
      expect(find.text('Livros'), findsOneWidget);

      // Fecha painel
      await tester.tap(find.byIcon(Icons.filter_alt_off_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Filtrar por Categoria'), findsNothing);
    });

    testWidgets('Alterna para a aba Nix Downloads e exibe botão de adicionar', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final dlTab = find.text('Nix Downloads (aria2)');
      await tester.tap(dlTab);
      await tester.pumpAndSettle();

      expect(find.text('Fila de Downloads Diretos (HTTP/HTTPS com aria2)'), findsOneWidget);
      expect(find.text('Adicionar URL'), findsOneWidget);

      // Abre diálogo de adicionar
      await tester.tap(find.text('Adicionar URL'));
      await tester.pumpAndSettle();

      expect(find.text('Adicionar Download Direto'), findsOneWidget);
      expect(find.text('URL de Download (HTTP/HTTPS)'), findsOneWidget);

      // Digita um magnet link e verifica mensagem de bloqueio
      final urlField = find.byType(TextField).first;
      await tester.enterText(urlField, 'magnet:?xt=urn:btih:123456');
      await tester.pumpAndSettle();

      expect(find.textContaining('O Nix Downloads utiliza aria2 exclusivamente para downloads diretos HTTP/HTTPS'), findsOneWidget);

      // Fecha diálogo
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Adicionar Download Direto'), findsNothing);
    });

    testWidgets('Alterna para a aba Fontes & Conectores e exibe catálogo', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      final sourcesTab = find.text('Fontes & Conectores');
      await tester.tap(sourcesTab);
      await tester.pumpAndSettle();

      expect(find.text('Catálogo Offline & Pacotes Assinados'), findsOneWidget);
      expect(find.textContaining('Registros Indexados Localmente:'), findsOneWidget);
      expect(find.text('Conectores e Indexadores Registrados'), findsOneWidget);
      expect(find.textContaining('Nyaa.si'), findsOneWidget);
      expect(find.textContaining('YTS.mx'), findsOneWidget);
    });
  });
}
