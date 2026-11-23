# Nix Torrent Index — Arquitetura de Indexação & Busca Soberana

## 1. Visão Geral

O **Nix Torrent Index** é um mecanismo soberano de busca e indexação de metadados de torrents para o Projeto Nix, operando em três modalidades complementares:

1. **Modo A — Catálogo Offline (Local):** Pesquisa instantânea em banco de dados SQLite local dedicado (`torrent_index_v1.db`) com indexação de texto completo FTS5, funcionando 100% sem acesso à rede.
2. **Modo B — Índice Online do Nix:** Consulta à API de metadados centralizada/distribuída do Nix hospedada em endpoint Tor Onion v3 via túnel SOCKS5 fail-closed.
3. **Modo C — Busca Federada ao Vivo:** Consulta sob demanda em tempo real aos conectores externos autorizados (Nyaa, YTS, 1337x, Torznab, RSS), com consolidação de consultas simultâneas em voo e cache de curto prazo com TTL.

---

## 2. Diagrama Arquitetural

```text
FONTES EXTERNAS (RSS / API REST / Torznab / XML)
    │
    │  Nyaa.si / YTS.mx / 1337x / Torznab / Feeds RSS
    ▼
NIX INDEXER WORKERS
    │
    │  Coleta assíncrona com controle de taxa e backoff
    ▼
NIX INDEXER ENGINE
    │
    │  Normalização de títulos, validação de hashes e deduplicação
    ▼
NIX INDEX DATABASE (SQLite FTS5 - torrent_index_v1.db)
    │
    ├──────────────────────────────────────────┐
    │                                          │
    ▼                                          ▼
NIX ONLINE SEARCH API (Onion v3)         PACOTES ASSINADOS (Ed25519)
    │                                          │
    ▼                                          ▼
CLIENTES ONLINE (SOCKS5 Tor)             CLIENTES OFFLINE
    │                                          │
    └────────────────────┬─────────────────────┘
                         │
                         ▼
             CENTRAL NIX DOWNLOADS & TORRENT INDEX
```

---

## 3. Regras Inegociáveis de Segurança e Privacidade

- **Separação Rígida de Atividades:** O Torrent Index é restrito a **pesquisar, visualizar metadados e copiar links magnet**. Ele **nunca** ingressa em swarms BitTorrent, não aciona DHT e não realiza conexões com peers.
- **aria2 Restrito a HTTP/HTTPS:** O gerenciador de downloads diretos do Nix nunca é utilizado para transferências BitTorrent. Qualquer tentativa de submeter uma URI `magnet:` ou arquivo `.torrent` para download direto é terminantemente rejeitada pelo controlador com aviso educativo sobre a preservação de anonimato.
- **Fail-Closed no Tor:** Consultas remotas exigem circuito Tor Onion v3 pronto. Rejeita-se categoricamente qualquer fallback silencioso em clearnet.
- **Zero Mock / Zero Dados Fictícios:** Campos de contagem de seeders, leechers, tamanho em bytes e data só são apresentados caso tenham sido explicitamente observados e fornecidos pelas fontes originais. Caso contrário, permanecem como "Não informado" ou ausentes.

---

## 4. Normalização e Deduplicação

1. **InfoHash v1:** Cadeia canônica de 40 caracteres hexadecimais em minúsculas (`[0-9a-f]{40}`). Se fornecido em Base32 (32 caracteres), é convertido deterministicamente para Hex 40.
2. **InfoHash v2:** Hash SHA-256 de 64 caracteres hexadecimais.
3. **Agregação de Proveniências:** Quando múltiplos indexadores indexam exatamente o mesmo InfoHash, o Nix unifica a visualização sob um único cartão principal, anexando a lista de proveniências (`TorrentSourceProvenance`) com a identificação de cada fonte e seus respectivos seeders e carimbos de tempo originais.
4. **Sem Falsos Positivos:** Torrents com títulos semelhantes mas hashes distintos **nunca** são agrupados automaticamente.

---

## 5. Banco de Dados Local (SQLite FTS5)

- Arquivo independente: `torrent_index_v1.db` (localizado em diretório de suporte seguro da plataforma).
- Tabela virtual `torrent_search` com módulo **FTS5** nativo, provendo busca por prefixos (`"termo"*`), sinônimos e relevância por pontuação `rank`.
- Isolamento absoluto: não polui nem interfere no catálogo cultural público (`nix_catalog_v1.db`) ou no cofre de dados pessoais cifrado (`nix_local_v4.db`).
