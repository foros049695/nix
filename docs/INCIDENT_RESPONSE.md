# 🚨 Plano de Resposta a Incidentes de Segurança — Nix

## 1. Contato & Triagem

- **Canal oficial (ativo):** relatos de vulnerabilidade devem ser enviados pelo **GitHub Private Vulnerability Reporting**:
  **https://github.com/foros049695/nix/security/advisories/new**
  (aba *Security* → *Report a vulnerability*). O relato fica visível apenas aos mantenedores e ao autor até a divulgação coordenada.
- **Nunca** use Issues, Pull Requests, Discussions ou comentários públicos para descrever falhas ainda não corrigidas.
- Uma chave PGP/Age oficial dos mantenedores **ainda não foi publicada**. Até lá, o canal acima é o único canal privado suportado; não envie relatos por outros meios.
- Não inclua seeds, chaves privadas, tokens, endereços IP reais ou dados pessoais no relato; use dados sintéticos na prova de conceito.
- A equipe de mantenedores realiza a triagem em até 48 horas úteis, classificando a severidade de acordo com o padrão CVSS v3.1.

---

## 2. Contenção & Notificação

1. **Correção em Branch Isolada:** O patch de segurança é desenvolvido e testado em repositório privado.
2. **Release Emergencial:** Publicação de nova versão assinada com changelog detalhando o impacto sem divulgar exploits de forma prematura.
3. **Divulgação Coordenada:** Relatório público em `docs/SECURITY.md` após prazo razoável para atualização dos nós da rede.
