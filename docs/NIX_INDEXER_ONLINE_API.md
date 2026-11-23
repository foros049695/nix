# Nix Online Search API — Especificação e Protocolo Onion v3

## 1. Visão Geral

A **Nix Online Search API** provê uma interface de busca de metadados de torrents disponibilizada através de um serviço oculto Onion v3 do Tor. Essa API atua como um coordenador central de consultas, protegendo os clientes de realizarem conexões dispersas e isolando os indexadores de tráfego redundante.

A API é estritamente separada do Relay de mensagens criptografadas (`nix_relay`) para assegurar conformidade de segurança e evitar vazamentos entre dados de conversação e termos de busca.

---

## 2. Endpoints e Contratos

### 2.1. `GET /v1/index/search`
Realiza consulta paginada no banco central de metadados normalizados.

- **Parâmetros da Query:**
  - `q` (string, obrigatório): Termo de busca textual.
  - `category` (string, opcional): Slug da categoria (`movies`, `tv`, `anime`, `manga`, `books`, `music`, `games`, `software`, `other`).
  - `source` (string, opcional): ID da fonte (`nyaa`, `yts`, etc.).
  - `sort` (string, opcional): `seeds`, `date`, `size`, `relevance` (padrão: `seeds`).
  - `page` (int, opcional): Índice da página (base 1, padrão: 1).
  - `page_size` (int, opcional): Tamanho da página (máx. 50, padrão: 20).

- **Resposta de Exemplo (JSON 200 OK):**
```json
{
  "query": "solaris",
  "category": "movies",
  "page": 1,
  "pageSize": 20,
  "total": 3,
  "hasMore": false,
  "results": [
    {
      "id": "nyaa_12345",
      "sourceId": "nyaa",
      "sourceName": "Nyaa",
      "title": "Solaris (1972) BDRip 1080p",
      "category": "movies",
      "sizeBytes": 4509715660,
      "infoHashV1": "3b24f5a2e99812df...",
      "magnetUri": "magnet:?xt=urn:btih:3b24f5a2e99812df...",
      "seeders": 42,
      "leechers": 5,
      "publicationDate": "2024-01-15T10:00:00Z",
      "indexedAt": "2024-01-15T12:00:00Z"
    }
  ]
}
```

---

### 2.2. `POST /v1/index/live-search`
Dispara uma consulta federada em tempo real contra todos os conectores ativos autorizados.

- **Corpo da Requisição (JSON):**
```json
{
  "query": "Neon Genesis Evangelion",
  "category": "anime",
  "sources": ["nyaa", "yts"]
}
```

- **Mecanismo de Coalescência (*In-Flight Request Coalescing*):**
  - Se múltiplos clientes (ex: 50 a 500) solicitarem simultaneamente a busca ao vivo do mesmo termo e categoria dentro da mesma janela temporal, a API executa **apenas 1 requisição upstream** para cada fonte.
  - Todas as chamadas concorrentes aguardam e compartilham o mesmo `Future` de resultado, reduzindo o tráfego externo em mais de 98% e prevenindo banimento por limite de requisições (*rate-limit*).
  - O resultado é mantido em cache volátil de curta duração (TTL padrão: 300 segundos).

---

### 2.3. `GET /v1/index/sources`
Retorna a lista de indexadores integrados, status de operação e data da última sincronização.

- **Resposta de Exemplo (JSON 200 OK):**
```json
{
  "sources": [
    {
      "id": "nyaa",
      "name": "Nyaa",
      "type": "rss",
      "enabled": true,
      "totalRecords": 18450,
      "lastSync": "2026-11-23T06:00:00Z"
    },
    {
      "id": "yts",
      "name": "YTS",
      "type": "api",
      "enabled": true,
      "totalRecords": 45200,
      "lastSync": "2026-11-23T06:30:00Z"
    }
  ]
}
```

---

### 2.4. `GET /v1/index/record/{id}`
Obtém o registro canônico completo com todas as fontes de proveniência agregadas.

---

## 3. Segurança e Mitigação de Ataques

1. **Proteção Contra SSRF:** Os workers só aceitam conexões para listas pré-definidas e autorizadas de domínios em HTTPS/Tor. Endpoints privados (127.0.0.1, 10.0.0.0/8, 192.168.0.0/16) são estritamente bloqueados.
2. **Sem Logs de Consultas com Identidade:** As consultas processadas pela API online não são gravadas com identificadores de usuário ou vinculadas a chaves públicas de conversação.
3. **Timeouts Conservadores:** Timeout de 15 segundos por fonte externa; cancelamento imediato em caso de congelamento da conexão.
