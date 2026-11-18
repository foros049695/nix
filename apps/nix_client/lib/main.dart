import 'package:flutter/material.dart';
import 'core/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NixApp());
}

class NixApp extends StatelessWidget {
  const NixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nix — Comunicação Segura',
      theme: NixTheme.tacticalDarkTheme,
      home: const NixHomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class NixHomeScreen extends StatelessWidget {
  const NixHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🏴‍☠️ NIX'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Status de Privacidade: Tor Ativo (Fail-Closed)',
            onPressed: () {},
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_clock, size: 72, color: Colors.greenAccent),
              const SizedBox(height: 16),
              Text(
                'PROJETO NIX',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      letterSpacing: 2.0,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Fase 1: Núcleo Local & Armazenamento Seguro',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• Identidade: Local (Sem telefone/email)',
                        style: TextStyle(color: Colors.white60)),
                    SizedBox(height: 6),
                    Text('• Banco: SQLCipher (Criptografado)',
                        style: TextStyle(color: Colors.white60)),
                    SizedBox(height: 6),
                    Text('• Rede: Tor Fail-Closed (Sem fallback IP)',
                        style: TextStyle(color: Colors.white60)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
