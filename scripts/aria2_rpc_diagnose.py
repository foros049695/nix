#!/usr/bin/env python3
"""
Nix Project - Aria2 RPC Diagnostic Tool
Audits and queries the local aria2c JSON-RPC daemon safely.
Prevents HTTP 400 Bad Request by enforcing:
  1. POST method to /jsonrpc
  2. Header Content-Type: application/json
  3. Explicit Content-Length
  4. Correct 'token:<secret>' parameter passing
  5. Redaction of sensitive tokens in all logs and outputs.
"""

import sys
import os
import json
import argparse
import urllib.request
import urllib.error

DEFAULT_RPC_FILE = os.path.expanduser("~/.local/share/nix/aria2_rpc.json")

def load_rpc_credentials(rpc_file=DEFAULT_RPC_FILE):
    if os.path.exists(rpc_file):
        try:
            with open(rpc_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data.get("port"), data.get("token"), data.get("pid")
        except Exception as e:
            print(f"[!] Aviso: Falha ao ler {rpc_file}: {e}", file=sys.stderr)
    return None, None, None

def rpc_call(port, token, method, params=None):
    if params is None:
        params = []
    
    # Prepend token if secret is configured
    full_params = []
    if token:
        full_params.append(f"token:{token}")
    full_params.extend(params)
    
    url = f"http://127.0.0.1:{port}/jsonrpc"
    payload = {
        "jsonrpc": "2.0",
        "id": f"diag_{os.getpid()}",
        "method": method,
        "params": full_params
    }
    
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Content-Length": str(len(data))
        }
    )
    
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body)
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        return {
            "error": {
                "http_status": e.code,
                "reason": e.reason,
                "body": err_body
            }
        }
    except Exception as e:
        return {"error": {"message": str(e)}}

