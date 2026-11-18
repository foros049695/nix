# 🔐 Política de Segurança & Modelo de Ameaças — Nix

## 1. Modelo de Ameaças

| Vetor de Ataque | Ameaça Concreta | Contramedida do Nix | Limite Técnico Declarado |
|---|---|---|---|
| **Apreensão de VPS / Servidor Relay** | Operador malicioso ou ordem judicial acessando a infraestrutura. | O relay armazena apenas buffers cifrados opacos com TTL de 7 dias. Não possui chaves de decifração. | O operador pode observar horários de conexão, tamanhos aproximados e contagem de caixas. |
| **Interceptação de Tráfego de Rede** | Ataque MITM por ISP ou atacante na mesma rede Wi-Fi. | E2EE via Double Ratchet + transporte via Tor Hidden Services (v3). | Análise estatística de tráfego avançada por adversário global pode inferir atividade. |
| **Perda ou Apreensão do Dispositivo** | Dispositivo físico em posse de adversário. | Banco local SQLCipher com chave AES-256 cifrada via Argon2id; Duress PIN opcional. | Se o aparelho estiver desbloqueado ou houver spyware residente, os dados podem ser acessados. |
| **Substituição de Chave (MITM de Identidade)** | Adversário injetando chave pública falsa durante troca inicial. | Verificação de identidade fora de banda via QR Code ou fingerprint seguro; alerta de alteração. | Requer ação deliberada do usuário para comparar os códigos. |
| **Tempestade de Rádio (DDoS em LoRa)** | Atacante saturando a frequência RF com mensagens falsas. | Filtro estrito de protocolo Protobuf, limites de airtime e deduplicação de mensagens. | O meio físico RF permanece sujeito a jamming ativo de sinal. |

---

## 2. Perfil Criptográfico

- **Identidade & Assinaturas:** Ed25519 (chaves separadas por aplicação).
- **Acordo de Chaves:** X25519.
- **Sessão Assíncrona & Catraca:** Double Ratchet com X3DH (e avaliação de trilha híbrida pós-quântica PQXDH).
- **Cifra Simétrica de Anexos:** XChaCha20-Poly1305 com nonces de 192 bits e autenticação de integridade.
- **Derivação de Chaves Locais:** Argon2id calibrado para mobile e desktop.
- **Proteção de Memória:** Limpeza explícita via `sodium_memzero` antes de liberar buffers sensíveis.

---

## 3. Divulgação Responsável de Vulnerabilidades

Caso encontre uma falha de segurança no Nix, solicitamos que nos contate de forma confidencial. Não abra issues públicas relatando vulnerabilidades críticas antes da mitigação. Veja `docs/INCIDENT_RESPONSE.md`.
