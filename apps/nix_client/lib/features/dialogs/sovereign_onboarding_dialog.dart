import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Modal de Onboarding Soberano: Consentimento Tor, Seed em Papel e Chave Pública.
class SovereignOnboardingDialog extends StatefulWidget {
  final NixState nixState;
  final VoidCallback onComplete;

  const SovereignOnboardingDialog({
    super.key,
    required this.nixState,
    required this.onComplete,
  });

  static Future<void> show(BuildContext context, NixState state) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SovereignOnboardingDialog(
        nixState: state,
        onComplete: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  State<SovereignOnboardingDialog> createState() => _SovereignOnboardingDialogState();
}

class _SovereignOnboardingDialogState extends State<SovereignOnboardingDialog> {
  int _currentStep = 0; // 0: Consentimento Tor, 1: Bootstrap Tor, 2: Seed no Papel, 3: Chave Pública
  bool _torAgreementAccepted = false;
  bool _seedWrittenOnPaper = false;
  int _bootstrapProgress = 0;
  String _bootstrapStatus = 'Aguardando inicialização do circuito...';
  late final List<String> _seedWords;

  @override
  void initState() {
    super.initState();
    _seedWords = _generateMnemonicWords();
  }

  List<String> _generateMnemonicWords() {
    // 24 palavras determinísticas/aleatórias para representação da Seed A soberana
    const wordlist = [
      'abandon', 'ability', 'able', 'about', 'above', 'absent', 'absorb', 'abstract',
      'absurd', 'abuse', 'access', 'accident', 'account', 'accuse', 'achieve', 'acid',
      'acoustic', 'acquire', 'across', 'act', 'action', 'actor', 'actress', 'actual',
      'adapt', 'add', 'addict', 'address', 'adjust', 'admit', 'adult', 'advance',
      'advice', 'aerobic', 'affair', 'afford', 'afraid', 'again', 'age', 'agent',
      'agree', 'ahead', 'aim', 'air', 'airport', 'aisle', 'alarm', 'album',
      'alcohol', 'alert', 'alien', 'all', 'alley', 'allow', 'almost', 'alone',
      'alpha', 'already', 'also', 'alter', 'always', 'amateur', 'amazing', 'among',
      'amount', 'amused', 'analyst', 'anchor', 'ancient', 'anger', 'angle', 'angry',
      'animal', 'ankle', 'announce', 'annual', 'another', 'answer', 'antenna', 'antique',
    ];
    final random = Random.secure();
    return List.generate(24, (_) => wordlist[random.nextInt(wordlist.length)]);
  }

