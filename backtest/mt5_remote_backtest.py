#!/usr/bin/env python3
"""
MT5 Remote Auto Backtest
========================
Tự động SSH vào Windows Server, chạy MT5 Strategy Tester, đọc kết quả.
Workflow: Upload INI → Task Scheduler → Wait → Parse log → Next test

Usage:
    python mt5_remote_backtest.py
"""

import subprocess
import time
import re
import os
import sys
from datetime import datetime

# ============================================================================
# CONNECTION CONFIG
# ============================================================================
SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")

MT5_EXE = r"C:\Program Files\MetaTrader 5 EXNESS\terminal64.exe"
MT5_EDITOR = r"C:\Program Files\MetaTrader 5 EXNESS\MetaEditor64.exe"
MT5_DATA = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
AGENT_LOG = MT5_TESTER + r"\Agent-127.0.0.1-3000\logs"

LOCAL_MQL5 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ============================================================================
# BACKTEST MATRIX — Edit this to test different configs
# ============================================================================
TESTS = [
    # (name, ea_path_relative, symbol, period, from_date, to_date)
    ("Scalper_EURUSD_M15",  "Scalper\\Expert Scalper",    "EURUSDm", "M15", "2024.01.01", "2026.02.01"),
    ("Scalper_XAUUSD_M15",  "Scalper\\Expert Scalper",    "XAUUSDm", "M15", "2024.01.01", "2026.02.01"),
    ("Scalper_USDJPY_M15",  "Scalper\\Expert Scalper",    "USDJPYm", "M15", "2024.01.01", "2026.02.01"),
    
    ("Reversal_EURUSD_H1",  "Reversal\\Expert Reversal",  "EURUSDm", "H1",  "2024.01.01", "2026.02.01"),
    ("Reversal_XAUUSD_H1",  "Reversal\\Expert Reversal",  "XAUUSDm", "H1",  "2024.01.01", "2026.02.01"),
    ("Reversal_USDJPY_H1",  "Reversal\\Expert Reversal",  "USDJPYm", "H1",  "2024.01.01", "2026.02.01"),
    
    ("Breakout_EURUSD_M15", "Breakout\\Expert Breakout",  "EURUSDm", "M15", "2024.01.01", "2026.02.01"),
    ("Breakout_XAUUSD_M15", "Breakout\\Expert Breakout",  "XAUUSDm", "M15", "2024.01.01", "2026.02.01"),
    ("Breakout_USDJPY_M15", "Breakout\\Expert Breakout",  "USDJPYm", "M15", "2024.01.01", "2026.02.01"),
]

DEPOSIT = 10000
LEVERAGE = 500


# ============================================================================
# SSH helpers
# ============================================================================
def ssh(cmd, timeout=60):
    """Run command on Windows Server"""
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

def scp_up(local, remote):
    """Upload file to server"""
    full = ["sshpass", "-p", SSH_PASS, "scp",
            "-o", "StrictHostKeyChecking=no", local,
            f"{SSH_USER}@{SSH_HOST}:{remote}"]
    r = subprocess.run(full, capture_output=True, text=True, timeout=30)
    return r.returncode == 0


# ============================================================================
# MT5 operations
# ============================================================================
def kill_mt5():
    ssh('taskkill /f /im terminal64.exe 2>nul')
    time.sleep(3)

def mt5_running():
    out = ssh('tasklist /fi "IMAGENAME eq terminal64.exe" /nh 2>nul')
    return "terminal64.exe" in out.lower()

def get_today_str():
    """Get today's date in MT5 agent log format (YYYYMMDD) — using server time"""
    out = ssh('powershell -Command "Get-Date -Format yyyyMMdd"')
    return out.strip() if out and len(out) == 8 else datetime.now().strftime("%Y%m%d")

def clear_agent_log(date_str):
    """Delete today's agent log so we get clean results"""
    ssh(f'del "{AGENT_LOG}\\{date_str}.log" 2>nul')

def read_agent_log(date_str):
    """Read the agent log"""
    out = ssh(f'type "{AGENT_LOG}\\{date_str}.log" 2>nul', timeout=30)
    return out

