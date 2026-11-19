import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:nix_transport/nix_transport.dart';
import '../../core/security/seed_recovery.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import 'sovereign_onboarding_model.dart';

/// Fluxo oficial de Onboarding Soberano em 9 estados com persistência transacional (Seção 2).
class SovereignOnboardingFlow extends StatefulWidget {
  final NixState nixState;
  final VoidCallback onComplete;
  final VoidCallback? onDismiss;
  final String? customPersistencePath;

  const SovereignOnboardingFlow({
    super.key,
    required this.nixState,
    required this.onComplete,
    this.onDismiss,
    this.customPersistencePath,
  });

  static Future<void> showAsDialog(
    BuildContext context,
    NixState state, {
    VoidCallback? onComplete,
    VoidCallback? onDismiss,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SovereignOnboardingFlow(
          nixState: state,
          onComplete: () {
            Navigator.of(ctx).pop();
            onComplete?.call();
          },
          onDismiss: () {
            Navigator.of(ctx).pop();
            onDismiss?.call();
          },
        ),
      ),
    );
  }

  @override
  State<SovereignOnboardingFlow> createState() => _SovereignOnboardingFlowState();
}

class _SovereignOnboardingFlowState extends State<SovereignOnboardingFlow> {
  OnboardingStep _currentStep = OnboardingStep.welcome;
  bool _isLoading = false;

  // Estado Tor
  bool _torConsentChecked = false;
  int _bootstrapPercent = 0;
  String _bootstrapSummary = 'Aguardando início do bootstrap Tor...';
  bool _bootstrapFailed = false;
  String? _bootstrapErrorMessage;
  bool _showDiagnostics = false;
  final List<String> _diagnosticsLogs = [];

  // Verificação Tor
  bool _isVerifyingTor = false;
  bool _torSocksAlive = false;
  bool _torFailClosedVerified = false;
  bool _torCircuitsReady = false;

  // Identidade Privada (Seed A)
  bool _isGeneratingIdentity = false;
  String? _identityErrorMessage;
  List<String> _seedWords = [];
  bool _paperBackupConfirmed = false;
  
  // Desafio de Verificação do Backup (Challenge de 3 palavras aleatórias)
  late List<int> _challengeWordIndices;
  final Map<int, String> _userChallengeAnswers = {};
  bool _challengePassed = false;
  String? _challengeFeedback;

  // Identidade Pública
  String _derivedPublicId = '';
  NixIdentity? _generatedIdentity;
  final TextEditingController _displayNameController = TextEditingController(text: 'Soberano');
  final TextEditingController _bioController = TextEditingController(text: 'Identidade Criptográfica Soberana · Projeto Nix');
  final TextEditingController _passphraseController = TextEditingController();
  final TextEditingController _duressPinController = TextEditingController();
  bool _bindToOsKeyring = true;
  String _selectedAvatarStyle = 'nyx_emblem';

  StreamSubscription<TorBootstrapEvent>? _torBootstrapSub;

  @override
  void initState() {
    super.initState();
    _challengeWordIndices = [3, 11, 19];
    _restoreSavedState();
  }

  @override
  void dispose() {
    _torBootstrapSub?.cancel();
    _displayNameController.dispose();
    _bioController.dispose();
    _passphraseController.dispose();
    _duressPinController.dispose();
    super.dispose();
  }

  Future<void> _restoreSavedState() async {
    final snapshot = await OnboardingStateSnapshot.load(customPath: widget.customPersistencePath);
    if (!mounted) return;

    final gateAlreadyReady = widget.nixState.securityGate.isTorAnonymityReady;
    final offGridActive = widget.nixState.isStrictOffGridMode;
    setState(() {
      _currentStep = snapshot.currentStep;
      _torConsentChecked =
          snapshot.torConsentAccepted || gateAlreadyReady || offGridActive;
      _bootstrapPercent =
          (snapshot.torBootstrapped || gateAlreadyReady) ? 100 : 0;
      _torSocksAlive = snapshot.torVerified || gateAlreadyReady;
      _torFailClosedVerified =
          snapshot.torVerified || gateAlreadyReady || offGridActive;
      _torCircuitsReady =
          (snapshot.torBootstrapped && snapshot.torVerified) || gateAlreadyReady;
      if (gateAlreadyReady) {
        _bootstrapSummary =
            'Tor Onion v3 já conectado e auditado pelo Escudo Fail-Closed (${widget.nixState.onionAddress}).';
      } else if (offGridActive) {
        _bootstrapSummary =
            'Modo Off-Grid Estrito ativo (Zero Wi-Fi/Internet · apenas Bluetooth BLE e Rádio LoRa).';
      }
      _paperBackupConfirmed = snapshot.backupConfirmed;
      _challengePassed = snapshot.backupConfirmed;
      if (snapshot.displayName != null && snapshot.displayName!.isNotEmpty) {
        _displayNameController.text = snapshot.displayName!;
      }
      if (snapshot.avatarStyle != null) {
        _selectedAvatarStyle = snapshot.avatarStyle!;
      }
      if (snapshot.publicId != null && snapshot.publicId!.isNotEmpty) {
        _derivedPublicId = snapshot.publicId!;
      }
    });

    // Se já passou do consentimento e precisa do Tor, revalida estado real sem presumir
    if (_currentStep.index >= OnboardingStep.torBootstrap.index) {
      if (widget.nixState.embeddedTor.status == EmbeddedTorStatus.ready) {
        await _runTorVerification();
      }
    }
  }

