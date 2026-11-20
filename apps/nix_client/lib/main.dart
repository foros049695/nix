import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/security/fail_closed_http_overrides.dart';
import 'core/security/platform_runtime.dart';
import 'core/theme.dart';
import 'core/theme/nix_colors.dart';
import 'core/theme/nix_palette.dart';
import 'features/navigation/app_shell.dart';
import 'features/splash/splash_screen.dart';
import 'state/nix_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Instala firewall HTTP fail-closed ANTES de qualquer componente de rede ou UI
  // para impedir qualquer contato direto com a rede doméstica do usuário.
  NixFailClosedHttpOverrides.install();
  await NixPlatformPaths.initialize();
  runApp(
    ChangeNotifierProvider(
      create: (_) => NixState(),
      child: const NixApp(),
    ),
  );
}

class NixApp extends StatelessWidget {
  final bool skipSplash;

  const NixApp({super.key, this.skipSplash = false});

  @override
  Widget build(BuildContext context) {
    final fontScale = context.select<NixState, double>((s) => s.settings.fontScale);
    final palette = context.select<NixState, NixPalette>((s) => s.currentPalette);
    final themeMode = context.select<NixState, NixThemeMode>((s) => s.settings.themeMode);
    final reducedMotion = context.select<NixState, bool>((s) => s.settings.reducedMotion);
    final sysBrightness = MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.dark;
    final resolvedScheme = NixSurfaceScheme.resolve(themeMode, sysBrightness);
    NixColors.sync(resolvedScheme, palette);

    final activeTheme = NixTheme.buildTheme(
      scheme: resolvedScheme,
      palette: palette,
      fontScale: fontScale,
    );

    return MaterialApp(
      title: 'Nix',
      theme: activeTheme,
      darkTheme: NixTheme.buildTheme(
        scheme: themeMode == NixThemeMode.amoled
            ? NixSurfaceScheme.amoled
            : NixSurfaceScheme.darkYellow,
        palette: palette,
        fontScale: fontScale,
      ),
      themeAnimationDuration: reducedMotion ? Duration.zero : const Duration(milliseconds: 180),
      themeMode: themeMode == NixThemeMode.system
          ? ThemeMode.system
          : (resolvedScheme.isLight ? ThemeMode.light : ThemeMode.dark),
      home: NixSplashWrapper(
        skipSplash: skipSplash,
        child: const AppShell(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
