# RoboSats como referência de negociação

O README do RoboSats descreve trocas P2P de Bitcoin por moedas locais, identidades por negociação, hold invoices Lightning e coordenadores Onion. O Nix mantém Monero como ativo central. A experiência de maker/taker e pseudônimos pode orientar ambas as interfaces, com uma implementação financeira própria por ativo. [Código e documentação do RoboSats](https://github.com/RoboSats/robosats)

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Lightning em testnet | [RoboSats](https://github.com/RoboSats/robosats) | Leitura do fluxo documentado | Inspeção do README | PARTIAL | O cliente consulta um LND próprio por Tor e verifica a rede, o valor e a expiração. A validação usou respostas de laboratório. A coordenação e a liquidação continuam abertas. |
| Bitcoin on-chain | Bitcoin Core e BIP21 | Revisão de endereços e valores, QR para carteira externa e consulta do nó de teste por Tor | Vetores BIP21 e SOCKS5 de laboratório | PARTIAL | Criação de endereço, transmissão, confirmação e aceitação externa continuam abertas. |
| Monero | [Mercado financeiro do Nix](UNIFIED_P2P_MARKETPLACE.md) | Ofertas assinadas, sala e isolamento existentes | Testes locais de anúncios e negociações | PARTIAL | Escrow, arbitragem e liquidação exigem mecanismos próprios de Monero. |


A aba **Bitcoin / Lightning** fica na área financeira. Pedidos BIP21 e
faturas BOLT11 podem ser revisados e transferidos para a carteira externa por
QR ou cópia. As consultas remotas são opcionais e exigem um nó próprio Onion
v3 de teste. Para Bitcoin Core, use um usuário RPC restrito à consulta
`getblockchaininfo`. Para LND, use um macaroon de leitura para
`GetInfo` e `DecodePayReq`. As credenciais são transitórias e a conexão usa
o SOCKS do Tor com isolamento por consulta. A carteira externa executa
pagamentos. A consulta do Nix somente lê dados do nó.
