# Fontes de Metadados, Licenças e Conformidade Legal

## 1. Princípios de Curadoria e Dados Abertos

O catálogo cultural do Nix é constituído unicamente a partir de dados públicos, legalmente redistribuíveis e livres de restrições proprietárias ou termos abusivos de uso. 

Nenhum metadado é extraído de plataformas proprietárias comerciais (como IMDb, TMDb ou Goodreads) sem licença expressa. O Nix prioriza fontes comunitárias estruturadas com licenças permissivas de Domínio Público ou Creative Commons.

---

## 2. Matriz de Fontes e Licenciamento

| Fonte | Categoria(s) Coberta(s) | Licença dos Dados | Mecanismo de Ingestão | Atribuição Exigida |
|---|---|---|---|---|
| **Wikidata** | Filmes, Séries, Obras Literárias | **CC0 1.0 Universal** (Domínio Público) | SPARQL Query Service & JSON Dumps | Não (CC0 renuncia direitos autorais) |
| **Open Library (Internet Archive)** | Livros e Obras Literárias | **CC0 1.0 Universal** / Dados Abertos | Dumps mensais (`ol_dump_editions.txt.gz`) | Não para dados brutos de catálogo |
| **Anime Offline Database (manami-project)** | Animes e Séries de Animação | **MIT License** | JSON dump (`anime-offline-database.json`) | Sim (incluso no arquivo de licenças do Nix) |
| **MusicBrainz** | Música, Álbuns e Faixas | **CC0 1.0 Universal** | Dumps estruturados | Não (CC0 para metadados core) |

---

## 3. Especificação Detalhada por Fonte

### 3.1. Wikidata (Wikimedia Foundation)
- **Escopo:** Obras audiovisuais cinematográficas (Q11424), séries de televisão (Q5398426), romances e publicações literárias.
- **Identificadores Preservados:** QID da Wikidata, identificadores VIAF, LCNAF, ISAN.
- **Tratamento de Privacidade:** Nenhum usuário consulta diretamente o endpoint SPARQL da Wikimedia durante a operação padrão; o catálogo é pré-compilado e distribuído em lote.

### 3.2. Open Library (Internet Archive)
- **Escopo:** Livros, autores, primeiros anos de publicação, ISBN-10, ISBN-13 e gêneros literários.
- **Licenciamento:** Os registros bibliográficos são disponibilizados sob domínio público (CC0).
- **Integridade:** Dumps brutos são filtrados para eliminar edições duplicadas ou lixo bibliográfico, retendo a obra raiz (*work*) com o título canônico e ano de primeira publicação.

### 3.3. Anime Offline Database (Anime-Offline-Database)
- **Escopo:** Metadados abrangentes de animação japonesa (títulos em romaji, inglês e japonês, número de episódios, sinopse resumida, anos de lançamento e término).
- **Licenciamento:** Licença MIT. O repositório mantém integridade e deduplicação comunitária regular.

---

## 4. Política de Atribuição e Isenção de Responsabilidade
- O Projeto Nix disponibiliza em sua interface de configurações e no pacote de licenças os termos das fontes de dados abertos utilizadas.
- Os metadados contêm exclusivamente informações fatuais (títulos, autores, diretores, datas, sinopses factuais), as quais não constituem obras protegidas por direitos autorais em jurisdições internacionais de direito autoral (Doutrina *Feist Publications* e equivalentes civis).
