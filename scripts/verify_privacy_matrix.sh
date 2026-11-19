#!/usr/bin/env bash
# ==============================================================================
# verify_privacy_matrix.sh — Portão de Verificação Estática de Privacidade (Nix)
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "🛡️ [NIX-AUDIT] Iniciando varredura da Matriz de Privacidade no repositório ($REPO_ROOT)..."

ERRORS=0

# 1. Proibir SDKs de terceiros e Analytics conhecidos (Critério L-S)
FORBIDDEN_PATTERNS=(
  "google-analytics"
  "firebase_analytics"
  "facebook_app_events"
  "mixpanel"
  "amplitude"
  "crashlytics"
  "sentry_flutter"
  "appsflyer"
)

echo "🔍 [L-S] Verificando ausência de SDKs de rastreamento e telemetria..."
for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
  if grep -ri --exclude-dir=".git" --exclude-dir=".dart_tool" --exclude-dir="build" --exclude-dir="assets" --exclude="verify_privacy_matrix.sh" "$pattern" .; then
    echo "❌ [FALHA] Encontrada menção ou dependência proibida: $pattern"
    ERRORS=$((ERRORS + 1))
  else
    grep_status=$?
    if [ "$grep_status" -gt 1 ]; then
      echo "❌ [ERRO] Não foi possível concluir a varredura L-S (grep: $grep_status)."
      ERRORS=$((ERRORS + 1))
    fi
  fi
done

# 2. Verificar que o relay não registra IPs em log (Critério I-S)
echo "🔍 [I-S] Verificando logs do Relay para evitar registro de IP..."
# Fontes diretas de IP do cliente, independentemente do nome do receptor.
if grep -riE --include="*.go" '\.[[:space:]]*RemoteAddr\b|X-Forwarded-For|X-Real-IP' services/nix_relay/; then
  echo "⚠️ [ALERTA] Acesso a endereço IP do cliente detectado no código Go do relay!"
  ERRORS=$((ERRORS + 1))
else
  grep_status=$?
  if [ "$grep_status" -gt 1 ]; then
    echo "❌ [ERRO] Não foi possível concluir a varredura I-S (grep: $grep_status)."
    ERRORS=$((ERRORS + 1))
  fi
fi

# 3. Proibir permissões de contatos e identidade telefônica no Android (Critério I-A)
echo "🔍 [I-A] Verificando permissões de contatos, SMS e telefonia nos manifests..."
# Examina cada tag, inclusive em várias linhas. Remover uma permissão herdada
# é permitido, sem ocultar outras solicitações no mesmo manifesto ou linha.
if manifest_matches=$(find . -type d \( -name .git -o -name .dart_tool -o -name build -o -name assets \) -prune -o \
  -type f -name AndroidManifest.xml -exec awk '
    BEGIN { RS = ">" }
    /<uses-permission(-sdk-[0-9]+)?[[:space:]]/ &&
    /android\.permission\.(READ_CONTACTS|WRITE_CONTACTS|GET_ACCOUNTS|READ_SMS|RECEIVE_SMS|SEND_SMS|READ_CALL_LOG|READ_PHONE_STATE|READ_PHONE_NUMBERS)["\047]/ &&
    !/tools:node[[:space:]]*=[[:space:]]*["\047]remove["\047]/ {
      print FILENAME ":" $0 ">"
    }
  ' {} +); then
  if [ -n "$manifest_matches" ]; then
    printf '%s\n' "$manifest_matches"
    echo "❌ [FALHA] Permissão Android de identificação civil detectada!"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "❌ [ERRO] Não foi possível concluir a varredura I-A (find/awk)."
  ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -eq 0 ]; then
  echo "✅ [SUCESSO] Todos os portões estáticos da Matriz de Privacidade foram aprovados!"
  exit 0
else
  echo "❌ [ERRO] Falha na verificação de privacidade: $ERRORS violações detectadas."
  exit 1
fi
