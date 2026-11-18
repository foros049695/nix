# ADR 0004: Contrato Criptográfico, Double Ratchet Transacional e Canonicalização

## Status
Aceito (Novembro/2026) — Marco P0-1

## Contexto
Na auditoria técnica do Projeto Nix (Novembro/2026), identificou-se uma vulnerabilidade crítica de negação de serviço persistente no módulo `nix_core_crypto` (achado **CRY01**):
1. O método `DoubleRatchet.decrypt` realizava rotação de chaves Diffie-Hellman (`_dhRatchet`) e derivação de chaves puladas (`_skipMessageKeys`) diretamente sobre as variáveis internas da sessão, antes da validação de autenticidade AEAD (`SealedEnvelope.open`).
2. Um atacante capaz de forjar um cabeçalho de mensagem com chave DH arbitrária provocava a corrupção do estado da sessão em memória do destinatário, desincronizando irreversivelmente a catraca criptográfica e impedindo que mensagens legítimas subsequentes fossem decifradas.
3. Além disso, a canonicalização de registros assinados (`SignedRecord`) ordenava unicamente as chaves de primeiro nível do payload, permitindo divergência de assinaturas em estruturas aninhadas, e o guarda anti-replay (`ReplayGuard`) interrompia prematuramente a limpeza de expurgos fora de ordem.

## Decisão
1. **Double Ratchet com Transação em Estado Candidato:**
   - O avanço da catraca DH e das cadeias de recepção deve ser calculado integralmente em um snapshot de estado candidato (`candidateState`).
   - Apenas se a verificação AEAD (`XChaCha20-Poly1305`) obtiver sucesso com o tag de autenticação e dados adicionais associados (AAD), o estado candidato é efetivado (*committed*) no objeto da sessão.
   - Caso a mensagem seja forjada ou adulterada, a exceção é propagada e nenhuma variável interna do ratchet é modificada, mantendo a sessão perfeitamente sincronizada para mensagens legítimas.
2. **Canonicalização Recursiva e Estrita de Payloads (`SignedRecord`):**
   - Implementar ordenação recursiva determinística de chaves para todos os níveis de mapas aninhados no payload.
   - Listas são serializadas mantendo a ordem dos elementos com valores internos canônicos.
3. **Guarda Anti-Replay com Purge Completo (`ReplayGuard`):**
   - Varrer o conjunto de nonces expurgando todas as entradas com `expiresAt < now`, sem pressupor que a ordem de inserção corresponda à ordem de expiração temporal.
4. **Isolamento de Pré-Chaves e Bundles:**
   - Prekey bundles são serializados com versão de domínio, prazo de validade estrito e assinados com a chave mestra Ed25519.

## Consequências
- Elimina completamente o vetor de ataque DoS por corrupção de ratchet via mensagens forjadas.
- Garante integridade matemática consistente entre emissores e verificadores em payloads estruturados.
- Mantém o limite de segurança de até 256 chaves puladas por sessão contra ataques de exaustão de memória.
