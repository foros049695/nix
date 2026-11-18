import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
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

    return MaterialApp(
      title: 'Nix',
      theme: NixTheme.buildTheme(fontScale: fontScale),
      home: NixSplashWrapper(
        skipSplash: skipSplash,
        child: const AppShell(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
