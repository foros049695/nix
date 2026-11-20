# RoboSats como referência de negociação

O README do RoboSats descreve trocas P2P de Bitcoin por moedas locais, identidades por negociação, hold invoices Lightning e coordenadores Onion. O Nix mantém Monero como ativo central. A experiência de maker/taker e pseudônimos pode orientar ambas as interfaces, com uma implementação financeira própria por ativo. [Código e documentação do RoboSats](https://github.com/RoboSats/robosats)

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Lightning em testnet | [RoboSats](https://github.com/RoboSats/robosats) | Leitura do fluxo documentado | Inspeção do README | PARTIAL | Faltam conector autenticado exclusivamente via Tor, validação das invoices e coordenação testnet. |
| Recebimento on-chain | [RoboSats](https://github.com/RoboSats/robosats) | Dependência de suporte do coordenador a verificar | Pendente | BLOCKED | Requer coordenador e cenário de teste autorizados antes do aceite externo. |
| Monero | [Mercado financeiro do Nix](UNIFIED_P2P_MARKETPLACE.md) | Ofertas assinadas, sala e isolamento existentes | Testes locais de anúncios e negociações | PARTIAL | Escrow, arbitragem e liquidação exigem mecanismos próprios de Monero. |
