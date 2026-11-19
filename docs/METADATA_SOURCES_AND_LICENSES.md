# Fontes de Metadados, Licenças e Conformidade Legal

## 1. Princípios de Curadoria e Dados Abertos

O catálogo cultural do Nix é constituído unicamente a partir de dados públicos, legalmente redistribuíveis e livres de restrições proprietárias ou termos abusivos de uso. 

Nenhum metadado é extraído de plataformas proprietárias comerciais (como IMDb, TMDb ou Goodreads) sem licença expressa. O Nix prioriza fontes comunitárias estruturadas com licenças permissivas de Domínio Público, Creative Commons ou licenças abertas de bases de dados (ODbL/DbCL).

---

## 2. Matriz de Fontes e Licenciamento

| Fonte | Categoria(s) Coberta(s) | Licença dos Dados | Mecanismo de Ingestão | Atribuição e Obrigações Exigidas |
|---|---|---|---|---|
| **Wikidata** | Filmes, Séries, Obras Literárias | **CC0 1.0 Universal** (Domínio Público) | SPARQL Query Service & JSON Dumps | Não exigida formalmente (CC0 renuncia direitos autorais), mas atribuída por boa prática |
| **Open Library (Internet Archive)** | Livros e Obras Literárias | **CC0 1.0 Universal** / Dados Abertos | Dumps mensais (`ol_dump_editions.txt.gz`) | Não exigida para dados brutos de catálogo |
| **Anime Offline Database (manami-project)** | Animes e Séries de Animação | **ODbL 1.0** (Open Database License) / **DbCL 1.0** (Database Contents License) | JSON dump (`anime-offline-database.json`) | Sim. Exige atribuição expressa, oferta do banco derivado sob ODbL e conformidade com a DbCL 1.0 para conteúdos individuais |
| **MusicBrainz** | Música, Álbuns e Faixas | **CC0 1.0 Universal** | Dumps estruturados | Não para dados centrais sob CC0 |

---

## 3. Especificação Detalhada por Fonte e Obrigações Legais

### 3.1. Wikidata (Wikimedia Foundation)
- **Escopo:** Obras audiovisuais cinematográficas (Q11424), séries de televisão (Q5398426), romances e publicações literárias.
- **Identificadores Preservados:** QID da Wikidata, identificadores VIAF, LCNAF, ISAN.
- **Tratamento de Privacidade:** Nenhum usuário consulta diretamente o endpoint SPARQL da Wikimedia durante a operação padrão; o catálogo é pré-compilado e distribuído em lote em formato SQLite/FTS5.

### 3.2. Open Library (Internet Archive)
- **Escopo:** Livros, autores, primeiros anos de publicação, ISBN-10, ISBN-13 e gêneros literários.
- **Licenciamento:** Os registros bibliográficos são disponibilizados sob domínio público (CC0).
- **Integridade:** Dumps brutos são filtrados para eliminar edições duplicadas ou lixo bibliográfico, retendo a obra raiz (*work*) com o título canônico e ano de primeira publicação.

### 3.3. Anime Offline Database (manami-project)
- **Escopo:** Metadados abrangentes de animação japonesa (títulos em romaji, inglês e japonês, número de episódios, sinopse resumida, anos de lançamento e término, identificadores externos).
- **Licenciamento Correto:** O Anime Offline Database é distribuído oficialmente sob a **Open Database License (ODbL) v1.0**, e os conteúdos individuais sob a **Database Contents License (DbCL) v1.0**. *(A menção anterior a MIT era incorreta e foi retificada).*
- **Obrigações de Redistribuição e Compartilhamento (Share-Alike):**
  - **Atribuição:** Ao redistribuir o dataset ou bases de dados derivadas, é obrigatório creditar o *manami-project / Anime Offline Database*.
  - **Base Derivada (Share-Alike):** Qualquer banco de dados derivado gerado a partir do dataset (como nosso catálogo SQLite compilado contendo registros do AOD) deve ser disponibilizado sob termos compatíveis com a ODbL 1.0 caso seja distribuído publicamente.
  - **Não Extensibilidade Automática a Capas e Mídias:** A licença ODbL aplica-se à estrutura do banco de dados e fatos. Imagens de capa, artes promocionais e sinopses protegidas por terceiros **não** são consideradas livres de restrições por padrão.
  - **Mitigação Nix:** O Nix utiliza estritamente placeholders temáticos gerados localmente (`placeholder:<tipo>`) e não redistribui imagens ou pôsteres proprietários no pacote do catálogo, prevenindo infrações de direitos autorais e vazamentos de rede (anti-tracking).

---

## 4. Política de Atribuição e Isenção de Responsabilidade
- O Projeto Nix disponibiliza em sua interface de configurações e no pacote de licenças os termos das fontes de dados abertos utilizadas, com destaque para a ODbL 1.0 do Anime Offline Database.
- Os metadados incorporados consistem estritamente em fatos históricos e bibliográficos públicos (títulos, autores, diretores, datas de publicação, identificadores canônicos), mantendo plena conformidade com as diretrizes internacionais de dados abertos.
