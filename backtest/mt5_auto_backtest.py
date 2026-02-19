#!/usr/bin/env python3
"""
MT5 Auto Backtest — Remote Strategy Tester via SSH
===================================================
Tự động:
1. Upload EA files → Windows Server
2. Compile EA bằng MetaEditor CLI
3. Tạo config .ini cho Strategy Tester
4. Chạy backtest trên MT5
5. Đọc report & phân tích kết quả

Usage:
    python mt5_auto_backtest.py
"""

import subprocess
import time
import os
import re
import sys
from datetime import datetime

# ============================================================================
# CONFIG — Windows Server
# ============================================================================
SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = "PNS1G3e7oc3h6PWJD4dsA"
SSH_PORT = 22

MT5_EXE = r"C:\Program Files\MetaTrader 5 EXNESS\terminal64.exe"
MT5_EDITOR = r"C:\Program Files\MetaTrader 5 EXNESS\MetaEditor64.exe"
MT5_DATA = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"

# Local workspace
LOCAL_MQL5 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ============================================================================
# BACKTEST MATRIX
# ============================================================================
TESTS = [
    # (EA Name, EA Path, Symbol, Period, FromDate, ToDate)
    ("Scalper", r"Experts\Scalper\Expert Scalper", "EURUSDm", "M15", "2024.01.01", "2026.02.01"),
    ("Scalper", r"Experts\Scalper\Expert Scalper", "XAUUSDm", "M15", "2024.01.01", "2026.02.01"),
    ("Scalper", r"Experts\Scalper\Expert Scalper", "USDJPYm", "M15", "2024.01.01", "2026.02.01"),

    ("Reversal", r"Experts\Reversal\Expert Reversal", "EURUSDm", "H1", "2024.01.01", "2026.02.01"),
    ("Reversal", r"Experts\Reversal\Expert Reversal", "XAUUSDm", "H1", "2024.01.01", "2026.02.01"),
    ("Reversal", r"Experts\Reversal\Expert Reversal", "USDJPYm", "H1", "2024.01.01", "2026.02.01"),

    ("Breakout", r"Experts\Breakout\Expert Breakout", "EURUSDm", "M15", "2024.01.01", "2026.02.01"),
    ("Breakout", r"Experts\Breakout\Expert Breakout", "XAUUSDm", "M15", "2024.01.01", "2026.02.01"),
    ("Breakout", r"Experts\Breakout\Expert Breakout", "USDJPYm", "M15", "2024.01.01", "2026.02.01"),
]

# Deposit & Leverage
DEPOSIT = 10000
LEVERAGE = "1:500"
MODEL = 1  # 0=Every tick, 1=1min OHLC, 2=Open prices, 3=Real ticks

# ============================================================================
# SSH / SCP HELPERS
# ============================================================================
def ssh_cmd(command, timeout=60):
    """Execute command on Windows Server via SSH"""
    full_cmd = [
        "sshpass", "-p", SSH_PASS,
        "ssh", "-o", "StrictHostKeyChecking=no",
        "-o", f"ConnectTimeout=15",
        f"{SSH_USER}@{SSH_HOST}",
        command
    ]
    try:
        result = subprocess.run(full_cmd, capture_output=True, text=True, timeout=timeout)
        return result.stdout.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "TIMEOUT", -1

def scp_upload(local_path, remote_path):
    """Upload file to Windows Server via SCP"""
    full_cmd = [
        "sshpass", "-p", SSH_PASS,
        "scp", "-o", "StrictHostKeyChecking=no",
        local_path,
        f"{SSH_USER}@{SSH_HOST}:{remote_path}"
    ]
    result = subprocess.run(full_cmd, capture_output=True, text=True, timeout=30)
    return result.returncode == 0

def scp_download(remote_path, local_path):
    """Download file from Windows Server via SCP"""
    full_cmd = [
        "sshpass", "-p", SSH_PASS,
        "scp", "-o", "StrictHostKeyChecking=no",
        f"{SSH_USER}@{SSH_HOST}:{remote_path}",
        local_path
    ]
    result = subprocess.run(full_cmd, capture_output=True, text=True, timeout=30)
    return result.returncode == 0


# ============================================================================
# MT5 OPERATIONS
# ============================================================================
def kill_mt5():
    """Kill running MT5 terminal"""
    print("  🔄 Killing MT5 terminal...")
    out, _ = ssh_cmd('taskkill /f /im terminal64.exe 2>nul & echo DONE')
    time.sleep(3)
    return "DONE" in out

def is_mt5_running():
    """Check if MT5 is running"""
    out, _ = ssh_cmd('tasklist /fi "IMAGENAME eq terminal64.exe" /nh 2>nul')
    return "terminal64.exe" in out.lower()

def compile_ea(ea_path):
    """Compile an EA using MetaEditor CLI"""
    mq5_path = f'{MT5_DATA}\\MQL5\\{ea_path}.mq5'
    cmd = f'"{MT5_EDITOR}" /compile:"{mq5_path}" /log 2>nul & timeout /t 5 /nobreak >nul & type "{mq5_path.replace(".mq5", ".log")}" 2>nul'
    out, _ = ssh_cmd(cmd, timeout=30)
    
    # Parse result
    errors = 0
    warnings = 0
    result_match = re.search(r'Result:\s*(\d+)\s*errors?,\s*(\d+)\s*warnings?', out)
    if result_match:
        errors = int(result_match.group(1))
        warnings = int(result_match.group(2))
    
    return errors, warnings, out

