#!/usr/bin/env python3
"""
MT5 Comprehensive Remote Backtest
==================================
- 4 strategies: MST Medio, Scalper, Reversal, Breakout
- 3 symbols: EURUSDm, XAUUSDm, USDJPYm
- Multiple timeframes: M5, M15, H1, H4
- Multiple date ranges
- Deposit: $1,000, Leverage: 1:100
- Results saved to backtest_results.md

Usage:
    python mt5_full_backtest.py
"""

import subprocess
import time
import re
import os
import sys
from datetime import datetime

# ============================================================================
# CONNECTION
# ============================================================================
SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")

MT5_EXE = r"C:\Program Files\MetaTrader 5 EXNESS\terminal64.exe"
MT5_DATA = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
AGENT_LOG_DIR = MT5_TESTER + r"\Agent-127.0.0.1-3000\logs"

DEPOSIT = 1000
LEVERAGE = 100

RESULTS_MD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "backtest_results.md")

# ============================================================================
# TEST MATRIX
# ============================================================================
# Strategy configs: (label, ea_path, recommended_timeframes)
STRATEGIES = {
    "MST Medio": {
        "ea": "MST Medio\\Expert MST Medio",
        "timeframes": ["M5", "M15", "H1"],
    },
    "Scalper": {
        "ea": "Scalper\\Expert Scalper",
        "timeframes": ["M5", "M15", "H1"],
    },
    "Reversal": {
        "ea": "Reversal\\Expert Reversal",
        "timeframes": ["M15", "H1", "H4"],
    },
    "Breakout": {
        "ea": "Breakout\\Expert Breakout",
        "timeframes": ["M5", "M15", "H1"],
    },
}

SYMBOLS = ["EURUSDm", "XAUUSDm", "USDJPYm"]

# Date ranges to test
DATE_RANGES = [
    ("2024.01.01", "2025.01.01", "2024"),       # Full year 2024
    ("2025.01.01", "2026.01.01", "2025"),       # Full year 2025
    ("2024.01.01", "2026.02.01", "2024-2026"),  # Full 2 years
]


# ============================================================================
# SSH
# ============================================================================
def ssh(cmd, timeout=60):
    full = ["sshpass", "-p", SSH_PASS, "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=15",
            f"{SSH_USER}@{SSH_HOST}", cmd]
    try:
        r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except:
        return ""

def scp_up(local, remote):
    full = ["sshpass", "-p", SSH_PASS, "scp",
            "-o", "StrictHostKeyChecking=no", local,
            f"{SSH_USER}@{SSH_HOST}:{remote}"]
    r = subprocess.run(full, capture_output=True, text=True, timeout=30)
    return r.returncode == 0


# ============================================================================
# MT5 OPERATIONS
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
    """Clear agent log and also create a marker to detect new writes"""
    ssh(f'del "{AGENT_LOG_DIR}\\{date_str}.log" 2>nul')
    time.sleep(1)

def read_agent_log(date_str, max_retries=3):
    """Read agent log with retries"""
    for attempt in range(max_retries):
        out = ssh(f'type "{AGENT_LOG_DIR}\\{date_str}.log" 2>nul', timeout=30)
        if out and "final balance" in out.lower():
            return out
        time.sleep(2)
    return out or ""

def create_ini(ea_path, symbol, period, from_date, to_date):
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
    local_tmp = "/tmp/mt5_backtest_auto.ini"
    with open(local_tmp, "w") as f:
        f.write(ini_content)
    remote = f"C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/53785E099C927DB68A545C249CDBCE06/tester/backtest_auto.ini"
    return scp_up(local_tmp, remote)

def launch_mt5():
    ini_path = f"{MT5_DATA}\\tester\\backtest_auto.ini"
    ssh(f'schtasks /delete /tn "MT5Backtest" /f 2>nul')
    ssh(f'schtasks /create /tn "MT5Backtest" /tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\" /config:\\"{ini_path}\\"" /sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5Backtest" 2>&1')

def wait_for_test(max_wait=300):
    start = time.time()
    time.sleep(8)
    while time.time() - start < max_wait:
        if not mt5_running():
            return True
        time.sleep(5)
    kill_mt5()
    return False


