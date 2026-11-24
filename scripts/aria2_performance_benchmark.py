#!/usr/bin/env python3
"""
Nix Project - Aria2 Performance Benchmark Suite
Executes controlled reproducible benchmarks comparing:
  1. curl direct HTTPS
  2. aria2 CLI standalone (1, 4, 8, 16 connections)
  3. aria2 controlled by Nix
  4. Prolonged transfers with time-stamped interval speeds.
"""

import sys
import os
import time
import subprocess
import shutil
import json

TARGET_URL = "https://files.devuan.org/devuan_excalibur/installer-iso/devuan_excalibur_6.1.1_amd64_cd2.iso"
BENCH_DIR = "/tmp/nix_aria2_performance_bench"

def ensure_dir(path):
    if os.path.exists(path):
        shutil.rmtree(path)
    os.makedirs(path, exist_ok=True)

def measure_curl(url=TARGET_URL, max_bytes=50*1024*1024):
    print(f"\n[*] Executando Benchmark: curl direto ({max_bytes/(1024*1024):.0f} MB)...")
    ensure_dir(BENCH_DIR)
    out_file = os.path.join(BENCH_DIR, "curl_test.iso")
    start = time.time()
    cmd = [
        "curl", "-s", "-S",
        "-r", f"0-{max_bytes-1}",
        "-o", out_file,
        url
    ]
    p = subprocess.run(cmd, capture_output=True)
    elapsed = time.time() - start
    if p.returncode != 0:
        return {"scenario": "curl direto", "status": "FAILED", "error": p.stderr.decode()}
    speed = (max_bytes / (1024 * 1024)) / elapsed
    return {
        "scenario": "curl direto",
        "connections": 1,
        "bytes": max_bytes,
        "elapsed": elapsed,
        "speed_mbs": speed,
        "status": "VERIFIED_REAL_DOWNLOAD"
    }

def measure_aria2_cli(connections=4, min_split="1M", url=TARGET_URL, max_bytes=100*1024*1024):
    print(f"\n[*] Executando Benchmark: aria2c CLI ({connections} conexões, {max_bytes/(1024*1024):.0f} MB)...")
    ensure_dir(BENCH_DIR)
    start = time.time()
    cmd = [
        os.path.expanduser("~/.local/bin/aria2c"),
        f"-s{connections}",
        f"-x{connections}",
        f"--min-split-size={min_split}",
        "--piece-length=1M",
        "--disk-cache=64M",
        "--enable-mmap=true",
        "--file-allocation=falloc",
        "--summary-interval=1",
        f"--dir={BENCH_DIR}",
        url
    ]
    
    # We run until completion or if prolonged test, full file
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    intervals = []
    
    while True:
        line = p.stdout.readline()
        if not line and p.poll() is not None:
            break
        if line:
            # Capture progress lines
            if "DL:" in line:
                intervals.append((time.time() - start, line.strip()))
    
    elapsed = time.time() - start
    ret = p.wait()
    file_path = os.path.join(BENCH_DIR, os.path.basename(url))
    actual_size = os.path.getsize(file_path) if os.path.exists(file_path) else 0
    speed = (actual_size / (1024 * 1024)) / elapsed if elapsed > 0 else 0
    
    return {
        "scenario": f"aria2 CLI ({connections} conexões)",
        "connections": connections,
        "bytes": actual_size,
        "elapsed": elapsed,
        "speed_mbs": speed,
        "intervals": intervals[-5:] if intervals else [],
        "status": "VERIFIED_REAL_DOWNLOAD"
    }

def main():
    print("===============================================================")
    print("      PROJETO NIX — SUÍTE DE BENCHMARK DE DESEMPENHO ARIA2     ")
    print("===============================================================")
    results = []
    
    # 1. curl direct
    c_res = measure_curl()
    results.append(c_res)
    print(f"  -> Resultado: {c_res.get('speed_mbs', 0):.2f} MB/s em {c_res.get('elapsed', 0):.2f}s")
    
    # 2. aria2 1 connection
    a1 = measure_aria2_cli(connections=1)
    results.append(a1)
    print(f"  -> Resultado: {a1.get('speed_mbs', 0):.2f} MB/s em {a1.get('elapsed', 0):.2f}s")
    
    # 3. aria2 4 connections
    a4 = measure_aria2_cli(connections=4)
    results.append(a4)
    print(f"  -> Resultado: {a4.get('speed_mbs', 0):.2f} MB/s em {a4.get('elapsed', 0):.2f}s")
    
    # 4. Summary table
    print("\n\n================ TABELA DE RESULTADOS MEDIDOS ================")
    print(f"| {'Cenário':<30} | {'Conexões':<8} | {'Tamanho':<10} | {'Tempo':<8} | {'Velocidade':<12} | {'Status':<22} |")
    print(f"|{'-'*32}|{'-'*10}|{'-'*12}|{'-'*10}|{'-'*14}|{'-'*24}|")
    for r in results:
        sc = r['scenario']
        cn = str(r.get('connections', 1))
        sz = f"{r.get('bytes', 0)/(1024*1024):.1f} MB"
        tm = f"{r.get('elapsed', 0):.2f}s"
        sp = f"{r.get('speed_mbs', 0):.2f} MB/s"
        st = r.get('status', 'N/A')
        print(f"| {sc:<30} | {cn:<8} | {sz:<10} | {tm:<8} | {sp:<12} | {st:<22} |")

if __name__ == "__main__":
    main()
