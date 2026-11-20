# Correções de interface em telas estreitas

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Área interna do Pager | `pager_profile.dart` | Identidade e atalhos rolam juntos. Botão de contemplação permanece acessível. A altura do LCD aumenta em celular | `mobile_layout_regression_test.dart` | VERIFIED_LOCAL | Layout testado como widget, aceite Android em aparelho pendente. |
| Tema e filtros do Media Index | `media_index_view.dart` | Chips acompanham o tema e mantêm o ícone de categoria visível | `mobile_responsive_ui_test.dart` | VERIFIED_LOCAL | Navegação e teclado físico em Android aguardam teste. |
| Convite e configuração do relay | `home_sidebar.dart`, `relay_settings_dialog.dart` | Formulários roláveis, com estados de erro e ações rotuladas | `clean_onboarding_and_real_messenger_test.dart` | VERIFIED_LOCAL | A configuração requer operador de relay. |

O checkout já continha o layout de seções para canal, a carteira flexível, a barra flutuante e a opção de contraste no tema claro. Os testes existentes cobrem 320, 360, 393, 412 e 800 dp em jornadas específicas. A matriz completa solicitada, incluindo paisagem e Android físico, segue em validação.
