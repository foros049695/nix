# ADR 0003: Isolamento Absoluto entre Seed A e Seed B (Monero)

## Status
Aceito (Novembro/2026)

## Contexto
O ecossistema Nix integra comunicação privada com transações em Monero (XMR). Misturar sementes mnemônicas ou chaves de identidade entre comunicação e finanças cria riscos severos de correlação e comprometimento cruzado de fundos.

## Decisão
1. **Seed A:** Exclusiva para recuperar identidades e sessões de comunicação do Nix Messenger.
2. **Seed B:** Gerada com gerador de números pseudoaleatórios criptograficamente seguro (CSPRNG) e mantida exclusivamente para a carteira Monero.
3. Proibir que a Seed B seja derivada matematicamente da Seed A, da senha da conta ou de identificadores do chat.
4. Executar operações da carteira em processo ou sandbox isolado com permissões restritas.

## Consequências
- Se o usuário perder ou divulgar acidentalmente a Seed A, seus fundos em Monero permanecem intocados.
- Um exploit em camadas de parsing de mídia ou chat não consegue assinar transações financeiras.
