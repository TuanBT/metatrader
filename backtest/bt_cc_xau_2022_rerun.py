#!/usr/bin/env python3
"""Rerun XAUUSDm H4 EMA50+ADX25 2022 (log error in multipair test)."""
import subprocess, time, re, os
from datetime import datetime

SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = "PNS1G3e7oc3h6PWJD4dsA"
MT5_DATA   = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
EA_PATH    = r"Candle Counter\Expert Candle Counter"
DEPOSIT    = 500
LEVERAGE   = 100


def ssh(cmd, timeout=90):
    full = ["sshpass", "-p", SSH_PASS, "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=15",
            f"{SSH_USER}@{SSH_HOST}", cmd]
    try:
        r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
        return (r.stdout + "\n" + r.stderr).strip()
    except Exception as e:
        return f"ERROR: {e}"


def kill_mt5():
    ssh("taskkill /f /im terminal64.exe 2>nul")
    time.sleep(3)


def mt5_running():
    return "terminal64.exe" in ssh('tasklist /fi "IMAGENAME eq terminal64.exe" /nh 2>nul').lower()


def get_date():
    out = ssh('powershell -Command "Get-Date -Format yyyyMMdd"')
    for ln in out.splitlines():
        ln = ln.strip()
        if len(ln) == 8 and ln.isdigit():
            return ln
    return datetime.now().strftime("%Y%m%d")


def find_log(date_str):
    ps = (f"$f=Get-ChildItem '{MT5_TESTER}\\Agent-127.0.0.1-*\\logs\\{date_str}.log' "
          f"-ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select -First 1;"
          f"if($f){{Write-Host $f.FullName}}else{{Write-Host 'NOT_FOUND'}}")
    out = ssh(f'powershell -Command "{ps}"', timeout=30)
    for ln in out.splitlines():
        ln = ln.strip()
        if ln and ".log" in ln and "NOT_FOUND" not in ln:
            return ln
    return None


def del_logs(date_str):
    ps = (f"Get-ChildItem '{MT5_TESTER}\\Agent-127.0.0.1-*\\logs\\{date_str}.log' "
          f"-ErrorAction SilentlyContinue | Remove-Item -Force")
    ssh(f'powershell -Command "{ps}"', timeout=30)


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
        f'echo Leverage={LEVERAGE} >> "{ini}"',
        f'echo [TesterInputs] >> "{ini}"',
    ]
    for k, v in inputs.items():
        lines.append(f'echo {k}={v} >> "{ini}"')
    ssh(" && ".join(lines), timeout=90)
    date_str = get_date()
    del_logs(date_str)
    ssh('schtasks /delete /tn "MT5BT" /f 2>nul')
    ssh(f'schtasks /create /tn "MT5BT" '
        f'/tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\" /config:\\"{ini}\\"" '
        f'/sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5BT" 2>&1')
    return date_str


def wait_done(max_wait=780):
    start = time.time()
    time.sleep(40)
    while time.time() - start < max_wait:
        if not mt5_running():
            time.sleep(12)
            return True
        time.sleep(12)
    kill_mt5()
    return False


def read_log(date_str):
    log = find_log(date_str)
    if not log:
        return "NO_LOG_FILE"
    ps = (f"$log='{log}';"
          f"$d=(Select-String $log -Pattern 'deal performed').Count;"
          f"$s=(Select-String $log -Pattern 'stop loss triggered').Count;"
          f"$bal=(Select-String $log -Pattern 'final balance'|Select -Last 1);"
          f"Write-Host \"DEALS=$d\"; Write-Host \"SL=$s\";"
          f"if($bal){{Write-Host $bal.Line}}")
    return ssh(f'powershell -Command "{ps}"', timeout=60)


CFG = {
    "InpLotSize": "0.01", "InpDeviation": "20", "InpMagic": "20260225",
    "InpOnePosition": "true", "InpMinBodyPct": "0.0", "InpMinCandleATR": "0.0",
    "InpATRPeriod": "14", "InpUseTimeFilter": "false", "InpStartHour": "7",
    "InpEndHour": "21", "InpEMATF": "0", "InpADXPeriod": "14",
    "InpUseEMAFilter": "true", "InpEMAPeriod": "50",
    "InpUseADXFilter": "true", "InpADXMinValue": "25.0",
}

print("[XAUUSDm H4 EMA50+ADX25 — 2022]")
kill_mt5()
date_str = run_bt("XAUUSDm", "H4", "2022.01.01", "2023.01.01", CFG)
print(f"Running... date_str={date_str}")
wait_done(780)
raw = read_log(date_str)
print("RAW:", raw[:400])
m = re.search(r'final balance\s+([\d.]+)\s+USD', raw, re.IGNORECASE)
if m:
    bal = float(m.group(1))
    p = bal - DEPOSIT
    dm = re.search(r'DEALS=(\d+)', raw)
    sm = re.search(r'SL=(\d+)', raw)
    d = int(dm.group(1)) if dm else 0
    s = int(sm.group(1)) if sm else 0
    wr = round((d - s) / d * 100) if d else 0
    print(f"\nRESULT: ${p:+.2f} ({p/DEPOSIT*100:+.2f}%)  Deals={d}  SL={s}  WR={wr}%")
else:
    print("No final balance found in log")
