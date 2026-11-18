import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'state/nix_state.dart';
import 'features/navigation/app_shell.dart';

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
  const NixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nix — Comunicação Soberana',
      theme: NixTheme.tacticalDarkTheme,
      home: const AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}
