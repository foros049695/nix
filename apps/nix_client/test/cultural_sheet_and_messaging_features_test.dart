import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:nix_client/core/models/cultural_item.dart';
import 'package:nix_client/core/models/cultural_tracking.dart';
import 'package:nix_client/core/models/monero_order.dart';
import 'package:nix_client/core/models/user_settings.dart';
import 'package:nix_client/core/security/secure_file_download_helper.dart';
import 'package:nix_client/features/chat/article_share_card.dart';
import 'package:nix_client/features/chat/offline_location_card.dart';
import 'package:nix_client/features/chat/offline_location_picker_dialog.dart';
import 'package:nix_client/features/chat/work_share_card.dart';
import 'package:nix_client/features/media/cultural_work_sheet.dart';
import 'package:nix_client/features/profile/nix_user_avatar.dart';
import 'package:nix_client/state/nix_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Offline Location Payload & Card Test', () {
    test('OfflineLocationData serializes and deserializes properly', () {
      const data = OfflineLocationData(
        title: 'Ponto Tático Alpha',
        lat: -23.55052,
        lng: -46.633308,
      );

      final text = data.toMessageText();
      expect(text.startsWith('[NIX_LOC]:'), isTrue);

      final parsed = OfflineLocationData.tryParse(text);
      expect(parsed, isNotNull);
      expect(parsed!.title, 'Ponto Tático Alpha');
      expect(parsed.lat, closeTo(-23.55052, 0.0001));
      expect(parsed.lng, closeTo(-46.633308, 0.0001));
    });

    testWidgets('OfflineLocationCard renders coordinates and action button', (tester) async {
      const data = OfflineLocationData(
        title: 'Posto Seguro Onion',
        lat: -15.793889,
        lng: -47.882778,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: OfflineLocationCard(data: data)),
          ),
        ),
      );

      expect(find.text('Posto Seguro Onion'), findsOneWidget);
      expect(find.textContaining('-15.7939'), findsOneWidget);
      expect(find.text('Ver no Mapa Tático'), findsOneWidget);
    });
  });

  group('2. Work & Article Share Cards Test', () {
    test('WorkShareData serializes and parses properly', () {
      const workData = WorkShareData(
        id: 'work_edgerunners',
        title: 'Cyberpunk: Edgerunners',
        originalTitle: 'Cyberpunk: Edgerunners',
        creator: 'Studio Trigger',
        year: 2022,
        kind: 'Anime',
        rating: 9.4,
        synopsis: 'A street kid trying to survive in a technology and body modification-obsessed city of the future.',
      );

      final text = workData.toMessageText();
      expect(text.startsWith('[NIX_WORK]:'), isTrue);

      final parsed = WorkShareData.tryParse(text);
      expect(parsed, isNotNull);
      expect(parsed!.title, 'Cyberpunk: Edgerunners');
      expect(parsed.creator, 'Studio Trigger');
      expect(parsed.rating, 9.4);
      expect(parsed.year, 2022);
    });

    test('ArticleShareData serializes and parses properly', () {
      const article = ArticleShareData(
        id: 'art_privacy_01',
        title: 'Soberania Digital e Roteamento Tor',
        authorName: 'Cypherpunk Nix',
        authorFingerprint: 'A1B2C3D4E5F6',
        publishedAt: '2026-11-23',
        excerpt: 'Análise detalhada do transporte fail-closed sobre circuitos cebola v3.',
      );

      final text = article.toMessageText();
      expect(text.startsWith('[NIX_ARTICLE]:'), isTrue);

      final parsed = ArticleShareData.tryParse(text);
      expect(parsed, isNotNull);
      expect(parsed!.title, 'Soberania Digital e Roteamento Tor');
      expect(parsed.authorName, 'Cypherpunk Nix');
      expect(parsed.authorFingerprint, 'A1B2C3D4E5F6');
    });

    testWidgets('WorkShareCard displays title, rating and dex action', (tester) async {
      final state = NixState(loadMockData: false);
      addTearDown(state.dispose);

      const workData = WorkShareData(
        id: 'work_anne',
        title: 'Anne of Green Gables',
        creator: 'Lucy Maud Montgomery',
        year: 1908,
        kind: 'Livro',
        rating: 8.1,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(
            home: Scaffold(
              body: Center(child: WorkShareCard(data: workData)),
            ),
          ),
        ),
      );

      expect(find.text('Anne of Green Gables'), findsOneWidget);
      expect(find.textContaining('LIVRO'), findsOneWidget);
      expect(find.text('Ver obra ↗'), findsOneWidget);
      expect(find.text('+ Ao Acervo'), findsOneWidget);

      await tester.tap(find.text('+ Ao Acervo'));
      await tester.pumpAndSettle();

      expect(state.userProfile.culturalItems.any((i) => i.id == 'work_anne'), isTrue);
    });
  });

  group('3. Secure File Download Helper Test', () {
    test('sanitizeFileName prevents path traversal and dangerous chars', () {
      expect(
        SecureFileDownloadHelper.sanitizeFileName('../../../etc/passwd'),
        'passwd',
      );
      expect(
        SecureFileDownloadHelper.sanitizeFileName('..\\windows\\system32\\cmd.exe'),
        'cmd.exe',
      );
      expect(
        SecureFileDownloadHelper.sanitizeFileName('arquivo?teste*com:caracteres|ruins.pdf'),
        'arquivo_teste_com_caracteres_ruins.pdf',
      );
    });

    test('saveFileSafely rejects tampering when expected hash mismatches', () async {
      final validBytes = utf8.encode('Nix Secure Document Content');
      final validHash = sha256.convert(validBytes).toString();

      final corruptedBytes = utf8.encode('Corrupted Tampered Document');

      expect(
        () => SecureFileDownloadHelper.saveFileSafely(
          bytes: corruptedBytes,
          rawFileName: 'doc_seguro.pdf',
          expectedSha256Hex: validHash,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('4. Avatar Frames & Profile Customization Test', () {
    test('AvatarFrameStyle string serialization and copyWith', () {
      const settings = UserSettings(
        avatarFrameStyle: 'cyberpunkNeon',
        avatarBorderWidth: 3.5,
        avatarFrameColorHex: '00FFFF',
      );

      final json = settings.toJson();
      expect(json['avatarFrameStyle'], 'cyberpunkNeon');
      expect(json['avatarBorderWidth'], 3.5);
      expect(json['avatarFrameColorHex'], '00FFFF');

      final deserialized = UserSettings.fromJson(json);
      expect(deserialized.avatarFrameStyle, 'cyberpunkNeon');
      expect(deserialized.avatarBorderWidth, 3.5);
      expect(deserialized.avatarFrameColorHex, '00FFFF');
    });

    testWidgets('NixUserAvatar renders frame decoration correctly', (tester) async {
      final state = NixState(loadMockData: false);
      addTearDown(state.dispose);
      state.updateSettings(state.settings.copyWith(
        avatarFrameStyle: 'tactical',
        avatarBorderWidth: 2.5,
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(
            home: Scaffold(
              body: NixUserAvatar(
                size: 56,
                showBorder: true,
                borderWidth: 2.5,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(NixUserAvatar), findsOneWidget);
    });
  });

  group('5. CulturalWorkSheet & Cultural Tracking Test', () {
    testWidgets('CulturalWorkSheet opens and toggles status chips', (tester) async {
      final state = NixState(loadMockData: false);
      addTearDown(state.dispose);

      const item = CulturalItem(
        id: 'item_edgerunners',
        title: 'Cyberpunk: Edgerunners',
        creatorOrYear: 'Studio Trigger (2022)',
        category: CulturalCategory.anime,
        rating: '9.4',
        monogram: 'CE',
        tracking: CulturalTracking(stage: CulturalStage.active),
      );
      state.addCulturalItem(item);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(
            home: Scaffold(
              body: CulturalWorkSheet(item: item),
            ),
          ),
        ),
      );

      expect(find.text('Cyberpunk: Edgerunners'), findsOneWidget);
      expect(find.text('assistindo'), findsOneWidget);

      // Clica para marcar como concluído
      await tester.tap(find.text('concluído'));
      await tester.pumpAndSettle();

      final updated = state.userProfile.culturalItems.firstWhere((i) => i.id == 'item_edgerunners');
      expect(updated.tracking.stage, CulturalStage.finished);
    });
  });

  group('6. Crypto Order Ownership & Cancellation Test', () {
    test('User can cancel own local signed order', () async {
      final state = NixState(loadMockData: false);
      addTearDown(state.dispose);

      final order = await state.createAndSignMoneroOrder(
        side: MoneroP2pSide.sell,
        pricePerXmr: 520000.0,
        minFiatLimit: 100.0,
        maxFiatLimit: 5000.0,
        fiatCurrency: 'BRL',
        paymentMethod: 'PIX',
        notes: 'Liberação imediata',
      );

      expect(state.isMyMoneroOrder(order.id), isTrue);
      expect(state.moneroOrders.any((o) => o.id == order.id), isTrue);

      final deleted = await state.cancelOrDeleteMoneroOrder(order.id);
      expect(deleted, isTrue);
      expect(state.isMyMoneroOrder(order.id), isFalse);
      expect(state.moneroOrders.any((o) => o.id == order.id), isFalse);
    });
  });
}
