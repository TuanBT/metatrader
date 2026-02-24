#!/usr/bin/env python3
"""
Backtest: Expert Grid USDJPY — Remote MT5 via SSH
==================================================
Uploads, compiles, and backtests the Grid EA on the remote VPS.

Usage:
    python bt_grid_usdjpy.py

SSH credentials are read from environment:
    MT5_SSH_PASS  (default: hardcoded in config block below)
"""

import subprocess
import time
import os
import re
import sys
from datetime import datetime

# ============================================================================
# CONFIG
# ============================================================================
SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")

MT5_EXE    = r"C:\Program Files\MetaTrader 5 EXNESS\terminal64.exe"
MT5_EDITOR = r"C:\Program Files\MetaTrader 5 EXNESS\MetaEditor64.exe"
MT5_DATA   = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"

LOCAL_MQL5 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCAL_EA   = os.path.join(LOCAL_MQL5, "MQL5", "Grid USDJPY", "Expert Grid USDJPY.mq5")

REMOTE_EA_DIR  = f"{MT5_DATA}\\MQL5\\Experts\\metatrader\\MQL5\\Grid USDJPY"
REMOTE_EA_FILE = f"{REMOTE_EA_DIR}\\Expert Grid USDJPY.mq5"
REMOTE_EA_PATH = r"Experts\metatrader\MQL5\Grid USDJPY\Expert Grid USDJPY"  # relative to MQL5\

DEPOSIT  = 1000
LEVERAGE = "1:100"
MODEL    = 1  # 1 = 1-minute OHLC (fast, accurate enough)

# ============================================================================
# BACKTEST VARIANTS — edit these to test different configs
# ============================================================================
TESTS = [
    # (label, symbol, period, from, to, extra_params)
    ("Grid_USDJPY_M15_RR1",  "USDJPYm", "M15", "2024.01.01", "2025.12.31", {
        "InpGridStep": 50, "InpGridTP": 50, "InpMaxLevels": 5,
        "InpMaxLossPct": 8.0, "InpRiskPctPerLevel": 0.5,
    }),
    ("Grid_USDJPY_M15_RR2",  "USDJPYm", "M15", "2024.01.01", "2025.12.31", {
        "InpGridStep": 80, "InpGridTP": 80, "InpMaxLevels": 5,
        "InpMaxLossPct": 8.0, "InpRiskPctPerLevel": 0.5,
    }),
    ("Grid_USDJPY_M15_RR3",  "USDJPYm", "M15", "2024.01.01", "2025.12.31", {
        "InpGridStep": 50, "InpGridTP": 100, "InpMaxLevels": 3,
        "InpMaxLossPct": 6.0, "InpRiskPctPerLevel": 0.3,
    }),
]

# ============================================================================
# SSH / SCP HELPERS
# ============================================================================
def ssh_cmd(command, timeout=60):
    full_cmd = [
        "sshpass", "-p", SSH_PASS,
        "ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=15",
        f"{SSH_USER}@{SSH_HOST}", command
    ]
    try:
        result = subprocess.run(full_cmd, capture_output=True, text=True, timeout=timeout)
        return result.stdout.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "TIMEOUT", -1

def scp_upload(local_path, remote_path):
    full_cmd = [
        "sshpass", "-p", SSH_PASS,
        "scp", "-o", "StrictHostKeyChecking=no",
        local_path, f"{SSH_USER}@{SSH_HOST}:{remote_path}"
    ]
    result = subprocess.run(full_cmd, capture_output=True, text=True, timeout=30)
    return result.returncode == 0

def scp_download(remote_path, local_path):
    full_cmd = [
        "sshpass", "-p", SSH_PASS,
        "scp", "-o", "StrictHostKeyChecking=no",
        f"{SSH_USER}@{SSH_HOST}:{remote_path}", local_path
    ]
    result = subprocess.run(full_cmd, capture_output=True, text=True, timeout=30)
    return result.returncode == 0

# ============================================================================
# MT5 HELPERS
# ============================================================================
def kill_mt5():
    ssh_cmd('taskkill /f /im terminal64.exe 2>nul')
    time.sleep(3)

def is_mt5_running():
    out, _ = ssh_cmd('tasklist /fi "IMAGENAME eq terminal64.exe" /nh 2>nul')
    return "terminal64.exe" in out.lower()

def upload_ea():
    """Upload .mq5 source to remote server"""
    print("  📤 Uploading EA source...")
    ssh_cmd(f'mkdir "{REMOTE_EA_DIR}" 2>nul')
    ok = scp_upload(LOCAL_EA, REMOTE_EA_FILE.replace("\\", "/").replace("C:/", "C:\\"))
    # Use Windows path for scp
    remote_scp = f"{SSH_USER}@{SSH_HOST}:{REMOTE_EA_FILE}"
    ok = scp_upload(LOCAL_EA, remote_scp.split("@")[1].replace(":", ":/", 1))
    if not ok:
        # Try with raw remote path
        full_cmd = [
            "sshpass", "-p", SSH_PASS,
            "scp", "-o", "StrictHostKeyChecking=no",
            LOCAL_EA,
            f"{SSH_USER}@{SSH_HOST}:{REMOTE_EA_FILE}"
        ]
        result = subprocess.run(full_cmd, capture_output=True, text=True, timeout=30)
        ok = result.returncode == 0
    print(f"  {'✅' if ok else '❌'} Upload {'OK' if ok else 'FAILED'}")
    return ok

