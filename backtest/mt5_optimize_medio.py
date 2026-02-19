#!/usr/bin/env python3
"""
MT5 MST Medio Parameter Optimization
Test different TP/SL/entry parameter combinations to find profitable config.
"""

import subprocess
import time
import re
import os
from datetime import datetime

# ============================================================================
# CONNECTION
# ============================================================================
SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")

MT5_DATA = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
AGENT_LOG_DIR = MT5_TESTER + r"\Agent-127.0.0.1-3000\logs"

DEPOSIT = 500
LEVERAGE = 100

EA_PATH = "MST Medio\\Expert MST Medio"
RESULTS_MD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "medio_optimization_results.md")

# ============================================================================
# VERIFICATION — Test optimized EAs on target pairs
# ============================================================================
VERIFY_MODE = True  # Set to True for verification of code changes

PARAM_SETS = [
    # MST Medio — now has ATR SL + 2.0R as DEFAULTS (code changed)
    {
        "name": "MST Medio (new defaults)",
        "ea": "MST Medio\\Expert MST Medio",
        "params": {}  # uses new defaults: ATR SL, TP 2.0R
    },
    # Reversal — now has SLBuffer 0.7 + MinSL 100 as DEFAULTS (code changed)
    {
        "name": "Reversal (new defaults)",
        "ea": "Reversal\\Expert Reversal",
        "params": {}  # uses new defaults
    },
]

SYMBOLS_PERIODS = [
    ("USDJPYm", "H1", "2024.01.01", "2025.01.01", "JPY H1 2024"),
    ("USDJPYm", "H1", "2025.01.01", "2026.02.01", "JPY H1 2025"),
    ("XAUUSDm", "H1", "2024.01.01", "2025.01.01", "XAU H1 2024"),
    ("XAUUSDm", "H1", "2025.01.01", "2026.02.01", "XAU H1 2025"),
    ("EURUSDm", "H1", "2024.01.01", "2025.01.01", "EUR H1 2024"),
    ("EURUSDm", "H1", "2025.01.01", "2026.02.01", "EUR H1 2025"),
]


# ============================================================================
# SSH helpers
# ============================================================================
def ssh(cmd, timeout=60):
    full = ["sshpass", "-p", SSH_PASS, "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=15",
            f"{SSH_USER}@{SSH_HOST}", cmd]
    try:
        r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return f"ERROR: {e}"


# ============================================================================
# MT5 operations
# ============================================================================
def kill_mt5():
    ssh('taskkill /f /im terminal64.exe 2>nul')
    time.sleep(3)

def mt5_running():
    out = ssh('tasklist /fi "IMAGENAME eq terminal64.exe" /nh 2>nul')
    return "terminal64.exe" in out.lower()

def get_server_date():
    out = ssh('powershell -Command "Get-Date -Format yyyyMMdd"')
    return out.strip() if out and len(out) == 8 else datetime.now().strftime("%Y%m%d")

def clear_agent_log(date_str):
    ssh(f'del "{AGENT_LOG_DIR}\\{date_str}.log" 2>nul')

def read_agent_log(date_str):
    """Read critical metrics from agent log using PowerShell (handles UTF-16)."""
    log_path = f"{AGENT_LOG_DIR}\\{date_str}.log"
    ps_cmd = (
        f"$log='{log_path}'; "
        f"if(-not(Test-Path $log)){{Write-Host 'NO_LOG_FILE'; exit}}; "
        f"$d=(Select-String $log -Pattern 'deal performed').Count; "
        f"$s=(Select-String $log -Pattern 'stop loss triggered').Count; "
        f"$t=(Select-String $log -Pattern 'take profit triggered').Count; "
        f"$b=(Select-String $log -Pattern 'SL moved to breakeven').Count; "
        f"$bal=(Select-String $log -Pattern 'final balance' | Select-Object -Last 1); "
        f"$fin=(Select-String $log -Pattern 'thread finished' | Select-Object -Last 1); "
        f"Write-Host \"DEALS=$d\"; "
        f"Write-Host \"SL=$s\"; "
        f"Write-Host \"TP=$t\"; "
        f"Write-Host \"BE=$b\"; "
        f"if($bal){{Write-Host $bal.Line}}; "
        f"if($fin){{Write-Host $fin.Line}}"
    )
    return ssh(f'powershell -Command "{ps_cmd}"', timeout=60)