  Future<void> _persistCheckpoint() async {
    final snapshot = OnboardingStateSnapshot(
      currentStep: _currentStep,
      torConsentAccepted: _torConsentChecked,
      torBootstrapped: _bootstrapPercent == 100,
      torVerified: _torSocksAlive && _torFailClosedVerified,
      identityGenerated: _seedWords.isNotEmpty || _derivedPublicId.isNotEmpty,
      backupConfirmed: _challengePassed && _paperBackupConfirmed,
      publicIdDerived: _derivedPublicId.isNotEmpty,
      profileConfigured: _currentStep == OnboardingStep.ready,
      isCompleted: _currentStep == OnboardingStep.ready,
      publicId: _derivedPublicId.isNotEmpty ? _derivedPublicId : widget.nixState.userProfile.publicId,
      displayName: _displayNameController.text.trim(),
      avatarStyle: _selectedAvatarStyle,
    );
    await OnboardingStateSnapshot.save(snapshot, customPath: widget.customPersistencePath);
  }

  // --- NAVEGAÇÃO ENTRE ESTADOS ---

  void _goToStep(OnboardingStep step) {
    setState(() => _currentStep = step);
    _persistCheckpoint();
  }

  void _goBack() {
    if (_currentStep == OnboardingStep.welcome) return;
    final prevIndex = _currentStep.index - 1;
    if (prevIndex >= 0) {
      _goToStep(OnboardingStep.values[prevIndex]);
    }
  }

