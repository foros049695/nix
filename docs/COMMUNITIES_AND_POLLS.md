# Grupos, comunidades e enquetes

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Agrupamento local | `workspace_folder_store.dart`, `channels_sidebar.dart`, `spaces_dock.dart` | Organiza grupos e canais em pastas locais. Dissolver a pasta solta seus itens | `attachments_call_and_music_test.dart` | VERIFIED_LOCAL | Organização local e participação remota são estados independentes. |
| Visibilidade | `channel_settings_dialog.dart`, `nix_state.dart` | Confirma alteração e filtra catálogo local segundo permissões | `pager_chat_privacy_regression_test.dart` | VERIFIED_LOCAL | A homologação de permissões distribuídas requer dois membros e transporte de grupo. |
| Comunidades, tags e enquetes | `forum_channel_view.dart`, `channel.dart` | Tópicos e permissões locais existentes | `mobile_layout_regression_test.dart` | PARTIAL | Faltam comunidades com acesso criptográfico separado, tags de membros e enquetes persistentes distribuídas. |


A distribuição experimental de Sender Keys agora verifica uma assinatura Ed25519 vinculada à época, ao remetente e ao destinatário. Uma chave já instalada para a combinação grupo, autor e época não é reinstalada. A abertura das mensagens verifica a chave de assinatura do autor e limita o avanço de cadeia a 256 mensagens. Grupos experimentais criados com o formato anterior devem rotacionar a época e distribuir novamente as chaves. O teste com três identidades cobre aceitação, rejeição de reenvio e rotação após remoção de um membro.