def write_ini_on_server(symbol, period, from_date, to_date, custom_params=None, ea_path=None):
    """Write INI directly on server with optional custom parameters."""
    if ea_path is None:
        ea_path = EA_PATH
    ini_path = f"{MT5_DATA}\\tester\\backtest_auto.ini"
    lines = [
        f'echo [Tester] > "{ini_path}"',
        f'echo Expert={ea_path} >> "{ini_path}"',
        f'echo Symbol={symbol} >> "{ini_path}"',
        f'echo Period={period} >> "{ini_path}"',
        f'echo Model=1 >> "{ini_path}"',
        f'echo Optimization=0 >> "{ini_path}"',
        f'echo FromDate={from_date} >> "{ini_path}"',
        f'echo ToDate={to_date} >> "{ini_path}"',
        f'echo ReplaceReport=1 >> "{ini_path}"',
        f'echo ShutdownTerminal=1 >> "{ini_path}"',
        f'echo Deposit={DEPOSIT} >> "{ini_path}"',
        f'echo Currency=USD >> "{ini_path}"',
        f'echo Leverage={LEVERAGE} >> "{ini_path}"',
        f'echo [TesterInputs] >> "{ini_path}"',
        f'echo InpUseDynamicLot=false >> "{ini_path}"',
        f'echo InpLotSize=0.02 >> "{ini_path}"',
    ]
    # Add custom parameter overrides
    if custom_params:
        for key, val in custom_params.items():
            lines.append(f'echo {key}={val} >> "{ini_path}"')
    
    cmd = " && ".join(lines)
    out = ssh(cmd)
    return "ERROR" not in out.upper() if out else True

def launch_mt5():
    ini_path = f"{MT5_DATA}\\tester\\backtest_auto.ini"
    ssh(f'schtasks /delete /tn "MT5Backtest" /f 2>nul')
    ssh(f'schtasks /create /tn "MT5Backtest" /tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\" /config:\\"{ini_path}\\"" /sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5Backtest" 2>&1')

def wait_for_completion(max_wait=300):
    start = time.time()
    time.sleep(15)
    while time.time() - start < max_wait:
        if not mt5_running():
            time.sleep(5)
            return True
        time.sleep(5)
    kill_mt5()
    return False

def parse_results(log_text):
    """Parse structured output from PowerShell log reader."""
    result = {}
    
    if not log_text or "NO_LOG_FILE" in log_text:
        return {"error": "No log file"}
    
    test_finished = "thread finished" in log_text.lower()
    
    m = re.search(r'final balance\s+([\d.]+)\s+USD', log_text, re.IGNORECASE)
    if m:
        result["balance"] = float(m.group(1))
        result["profit"] = result["balance"] - DEPOSIT
        result["profit_pct"] = (result["profit"] / DEPOSIT) * 100
    elif test_finished:
        result["balance"] = float(DEPOSIT)
        result["profit"] = 0.0
        result["profit_pct"] = 0.0
    else:
        return {"error": "No results in log"}
    
    def get_count(key):
        m = re.search(rf'{key}=(\d+)', log_text)
        return int(m.group(1)) if m else 0
    
    result["deals"] = get_count("DEALS")
    result["sl_hits"] = get_count("SL")
    result["tp_hits"] = get_count("TP")
    result["breakevens"] = get_count("BE")
    
    return result

