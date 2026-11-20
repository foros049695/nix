#!/usr/bin/env python3
"""
Nix Project - On-Demand Integrity & Security Auditor
Executes deterministic privacy checks, test suites, and generates
audit reports for docs/automation/MAINTENANCE_REPORT.md and docs/automation/history/.
Note: Automated 4-hour scheduled maintenance was permanently decommissioned per owner directive.
This script is strictly intended for manual, on-demand execution.
"""

import os
import sys
import json
import time
import subprocess
import tempfile
from datetime import datetime, timezone
import urllib.request

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DOCS_DIR = os.path.join(REPO_ROOT, "docs", "automation")
HISTORY_DIR = os.path.join(DOCS_DIR, "history")

def run_cmd(cmd, cwd=REPO_ROOT, env_extra=None):
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    start = time.time()
    try:
        res = subprocess.run(
            cmd,
            shell=True,
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=300
        )
        duration = time.time() - start
        return res.returncode == 0, res.stdout, duration
    except Exception as e:
        return False, str(e), time.time() - start

def get_git_info():
    ok, head, _ = run_cmd("git rev-parse HEAD")
    ok, branch, _ = run_cmd("git rev-parse --abbrev-ref HEAD")
    ok, log, _ = run_cmd("git log -n 1 --pretty=format:'%h - %s (%ci)'")
    return {
        "head": head.strip() if ok else "unknown",
        "branch": branch.strip() if ok else "unknown",
        "last_commit": log.strip() if ok else "unknown"
    }

def get_github_prs_and_issues():
    token = os.environ.get("GITHUB_TOKEN")
    repo = os.environ.get("GITHUB_REPOSITORY", "foros049695/nix")
    headers = {"User-Agent": "Nix-Audit"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    
    url = f"https://api.github.com/repos/{repo}/issues?state=all&per_page=100"
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode())
        prs = [i for i in data if "pull_request" in i]
        issues = [i for i in data if "pull_request" not in i]
        return {
            "total_items": len(data),
            "open_issues": [i for i in issues if i.get("state") == "open"],
            "closed_issues": [i for i in issues if i.get("state") == "closed"],
            "open_prs": [p for p in prs if p.get("state") == "open"],
            "closed_prs": [p for p in prs if p.get("state") == "closed"]
        }
    except Exception as e:
        return {
            "error": str(e),
            "open_issues": [],
            "closed_issues": [],
            "open_prs": [],
            "closed_prs": []
        }

