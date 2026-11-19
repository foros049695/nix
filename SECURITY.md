# 🔐 Política de Segurança & Modelo de Ameaças — Projeto Nix

> **Data de Revisão:** Novembro de 2026  
> **Versão:** 4.1-dev

O Projeto Nix é desenvolvido sob a premissa de que a segurança e a privacidade devem ser comprovadas por meio de auditoria de código aberta, propriedades matemáticas verificáveis e testes de regressão automatizados.

---

## 1. Modelo de Ameaças e Limites Técnicos

O Nix adota uma abordagem honesta de segurança por projeto (*Security by Design*). Reconhecemos que nenhuma ferramenta de software é capaz de garantir anonimato absoluto contra todos os vetores de vigilância possíveis.

| Vetor de Ataque | Ameaça Concreta | Contramedida do Nix | Limite Técnico Declarado |
|---|---|---|---|
| **Apreensão de Servidor Relay** | Operador malicioso ou ordem judicial assumindo controle da VPS. | O relay armazena exclusivamente buffers cifrados opacos (*blind mailboxes*) com expurgo progressivo em até 7 dias. Não possui chaves de decifração. | O operador pode observar horários de conexão, tamanhos aproximados de pacotes e volumetria de tráfego. |
| **Interceptação de Tráfego de Rede** | Ataque Man-in-the-Middle (MITM) por operadoras (ISP) ou redes hostis. | Criptografia de ponta a ponta (Double Ratchet) e transporte estritamente encapsulado via circuitos Tor Onion v3 (*fail-closed*). | Ataques avançados de correlação estatística de tráfego em escala global podem inferir padrões de atividade. |
| **Perda ou Apreensão do Dispositivo** | Dispositivo físico em posse de adversário. | Banco de dados local cifrado com SQLCipher (AES-256-CBC por página) e chave protegida pelo cofre seguro do sistema operacional (Android Keystore / Linux Secret Service) com envelope Argon2id. | Se o dispositivo for apreendido desbloqueado ou possuir spyware/malware em nível de kernel/root, os dados em memória podem ser extraídos. |
| **Substituição de Chave Pública (MITM)** | Adversário tentando forjar chaves públicas durante o intercâmbio inicial. | Verificação de identidade fora de banda via QR Code padronizado e comparação de fingerprints completos; alerta visual de alteração de chaves. | Exige ação deliberada dos usuários para comparar os dados fora de banda. |
| **Fingerprinting de Viewport & Sistema** | Conteúdo ou mídia tentando inferir o dispositivo pelas dimensões exatas de tela. | Inicialização padronizada em janela não maximizada (`1152x720`), quantização de viewport em múltiplos de 64px (`WindowPrivacyGuard`) e bloqueio de embeds externos remotos. | Protege contra scripts e visualizadores internos; não impede que ferramentas locais com acesso ao servidor gráfico nativo (X11/Wayland) consultem o hardware. |

---

## 2. Perfil Criptográfico Padrão

* **Identidade & Assinaturas de Rede:** Ed25519 (chaves públicas canônicas com derivação determinística).
* **Acordo de Chaves Assegurado:** X25519 com troca de chaves Diffie-Hellman em curva elíptica.
* **Sessão Assíncrona & Catraca:** Double Ratchet com X3DH (Extended Triple Diffie-Hellman) e autenticação AEAD com transação atômica pré-commit.
* **Cifragem de Objetos e Anexos:** XChaCha20-Poly1305 com nonces aleatórios de 192 bits e autenticação de integridade.
* **Derivação de Chaves Locais:** Argon2id calibrado para mobile e desktop.
* **Cofre Local de Persistência:** SQLCipher com integridade de página e verificação estrita de `cipher_version`.

---

## 3. Divulgação Responsável de Vulnerabilidades

Se você identificar uma falha de segurança, vulnerabilidade criptográfica ou possibilidade de vazamento de metadados no Projeto Nix:

1. **Não abra issues públicas no GitHub** relatando detalhes exploráveis de vulnerabilidades ainda não corrigidas.
2. Envie um relatório confidencial pelo **GitHub Private Vulnerability Reporting**: <https://github.com/foros049695/nix/security/advisories/new> (aba *Security* → *Report a vulnerability*). Detalhes e regras de triagem em [`docs/INCIDENT_RESPONSE.md`](docs/INCIDENT_RESPONSE.md).
3. Inclua no relatório:
   * Versão do software e commit do repositório afetado.
   * Descrição detalhada do vetor de ataque e impacto esperado.
   * Prova de conceito (PoC) reproduzível ou passos para demonstração.
4. Nossa equipe responderá acusando o recebimento em até 48 horas e trabalhará na validação, desenvolvimento de patch e divulgação coordenada.
