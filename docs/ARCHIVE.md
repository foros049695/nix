# 📚 Nix Archive — Publicação Canônica, Claims e Refutações

## 1. Esquema Canônico v1

Cada artigo ou evidência publicado no Nix Archive é transformado em um objeto JSON canônico versionado e endereçado pelo hash SHA-256 (ou Blake3 / CID) dos seus bytes:

```json
{
  "schema": "nix.archive.article.v1",
  "title": "Análise Técnica de Vulnerabilidade de Rádio",
  "body": {
    "format": "markdown",
    "content": "Conteúdo formatado da publicação..."
  },
  "claims": [
    {
      "id": "claim-001",
      "text": "O protocolo LoRa padrão não autentica pacotes em nível de aplicação."
    }
  ],
  "references": [
    {
      "url": "https://example.org/spec",
      "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    }
  ],
  "supersedes": null,
  "author_key": "ed25519:pubkey_da_persona_editorial_opcional"
}
```

---

## 2. Grafo de Refutações

- Uma refutação referencia explicitamente o `object_id` da publicação original e o `claim_id` específico.
- Versões corrigidas mantêm a referência canônica `supersedes` ao objeto anterior, preservando o histórico auditável de correções sem censura silenciosa.
- Votos e avaliações comunitárias são armazenados em camadas de metadados separadas e **não alteram o hash do objeto original**.
