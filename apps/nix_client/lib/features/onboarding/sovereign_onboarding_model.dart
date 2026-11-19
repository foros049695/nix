import 'dart:convert';
import 'dart:io';

/// Estados explícitos da máquina de estados do Onboarding Soberano (Seção 2).
enum OnboardingStep {
  welcome,             // Boas-vindas e introdução à arquitetura soberana
  torConsent,          // Consentimento explícito da rede Tor (Fail-Closed)
  torBootstrap,        // Inicialização e bootstrap do daemon Tor embutido (0 a 100%)
  torVerification,     // Verificação real de conectividade SOCKS5 e bloqueio de clearnet
  identityGeneration,  // Geração criptográfica segura da Seed A (Ed25519/X25519/SQLCipher)
  recoveryBackup,      // Exibição e desafio de verificação da Seed de 24 palavras no papel
  publicId,            // Derivação do Card ID público e QR Code interoperável
  profileSetup,        // Configuração de nome de exibição e avatar soberano sincronizado
  ready,               // Confirmação final e transição para o mensageiro operacional real
}

/// Estado persistente e transacional do fluxo de onboarding para resistir a quedas e reinicializações.
class OnboardingStateSnapshot {
  final OnboardingStep currentStep;
  final bool torConsentAccepted;
  final bool torBootstrapped;
  final bool torVerified;
  final bool identityGenerated;
  final bool backupConfirmed;
  final bool publicIdDerived;
  final bool profileConfigured;
  final bool isCompleted;
  final String? publicId;
  final String? displayName;
  final String? avatarStyle;

  const OnboardingStateSnapshot({
    this.currentStep = OnboardingStep.welcome,
    this.torConsentAccepted = false,
    this.torBootstrapped = false,
    this.torVerified = false,
    this.identityGenerated = false,
    this.backupConfirmed = false,
    this.publicIdDerived = false,
    this.profileConfigured = false,
    this.isCompleted = false,
    this.publicId,
    this.displayName,
    this.avatarStyle,
  });

  OnboardingStateSnapshot copyWith({
    OnboardingStep? currentStep,
    bool? torConsentAccepted,
    bool? torBootstrapped,
    bool? torVerified,
    bool? identityGenerated,
    bool? backupConfirmed,
    bool? publicIdDerived,
    bool? profileConfigured,
    bool? isCompleted,
    String? publicId,
    String? displayName,
    String? avatarStyle,
  }) {
    return OnboardingStateSnapshot(
      currentStep: currentStep ?? this.currentStep,
      torConsentAccepted: torConsentAccepted ?? this.torConsentAccepted,
      torBootstrapped: torBootstrapped ?? this.torBootstrapped,
      torVerified: torVerified ?? this.torVerified,
      identityGenerated: identityGenerated ?? this.identityGenerated,
      backupConfirmed: backupConfirmed ?? this.backupConfirmed,
      publicIdDerived: publicIdDerived ?? this.publicIdDerived,
      profileConfigured: profileConfigured ?? this.profileConfigured,
      isCompleted: isCompleted ?? this.isCompleted,
      publicId: publicId ?? this.publicId,
      displayName: displayName ?? this.displayName,
      avatarStyle: avatarStyle ?? this.avatarStyle,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'currentStep': currentStep.name,
      'torConsentAccepted': torConsentAccepted,
      'torBootstrapped': torBootstrapped,
      'torVerified': torVerified,
      'identityGenerated': identityGenerated,
      'backupConfirmed': backupConfirmed,
      'publicIdDerived': publicIdDerived,
      'profileConfigured': profileConfigured,
      'isCompleted': isCompleted,
      'publicId': publicId,
      'displayName': displayName,
      'avatarStyle': avatarStyle,
      // INVARIANTE CRÍTICO: A seed (Seed A) NUNCA é serializada ou salva em disco em claro!
    };
  }

  factory OnboardingStateSnapshot.fromJson(Map<String, dynamic> json) {
    OnboardingStep step = OnboardingStep.welcome;
    if (json['currentStep'] != null) {
      step = OnboardingStep.values.firstWhere(
        (s) => s.name == json['currentStep'],
        orElse: () => OnboardingStep.welcome,
      );
    }
    return OnboardingStateSnapshot(
      currentStep: step,
      torConsentAccepted: json['torConsentAccepted'] as bool? ?? false,
      torBootstrapped: json['torBootstrapped'] as bool? ?? false,
      torVerified: json['torVerified'] as bool? ?? false,
      identityGenerated: json['identityGenerated'] as bool? ?? false,
      backupConfirmed: json['backupConfirmed'] as bool? ?? false,
      publicIdDerived: json['publicIdDerived'] as bool? ?? false,
      profileConfigured: json['profileConfigured'] as bool? ?? false,
      isCompleted: json['isCompleted'] as bool? ?? false,
      publicId: json['publicId'] as String?,
      displayName: json['displayName'] as String?,
      avatarStyle: json['avatarStyle'] as String?,
    );
  }

  static String getPersistencePath({String? customPath}) {
    if (customPath != null) return customPath;
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return '${Directory.systemTemp.path}/nix_test_onboarding_state.json';
    }
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return '.nix_onboarding_state.json';
    return '$home/.local/share/nix/onboarding_state.json';
  }

  /// Salva o estado de forma atômica no arquivo de estado transacional.
  static Future<void> save(OnboardingStateSnapshot snapshot, {String? customPath}) async {
    final path = getPersistencePath(customPath: customPath);
    final file = File(path);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    file.writeAsStringSync(jsonEncode(snapshot.toJson()), flush: true);
  }

  /// Carrega o estado salvo ou retorna estado inicial se não existir.
  static Future<OnboardingStateSnapshot> load({String? customPath}) async {
    final path = getPersistencePath(customPath: customPath);
    final file = File(path);
    if (!file.existsSync()) {
      return const OnboardingStateSnapshot();
    }
    try {
      final content = file.readAsStringSync();
      final map = jsonDecode(content) as Map<String, dynamic>;
      return OnboardingStateSnapshot.fromJson(map);
    } catch (_) {
      return const OnboardingStateSnapshot();
    }
  }

  /// Apaga o arquivo de onboarding em caso de reset anti-forense.
  static Future<void> delete({String? customPath}) async {
    final path = getPersistencePath(customPath: customPath);
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}
