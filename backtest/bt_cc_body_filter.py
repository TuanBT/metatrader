#!/usr/bin/env python3
"""
CC v1.3 — Body Filter Test
Test MinBodyPct = 20%, 30%, 40% on XAUUSDm + USDJPYm, H4, 2022-2025
Compare vs baseline (0%) to see if WR improves.
2 pairs × 3 body values × 4 years = 24 tests
"""
import subprocess, time, re, os
from datetime import datetime
from collections import defaultdict

SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")
MT5_DATA   = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
EA_PATH    = r"Candle Counter\Expert Candle Counter"
DEPOSIT    = 500
LEVERAGE   = 100
RESULT_MD  = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "bt_cc_body_filter_results.md")


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
    return "terminal64.exe" in ssh(
        'tasklist /fi "IMAGENAME eq terminal64.exe" /nh 2>nul').lower()


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
    d = get_date()
    del_logs(d)
    ssh('schtasks /delete /tn "MT5BT" /f 2>nul')
    ssh(f'schtasks /create /tn "MT5BT" '
        f'/tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\" /config:\\"{ini}\\"" '
        f'/sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5BT" 2>&1')
    return d


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


def parse_log(raw):
    m = re.search(r'final balance\s+([\d.]+)\s+USD', raw, re.IGNORECASE)
    if m:
        bal = float(m.group(1))
        p = bal - DEPOSIT
        dm = re.search(r'DEALS=(\d+)', raw)
        sm = re.search(r'SL=(\d+)', raw)
        d = int(dm.group(1)) if dm else 0
        s = int(sm.group(1)) if sm else 0
        wr = round((d - s) / d * 100) if d else 0
        return {"profit": p, "profit_pct": p / DEPOSIT * 100,
                "deals": d, "sl": s, "wr": wr}
    if "thread finished" in raw.lower():
        return {"profit": 0, "profit_pct": 0, "deals": 0, "sl": 0, "wr": 0}
    return {"error": raw[:120]}


BASE = {
    "InpLotSize": "0.01", "InpDeviation": "20", "InpMagic": "20260225",
    "InpOnePosition": "true", "InpMinCandleATR": "0.0", "InpATRPeriod": "14",
    "InpUseTimeFilter": "false", "InpStartHour": "7", "InpEndHour": "21",
    "InpEMATF": "0", "InpADXPeriod": "14",
    "InpUseEMAFilter": "true", "InpEMAPeriod": "50",
    "InpUseADXFilter": "true", "InpADXMinValue": "25.0",
}

PAIRS = ["XAUUSDm", "USDJPYm"]
BODY_VALS = ["0.0", "20.0", "30.0", "40.0"]   # 0% = baseline
YEARS = [
    ("2022.01.01", "2023.01.01", "2022"),
    ("2023.01.01", "2024.01.01", "2023"),
    ("2024.01.01", "2025.01.01", "2024"),
    ("2025.01.01", "2026.02.01", "2025"),
]

# Known baselines from multipair test (body=0%)
BASELINE = {
    ("XAUUSDm", "2022"): {"profit_pct": -9.13, "deals": 168, "wr": 50},
    ("XAUUSDm", "2023"): {"profit_pct": 15.12, "deals": 160, "wr": 50},
    ("XAUUSDm", "2024"): {"profit_pct": 25.32, "deals": 222, "wr": 50},
    ("XAUUSDm", "2025"): {"profit_pct": 153.95, "deals": 224, "wr": 50},
    ("USDJPYm", "2022"): {"profit_pct": 11.08, "deals": 178, "wr": 51},
    ("USDJPYm", "2023"): {"profit_pct": 1.56,  "deals": 168, "wr": 50},
    ("USDJPYm", "2024"): {"profit_pct": 28.21, "deals": 160, "wr": 51},
    ("USDJPYm", "2025"): {"profit_pct": 5.52,  "deals": 202, "wr": 50},
}

TESTS = [
    (p, bv, yr_from, yr_to, yr)
    for bv in BODY_VALS if bv != "0.0"   # skip baseline
    for p in PAIRS
    for (yr_from, yr_to, yr) in YEARS
]

results = {k: v for k, v in BASELINE.items()}   # pre-populated baseline


def save_md():
    ts = datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [
        f"# CC v1.3 — Body% Filter Comparison [{ts}]",
        "**H4 | EMA50+ADX25 | XAUUSDm + USDJPYm | 2022-2025**\n",
        "## P&L% (positive=bold)\n",
    ]
    yr_list = [y for _, _, y in YEARS]
    for pair in PAIRS:
        lines.append(f"### {pair}")
        header = "| Body% | " + " | ".join(yr_list) + " | +/n | Avg Deals |"
        sep    = "|---|" + "---|" * (len(yr_list) + 2)
        lines += [header, sep]
        for bv in BODY_VALS:
            row = []
            pos = 0
            total_deals = 0
            n = 0
            for yr in yr_list:
                d = results.get((pair, bv, yr)) or results.get((pair, yr))
                if d and "error" not in d:
                    pp = d["profit_pct"]
                    wr = d.get("wr", 0)
                    deals = d.get("deals", 0)
                    total_deals += deals
                    n += 1
                    cell = f"{'**' if pp > 0 else ''}{pp:+.1f}% WR{wr}%{'**' if pp > 0 else ''}"
                    row.append(cell)
                    if pp > 0:
                        pos += 1
                else:
                    row.append("—")
            avg_d = round(total_deals / n) if n else 0
            label = f"{bv}%" if bv != "0.0" else "0% (base)"
            lines.append(f"| {label} | {' | '.join(row)} | {pos}/{n} | {avg_d} |")
        lines.append("")
    with open(RESULT_MD, "w") as f:
        f.write("\n".join(lines) + "\n")


total = len(TESTS)
for idx, (pair, bv, yr_from, yr_to, yr) in enumerate(TESTS, 1):
    label = f"{pair} Body{bv}% {yr}"
    print(f"\n[{idx}/{total}] {label}")
    kill_mt5()
    cfg = dict(BASE)
    cfg["InpMinBodyPct"] = bv
    date_str = run_bt(pair, "H4", yr_from, yr_to, cfg)
    wait_done(780)
    raw = read_log(date_str)
    parsed = parse_log(raw)
    if "error" in parsed:
        err = parsed["error"]
        print(f"  ERROR: {err}")
    else:
        pp = parsed["profit_pct"]
        wr = parsed["wr"]
        nd = parsed["deals"]
        print(f"  P&L: ${parsed['profit']:+.2f} ({pp:+.2f}%)  Deals={nd}  WR={wr}%")
    results[(pair, bv, yr)] = parsed
    save_md()

save_md()
print(f"\nDone → {RESULT_MD}")
