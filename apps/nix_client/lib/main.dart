import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'core/theme/nix_colors.dart';
import 'core/theme/nix_palette.dart';
import 'features/navigation/app_shell.dart';
import 'features/splash/splash_screen.dart';
import 'state/nix_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
