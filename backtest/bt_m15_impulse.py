#!/usr/bin/env python3
"""
M15 Impulse FAG Entry — Backtest & Session Analysis
=====================================================
- Backtest trên nhiều forex pairs
- Phân tích kết quả theo session (Asian/London/NY)
- Tối ưu cho giờ thị trường biến động

Usage:
    python3 backtest/bt_m15_impulse.py
"""

import subprocess
import time
import re
import sys
import os
from datetime import datetime

# ============================================================================
# CONFIG
# ============================================================================
SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = "PNS1G3e7oc3h6PWJD4dsA"

MT5_EXE = r"C:\Program Files\MetaTrader 5 EXNESS\terminal64.exe"
MT5_DATA = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
AGENT_LOG_DIR = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06\Agent-127.0.0.1-3000\logs"

EA_PATH = r"M15 Impulse FAG Entry\Expert M15 Impulse FAG Entry"

# SERVER TIMEZONE: UTC+0 (MT5 server)
# BROKER TIME = UTC+0 for Exness Demo

# ============================================================================
# TEST MATRIX
# ============================================================================
SYMBOLS = ["XAUUSDm"]
PERIODS = ["M15"]  # EA is designed for M15
DATE_RANGES = [
    ("2024.01.01", "2025.06.01", "FULL"),
]

# ── Phase 5: Final verification ──
# Format: (label, UseTimeFilter, StartHour, EndHour, TPMult, ATRMult, MinZonePips, SLBufferPips, MaxZoneBars)
SESSION_TESTS = [
    # BEST COMBO confirmation
    ("BEST_NY_TP1_MZ50_SL10",  "true", 13, 21, 1.0,  1.2, 50, 10, 0),
    # Extended session + best params  
    ("Ext12-22_TP1_MZ50_SL10", "true", 12, 22, 1.0,  1.2, 50, 10, 0),
    # Night session test (VN daytime ~ early Asian)
    ("Asian_TP1_MZ50_SL10",    "true", 0, 8, 1.0,  1.2, 50, 10, 0),
    # Full day with best filters
    ("NoFilt_TP1_MZ50_SL10",   "false", 0, 24, 1.0,  1.2, 50, 10, 0),
]

DEPOSIT = 10000
LEVERAGE = "1:500"
MODEL = 1  # 1 min OHLC

# ============================================================================
# SSH HELPERS
# ============================================================================
def ssh_cmd(command, timeout=60):
    for attempt in range(3):
        full_cmd = [
            "sshpass", "-p", SSH_PASS,
            "ssh", "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=15",
            f"{SSH_USER}@{SSH_HOST}",
            command
        ]
        try:
            result = subprocess.run(full_cmd, capture_output=True, text=True, timeout=timeout)
            if result.returncode == 255:  # SSH connection failed
                time.sleep(3)
                continue
            return result.stdout.strip(), result.returncode
        except subprocess.TimeoutExpired:
            return "TIMEOUT", -1
    return "", -1

def ssh_powershell(ps_cmd, timeout=60):
    """Run PowerShell command via SSH"""
    escaped = ps_cmd.replace('"', '\\"')
    return ssh_cmd(f'powershell -Command "{escaped}"', timeout=timeout)

# ============================================================================
# MT5 OPERATIONS  
# ============================================================================
def kill_mt5():
    ssh_cmd('taskkill /f /im terminal64.exe 2>nul')
    time.sleep(3)

def is_mt5_running():
    out, _ = ssh_cmd('tasklist /fi "IMAGENAME eq terminal64.exe" /nh 2>nul')
    return "terminal64.exe" in out.lower()

def start_mt5_tester(ini_path):
    """Start MT5 via Task Scheduler with tester config"""
    # Write config path to a known location and use schtasks
    ssh_cmd(f'schtasks /run /tn "MT5_Live" 2>nul', timeout=10)
    time.sleep(3)
    # Actually we need to start with /config parameter
    # Use powershell Start-Process
    ps = f"Start-Process -FilePath '{MT5_EXE}' -ArgumentList '/config:{ini_path}'"
    ssh_powershell(ps, timeout=15)

