# Mercado financeiro do Nix

O módulo permanece na entrada financeira existente com foco em Monero. A negociação local usa pseudônimos por anúncio e a sala privada usa chaves isoladas da identidade de mensagens. O método fiduciário pode identificar as partes fora do Nix.

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Ofertas XMR | `monero_p2p_view.dart`, `monero_ad_verifier.dart` | Assinatura, limites e expiração existentes | `audit_integration_verification_test.dart` | VERIFIED_LOCAL | Liquidação real depende de carteira e rede de teste. |
| Chat privado | `trade_simulation_test.dart`, `sovereign_messenger.dart` | Negociação isolada e sala de teste separada do fluxo real | `gate3_two_client_e2ee_test.dart` | VERIFIED_LOCAL | Pagamento e disputa requerem mecanismos próprios de XMR. |
| Bitcoin e Lightning | [Análise do RoboSats](ROBOSATS_INTEGRATION.md) | Consulta do protocolo e das dependências | Leitura das fontes públicas | PARTIAL | O aplicativo ainda carece do conector e de uma jornada testnet verificável. |
