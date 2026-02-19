#!/usr/bin/env python3
"""
MT5 Quick Backtest — Run a few tests and generate report MD
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

RESULTS_MD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "quick_backtest_results.md")

# ============================================================================
# QUICK TEST MATRIX — EURUSD focus, all strategies, multiple TFs
# ============================================================================
TESTS = [
    # (strategy, ea_path, symbol, period, from_date, to_date, period_label)
    # --- EURUSD H1 — All 4 strategies ---
    ("Reversal",   "Reversal\\Expert Reversal",   "EURUSDm", "H1",  "2024.01.01", "2025.01.01", "2024"),
    ("Reversal",   "Reversal\\Expert Reversal",   "EURUSDm", "H1",  "2025.01.01", "2026.02.01", "2025"),
    ("Breakout",   "Breakout\\Expert Breakout",   "EURUSDm", "H1",  "2024.01.01", "2025.01.01", "2024"),
    ("Breakout",   "Breakout\\Expert Breakout",   "EURUSDm", "H1",  "2025.01.01", "2026.02.01", "2025"),
    ("Scalper",    "Scalper\\Expert Scalper",     "EURUSDm", "H1",  "2024.01.01", "2025.01.01", "2024"),
    ("Scalper",    "Scalper\\Expert Scalper",     "EURUSDm", "H1",  "2025.01.01", "2026.02.01", "2025"),
    ("MST Medio",  "MST Medio\\Expert MST Medio", "EURUSDm", "H1",  "2024.01.01", "2025.01.01", "2024"),
    ("MST Medio",  "MST Medio\\Expert MST Medio", "EURUSDm", "H1",  "2025.01.01", "2026.02.01", "2025"),
    # --- EURUSD M15 — All 4 strategies ---
    ("Reversal",   "Reversal\\Expert Reversal",   "EURUSDm", "M15", "2024.01.01", "2025.01.01", "2024"),
    ("Reversal",   "Reversal\\Expert Reversal",   "EURUSDm", "M15", "2025.01.01", "2026.02.01", "2025"),
    ("Breakout",   "Breakout\\Expert Breakout",   "EURUSDm", "M15", "2024.01.01", "2025.01.01", "2024"),
    ("Breakout",   "Breakout\\Expert Breakout",   "EURUSDm", "M15", "2025.01.01", "2026.02.01", "2025"),
    ("Scalper",    "Scalper\\Expert Scalper",     "EURUSDm", "M15", "2024.01.01", "2025.01.01", "2024"),
    ("Scalper",    "Scalper\\Expert Scalper",     "EURUSDm", "M15", "2025.01.01", "2026.02.01", "2025"),
    ("MST Medio",  "MST Medio\\Expert MST Medio", "EURUSDm", "M15", "2024.01.01", "2025.01.01", "2024"),
    ("MST Medio",  "MST Medio\\Expert MST Medio", "EURUSDm", "M15", "2025.01.01", "2026.02.01", "2025"),
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
    """Read critical metrics from agent log using PowerShell (handles UTF-16 encoding).
    Returns a structured string with counts and key lines."""
    log_path = f"{AGENT_LOG_DIR}\\{date_str}.log"
    # Single PowerShell command to extract all needed metrics
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

def write_ini_on_server(ea_path, symbol, period, from_date, to_date):
    """Write INI directly on server via echo commands"""
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
        # Force fixed lot = 0.02
        f'echo [TesterInputs] >> "{ini_path}"',
        f'echo InpUseDynamicLot=false >> "{ini_path}"',
        f'echo InpLotSize=0.02 >> "{ini_path}"',
    ]
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
    time.sleep(15)  # More initial wait for startup + quick tests
    while time.time() - start < max_wait:
        if not mt5_running():
            time.sleep(5)  # Extra wait for log to be flushed
            return True
        time.sleep(5)
    kill_mt5()
    return False

def parse_results(log_text):
    """Parse structured output from read_agent_log PowerShell command"""
    result = {}
    
    if not log_text or "NO_LOG_FILE" in log_text:
        return {"error": "No log file"}
    
    # Check if test actually ran (thread finished)
    test_finished = "thread finished" in log_text.lower()
    
    # Final balance
    m = re.search(r'final balance\s+([\d.]+)\s+USD', log_text, re.IGNORECASE)
    if m:
        result["balance"] = float(m.group(1))
        result["profit"] = result["balance"] - DEPOSIT
        result["profit_pct"] = (result["profit"] / DEPOSIT) * 100
    elif test_finished:
        # Test ran but no final balance = 0 trades
        result["balance"] = float(DEPOSIT)
        result["profit"] = 0.0
        result["profit_pct"] = 0.0
    else:
        return {"error": "No results in log"}
    
    # Parse structured counts from PowerShell output
    def get_count(key):
        m = re.search(rf'{key}=(\d+)', log_text)
        return int(m.group(1)) if m else 0
    
    result["deals"] = get_count("DEALS")
    result["sl_hits"] = get_count("SL")
    result["tp_hits"] = get_count("TP")
    result["breakevens"] = get_count("BE")
    
    return result


def restart_mt5_normal():
    """Restart MT5 without config"""
    ssh('schtasks /delete /tn "MT5Backtest" /f 2>nul')
    ssh('schtasks /create /tn "MT5Start" /tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\"" /sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5Start" 2>&1')
    ssh('schtasks /delete /tn "MT5Start" /f 2>nul')


def generate_report(all_results):
    """Generate markdown report"""
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    
    lines = []
    lines.append("# MT5 Quick Backtest Results\n")
    lines.append(f"**Date:** {now}")
    lines.append(f"**Deposit:** ${DEPOSIT:,} | **Leverage:** 1:{LEVERAGE}")
    lines.append(f"**Total tests:** {len(all_results)}\n")
    
    # Results table
    lines.append("## Results\n")
    lines.append("| # | Strategy | Symbol | TF | Period | Balance | P&L | % | Deals | SL | TP | BE |")
    lines.append("|---|----------|--------|----|--------|---------|-----|---|-------|----|----|----|")
    
    for i, (test, result) in enumerate(all_results, 1):
        strategy, _, symbol, tf, _, _, period_label = test
        
        if "error" in result:
            lines.append(f"| {i} | {strategy} | {symbol} | {tf} | {period_label} | ERROR | ERROR | ❌ ERROR | 0 | 0 | 0 | 0 |")
        else:
            bal = f"${result['balance']:,.2f}"
            pnl = f"${result['profit']:+,.2f}"
            pct_val = result['profit_pct']
            if pct_val > 0:
                pct = f"🟢 +{pct_val:.2f}%"
            elif pct_val < 0:
                pct = f"🔴 {pct_val:.2f}%"
            else:
                pct = f"⚪ {pct_val:.2f}%"
            
            deals = result.get('deals', '?')
            sl = result.get('sl_hits', '?')
            tp = result.get('tp_hits', '?')
            be = result.get('breakevens', '?')
            lines.append(f"| {i} | {strategy} | {symbol} | {tf} | {period_label} | {bal} | {pnl} | {pct} | {deals} | {sl} | {tp} | {be} |")
    
    # Summary
    valid = [(t, r) for t, r in all_results if "error" not in r and r.get("balance")]
    if valid:
        lines.append("\n## Summary\n")
        
        profitable = [(t, r) for t, r in valid if r['profit_pct'] > 0]
        losing = [(t, r) for t, r in valid if r['profit_pct'] < 0]
        
        lines.append(f"- **Profitable:** {len(profitable)}/{len(valid)} ({len(profitable)/len(valid)*100:.0f}%)")
        lines.append(f"- **Losing:** {len(losing)}/{len(valid)}")
        
        avg_pnl = sum(r['profit_pct'] for _, r in valid) / len(valid)
        lines.append(f"- **Average P&L:** {avg_pnl:+.2f}%")
        
        best = max(valid, key=lambda x: x[1]['profit_pct'])
        worst = min(valid, key=lambda x: x[1]['profit_pct'])
        
        bt, br = best
        wt, wr = worst
        lines.append(f"\n### 🏆 Best: {bt[0]} {bt[2]} {bt[3]} → {br['profit_pct']:+.2f}%")
        lines.append(f"### 💀 Worst: {wt[0]} {wt[2]} {wt[3]} → {wr['profit_pct']:+.2f}%")
    
    errors = [(t, r) for t, r in all_results if "error" in r]
    if errors:
        lines.append(f"\n### ⚠️ Errors: {len(errors)}")
        for t, r in errors:
            lines.append(f"- {t[0]} {t[2]} {t[3]}: {r['error']}")
    
    report = "\n".join(lines) + "\n"
    
    with open(RESULTS_MD, "w") as f:
        f.write(report)
    
    return report


# ============================================================================
# MAIN
# ============================================================================
def main():
    print("=" * 70)
    print("  MT5 QUICK BACKTEST")
    print("=" * 70)
    print(f"  Server: {SSH_HOST}")
    print(f"  Tests:  {len(TESTS)}")
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
    all_results = []
    
    for i, test in enumerate(TESTS):
        strategy, ea_path, symbol, period, from_date, to_date, period_label = test
        test_name = f"{strategy} {symbol} {period} {period_label}"
        
        print(f"\n{'─'*70}")
        print(f"  [{i+1}/{len(TESTS)}] {test_name}")
        print(f"{'─'*70}")
        
        # Kill MT5 if running
        if mt5_running():
            print("  🔄 Killing MT5...", flush=True)
            kill_mt5()
        
        # Clear log
        clear_agent_log(date_str)
        time.sleep(1)
        
        # Write INI
        print("  📄 Writing config...", end=" ", flush=True)
        if write_ini_on_server(ea_path, symbol, period, from_date, to_date):
            print("✅")
        else:
            print("❌")
            all_results.append((test, {"error": "INI write failed"}))
            continue
        
        # Launch
        print("  🚀 Launching MT5...", end=" ", flush=True)
        launch_mt5()
        time.sleep(8)
        
        # Wait for MT5 to appear (may take time via Task Scheduler)
        mt5_started = False
        for attempt in range(5):
            if mt5_running():
                mt5_started = True
                print("✅ Running")
                break
            time.sleep(5)
        
        if not mt5_started:
            # One more retry - recreate and run task
            print("⏳ Retry...", end=" ", flush=True)
            launch_mt5()
            time.sleep(10)
            for attempt in range(3):
                if mt5_running():
                    mt5_started = True
                    print("✅ Running (retry)")
                    break
                time.sleep(5)
        
        if not mt5_started:
            # MT5 might have already started AND finished (very fast test)
            # Check if log has new content
            time.sleep(3)
            log_check = read_agent_log(date_str)
            if log_check and ("thread finished" in log_check.lower() or "final balance" in log_check.lower()):
                print("✅ Already finished (fast test)")
                result = parse_results(log_check)
                all_results.append((test, result))
                if result.get("balance"):
                    pct = result["profit_pct"]
                    sign = "+" if pct >= 0 else ""
                    print(f"  💰 Balance: ${result['balance']:,.2f} ({sign}{pct:.2f}%)")
                    print(f"  📊 Deals: {result['deals']} | SL: {result['sl_hits']} | TP: {result['tp_hits']} | BE: {result['breakevens']}")
                else:
                    print(f"  ❌ {result.get('error', 'Unknown')}")
                continue
            else:
                print("❌ MT5 not started")
                all_results.append((test, {"error": "MT5 failed to start"}))
                continue
        
        # Wait
        print("  ⏳ Waiting...", end=" ", flush=True)
        completed = wait_for_completion(max_wait=300)
        
        if not completed:
            print("⚠️ TIMEOUT")
            all_results.append((test, {"error": "Timeout"}))
            continue
        
        time.sleep(3)
        
        # Read results (with retry)
        log = read_agent_log(date_str)
        result = parse_results(log)
        
        # Retry if no results — log might not be flushed yet
        if "error" in result:
            time.sleep(5)
            log = read_agent_log(date_str)
            result = parse_results(log)
        
        all_results.append((test, result))
        
        if result.get("balance"):
            pct = result["profit_pct"]
            sign = "+" if pct >= 0 else ""
            print(f"✅ Done!")
            print(f"  💰 Balance: ${result['balance']:,.2f} ({sign}{pct:.2f}%)")
            print(f"  📊 Deals: {result['deals']} | SL: {result['sl_hits']} | TP: {result['tp_hits']} | BE: {result['breakevens']}")
        else:
            print(f"❌ {result.get('error', 'Unknown')}")
    
    # Generate report
    duration = datetime.now() - start_time
    print(f"\n{'='*70}")
    print(f"  📝 Generating report... ({duration})")
    print(f"{'='*70}")
    
    report = generate_report(all_results)
    print(f"\n📄 Report saved to: {RESULTS_MD}")
    print(f"\n{report}")
    
    # Restart MT5 normally
    print("🔄 Restarting MT5 normally...")
    restart_mt5_normal()
    
    print(f"\n✅ All done! Duration: {duration}")


if __name__ == "__main__":
    main()
