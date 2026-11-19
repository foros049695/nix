# Cliente Nix (`nix_client`)

Aplicação cliente *local-first* multiplataforma (Flutter) do **Projeto Nix** (em estágio *pre-alpha*), responsável pela mensageria cifrada de ponta a ponta, cofre local SQLCipher, onboarding soberano, Nix Archive, catálogo local de mídia/Starwire e mural Monero P2P com isolamento estrito de chaves.

O pacote consome localmente [`modules/core_crypto`](../../modules/core_crypto) e [`modules/transport`](../../modules/transport) via dependências `path` em [`pubspec.yaml`](pubspec.yaml).

---

## Como obter dependências, analisar e executar (Linux)

Execute todos os comandos abaixo a partir deste diretório (`apps/nix_client`):

```bash
# 1. Resolver dependências (incluindo os módulos locais do monorepo)
flutter pub get

# 2. Análise estática (política usada pelo CI em .github/workflows/ci.yml;
#    `flutter analyze` sem flags trata diagnósticos informativos como fatais)
flutter analyze --no-fatal-infos

# 3. Executar o cliente desktop no Linux
flutter run -d linux
```

---

## Como executar os testes com segurança

> **Recomendação (`HOME` isolado):** por precaução — já que os caminhos padrão do cliente em execução normal apontam para `~/.local/share/nix` ([`lib/core/security/platform_runtime.dart`](lib/core/security/platform_runtime.dart) e [`lib/core/security/anti_forensic_shredder.dart`](lib/core/security/anti_forensic_shredder.dart)) — execute `flutter test` sempre com um diretório `HOME` temporário isolado e evite ambientes com um daemon Tor real ouvindo em `127.0.0.1:9050`.

```bash
# Suíte completa com HOME isolado
TMP_HOME="$(mktemp -d)"
HOME="$TMP_HOME" flutter test
rm -rf "$TMP_HOME"

# Executar um único teste pelo nome
TMP_HOME="$(mktemp -d)"
HOME="$TMP_HOME" flutter test test/widget_test.dart --plain-name "<subtexto>"
rm -rf "$TMP_HOME"
```

Para validar também o portão estático de privacidade na raiz do repositório:

```bash
../../scripts/verify_privacy_matrix.sh
```

---

## Onde ficam os dados locais

A resolução de caminhos é centralizada em `NixPlatformPaths` ([`lib/core/security/platform_runtime.dart`](lib/core/security/platform_runtime.dart)):

- **Linux / Desktop POSIX:** `$HOME/.local/share/nix/` (ou `.nix_data` / `.<arquivo>` caso `HOME` não esteja definido).
- **Android:** `<filesDir>/nix_data/` (ex.: `/data/user/0/com.projetonix.nix_client/files/nix_data`).

Principais arquivos e diretórios gerenciados sob essa base:

| Caminho relativo | Papel | Origem no código |
|---|---|---|
| `vault_bootstrap.json` | Chave mestra encapsulada via Argon2id + XChaCha20-Poly1305 e metadados do cofre | [`lib/core/security/key_vault.dart`](lib/core/security/key_vault.dart) |
| `nix_local_v4.db` (`-wal`, `-shm`) | Banco de dados local cifrado via SQLCipher | [`lib/core/database/local_database.dart`](lib/core/database/local_database.dart) |
| `client_prefs_v4.json` | Preferências visuais e de interface em JSON (ignorado quando `FLUTTER_TEST=true`) | [`lib/state/nix_state.dart`](lib/state/nix_state.dart) |
| `onboarding_state.json` | Estado persistido do fluxo de onboarding em 9 etapas | [`lib/features/onboarding/sovereign_onboarding_model.dart`](lib/features/onboarding/sovereign_onboarding_model.dart) |
| `encrypted_objects/` | Anexos locais cifrados | [`lib/core/messaging/sovereign_messenger.dart`](lib/core/messaging/sovereign_messenger.dart) |
| `sanitized_media/` | Imagens locais após remoção de metadados | [`lib/core/security/local_image_helper.dart`](lib/core/security/local_image_helper.dart) |
| `tor_data/` | Diretório de dados do processo Tor embutido | [`../../modules/transport/lib/nix_embedded_tor.dart`](../../modules/transport/lib/nix_embedded_tor.dart) e [`lib/state/nix_state.dart`](lib/state/nix_state.dart) |
| `downloads/` | Pacotes ZIP baixados do catálogo Starwire | [`lib/features/discovery/github_discovery_view.dart`](lib/features/discovery/github_discovery_view.dart) |

---

## Diretrizes do Projeto

Antes de alterar código, adicionar dependências ou abrir um Pull Request, leia:

- [`AGENTS.md`](../../AGENTS.md) — arquitetura do monorepo, invariantes de segurança e segurança na execução de testes.
- [`CONTRIBUTING.md`](../../CONTRIBUTING.md) — princípios não-negociáveis (zero telemetria, *fail-closed*, isolamento Seed A / Seed B, exigência de ADR para novas dependências) e checklist de PR.
- [`SECURITY.md`](../../SECURITY.md) — modelo de ameaças e canal privado de divulgação responsável de vulnerabilidades.
- [`ROADMAP.md`](../../ROADMAP.md) — estado atual das fases e critérios de aceite (*gates*).
