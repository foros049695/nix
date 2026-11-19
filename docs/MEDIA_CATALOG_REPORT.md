# Relatório de Qualidade e Conformidade — Nix Media Index

**Data de Compilação:** 2026-11-19 20:29:37 UTC  
**Versão Monotônica:** 1  
**Artefato Gerado:** `nix_catalog_full.db` (25.11 MB, 26333184 bytes)  
**Hash SHA-256:** `f0423fbfd0e9b52c937af5093978e8e1141a9e852c70732b1fc29bd95bc3b109`  
**Signer Ed25519:** `a805baa55178d7c0220a9d586a56db6359521455e3b66d9abf914b829a47f045`  
**Modo de Produção:** `NÃO (Fixture/Test)`  

---

## 1. Métricas Globais do Acervo
- **Total de Obras Ingeridas e Deduplicadas:** 54,692 obras
- **Integridade SQLite:** Aprovada (`PRAGMA integrity_check = ok`)
- **Mecanismo de Busca:** SQLite FTS5 (`unicode61 remove_diacritics 2`)

### 1.1. Distribuição por Categoria Cultural (Kinds)
| Categoria (Kind) | Quantidade de Obras | Percentual |
|---|---|---|
| **anime** | 41,537 | 75.9% |
| **movie** | 12,000 | 21.9% |
| **series** | 4,762 | 8.7% |
| **manga** | 2,500 | 4.6% |
| **book** | 2,157 | 3.9% |

### 1.2. Distribuição por Fonte e Licença Aberta
| Fonte Primária | Licença Aplicada | Obras Contribuídas |
|---|---|---|
| anime-offline-database | ODbL 1.0 / DbCL 1.0 | 41,537 |
| wikidata | CC0 1.0 Universal | 21,419 |

---

## 2. Desempenho e Latência de Busca FTS5
O motor de busca executa 100% localmente no dispositivo sem requisições de rede.

| Consulta (Termo) | Filtro de Categoria | Obras Retornadas | Latência de Busca (ms) |
|---|---|---|---|
| `Matrix` | `movie` | 0 | 0.65 ms |
| `Space` | `all` | 20 | 0.28 ms |
| `Science` | `all` | 20 | 0.23 ms |
| `Naruto` | `anime` | 20 | 0.2 ms |
| `History` | `book` | 20 | 0.7 ms |

---

## 3. Conformidade Legal e Privacidade
- **Anime Offline Database:** Total conformidade com ODbL 1.0. Atribuição incluída.
- **Wikidata:** Dados bibliográficos e cinematográficos sob domínio público (CC0).
- **Privacidade Estrita:** Zero vazamento de telemetria ou rede durante buscas locais.
- **Placeholders Locais:** Capas utilizam placeholders temáticos gerados no cliente, sem requisições HTTP para CDNs externas.
