# 🔮 Trilha Criptográfica Pós-Quântica — Nix

## 1. Avaliação de Handshake Híbrido

- O Nix mantém o X3DH como protocolo clássico de referência e investiga ativamente o protocolo híbrido **PQXDH** (combinando X25519 com algoritmos KEM pós-quânticos padronizados pelo NIST, como ML-KEM-768).
- **Proteção Contra Downgrade:** A negociação de versão em `message.proto` impede que um intermediário force o retorno a perfis clássicos quando ambas as pontas suportam o handshake híbrido.
- **Impacto em Rádio:** A sobrecarga de tamanho de chaves pós-quânticas é avaliada com cautela para evitar inviabilizar o tráfego estrito de rádio LoRa (< 240 bytes).
