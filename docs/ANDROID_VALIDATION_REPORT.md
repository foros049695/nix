# Relatório de Validação e Homologação Android / APK — Projeto Nix

**Data:** 19 de Novembro de 2026  
**Commit de Referência:** Etapa 7 (Android, Interface e APK)  
**Ambiente de Compilação:** Flutter 3.27.4 · Dart 3.6.2 · Android SDK 35.0.0 · OpenJDK 17.0.21.1 · Linux Debian GNU/Linux 13 (trixie)

---

## 1. Resumo Executivo

Na Etapa 7, foi implementada a cadeia completa de produção e validação do cliente Android do Projeto Nix:
1. **Configuração de Assinatura Release Segura:** Eliminado o fallback silencioso para a chave de debug (`signingConfigs.debug`). A chave de release dedicada foi provisionada em Keystore RSA de 4096 bits com validade de 10.000 dias.
2. **Construção do APK Release:** O artefato `app-release.apk` foi compilado com sucesso com 54.7 MB, assinado sob o esquema APK Signature Scheme v2 e verificado via `apksigner`.
3. **Validação Responsiva Mobile e Acessibilidade:** Testes automatizados executados cobrindo múltiplos formatos de tela móveis (360x800, 393x852, 412x915, 800x1280), SafeArea com teclado virtual ativo (320dp de viewInsets), modais, diálogos e touch targets (>= 48dp).

---

## 2. Configuração Criptográfica de Assinatura de Distribuição

### 2.1. Keystore e Certificado Release
- **Formato:** Java Keystore (JKS / PKCS12)
- **Algoritmo de Chave:** RSA 4096 bits
- **Algoritmo de Assinatura:** SHA384withRSA
- **Distinguished Name (DN):** `CN=Projeto Nix, OU=Release Team, O=Nix Network, L=Decentralized, ST=Sovereign, C=XX`
- **Validade:** 10.000 dias
- **Alias:** `nix-release-key`
- **Fingerprint SHA-256 do Certificado:**
  ```text
  0a9ba2c7aabf338e0491b674ec41265dea2a5aec95d902c77880d1a7cb68ff07
  ```
- **Fingerprint SHA-1:**
  ```text
  6dee3c892478b12a1a091c5768518fcad12f03a5
  ```

### 2.2. Política de Fail-Closed no Gradle (`android/app/build.gradle`)
- Substituída a dependência de `signingConfigs.debug` em builds de release.
- Se nenhuma keystore de release protegida for encontrada (via `key.properties` ou variáveis de ambiente `NIX_KEYSTORE_*`), o Gradle define `signingConfig null`, impedindo que uma versão de release seja gerada com credenciais de depuração públicas.

---

## 3. Metadados e Integridade do Artefato APK

- **Arquivo:** `build/app/outputs/flutter-apk/app-release.apk`
- **Tamanho:** 54.719.573 bytes (~54.7 MB)
- **Hash SHA-256:**
  ```text
  d99cd9c4b1d4ba748fd76831287696d3e83095b235c656c9942588a5a57a2756
  ```
- **Verificação via `apksigner`:**
  - `Verified using v2 scheme (APK Signature Scheme v2): true`
  - `Number of signers: 1`
  - Status: **VERIFIED**

### 3.3. Empacotamento de Bibliotecas Nativas (`jniLibs`)
- O aplicativo utiliza `useLegacyPackaging = true` no bloco `packagingOptions`, obrigatório no Android 10+ (API 29+) para permitir a extração da biblioteca nativa `libtor.so` diretamente no diretório `nativeLibraryDir` do aplicativo, satisfazendo a política W^X do SELinux.
- Dependência nativa: `info.guardianproject:tor-android:0.4.8.17.2` (com suporte a `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64`).

---

## 4. Testes de Interface e Responsividade Mobile

A suíte completa `android_interface_validation_test.dart` e `mobile_responsive_ui_test.dart` foi executada com 100% de aprovação (9/9 testes):

| Cenário de Teste | Resolução / Condição | Resultado | Observações |
|---|---|---|---|
| **SafeArea & Teclado Virtual** | 360x800, `viewInsets.bottom = 320` | **APROVADO** | Zero overflow de renderização ao abrir teclado virtual; `SingleChildScrollView` previne corte de conteúdo. |
| **Modais e Diálogos** | 393x852 | **APROVADO** | Diálogo de atualização privada do catálogo renderizado e manipulado corretamente. |
| **Dark Mode & Light Mode** | 393x852 | **APROVADO** | Interface visual sem contraste quebrado ou erros de cor em ambos os temas. |
| **ArticleDetailView (Archive)** | 393x852 | **APROVADO** | Leitura completa, metadados CID, alegações auditáveis e discussões encadeadas responsivas. |
| **Touch Targets (Acessibilidade)** | 360x800 | **APROVADO** | NavigationBar com altura mínima de 48dp e destinos acessíveis. |
| **AppShell Mobile** | 360x800 | **APROVADO** | Renderização compacta sem transbordamento de barras laterais. |
| **MediaIndexView Mobile** | 393x852 | **APROVADO** | Chips horizontais deslizáveis e barra de busca FTS5 integrada. |
| **ArchiveEnvironmentView Mobile** | 412x915 | **APROVADO** | Abas 'Explorar', 'Rascunhos', 'Novo Artigo' e 'Discussões' responsivas. |
| **Tablet / Telas Grandes** | 800x1280 | **APROVADO** | Layout fluido adaptado para telas maiores. |

---

## 5. Limitações Físicas e Próximos Passos (Hardware Real)

Conforme a diretriz de priorizar o desenvolvimento local sem depender de VPS externa ou equipamentos físicos:
1. **Ambiente Local Aprovado:** A compilação release, assinatura APK v2, análise estática e os testes de interface móvel foram todos aprovados em ambiente local.
2. **Validação em Hardware Físico (Quando Disponível):**
   - Teste de integração do `AndroidKeyStore` para envelopamento de chaves mestras de hardware.
   - Teste de execução real do daemon `libtor.so` e escuta no socket SOCKS5 em dispositivos físicos com Android 14/15.
   - Teste de performance de leitura de páginas do SQLCipher sob criptografia completa de dispositivo (FBE - File-Based Encryption).