def run_single_test(symbol, period, from_date, to_date, custom_params, date_str, ea_path=None):
    """Run a single backtest and return results."""
    if mt5_running():
        kill_mt5()
    
    clear_agent_log(date_str)
    time.sleep(1)
    
    if not write_ini_on_server(symbol, period, from_date, to_date, custom_params, ea_path):
        return {"error": "INI write failed"}
    
    launch_mt5()
    time.sleep(8)
    
    # Wait for MT5 to start
    mt5_started = False
    for _ in range(5):
        if mt5_running():
            mt5_started = True
            break
        time.sleep(5)
    
    if not mt5_started:
        # Check if already finished (fast test)
        time.sleep(3)
        log = read_agent_log(date_str)
        if log and ("thread finished" in log.lower() or "final balance" in log.lower()):
            return parse_results(log)
        # One more retry
        launch_mt5()
        time.sleep(10)
        for _ in range(3):
            if mt5_running():
                mt5_started = True
                break
            time.sleep(5)
    
    if not mt5_started:
        time.sleep(5)
        log = read_agent_log(date_str)
        if log and ("thread finished" in log.lower() or "final balance" in log.lower()):
            return parse_results(log)
        return {"error": "MT5 failed to start"}
    
    completed = wait_for_completion(max_wait=300)
    if not completed:
        return {"error": "Timeout"}
    
    time.sleep(3)
    log = read_agent_log(date_str)
    result = parse_results(log)
    
    # Retry once
    if "error" in result:
        time.sleep(5)
        log = read_agent_log(date_str)
        result = parse_results(log)
    
    return result


def restart_mt5_normal():
    ssh('schtasks /delete /tn "MT5Backtest" /f 2>nul')
    ssh('schtasks /create /tn "MT5Start" /tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\"" /sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5Start" 2>&1')
    ssh('schtasks /delete /tn "MT5Start" /f 2>nul')


def generate_report(all_results):
    """Generate markdown report for optimization."""
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    
    lines = []
    lines.append("# MST Medio Parameter Optimization Results\n")
    lines.append(f"**Date:** {now}")
    lines.append(f"**EA:** MST Medio | **Deposit:** ${DEPOSIT:,} | **Leverage:** 1:{LEVERAGE} | **Lot:** 0.02\n")
    
    # Build header dynamically from symbol/period combos
    sp_labels = [sp[4] for sp in SYMBOLS_PERIODS]
    
    # Table header
    header = "| # | Config |"
    sep = "|---|--------|"
    for label in sp_labels:
        header += f" {label} |"
        sep += "------|"
    header += " Avg |"
    sep += "-----|"
    lines.append("## Results\n")
    lines.append(header)
    lines.append(sep)
    
    best_avg = -999
    best_config = ""
    
    for i, pset in enumerate(PARAM_SETS, 1):
        pname = pset["name"]
        row = f"| {i} | {pname} |"
        pcts = []
        
        for sp in SYMBOLS_PERIODS:
            key = (pname, sp[4])
            r = all_results.get(key, {})
            
            if "error" in r:
                row += " ❌ ERR |"
            else:
                pct = r.get("profit_pct", 0)
                pcts.append(pct)
                tp = r.get("tp_hits", 0)
                if pct > 0:
                    row += f" 🟢 {pct:+.1f}% (TP:{tp}) |"
                elif pct == 0:
                    row += f" ⚪ 0% (TP:{tp}) |"
                else:
                    row += f" 🔴 {pct:+.1f}% (TP:{tp}) |"
        
        if pcts:
            avg = sum(pcts) / len(pcts)
            if avg > best_avg:
                best_avg = avg
                best_config = pname
            if avg > 0:
                row += f" **{avg:+.1f}%** |"
            else:
                row += f" {avg:+.1f}% |"
        else:
            row += " N/A |"
        
        lines.append(row)
    
    # Summary
    lines.append(f"\n## Best Configuration\n")
    lines.append(f"**{best_config}** → Average: {best_avg:+.1f}%\n")
    
    # Detail per config
    lines.append("## Detailed Stats\n")
    lines.append("| Config | Symbol | Balance | P&L% | Deals | SL | TP | BE |")
    lines.append("|--------|--------|---------|------|-------|----|----|-----|")
    
    for pset in PARAM_SETS:
        pname = pset["name"]
        for sp in SYMBOLS_PERIODS:
            key = (pname, sp[4])
            r = all_results.get(key, {})
            if "error" not in r:
                bal = f"${r['balance']:,.2f}"
                pct = r['profit_pct']
                icon = "🟢" if pct > 0 else ("🔴" if pct < 0 else "⚪")
                lines.append(f"| {pname} | {sp[4]} | {bal} | {icon} {pct:+.2f}% | {r['deals']} | {r['sl_hits']} | {r['tp_hits']} | {r['breakevens']} |")
            else:
                lines.append(f"| {pname} | {sp[4]} | ERROR | ❌ | - | - | - | - |")
    
    # Parameters reference
    lines.append("\n## Parameter Reference\n")
    lines.append("| Config | Key Changes |")
    lines.append("|--------|-------------|")
    for pset in PARAM_SETS:
        params = pset["params"]
        if not params:
            changes = "All defaults"
        else:
            changes = ", ".join(f"`{k}={v}`" for k, v in params.items())
        lines.append(f"| {pset['name']} | {changes} |")
    
    report = "\n".join(lines) + "\n"
    
    with open(RESULTS_MD, "w") as f:
        f.write(report)
    
    return report


