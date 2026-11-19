# ADR 0006: Dependências de SQLCipher, FFI de Cofre Nativo e QR Code no Cliente Flutter

## Status
Proposto (registro retroativo)

## Contexto
Conforme o [ADR 0001](0001-record-architecture-decisions.md), o [ADR 0002](0002-crypto-library-and-primitives.md) e o [`CONTRIBUTING.md`](../../CONTRIBUTING.md), toda adição de biblioteca externa em manifestos de pacotes deve ser registrada em ADR. Durante a entrega do onboarding soberano e da persistência cifrada da Fase 1 (commits `6fec381` e `1dea5f3`), o mantenedor adicionou quatro dependências diretas a `apps/nix_client/pubspec.yaml`:

1. `sqlite3: ^2.4.0` (resolvida em `2.9.4` no `pubspec.lock`, commit `6fec381`);
2. `qr_flutter: ^4.1.0` (trazendo a dependência transitiva `qr: 3.0.3`, commit `6fec381`);
3. `sqlcipher_flutter_libs: ^0.6.8` (commit `1dea5f3`);
4. `ffi: ^2.1.3` (commit `1dea5f3`).

> **Nota sobre este registro retroativo:** a motivação técnica e a comparação de alternativas abaixo foram reconstruídas a partir dos commits e do código atual para regularizar a rastreabilidade exigida pelo projeto, ficando abertas para revisão, ajuste e eventual promoção a `Aceito` pelo mantenedor.

## Decisão Registrada
Utilizar as quatro dependências em `apps/nix_client/pubspec.yaml` com escopos delimitados e sem acesso de rede:

1. **`sqlite3` (`package:sqlite3/open.dart`) + `sqlcipher_flutter_libs`:**
   - `sqlite3` fornece o ponto de substituição `open.overrideFor(...)` em `apps/nix_client/lib/core/database/local_database.dart`, permitindo que `sqflite_common_ffi` carregue explicitamente bibliotecas dinâmicas SQLCipher (`libsqlcipher_flutter_libs_plugin.so` / `libsqlcipher.so`) antes de qualquer fallback local, viabilizando a validação *fail-closed* `PRAGMA cipher_version` (`requireEncryption: true`).
   - `sqlcipher_flutter_libs` empacota o motor nativo SQLCipher 4.x (Community Edition + OpenSSL 3.x) nos builds Flutter Android/Linux (`apps/nix_client/lib/core/database/android_sqlcipher_flutter.dart`).
2. **`ffi` (`package:ffi/ffi.dart`):**
   - Fornece utilitários de alocação nativa (`calloc`/`malloc`) e conversão `Utf8` em `apps/nix_client/lib/core/security/os_key_storage.dart` para invocar diretamente `libsecret-1.so.0` e `libglib-2.0.so.0` via `dart:ffi` no Linux Desktop, sem recorrer a subprocessos shell (`secret-tool`).
3. **`qr_flutter` (e transitiva `qr`):**
   - Substitui o desenho ilustrativo anterior por codificação e renderização local em conformidade com o padrão ISO/IEC 18004 (`QrImageView` em `apps/nix_client/lib/features/profile/qr_code_painter.dart` e `sovereign_onboarding_flow.dart`), operando 100% offline sobre identificadores públicos (`nix://id/...`).

## Alternativas e Trade-offs (Reconstrução)
1. **`sqflite_sqlcipher` (via `MethodChannel`) vs. `sqflite_common_ffi` + `sqlite3` + `sqlcipher_flutter_libs`:** a combinação atual com `sqflite_common_ffi` e `sqlite3/open.dart` unifica o motor transacional entre Linux Desktop, suítes de teste FFI locais (sem emulador) e Android, além de permitir injeção controlada em testes para validar rejeição *fail-closed* contra `libsqlite3.so` comum (`plain_sqlite_rejection_probe_test.dart`).
2. **`flutter_secure_storage` vs. `ffi` + `MainActivity.kt`:** no Android o cliente já acessa o `AndroidKeyStore` diretamente via `MethodChannel` próprio; o uso pontual de `package:ffi` oficial do Dart para `libsecret` no Linux evita incorporar um plugin multiplataforma adicional no caminho crítico do cofre.
3. **Codificador QR próprio ou geração externa vs. `qr_flutter`:** implementar codificação Reed-Solomon/ISO 18004 própria adicionaria complexidade desnecessária (o pintor anterior baseado em SHA-256 não gerava matriz legível por leitores padrão), enquanto qualquer serviço externo violaria a diretriz *offline/zero-telemetry*.

