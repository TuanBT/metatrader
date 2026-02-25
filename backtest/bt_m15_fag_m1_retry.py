#!/usr/bin/env python3
"""Retry M1 2024 tests that previously returned no-log errors."""
import subprocess, time, re, os
from datetime import datetime

SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = "PNS1G3e7oc3h6PWJD4dsA"
MT5_DATA   = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
AGENT_LOGS = MT5_TESTER + r"\Agent-127.0.0.1-3000\logs"
EA_PATH    = r"M15 Impulse FAG Entry\Expert M15 Impulse FAG Entry"
DEPOSIT    = 500

def ssh(cmd, timeout=120):
    full = ["sshpass", "-p", SSH_PASS, "ssh", "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=15", f"{SSH_USER}@{SSH_HOST}", cmd]
    try:
        r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
        return (r.stdout + "\n" + r.stderr).strip()
    except:
        return "ERROR"

def kill_mt5():
    ssh('taskkill /f /im terminal64.exe 2>nul')
    time.sleep(5)

def mt5_running():
    return "terminal64.exe" in ssh('tasklist /fi "IMAGENAME eq terminal64.exe" /nh 2>nul').lower()

def get_date():
    out = ssh('powershell -Command "Get-Date -Format yyyyMMdd"')
    for ln in out.splitlines():
        ln = ln.strip()
        if len(ln) == 8 and ln.isdigit():
            return ln
    return datetime.now().strftime("%Y%m%d")

def run_bt(symbol, period, from_d, to_d, inputs):
    ini = f"{MT5_DATA}\\tester\\backtest_auto.ini"
    lines = [
        f'echo [Tester] > "{ini}"',
        f'echo Expert={EA_PATH} >> "{ini}"',
        f'echo Symbol={symbol} >> "{ini}"',
        f'echo Period={period} >> "{ini}"',
        f'echo Model=1 >> "{ini}"',
        f'echo Optimization=0 >> "{ini}"',
        f'echo FromDate={from_d} >> "{ini}"',
        f'echo ToDate={to_d} >> "{ini}"',
        f'echo ReplaceReport=1 >> "{ini}"',
        f'echo ShutdownTerminal=1 >> "{ini}"',
        f'echo Deposit={DEPOSIT} >> "{ini}"',
        f'echo Currency=USD >> "{ini}"',
        f'echo Leverage=100 >> "{ini}"',
        f'echo [TesterInputs] >> "{ini}"',
    ]
    for k, v in inputs.items():
        lines.append(f'echo {k}={v} >> "{ini}"')
    ssh(" && ".join(lines), timeout=90)
    ssh(f'del "{AGENT_LOGS}\\{get_date()}.log" 2>nul')
    ssh('schtasks /delete /tn "MT5BT" /f 2>nul')
    ssh(f'schtasks /create /tn "MT5BT" '
        f'/tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\" /config:\\"{ini}\\"" '
        f'/sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5BT" 2>&1')

def wait_done(max_wait=900):
    start = time.time()
    time.sleep(45)
    while time.time() - start < max_wait:
        if not mt5_running():
            time.sleep(12)
            return True
        time.sleep(12)
    kill_mt5(); return False

def read_log(date_str):
    log = f"{AGENT_LOGS}\\{date_str}.log"
    ps = (f"$log='{log}';"
          f"if(-not(Test-Path $log)){{Write-Host 'NO_LOG_FILE';exit}};"
          f"$d=(Select-String $log -Pattern 'deal performed').Count;"
          f"$s=(Select-String $log -Pattern 'stop loss triggered').Count;"
          f"$bal=(Select-String $log -Pattern 'final balance'|Select -Last 1);"
          f"Write-Host \"DEALS=$d\"; Write-Host \"SL=$s\";"
          f"if($bal){{Write-Host $bal.Line}}")
    return ssh(f'powershell -Command "{ps}"', timeout=90)

BASE = {
    "InpUseMoneyRisk":"true","InpRiskMoney":"10.0","InpLotSize":"0.01",
    "InpMaxDailyLossPct":"0.0","InpATRLen":"14","InpATRMult":"1.2",
    "InpBodyRatioMin":"0.55","InpDeviation":"20","InpMagic":"20260224",
    "InpOnePosition":"true","InpExpiryMinutes":"0","InpMinZonePips":"0.0",
    "InpSLBufferPips":"0.0","InpMaxZoneBars":"0","InpUseTimeFilter":"true",
    "InpStartHour":"2","InpEndHour":"21","InpEMAFastPeriod":"20",
    "InpEMASlowPeriod":"50","InpMTFTrail":"true","InpMTFTrailStartR":"0.5",
    "InpMTFTrailStepR":"0.25",
}

RETRY = [
    ("M1 MinAg=3 2024",  "true",  "3"),
    ("M1 NoFilter 2024", "false", "3"),
]

for (label, usemtf, minag) in RETRY:
    print(f"\n[{label}]")
    kill_mt5()
    date_str = get_date()
    cfg = dict(BASE)
    cfg["InpUseMTFConsensus"] = usemtf
    cfg["InpMTFMinAgree"]     = minag
    run_bt("XAUUSDm", "M1", "2024.01.01", "2025.01.01", cfg)
    wait_done(max_wait=900)
    raw = read_log(date_str)
    m = re.search(r'final balance\s+([\d.]+)\s+USD', raw, re.IGNORECASE)
    if m:
        bal = float(m.group(1)); p = bal - DEPOSIT
        dm = re.search(r'DEALS=(\d+)', raw)
        sm = re.search(r'(?<!\w)SL=(\d+)', raw)
        d  = int(dm.group(1)) if dm else 0
        s  = int(sm.group(1)) if sm else 0
        pct = p / DEPOSIT * 100
        print(f"  P&L: ${p:+.2f} ({pct:+.2f}%)  Deals={d}  SL={s}")
    else:
        print(f"  ERROR: {raw[:200]}")