def compile_ea():
    """Compile EA via MetaEditor CLI"""
    print("  🔨 Compiling EA...")
    cmd = (
        f'"{MT5_EDITOR}" /compile:"{REMOTE_EA_FILE}" /log & '
        f'timeout /t 8 /nobreak >nul & '
        f'type "{REMOTE_EA_FILE.replace(".mq5", ".log")}" 2>nul'
    )
    out, _ = ssh_cmd(cmd, timeout=40)

    errors   = 0
    warnings = 0
    m = re.search(r'(\d+) errors?, (\d+) warnings?', out)
    if m:
        errors, warnings = int(m.group(1)), int(m.group(2))

    if errors == 0:
        print(f"  ✅ Compiled OK (warnings={warnings})")
    else:
        print(f"  ❌ Compile errors={errors}:")
        print(out[-1000:])
    return errors == 0

def write_ini(label, symbol, period, from_date, to_date, params):
    """Write Strategy Tester INI to remote server"""
    ini_path   = f"{MT5_DATA}\\tester\\grid_test.ini"
    report_dir = f"{MT5_DATA}\\reports"
    ssh_cmd(f'mkdir "{report_dir}" 2>nul')

    # Build inputs section
    inputs_str = ""
    for k, v in params.items():
        inputs_str += f"{k}={v}\n"

    ini_content = f"""[Tester]
Expert={REMOTE_EA_PATH}
Symbol={symbol}
Period={period}
Model={MODEL}
Optimization=0
FromDate={from_date}
ToDate={to_date}
Report={report_dir}\\{label}
ReplaceReport=1
ShutdownTerminal=1
Deposit={DEPOSIT}
Leverage={LEVERAGE}
ExecutionMode=0
Inputs={inputs_str}"""

    # Write INI line by line
    lines = ini_content.strip().replace("\r", "").split("\n")
    for i, line in enumerate(lines):
        op = ">" if i == 0 else ">>"
        escaped = line.replace('"', '\\"').strip()
        ssh_cmd(f'echo {escaped} {op} "{ini_path}"')

    # Verify
    out, _ = ssh_cmd(f'type "{ini_path}" 2>nul')
    ok = "[Tester]" in out
    print(f"  {'✅' if ok else '❌'} INI written ({len(lines)} lines)")
    return ok, ini_path

def run_backtest_and_wait(ini_path, label, timeout_s=600):
    """Launch MT5 with INI and wait for completion"""
    kill_mt5()
    time.sleep(2)

    print(f"  🚀 Starting MT5 backtest...")
    ssh_cmd(f'start "" "{MT5_EXE}" /config:"{ini_path}"', timeout=10)
    time.sleep(8)

    start = time.time()
    while time.time() - start < timeout_s:
        if not is_mt5_running():
            elapsed = int(time.time() - start)
            print(f"  ✅ MT5 exited — done in {elapsed}s")
            return True
        time.sleep(10)

    print(f"  ⚠️  Timeout after {timeout_s}s — MT5 still running")
    kill_mt5()
    return False

def fetch_log(label):
    """Download result log from remote to local logs/"""
    log_dir = os.path.join(LOCAL_MQL5, "MQL5", "Grid USDJPY", "logs")
    os.makedirs(log_dir, exist_ok=True)

    # MT5 tester log is in MT5_DATA\logs\YYYYMMDD.log
    today = datetime.now().strftime("%Y%m%d")
    remote_log = f"{MT5_DATA}\\logs\\{today}.log"
    local_log  = os.path.join(log_dir, f"{label}_{today}.log")

    ok = scp_download(remote_log, local_log)
    if ok:
        print(f"  📥 Log saved: MQL5/Grid USDJPY/logs/{label}_{today}.log")
    else:
        print(f"  ⚠️  Log download failed (may not exist yet)")
    return local_log if ok else None

# ============================================================================
# MAIN
# ============================================================================
def main():
    print("=" * 60)
    print("  Expert Grid USDJPY — Remote Backtest")
    print(f"  Server: {SSH_HOST}")
    print(f"  Tests:  {len(TESTS)}")
    print("=" * 60)

    # Check SSH connectivity
    out, code = ssh_cmd("echo PONG")
    if "PONG" not in out:
        print("❌ Cannot connect to SSH server. Check VPN/credentials.")
        sys.exit(1)
    print("✅ SSH connected\n")

    # Upload + compile once
    if not upload_ea():
        print("❌ Upload failed. Aborting.")
        sys.exit(1)
    if not compile_ea():
        print("❌ Compile failed. Aborting.")
        sys.exit(1)
    print()

    results = []
    for label, symbol, period, from_d, to_d, params in TESTS:
        print(f"[{label}]")
        ok, ini_path = write_ini(label, symbol, period, from_d, to_d, params)
        if not ok:
            print("  ❌ INI write failed, skipping\n")
            continue

        success = run_backtest_and_wait(ini_path, label)
        log_path = fetch_log(label)
        results.append({
            "label": label, "symbol": symbol, "period": period,
            "params": params, "success": success, "log": log_path
        })
        print()

    # Summary
    print("=" * 60)
    print("  RESULTS SUMMARY")
    print("=" * 60)
    for r in results:
        status = "✅" if r["success"] else "❌"
        step = r["params"].get("InpGridStep", "?")
        tp   = r["params"].get("InpGridTP", "?")
        maxl = r["params"].get("InpMaxLevels", "?")
        print(f"  {status} {r['label']:<35} Step={step}pts TP={tp}pts MaxLvl={maxl}")

    print(f"\nLogs saved to: MQL5/Grid USDJPY/logs/")
    print("Run analyze script to see P&L results from logs.")

if __name__ == "__main__":
    main()
