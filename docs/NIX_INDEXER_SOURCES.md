# Nix Torrent Index — Conectores e Fontes de Indexação

## 1. Visão Geral

O **Nix Torrent Index** utiliza uma arquitetura baseada em adaptadores independentes para coleta e consulta de metadados de torrents. Cada fonte implementa a interface abstrata `NixIndexerAdapter`, assegurando desacoplamento total, tratamento de falhas isolado e conformidade estrita com as políticas de privacidade e anti-abuso.

---

## 2. Política de Coleta e Anti-Bypass

1. **Prioridade de Protocolo:**
   - APIs REST / JSON oficiais ou públicas autorizadas.
   - Feeds RSS 2.0 / Atom com namespaces de torrent (`nyaa:`, `torznab:`).
   - Endpoints Torznab XML autenticados por chave de API (opcional).
   - Extração HTML de espelhos públicos autorizados somente quando estritamente compatível.

2. **Proibição Absoluta de Bypass Anti-Bot:**
   - Em conformidade com os princípios éticos do Nix e as diretrizes do sistema, **é proibido burlar CAPTCHAs, Cloudflare Turnstile, hCaptcha ou proteções contra scraping automatizado**.
   - Se uma fonte apresentar desafio Cloudflare/Turnstile (como ocorre frequentemente em espelhos do 1337x), o adaptador identifica a assinatura HTTP 403 / 503 com `cf-mitigated` ou `cf-turnstile` e encerra a consulta marcando a fonte como `rateLimited` ou `blocked`, sem tentar contornar a proteção.

3. **Isolamento de Falhas:**
   - A falha de uma fonte não compromete a pesquisa nas demais fontes ativas.
   - O agregador compila erros parciais e retorna os resultados das fontes operacionais.

---

## 3. Adaptadores Implementados

### 3.1. Nyaa RSS Adapter (`NyaaRssAdapter`)
- **Tipo:** RSS XML.
- **URL Base:** `https://nyaa.si/?page=rss`
- **Categorias Suportadas:** Animes, Mangás, Áudio / Música sem perdas.
- **Metadados Extraídos:**
  - `title`: Título original do release.
  - `nyaa:infoHash`: Hash canônico de 40 caracteres hexadecimais v1.
  - `nyaa:seeders`: Quantidade real de seeders.
  - `nyaa:leechers`: Quantidade real de leechers.
  - `nyaa:size`: Tamanho em formato legível e convertido em bytes reais.
  - `pubDate`: Data RFC-822 da publicação.
  - `enclosure`: Link magnet nativo com trackers anunciados.
- **Regras:** Preserva exatamente os contadores fornecidos pelo feed sem arredondamentos ou preenchimentos artificiais.

### 3.2. YTS API Adapter (`YtsApiAdapter`)
- **Tipo:** REST JSON API (`/api/v2/list_movies.json`).
- **URL Base:** `https://yts.mx/api/v2/list_movies.json`
- **Categorias Suportadas:** Filmes (Longas, Documentários).
- **Metadados Extraídos:**
  - `title_long`: Título do filme com ano de lançamento.
  - `torrents[].hash`: Hash SHA-1 v1 de 40 caracteres.
  - `torrents[].seeds`: Seeders reportados pelo tracker da API.
  - `torrents[].peers`: Leechers reportados.
  - `torrents[].size_bytes`: Tamanho exato em bytes.
  - `torrents[].quality`: Resolução/formato (720p, 1080p, 2160p).
  - Geração canônica de magnet URI: `magnet:?xt=urn:btih:<hash>&dn=<title>&tr=udp://open.demonii.com:1337/announce...`
- **Regras:** Deduplicação entre diferentes resoluções da mesma obra com hash distinto preservando a proveniência.

### 3.3. Torznab XML Adapter (`TorznabAdapter`)
- **Tipo:** Padrão aberto Torznab / Newznab (XML).
- **URL Base:** Configurável pelo usuário (ex: instâncias locais ou comunitárias).
- **Categorias Suportadas:** Todas as categorias padrão Torznab (2000=Movies, 5000=TV, 3000=Audio, 7000=Books, 4000=PC).
- **Metadados Extraídos:**
  - `torznab:attr name="infohash"`: Hash InfoHash v1.
  - `torznab:attr name="seeders"`: Contagem de seeders.
  - `torznab:attr name="peers"`: Contagem de leechers.
  - `torznab:attr name="magneturl"`: Link magnet direto.
- **Regras:** Suporte totalmente opcional para usuários que mantenham instâncias próprias. O Nix **não depende obrigatoriamente de Jackett ou Prowlarr** para seu funcionamento central.

### 3.4. Tracker 1337x Scraper Adapter (`Tracker1337xAdapter`)
- **Tipo:** HTML Parsing (quando espelho autorizado estiver ativo).
- **URL Base:** `https://1337x.to/search/{query}/1/`
- **Comportamento Seguro:**
  - Inspeção de cabeçalhos e corpo para detectar páginas de desafio Turnstile/Cloudflare.
  - Em caso de bloqueio, suspende as requisições imediatas e aciona backoff exponencial de segurança.
  - Extrai linhas da tabela (`name`, `seeds`, `leeches`, `size`) e hash canônico quando acessível.

### 3.5. Feed RSS 2.0 Genérico (`RssIndexAdapter`)
- **Tipo:** RSS / Atom padrão.
- **URL Base:** Configurável por provedor.
- **Metadados Extraídos:** Itens com tags `<enclosure>` de tipo `application/x-bittorrent` ou links `magnet:?xt=urn:btih:`.

---

## 4. Gerenciamento e Teste de Conectividade

O `IndexerSourcesManager` gerencia o ciclo de vida de todas as fontes:
- **Habilitar / Desabilitar:** Controle manual persistido no banco local.
- **Teste de Conexão Ativo:** Envia consulta sintética pontual para verificar a latência e o status HTTP da fonte.
- **Estatísticas de Consulta:** Contadores discretos de registros indexados e registro temporal da última atualização bem-sucedida.