## Compatibilidade de Licenças com GPL-3.0
O Projeto Nix é licenciado sob **GNU General Public License v3.0 (`GPL-3.0`)** ([`LICENSE`](../../LICENSE)). Todas as bibliotecas diretas, transitivas e nativas embutidas possuem licenças livres compatíveis com a GPLv3:

| Componente | Escopo | Licença | Fontes Verificadas |
|---|---|---|---|
| `sqlite3` (`^2.4.0` / `2.9.4`) | Dart FFI loader | MIT (Expat) | [pub.dev/packages/sqlite3/license](https://pub.dev/packages/sqlite3/license) |
| `sqlcipher_flutter_libs` (`^0.6.8`) | Wrapper Flutter | MIT (Expat) | [pub.dev/packages/sqlcipher_flutter_libs/versions/0.6.8/license](https://pub.dev/packages/sqlcipher_flutter_libs/versions/0.6.8/license) |
| SQLCipher Community Edition (embutido) | Motor C criptográfico | BSD-3-Clause (Modified BSD) | [zetetic.net/sqlcipher/license](https://www.zetetic.net/sqlcipher/license/) |
| OpenSSL 3.x (embutido em `sqlcipher_flutter_libs`) | Primitivas criptográficas C | Apache-2.0 | [pub.dev/packages/sqlcipher_flutter_libs/versions/0.6.8/license](https://pub.dev/packages/sqlcipher_flutter_libs/versions/0.6.8/license) |
| SQLite core (embutido) | Motor SQL base | Domínio Público | [zetetic.net/sqlcipher/license](https://www.zetetic.net/sqlcipher/license/) |
| `ffi` (`^2.1.3`) | Utilitários `dart:ffi` | BSD-3-Clause (Modified BSD) | [pub.dev/packages/ffi/license](https://pub.dev/packages/ffi/license) |
| `qr_flutter` (`^4.1.0`) e `qr` (`3.0.3`) | Renderização QR offline | BSD-3-Clause (Modified BSD) | [pub.dev/packages/qr_flutter/license](https://pub.dev/packages/qr_flutter/license); [pub.dev/packages/qr/license](https://pub.dev/packages/qr/license) |
| `libsecret-1` / `glib-2.0` (sistema Linux via `dlopen`) | Cofre D-Bus do SO | LGPL-2.1+ | [FSF License List: `#LGPLv2.1`](https://www.gnu.org/licenses/license-list.html#LGPLv2.1) |

- **Avaliação de compatibilidade (FSF):** as licenças Expat/MIT (`#Expat`), Modified BSD / BSD-3-Clause (`#ModifiedBSD`), Domínio Público (`#PublicDomain`) e LGPL-2.1+ (`#LGPLv2.1`) são compatíveis com a GNU GPLv3, e a licença **Apache-2.0** (adotada pelo OpenSSL 3.x em substituição à antiga licença dupla OpenSSL/SSLeay) é expressamente compatível com a **versão 3 da GNU GPL** ([FSF — Various Licenses and Comments about Them: `#apache2`](https://www.gnu.org/licenses/license-list.html#apache2)).
- **Obrigação de atribuição:** a licença BSD da SQLCipher Community Edition e a Apache-2.0 exigem preservação dos avisos de copyright e licença na documentação/materiais distribuídos com o aplicativo (já catalogados em [`docs/THIRD_PARTY_LICENSES.md`](../THIRD_PARTY_LICENSES.md)).

## Consequências
- Nenhuma das dependências adicionadas introduz telemetria, SDKs comerciais ou permissões de rede/identificação civil, mantendo conformidade integral com `scripts/verify_privacy_matrix.sh`.
- Em ambientes Linux headless de CI onde `libsqlcipher` nativa não está pré-compilada, `LocalDatabase` reporta explicitamente `isEncrypted: false` em modo de desenvolvimento e recusa abertura *fail-closed* quando `requireEncryption: true`.
- O mantenedor upstream de `sqlcipher_flutter_libs` marcou a linha `0.7.0+eol` recomendando migração futura para `package:sqlite3` 3.x com *native build hooks* do Dart SDK; qualquer atualização futura para essa arquitetura deverá ser registrada em novo ADR.
