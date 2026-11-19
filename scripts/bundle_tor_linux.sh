#!/usr/bin/env bash
set -euo pipefail

# Script para empacotar os binários do Tor e bibliotecas no bundle do Nix Client Linux
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="$PROJECT_ROOT/apps/nix_client/build/linux/x64/release/bundle"
LOCAL_BUNDLE="$HOME/.local/share/nix/bundle"
BUILD_LIB_APP="$PROJECT_ROOT/apps/nix_client/build/lib/libapp.so"

echo "=== Empacotando Tor Embutido e Atualizando Bundle Linux ==="

mkdir -p "$LOCAL_BUNDLE/lib"
mkdir -p "$BUNDLE_DIR/lib"

# 1. Se a nova compilação AOT gerou build/lib/libapp.so, atualiza o bundle
if [ -f "$BUILD_LIB_APP" ]; then
  cp -f "$BUILD_LIB_APP" "$BUNDLE_DIR/lib/libapp.so"
  echo " -> Compilação AOT atualizada: $BUNDLE_DIR/lib/libapp.so"
fi

# 2. Injeta o binário do Tor
if [ -f "$LOCAL_BUNDLE/tor" ]; then
  cp -f "$LOCAL_BUNDLE/tor" "$BUNDLE_DIR/tor"
  chmod 0755 "$BUNDLE_DIR/tor"
  echo " -> Binário tor embutido no bundle: $BUNDLE_DIR/tor"
fi

# 3. Sincroniza bundle completo compilado para ~/.local/share/nix/bundle/
cp -rf "$BUNDLE_DIR/"* "$LOCAL_BUNDLE/"
chmod 0755 "$LOCAL_BUNDLE/nix_client" "$LOCAL_BUNDLE/tor"

echo "=== Bundle perfeitamente sincronizado para $LOCAL_BUNDLE ==="
