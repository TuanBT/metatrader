#!/usr/bin/env python3
"""
Candle Counter v1.5 — SL Lookback Comparison
Compare SL lookback=3 (original bar[3]) vs lookback=5 vs lookback=7
Tests: XAUUSDm H4 EMA50+ADX25, years 2022-2025
"""

import subprocess, time, re, os
from datetime import datetime

SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")

MT5_DATA   = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
EA_PATH    = r"Candle Counter\Expert Candle Counter"
DEPOSIT    = 500
LEVERAGE   = 100
RESULT_MD  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bt_cc_sl_lookback_results.md")


def ssh(cmd, timeout=90):
    full = ["sshpass", "-p", SSH_PASS, "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=15",
            "-o", "ServerAliveInterval=20",
            f"{SSH_USER}@{SSH_HOST}", cmd]
    try:
        r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
        return (r.stdout + "\n" + r.stderr).strip()
    except:
        return "ERROR"


def kill_mt5():
    ssh('taskkill /f /im terminal64.exe 2>nul')
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


def write_ini_and_run(symbol, period, from_d, to_d, inputs):
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


def parse_log(raw):
    m = re.search(r'final balance\s+([\d.]+)\s+USD', raw, re.IGNORECASE)
    if m:
        bal = float(m.group(1))
        p = bal - DEPOSIT
        d = int(re.search(r'DEALS=(\d+)', raw).group(1)) if re.search(r'DEALS=(\d+)', raw) else 0
        s = int(re.search(r'(?<!\w)SL=(\d+)', raw).group(1)) if re.search(r'(?<!\w)SL=(\d+)', raw) else 0
        wr = round((d - s) / d * 100) if d else 0
        return {"balance": bal, "profit": p, "pct": p / DEPOSIT * 100, "deals": d, "sl": s, "wr": wr}
    return None


BASE = {
    "InpLotSize": "0.01",
    "InpDeviation": "20",
    "InpMagic": "20260225",
    "InpOnePosition": "true",
    "InpUseTimeFilter": "false",
    "InpStartHour": "7",
    "InpEndHour": "21",
    "InpEMATF": "0",
    "InpUseEMAFilter": "true",
    "InpEMAPeriod": "50",
    "InpUseADXFilter": "true",
    "InpADXPeriod": "14",
    "InpADXMinValue": "25.0",
}

# Test matrix: (label, lookback, tf, from, to)
TESTS = []
for lb in [3, 5, 7]:
    for (yr_label, yr_from, yr_to) in [
        ("2025", "2025.01.01", "2026.02.01"),
        ("2024", "2024.01.01", "2025.01.01"),
        ("2023", "2023.01.01", "2024.01.01"),
        ("2022", "2022.01.01", "2023.01.01"),
    ]:
        TESTS.append((f"LB={lb} H4 {yr_label}", lb, "H4", yr_from, yr_to))


def main():
    results = []

    for (label, lookback, tf, from_d, to_d) in TESTS:
        print(f"\n[{label}]")
        kill_mt5()

        cfg = dict(BASE)
        cfg["InpSLLookback"] = str(lookback)

        date_str = write_ini_and_run("XAUUSDm", tf, from_d, to_d, cfg)
        wait_done(780)
        raw = read_log(date_str)
        parsed = parse_log(raw)

        if parsed:
            print(f"  P&L: ${parsed['profit']:+.2f} ({parsed['pct']:+.2f}%)  "
                  f"Deals={parsed['deals']}  SL={parsed['sl']}  WR={parsed['wr']}%")
            results.append({"label": label, "lb": lookback, **parsed})
        else:
            print(f"  No result: {raw[:200]}")
            results.append({"label": label, "lb": lookback, "error": raw[:160]})

    # ── Markdown ──
    ts = datetime.now().strftime("%Y-%m-%d %H:%M")
    md = [
        f"# Candle Counter v1.5 — SL Lookback Comparison",
        f"*Generated: {ts}*",
        f"**XAUUSDm H4 | EMA50 + ADX25 | Lot=0.01**\n",
        "| Lookback | Year | P&L | P&L% | Deals | SL | WR% |",
        "|---|---|---|---|---|---|---|",
    ]

    for r in results:
        if "error" in r:
            md.append(f"| {r['lb']} | {r['label']} | — | — | — | — | error |")
        else:
            yr = r['label'].split()[-1]
            md.append(f"| {r['lb']} | {yr} | ${r['profit']:+.2f} | {r['pct']:+.2f}% | "
                      f"{r['deals']} | {r['sl']} | {r['wr']}% |")

    with open(RESULT_MD, "w") as f:
        f.write("\n".join(md) + "\n")
    print(f"\nResults → {RESULT_MD}")

    # Summary
    print("\n── Summary ──")
    for lb in [3, 5, 7]:
        group = [r for r in results if r.get("lb") == lb and "error" not in r]
        if group:
            total_pct = sum(r["pct"] for r in group)
            avg_wr = sum(r["wr"] for r in group) / len(group)
            print(f"  LB={lb}: Total P&L%={total_pct:+.2f}%  Avg WR={avg_wr:.0f}%")


if __name__ == "__main__":
    main()