def create_ini(symbol, period, from_date, to_date, report_name, extra_inputs=""):
    """Create MT5 Strategy Tester INI config"""
    ini = f"""[Tester]
Expert={EA_PATH}
Symbol={symbol}
Period={period}
Model={MODEL}
Optimization=0
FromDate={from_date}
ToDate={to_date}
Report={MT5_DATA}\\reports\\{report_name}
ReplaceReport=1
ShutdownTerminal=1
Deposit={DEPOSIT}
Leverage={LEVERAGE}
ExecutionMode=0"""

    if extra_inputs:
        ini += f"\n[TesterInputs]\n{extra_inputs}"
    
    return ini

def write_ini_to_server(ini_content, ini_filename="bt_m15_impulse.ini"):
    """Write INI file locally then SCP to server (with retry)"""
    ini_remote_path = f"{MT5_DATA}\\tester\\{ini_filename}"
    ini_remote_scp = f"C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/53785E099C927DB68A545C249CDBCE06/tester/{ini_filename}"
    
    # Write locally first (CRLF for Windows)
    local_tmp = f"/tmp/{ini_filename}"
    with open(local_tmp, 'w', newline='\r\n') as f:
        f.write(ini_content)
    
    # SCP to server with retry
    for attempt in range(3):
        scp_shell = f"sshpass -p '{SSH_PASS}' scp -o StrictHostKeyChecking=no '{local_tmp}' '{SSH_USER}@{SSH_HOST}:{ini_remote_scp}'"
        result = subprocess.run(scp_shell, shell=True, capture_output=True, text=True, timeout=15)
        if result.returncode == 0:
            break
        time.sleep(2)
    else:
        print(f"  ❌ SCP failed after 3 attempts")
        return None
    
    # Verify
    out, _ = ssh_cmd(f'type "{ini_remote_path}" 2>nul')
    if '[Tester]' not in out:
        print(f"  ❌ INI verification failed")
        return None
    return ini_remote_path

def run_single_backtest(symbol, period, from_date, to_date, label, extra_inputs=""):
    """Run a single backtest and return results"""
    report_name = f"M15Impulse_{symbol}_{label}"
    
    # Create reports dir
    ssh_cmd(f'mkdir "{MT5_DATA}\\reports" 2>nul')
    
    # Create & write INI
    ini_content = create_ini(symbol, period, from_date, to_date, report_name, extra_inputs)
    ini_path = write_ini_to_server(ini_content)
    if not ini_path:
        return None
    
    # Kill existing MT5
    kill_mt5()
    time.sleep(3)
    
    # Clear agent log to isolate this test's results
    today = datetime.now().strftime("%Y%m%d")
    log_path = f"{AGENT_LOG_DIR}\\{today}.log"
    ssh_cmd(f'del "{log_path}" 2>nul')
    
    # Start MT5 via Task Scheduler (batch file reads bt_m15_impulse.ini)
    ssh_cmd('schtasks /run /tn "MT5_Backtest" 2>nul', timeout=10)
    
    # Wait for MT5 to start
    time.sleep(15)
    
    # Poll for completion (MT5 shuts down when done)
    max_wait = 300
    start_time = time.time()
    
    while time.time() - start_time < max_wait:
        if not is_mt5_running():
            elapsed = int(time.time() - start_time)
            print(f"    MT5 exited ({elapsed}s)")
            break
        time.sleep(5)
        elapsed = int(time.time() - start_time)
        if elapsed % 30 == 0:
            print(f"    Waiting... {elapsed}s")
    else:
        print(f"    Timeout {max_wait}s — killing MT5")
        kill_mt5()
    
    time.sleep(3)
    
    # Read report (with retry)
    for attempt in range(3):
        report = read_report(report_name)
        if report.get("total_trades", 0) > 0 or report.get("net_profit") is not None:
            return report
        time.sleep(5)
    return report