def main():
    parser = argparse.ArgumentParser(description="Projeto Nix - Aria2 RPC Diagnóstico Seguro")
    parser.add_argument("--port", type=int, help="Porta RPC do aria2c (ex: 6800)")
    parser.add_argument("--token", type=str, help="Token secreto RPC")
    parser.add_argument("--rpc-file", type=str, default=DEFAULT_RPC_FILE, help="Caminho do arquivo com credenciais RPC")
    parser.add_argument("--gid", type=str, help="Consultar tarefa específica por GID")
    args = parser.parse_args()

    port = args.port
    token = args.token
    pid = None

    if not port or not token:
        f_port, f_token, f_pid = load_rpc_credentials(args.rpc_file)
        if not port:
            port = f_port
        if not token:
            token = f_token
        pid = f_pid

    if not port:
        print("[ERRO] Porta RPC não fornecida e arquivo de sessão não encontrado.")
        print(f"Verifique se o Nix está em execução ou passe --port e --token explicitamente.")
        sys.exit(1)

    print("===============================================================")
    print("      PROJETO NIX — AUDITORIA TÉCNICA DO ARIA2 RPC             ")
    print("===============================================================")
    print(f"Alvo RPC: http://127.0.0.1:{port}/jsonrpc")
    if pid:
        print(f"Daemon PID: {pid}")
    print(f"Token RPC: [PROTEGIDO/REDACTED] ({len(token) if token else 0} caracteres)")
    print("")

    # 1. aria2.getVersion
    print("--- [1] TESTE DE COMUNICAÇÃO: aria2.getVersion ---")
    ver_res = rpc_call(port, token, "aria2.getVersion")
    if "error" in ver_res:
        print(f"[FALHA] Erro na consulta RPC:")
        print(json.dumps(ver_res["error"], indent=2))
        print("\nPossíveis causas:")
        print("1. O token RPC informado não corresponde ao token configurado no daemon.")
        print("2. A porta informada não está escutando o daemon aria2c.")
        print("3. O daemon foi encerrado ou caiu.")
        sys.exit(2)
    else:
        res = ver_res.get("result", {})
        print(f"Status: OK (HTTP 200)")
        print(f"Versão do aria2: {res.get('version')}")
        features = res.get("enabledFeatures", [])
        print(f"Recursos Ativados: {', '.join(features)}")
    print("")

    # 2. aria2.getGlobalOption (Audit real runtime options)
    print("--- [2] OPÇÕES GLOBAIS EM TEMPO DE EXECUÇÃO (AUDIT) ---")
    opt_res = rpc_call(port, token, "aria2.getGlobalOption")
    if "result" in opt_res:
        opts = opt_res["result"]
        critical_keys = [
            "split",
            "max-connection-per-server",
            "min-split-size",
            "piece-length",
            "timeout",
            "connect-timeout",
            "retry-wait",
            "max-tries",
            "lowest-speed-limit",
            "max-download-limit",
            "max-overall-download-limit",
            "max-concurrent-downloads",
            "file-allocation",
            "disk-cache",
            "continue",
            "enable-dht",
            "enable-peer-exchange",
            "follow-torrent",
            "follow-metalink",
            "all-proxy",
            "dir"
        ]
        for k in critical_keys:
            val = opts.get(k, "[NÃO DEFINIDO / DEFAULT]")
            print(f"  • {k:28}: {val}")
    else:
        print(f"[!] Falha ao obter opções globais: {opt_res.get('error')}")
    print("")

    # 3. aria2.getGlobalStat
    print("--- [3] ESTATÍSTICAS GLOBAIS: aria2.getGlobalStat ---")
    stat_res = rpc_call(port, token, "aria2.getGlobalStat")
    if "result" in stat_res:
        stats = stat_res["result"]
        down_speed = int(stats.get("downloadSpeed", 0))
        up_speed = int(stats.get("uploadSpeed", 0))
        print(f"  Velocidade Download Global: {down_speed / (1024*1024):.2f} MB/s ({down_speed} B/s)")
        print(f"  Velocidade Upload Global  : {up_speed / (1024*1024):.2f} MB/s")
        print(f"  Downloads Ativos          : {stats.get('numActive')}")
        print(f"  Downloads em Espera       : {stats.get('numWaiting')}")
        print(f"  Downloads Parados         : {stats.get('numStopped')}")
    print("")

    # 4. aria2.tellActive
    print("--- [4] TAREFAS ATIVAS: aria2.tellActive ---")
    active_res = rpc_call(port, token, "aria2.tellActive")
    active_tasks = active_res.get("result", [])
    if not active_tasks:
        print("  Nenhuma tarefa ativa no momento.")
    else:
        for t in active_tasks:
            gid = t.get("gid")
            status = t.get("status")
            total = int(t.get("totalLength", 0))
            completed = int(t.get("completedLength", 0))
            speed = int(t.get("downloadSpeed", 0))
            conns = t.get("connections", "0")
            num_pieces = t.get("numPieces", "0")
            piece_length = t.get("pieceLength", "0")
            files = t.get("files", [])
            path = files[0].get("path") if files else "N/A"
            uris = files[0].get("uris", []) if files else []
            uri = uris[0].get("uri") if uris else "N/A"
            
            prog = (completed / total * 100) if total > 0 else 0
            print(f"  GID: {gid}")
            print(f"    Arquivo: {path}")
            print(f"    Origem : {uri}")
            print(f"    Estado : {status}")
            print(f"    Progresso: {completed/(1024*1024):.1f} MB / {total/(1024*1024):.1f} MB ({prog:.1f}%)")
            print(f"    Velocidade: {speed/(1024*1024):.2f} MB/s ({speed} B/s)")
            print(f"    Conexões Reais Estabelecidas: {conns}")
            print(f"    Número de Peças: {num_pieces} (Tamanho da peça: {int(piece_length)/(1024*1024):.1f} MB)")
            print("")

    if args.gid:
        print(f"--- [5] DETALHES DO GID: {args.gid} ---")
        g_status = rpc_call(port, token, "aria2.tellStatus", [args.gid])
        g_opts = rpc_call(port, token, "aria2.getOption", [args.gid])
        print("Status do GID:")
        print(json.dumps(g_status.get("result", g_status.get("error")), indent=2))
        print("Opções Específicas do GID:")
        print(json.dumps(g_opts.get("result", g_opts.get("error")), indent=2))

    print("===============================================================")
    print("Auditoria RPC concluída com sucesso (sem HTTP 400).")
    print("===============================================================")

if __name__ == "__main__":
    main()
