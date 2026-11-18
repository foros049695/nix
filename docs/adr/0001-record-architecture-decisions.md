# ADR 0001: Registro Formal de Decisões de Arquitetura

## Status
Aceito (Novembro/2026)

## Contexto
O Nix é um projeto de alta segurança que envolve múltiplos módulos (mensageria, rádio, finanças, publicação). Para manter a rastreabilidade e evitar desvios inadvertidos de projeto ao longo do tempo ou por contribuições via IA, todas as decisões de engenharia relevantes precisam ser registradas formalmente.

## Decisão
Adotamos o padrão de Architecture Decision Records (ADRs) numerados sequencialmente em `docs/adr/`. Toda nova biblioteca externa, mudança de algoritmo criptográfico ou quebra de protocolo deve ser precedida por um ADR aprovado.

## Consequências
- Decisões ficam documentadas com prós, contras e alternativas consideradas.
- Facilita revisões de código e auditorias externas de segurança.
