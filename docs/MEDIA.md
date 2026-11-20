# 🎬 Nix Media — Catálogo Local & Conectores em Sandbox

## 1. Armazenamento Local & Histórico Privado

- O Nix Media organiza filmes, séries, animes, mangás e livros de forma totalmente privada.
- O histórico de visualização, notas e listas de favoritos são gravados exclusivamente no banco de dados local **SQLCipher**.
- Nenhum dado de consumo ou preferências de mídia é transmitido para relays ou terceiros.

---

## 2. Conectores em Sandbox

- **Fontes Suportadas:** TMDB, AniList e servidores Jellyfin locais/pessoais.
- **Sanitização de Metadados:**
  - O download de pôsteres e sinopses ocorre através de proxy Tor quando em perfil privado.
  - O visualizador desativa requisições automáticas a pixels de rastreamento remotos ou links de telemetria embutidos nas descrições.

## Abertura do catálogo embarcado

O catálogo abre no isolate com a mesma resolução nativa de SQLite. A primeira instalação verifica o SHA-256 do pacote local. Consultas FTS5 preservam letras e marcas Unicode. Consulte o [estado da integração musical](MEDIA_PROGRESS_AND_MUSIC.md).