def read_report(report_name):
    """Read results from the tester agent log (only the LAST test section)"""
    result = {"name": report_name}
    
    today = datetime.now().strftime("%Y%m%d")
    log_path = f"{AGENT_LOG_DIR}\\{today}.log"
    
    # Read agent log via PowerShell (UTF-16 LE) — only tail
    ps = f"Get-Content -Path '{log_path}' -Encoding Unicode -Tail 2000"
    out, rc = ssh_powershell(ps, timeout=30)
    
    if not out:
        print(f"    ⚠️ Cannot read agent log")
        return result
    
    lines = out.split('\n')
    
    # Find the LAST "test ... thread finished" to delimit our test
    # Then go back to find "automatical testing started" or first trade line
    test_start = 0
    for i, line in enumerate(lines):
        if 'test Experts' in line and 'thread finished' in line:
            # This is the end of a test run — find start
            for j in range(i, -1, -1):
                if 'automatical testing started' in lines[j] or 'connected' in lines[j].lower():
                    test_start = j
                    break
            # We want the last complete test
            test_lines = lines[test_start:i+1]
    
    if test_start == 0:
        test_lines = lines  # fallback to all lines
    
    # Parse final balance
    for line in test_lines:
        m = re.search(r'final balance\s+([\d.]+)\s+USD', line)
        if m:
            balance = float(m.group(1))
            result["net_profit"] = round(balance - DEPOSIT, 2)
    
    # Parse deals (trades)
    deals = []
    for line in test_lines:
        m = re.search(r'deal #(\d+)\s+(buy|sell)\s+([\d.]+)\s+\S+\s+at\s+([\d.]+)', line)
        if m:
            deal_num = int(m.group(1))
            direction = m.group(2)
            lot = float(m.group(3))
            price = float(m.group(4))
            
            time_m = re.search(r'(\d{4}\.\d{2}\.\d{2}\s+\d{2}:\d{2}:\d{2})', line)
            trade_time = time_m.group(1) if time_m else ""
            
            deals.append({
                "deal": deal_num, "dir": direction, "lot": lot,
                "price": price, "time": trade_time
            })
    
    result["total_trades"] = len(deals) // 2
    
    # Parse SL/TP hits
    sl_hits = sum(1 for l in test_lines if 'stop loss triggered' in l)
    tp_hits = sum(1 for l in test_lines if 'take profit triggered' in l)
    result["sl_hits"] = sl_hits
    result["tp_hits"] = tp_hits
    if sl_hits + tp_hits > 0:
        result["win_rate"] = round(tp_hits / (sl_hits + tp_hits) * 100, 1)
    
    # Extract trade hours for session analysis (from Pending order placed)
    trade_hours = {}
    for line in test_lines:
        if 'Pending order placed' in line:
            time_m = re.search(r'(\d{4}\.\d{2}\.\d{2}\s+(\d{2}):\d{2}:\d{2})', line)
            if time_m:
                hour = int(time_m.group(2))
                trade_hours[hour] = trade_hours.get(hour, 0) + 1
    
    result["trade_hours"] = trade_hours
    result["source"] = "agent_log"
    
    return result

# ============================================================================
# ANALYSIS
# ============================================================================
def read_agent_logs_for_trades(symbol, days_back=180):
    """Read EA logs to analyze trade hours — mais this needs the EA to have been running.
    For backtest analysis, we'll use the tester journal logs instead."""
    
    # Read tester journal for trade details
    today = datetime.now().strftime("%Y%m%d")
    log_path = f"{TESTER_DATA}\\logs\\{today}.log"
    
    ps = f"Get-Content -Path '{log_path}' -Encoding Unicode | Select-String -Pattern 'deal|order|buy|sell' | Select-Object -Last 100"
    out, _ = ssh_powershell(ps, timeout=20)
    return out

