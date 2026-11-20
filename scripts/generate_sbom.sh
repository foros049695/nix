#!/usr/bin/env bash
# Gera SBOM CycloneDX 1.5 JSON reproduzível das dependências Go, Dart e Flutter do Projeto Nix (Fase 9).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_FILE="${1:-$ROOT_DIR/dist/sbom.cdx.json}"
mkdir -p "$(dirname "$OUT_FILE")"

python3 - "$ROOT_DIR" "$OUT_FILE" <<'PY'
import json, pathlib, re, sys, uuid

root = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
components = []

# 1. Go module dependencies (services/nix_relay/go.mod)
go_mod = root / "services/nix_relay/go.mod"
if go_mod.exists():
    in_require = False
    for line in go_mod.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line == "require (":
            in_require = True
            continue
        if in_require and line == ")":
            in_require = False
            continue
        if not in_require:
            if not line.startswith("require "):
                continue
            line = line.removeprefix("require ").lstrip()
        m = re.match(r'^([^\s/]+/[^\s]+)\s+(v[0-9A-Za-z.\-+]+)', line)
        if m:
            name, ver = m.group(1), m.group(2)
            components.append({
                "type": "library",
                "name": name,
                "version": ver,
                "purl": f"pkg:golang/{name}@{ver}",
                "scope": "required"
            })

# 2. Dart / Flutter dependencies from pubspec.lock files
for lock_rel in ["modules/core_crypto/pubspec.lock", "modules/transport/pubspec.lock", "apps/nix_client/pubspec.lock"]:
    lock_file = root / lock_rel
    if not lock_file.exists():
        continue
    cur_pkg = None
    in_packages = False
    for raw in lock_file.read_text(encoding="utf-8").splitlines():
        if raw.startswith("packages:"):
            in_packages = True
            continue
        if in_packages and not raw.startswith(" "):
            in_packages = False
        if not in_packages:
            continue
        m_pkg = re.match(r'^  ([a-zA-Z0-9_]+):$', raw)
        if m_pkg:
            cur_pkg = m_pkg.group(1)
            continue
        m_ver = re.match(r'^    version:\s*"([^"]+)"', raw)
        if m_ver and cur_pkg:
            ver = m_ver.group(1)
            purl = f"pkg:pub/{cur_pkg}@{ver}"
            if not any(c["purl"] == purl for c in components):
                components.append({
                    "type": "library",
                    "name": cur_pkg,
                    "version": ver,
                    "purl": purl,
                    "scope": "required"
                })
            cur_pkg = None

client_yaml = (root / "apps/nix_client/pubspec.yaml").read_text(encoding="utf-8")
client_version = re.search(r"^version:\s*(\S+)", client_yaml, re.MULTILINE)[1]
sorted_components = sorted(components, key=lambda component: component["purl"])
inventory = json.dumps([client_version, sorted_components], sort_keys=True)
sbom = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.5",
    "serialNumber": f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, inventory)}",
    "version": 1,
    "metadata": {
        "component": {
            "type": "application",
            "name": "projeto-nix",
            "version": client_version
        }
    },
    "components": sorted_components
}
out.write_text(json.dumps(sbom, indent=2) + "\n", encoding="utf-8")
print(f"SBOM CycloneDX 1.5 gravado em {out} ({len(components)} componentes)")
PY
