# Aceite incremental do plano mestre

**Base inspecionada:** `cc7602923a`, confirmado no `main` remoto. Issues e PRs abertos estavam vazios na consulta. O plano parte da implementação já integrada e do status registrado em [ROADMAP.md](../ROADMAP.md).

Foram inspecionadas as capturas do Nix e amostras de quadros de sete vídeos. As referências de comunidades e tags mostram papéis, agrupamento e associação de espaços. As referências de enquetes e editor mostram mídia por opção, regras de voto e ferramentas de composição. Os outros vídeos mostram pausa na gravação, organização de faixas no perfil e recorrência no agendamento. Os padrões foram registrados como requisitos funcionais para o design do Nix.

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| A. Correções críticas | [Mensagens](MESSAGING_AND_MEDIA_INTEGRATION.md), [Áudio](AUDIO_DEVICE_DIAGNOSTIC.md) | Convites recíprocos, relay, avatar e diagnóstico de áudio | Suíte Flutter, teste com dois clientes e relay local | PARTIAL | Onboarding e conversa por Onion externo e hardware de áudio aguardam homologação. |
| B. Interface adaptativa | [Android](ANDROID_UI_REMEDIATION.md) | Pager, filtros e navegação compacta no Discovery | Testes Flutter com largura variável | PARTIAL | Matriz completa de resoluções e painéis redimensionáveis ainda em aberto. |
| C. Texto e mídia | [Mensagens](MESSAGING_AND_MEDIA_INTEGRATION.md) | Seletor e prévia de imagem existentes, falha explícita de anexo ausente | Testes de timeline e anexos | PARTIAL | Gravação, galeria, player, formatação contextual, stickers e agendamento ainda em aberto. |
| D. Comunidades | [Comunidades e enquetes](COMMUNITIES_AND_POLLS.md) | Visibilidade e agrupamento local preservados | Testes de privacidade e pastas | PARTIAL | Comunidades distribuídas, papéis, tags, editor de tópicos enriquecido e enquetes continuam pendentes. |
| E. Archive | [Archive](ARCHIVE_EDITOR_VALIDATION.md) | Editor Markdown, revisão visual, moderação reversível e assinatura preservada | Teste de fluxo Archive | PARTIAL | Mídias autorizadas, notas de rodapé e reações precisam de integração adicional. |
| F. Acervo e música | [Catálogo](MEDIA_PROGRESS_AND_MUSIC.md) | Catálogo local, busca Unicode, progresso cultural e pacote musical existente | Testes de abertura, busca e integridade | PARTIAL | Playlists, resenhas formatadas e reprodução no perfil continuam pendentes. |
| G. Finanças | [Mercado](UNIFIED_P2P_MARKETPLACE.md), [RoboSats](ROBOSATS_INTEGRATION.md) | Mercado e carteira em uma entrada, com análise de integração RoboSats | Testes locais de isolamento e assinatura | PARTIAL | Bitcoin on-chain, Lightning, coordenadores e liquidação Monero real continuam pendentes. |
| H. Windows | [Windows](WINDOWS_DESKTOP_IMPLEMENTATION.md) | Runner, cofre, Tor, audio diagnóstico e pacote piloto | Job Windows x64 | PARTIAL | Aceite em máquina Windows com hardware, instalador e assinatura de código aguardam ambiente. |
| I. Validação | [Testes](TESTING.md) | Suítes locais, CI e builds piloto | Privacidade, transportes, Flutter e workflow nativo | PARTIAL | Validação externa e jornadas físicas seguem em aberto. |

A [primeira execução do piloto](https://github.com/foros049695/nix/actions/runs/44796651333) gerou APKs Android, Linux x86_64 e Windows x64. O job Windows compilou o runner, testou o Credential Manager, executou `tor.exe --version` e confirmou a abertura do processo. Esse teste é automatizado e continua separado da homologação em hardware.

## Resultado da revisão publicada

A revisão de código `2aa9cd7` passou em 220 testes Flutter locais. Cinco casos foram ignorados na execução Linux, incluindo os dois casos exclusivos do Windows. Os 23 testes do módulo de transporte também passaram. A jornada de mensageria usou dois clientes, relay local e SOCKS5, com recuperação após a reabertura. [CI completo](https://github.com/foros049695/nix/actions/runs/44800654625)

Os APKs ARM64 e ARMv7 e o pacote Linux x86_64 foram produzidos pelo mesmo workflow, com verificação de SHA-256. A validação Android em aparelho, o áudio em hardware e as jornadas com relay externo e carteira de testes permanecem pendentes. [Pacotes piloto](https://github.com/foros049695/nix/actions/runs/44800654122)

O job Windows x64 compilou o executável, gravou e removeu uma credencial temporária, abriu o catálogo e reabriu um cofre cifrado com a DLL distribuída. Também executou o Tor empacotado e confirmou a abertura do processo do Nix. O ZIP do piloto foi produzido pelo [mesmo workflow](https://github.com/foros049695/nix/actions/runs/44800654122).
