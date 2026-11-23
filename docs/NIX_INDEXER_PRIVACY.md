# Nix Torrent Index & Downloads — Diretrizes de Privacidade e Segurança

## 1. Princípios Inegociáveis

1. **Sem BitTorrent Através do Tor:**
   - O tráfego do protocolo BitTorrent (uTP, TCP BitTorrent, DHT, PEX) é historicamente notório por vazar o endereço IP real do cliente devido a anúncios de porta no payload UDP e consultas aos trackers.
   - O Nix **nunca conecta a swarms BitTorrent, não faz seeding e não utiliza aria2 para baixar torrents ou resolver magnets**. Magnets servem única e exclusivamente como texto de referência/metadado para cópia pelo usuário.

2. **Ausência de Telemetria e Logs Identificáveis:**
   - O motor de busca não transmite consultas de pesquisa para serviços de telemetria de terceiros.
   - O histórico de busca local permanece desativado por padrão.
   - O modo de busca offline não realiza qualquer chamada de rede.

3. **Opt-in Explícito para Buscas Externas:**
   - A busca padrão utiliza o banco local FTS5 no dispositivo.
   - O modo Online (Onion v3) e o modo Ao Vivo (Federado) requerem seleção explícita pelo usuário.
   - Um aviso claro de transparência informa que o termo pesquisado será enviado através da conexão Tor para o nó de indexação.

4. **Segregação Rigorosa de Dados:**
   - O banco de dados do Torrent Index é armazenado no arquivo dedicado `torrent_index_v1.db`.
   - Nenhuma informação de busca é salva ou misturada com a base do Passaporte Cultural (`nix_database.db`), com as mensagens salvas ou com o cofre de chaves (`key_vault`).

5. **Proteção Anti-Leak em Downloads HTTP:**
   - O controlador do `aria2c` é restrito à interface de loopback (`127.0.0.1`), com porta efêmera e segredo RPC de 32 caracteres gerado criptograficamente a cada inicialização.
   - O aria2c é configurado com flag `--all-proxy=socks5://127.0.0.1:<tor_socks_port>` e `--enable-rpc` restrito a conexões locais autenticadas.
   - Não existe fallback clearnet: em caso de queda do Tor, o download falha de forma fechada (*fail-closed*).
   - O downloader segmentado nativo em puro Dart implementa a mesma política de isolamento.
