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

## 4. Salas privadas de negociação

Use **Criar sala** no mercado ou **Negociar** em uma oferta verificada. Copie o
convite e envie-o em particular à contraparte, que deve escolher **Usar convite**.
O primeiro dispositivo que comprova posse do convite ocupa a vaga da contraparte.
A sala usa um serviço Onion v3 próprio e mensagens autenticadas com
XChaCha20-Poly1305. Os pseudônimos valem apenas naquela sessão. O cliente mantém
o histórico em memória e encerra a sala ao fechá-la ou após 30 minutos.

A entrega depende de Tor operacional nos dois dispositivos e do anfitrião online.
A sala não recebe dados das identidades de mensageria ou da carteira. O método de
pagamento e os dados que as partes compartilham na negociação podem identificá-las.
