# Aceite incremental do plano mestre

**Base inspecionada:** `cc7602923a`, confirmado no `main` remoto. Issues e PRs abertos estavam vazios na consulta. O plano parte da implementação já integrada e do status registrado em [ROADMAP.md](../ROADMAP.md).

Foram inspecionadas as capturas do Nix e amostras de quadros de sete vídeos. As referências de comunidades e tags mostram papéis, agrupamento e associação de espaços. As referências de enquetes e editor mostram mídia por opção, regras de voto e ferramentas de composição. Os outros vídeos mostram pausa na gravação, organização de faixas no perfil e recorrência no agendamento. Os padrões foram registrados como requisitos funcionais para o design do Nix.

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| A. Correções críticas | [Mensagens](MESSAGING_AND_MEDIA_INTEGRATION.md), [Áudio](AUDIO_DEVICE_DIAGNOSTIC.md) | Convites recíprocos, leitura de QR no Android, relay, avatar e diagnóstico de áudio | Suíte Flutter, teste com dois clientes e relay local | PARTIAL | Câmera, onboarding e conversa por Onion externo e hardware de áudio aguardam homologação. |
| B. Interface adaptativa | [Android](ANDROID_UI_REMEDIATION.md) | Pager, filtros e navegação compacta no Discovery | Testes Flutter com largura variável | PARTIAL | Matriz completa de resoluções e painéis redimensionáveis ainda em aberto. |
| C. Texto e mídia | [Mensagens](MESSAGING_AND_MEDIA_INTEGRATION.md) | Seletor, prévia de imagem, falha explícita de anexo ausente e agendamento de texto direto | Testes de timeline e anexos | PARTIAL | Notas de voz, seleção de fotos com prévia e formatação contextual básica entregues. Vídeo inline, stickers e áudio de chamadas continuam pendentes. |
| D. Comunidades | [Comunidades e enquetes](COMMUNITIES_AND_POLLS.md) | Visibilidade e agrupamento local preservados | Testes de privacidade e pastas | PARTIAL | Enquetes cifradas disponíveis em conversas diretas. Comunidades distribuídas, papéis, tags e enquetes em grupos continuam pendentes. |
| E. Archive | [Archive](ARCHIVE_EDITOR_VALIDATION.md) | Editor Markdown, revisão visual, moderação reversível e assinatura preservada | Teste de fluxo Archive | PARTIAL | Notas de rodapé preservadas. Mídias autorizadas e reações estão pendentes. |
| F. Acervo e música | [Catálogo](MEDIA_PROGRESS_AND_MUSIC.md) | Catálogo local, busca Unicode, progresso cultural e playlist local do Pager no Android | Testes de abertura, busca e integridade | PARTIAL | Playlist do Pager aceita WAV no Linux e Windows. Playlists do acervo, publicação opcional e resenhas formatadas continuam pendentes. |
| G. Finanças | [Mercado](UNIFIED_P2P_MARKETPLACE.md), [RoboSats](ROBOSATS_INTEGRATION.md) | Mercado e carteira em uma entrada, com análise de integração RoboSats | Testes locais de isolamento e assinatura | PARTIAL | Bitcoin on-chain, Lightning, coordenadores e liquidação Monero real continuam pendentes. |
| H. Windows | [Windows](WINDOWS_DESKTOP_IMPLEMENTATION.md) | Runner, cofre, Tor, audio diagnóstico e pacote piloto | Job Windows x64 | PARTIAL | Aceite em máquina Windows com hardware, instalador e assinatura de código aguardam ambiente. |
| I. Validação | [Testes](TESTING.md) | Suítes locais, CI e builds piloto | Privacidade, transportes, Flutter e workflow nativo | PARTIAL | Validação externa e jornadas físicas seguem em aberto. |

