# Mensagens cifradas e anexos no cliente

1. Desbloqueie o cofre e abra **Configurações → Conexões → Relay de mensagens**.
2. Copie o identificador da caixa postal e forneça-o ao operador por um canal de confiança. Configure o endereço Onion v3 e a credencial de leitura emitida pelo operador. Informe a cota de escrita se o relay exigir.
3. Na lista de conversas, abra **Adicionar Contato Soberano**. Copie o convite ou exiba o QR na tela. No Android, use **Ler QR pela câmera**, confira o conteúdo recebido e escolha **Importar e abrir conversa**. As duas pessoas devem trocar e importar os convites assinados pelo canal de confiança.
4. O cliente escolhe o iniciador X3DH pela ordenação dos identificadores. A outra pessoa sincroniza a caixa postal para receber a primeira mensagem cifrada e habilitar a resposta. Os dois clientes usam o mesmo identificador de conversa. A assinatura do convite valida as chaves contidas nele. A interface mantém o contato como não verificado até haver verificação por um canal independente.

Os tokens ficam no cofre SQLCipher, separados do JSON de inicialização. A opção de sincronização usa as credenciais provisionadas e o SOCKS atual do Tor. Sem sessão válida, o cliente bloqueia o envio. Com sessão pronta e relay ausente, enfileira o envelope cifrado localmente. A aceitação pelo relay representa armazenamento remoto, com a entrega ao contato ainda pendente.

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Convite, sessão e resposta | `home_sidebar.dart`, `nix_state.dart`, `sovereign_messenger.dart` | Convite recíproco assinado, X3DH e Double Ratchet serializado | `transactional_messaging_fault_test.dart`, `gate3_two_client_e2ee_test.dart` | VERIFIED_LOCAL | A jornada externa precisa de duas contas provisionadas no mesmo relay Onion. |
| Escrita com cota, falha e reinício | `nix_state.dart` | Usa a cota do operador, mantém a outbox e recupera os envelopes após o reinício | `transactional_messaging_fault_test.dart` | VERIFIED_LOCAL | Teste usa SOCKS5 e relay em loopback. |
| Anexos | `chat_input_bar.dart`, `message_bubble.dart`, `sovereign_messenger.dart` | Seletor e prévia de imagens existentes. O envio agora acusa um arquivo ausente | `attachments_call_and_music_test.dart` | PARTIAL | Galeria, vídeo inline e gravação de chamadas ficam pendentes. |

## Mensagens agendadas

Em uma conversa direta com sessão cifrada, escreva o texto e use o menu do relógio para selecionar **Agendar este texto**. Escolha a data, hora e repetição. **Ver agendamentos** mostra os textos pendentes da conversa e permite cancelar os próximos envios. Texto já enfileirado segue o ciclo de entrega normal.

O agendamento fica no SQLCipher local. O Nix precisa estar aberto em primeiro plano, com o cofre desbloqueado, o Tor operacional e o relay Onion disponível. Se voltar após o horário, o cliente envia a ocorrência pendente e avança para o próximo intervalo. As recorrências são intervalos de 24 horas ou sete dias a partir da primeira data. Os envios automáticos não usam BLE, LoRa ou rede direta. O recurso admite texto simples em conversas diretas.

O caminho exibido em builds anteriores era a referência interna do seletor Android escrita diretamente no balão. O componente atual apresenta o nome e, se conseguir acessar uma imagem válida, a prévia. O caminho continua necessário para ler o arquivo local antes de preparar o anexo.


## Voz e formatação

No Android, use o microfone do compositor em uma conversa direta cifrada. O diálogo permite gravar, pausar, retomar, ouvir a prévia e cancelar. A captura exige autorização do microfone, fica em memória e tem limite de 12 segundos. O envio confirmado usa o mesmo formato de anexo cifrado da conversa. O Nix interrompe a captura ao entrar em segundo plano. As notas recebidas podem ser reproduzidas no próprio chat Android.

Selecione texto no compositor ou na descrição de um tópico para aplicar negrito, itálico, tachado ou monoespaçado. A leitura usa spans de texto locais e mantém mídia e links externos como texto.
