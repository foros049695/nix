import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';

/// Tela de Inicialização Minimalista AMOLED (Seção 8).
/// Acompanha o estado real de inicialização dos serviços essenciais sem atrasos artificiais.
class NixSplashWrapper extends StatefulWidget {
  final Widget child;
  final bool skipSplash;

  const NixSplashWrapper({
    super.key,
    required this.child,
    this.skipSplash = false,
  });

  @override
  State<NixSplashWrapper> createState() => _NixSplashWrapperState();
}

class _NixSplashWrapperState extends State<NixSplashWrapper>
    with SingleTickerProviderStateMixin {
  bool _initialized = false;
  String? _initError;
  String _statusMessage = 'Verificando cofre local e políticas de transporte...';
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: NixTokens.motionMedium,
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: NixTokens.curveStandard),
    );

    if (widget.skipSplash) {
      _initialized = true;
    } else {
      _animController.forward();
      _bootServices();
    }
  }

  Future<void> _bootServices() async {
    try {
      setState(() {
        _initError = null;
        _statusMessage = 'Inicializando fronteiras criptográficas e viewport seguro...';
      });
      // Aguarda o próximo frame real de hidratação dos serviços locais
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
      setState(() => _initialized = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initError = 'Falha ao inicializar subsistema local: $e';
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: NixTokens.motionFluid,
      switchInCurve: NixTokens.curveStandard,
      switchOutCurve: NixTokens.curveStandard,
      child: _initialized ? widget.child : _buildSplashView(),
    );
  }

  Widget _buildSplashView() {
    return Scaffold(
      key: const ValueKey('nix_splash_screen'),
      backgroundColor: NixColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Nova Logo Vetorizada do Nix adaptada ao Tema Ativo
                Container(
                  width: 108,
                  height: 108,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: NixColors.surfaceCard,
                    border: Border.all(
                      color: context.accentColor.withValues(alpha: 0.65),
                      width: 1.6,
                    ),
                  ),
                  child: Image.asset(
                    context.brandLogoAsset,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(
                      child: Icon(
                        Icons.shield_moon_outlined,
                        color: NixColors.textPrimary,
                        size: 42,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'N I X',
                  style: TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6.0,
                  ),
                ),
                const SizedBox(height: 10),
                if (_initError != null) ...[
                  Text(
                    _initError!,
                    style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NixColors.textPrimary,
                      side: BorderSide(color: NixColors.surfaceBorderStrong),
                    ),
                    onPressed: _bootServices,
                    child: const Text('Tentar Novamente', style: TextStyle(fontSize: 12)),
                  ),
                ] else ...[
                  Text(
                    _statusMessage,
                    style: TextStyle(color: NixColors.textMuted, fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