def create_ini(ea_path, symbol, period, from_date, to_date):
    """Create INI content for Strategy Tester"""
    return f"""[Tester]
Expert={ea_path}
Symbol={symbol}
Period={period}
Model=1
Optimization=0
FromDate={from_date}
ToDate={to_date}
ReplaceReport=1
ShutdownTerminal=1
Deposit={DEPOSIT}
Currency=USD
Leverage={LEVERAGE}
"""

def upload_ini(ini_content):
    """Write INI to a temp local file, then upload"""
    local_tmp = "/tmp/mt5_backtest_auto.ini"
    with open(local_tmp, "w") as f:
        f.write(ini_content)
    remote = f"C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/53785E099C927DB68A545C249CDBCE06/tester/backtest_auto.ini"
    return scp_up(local_tmp, remote)

def launch_mt5():
    """Launch MT5 via Task Scheduler (required for GUI app from SSH)"""
    ini_path = f"{MT5_DATA}\\tester\\backtest_auto.ini"
    
    # Delete and recreate scheduled task
    ssh(f'schtasks /delete /tn "MT5Backtest" /f 2>nul')
    ssh(f'schtasks /create /tn "MT5Backtest" /tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\" /config:\\"{ini_path}\\"" /sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5Backtest" 2>&1')

def wait_for_completion(max_wait=300):
    """Wait for MT5 to finish (ShutdownTerminal=1)"""
    start = time.time()
    time.sleep(10)  # Initial wait for startup
    
    while time.time() - start < max_wait:
        if not mt5_running():
            return True
        elapsed = int(time.time() - start)
        if elapsed % 30 == 0:
            print(f"    ⏳ {elapsed}s...", flush=True)
        time.sleep(5)
    
    # Timeout
    kill_mt5()
    return False

def parse_results(log_text, test_name):
    """Parse agent log for backtest results"""
    result = {"name": test_name, "balance": None, "trades": 0, "ticks": 0, "time": ""}
    
    if not log_text or "final balance" not in log_text.lower():
        result["error"] = "No results found"
        return result
    
    # Final balance
    m = re.search(r'final balance\s+([\d.]+)\s+USD', log_text, re.IGNORECASE)
    if m:
        result["balance"] = float(m.group(1))
        result["profit"] = result["balance"] - DEPOSIT
        result["profit_pct"] = (result["profit"] / DEPOSIT) * 100
    
    # Ticks and bars
    m = re.search(r'(\d+)\s+ticks,\s+(\d+)\s+bars\s+generated', log_text)
    if m:
        result["ticks"] = int(m.group(1))
        result["bars"] = int(m.group(2))
    
    # Test time
    m = re.search(r'Test passed in\s+([\d:]+\.\d+)', log_text)
    if m:
        result["time"] = m.group(1)
    
    # Count trades (deal performed)
    deals = re.findall(r'deal\s+#\d+\s+(buy|sell)', log_text, re.IGNORECASE)
    result["deals"] = len(deals)
    
    # Count unique orders placed by EA
    orders = re.findall(r'Order placed.*?Retcode=10009', log_text)
    result["trades"] = len(orders)
    
    # Count SL/TP hits
    sl_hits = len(re.findall(r'stop loss triggered', log_text, re.IGNORECASE))
    tp_hits = len(re.findall(r'take profit triggered', log_text, re.IGNORECASE))
    result["sl_hits"] = sl_hits
    result["tp_hits"] = tp_hits
    
    # Count partial TPs and BEs
    partials = len(re.findall(r'PARTIAL TP', log_text))
    bes = len(re.findall(r'SL moved to breakeven', log_text))
    result["partials"] = partials
    result["breakevens"] = bes
    
    return result