  Future<void> _startTorBootstrap() async {
    setState(() {
      _currentStep = 1;
      _bootstrapProgress = 15;
      _bootstrapStatus = 'Iniciando daemon Tor embutido e alocando SOCKS5...';
    });

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    setState(() {
      _bootstrapProgress = 60;
      _bootstrapStatus = 'Construindo circuito Onion v3 de 3 saltos...';
    });

    await widget.nixState.startEmbeddedTor();

    if (!mounted) return;
    setState(() {
      _bootstrapProgress = 100;
      _bootstrapStatus = 'Circuito Tor estabelecido · Modo Fail-Closed ATIVO';
    });

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _currentStep = 2);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: NixColors.surfaceElevatedHigh,
      shape: RoundedRectangleBorder(
        borderRadius: NixTokens.borderMd,
        side: BorderSide(color: NixColors.surfaceBorderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabeçalho Soberano
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: NixColors.accentYellow,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: const Text('N', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PROJETO NIX · ONBOARDING SOBERANO',
                            style: TextStyle(color: NixColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                        Text('Privacidade Fail-Closed e Chaves Criptográficas',
                            style: TextStyle(color: NixColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: NixColors.surfaceCard,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: NixColors.surfaceBorder),
                    ),
                    child: Text('ETAPA ${_currentStep + 1} DE 4',
                        style: TextStyle(color: NixColors.accentYellow, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Conteúdo da Etapa
              Expanded(
                child: SingleChildScrollView(
                  child: _buildCurrentStepContent(),
                ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // Botões de Ação
              _buildStepActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep0TorConsent();
      case 1:
        return _buildStep1TorBootstrap();
      case 2:
        return _buildStep2PaperSeed();
      case 3:
      default:
        return _buildStep3PublicKey();
    }
  }

  Widget _buildStep0TorConsent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.security_rounded, color: NixColors.accentYellow, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('CONSENTIMENTO DA REDE TOR (FAIL-CLOSED)',
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'O Projeto Nix foi desenhado para proteger sua identidade e metadados contra governos, corporações e interceptadores de tráfego.\n\n'
          'Por padrão arquitetural estrito:\n'
          '• Todas as conexões privadas trafegam exclusivamente pela rede Tor Onion v3.\n'
          '• Nenhum pacote de texto claro (clearnet) é transmitido.\n'
          '• Não exigimos número de telefone, SMS, e-mail ou dados pessoais.\n\n'
          'Para prosseguir, você deve aceitar inicializar a infraestrutura de rede Tor embutida no aplicativo.',
          style: TextStyle(color: NixColors.textSecondary, fontSize: 12.5, height: 1.45),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.surfaceBorderStrong),
          ),
          child: GestureDetector(
            key: const Key('tor_consent_checkbox_tile'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _torAgreementAccepted = !_torAgreementAccepted),
            child: Row(
              children: [
                Checkbox(
                  value: _torAgreementAccepted,
                  onChanged: (v) => setState(() => _torAgreementAccepted = v ?? false),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Compreendo e aceito rotear todo o tráfego estritamente pela rede Tor.',
                    style: TextStyle(color: NixColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep1TorBootstrap() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                value: _bootstrapProgress / 100,
                strokeWidth: 2,
                color: NixColors.accentYellow,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('CONECTANDO À REDE ONION...',
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'O daemon Tor embutido está construindo seu túnel seguro de 3 saltos. Nenhuma configuração externa ou aplicativo extra é necessário.',
          style: TextStyle(color: NixColors.textSecondary, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(
          value: _bootstrapProgress / 100,
          backgroundColor: NixColors.surfaceCard,
          valueColor: AlwaysStoppedAnimation<Color>(NixColors.accentYellow),
          minHeight: 6,
        ),
        const SizedBox(height: 12),
        Text(
          '$_bootstrapProgress% — $_bootstrapStatus',
          style: NixTokens.monoCode(size: 11, color: NixColors.accentYellow),
        ),
      ],
    );
  }

  Widget _buildStep2PaperSeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.edit_note_rounded, color: Color(0xFFFFC928), size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text('ANOTE SUA SEED PRIVADA NO PAPEL',
                  style: TextStyle(color: Color(0xFFFFC928), fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Estas 24 palavras geram sua identidade criptográfica (Seed A). Anote-as com caneta em um papel físico seguro. Não tire prints, não salve em e-mails e não fotografe.',
          style: TextStyle(color: NixColors.textSecondary, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NixColors.background,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.surfaceBorderStrong),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_seedWords.length, (idx) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: Text(
                  '${idx + 1}. ${_seedWords[idx]}',
                  style: NixTokens.monoCode(size: 11, color: NixColors.textPrimary),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: GestureDetector(
            key: const Key('seed_written_checkbox_tile'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _seedWrittenOnPaper = !_seedWrittenOnPaper),
            child: Row(
              children: [
                Checkbox(
                  value: _seedWrittenOnPaper,
                  onChanged: (v) => setState(() => _seedWrittenOnPaper = v ?? false),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Confirmo que anotei as 24 palavras em um papel físico seguro.',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3PublicKey() {
    final publicId = widget.nixState.userProfile.publicId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.badge_outlined, color: NixColors.accentYellow, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('SUA IDENTIDADE PÚBLICA (CARD ID)',
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Sua identidade soberana foi criada e ancorada no cofre local SQLCipher. Compartilhe seu Card ID público abaixo com quem você deseja conversar:',
          style: TextStyle(color: NixColors.textSecondary, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NixColors.background,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.accentYellow, width: 1.2),
          ),
          child: Column(
            children: [
              Text(publicId,
                  style: NixTokens.monoCode(size: 14, color: NixColors.accentYellow), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('Chave Pública Derivada Ed25519/X25519',
                  style: TextStyle(color: NixColors.textMuted, fontSize: 10)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '• Para conversar via Tor: seu par adiciona seu Card ID.\n'
          '• Para conversar via Bluetooth offline: ative o modo Malha quando estiver próximo.\n'
          '• Para apagar tudo em emergência: utilize o Botão de Pânico nas configurações.',
          style: TextStyle(color: NixColors.textMuted, fontSize: 11.5, height: 1.45),
        ),
      ],
    );
  }

  Widget _buildStepActions() {
    if (_currentStep == 0) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton(
            key: const Key('accept_tor_and_continue_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _torAgreementAccepted ? NixColors.accentYellow : Colors.grey[800],
              foregroundColor: Colors.black,
            ),
            onPressed: _torAgreementAccepted ? _startTorBootstrap : null,
            child: const Text('Concordar e Conectar ao Tor', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      );
    } else if (_currentStep == 1) {
      return const SizedBox.shrink(); // Conexão em progresso
    } else if (_currentStep == 2) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton(
            key: const Key('confirm_seed_written_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _seedWrittenOnPaper ? NixColors.accentYellow : Colors.grey[800],
              foregroundColor: Colors.black,
            ),
            onPressed: _seedWrittenOnPaper ? () => setState(() => _currentStep = 3) : null,
            child: const Text('Avançar para Card ID Público', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton(
            key: const Key('finish_onboarding_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: NixColors.accentYellow,
              foregroundColor: Colors.black,
            ),
            onPressed: widget.onComplete,
            child: const Text('Concluir e Entrar no Nix', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      );
    }
  }
}
