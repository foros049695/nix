# 🔐 Política de Segurança & Modelo de Ameaças — Nix

## 1. Modelo de Ameaças

| Vetor de Ataque | Ameaça Concreta | Contramedida do Nix | Limite Técnico Declarado |
|---|---|---|---|
| **Apreensão de VPS / Servidor Relay** | Operador malicioso ou ordem judicial acessando a infraestrutura. | O relay armazena apenas buffers cifrados opacos com TTL de 7 dias. Não possui chaves de decifração. | O operador pode observar horários de conexão, tamanhos aproximados e contagem de caixas. |
| **Interceptação de Tráfego de Rede** | Ataque MITM por ISP ou atacante na mesma rede Wi-Fi. | E2EE via Double Ratchet + transporte via Tor Hidden Services (v3). | Análise estatística de tráfego avançada por adversário global pode inferir atividade. |
| **Perda ou Apreensão do Dispositivo** | Dispositivo físico em posse de adversário. | Banco local SQLCipher com chave AES-256 cifrada via Argon2id; Duress PIN opcional. | Se o aparelho estiver desbloqueado ou houver spyware residente, os dados podem ser acessados. |
| **Substituição de Chave (MITM de Identidade)** | Adversário injetando chave pública falsa durante troca inicial. | Verificação de identidade fora de banda via QR Code ou fingerprint seguro; alerta de alteração. | Requer ação deliberada do usuário para comparar os códigos. |
| **Tempestade de Rádio (DDoS em LoRa)** | Atacante saturando a frequência RF com mensagens falsas. | Filtro estrito de protocolo Protobuf, limites de airtime e deduplicação de mensagens. | O meio físico RF permanece sujeito a jamming ativo de sinal. |
| **Fingerprinting de Resolução e Dispositivo** | Conteúdo remoto ou embed tentando identificar o usuário pelas dimensões exatas da tela e DPR. | Inicialização em janela não maximizada padronizada (`1152x720`), discretização de viewport em múltiplos de 64px (`WindowPrivacyGuard`) e bloqueio de embeds remotos. | Protege contra scripts/conteúdos renderizados internamente; não impede que processos locais com acesso ao servidor gráfico (X11/Wayland) consultem o monitor físico. |

---

## 2. Perfil Criptográfico

- **Identidade & Assinaturas:** Ed25519 (chaves separadas por aplicação).
- **Acordo de Chaves:** X25519.
- **Sessão Assíncrona & Catraca:** Double Ratchet com X3DH (e avaliação de trilha híbrida pós-quântica PQXDH).
- **Cifra Simétrica de Anexos:** XChaCha20-Poly1305 com nonces de 192 bits e autenticação de integridade.
- **Derivação de Chaves Locais:** Argon2id (64 MiB, 3 iterações) via `PassphraseKdf.strong()` sem frase-passe padrão fixa.
- **Banco Local Cifrado:** SQLCipher com `requireEncryption: true` (bloqueio fail-closed contra SQLite comum sem `PRAGMA cipher_version`).
- **Proteção de Memória:** Zeroização explícita de buffers sensíveis `Uint8List` via `fillRange(0, length, 0)` ao bloquear o `KeyVault` ou encerrar `NixState.dispose()`, reconhecendo os limites inerentes ao coletor de lixo (GC) do runtime Dart.
- **Autenticidade de Distribuição Offline:** Verificação obrigatória de manifesto assinado Ed25519 (`SignedReleaseManifest`) além de SHA-256 em `ShareAppOfflineDialog`.
- **Sanitização Editorial Anti-XSS:** Tokenizador determinístico de HTML por whitelist estrita (`NixArchiveService.sanitizeRichTextHtml`) em artigos e refutações canônicos.

---

## 3. Divulgação Responsável de Vulnerabilidades

Caso encontre uma falha de segurança no Nix, envie um relato confidencial pelo **GitHub Private Vulnerability Reporting** (`https://github.com/foros049695/nix/security/advisories/new`, verificado como ativo via API). Não abra issues públicas relatando vulnerabilidades antes da mitigação. Veja `SECURITY.md` e `docs/INCIDENT_RESPONSE.md`.