def format_results_table(results):
    """Format results as a readable table"""
    lines = []
    lines.append(f"\n{'='*85}")
    lines.append(f"  M15 IMPULSE FAG ENTRY — BACKTEST RESULTS")
    lines.append(f"{'='*85}")
    lines.append(f"  {'Test':<30} {'Profit':>10} {'Trades':>7} {'Win%':>7} {'TP':>5} {'SL':>5}")
    lines.append(f"  {'─'*65}")
    
    for r in results:
        name = r.get("name", "?")[:30]
        profit = r.get("net_profit", "—")
        trades = r.get("total_trades", "—")
        win_rate = r.get("win_rate", "—")
        tp_hits = r.get("tp_hits", "—")
        sl_hits = r.get("sl_hits", "—")
        
        if isinstance(profit, (int, float)):
            profit = f"${profit:,.2f}"
        if isinstance(win_rate, (int, float)):
            win_rate = f"{win_rate}%"
            
        lines.append(f"  {name:<30} {str(profit):>10} {str(trades):>7} {str(win_rate):>7} {str(tp_hits):>5} {str(sl_hits):>5}")
    
    lines.append(f"{'='*85}")
    
    # Trade hour distribution
    all_hours = {}
    for r in results:
        for h, count in r.get("trade_hours", {}).items():
            all_hours[h] = all_hours.get(h, 0) + count
    
    if all_hours:
        lines.append(f"\n  📊 TRADE HOUR DISTRIBUTION (Server time / GMT+0):")
        lines.append(f"  {'─'*50}")
        
        # Session labels
        sessions = {
            "Asian (0-8)": range(0, 8),
            "London (8-16)": range(8, 16),
            "NY (13-21)": range(13, 21),
            "Late (21-24)": range(21, 24),
        }
        
        for h in sorted(all_hours.keys()):
            count = all_hours[h]
            bar = "█" * count
            lines.append(f"  {h:02d}:00  {count:>3}  {bar}")
        
        # Session summary
        lines.append(f"\n  Session Breakdown:")
        asian = sum(all_hours.get(h, 0) for h in range(0, 8))
        london = sum(all_hours.get(h, 0) for h in range(8, 16))
        ny_overlap = sum(all_hours.get(h, 0) for h in range(13, 21))
        late = sum(all_hours.get(h, 0) for h in range(21, 24))
        total = sum(all_hours.values())
        
        lines.append(f"  Asian (0-8):     {asian:>3} ({asian/total*100:.0f}%)" if total else "")
        lines.append(f"  London (8-16):   {london:>3} ({london/total*100:.0f}%)" if total else "")
        lines.append(f"  NY (13-21):      {ny_overlap:>3} ({ny_overlap/total*100:.0f}%)" if total else "")
        lines.append(f"  Late (21-24):    {late:>3} ({late/total*100:.0f}%)" if total else "")
    
    return '\n'.join(lines)

