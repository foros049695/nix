# Registro de implementação e homologação do Nix

**Data de referência** 20/11/2026

**Base da validação** `c345886` com as correções da Etapa 9, em clone limpo no Linux.

A [matriz de aceite do roadmap](../ROADMAP.md#aceite-do-plano-mestre-de-implementação)
registra as entregas e os commits das Etapas 0 a 8. O
[relatório mestre de execução](EXECUTION_SUMMARY_REPORT.md) documenta a transição
para a Etapa 9.

## Resultados locais da Etapa 9

| Verificação | Resultado |
|---|---|
| Core criptográfico, `dart analyze` e `dart test` | Análise sem diagnósticos e 13 testes aprovados |
| Transporte, `dart analyze` e `dart test` | Análise sem diagnósticos e 22 testes aprovados em namespace de rede isolado |
| Relay, `go vet ./...` e `go test -race ./...` | Aprovados com Go 1.23.12 |
| `./scripts/verify_privacy_matrix.sh` | Aprovado |
| `./scripts/verify_automation_policy.sh` | Aprovado |
| Cliente, `flutter analyze --no-fatal-infos` | Código 0, sem avisos ou erros, com 188 diagnósticos informativos no Flutter 3.50.1 / Dart 3.14.0 |
| Cliente, `flutter test` com HOME isolado | 190 aprovados e 3 pulados por ausência do catálogo completo |

## Catálogo completo de mídia

O checkout limpo executa os testes de busca, atualização e assinatura com
fixtures versionadas. O teste do catálogo seed abre o banco em modo somente
leitura para preservar o arquivo e verifica a assinatura Ed25519 do manifesto.
O manifesto foi assinado novamente com a chave de teste para corresponder
aos bytes do banco versionado. A suíte de escala pula três casos quando faltam o par
banco/manifesto e o cache AOD. Uma execução dedicada com Python sem
`cryptography` confirmou os mesmos três pulos e código de saída 0.

Para executar esses três casos, disponibilize o par
`build/catalog/nix_catalog_full.db` e
`build/catalog/nix_catalog_full_manifest.json` assinado com a chave de teste
do publicador, ou disponibilize o cache
`tools/metadata_builder/cache/anime-offline-database-minified.json`, Python 3
com `cryptography` e dados do Wikidata via cache ou rede. Com o cache AOD,
a suíte reconstrói os artefatos em diretório temporário.

```bash
cd apps/nix_client
flutter pub get
HOME="$(mktemp -d)" flutter test test/full_media_catalog_test.dart
```

A suíte exige integridade SQLite, pelo menos 50 mil obras nas cinco
categorias, consultas FTS5 abaixo de 50 ms e manifesto Ed25519 válido.
O [relatório de qualidade do catálogo](MEDIA_CATALOG_REPORT.md) registra a
validação anterior do artefato completo, que estava indisponível neste clone.

## APK e publicação

O [relatório Android](ANDROID_VALIDATION_REPORT.md) registra o APK assinado
da Etapa 7. O APK histórico e sua keystore estavam indisponíveis neste clone. As instruções de compilação e o SHA-256 do artefato estão no
[README](../README.md#2-compilação-do-apk-android-release).

A publicação em `origin/main` depende da confirmação do proprietário.
Os cinco jobs do GitHub Actions serão confirmados após a publicação.
Os marcos que dependem de hardware físico e infraestrutura externa constam no
[roadmap](../ROADMAP.md#próximos-marcos-operacionais-e-de-hardware).

O [AGENTS.md](../AGENTS.md) documenta a proibição permanente da rotina de
manutenção de quatro horas. O portão de automação do CI verifica essa política.
