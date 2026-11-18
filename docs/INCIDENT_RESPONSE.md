# 🚨 Plano de Resposta a Incidentes de Segurança — Nix

## 1. Contato & Triagem

- Relatos de vulnerabilidades devem ser enviados aos canais seguros dos mantenedores (chave PGP/Age oficial).
- A equipe de mantenedores realiza a triagem em até 48 horas úteis, classificando a severidade de acordo com o padrão CVSS v3.1.

---

## 2. Contenção & Notificação

1. **Correção em Branch Isolada:** O patch de segurança é desenvolvido e testado em repositório privado.
2. **Release Emergencial:** Publicação de nova versão assinada com changelog detalhando o impacto sem divulgar exploits de forma prematura.
3. **Divulgação Coordenada:** Relatório público em `docs/SECURITY.md` após prazo razoável para atualização dos nós da rede.