# ============================================================================
# PARSE RESULTS
# ============================================================================
def parse_results(log_text, test_label):
    r = {"label": test_label, "balance": None, "profit": None, "profit_pct": None,
         "trades": 0, "sl": 0, "tp": 0, "partials": 0, "bes": 0, "error": None}
    
    if not log_text or "final balance" not in log_text.lower():
        r["error"] = "No results"
        return r
    
    m = re.search(r'final balance\s+([\d.]+)\s+USD', log_text, re.IGNORECASE)
    if m:
        r["balance"] = float(m.group(1))
        r["profit"] = r["balance"] - DEPOSIT
        r["profit_pct"] = (r["profit"] / DEPOSIT) * 100
    
    m = re.search(r'(\d+)\s+ticks,\s+(\d+)\s+bars', log_text)
    if m:
        r["ticks"] = int(m.group(1))
        r["bars"] = int(m.group(2))
    
    r["sl"] = len(re.findall(r'stop loss triggered', log_text, re.IGNORECASE))
    r["tp"] = len(re.findall(r'take profit triggered', log_text, re.IGNORECASE))
    r["partials"] = len(re.findall(r'PARTIAL', log_text, re.IGNORECASE))
    r["bes"] = len(re.findall(r'breakeven', log_text, re.IGNORECASE))
    
    # Count EA-placed orders
    r["trades"] = len(re.findall(r'Order placed|PlaceOrder|BREAKOUT (UP|DOWN)', log_text))
    # If trades=0, count from deals
    if r["trades"] == 0:
        r["trades"] = r["sl"] + r["tp"]
    
    return r


# ============================================================================
# MAIN
# ============================================================================
def run_single_test(label, ea_path, symbol, period, from_date, to_date, date_str):
    """Run a single backtest and return parsed result"""
    if mt5_running():
        kill_mt5()
    
    clear_agent_log(date_str)
    
    ini = create_ini(ea_path, symbol, period, from_date, to_date)
    if not upload_ini(ini):
        return {"label": label, "error": "INI upload failed"}
    
    launch_mt5()
    time.sleep(5)
    
    if not mt5_running():
        time.sleep(5)
        if not mt5_running():
            return {"label": label, "error": "MT5 failed to start"}
    
    completed = wait_for_test(max_wait=300)
    if not completed:
        return {"label": label, "error": "Timeout"}
    
    time.sleep(3)
    
    log = read_agent_log(date_str, max_retries=5)
    return parse_results(log, label)


