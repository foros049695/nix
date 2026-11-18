# ⏱️ Retenção Temporária & AutoPruner — Nix

## 1. Política de Retenção Base

O Nix Relay opera estritamente como um **buffer temporário de entrega (store-and-forward)**:
- **TTL Base:** `expires_at = created_at + 7 dias`.
- **Cota por Anexo:** 50 MB por arquivo individual.
- **Cota em Trânsito por Usuário:** 500 MB cumulativos ativos no relay por token de quota anônimo.
- **Uploads Multipart Incompletos:** Expurgo obrigatório após 12 horas.

---

## 2. AutoPruner Dinâmico com Histerese

Para garantir que o disco de 40 GB da VPS nunca esgote, o daemon de limpeza monitora o percentual de ocupação física e ajusta a janela de retenção:

| Estado | Gatilho de Entrada | Ação do AutoPruner | Retorno (Histerese) |
|---|---|---|---|
| **Normal** | `< 75%` | TTL base de 7 dias mantido. Limpeza de órfãos a cada 1 hora. | — |
| **Alívio Leve** | `≥ 75%` | Redução do teto de expiração para **4 dias** nos itens mais antigos elegíveis. | `< 70%` |
| **Alívio Severo** | `≥ 85%` | Teto reduzido para **48 horas**. Novos anexos limitados a no máximo 10 MB. | `< 75%` |
| **Bloqueio Crítico** | `≥ 92%` | Rejeição imediata de novas mídias/anexos. Reserva exclusiva para texto em fila prioritária. | `< 85%` |

### Regra de Não-Ressurreição
Uma vez que a pressão de disco é aliviada e o estado retorna para Normal, objetos que já foram expurgados **jamais são ressuscitados**, e objetos que tiveram seu tempo reduzido não têm seu prazo estendido além do `expires_at` original.
