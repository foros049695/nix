# Nix Archive — Publicação Imutável, Assinaturas Ed25519 e Discussões Federadas

## 1. Visão Geral do Nix Archive

O **Nix Archive** é um ambiente autônomo dentro do ecossistema Nix voltado à publicação imutável de ensaios, manifestos, artigos de pesquisa e documentação técnica com autoria criptográfica verificável.

Diferente de plataformas centralizadas com moderação opaca (Substack, Medium), o Nix Archive assegura que:
1. Cada artigo e cada comentário é uma mensagem canônica assinada pela chave **Ed25519** do autor (derivada deterministicamente da Seed A).
2. O conteúdo publicado é endereçado pelo seu hash criptográfico (CID / SHA-256) e armazenado de forma imutável.
3. Rascunhos em elaboração residem **estritamente no cofre local SQLCipher** do autor e **jamais** são transmitidos para a rede.

---

## 2. Diferença Arquitetural: Comentários de Discussão vs. Refutações Formais

O Nix estabelece uma distinção técnica fundamental entre duas formas de interação textual:

| Característica | Comentários de Discussão (`archive_comments`) | Refutações Formais (`archive_refutations`) |
|---|---|---|
| **Tipo de Mensagem** | `nix.archive.comment.v1` | `nix.archive.refutation.v1` |
| **Objetivo** | Diálogo comunitário, dúvidas, notas de rodapé, esclarecimentos e respostas encadeadas (*threads*). | Contestação formal e estruturada de teses, refutação metodológica ou correção factual rigorosa. |
| **Topologia** | Árvore de comentários hierárquica recursiva (`parent_comment_id`). | Vinculada ao identificador da publicação alvo com seções formais (Tese, Prova, Evidência, Conclusão). |
| **Assinatura** | Ed25519 sobre `comment_id + article_id + parent_id + content + timestamp`. | Ed25519 canônica com carimbo de tempo determinístico e verificação de integridade formal. |
| **Moderação do Autor** | Moderação local: o autor do artigo pode silenciar (`muted`) ou ocultar (`hidden`) spams em sua visualização local. | Imutável: o autor não pode censurar uma refutação formal contrária à sua publicação; ela é exibida publicamente lado a lado. |

---

## 3. Estrutura de Dados e Assinatura Canônica de Comentários

### 3.1. Esquema SQLCipher
```sql
CREATE TABLE archive_comments (
    id TEXT PRIMARY KEY,
    article_id TEXT NOT NULL,
    parent_comment_id TEXT,
    author_id TEXT NOT NULL,
    author_name TEXT NOT NULL,
    content TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    signature TEXT NOT NULL,
    is_author_reply INTEGER NOT NULL DEFAULT 0,
    depth INTEGER NOT NULL DEFAULT 0
);
```

### 3.2. Formato Canônico de Assinatura
A assinatura de um comentário `nix.archive.comment.v1` é calculada sobre:
```
UTF8("nix.archive.comment.v1:<article_id>:<parent_comment_id ?? ''>:<author_id>:<created_at>:<content>")
```
Qualquer alteração em um único caractere do conteúdo ou da filiação encadeada invalida a assinatura matemática em todos os nós da rede.

---

## 4. Moderação Local e Silenciamento de Autores

Para prevenir assédio e spam sem introduzir censura centralizada ou pontos únicos de falha:
- A moderação é **estritamente local do leitor/autor**:
  ```sql
  CREATE TABLE archive_moderation (
      author_id TEXT PRIMARY KEY,
      status TEXT NOT NULL CHECK(status IN ('muted', 'blocked')),
      reason TEXT,
      created_at INTEGER NOT NULL
  );
  ```
- Quando um autor é marcado como `muted`, seus comentários deixam de ser renderizados na árvore local de discussões, mas suas assinaturas criptográficas originais permanecem íntegras no banco de dados para fins de auditoria ou desbloqueio futuro.
