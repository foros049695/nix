# 🧪 Estratégia de Testes & Portões de Qualidade — Nix

## 1. Níveis de Teste

- **Testes Unitários:** Validação de funções matemáticas, serialização Protobuf e encoders canônicos.
- **Testes de Protocolo:** Simulações de troca de mensagens com reordenação de pacotes, perda forçada e injeção de lixo (fuzzing).
- **Testes Negativos:** Tentativas forçadas de conectar sem Tor no modo privado, assinar com Seed B a partir de mensageria, ou enviar pacotes LoRa maiores que 240 bytes.
- **Portão Estático de Privacidade:** `./scripts/verify_privacy_matrix.sh` executado em todos os commits para barrar SDKs de terceiros e logs com IP.
