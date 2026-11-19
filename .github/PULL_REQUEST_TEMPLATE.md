## 📝 Resumo das Mudanças

Uma breve descrição das mudanças introduzidas por este PR.

## 🛡️ Checklist de Conformidade com a Privacidade

- [ ] **Zero Telemetria:** Nenhuma biblioteca de terceiros adiciona rastreadores ou analítica.
- [ ] **Sem Identificação Civil:** Nenhum fluxo exige e-mail, telefone ou acesso à lista de contatos.
- [ ] **Fail-Closed:** Conexões de rede continuam protegidas sob falha de proxy/Tor.
- [ ] **Isolamento de Seeds:** Nenhuma chave financeira (Monero) é tocada por fluxos de mensageria ou mídia.
- [ ] **Sanitização de Metadados:** Imagens e mídias passam por remoção de dados EXIF antes da cifra.

## 🧪 Testes Realizados

- [ ] Testes unitários incluídos e passando.
- [ ] `./scripts/verify_privacy_matrix.sh` executado com sucesso.
- [ ] Verificação de ausência de vazamento de plaintext em disco ou logs.

- **Comando isolado executado:** [ex: `HOME="$(mktemp -d)" flutter test` / namespace de rede isolado]
- **Versões dos SDKs:** [ex: Flutter 3.x / Dart 3.x / Go 1.23]
- **Testes não executados:** [ex: N/A, PostgreSQL (`NIX_TEST_PG_DSN`), Android físico, Tor público]

## 📌 Rastreabilidade
- **Commit Base:** [ex: `abc1234`]
- **Fase do Roadmap:** [ex: Fase 1, Fase 2]
- **Issue Relacionada:** Closes #...
- **Novas Dependências / ADR:** [Nenhuma | `docs/adr/000X-...md`]