# ============================================================================
# MAIN
# ============================================================================
def main():
    total_tests = len(PARAM_SETS) * len(SYMBOLS_PERIODS)
    
    print("=" * 70)
    print("  MST MEDIO PARAMETER OPTIMIZATION")
    print("=" * 70)
    print(f"  Configs: {len(PARAM_SETS)} | Markets: {len(SYMBOLS_PERIODS)} | Total: {total_tests} tests")
    print(f"  Deposit: ${DEPOSIT:,} | Leverage: 1:{LEVERAGE}")
    print("=" * 70)
    
    # Test SSH
    print("\n🔌 Testing SSH...", end=" ", flush=True)
    out = ssh("echo OK")
    if "OK" not in out:
        print(f"❌ FAILED: {out}")
        return
    print("✅ Connected")
    
    date_str = get_server_date()
    print(f"📅 Server date: {date_str}")
    
    start_time = datetime.now()
    all_results = {}
    test_num = 0
    
    for pset in PARAM_SETS:
        pname = pset["name"]
        params = pset["params"]
        ea_path = pset.get("ea", EA_PATH)
        
        print(f"\n{'═'*70}")
        print(f"  📋 {pname}")
        if params:
            print(f"  Changes: {', '.join(f'{k}={v}' for k, v in params.items())}")
        print(f"{'═'*70}")
        
        for symbol, period, from_date, to_date, label in SYMBOLS_PERIODS:
            test_num += 1
            print(f"\n  [{test_num}/{total_tests}] {label}...", end=" ", flush=True)
            
            result = run_single_test(symbol, period, from_date, to_date, params, date_str, ea_path)
            all_results[(pname, label)] = result
            
            if "error" in result:
                print(f"❌ {result['error']}")
            else:
                pct = result["profit_pct"]
                icon = "🟢" if pct > 0 else ("🔴" if pct < 0 else "⚪")
                print(f"{icon} ${result['balance']:,.2f} ({pct:+.1f}%) | D:{result['deals']} SL:{result['sl_hits']} TP:{result['tp_hits']} BE:{result['breakevens']}")
    
    # Generate report
    duration = datetime.now() - start_time
    print(f"\n{'='*70}")
    print(f"  📝 Generating report... ({duration})")
    print(f"{'='*70}\n")
    
    report = generate_report(all_results)
    print(f"📄 Report saved to: {RESULTS_MD}")
    print(report)
    
    # Restart MT5
    print("\n🔄 Restarting MT5 normally...")
    restart_mt5_normal()
    
    print(f"\n✅ All done! Duration: {duration}")


if __name__ == "__main__":
    main()
