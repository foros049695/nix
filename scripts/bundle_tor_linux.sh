#!/usr/bin/env bash
set -euo pipefail

# Script para empacotar os binários do Tor e bibliotecas no bundle do Nix Client Linux
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="$PROJECT_ROOT/apps/nix_client/build/linux/x64/release/bundle"
LOCAL_BUNDLE="$HOME/.local/share/nix/bundle"

echo "=== Empacotando Tor Embutido no Bundle Linux ==="

# 1. Garante que o diretório ~/.local/share/nix/bundle existe
mkdir -p "$LOCAL_BUNDLE"

# 2. Se o bundle de release existir, injeta o executável tor e dependências
if [ -d "$BUNDLE_DIR" ]; then
  mkdir -p "$BUNDLE_DIR/lib"
  
  if [ -f "$LOCAL_BUNDLE/tor" ]; then
    cp -f "$LOCAL_BUNDLE/tor" "$BUNDLE_DIR/tor"
    chmod 0755 "$BUNDLE_DIR/tor"
    echo " -> Binário tor copiado para: $BUNDLE_DIR/tor"
  fi

  if [ -d "$LOCAL_BUNDLE/lib" ]; then
    cp -rf "$LOCAL_BUNDLE/lib/"* "$BUNDLE_DIR/lib/" || true
    echo " -> Bibliotecas dinâmicas copiadas para: $BUNDLE_DIR/lib"
  fi
fi

echo "=== Empacotamento concluído com sucesso ==="
