# Grupos, comunidades e enquetes

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Agrupamento local | `workspace_folder_store.dart`, `channels_sidebar.dart`, `spaces_dock.dart` | Organiza grupos e canais em pastas locais. Dissolver a pasta solta seus itens | `attachments_call_and_music_test.dart` | VERIFIED_LOCAL | Organização local e participação remota são estados independentes. |
| Visibilidade | `channel_settings_dialog.dart`, `nix_state.dart` | Confirma alteração e filtra catálogo local segundo permissões | `pager_chat_privacy_regression_test.dart` | VERIFIED_LOCAL | A homologação de permissões distribuídas requer dois membros e transporte de grupo. |
| Comunidades, tags e enquetes | `forum_channel_view.dart`, `channel.dart` | Tópicos e permissões locais existentes | `mobile_layout_regression_test.dart` | PARTIAL | Faltam comunidades com acesso criptográfico separado, tags de membros e enquetes persistentes distribuídas. |
