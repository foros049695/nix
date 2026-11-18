# 🪙 Nix Wallet — Finanças Exclusivamente Monero (XMR)

## 1. Princípios Não-Custodiais & Isolamento de Seeds

O módulo de finanças do Nix opera de forma 100% não custodial e adota **exclusivamente Monero (XMR)**:
- **Seed A (Mensageiro):** Utilizada exclusivamente para a identidade criptográfica de comunicação e sessões E2EE.
- **Seed B (Monero):** Gerada com entropia criptográfica independente. **Jamais derivada da Seed A, de senhas do chat ou de personas editoriais.**
- **Isolamento de Processo:** A carteira Monero é instanciada em um subprocesso com sandbox ou fronteira FFI estrita. Uma falha de memória ou vulnerabilidade no mensageiro não possui permissão para instruir a assinatura de uma transação financeira.

---

## 2. Roteamento de Rede & Nós Remotos

- **Nós Controlados ou Onion:** O usuário pode configurar seu próprio nó completo ou selecionar nós remotos confiáveis via Tor Onion Service.
- **Prevenção de Vazamento:** Todo o tráfego do daemon wallet RPC é forçado através da interface SOCKS5 do Tor local.
- **Subendereços Descartáveis:** O Nix Wallet gera automaticamente novos subendereços para cada pagamento solicitado, mitigando correlação de histórico por contrapartes.

---

## 3. Mural P2P Efêmero de Ofertas

O Nix inclui um mural para publicação de ofertas de produtos e serviços ponto a ponto com liquidação em XMR:
- As ofertas são mensagens efêmeras assinadas com TTL curto.
- O mural **não atua como custodiante, nem como intermediário de escrow automático**.
- A reputação financeira é estritamente local e **não se transforma em um identificador global do usuário** em outros módulos.