# ============================================================================
# MAIN
# ============================================================================
def main():
    print("=" * 70)
    print("  MT5 REMOTE AUTO BACKTEST")
    print("=" * 70)
    print(f"  Server: {SSH_HOST}")
    print(f"  Tests:  {len(TESTS)}")
    print(f"  Deposit: ${DEPOSIT:,} | Leverage: 1:{LEVERAGE}")
    print("=" * 70)
    
    # Test SSH
    print("\n🔌 Testing SSH...", end=" ", flush=True)
    out = ssh("echo OK")
    if "OK" not in out:
        print("❌ FAILED")
        sys.exit(1)
    print("✅ Connected")
    
    date_str = get_today_str()
    print(f"📅 Server date: {date_str}")
    
    results = []
    
    for i, (name, ea_path, symbol, period, from_date, to_date) in enumerate(TESTS):
        print(f"\n{'─'*70}")
        print(f"  [{i+1}/{len(TESTS)}] {name}")
        print(f"  EA={ea_path} | {symbol} | {period} | {from_date} → {to_date}")
        print(f"{'─'*70}")
        
        # Kill any running MT5
        if mt5_running():
            print("  🔄 Killing existing MT5...")
            kill_mt5()
        
        # Clear old agent log
        clear_agent_log(date_str)
        time.sleep(1)
        
        # Create & upload INI
        ini = create_ini(ea_path, symbol, period, from_date, to_date)
        print("  📄 Uploading config...", end=" ", flush=True)
        if upload_ini(ini):
            print("✅")
        else:
            print("❌ FAILED")
            results.append({"name": name, "error": "INI upload failed"})
            continue
        
        # Launch MT5
        print("  🚀 Launching MT5...", end=" ", flush=True)
        launch_mt5()
        time.sleep(5)
        
        if mt5_running():
            print("✅ Running")
        else:
            # Sometimes takes a moment
            time.sleep(5)
            if mt5_running():
                print("✅ Running")
            else:
                print("❌ MT5 not started")
                results.append({"name": name, "error": "MT5 failed to start"})
                continue
        
        # Wait for completion
        print("  ⏳ Waiting for backtest...", flush=True)
        completed = wait_for_completion(max_wait=300)
        
        if not completed:
            print("  ⚠️ TIMEOUT")
            results.append({"name": name, "error": "Timeout"})
            continue
        
        time.sleep(2)
        
        # Read results
        print("  📖 Reading results...", end=" ", flush=True)
        log = read_agent_log(date_str)
        result = parse_results(log, name)
        results.append(result)
        
        if result.get("balance"):
            pct = result["profit_pct"]
            sign = "+" if pct >= 0 else ""
            print(f"✅")
            print(f"  💰 Balance: ${result['balance']:,.2f} ({sign}{pct:.2f}%)")
            print(f"  📊 Trades: {result['trades']} | SL: {result['sl_hits']} | TP: {result['tp_hits']}")
            print(f"  🎯 Partials: {result['partials']} | BEs: {result['breakevens']}")
        else:
            print(f"❌ {result.get('error', 'Unknown error')}")
    
    # =========================================================================
    # SUMMARY
    # =========================================================================
    print(f"\n{'='*70}")
    print(f"  📊 BACKTEST RESULTS SUMMARY")
    print(f"{'='*70}")
    print(f"  {'Test':<28} {'Balance':>10} {'P&L':>10} {'%':>8} {'Trades':>7} {'SL':>4} {'TP':>4}")
    print(f"  {'─'*71}")
    
    for r in results:
        name = r["name"][:28]
        if r.get("balance"):
            bal = f"${r['balance']:,.2f}"
            pnl = f"${r['profit']:+,.2f}"
            pct = f"{r['profit_pct']:+.2f}%"
            trades = str(r.get("trades", "?"))
            sl = str(r.get("sl_hits", "?"))
            tp = str(r.get("tp_hits", "?"))
        else:
            bal = pnl = pct = "ERROR"
            trades = sl = tp = "-"
        
        print(f"  {name:<28} {bal:>10} {pnl:>10} {pct:>8} {trades:>7} {sl:>4} {tp:>4}")
    
    print(f"  {'─'*71}")
    
    # Best performer
    valid = [r for r in results if r.get("balance")]
    if valid:
        best = max(valid, key=lambda x: x.get("profit_pct", -999))
        worst = min(valid, key=lambda x: x.get("profit_pct", 999))
        print(f"\n  🏆 Best:  {best['name']} → {best['profit_pct']:+.2f}%")
        print(f"  💀 Worst: {worst['name']} → {worst['profit_pct']:+.2f}%")
    
    print(f"\n{'='*70}")
    
    # Restart MT5 normally (without config)
    print("🔄 Restarting MT5 normally...")
    ssh(f'schtasks /delete /tn "MT5Backtest" /f 2>nul')
    ssh(f'schtasks /create /tn "MT5Start" /tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\"" /sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5Start" 2>&1')
    ssh('schtasks /delete /tn "MT5Start" /f 2>nul')
    
    return results


if __name__ == "__main__":
    main()