def save_results(results, filename="m15_impulse_results.md"):
    """Save results to markdown file"""
    filepath = os.path.join(os.path.dirname(os.path.abspath(__file__)), filename)
    
    with open(filepath, 'w') as f:
        f.write("# M15 Impulse FAG Entry — Backtest Results\n\n")
        f.write(f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
        f.write(f"**Deposit:** ${DEPOSIT:,} | **Leverage:** {LEVERAGE}\n")
        f.write(f"**Model:** 1 min OHLC\n\n")
        
        f.write("## Results\n\n")
        f.write("| Test | Net Profit | Trades | Win% | TP | SL |\n")
        f.write("|------|-----------|--------|------|-----|-----|\n")
        
        for r in results:
            name = r.get("name", "?")
            profit = r.get("net_profit", "—")
            trades = r.get("total_trades", "—")
            win_rate = r.get("win_rate", "—")
            tp_hits = r.get("tp_hits", "—")
            sl_hits = r.get("sl_hits", "—")
            
            if isinstance(profit, (int, float)):
                profit = f"${profit:,.2f}"
            if isinstance(win_rate, (int, float)):
                win_rate = f"{win_rate}%"
            
            f.write(f"| {name} | {profit} | {trades} | {win_rate} | {tp_hits} | {sl_hits} |\n")
        
        # Trade hour distribution
        all_hours = {}
        for r in results:
            for h, count in r.get("trade_hours", {}).items():
                all_hours[h] = all_hours.get(h, 0) + count
        
        if all_hours:
            f.write("\n## Trade Hour Distribution (Server GMT+0)\n\n")
            f.write("| Hour | Trades | Session |\n")
            f.write("|------|--------|---------|\n")
            for h in sorted(all_hours.keys()):
                session = "Asian" if h < 8 else "London" if h < 16 else "NY" if h < 21 else "Late"
                f.write(f"| {h:02d}:00 | {all_hours[h]} | {session} |\n")
        
        f.write("\n---\n")
        f.write("*Generated by bt_m15_impulse.py*\n")
    
    print(f"\n📄 Results saved to {filepath}")

# ============================================================================
# MAIN
# ============================================================================
def main():
    print("=" * 70)
    print("  M15 IMPULSE FAG ENTRY — BACKTEST")
    print("=" * 70)
    print(f"  Server: {SSH_HOST}")
    print(f"  Symbols: {', '.join(SYMBOLS)}")
    print(f"  Deposit: ${DEPOSIT:,} | Leverage: {LEVERAGE}")
    print("=" * 70)
    
    # Test SSH
    print("\n🔌 Testing SSH...")
    out, rc = ssh_cmd("echo OK")
    if "OK" not in out:
        print("❌ SSH failed!")
        sys.exit(1)
    print("✅ SSH OK")
    
    # Verify EA exists
    print("\n🔍 Checking EA...")
    ex5_path = f"{MT5_DATA}\\MQL5\\Experts\\{EA_PATH}.ex5"
    out, _ = ssh_cmd(f'if exist "{ex5_path}" echo FOUND')
    if "FOUND" not in out:
        print(f"❌ EA not found: {ex5_path}")
        sys.exit(1)
    print("✅ EA compiled")
    
    # Run backtests: each symbol × each session filter
    results = []
    total_tests = len(SYMBOLS) * len(SESSION_TESTS)
    test_num = 0
    
    for symbol in SYMBOLS:
        for sess_label, use_filter, start_h, end_h, tp_mult, atr_mult, min_zone, sl_buffer, max_bars in SESSION_TESTS:
            test_num += 1
            from_date, to_date, date_label = DATE_RANGES[0]
            label = f"{date_label}_{sess_label}"
            
            # Build TesterInputs section (simple format for non-optimization)
            inputs = f"InpUseTimeFilter={use_filter}\n"
            inputs += f"InpStartHour={start_h}\n"
            inputs += f"InpEndHour={end_h}\n"
            inputs += f"InpTPMultiplier={tp_mult}\n"
            inputs += f"InpATRMult={atr_mult}\n"
            inputs += f"InpMinZonePips={min_zone}\n"
            inputs += f"InpSLBufferPips={sl_buffer}\n"
            inputs += f"InpMaxZoneBars={max_bars}\n"
            
            print(f"\n{'─'*60}")
            print(f"  [{test_num}/{total_tests}] {symbol} | {sess_label}")
            print(f"  ATR×{atr_mult} | TP×{tp_mult} | MinZone={min_zone} | SLBuf={sl_buffer} | MaxBars={max_bars}")
            print(f"{'─'*60}")
            
            result = run_single_backtest(symbol, "M15", from_date, to_date, label, extra_inputs=inputs)
            if result:
                result["session"] = sess_label
                result["symbol"] = symbol
                results.append(result)
                profit = result.get("net_profit", "?")
                trades = result.get("total_trades", "?")
                win_rate = result.get("win_rate", "?")
                print(f"    📊 ${profit} | {trades} trades | WR: {win_rate}%")
            else:
                results.append({"name": f"{symbol}_{label}", "session": sess_label, "symbol": symbol, "error": "No report"})
                print(f"    ❌ No report")
    
    # Print summary
    print(format_results_table(results))
    
    # Save results
    save_results(results)
    
    # Restart MT5 normally
    print("\n🔄 Restarting MT5 for live trading...")
    ssh_cmd('schtasks /run /tn "MT5_Live" 2>nul', timeout=10)
    
    return results

if __name__ == "__main__":
    main()