def create_backtest_ini(ea_path, symbol, period, from_date, to_date, report_name):
    """Create MT5 Strategy Tester INI config"""
    ini_content = f"""[Tester]
Expert={ea_path}
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
ExecutionMode=0
"""
    return ini_content

def run_backtest(ea_name, ea_path, symbol, period, from_date, to_date):
    """Run a single backtest"""
    report_name = f"{ea_name}_{symbol}_{period}_{from_date.replace('.','')}"
    
    # Create reports directory
    ssh_cmd(f'mkdir "{MT5_DATA}\\reports" 2>nul')
    
    # Create INI content
    ini_content = create_backtest_ini(ea_path, symbol, period, from_date, to_date, report_name)
    
    # Write INI to temp file on Windows
    ini_path = f"{MT5_DATA}\\tester\\backtest_auto.ini"
    
    # Use echo to write the INI file (escape for cmd)
    # Write line by line to avoid escaping issues
    lines = ini_content.strip().split('\n')
    # First line with > (overwrite), rest with >> (append)
    for i, line in enumerate(lines):
        op = '>' if i == 0 else '>>'
        line_escaped = line.replace('\\', '\\\\').strip()
        ssh_cmd(f'echo {line_escaped} {op} "{ini_path}"')
    
    # Verify INI was written
    out, _ = ssh_cmd(f'type "{ini_path}" 2>nul')
    if '[Tester]' not in out:
        print(f"  ❌ Failed to write INI file")
        return None
    
    print(f"  📄 INI config written")
    
    # Kill existing MT5
    kill_mt5()
    time.sleep(2)
    
    # Start MT5 with config
    print(f"  🚀 Starting MT5 Strategy Tester...")
    ssh_cmd(f'start "" "{MT5_EXE}" /config:"{ini_path}"', timeout=10)
    
    # Wait for MT5 to start
    time.sleep(5)
    
    # Poll for completion (MT5 shuts down when done due to ShutdownTerminal=1)
    max_wait = 300  # 5 minutes max per test
    start_time = time.time()
    
    while time.time() - start_time < max_wait:
        if not is_mt5_running():
            print(f"  ✅ MT5 exited — backtest complete ({int(time.time()-start_time)}s)")
            break
        time.sleep(5)
        elapsed = int(time.time() - start_time)
        if elapsed % 30 == 0:
            print(f"  ⏳ Waiting... {elapsed}s")
    else:
        print(f"  ⚠️ Timeout after {max_wait}s — killing MT5")
        kill_mt5()
    
    # Read report
    report_path = f"{MT5_DATA}\\reports\\{report_name}.xml"
    report_htm = f"{MT5_DATA}\\reports\\{report_name}.htm"
    
    # Try to read the HTM report
    out, rc = ssh_cmd(f'type "{report_htm}" 2>nul')
    if rc == 0 and len(out) > 100:
        return parse_htm_report(out, report_name)
    
    # Try XML
    out, rc = ssh_cmd(f'type "{report_path}" 2>nul')
    if rc == 0 and len(out) > 100:
        return parse_xml_report(out, report_name)
    
    # Check tester logs for today
    today = datetime.now().strftime("%Y%m%d")
    out, _ = ssh_cmd(f'type "{MT5_DATA}\\tester\\logs\\{today}.log" 2>nul')
    if out:
        return parse_tester_log(out, report_name)
    
    print(f"  ❌ No report found")
    return None

def parse_htm_report(html, name):
    """Parse MT5 HTML backtest report"""
    result = {"name": name}
    
    # Extract key metrics from HTML
    patterns = {
        "total_net_profit": r'Total Net Profit.*?>([-\d\s.]+)<',
        "gross_profit": r'Gross Profit.*?>([-\d\s.]+)<',
        "gross_loss": r'Gross Loss.*?>([-\d\s.]+)<',
        "profit_factor": r'Profit Factor.*?>([-\d\s.]+)<',
        "total_trades": r'Total Trades.*?>(\d+)<',
        "win_rate": r'(?:Win|Profit).*?Trades.*?>([\d.]+)%?<',
        "max_drawdown": r'(?:Max|Maximal).*?[Dd]rawdown.*?>([-\d\s.]+)',
        "sharpe_ratio": r'Sharpe Ratio.*?>([-\d\s.]+)<',
    }
    
    for key, pattern in patterns.items():
        match = re.search(pattern, html, re.IGNORECASE | re.DOTALL)
        if match:
            val = match.group(1).strip().replace(' ', '')
            try:
                result[key] = float(val)
            except ValueError:
                result[key] = val
    
    return result

