# ADR 0002: Bibliotecas Criptográficas e Primitivas Padrão

## Status
Aceito (Novembro/2026)

## Contexto
A segurança do Nix depende de criptografia madura, sem código criptográfico ad-hoc ou primitivas proprietárias.

## Decisão
1. Adotar **libsodium** e **SQLCipher** como fundações de baixo nível.
2. Utilizar:
   - **XChaCha20-Poly1305** para cifragem simétrica de anexos e objetos.
   - **Double Ratchet + X3DH** para sessões fim a fim assíncronas par a par.
   - **Ed25519** para identificação de rede e personas editoriais.
   - **Argon2id** para derivação de chave de cofre local a partir de senha de usuário.
3. Proibir expressamente modificações nas funções de derivação interna ou misturas de primitivas sem avaliação em ADR.

## Consequências
- Garantia de implementação testada e auditada por especialistas internacionais.
- FFI limpo entre Dart (Flutter) e C nativo com limpeza de memória garantida.
