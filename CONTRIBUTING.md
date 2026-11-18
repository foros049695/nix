# 🤝 Guia de Contribuição — Projeto NIX

Obrigado pelo seu interesse em contribuir com o **Projeto Nix**! Nosso objetivo é construir um sistema robusto, auditável e soberano de comunicação e conhecimento.

---

## 🔒 Princípios Não-Negociáveis

Ao submeter código ou documentação, esteja ciente de que qualquer alteração que fira os princípios abaixo será **rejeitada imediatamente**:

1. **Zero Telemetria:** É estritamente proibida a adição de analytics, rastreadores, SDKs comerciais ou relatórios de crash automatizados para terceiros.
2. **Sem Identificação Civil:** O cliente jamais deve exigir ou sugerir telefone, SMS, e-mail, CPF ou leitura de contatos.
3. **Criptografia Padrão:** Não implemente primitivas criptográficas próprias. Toda operação deve usar bibliotecas consolidadas e auditadas (libsodium, SQLCipher).
4. **Isolamento de Seeds:** A chave do mensageiro (**Seed A**) jamais deve se comunicar ou derivar a chave da carteira Monero (**Seed B**).
5. **Fail-Closed:** Conexões de rede privadas não devem recorrer a fallback desprotegido caso o Tor ou proxy falhe.

---

## 🛠️ Fluxo de Trabalho e Git

1. **Crie um Fork e uma Branch de Tópico:**
   ```bash
   git checkout -b feature/minha-melhoria
   ```
2. **Escreva Testes:**
   Toda nova funcionalidade deve vir acompanhada de testes unitários ou de integração que validem os gates de segurança da fase atual.
3. **Valide a Matriz de Privacidade:**
   ```bash
   ./scripts/verify_privacy_matrix.sh
   ```
4. **Convenção de Commits:**
   Utilize commits convencionais e claros:
   - `feat(messenger): adiciona temporizador de mensagens efêmeras`
   - `fix(relay): corrige histerese no AutoPruner ao atingir 85% de disco`
   - `docs(privacy): documenta procedimento de auditoria da célula L-U`

---

## 📋 Checklist de Pull Request (PR)

Antes de abrir o PR, verifique:
- [ ] Código formatado de acordo com `.editorconfig`.
- [ ] Nenhum segredo, chave ou token em arquivos ou histórico.
- [ ] Nenhuma dependência externa adicionada sem registro prévio em ADR.
- [ ] Testes passando localmente (`flutter test`, `go test`).
- [ ] Execução bem-sucedida de `./scripts/verify_privacy_matrix.sh`.