def parse_xml_report(xml, name):
    """Parse MT5 XML backtest report"""
    result = {"name": name}
    
    patterns = {
        "total_net_profit": r'<ProfitNet>([-\d.]+)',
        "total_trades": r'<TotalDeals>(\d+)',
        "profit_factor": r'<ProfitFactor>([-\d.]+)',
        "max_drawdown": r'<MaxDrawdown>([-\d.]+)',
        "sharpe_ratio": r'<SharpeRatio>([-\d.]+)',
    }
    
    for key, pattern in patterns.items():
        match = re.search(pattern, xml)
        if match:
            try:
                result[key] = float(match.group(1))
            except ValueError:
                result[key] = match.group(1)
    
    return result

def parse_tester_log(log, name):
    """Parse MT5 tester log for basic results"""
    result = {"name": name, "log_excerpt": ""}
    
    # Get last 30 lines
    lines = log.strip().split('\n')
    result["log_excerpt"] = '\n'.join(lines[-30:])
    
    # Look for profit/trade info in log
    for line in lines:
        if 'profit' in line.lower() or 'trade' in line.lower() or 'result' in line.lower():
            result["log_excerpt"] = line
    
    return result


# ============================================================================
# MAIN
# ============================================================================
def main():
    print("=" * 70)
    print("  MT5 AUTO BACKTEST — Remote Strategy Tester")
    print("=" * 70)
    print(f"  Server: {SSH_HOST}")
    print(f"  MT5: {MT5_EXE}")
    print(f"  Tests: {len(TESTS)}")
    print(f"  Deposit: ${DEPOSIT:,} | Leverage: {LEVERAGE}")
    print("=" * 70)
    
    # Step 1: Test SSH
    print("\n🔌 Testing SSH connection...")
    out, rc = ssh_cmd("echo OK")
    if "OK" not in out:
        print("❌ Cannot connect to Windows Server!")
        sys.exit(1)
    print("✅ SSH connected")
    
    # Step 2: Upload & compile EAs
    print("\n📤 Uploading & compiling EAs...")
    ea_folders = set()
    for test in TESTS:
        ea_name = test[0]
        ea_folder = ea_name  # Scalper, Reversal, Breakout
        ea_folders.add((ea_name, ea_folder))
    
    for ea_name, ea_folder in ea_folders:
        local_file = os.path.join(LOCAL_MQL5, ea_folder, f"Expert {ea_name}.mq5")
        remote_dir = f"C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/53785E099C927DB68A545C249CDBCE06/MQL5/Experts/{ea_folder}/"
        
        if not os.path.exists(local_file):
            print(f"  ⚠️ {local_file} not found locally, skipping upload")
            continue
            
        print(f"  📤 Uploading {ea_name}...")
        if scp_upload(local_file, remote_dir):
            print(f"  ✅ {ea_name} uploaded")
        else:
            print(f"  ❌ {ea_name} upload failed!")
            continue
        
        print(f"  🔨 Compiling {ea_name}...")
        errors, warnings, log = compile_ea(f"Experts\\{ea_folder}\\Expert {ea_name}")
        if errors == 0:
            print(f"  ✅ {ea_name} compiled: {errors} errors, {warnings} warnings")
        else:
            print(f"  ❌ {ea_name} compile FAILED: {errors} errors")
            print(f"     {log[-300:]}")
    
    # Step 3: Run backtests
    print(f"\n🧪 Running {len(TESTS)} backtests...")
    results = []
    
    for i, (ea_name, ea_path, symbol, period, from_date, to_date) in enumerate(TESTS):
        print(f"\n{'─'*60}")
        print(f"  [{i+1}/{len(TESTS)}] {ea_name} | {symbol} | {period} | {from_date}→{to_date}")
        print(f"{'─'*60}")
        
        result = run_backtest(ea_name, ea_path, symbol, period, from_date, to_date)
        if result:
            results.append(result)
            print(f"  📊 Result: {result}")
        else:
            results.append({"name": f"{ea_name}_{symbol}", "error": "No report"})
    
    # Step 4: Summary
    print(f"\n{'='*70}")
    print(f"  BACKTEST RESULTS SUMMARY")
    print(f"{'='*70}")
    print(f"  {'Test':<30} {'Profit':>10} {'Trades':>8} {'PF':>8} {'DD%':>8}")
    print(f"  {'─'*66}")
    
    for r in results:
        name = r.get("name", "?")[:30]
        profit = r.get("total_net_profit", "N/A")
        trades = r.get("total_trades", "N/A")
        pf = r.get("profit_factor", "N/A")
        dd = r.get("max_drawdown", "N/A")
        
        if isinstance(profit, (int, float)):
            profit = f"${profit:,.2f}"
        if isinstance(pf, (int, float)):
            pf = f"{pf:.2f}"
        if isinstance(dd, (int, float)):
            dd = f"${dd:,.2f}"
            
        print(f"  {name:<30} {str(profit):>10} {str(trades):>8} {str(pf):>8} {str(dd):>8}")
    
    print(f"{'='*70}")
    
    # Restart MT5 normally
    print("\n🔄 Restarting MT5...")
    ssh_cmd(f'start "" "{MT5_EXE}"', timeout=10)
    
    return results

if __name__ == "__main__":
    main()
