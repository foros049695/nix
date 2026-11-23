import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/interface_wallpaper.dart';
import 'package:nix_client/core/security/file_picker_adapter.dart';
import 'package:nix_client/core/security/local_image_helper.dart';
import 'package:nix_client/features/navigation/interface_wallpaper_layer.dart';
import 'package:nix_client/features/navigation/workspace_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Video & Animated Media Support for Wallpapers, Profile Avatars and Banners', () {
    test('LocalImageHelper reconhece extensões de vídeo e mídia suportadas', () {
      const videos = ['mp4', 'webm', 'mkv', 'mov', 'avi'];
      for (final ext in videos) {
        expect(LocalImageHelper.supportedVideoExtensions.contains(ext), isTrue);
        expect(LocalImageHelper.isVideoExtension('test_file.$ext'), isTrue);
        expect(LocalImageHelper.isSupportedExtension('test_file.$ext'), isTrue);
      }

      const images = ['png', 'jpg', 'jpeg', 'webp', 'gif'];
      for (final ext in images) {
        expect(LocalImageHelper.isVideoExtension('photo.$ext'), isFalse);
        expect(LocalImageHelper.isSupportedExtension('photo.$ext'), isTrue);
      }

      expect(LocalImageHelper.isVideoExtension('document.pdf'), isFalse);
      expect(LocalImageHelper.isSupportedExtension('malicious.exe'), isFalse);
    });

    test('FilePickerAdapter inclui extensões de vídeo por padrão', () {
      final picker = ProgrammableFilePickerAdapter();
      expect(picker.pickImageCalls, 0);
      expect(LocalImageHelper.filePickerAdapter, isNotNull);
      for (final ext in ['mp4', 'webm', 'mkv', 'mov', 'avi']) {
        expect(LocalImageHelper.supportedExtensions.contains(ext), isTrue);
      }
    });

    test('sanitizeAndStoreImage processa vídeo e gera arquivo sanitizado', () async {
      final tempDir = await Directory.systemTemp.createTemp('nix_video_test_');
      addTearDown(() => tempDir.delete(recursive: true));

      final testVideo = File('${tempDir.path}/sample.mp4');
      await testVideo.writeAsBytes(List.filled(1024, 0x00));

      final result = await LocalImageHelper.sanitizeAndStoreImage(testVideo.path);
      expect(result, isNotNull);
      expect(File(result!).existsSync(), isTrue);
    });

    testWidgets('InterfaceWallpaperLayer identifica mídias animadas com segurança',
        (tester) async {
      const wallpaper = InterfaceWallpaper(
        opacity: 0.3,
        animated: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InterfaceWallpaperLayer(
              wallpaper: wallpaper,
              reducedMotion: false,
              child: Center(child: Text('Nix UI')),
            ),
          ),
        ),
      );

      expect(find.text('Nix UI'), findsOneWidget);
    });

    testWidgets('WorkspaceBannerView renderiza com banner nulo ou ausente sem falhar',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WorkspaceBannerView(
              banner: null,
            ),
          ),
        ),
      );

      expect(find.byType(WorkspaceBannerView), findsOneWidget);
    });
  });
}