def main():
    start_time = datetime.now()
    
    print("=" * 70)
    print("  MT5 COMPREHENSIVE BACKTEST")
    print("=" * 70)
    print(f"  Deposit: ${DEPOSIT:,} | Leverage: 1:{LEVERAGE}")
    print(f"  Strategies: {len(STRATEGIES)} | Symbols: {len(SYMBOLS)} | Ranges: {len(DATE_RANGES)}")
    
    # Build test list
    tests = []
    for strat_name, strat_info in STRATEGIES.items():
        for symbol in SYMBOLS:
            for tf in strat_info["timeframes"]:
                for from_d, to_d, range_label in DATE_RANGES:
                    label = f"{strat_name} | {symbol} | {tf} | {range_label}"
                    tests.append((label, strat_info["ea"], symbol, tf, from_d, to_d, range_label))
    
    total = len(tests)
    print(f"  Total tests: {total}")
    print(f"  Estimated time: ~{total * 0.5:.0f} minutes")
    print("=" * 70)
    
    # Test SSH
    print("\n🔌 Testing SSH...", end=" ", flush=True)
    out = ssh("echo OK")
    if "OK" not in out:
        print("❌ FAILED")
        sys.exit(1)
    print("✅ Connected")
    
    date_str = get_server_date()
    print(f"📅 Server date: {date_str}")
    
    # Run all tests
    all_results = []
    
    for i, (label, ea_path, symbol, tf, from_d, to_d, range_label) in enumerate(tests):
        print(f"\n[{i+1}/{total}] {label}")
        
        result = run_single_test(label, ea_path, symbol, tf, from_d, to_d, date_str)
        result["strategy"] = label.split("|")[0].strip()
        result["symbol"] = symbol
        result["tf"] = tf
        result["range"] = range_label
        all_results.append(result)
        
        if result.get("balance"):
            pct = result["profit_pct"]
            sign = "+" if pct >= 0 else ""
            emoji = "🟢" if pct > 0 else ("🔴" if pct < 0 else "⚪")
            print(f"  {emoji} ${result['balance']:,.2f} ({sign}{pct:.1f}%) | T:{result['trades']} SL:{result['sl']} TP:{result['tp']}")
        else:
            print(f"  ❌ {result.get('error', '?')}")
    
    # =========================================================================
    # SAVE RESULTS TO .md
    # =========================================================================
    elapsed = datetime.now() - start_time
    
    md = []
    md.append("# MT5 Backtest Results")
    md.append("")
    md.append(f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    md.append(f"**Deposit:** ${DEPOSIT:,} | **Leverage:** 1:{LEVERAGE}")
    md.append(f"**Total tests:** {total} | **Duration:** {elapsed}")
    md.append("")
    
    # Group by strategy
    for strat_name in STRATEGIES:
        md.append(f"## {strat_name}")
        md.append("")
        md.append("| Symbol | TF | Period | Balance | P&L | % | Trades | SL | TP |")
        md.append("|--------|-----|--------|---------|-----|---|--------|----|----|")
        
        strat_results = [r for r in all_results if r.get("strategy") == strat_name]
        for r in strat_results:
            if r.get("balance"):
                pct = f"{r['profit_pct']:+.2f}%"
                bal = f"${r['balance']:,.2f}"
                pnl = f"${r['profit']:+,.2f}"
                emoji = "🟢" if r['profit_pct'] > 0 else ("🔴" if r['profit_pct'] < 0 else "⚪")
            else:
                pct = bal = pnl = "ERROR"
                emoji = "❌"
            
            sym = r.get("symbol", "?")
            tf = r.get("tf", "?")
            rng = r.get("range", "?")
            trades = r.get("trades", "?")
            sl = r.get("sl", "?")
            tp = r.get("tp", "?")
            
            md.append(f"| {sym} | {tf} | {rng} | {bal} | {pnl} | {emoji} {pct} | {trades} | {sl} | {tp} |")
        
        md.append("")
    
    # Summary — best/worst
    valid = [r for r in all_results if r.get("balance")]
    if valid:
        md.append("## Summary")
        md.append("")
        
        # Top 5 best
        best5 = sorted(valid, key=lambda x: x.get("profit_pct", -999), reverse=True)[:5]
        md.append("### 🏆 Top 5 Best")
        md.append("")
        md.append("| # | Strategy | Symbol | TF | Period | P&L % |")
        md.append("|---|----------|--------|----|--------|-------|")
        for j, r in enumerate(best5):
            md.append(f"| {j+1} | {r['strategy']} | {r['symbol']} | {r['tf']} | {r['range']} | {r['profit_pct']:+.2f}% |")
        md.append("")
        
        # Top 5 worst
        worst5 = sorted(valid, key=lambda x: x.get("profit_pct", 999))[:5]
        md.append("### 💀 Top 5 Worst")
        md.append("")
        md.append("| # | Strategy | Symbol | TF | Period | P&L % |")
        md.append("|---|----------|--------|----|--------|-------|")
        for j, r in enumerate(worst5):
            md.append(f"| {j+1} | {r['strategy']} | {r['symbol']} | {r['tf']} | {r['range']} | {r['profit_pct']:+.2f}% |")
        md.append("")
        
        # Stats
        profitable = sum(1 for r in valid if r.get("profit_pct", 0) > 0)
        losing = sum(1 for r in valid if r.get("profit_pct", 0) < 0)
        no_trade = sum(1 for r in valid if r.get("profit_pct", 0) == 0)
        avg_pct = sum(r.get("profit_pct", 0) for r in valid) / len(valid)
        
        md.append("### Stats")
        md.append("")
        md.append(f"- Profitable: {profitable}/{len(valid)} ({profitable/len(valid)*100:.0f}%)")
        md.append(f"- Losing: {losing}/{len(valid)}")
        md.append(f"- No trades: {no_trade}/{len(valid)}")
        md.append(f"- Average P&L: {avg_pct:+.2f}%")
        md.append(f"- Errors: {sum(1 for r in all_results if r.get('error'))}")
    
    md_text = "\n".join(md) + "\n"
    
    with open(RESULTS_MD, "w") as f:
        f.write(md_text)
    print(f"\n📝 Results saved to: {RESULTS_MD}")
    
    # Print summary table
    print(f"\n{'='*70}")
    print(f"  SUMMARY — ${DEPOSIT:,} / 1:{LEVERAGE}")
    print(f"{'='*70}")
    
    if valid:
        best = max(valid, key=lambda x: x.get("profit_pct", -999))
        worst = min(valid, key=lambda x: x.get("profit_pct", 999))
        print(f"  🏆 Best:  {best['label']} → {best['profit_pct']:+.2f}%")
        print(f"  💀 Worst: {worst['label']} → {worst['profit_pct']:+.2f}%")
        print(f"  📊 Avg:   {avg_pct:+.2f}%")
        print(f"  ✅ Profitable: {profitable}/{len(valid)}")
    
    # Restart MT5
    print("\n🔄 Restarting MT5...")
    ssh('schtasks /delete /tn "MT5Backtest" /f 2>nul')
    ssh(f'schtasks /create /tn "MT5Start" /tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\"" /sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5Start" 2>&1')
    ssh('schtasks /delete /tn "MT5Start" /f 2>nul')
    
    print(f"\n⏱️ Total time: {elapsed}")
    return all_results


if __name__ == "__main__":
    main()
