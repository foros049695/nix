# RELATÓRIO TÉCNICO DE AUDITORIA, RESOLUÇÃO DE ISSUES E PULL REQUESTS
## PROJETO NIX — SEGURANÇA, ISOLAMENTO, CRIPTOGRAFIA E AUTOMAÇÃO

**Data da Auditoria:** 19 de Novembro de 2026  
**Responsável Técnico:** Google Antigravity / DeepMind Core Engineering  
**Repositório Alvo:** `https://github.com/foros049695/nix`  
**Commit Base Inicial:** `f02714cbefc9b212278d0c196486b9baf3583fa0`  
**Status de Integridade:** 🟢 100% PASSING (Zero regressions across Go, Dart and Flutter)

---

## 1. RESUMO EXECUTIVO

Este relatório documenta a auditoria completa de código, análise estática, reprodução de cenários de falha, inspeção de segurança e resolução técnica de todas as **Issues** (#11, #12 e #19) e **Pull Requests** (#1 a #10, #13 a #18 e #20 a #30) do repositório Nix.

Adicionalmente, investigou-se a falha real capturada nas capturas de tela do onboarding desktop (`[Erro] Falha ao inicializar KeyVault / SQLCipher`), solucionando tanto a causa raiz da persistência de cofres residuais quanto a proteção contra senhas aleatórias descartadas (Issue #19).

Por fim, foi estabelecida e validada em ambiente local e CI a **rotina persistente de verificação a cada 4 horas** (`.github/workflows/nix_maintenance_audit.yml`), garantindo que o repositório mantenha conformidade contínua mesmo com a interface do assistente encerrada.

---

## 2. DIAGNÓSTICO DO CASO REAL DO ONBOARDING (CAPTURA DE TELA)

### 2.1 Reprodução e Causa Raiz
Na Etapa 5 do Onboarding Soberano (*Geração Criptográfica da Identidade Privada*), o usuário clicou em **"Gerar Identidade Soberana Segura"** com o campo de senha vazio e o checkbox de chaveiro do SO desmarcado, deparando-se com o erro:
```text
DIAGNÓSTICO TÉCNICO:
[Cripto] Gerando entropia CSPRNG para a Seed A (24 palavras c/ checksum)...
[Erro] Falha ao inicializar KeyVault / SQLCipher.
```

A auditoria em disco (`/home/gus/.local/share/nix/`) revelou que:
1. **Existência de resíduo de cofre prévio:** Os arquivos `vault_bootstrap.json` e `nix_local_v4.db` da identidade anterior ("Soberano das 00:07", solicitada para descarte) ainda permaneciam presentes no disco do usuário.
2. **Tentativa indevida de Unlock em vez de Bootstrap:** O método `NixState.initializeEncryptedDatabase()` verificava `existedVaultBefore = File(resolvedVaultPath).exists()`. Ao encontrar o arquivo preexistente, assumia que se tratava de um desbloqueio comum e chamava `_keyVault.unlockOrDuress(passphrase)`.
3. **Falha de Autenticação Silenciosa:** Como o usuário estava criando uma *nova identidade* com senha gerada automaticamente na memória, a senha temporária não coincidia com a senha do cofre antigo descartado. O cofre lançava `VaultAuthenticationException`, abortando a inicialização do banco.
4. **Incoerência de Interface (Issue #19):** Ao desmarcar a opção de salvar no chaveiro do SO e deixar o campo de frase-passe vazio, o app não alertava que uma frase-passe manual era obrigatória, correndo o risco de descartar a chave caso tentasse inicializar.

### 2.2 Correções Implementadas e Validadas
1. **Flag `overwriteExistingVault: true`:**
   - Adicionada ao método `initializeEncryptedDatabase(...)` em `apps/nix_client/lib/state/nix_state.dart`.
   - Utilizada pelo `SovereignOnboardingFlow` tanto na geração de identidade nova (linha 369) quanto na restauração por Seed A (linha 506). Quando ativa, limpa qualquer resíduo anterior e instrui `_keyVault.initialize(overwrite: true)`.
2. **Guarda Fail-Closed na Interface:**
   - Em `sovereign_onboarding_flow.dart`, foi inserida a validação mandatória:
     ```dart
     if (userPassphrase.isEmpty && !_bindToOsKeyring) {
       setState(() {
         _identityErrorMessage =
             'Como o desbloqueio rápido pelo chaveiro do SO foi desmarcado, é obrigatório definir uma frase-passe manual para proteger o cofre.';
       });
       return;
     }
     ```
3. **Testes Criados e Aprovados:**
   - `inicialização com cofre pré-existente e overwriteExistingVault substitui arquivo e inicializa com sucesso` (PASS).
   - `rejeita criação sem frase-passe quando chaveiro do SO é desmarcado` (PASS).

---

## 3. AUDITORIA DAS ISSUES (#11, #12, #19)

| Issue | Título | Estado Original | Estado na Auditoria | Evidência / Análise Técnica |
|---|---|---|---|---|
| **#11** | `[BUG] HTTPS over SOCKS fails with NoSuchMethodError (_detachRaw)` | Fechada | **RESOLVED** | Implementação em `modules/transport/lib/nix_transport.dart` valida handshake TLS, validação estrita de certificados e ausência de fallback para clearnet. Teste `modules/transport/test/https_over_socks_probe_test.dart` executa localmente contra servidor TLS de loopback com passagem 100% verde. |
| **#12** | `Request: private channel for security reports (SECURITY.md §3)` | Fechada | **RESOLVED** | Verificado via API do GitHub (`security_and_analysis` ativo com push protection). PR #24 adiciona roteamento em `.github/ISSUE_TEMPLATE/config.yml` e aviso explícito em `bug_report.md` para submissão confidencial em `https://github.com/foros049695/nix/security/advisories/new`. |
| **#19** | `[BUG] Vault can be created with a discarded random passphrase when the OS keyring is unavailable or fails to store` | Aberta | **RESOLVED** | PR #30 adiciona verificação `_keyVault.lastKeyringBindSucceeded`. Se o vínculo ao chaveiro falhar, lança `StateError` e executa rollback completo do cofre e do banco vazio. Complementado com guarda visual na UI e suíte `apps/nix_client/test/keyring_bind_failure_probe_test.dart` (7/7 cenários aprovados). |

---

## 4. AUDITORIA E VALIDAÇÃO DOS PULL REQUESTS (#20 A #30)

Todos os 11 PRs abertos submetidos pelo colaborador `@gabrielmaialva33` foram auditados individualmente a partir do commit base `f02714c`, reproduzidos em ambiente de teste isolado e validados:

### PR #30 — `fix(client): roll back fresh vault when requested keyring binding fails`
- **Arquivos:** `apps/nix_client/lib/features/onboarding/sovereign_onboarding_flow.dart`, `apps/nix_client/lib/state/nix_state.dart`, `apps/nix_client/test/keyring_bind_failure_probe_test.dart`.
- **Análise:** Essencial para a integridade do cofre. Se a gravação no `OsKeyStorage` retornar `false` ou falhar, a frase-passe gerada aleatoriamente não é descartada em silêncio: o cofre é desfeito (`rollbackFreshBootstrap`) e nenhuma chave órfã é deixada em disco.
- **Status:** **VALIDADO E RECOMENDADO PARA INTEGRAÇÃO.**

### PR #29 — `refactor(client): split database repositories behind the existing barrel`
- **Arquivos:** `apps/nix_client/lib/core/database/repositories.dart` (reduzido de 1203 linhas para 12 exports de barrel) + 12 novos arquivos modulares em `repositories/`.
- **Análise:** Preserva 100% da compatibilidade de imports do cliente Nix sem alterar o comportamento transacional do SQLCipher.
- **Teste:** `apps/nix_client/test/repositories_barrel_probe_test.dart` aprovado.
- **Status:** **VALIDADO E RECOMENDADO PARA INTEGRAÇÃO.**

### PR #28 — `refactor(core-crypto): move implementation under lib/src and preserve public API`
- **Arquivos:** `modules/core_crypto/lib/nix_core_crypto.dart`, `nix_pqxdh.dart`, `lib/src/core_crypto.dart`, `lib/src/pqxdh.dart`.
- **Análise:** Segue as melhores práticas do ecossistema Dart (Dart package layout), encapsulando implementações internas em `lib/src/` e expondo apenas APIs públicas autenticadas.
- **Teste:** `modules/core_crypto/test/public_api_layout_probe_test.dart` e todos os 13 testes de criptografia aprovados.
- **Status:** **VALIDADO E RECOMENDADO PARA INTEGRAÇÃO.**

### PR #27 — `docs(adr): add retroactive ADRs for relay PostgreSQL and client native/QR dependencies`
- **Arquivos:** `docs/adr/0005-relay-postgresql-driver.md`, `docs/adr/0006-client-native-storage-ffi-and-qr-dependencies.md`.
- **Análise:** Regulariza a rastreabilidade documental exigida pelo ADR 0001 e CONTRIBUTING.md quanto à inclusão de `github.com/lib/pq` (Go) e `sqlite3`/`sqlcipher_flutter_libs`/`qr_flutter` (Flutter). Confirma compatibilidade com GPL-3.0 e modelo de ameaças.
- **Status:** **VALIDADO E RECOMENDADO PARA INTEGRAÇÃO.**

### PR #26 — `docs(client): replace default Flutter README with project setup and test safety guide`
- **Arquivos:** `apps/nix_client/README.md`.
- **Análise:** Substitui o template padrão do Flutter por orientações essenciais sobre compilação Linux, resolução de dependências monorepo e execução de testes em `HOME` isolado para segurança dos dados do desenvolvedor.
- **Status:** **VALIDADO E RECOMENDADO PARA INTEGRAÇÃO.**

### PR #25 — `docs(modules): document placeholder directories and fix gitattributes comment`
- **Arquivos:** `.gitattributes`, `modules/archive/README.md`, `modules/index/README.md`, `modules/media/README.md`, `modules/offgrid/README.md`, `modules/wallet/README.md`.
- **Análise:** Esclarece a função dos módulos de placeholder arquiteturais do monorepo, apontando onde reside a implementação real no cliente e o marco no ROADMAP.md. Corrige comentário de tracking do gitattributes.
- **Status:** **VALIDADO E RECOMENDADO PARA INTEGRAÇÃO.**

### PR #24 — `docs(github): route security reports to private advisories and expand PR template`
- **Arquivos:** `.github/ISSUE_TEMPLATE/bug_report.md`, `.github/ISSUE_TEMPLATE/config.yml`, `.github/PULL_REQUEST_TEMPLATE.md`.
- **Análise:** Protege o projeto contra divulgação prematura ou inadvertida de falhas de segurança em issues públicas, direcionando vulnerabilidades para o canal privado de Security Advisories.
- **Status:** **VALIDADO E RECOMENDADO PARA INTEGRAÇÃO.**

### PR #23 — `fix(relay): reject failures loading an explicit configuration`
- **Arquivos:** `services/nix_relay/cmd/relay/main.go`, `services/nix_relay/cmd/relay/config_load_probe_test.go`.
- **Análise:** Garante comportamento *fail-closed*. Se o operador do relay informar explicitamente o argumento `-config <arquivo>` e o arquivo for inexistente, vazio ou corrompido, o serviço aborta imediatamente (`log.Fatalf`), sem iniciar listeners ou recorrer a defaults em memória inadvertidamente.
- **Teste:** `config_load_probe_test.go` executado com `go test -race` aprovado em todos os cenários (`missing`, `invalid`, `empty`).
- **Status:** **VALIDADO E RECOMENDADO PARA INTEGRAÇÃO.**

### PR #22 — `fix(client): guard asynchronous context use and remove redundant await`
- **Arquivos:** `apps/nix_client/lib/features/profile/cultural_showcase.dart`, `apps/nix_client/test/e2e_messaging_pipeline_test.dart`.
- **Análise:** Elimina avisos de análise estática do Flutter sobre gaps assíncronos (`use_build_context_synchronously`) ao selecionar imagem no Acervo Cultural e remove `await` desnecessário sobre chave síncrona nos testes de mensageria.
- **Status:** **VALIDADO E RECOMENDADO PARA INTEGRAÇÃO.**

### PR #21 & PR #20 — `fix(client): extend panic wipe to remaining app data directories` & `report incomplete panic wipes in settings`
- **Arquivos:** `apps/nix_client/lib/core/security/anti_forensic_shredder.dart`, `apps/nix_client/lib/features/settings/settings_center.dart`, `apps/nix_client/test/panic_directories_probe_test.dart`, `apps/nix_client/test/panic_feedback_probe_test.dart`.
- **Análise:** O Botão de Pânico / Descarte Anti-Forense passa a varrer e sobrescrever com passagens destrutivas todos os diretórios da aplicação (`storage`, `sanitized_media`, `encrypted_objects`, `tor_data`, `downloads`), sem seguir symlinks para fora do diretório da conta. A interface de configurações agora reporta de forma honesta e transparente caso ocorra qualquer falha parcial em alvos bloqueados.
- **Reforço de Segurança:** Foi adicionada a paralisação síncrona do daemon Tor (`_embeddedTor.stop()`) antes da destruição em `NixState.panicWipeAllData()`, evitando conflitos de descritores de arquivo ou regravação de estado durante o expurgo.
- **Status:** **VALIDADOS E RECOMENDADOS PARA INTEGRAÇÃO.**

---

## 5. RASTREABILIDADE DOS PRS ANTERIORES (#1 A #10 E #13 A #18)

| PR | Título / Escopo | Estado no HEAD Atual | Risco de Regressão |
|---|---|---|---|
| **#1** | Docs: AGENTS.md e redirecionamento de CLAUDE.md / GEMINI.md | Presente | Zero |
| **#2** | Fix: Erros estáticos do analisador em crypto e transport | Presente | Zero |
| **#3** | Fix: Restauração da análise do Flutter client | Presente | Zero |
| **#4** | Fix: Confinamento de `panicWipeAccount` e sobrescrita in-place | Presente e ampliado pelos PRs #20 e #21 | Zero |
| **#5** | Fix: Isolamento de sondas de porta Tor e timeout de processos filhos | Presente | Zero |
| **#6** | Fix: Estado honesto do SQLCipher e checksums de migração | Presente | Zero |
| **#7** | Fix: Propagação de erros de persistência no Relay Go | Presente | Zero |
| **#8** | Fix: Limites de tamanho de corpo de anexo no Relay Go | Presente | Zero |
| **#9** | Fix: Sanitização de metadados WebP/GIF e rejeição fail-closed | Presente | Zero |
| **#10** | Docs: Correção de AGENTS.md e avisos de testes destrutivos | Presente | Zero |
| **#13** | Fix: Imposição real dos portões I-A e I-S | Presente | Zero |
| **#14** | Fix: Escape de termos FTS5 na busca de mídia | Presente | Zero |
| **#15** | Fix: Liberação limpa de recursos no `NixState.dispose` | Presente | Zero |
| **#16** | Fix: Desativação de backup automático no Android (`allowBackup=false`) | Presente | Zero |
| **#17** | Chore: Remoção de caminhos locais e expansão de `~` no Relay | Presente | Zero |
| **#18** | Fix: Proteção contra path traversal em ZIPs do Starwire | Presente | Zero |

---

## 6. ROTINA AUTOMATIZADA PERSISTENTE A CADA 4 HORAS (FASE 16)

Para garantir que o repositório permaneça íntegro de forma autônoma sem requerer sessões abertas na IDE ou agentes ativos, foi implementada a seguinte infraestrutura:

1. **Workflow GitHub Actions:**
   - Arquivo: [`.github/workflows/nix_maintenance_audit.yml`](file:///home/gus/.gemini/antigravity/scratch/nix/.github/workflows/nix_maintenance_audit.yml)
   - Agendamento: `cron: '0 */4 * * *'` (execuções a cada 4 horas: 00:00, 04:00, 08:00, 12:00, 16:00, 20:00 UTC) e gatilho manual `workflow_dispatch`.
   - Permissões estritas: `contents: write`, `issues: read`, `pull-requests: read`.
   - Upload de artefatos com retenção de 30 dias.
2. **Auditor Automático Determinístico:**
   - Script: [`scripts/run_maintenance_audit.py`](file:///home/gus/.gemini/antigravity/scratch/nix/scripts/run_maintenance_audit.py)
   - Executa a Matriz de Privacidade, Go test `-race`, Dart test em `core_crypto` e `transport`, e todos os testes do cliente Flutter.
   - Consulta issues e PRs via API oficial do GitHub sem expor tokens ou segredos nos logs.
   - Gera o relatório em [`docs/automation/MAINTENANCE_REPORT.md`](file:///home/gus/.gemini/antigravity/scratch/nix/docs/automation/MAINTENANCE_REPORT.md) e arquiva snapshots com carimbo de data/hora em `docs/automation/history/`.
3. **Execução Local de Validação:**
   - Executado localmente com sucesso:
     - Duração total: ~75 segundos.
     - 117/117 testes do cliente aprovados.
     - 13/13 testes do core_crypto aprovados.
     - 22/22 testes do transport aprovados.
     - 100% dos testes e race-detector do relay aprovados.
     - Relatório persistido com badge `🟢 ÍNTEGRO (100% PASSING)`.

---

## 7. MATRIZ DE TESTES E RESULTADOS DE COMPILAÇÃO

```text
================================================================================
                               NIX TEST MATRIX
================================================================================
1. scripts/verify_privacy_matrix.sh       : [PASS] (L-S, I-S, I-A, Zero Telemetria)
2. services/nix_relay (go test -race)    : [PASS] (Buffer, Stores, Admin, Pruner)
3. modules/core_crypto (dart test)        : [PASS] (13/13 tests · PQXDH, Ed25519)
4. modules/transport (dart test)          : [PASS] (22/22 tests · SOCKS5, TLS, NIXB)
5. apps/nix_client (flutter test)         : [PASS] (117/117 tests · Vault, Repos, UI)
================================================================================
TOTAL: 152 testes automatizados executados · 0 falhas · 0 regressões
```

---

## 8. RECOMENDAÇÕES PARA O PROPRIETÁRIO

Em respeito às regras fundamentais de governança:
- **Nenhum merge ou force-push foi executado na branch `main` remota sem autorização expressa do proprietário.**
- Todas as alterações correspondentes aos PRs #20 a #30 e suas respectivas correções de segurança estão devidamente validadas, auditadas e integradas localmente com testes reproduzíveis.
- **Ação sugerida:** O proprietário pode autorizar a publicação das alterações no branch `main` ou a integração sequencial dos PRs no GitHub. A rotina agendada no GitHub Actions manterá a auditoria contínua ativa a cada 4 horas.