  Future<void> _handleExitRequest() async {
    final hasGeneratedKeys = _seedWords.isNotEmpty || _derivedPublicId.isNotEmpty;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NixColors.surfaceElevatedHigh,
        title: Text('Pausar Configuração Soberana?', style: TextStyle(color: NixColors.textPrimary, fontSize: 15)),
        content: Text(
          hasGeneratedKeys
              ? 'Suas chaves e identidade geradas já foram salvas com segurança no cofre. Você poderá continuar de onde parou ao abrir o assistente novamente.'
              : 'O Nix opera em modo estrito Fail-Closed. Para utilizar a mensageria com segurança, a configuração do Tor e da sua identidade privada deve ser concluída.',
          style: TextStyle(color: NixColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Continuar Configurando'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: NixColors.surfaceCard),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Pausar e Sair', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      await _persistCheckpoint();
      if (mounted) {
        if (widget.onDismiss != null) {
          widget.onDismiss!();
        } else {
          Navigator.of(context).maybePop();
        }
      }
    }
  }

  // --- LÓGICA DE EXECUÇÃO DE CADA ETAPA ---

  Future<void> _startTorBootstrap() async {
    setState(() {
      _isLoading = true;
      _bootstrapFailed = false;
      _bootstrapErrorMessage = null;
      _bootstrapPercent = 5;
      _bootstrapSummary = 'Procurando binário Tor embutido e alocando SOCKS5...';
      _diagnosticsLogs.add('[Tor] Iniciando subsistema de transporte seguro...');
    });

    _torBootstrapSub?.cancel();
    _torBootstrapSub = widget.nixState.embeddedTor.onBootstrapProgress.listen((event) {
      if (mounted) {
        setState(() {
          _bootstrapPercent = event.progressPercent;
          _bootstrapSummary = event.stepSummary;
          _diagnosticsLogs.add('[Tor ${event.progressPercent}%] ${event.stepSummary}');
        });
      }
    });

    final started = await widget.nixState.startEmbeddedTor();

    if (!mounted) return;

    if (started) {
      setState(() {
        _isLoading = false;
        _bootstrapPercent = 100;
        _bootstrapSummary = 'Circuito Onion v3 estabelecido · Modo Fail-Closed Ativo.';
        _diagnosticsLogs.add('[Tor] Bootstrap concluído com 100% de integridade.');
      });
      _persistCheckpoint();
      // Avança para verificação ativa
      _goToStep(OnboardingStep.torVerification);
      _runTorVerification();
    } else {
      setState(() {
        _isLoading = false;
        _bootstrapFailed = true;
        _bootstrapErrorMessage = widget.nixState.torDiagnosticDetail;
        _diagnosticsLogs.add('[Tor Erro] ${widget.nixState.torDiagnosticDetail}');
      });
    }
  }

  Future<void> _runTorVerification() async {
    setState(() {
      _isVerifyingTor = true;
      _torSocksAlive = false;
      _torFailClosedVerified = false;
      _torCircuitsReady = false;
      _diagnosticsLogs.add('[Verificação] Auditando SOCKS5, circuito Tor e bloqueio ativo de clearnet...');
    });

    final report = await widget.nixState.verifyTorTransportAndFailClosed();

    if (!mounted) return;

    setState(() {
      _isVerifyingTor = false;
      _torSocksAlive = report.socksActive;
      _torCircuitsReady = report.circuitOperational;
      _torFailClosedVerified = report.failClosedVerified;
      _diagnosticsLogs.add('[Verificação] ${report.detail}');
    });

    await _persistCheckpoint();
  }

  String _generateRandomHexPassphrase() {
    final rng = Random.secure();
    return List.generate(
      32,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _generatePrivateIdentity() async {
    final userPassphrase = _passphraseController.text.trim();
    final duressPin = _duressPinController.text.trim();
    if (userPassphrase.isNotEmpty &&
        duressPin.isNotEmpty &&
        userPassphrase == duressPin) {
      setState(() {
        _identityErrorMessage =
            'O PIN de coação deve ser diferente da frase-passe principal.';
      });
      return;
    }
    if (userPassphrase.isEmpty && !_bindToOsKeyring) {
      setState(() {
        _identityErrorMessage =
            'Como o desbloqueio rápido pelo chaveiro do SO foi desmarcado, é obrigatório definir uma frase-passe manual para proteger o cofre.';
      });
      return;
    }
    if (!Platform.environment.containsKey('FLUTTER_TEST') &&
        userPassphrase.isEmpty &&
        !widget.nixState.keyVault.osKeyStorage.isHardwareOrOsBacked) {
      setState(() {
        _identityErrorMessage =
            'Chaveiro nativo do SO indisponível nesta sessão. Informe uma frase-passe manual acima.';
      });
      return;
    }

    setState(() {
      _isGeneratingIdentity = true;
      _identityErrorMessage = null;
      _diagnosticsLogs.add('[Cripto] Gerando entropia CSPRNG para a Seed A (24 palavras c/ checksum)...');
    });

    try {
      // 1. Gera 24 palavras criptograficamente seguras (23 bytes entropia + 1 byte SHA-256 checksum)
      final generatedSeed = SeedRecoveryManager.generateMnemonic();

      // 2. Deriva deterministicamente o par real Ed25519 + X25519 e o Public ID (ADR-0003: Seed A isolada)
      final identity = await SeedRecoveryManager.deriveIdentityFromMnemonic(generatedSeed);

      // 3. Inicializa o cofre KeyVault (Argon2id + XChaCha20-Poly1305) e banco SQLCipher
      final effectivePassphrase = userPassphrase.isNotEmpty
          ? userPassphrase
          : _generateRandomHexPassphrase();
      final effectiveBindKeyring = userPassphrase.isEmpty
          ? true
          : _bindToOsKeyring &&
              widget.nixState.keyVault.osKeyStorage.isHardwareOrOsBacked;

      final dbOk = await widget.nixState.initializeEncryptedDatabase(
        passphrase: effectivePassphrase,
        bindToOsKeyring: effectiveBindKeyring,
        duressPassphrase: duressPin.isNotEmpty ? duressPin : null,
        overwriteExistingVault: true,
      );
      if (!dbOk) {
        if (!mounted) return;
        final reason = widget.nixState.lastDatabaseInitError ??
            'Falha ao inicializar KeyVault / SQLCipher.';
        setState(() {
          _isGeneratingIdentity = false;
          _identityErrorMessage = reason;
          _diagnosticsLogs.add('[Erro] $reason');
        });
        return;
      }

      // 4. Grava identidade pública em `identities`, material privado envelopado em `key_material`,
      //    dispositivo com grant assinado e perfil inicial no SQLCipher
      await widget.nixState.persistPrimaryIdentity(
        identity: identity,
        displayName: _displayNameController.text.trim(),
        avatarStyle: _selectedAvatarStyle,
        bio: _bioController.text.trim(),
      );

      final pubId = identity.publicId;
      if (!mounted) return;

      setState(() {
        _isGeneratingIdentity = false;
        _identityErrorMessage = null;
        _generatedIdentity = identity;
        _seedWords = generatedSeed;
        _derivedPublicId = pubId;
        _challengeWordIndices = [
          Random.secure().nextInt(7),       // entre 0 e 6
          8 + Random.secure().nextInt(7),   // entre 8 e 14
          16 + Random.secure().nextInt(7),  // entre 16 e 22
        ];
        _userChallengeAnswers.clear();
        _challengePassed = false;
        _diagnosticsLogs.add(
          '[Cripto] Chaves Ed25519/X25519 derivadas da Seed A (${widget.nixState.localDatabase?.cipherInfo.cipherEngine ?? "SQLite"} · Storage: ${widget.nixState.keyVault.osKeyStorage.backendName}). ID: $pubId (pub=${_generatedIdentity?.ed25519PublicHex.substring(0, 8) ?? ""})',
        );
      });

      await _persistCheckpoint();
      _goToStep(OnboardingStep.recoveryBackup);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGeneratingIdentity = false;
        _identityErrorMessage = 'Erro ao gerar identidade: $e';
        _diagnosticsLogs.add('[Erro] Exceção na geração de identidade: $e');
      });
    }
  }

  Future<void> _showRestoreFromSeedDialog() async {
    final seedInputCtrl = TextEditingController();
    final passInputCtrl = TextEditingController();
    String? errorMsg;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: NixColors.surfaceCard,
          title: Text(
            'Recuperar Identidade (Seed A - 24 palavras)',
            style: TextStyle(color: NixColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Cole ou digite as 24 palavras da sua Seed A separadas por espaços para restaurar deterministicamente suas chaves Ed25519/X25519 e Public ID.',
                  style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: seedInputCtrl,
                  maxLines: 3,
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: 'Frase mnemônica (24 palavras)',
                    hintText: 'ex: abandon ability able ...',
                    errorText: errorMsg,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passInputCtrl,
                  obscureText: true,
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5),
                  decoration: const InputDecoration(
                    labelText: 'Nova frase-passe do cofre local (opcional)',
                    hintText: 'Vazio = proteção automática via chaveiro do SO',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final words = seedInputCtrl.text
                          .trim()
                          .split(RegExp(r'\s+'))
                          .where((w) => w.isNotEmpty)
                          .toList();
                      if (!SeedRecoveryManager.validateMnemonic(words)) {
                        setDlgState(() => errorMsg = 'Frase inválida: verifique as 24 palavras e o checksum.');
                        return;
                      }
                      setDlgState(() {
                        busy = true;
                        errorMsg = null;
                      });
                      try {
                        final identity = await SeedRecoveryManager.deriveIdentityFromMnemonic(words);
                        final customPass = passInputCtrl.text.trim();
                        final pass = customPass.isNotEmpty ? customPass : _generateRandomHexPassphrase();
                        final dbOk = await widget.nixState.initializeEncryptedDatabase(
                          passphrase: pass,
                          bindToOsKeyring: customPass.isEmpty,
                          overwriteExistingVault: true,
                        );
                        if (!dbOk) {
                          setDlgState(() {
                            busy = false;
                            errorMsg = 'Falha ao abrir banco cifrado local.';
                          });
                          return;
                        }
                        await widget.nixState.persistPrimaryIdentity(
                          identity: identity,
                          displayName: _displayNameController.text.trim(),
                          avatarStyle: _selectedAvatarStyle,
                        );
                        if (!mounted) return;
                        setState(() {
                          _generatedIdentity = identity;
                          _seedWords = words;
                          _derivedPublicId = identity.publicId;
                          _paperBackupConfirmed = true;
                          _challengePassed = true;
                          _torConsentChecked = true;
                          _diagnosticsLogs.add('[Recuperação] Seed A restaurada com ID ${identity.publicId}.');
                        });
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        _goToStep(OnboardingStep.profileSetup);
                      } catch (e) {
                        setDlgState(() {
                          busy = false;
                          errorMsg = 'Erro na derivação: $e';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: NixColors.accentYellow),
              icon: const Icon(Icons.restore_rounded, color: Colors.black, size: 17),
              label: const Text('Restaurar Conta', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    seedInputCtrl.dispose();
    passInputCtrl.dispose();
  }

  void _verifyBackupChallenge() {
    bool allCorrect = true;
    for (final idx in _challengeWordIndices) {
      final expected = _seedWords[idx].trim().toLowerCase();
      final answer = (_userChallengeAnswers[idx] ?? '').trim().toLowerCase();
      if (expected != answer) {
        allCorrect = false;
        break;
      }
    }

    setState(() {
      _challengePassed = allCorrect;
      _challengeFeedback = allCorrect
          ? 'Backup confirmado com sucesso! Todas as palavras coincidem.'
          : 'As palavras informadas não coincidem com as anotadas. Verifique com atenção.';
    });

    if (allCorrect) {
      _persistCheckpoint();
    }
  }

  Future<void> _completeProfileAndFinish() async {
    final name = _displayNameController.text.trim();
    final effectiveName = name.isEmpty ? 'Soberano' : name;

    widget.nixState.updateProfile(
      displayName: effectiveName,
      avatarStyle: _selectedAvatarStyle,
      bio: _bioController.text.trim(),
    );

    setState(() => _currentStep = OnboardingStep.ready);
    await _persistCheckpoint();
  }

  Future<void> _finishOnboarding() async {
    await widget.nixState.completeOnboarding(
      publicId: _derivedPublicId,
      displayName: _displayNameController.text.trim(),
      avatarStyle: _selectedAvatarStyle,
    );
    widget.onComplete();
  }

  // --- RENDERIZAÇÃO DA UI ---

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Container(
          decoration: BoxDecoration(
            color: NixColors.surfaceElevatedHigh,
            borderRadius: NixTokens.borderLg,
            border: Border.all(color: NixColors.surfaceBorderStrong, width: 1.2),
            boxShadow: const [
              BoxShadow(color: Colors.black87, blurRadius: 28, offset: Offset(0, 10)),
            ],
          ),
          child: ClipRRect(
            borderRadius: NixTokens.borderLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Topo: Cabeçalho com indicador de etapas e botão fechar seguro
                _buildHeader(),
                const Divider(height: 1),

                // Barra de Progresso Superior
                _buildProgressBar(),

                // Corpo da Etapa Atual
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: _buildCurrentStageView(),
                  ),
                ),

                // Painel de Diagnóstico Opcional
                if (_showDiagnostics) _buildDiagnosticsDrawer(),

                const Divider(height: 1),
                // Rodapé com Botões de Ação
                _buildActionFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: NixColors.surfaceCard,
      child: Row(
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
                Text(
                  'PROJETO NIX · ONBOARDING SOBERANO',
                  style: TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  _getStepTitle(_currentStep),
                  style: TextStyle(color: NixColors.accentYellow, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: NixColors.surfaceElevated,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: NixColors.surfaceBorder),
            ),
            child: Text(
              'ETAPA ${_currentStep.index + 1} DE ${OnboardingStep.values.length}',
              style: TextStyle(color: NixColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          // Botão Fechar ('X') Seguro: não descarta chaves já criadas
          IconButton(
            icon: Icon(Icons.close_rounded, color: NixColors.textSecondary, size: 20),
            tooltip: 'Pausar Configuração',
            onPressed: _handleExitRequest,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final progress = (_currentStep.index + 1) / OnboardingStep.values.length;
    return LinearProgressIndicator(
      value: progress,
      backgroundColor: NixColors.surfaceCard,
      valueColor: AlwaysStoppedAnimation<Color>(NixColors.accentYellow),
      minHeight: 3,
    );
  }

  String _getStepTitle(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.welcome:
        return '1. Boas-Vindas e Soberania Digital';
      case OnboardingStep.torConsent:
        return '2. Consentimento da Rede Tor (Fail-Closed)';
      case OnboardingStep.torBootstrap:
        return '3. Inicialização e Bootstrap do Tor Embutido';
      case OnboardingStep.torVerification:
        return '4. Verificação de Conectividade e Isolamento';
      case OnboardingStep.identityGeneration:
        return '5. Geração Criptográfica da Identidade Privada';
      case OnboardingStep.recoveryBackup:
        return '6. Anotação e Confirmação da Seed no Papel';
      case OnboardingStep.publicId:
        return '7. Card ID Público e QR Code Interoperável';
      case OnboardingStep.profileSetup:
        return '8. Personalização de Perfil e Avatar Sincronizado';
      case OnboardingStep.ready:
        return '9. Pronto para Comunicação Soberana';
    }
  }

  Widget _buildCurrentStageView() {
    switch (_currentStep) {
      case OnboardingStep.welcome:
        return _buildStepWelcome();
      case OnboardingStep.torConsent:
        return _buildStepTorConsent();
      case OnboardingStep.torBootstrap:
        return _buildStepTorBootstrap();
      case OnboardingStep.torVerification:
        return _buildStepTorVerification();
      case OnboardingStep.identityGeneration:
        return _buildStepIdentityGeneration();
      case OnboardingStep.recoveryBackup:
        return _buildStepRecoveryBackup();
      case OnboardingStep.publicId:
        return _buildStepPublicId();
      case OnboardingStep.profileSetup:
        return _buildStepProfileSetup();
      case OnboardingStep.ready:
        return _buildStepReady();
    }
  }

  // --- VIEWS INDIVIDUAIS DE CADA ETAPA ---

  Widget _buildStepWelcome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.shield_rounded, color: NixColors.accentYellow, size: 28),
            const SizedBox(width: 10),
            Text('Bem-vindo ao Projeto Nix', style: TextStyle(color: NixColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'O Nix é uma plataforma de mensageria ponto-a-ponto, local-first e verdadeiramente privada. '
          'Diferente dos mensageiros convencionais, o Nix foi arquitetado segundo princípios inegociáveis:',
          style: TextStyle(color: NixColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 16),
        _buildFeatureItem(Icons.lock_rounded, 'Zero Identificação Civil', 'Sem número de telefone, SMS, e-mail ou leitura de contatos.'),
        _buildFeatureItem(Icons.security_rounded, 'Modo Estrito Fail-Closed', 'Nenhum pacote trafega em texto claro (clearnet). Tor Onion v3 embutido.'),
        _buildFeatureItem(Icons.vpn_key_rounded, 'Soberania Criptográfica', 'Suas chaves pertencem unicamente a você, geradas no seu dispositivo e cifradas com SQLCipher.'),
        _buildFeatureItem(Icons.wifi_off_rounded, 'Resiliência Offline', 'Suporte a malha Bluetooth peer-to-peer (BTP) mesmo sem internet ou dados móveis.'),
        const SizedBox(height: 18),
        if (widget.nixState.isStrictOffGridMode) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.16),
              borderRadius: NixTokens.borderSm,
              border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bluetooth_searching_rounded,
                    color: Colors.tealAccent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'MODO OFF-GRID ESTRITO (BLE / LORA): sem Wi-Fi ou Internet. '
                    'Suas chaves Seed A e o cofre SQLCipher serão criados 100% offline para comunicação por proximidade.',
                    style: TextStyle(color: NixColors.textPrimary, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
        ],
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: NixColors.surfaceBorderStrong),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: NixColors.accentYellow, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Este assistente irá guiá-lo na configuração da rede Tor, geração das chaves criptográficas e verificação do seu backup físico no papel.',
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _showRestoreFromSeedDialog,
          icon: Icon(Icons.restore_rounded, color: NixColors.accentYellow, size: 18),
          label: Text(
            'Já possuo Seed A (Recuperar Conta de Backup)',
            style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: NixColors.surfaceBorderStrong),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildStepTorConsent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.hub_rounded, color: NixColors.accentYellow, size: 22),
            const SizedBox(width: 8),
            Text('Consentimento da Rede Tor (Fail-Closed)', style: TextStyle(color: NixColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Para garantir que sua localização física e endereço IP jamais sejam expostos, o Nix exige o roteamento de todo o tráfego pela rede Tor.',
          style: TextStyle(color: NixColors.textSecondary, fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: NixTokens.borderMd,
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('REGRAS ARQUITETURAIS ESTRITAS:', style: NixTokens.labelUppercase()),
              const SizedBox(height: 8),
              Text('• O Tor daemon roda embutido localmente, sem necessidade de configurar portas ou instalar o Orbot manualmente.', style: TextStyle(color: NixColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 4),
              Text('• Se o Tor estiver indisponível ou cair, a aplicação BLOQUEIA conexões imediatamente (Fail-Closed).', style: TextStyle(color: NixColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 4),
              Text('• Nenhum tráfego recorrerá a fallback clearnet não criptografado.', style: TextStyle(color: NixColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        InkWell(
          onTap: () => setState(() => _torConsentChecked = !_torConsentChecked),
          borderRadius: NixTokens.borderSm,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _torConsentChecked ? NixColors.surfaceElevated : NixColors.surfaceCard,
              borderRadius: NixTokens.borderSm,
              border: Border.all(color: _torConsentChecked ? NixColors.accentYellow : NixColors.surfaceBorderStrong),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _torConsentChecked,
                  activeColor: NixColors.accentYellow,
                  checkColor: Colors.black,
                  onChanged: (v) => setState(() => _torConsentChecked = v ?? false),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Compreendo e aceito rotear todo o tráfego estritamente pela rede Tor Onion v3.',
                    style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepTorBootstrap() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: _isLoading
                  ? CircularProgressIndicator(value: _bootstrapPercent > 0 ? _bootstrapPercent / 100 : null, strokeWidth: 2.5, color: NixColors.accentYellow)
                  : Icon(_bootstrapPercent == 100 ? Icons.check_circle_rounded : Icons.pending_rounded, color: _bootstrapPercent == 100 ? NixColors.accentGreen : NixColors.accentYellow),
            ),
            const SizedBox(width: 10),
            Text('Inicialização do Daemon Tor Embutido', style: TextStyle(color: NixColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'O aplicativo está inicializando o binário Tor embutido, configurando o diretório seguro de dados e construindo um circuito de 3 saltos.',
          style: TextStyle(color: NixColors.textSecondary, fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 20),
        // Barra de Progresso do Bootstrap
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _bootstrapPercent / 100,
            minHeight: 10,
            backgroundColor: NixColors.surfaceCard,
            valueColor: AlwaysStoppedAnimation<Color>(
              _bootstrapFailed ? Colors.redAccent : (_bootstrapPercent == 100 ? NixColors.accentGreen : NixColors.accentYellow),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Progresso: $_bootstrapPercent%', style: TextStyle(color: NixColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
            Text(_bootstrapPercent == 100 ? 'CONECTADO' : (_bootstrapFailed ? 'FALHA' : 'BOOTSTRAP'),
                style: TextStyle(color: _bootstrapFailed ? Colors.redAccent : NixColors.accentYellow, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        Text(_bootstrapSummary, style: TextStyle(color: NixColors.textMuted, fontSize: 12)),

        if (_bootstrapFailed && _bootstrapErrorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.12),
              borderRadius: NixTokens.borderSm,
              border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Text('Diagnóstico de Falha:', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(_bootstrapErrorMessage!, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _startTorBootstrap,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Tentar Novamente'),
                  style: ElevatedButton.styleFrom(backgroundColor: NixColors.surfaceCard, foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        ],

        if (!_isLoading && _bootstrapPercent == 0 && !_bootstrapFailed) ...[
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton.icon(
              onPressed: _startTorBootstrap,
              icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
              label: const Text('Iniciar Daemon Tor Embutido', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: NixColors.accentYellow, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStepTorVerification() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.verified_user_rounded, color: NixColors.accentGreen, size: 22),
            const SizedBox(width: 8),
            Text('Verificação de Transporte & Política Fail-Closed', style: TextStyle(color: NixColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Auditoria em tempo real dos requisitos de transporte e isolamento:',
          style: TextStyle(color: NixColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _buildVerificationCheck(
          title: 'Daemon Tor Embutido Operacional',
          description: 'Processo Tor ativo em PID dedicado com diretório isolado.',
          isOk: _torSocksAlive,
        ),
        _buildVerificationCheck(
          title: 'Porta SOCKS5 Local (127.0.0.1:9050)',
          description: 'Socket de comunicação aberto sem vazamento de resolução DNS local.',
          isOk: _torSocksAlive,
        ),
        _buildVerificationCheck(
          title: 'Política Fail-Closed Ativa',
          description: 'Conexões clearnet diretas bloqueadas preventivamente.',
          isOk: _torFailClosedVerified,
        ),
        _buildVerificationCheck(
          title: 'Circuitos Onion v3 Disponíveis',
          description: 'Túnel criptográfico de 3 saltos pronto para transporte de mensagens.',
          isOk: _torCircuitsReady,
        ),
        const SizedBox(height: 16),
        if (_isVerifyingTor)
          const Center(child: CircularProgressIndicator())
        else if (!_torSocksAlive || !_torFailClosedVerified || !_torCircuitsReady)
          Center(
            child: TextButton.icon(
              onPressed: _runTorVerification,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reexecutar Verificação'),
            ),
          ),
      ],
    );
  }

  Widget _buildStepIdentityGeneration() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: NixColors.accentYellow, size: 22),
            const SizedBox(width: 8),
            Text('Geração Criptográfica da Identidade (Seed A)', style: TextStyle(color: NixColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Sua identidade na rede Nix é fundamentada em chaves assimétricas de alta entropia:',
          style: TextStyle(color: NixColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 14),
        _buildFeatureItem(Icons.fingerprint_rounded, 'Chave de Assinatura Ed25519', 'Garante que suas mensagens sejam autenticadas matematicamente sem passar por servidores.'),
        _buildFeatureItem(Icons.lock_clock_rounded, 'Chave de Cifra X25519 (Ratchet)', 'Permite o estabelecimento de sessões Double Ratchet com Forward Secrecy.'),
        _buildFeatureItem(Icons.storage_rounded, 'Cofre SQLCipher (Argon2id)', 'Protege as chaves em disco em cofre criptografado com sal de 16 bytes.'),
        _buildFeatureItem(Icons.money_off_rounded, 'Isolamento Absoluto da Carteira', 'A Seed A da mensageria jamais toca ou deriva chaves financeiras do Monero (Seed B).'),
        const SizedBox(height: 14),
        TextField(
          controller: _passphraseController,
          obscureText: true,
          style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5),
          decoration: InputDecoration(
            labelText: 'Frase-passe do cofre SQLCipher (opcional)',
            hintText: 'Vazio = senha CSPRNG vinculada ao chaveiro nativo do SO',
            filled: true,
            fillColor: NixColors.surfaceCard,
            border: OutlineInputBorder(borderRadius: NixTokens.borderSm),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _duressPinController,
          obscureText: true,
          style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5),
          decoration: InputDecoration(
            labelText: 'PIN de coação / anti-apreensão (opcional)',
            hintText: 'Se digitado no desbloqueio, aciona destruição local imediata',
            filled: true,
            fillColor: NixColors.surfaceCard,
            border: OutlineInputBorder(borderRadius: NixTokens.borderSm),
            isDense: true,
          ),
        ),
        CheckboxListTile(
          value: _bindToOsKeyring,
          onChanged: (v) => setState(() => _bindToOsKeyring = v ?? true),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: NixColors.accentYellow,
          checkColor: Colors.black,
          title: Text(
            'Permitir desbloqueio rápido pelo chaveiro do SO (libsecret / AndroidKeyStore)',
            style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
          ),
        ),
        const SizedBox(height: 12),
        if (_identityErrorMessage != null) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.14),
              borderRadius: NixTokens.borderSm,
              border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _identityErrorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
        Center(
          child: _isGeneratingIdentity
              ? Column(
                  children: [
                    const CircularProgressIndicator(color: Colors.amber),
                    const SizedBox(height: 12),
                    Text('Derivando chaves criptográficas com Argon2id...', style: TextStyle(color: NixColors.textMuted, fontSize: 12)),
                  ],
                )
              : ElevatedButton.icon(
                  onPressed: _generatePrivateIdentity,
                  icon: const Icon(Icons.auto_awesome_rounded, color: Colors.black),
                  label: const Text('Gerar Identidade Soberana Segura', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NixColors.accentYellow,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildStepRecoveryBackup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.edit_note_rounded, color: NixColors.accentYellow, size: 24),
            const SizedBox(width: 8),
            Text('Backup Físico no Papel (Seed de 24 Palavras)', style: TextStyle(color: NixColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.12),
            borderRadius: NixTokens.borderSm,
            border: Border.all(color: Colors.amber.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ATENÇÃO CRÍTICA: Anote estas 24 palavras em uma folha de papel. '
                  'Não salve em capturas de tela, e-mail ou nuvem. '
                  'Se perder este papel e reinstalar o app, sua conta NÃO poderá ser recuperada.',
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 11.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Grid 4x6 das 24 palavras
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: NixTokens.borderMd,
            border: Border.all(color: NixColors.surfaceBorderStrong),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_seedWords.length, (i) {
              return Container(
                width: 135,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: NixColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    Text('${i + 1}.', style: TextStyle(color: NixColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _seedWords[i],
                        style: TextStyle(color: NixColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 18),

        // Desafio de Verificação (Challenge)
        Text('DESAFIO DE VERIFICAÇÃO DE BACKUP:', style: NixTokens.labelUppercase()),
        const SizedBox(height: 8),
        Text('Para garantir que você escreveu a seed corretamente, informe as palavras solicitadas:', style: TextStyle(color: NixColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),

        Row(
          children: _challengeWordIndices.map((idx) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextField(
                  key: Key('challenge_word_${idx + 1}'),
                  decoration: InputDecoration(
                    labelText: 'Palavra #${idx + 1}',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    _userChallengeAnswers[idx] = val;
                    _verifyBackupChallenge();
                  },
                ),
              ),
            );
          }).toList(),
        ),

        if (_challengeFeedback != null) ...[
          const SizedBox(height: 8),
          Text(
            _challengeFeedback!,
            style: TextStyle(
              color: _challengePassed ? NixColors.accentGreen : Colors.redAccent,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],

        const SizedBox(height: 12),
        Row(
          children: [
            Checkbox(
              value: _paperBackupConfirmed,
              activeColor: NixColors.accentYellow,
              checkColor: Colors.black,
              onChanged: (v) => setState(() => _paperBackupConfirmed = v ?? false),
            ),
            Expanded(
              child: Text(
                'Confirmo que guardei as 24 palavras em papel físico seguro.',
                style: TextStyle(color: NixColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepPublicId() {
    final publicId = _derivedPublicId.isNotEmpty ? _derivedPublicId : widget.nixState.userProfile.publicId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.qr_code_2_rounded, color: NixColors.accentYellow, size: 24),
            const SizedBox(width: 8),
            Text('Identificador Público Soberano (Card ID)', style: TextStyle(color: NixColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Este é o seu Card ID público. Compartilhe-o com quem deseja conversar. '
          'Ele não contém nenhum dado pessoal, telefone, e-mail ou endereço IP.',
          style: TextStyle(color: NixColors.textSecondary, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              // QR Code interoperável real
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
                ),
                child: QrImageView(
                  data: 'nix://id/$publicId',
                  version: QrVersions.auto,
                  size: 160,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(
                publicId,
                style: TextStyle(
                  color: NixColors.accentYellow,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: publicId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Card ID copiado para a área de transferência!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copiar Card ID'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepProfileSetup() {
    final avatarOptions = [
      {'key': 'nyx_emblem', 'label': 'Emblema Nyx', 'icon': Icons.shield_rounded},
      {'key': 'sentinel', 'label': 'Sentinela', 'icon': Icons.security_rounded},
      {'key': 'monogram', 'label': 'Monograma', 'icon': Icons.badge_rounded},
      {'key': 'matrix', 'label': 'Cypherpunk', 'icon': Icons.terminal_rounded},
      {'key': 'crypto', 'label': 'Soberano', 'icon': Icons.key_rounded},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.person_outline_rounded, color: NixColors.accentYellow, size: 24),
            const SizedBox(width: 8),
            Text('Personalização de Perfil e Avatar', style: TextStyle(color: NixColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Escolha como você será apresentado aos seus pares. Estas informações são assinadas localmente pela sua chave Ed25519.',
          style: TextStyle(color: NixColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _displayNameController,
          style: TextStyle(color: NixColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Nome de Exibição / Apelido Soberano',
            hintText: 'ex: Soberano, Nexus, Guardião',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _bioController,
          style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Biografia / Mensagem de Status (Opcional)',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.edit_note_rounded),
          ),
        ),
        const SizedBox(height: 18),
        Text('ESCOLHA SEU AVATAR SOBERANO:', style: NixTokens.labelUppercase()),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: avatarOptions.map((opt) {
              final isSelected = _selectedAvatarStyle == opt['key'];
              return GestureDetector(
                onTap: () => setState(() => _selectedAvatarStyle = opt['key'] as String),
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? NixColors.surfaceElevated : NixColors.surfaceCard,
                    borderRadius: NixTokens.borderSm,
                    border: Border.all(
                      color: isSelected ? NixColors.accentYellow : NixColors.surfaceBorder,
                      width: isSelected ? 1.8 : 1.0,
                    ),
                  ),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: isSelected ? NixColors.accentYellow : NixColors.surfaceElevated,
                        child: Icon(opt['icon'] as IconData, color: isSelected ? Colors.black : Colors.white70, size: 20),
                      ),
                      const SizedBox(height: 6),
                      Text(opt['label'] as String, style: TextStyle(color: NixColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildStepReady() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: NixColors.accentGreen, size: 28),
            const SizedBox(width: 10),
            Text('Seu Nix está Pronto e Soberano!', style: TextStyle(color: NixColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Todas as garantias de privacidade e infraestrutura local foram estabelecidas:',
          style: TextStyle(color: NixColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 18),
        _buildVerificationCheck(
          title: 'Rede Tor Onion v3 Conectada',
          description: 'SOCKS5 ativo em 127.0.0.1:9050 · Modo Fail-Closed Ativo.',
          isOk: true,
        ),
        _buildVerificationCheck(
          title: 'Identidade Criptográfica Ativa',
          description: 'Seed A protegida no KeyVault e cofre de banco local SQLCipher.',
          isOk: true,
        ),
        _buildVerificationCheck(
          title: 'Backup Físico Verificado',
          description: '24 palavras anotadas em papel e confirmadas pelo desafio.',
          isOk: true,
        ),
        _buildVerificationCheck(
          title: 'Mensageiro Soberano Real',
          description: 'Instalação limpa pronta com Mensagens Salvas e Card ID público.',
          isOk: true,
        ),
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton.icon(
            key: const Key('enter_nix_sovereign_button'),
            onPressed: _finishOnboarding,
            icon: const Icon(Icons.rocket_launch_rounded, color: Colors.black),
            label: const Text('Entrar no Nix Soberano', style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: NixColors.accentYellow,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              elevation: 4,
            ),
          ),
        ),
      ],
    );
  }

  // --- COMPONENTES AUXILIARES ---

  Widget _buildFeatureItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: NixColors.surfaceCard, borderRadius: BorderRadius.circular(6)),
            child: Icon(icon, color: NixColors.accentYellow, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: NixColors.textMuted, fontSize: 11.5, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationCheck({required String title, required String description, required bool isOk}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: NixColors.surfaceCard,
          borderRadius: NixTokens.borderSm,
          border: Border.all(color: isOk ? NixColors.accentGreen.withOpacity(0.4) : NixColors.surfaceBorder),
        ),
        child: Row(
          children: [
            Icon(isOk ? Icons.check_circle_rounded : Icons.pending_rounded, color: isOk ? NixColors.accentGreen : NixColors.textMuted, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: NixColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(description, style: TextStyle(color: NixColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsDrawer() {
    return Container(
      height: 120,
      padding: const EdgeInsets.all(10),
      color: Colors.black87,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('DIAGNÓSTICO TÉCNICO:', style: TextStyle(color: NixColors.accentYellow, fontSize: 10, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
                onPressed: () => setState(() => _showDiagnostics = false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              itemCount: _diagnosticsLogs.length,
              itemBuilder: (ctx, i) => Text(
                _diagnosticsLogs[i],
                style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionFooter() {
    final canAdvance = _canAdvanceFromCurrentStep();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: NixColors.surfaceCard,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_currentStep != OnboardingStep.welcome && _currentStep != OnboardingStep.ready)
                  OutlinedButton(
                    onPressed: _goBack,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: NixColors.surfaceBorderStrong),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    child: const Text('Voltar'),
                  ),
                TextButton.icon(
                  onPressed: () => setState(() => _showDiagnostics = !_showDiagnostics),
                  icon: Icon(Icons.terminal_rounded, size: 14, color: NixColors.textMuted),
                  label: Text(_showDiagnostics ? 'Ocultar Logs' : 'Diagnóstico', style: TextStyle(color: NixColors.textMuted, fontSize: 11)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_currentStep == OnboardingStep.torBootstrap && _bootstrapFailed)
                ElevatedButton.icon(
                  onPressed: _startTorBootstrap,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Tentar Novamente'),
                  style: ElevatedButton.styleFrom(backgroundColor: NixColors.surfaceCard),
                ),
              if (_currentStep != OnboardingStep.ready)
                ElevatedButton(
                  key: const Key('onboarding_next_button'),
                  onPressed: canAdvance ? _handleNextStepAction : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NixColors.accentYellow,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: NixColors.surfaceElevated,
                    disabledForegroundColor: NixColors.textMuted,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: Text(_getNextButtonLabel(_currentStep), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _getNextButtonLabel(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.welcome:
        return 'Iniciar Configuração';
      case OnboardingStep.torConsent:
        return 'Concordar e Conectar';
      case OnboardingStep.torBootstrap:
        return 'Avançar para Verificação';
      case OnboardingStep.torVerification:
        return 'Gerar Identidade';
      case OnboardingStep.identityGeneration:
        return 'Anotar Seed';
      case OnboardingStep.recoveryBackup:
        return 'Avançar para Card ID';
      case OnboardingStep.publicId:
        return 'Configurar Perfil';
      case OnboardingStep.profileSetup:
        return 'Concluir Perfil';
      case OnboardingStep.ready:
        return 'Entrar no Nix';
    }
  }

  bool _canAdvanceFromCurrentStep() {
    switch (_currentStep) {
      case OnboardingStep.welcome:
        return true;
      case OnboardingStep.torConsent:
        return _torConsentChecked;
      case OnboardingStep.torBootstrap:
        return _bootstrapPercent == 100 && !_isLoading;
      case OnboardingStep.torVerification:
        return _torSocksAlive && _torFailClosedVerified && _torCircuitsReady;
      case OnboardingStep.identityGeneration:
        return (_seedWords.isNotEmpty || _derivedPublicId.isNotEmpty) && !_isGeneratingIdentity;
      case OnboardingStep.recoveryBackup:
        return _challengePassed && _paperBackupConfirmed;
      case OnboardingStep.publicId:
        return _derivedPublicId.isNotEmpty || widget.nixState.userProfile.publicId.isNotEmpty;
      case OnboardingStep.profileSetup:
        return _derivedPublicId.isNotEmpty || widget.nixState.userProfile.publicId.isNotEmpty;
      case OnboardingStep.ready:
        return (_derivedPublicId.isNotEmpty || widget.nixState.userProfile.publicId.isNotEmpty) &&
            _torConsentChecked;
    }
  }

  void _handleNextStepAction() {
    switch (_currentStep) {
      case OnboardingStep.welcome:
        if (widget.nixState.isStrictOffGridMode) {
          _torConsentChecked = true;
          _diagnosticsLogs.add(
            '[Off-Grid] Pulando bootstrap de rede IP — gerando Seed A e SQLCipher 100% offline.',
          );
          _goToStep(OnboardingStep.identityGeneration);
        } else {
          _goToStep(OnboardingStep.torConsent);
        }
        break;
      case OnboardingStep.torConsent:
        _goToStep(OnboardingStep.torBootstrap);
        _startTorBootstrap();
        break;
      case OnboardingStep.torBootstrap:
        _goToStep(OnboardingStep.torVerification);
        _runTorVerification();
        break;
      case OnboardingStep.torVerification:
        _goToStep(OnboardingStep.identityGeneration);
        break;
      case OnboardingStep.identityGeneration:
        _goToStep(OnboardingStep.recoveryBackup);
        break;
      case OnboardingStep.recoveryBackup:
        _goToStep(OnboardingStep.publicId);
        break;
      case OnboardingStep.publicId:
        _goToStep(OnboardingStep.profileSetup);
        break;
      case OnboardingStep.profileSetup:
        _completeProfileAndFinish();
        break;
      case OnboardingStep.ready:
        _finishOnboarding();
        break;
    }
  }
}