A [primeira execução do piloto](https://github.com/foros049695/nix/actions/runs/44796651333) gerou APKs Android, Linux x86_64 e Windows x64. O job Windows compilou o runner, testou o Credential Manager, executou `tor.exe --version` e confirmou a abertura do processo. Esse teste é automatizado e continua separado da homologação em hardware.

## Resultado da revisão publicada

A revisão de código `2aa9cd7` passou em 220 testes Flutter locais. Cinco casos foram ignorados na execução Linux, incluindo os dois casos exclusivos do Windows. Os 23 testes do módulo de transporte também passaram. A jornada de mensageria usou dois clientes, relay local e SOCKS5, com recuperação após a reabertura. [CI completo](https://github.com/foros049695/nix/actions/runs/44800654625)

Os APKs ARM64 e ARMv7 e o pacote Linux x86_64 foram produzidos pelo mesmo workflow, com verificação de SHA-256. A validação Android em aparelho, o áudio em hardware e as jornadas com relay externo e carteira de testes permanecem pendentes. [Pacotes piloto](https://github.com/foros049695/nix/actions/runs/44800654122)

O job Windows x64 compilou o executável, gravou e removeu uma credencial temporária, abriu o catálogo e reabriu um cofre cifrado com a DLL distribuída. Também executou o Tor empacotado e confirmou a abertura do processo do Nix. O ZIP do piloto foi produzido pelo [mesmo workflow](https://github.com/foros049695/nix/actions/runs/44800654122).

## Segunda rodada de implementação

| Entrega | Validação automatizada | Aceite pendente |
|---|---|---|
| QR de convite no Android | O formulário recebe texto do leitor, rejeita links, mostra a recusa de câmera e continua exigindo confirmação explícita. Os APKs incluem o decodificador nativo. | Leitura com câmera em dois aparelhos. |
| Agendamento de texto direto | Teste com dois clientes, relay de loopback e SOCKS5. Reabre o cofre, força rollback na outbox, concorre o despacho e confirma que o contato decifra e reconhece uma única mensagem. Cobre recorrência e cancelamento. | Confirmação de operação com relay Onion externo. O envio automático requer execução em primeiro plano. |
| Playlist privada do Pager no Android | A ordem sobrevive à reabertura do cofre. A interface testa seleção, reordenação, retirada e reprodução por comando explícito. Os APKs incluem o player nativo. | Reprodução audível em Android. A implementação é local e a exposição pública e o suporte desktop seguem em aberto. |

A suíte local do cliente passou com 224 testes e cinco ignorados. Os testes direcionados passaram após reforçar as verificações de decifragem e de permissão. Os jobs de análise e testes do cliente, criptografia, transporte, relay e privacidade passaram na revisão de aplicativo `fafa400`. No PostgreSQL 17 do CI, passaram os testes de concorrência, persistência, expiração e cotas duráveis em duas instâncias. [CI completo](https://github.com/foros049695/nix/actions/runs/44806290027)

Os APKs ARM64 e ARMv7 e o pacote Linux x86_64 tiveram seus SHA-256 verificados. A execução piloto registra a compilação nativa e seus artefatos. [Pacotes piloto de `fafa400`](https://github.com/foros049695/nix/actions/runs/44806291368)

Continuam pendentes mídia e gravação em chamadas, comunidades e enquetes distribuídas, Bitcoin e Lightning e a homologação de liquidação externa de Monero. Os ensaios de rede usaram dados e credenciais do ambiente local de testes.


## Voz, formatação e reprodução local

| Entrega | Verificação |
|---|---|
| Nota de voz Android | Teste de seleção de ações pela interface. Dois clientes trocam e decifram nota de 12 segundos através do relay de laboratório. O tamanho do envelope fica abaixo de 1 MiB. A gravação audível exige aparelho. |
| Formatação contextual | O compositor e o editor de tópicos oferecem negrito, itálico, tachado e monoespaçado. A renderização mantém URLs e mídia externa em texto. |
| Notas de rodapé no Archive | O teste verifica preservação das referências e da lista na representação HTML sanitizada e assinável. |
| Playlist do Pager no desktop | O cofre aceita referências WAV locais e bloqueia endereços remotos. A reprodução depende de saída de áudio e do backend do sistema. |
| Sender Keys experimentais | Teste com três identidades cobre distribuição assinada, duplicatas e exclusão após rotação. A interface de comunidades e enquetes distribuídas depende da integração com o transporte de grupos. |

Continuam pendentes chamadas de voz e sua gravação, enquetes e comunidades distribuídas, Bitcoin/Lightning, aceitação física e ensaios por relay Onion externo.

A suíte local passou com 231 testes e cinco ignorados. O CI da revisão `3a94df4` passou no relay, no cliente, nos módulos Dart e nos gates de privacidade. O player Linux iniciou um fluxo WAV real em uma saída virtual PulseAudio por socket local e encerrou o fluxo ao parar. [CI da revisão](https://github.com/foros049695/nix/actions/runs/44811641607) · [Pilotos nativos](https://github.com/foros049695/nix/actions/runs/44811643293)


## Enquetes diretas e fotos no compositor

Dois clientes trocaram uma enquete pelo relay de laboratório, registraram e alteraram votos e confirmaram a autoridade do autor para encerrar. O resultado foi reconstruído após reabrir o banco. Testes do codec e da interface cobrem prazo, revisões, opções, filtros e prévia local de foto. A integração usa o Double Ratchet existente e nenhuma chave do ambiente financeiro. [Enquetes](COMMUNITIES_AND_POLLS.md) · [Fotos e mensagens](MESSAGING_AND_MEDIA_INTEGRATION.md)

As enquetes em comunidades, o transporte de chamadas, Bitcoin/Lightning e o aceite em hardware permanecem abertos.

O fórum local agora salva tópicos, tags, comentários e reações no SQLCipher. A integração foi executada com SQLCipher 4.6.1 e confirmou que o conteúdo e as permissões retornam após reabrir o cofre. A inspeção do banco bruto confirmou que os textos de controle não aparecem em claro. Os tópicos iniciam com a lista real de anexos vazia. [Fórum e enquetes](COMMUNITIES_AND_POLLS.md)

A tentativa com a rede Tor real chegou ao handshake e parou em 14% do bootstrap. Os resultados de troca cifrada desta rodada correspondem ao relay de laboratório. O aceite por Onion externo continua pendente.

A revisão `cea75b5` passou em 236 testes locais, com seis ignorados na suíte padrão. O teste do fórum foi executado separadamente com SQLCipher obrigatório. Uma segunda prova conectou dois clientes com SQLCipher ao binário Go real do Nix Relay por SOCKS5 de laboratório. O relay armazenou e confirmou quatro envelopes cifrados durante criação, votos e encerramento. [CI da revisão](https://github.com/foros049695/nix/actions/runs/44816035347) · [Pilotos nativos](https://github.com/foros049695/nix/actions/runs/44816035341)
