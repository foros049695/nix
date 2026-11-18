#!/usr/bin/env bash
# ==============================================================================
# setup_dev.sh — Verificação e Preparação do Ambiente de Desenvolvimento
# ==============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "================================================="
echo "🏴‍☠️ PROJETO NIX — Verificação de Pré-Requisitos"
echo "================================================="

check_tool() {
  local tool="$1"
  local desc="$2"
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  ✅ $tool: $(command -v "$tool")"
  else
    echo "  ⚠️ $tool: NÃO ENCONTRADO ($desc)"
  fi
}

echo "Checando ferramentas essenciais:"
check_tool "git" "Controle de versão"
check_tool "code" "Editor VS Code"
check_tool "go" "Linguagem Go (Relay)"
check_tool "rustc" "Compilador Rust"
check_tool "flutter" "SDK Flutter (Cliente Mobile/Desktop)"
check_tool "protoc" "Compilador Protocol Buffers"
check_tool "tor" "Daemon Tor (Onion Services)"

echo ""
echo "Configurando permissões de execução dos scripts..."
chmod +x scripts/*.sh

echo "Executando auditoria da Matriz de Privacidade..."
./scripts/verify_privacy_matrix.sh

echo ""
echo "✨ Ambiente inspecionado com sucesso!"
echo "Para abrir o projeto no VS Code: code nix.code-workspace"
