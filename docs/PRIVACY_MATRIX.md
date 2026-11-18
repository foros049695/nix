# 🛡️ Matriz de Privacidade — The Hated One (21 IDs)

Esta matriz traduz os critérios de pontuação máxima em testes verificáveis de engenharia para o Projeto Nix. Todos os IDs começam no estado **PLANEJADO** e só são promovidos para **VALIDADO** mediante relatório de teste assinado e auditável.

| ID | Eixo | Contexto | Requisito Verificável | Procedimento de Teste | Critério de Aceite |
|---|---|---|---|---|---|
| **L-A** | Linkability | Account | Criação de 2 personas distintas sem compartilhamento de dados. | Gerar Conta 1 e Conta 2 no mesmo cliente. Inspecionar bancos SQLite/SQLCipher e memória. | Zero chaves, hashes ou identificadores cruzados. |
| **L-U** | Linkability | Usage | Tráfego de uso e reconexão não correlacionáveis diretamente via IP. | Captura de pacotes (Wireshark) durante login, envio e sincronização. | 100% do tráfego encapsulado em Onion v3 Tor; zero saídas diretas. |
| **L-S** | Linkability | Service | Nenhuma vinculação de usuário entre dispositivos ou serviços externos. | Varredura de binários e dependências contra SDKs analíticos ou IDs de anunciantes. | Zero bibliotecas de tracking; zero endpoints externos embutidos. |
| **I-A** | Identifiability | Account | Cadastro local soberano sem PII. | Execução do assistente de primeiro uso. | Zero campos para telefone, email, nome civil ou upload de agenda. |
| **I-U** | Identifiability | Usage | Fail-closed em quedas de rede Tor/Proxy. | Desconectar intencionalmente o daemon Tor ou bloquear porta 9050. | O app bloqueia transmissões imediatamente; nenhum pacote IP vaza. |
| **I-S** | Identifiability | Service | Discos e logs do relay limpos de dados de identidade. | Inspeção do servidor relay após tráfego de teste com dados sentinela. | Zero endereços IP, nomes ou metadados de identidade em logs ou dumps. |
| **N-A** | Nonrepudiation | Account | Negação plausível de mensagens no chat privado. | Análise criptográfica do esquema de chaves efêmeras. | Mensagens privadas não utilizam assinaturas digitais públicas não-repudiáveis. |
| **N-U** | Nonrepudiation | Usage | Metadados de transporte efêmeros. | Inspeção de cabeçalhos de envelopes trocados no relay. | Envelopes usam chaves de caixa opacas descartáveis. |
| **N-S** | Nonrepudiation | Service | Purgamento comprovado após TTL. | Inspeção do disco do relay após expiração de 7 dias (ou histerese). | Dados eliminados física e criptograficamente sem possibilidade de reconstrução. |
| **D-A** | Detectability | Account | Instalação e uso sem registro em autoridade central. | Criação de conta em modo avião. | Conta local criada com sucesso sem tocar em nenhum servidor remoto. |
| **D-U** | Detectability | Usage | Tor integrado ativo por padrão. | Início do aplicativo em rede monitorada. | Tráfego inicial consiste unicamente em conexões Tor Onion. |
| **D-S** | Detectability | Service | Métricas Prometheus minimizadas e agregadas. | Consulta ao endpoint `/metrics` do relay. | Métricas restritas a contadores de conexões e buffers; sem labels de IPs ou IDs. |
| **DD-A** | Data Disclosure | Account | Proteção do cofre local contra extração física. | Tentativa de leitura do arquivo SQLCipher sem senha ou chave Argon2id. | Conteúdo indistinguível de ruído aleatório; zero plaintext em swap/WAL. |
| **DD-U** | Data Disclosure | Usage | Criptografia de ponta a ponta em todos os fluxos privados. | Análise de payload nos intermediários (relay e S3/MinIO). | Todas as mensagens, anexos e mídias privadas estão cifrados pelo remetente. |
| **DD-S** | Data Disclosure | Service | Código aberto, auditável e com retenção zero de plaintext. | Auditoria de código fonte e dependências. | 100% de código aberto; sem chaves mestras ou backdoors. |
| **U-A** | Unawareness | Account | Chaves com escopo estritamente delimitado. | Teste de tentativa de assinatura financeira usando chaves de mensageria. | Rejeição garantida pelo sistema de tipos e fronteiras de processo. |
| **U-U** | Unawareness | Usage | Avisos de exposição explícitos ao usuário. | Transição para perfil Wi-Fi local ou transmissão de rádio LoRa. | Modal de confirmação claro alertando sobre a detecção por proximidade/RF. |
| **U-S** | Unawareness | Service | Modelo de operação e políticas 100% documentados. | Validação cruzada entre `docs/PRIVACY.md` e código do relay. | Nenhuma divergência entre documentação pública e comportamento real. |
| **C-A** | Noncompliance | Account | Revogação de acesso e exclusão local instantânea. | Acionamento de PIN de coação ou deleção de cofre. | Chaves de descriptografia sobrescritas em memória e storage destruído. |
| **C-U** | Noncompliance | Usage | Revogação imediata de permissões de conectores. | Desativar conector externo (ex: TMDB) nas configurações. | Cessação imediata de quaisquer chamadas de rede para o serviço. |
| **C-S** | Noncompliance | Service | Resposta a incidentes e ciclo de vulnerabilidades. | Simulação de falha de segurança e execução de `docs/INCIDENT_RESPONSE.md`. | Protocolo documentado de contenção, divulgação responsável e mitigação. |
