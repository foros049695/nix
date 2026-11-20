# Grupos, comunidades e enquetes

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Agrupamento local | `workspace_folder_store.dart`, `channels_sidebar.dart`, `spaces_dock.dart` | Organiza grupos e canais em pastas locais. Dissolver a pasta solta seus itens | `attachments_call_and_music_test.dart` | VERIFIED_LOCAL | Organização local e participação remota são estados independentes. |
| Visibilidade | `channel_settings_dialog.dart`, `nix_state.dart` | Confirma alteração e filtra catálogo local segundo permissões | `pager_chat_privacy_regression_test.dart` | VERIFIED_LOCAL | A homologação de permissões distribuídas requer dois membros e transporte de grupo. |
| Comunidades, tags e enquetes | `forum_channel_view.dart`, `channel.dart` | Tópicos e permissões locais existentes | `mobile_layout_regression_test.dart` | PARTIAL | Faltam comunidades com acesso criptográfico separado, tags de membros e enquetes distribuídas para grupos com mais de dois participantes. |


A distribuição experimental de Sender Keys agora verifica uma assinatura Ed25519 vinculada à época, ao remetente e ao destinatário. Uma chave já instalada para a combinação grupo, autor e época não é reinstalada. A abertura das mensagens verifica a chave de assinatura do autor e limita o avanço de cadeia a 256 mensagens. Grupos experimentais criados com o formato anterior devem rotacionar a época e distribuir novamente as chaves. O teste com três identidades cobre aceitação, rejeição de reenvio e rotação após remoção de um membro.


## Enquetes em conversas diretas

No menu do relógio do compositor de uma conversa cifrada, escolha **Criar enquete**. O formulário aceita pergunta, descrição opcional, duas a oito opções distintas, prazo, respostas múltiplas, alteração de voto, ordem embaralhada e ocultação visual de resultados. Uma enquete de resposta única pode indicar a opção correta de um quiz.

A criação, os votos e o encerramento seguem a mesma fila cifrada do chat. Cada participante tem uma revisão de voto própria, validada a partir dos envelopes autenticados e projetada a partir do histórico do cofre. Só o autor encerra uma enquete e comunica o resultado com os votos que recebeu até aquele momento. Votos locais ainda na fila ficam sinalizados como pendentes. A visualização consulta os 2.048 eventos mais recentes da conversa para manter o custo previsível.

As enquetes são identificadas nesses chats de dois participantes. A ocultação e a resposta do quiz são regras de apresentação no aplicativo. Ambas as partes recebem o conteúdo no envelope cifrado. Use a mesma versão do cliente nos dois dispositivos para interpretar os eventos. Anonimato, anexos por opção e enquetes em comunidades permanecem pendentes.

## Fórum local cifrado

Tópicos, tags, comentários e reações de comentários são gravados no cofre SQLCipher junto às preferências do workspace e restaurados ao desbloquear. O cliente respeita as permissões locais de envio, silenciamento e banimento. Cada tópico começa com a lista de anexos vazia. Esse armazenamento prepara a interface para um futuro transporte de eventos de comunidade.

A integração automatizada abre um cofre real, registra o tópico, reabre a conta e confirma a restauração e o bloqueio de novos comentários. Em ambiente sem biblioteca SQLCipher, o teste informa a limitação. Para tornar a biblioteca obrigatória nesse teste, execute com `NIX_TEST_ENCRYPTED_FORUM=true`.


## Enquetes locais de canais

Em um canal de texto, **Enquetes locais** abre o painel da sala. A enquete
tem pergunta, opções, prazo, voto múltiplo, revoto e resposta correta
configuráveis. A sala isola a visualização, o voto e o encerramento e respeita
a permissão de enviar mensagens. O cofre SQLCipher guarda votos e enquetes
por canal. O ensaio confirmou a recuperação do voto e do encerramento após
reabrir o cofre e a ausência do texto de controle no arquivo cifrado.

A sincronização de enquetes de grupos entre instalações continua aberta.
Os espaços e canais locais ainda carecem de convites autenticados de grupo,
vínculo de membros à época e entrega de eventos aos membros autorizados.
