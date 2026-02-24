#!/usr/bin/env python3
"""Fill missing results: H4 EMA50+ADX20 2022 and H4 EMA50+ADX25 2023."""
import subprocess, time, re, os
from datetime import datetime

SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = "PNS1G3e7oc3h6PWJD4dsA"
MT5_DATA   = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
AGENT_LOGS = MT5_TESTER + r"\Agent-127.0.0.1-3000\logs"
EA_PATH    = r"Candle Counter\Expert Candle Counter"
DEPOSIT    = 500

def ssh(cmd, timeout=90):
    full = ["sshpass", "-p", SSH_PASS, "ssh",
            "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=15",
            "-o", "ServerAliveInterval=20", f"{SSH_USER}@{SSH_HOST}", cmd]
    try:
        r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
        return (r.stdout + "\n" + r.stderr).strip()
    except Exception as e:
        return f"ERROR: {e}"

def kill_mt5():
    ssh('taskkill /f /im terminal64.exe 2>nul'); time.sleep(3)

def mt5_running():
    return "terminal64.exe" in ssh('tasklist /fi "IMAGENAME eq terminal64.exe" /nh 2>nul').lower()

def get_date():
    out = ssh('powershell -Command "Get-Date -Format yyyyMMdd"')
    for ln in out.splitlines():
        ln = ln.strip()
        if len(ln) == 8 and ln.isdigit(): return ln
    return datetime.now().strftime("%Y%m%d")

def run_bt(tf, yr_from, yr_to, inputs):
    ini = f"{MT5_DATA}\\tester\\backtest_auto.ini"
    lines = [f'echo [Tester] > "{ini}"', f'echo Expert={EA_PATH} >> "{ini}"',
             f'echo Symbol=XAUUSDm >> "{ini}"', f'echo Period={tf} >> "{ini}"',
             f'echo Model=1 >> "{ini}"', f'echo Optimization=0 >> "{ini}"',
             f'echo FromDate={yr_from} >> "{ini}"', f'echo ToDate={yr_to} >> "{ini}"',
             f'echo ReplaceReport=1 >> "{ini}"', f'echo ShutdownTerminal=1 >> "{ini}"',
             f'echo Deposit={DEPOSIT} >> "{ini}"', f'echo Currency=USD >> "{ini}"',
             f'echo Leverage=100 >> "{ini}"', f'echo [TesterInputs] >> "{ini}"']
    for k, v in inputs.items():
        lines.append(f'echo {k}={v} >> "{ini}"')
    ssh(" && ".join(lines), timeout=60)
    ssh(f'del "{AGENT_LOGS}\\{get_date()}.log" 2>nul')
    ssh('schtasks /delete /tn "MT5BT" /f 2>nul')
    ssh(f'schtasks /create /tn "MT5BT" /tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\" /config:\\"{ini}\\"" /sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5BT" 2>&1')

def wait_done(max_wait=600):
    start = time.time(); time.sleep(40)
    while time.time() - start < max_wait:
        if not mt5_running():
            time.sleep(12); return True
        time.sleep(12)
    kill_mt5(); return False

def read_log(date_str):
    log = f"{AGENT_LOGS}\\{date_str}.log"
    ps  = (f"$log='{log}';if(-not(Test-Path $log)){{Write-Host 'NO_LOG_FILE';exit}};"
           f"$d=(Select-String $log -Pattern 'deal performed').Count;"
           f"$s=(Select-String $log -Pattern 'stop loss triggered').Count;"
           f"$bal=(Select-String $log -Pattern 'final balance'|Select -Last 1);"
           f"Write-Host 'DEALS='$d; Write-Host 'SL='$s;"
           f"if($bal){{Write-Host $bal.Line}}")
    return ssh(f'powershell -Command "{ps}"', timeout=60)

BASE = {
    "InpLotSize":"0.01","InpDeviation":"20","InpMagic":"20260225","InpOnePosition":"true",
    "InpMinBodyPct":"0.0","InpMinCandleATR":"0.0","InpATRPeriod":"14",
    "InpUseTimeFilter":"false","InpStartHour":"7","InpEndHour":"21","InpEMATF":"0","InpADXPeriod":"14",
}

tests = [
    ("H4 EMA50+ADX20 2022", "H4", "2022.01.01", "2023.01.01", "true", "50", "true", "20.0"),
    ("H4 EMA50+ADX25 2023", "H4", "2023.01.01", "2024.01.01", "true", "50", "true", "25.0"),
]

for (label, tf, yr_from, yr_to, use_ema, ema_p, use_adx, adx_min) in tests:
    print(f"\n[{label}]")
    kill_mt5()
    date_str = get_date()
    cfg = dict(BASE)
    cfg["InpUseEMAFilter"] = use_ema
    cfg["InpEMAPeriod"]    = ema_p
    cfg["InpUseADXFilter"] = use_adx
    cfg["InpADXMinValue"]  = adx_min
    run_bt(tf, yr_from, yr_to, cfg)
    wait_done(600)
    raw = read_log(date_str)
    m = re.search(r'final balance\s+([\d.]+)\s+USD', raw, re.IGNORECASE)
    if m:
        bal = float(m.group(1)); p = bal - DEPOSIT
        dm = re.search(r'DEALS=?\s*(\d+)', raw)
        sm = re.search(r'SL=?\s*(\d+)', raw)
        d = int(dm.group(1)) if dm else 0
        s = int(sm.group(1)) if sm else 0
        wr = round((d-s)/d*100) if d else 0
        print(f"  P&L: ${p:+.2f} ({p/DEPOSIT*100:+.2f}%)  Deals={d}  SL={s}  WR={wr}%")
    else:
        print(f"  RAW: {raw[:200]}")