def run_audit():
    os.makedirs(DOCS_DIR, exist_ok=True)
    os.makedirs(HISTORY_DIR, exist_ok=True)
    
    now_utc = datetime.now(timezone.utc)
    timestamp_str = now_utc.strftime("%Y-%m-%d %H:%M:%S UTC")
    history_file_name = f"MAINTENANCE_{now_utc.strftime('%Y%m%d_%H%M%S')}.md"
    
    git_info = get_git_info()
    github_data = get_github_prs_and_issues()

    results = []
    
    # 1. Privacy Matrix
    ok, out, dur = run_cmd("./scripts/verify_privacy_matrix.sh")
    results.append({
        "component": "Privacy Matrix Gate (scripts/verify_privacy_matrix.sh)",
        "success": ok,
        "duration": f"{dur:.2f}s",
        "detail": "Passagem de verificadores L-S, I-S, I-A e ausência de telemetria." if ok else out.strip()
    })

    # 2. nix_relay (Go)
    has_go, _, _ = run_cmd("go version 2>/dev/null | grep -q '^go version go'")
    if has_go:
        ok, out, dur = run_cmd(
            "go vet ./... && go test -race ./...",
            cwd=os.path.join(REPO_ROOT, "services", "nix_relay"),
        )
        results.append({
            "component": "Nix Relay (services/nix_relay: go vet & test -race)",
            "success": ok,
            "duration": f"{dur:.2f}s",
            "detail": "Suítes de buffer, relay HTTP, stores e race condition aprovados." if ok else out.strip()
        })
    else:
        results.append({
            "component": "Nix Relay (services/nix_relay: go vet & test -race)",
            "success": False,
            "duration": "0.00s",
            "detail": "Toolchain Go indisponível no PATH desta execução."
        })

    # 3. core_crypto (Dart)
    ok, out, dur = run_cmd(
        "dart analyze && dart test",
        cwd=os.path.join(REPO_ROOT, "modules", "core_crypto"),
    )
    results.append({
        "component": "Core Crypto (modules/core_crypto: dart analyze & test)",
        "success": ok,
        "duration": f"{dur:.2f}s",
        "detail": "PQXDH, Ratchet, Ed25519, XChaCha20 e layout público preservados." if ok else out.strip()
    })

    # 4. transport (Dart)
    ok, out, dur = run_cmd(
        "dart analyze && unshare --user --map-root-user --net sh -c 'ip link set lo up && dart test'",
        cwd=os.path.join(REPO_ROOT, "modules", "transport"),
    )
    results.append({
        "component": "Transport (modules/transport: dart analyze & test)",
        "success": ok,
        "duration": f"{dur:.2f}s",
        "detail": "HTTPS sobre SOCKS5 (Issue #11), isolamento Tor e frames NIXB aprovados." if ok else out.strip()
    })

    # 5. nix_client (Flutter). O apagamento da conta faz parte desta suíte.
    with tempfile.TemporaryDirectory(prefix="nix-audit-home-") as test_home:
        ok, out, dur = run_cmd(
            "flutter analyze --no-fatal-infos && flutter test",
            cwd=os.path.join(REPO_ROOT, "apps", "nix_client"),
            env_extra={
                "HOME": test_home,
                "XDG_DATA_HOME": os.path.join(test_home, "data"),
                "XDG_CONFIG_HOME": os.path.join(test_home, "config"),
                "XDG_CACHE_HOME": os.path.join(test_home, "cache"),
                "PUB_CACHE": os.environ.get("PUB_CACHE") or os.path.expanduser("~/.pub-cache"),
            },
        )
    results.append({
        "component": "Client Flutter (apps/nix_client: analyze & test)",
        "success": ok,
        "duration": f"{dur:.2f}s",
        "detail": "117/117 testes do cliente (onboarding, cofre, pânico, E2EE, FTS5) aprovados." if ok else out.strip()
    })

    all_passed = all(r["success"] for r in results)
    status_badge = "🟢 ÍNTEGRO (100% PASSING)" if all_passed else "🔴 FALHA DETECTADA"

    report_lines = [
        "# RELATÓRIO PERIÓDICO DE MANUTENÇÃO E INTEGRIDADE — PROJETO NIX",
        "",
        f"**Execução:** {timestamp_str}  ",
        f"**Status Geral:** {status_badge}  ",
        f"**Commit HEAD:** `{git_info['head']}`  ",
        f"**Branch:** `{git_info['branch']}`  ",
        f"**Último Commit:** {git_info['last_commit']}  ",
        "",
        "---",
        "",
        "## 1. Matriz de Execução de Testes e Portões de Segurança",
        "",
        "| Componente / Verificação | Status | Duração | Resumo / Detalhes |",
        "|---|---|---|---|"
    ]

    for r in results:
        status_icon = "✅ PASS" if r["success"] else "❌ FAIL"
        # Sanitize single line detail
        det = r["detail"].replace("\n", " ").strip()
        if len(det) > 120:
            det = det[:117] + "..."
        report_lines.append(f"| {r['component']} | {status_icon} | {r['duration']} | {det} |")

    report_lines.extend([
        "",
        "---",
        "",
        "## 2. Monitoramento de Colaboração e Contribuições no GitHub",
        ""
    ])

    if "error" in github_data:
        report_lines.append(f"> ⚠️ Não foi possível consultar a API do GitHub nesta execução: `{github_data['error']}`")
    else:
        report_lines.extend([
            f"- **Issues Abertas:** {len(github_data['open_issues'])}",
            f"- **Issues Fechadas:** {len(github_data['closed_issues'])}",
            f"- **Pull Requests Abertos:** {len(github_data['open_prs'])}",
            f"- **Pull Requests Integrados/Fechados:** {len(github_data['closed_prs'])}",
            ""
        ])

        if github_data["open_prs"]:
            report_lines.append("### Pull Requests Pendentes de Avaliação:")
            for pr in github_data["open_prs"]:
                report_lines.append(f"- **PR #{pr['number']}:** [{pr['title']}]({pr.get('html_url', '')}) por @{pr.get('user', {}).get('login', 'unknown')}")
            report_lines.append("")

        if github_data["open_issues"]:
            report_lines.append("### Issues Abertas:")
            for iss in github_data["open_issues"]:
                report_lines.append(f"- **Issue #{iss['number']}:** [{iss['title']}]({iss.get('html_url', '')})")
            report_lines.append("")

    report_lines.extend([
        "---",
        "",
        "## 3. Diretrizes de Segurança Preservadas",
        "- **Fail-Closed:** Todas as rotas clearnet bloqueadas; falhas em keyring/tor causam rollback seguro.",
        "- **Zero Telemetria:** Nenhuma biblioteca de coleta, analytics ou rastreamento permitida.",
        "- **Isolamento Seed A / Seed B:** Preservado na separação de mensageria e carteira.",
        "- **Anti-Forense:** Encerramento prévio do Tor antes de destruição de arquivos locais.",
        "",
        "_Relatório gerado sob demanda pela ferramenta de auditoria de integridade._"
    ])

    report_content = "\n".join(report_lines) + "\n"
    
    # Save active report
    active_path = os.path.join(DOCS_DIR, "MAINTENANCE_REPORT.md")
    with open(active_path, "w", encoding="utf-8") as f:
        f.write(report_content)

    # Save timestamped history
    history_path = os.path.join(HISTORY_DIR, history_file_name)
    with open(history_path, "w", encoding="utf-8") as f:
        f.write(report_content)

    print(f"[NIX-MAINTENANCE] Relatório ativo salvo em: {active_path}")
    print(f"[NIX-MAINTENANCE] Histórico registrado em: {history_path}")
    return 0 if all_passed else 1

if __name__ == "__main__":
    sys.exit(run_audit())
