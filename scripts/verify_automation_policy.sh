#!/usr/bin/env bash
# ==============================================================================
# verify_automation_policy.sh — Verificação de Política de Automação (Nix)
#
# REGRA PERMANENTE: A automação periódica de 4 horas (nix_maintenance_audit.yml)
# foi desativada permanentemente por ordem do proprietário.
# Este script verifica se:
# 1. O arquivo .github/workflows/nix_maintenance_audit.yml permanece ausente.
# 2. Nenhum outro workflow possui agendamento de 4 horas (*/4 ou equivalente).
# 3. Nenhum cron job ou mecanismo de manutenção recorrente foi reintroduzido.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "🛡️ [NIX-POLICY] Verificando conformidade da política de automações..."

ERRORS=0

# 1. Verificar ausência estrita de .github/workflows/nix_maintenance_audit.yml
if [ -f ".github/workflows/nix_maintenance_audit.yml" ]; then
  echo "❌ [VIOLAÇÃO CRÍTICA] O arquivo .github/workflows/nix_maintenance_audit.yml foi reintroduzido!"
  echo "   O proprietário determinou expressamente que essa rotina deve permanecer desativada."
  ERRORS=$((ERRORS + 1))
fi

# 2. Verificar se algum workflow em .github/workflows contém agendamento de 4 horas ou rotina de manutenção periódica
if [ -d ".github/workflows" ]; then
  for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$wf" ] || continue

    # Permitir workflows legítimos conhecidos (ci.yml, security-audit.yml semanal)
    # Mas proibir qualquer schedule com intervalo de 4 horas (ex: */4)
    if grep -qE "cron:[[:space:]]*['\"][^'\"]*\*/4" "$wf"; then
      echo "❌ [VIOLAÇÃO CRÍTICA] Agendamento de 4 horas detectado em $wf!"
      ERRORS=$((ERRORS + 1))
    fi

    # Proibir qualquer workflow que execute run_maintenance_audit.py em schedule
    if grep -q "run_maintenance_audit.py" "$wf" && grep -q "schedule:" "$wf"; then
      echo "❌ [VIOLAÇÃO CRÍTICA] Execução agendada de run_maintenance_audit.py detectada em $wf!"
      ERRORS=$((ERRORS + 1))
    fi
  done
fi

# 3. Verificar scripts e crontabs locais no repositório
if grep -riE --exclude-dir=".git" --exclude-dir="docs" --exclude="verify_automation_policy.sh" "0 \*/4 \* \* \*" .; then
  echo "❌ [VIOLAÇÃO CRÍTICA] Expressão cron de 4 horas encontrada no repositório!"
  ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -eq 0 ]; then
  echo "✅ [SUCESSO] Política de desativação da rotina de 4 horas plenamente cumprida!"
  exit 0
else
  echo "❌ [ERRO] Política de automação violada: $ERRORS inconformidade(s) detectada(s)."
  exit 1
fi
