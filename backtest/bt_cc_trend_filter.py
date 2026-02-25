#!/usr/bin/env python3
"""
Candle Counter v1.5 + Trend Structure Filter — Backtest
Compares results WITH the new higher-low/lower-high filter.
Same test cases as bt_cc_v15_extended.py for direct comparison.
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
RESULT_MD  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bt_cc_trend_filter_results.md")


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


def wait_done(max_wait=900):
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
    "InpUseEMAFilter": "true",
    "InpEMAPeriod": "50",
    "InpEMATF": "0",
    "InpUseADXFilter": "true",
    "InpADXPeriod": "14",
    "InpADXMinValue": "25.0",
    "InpSLLookback": "5",
}

# Old results for comparison (v1.5 without trend filter)
OLD_RESULTS = {
    "USDJPYm H4 2025": {"pct": 2.79, "deals": 204, "sl": 102, "wr": 50},
    "USDJPYm H4 2024": {"pct": 24.62, "deals": 160, "sl": 79, "wr": 51},
    "USDJPYm H4 2023": {"pct": -0.22, "deals": 168, "sl": 84, "wr": 50},
    "USDJPYm H4 2022": {"pct": 8.35, "deals": 178, "sl": 88, "wr": 51},
    "XAUUSDm H1 2025":  {"pct": 3.93, "deals": 722, "sl": 361, "wr": 50},
    "XAUUSDm H1 2024":  {"pct": -61.17, "deals": 680, "sl": 340, "wr": 50},
    "XAUUSDm M15 2025": {"pct": -94.14, "deals": 2544, "sl": 1272, "wr": 50},
    "XAUUSDm M15 2024": {"pct": 7.99, "deals": 2540, "sl": 1270, "wr": 50},
}

# (label, symbol, tf, from, to, max_wait)
TESTS = [
    ("USDJPYm H4 2025", "USDJPYm", "H4", "2025.01.01", "2026.02.01", 600),
    ("USDJPYm H4 2024", "USDJPYm", "H4", "2024.01.01", "2025.01.01", 600),
    ("USDJPYm H4 2023", "USDJPYm", "H4", "2023.01.01", "2024.01.01", 600),
    ("USDJPYm H4 2022", "USDJPYm", "H4", "2022.01.01", "2023.01.01", 600),
    ("XAUUSDm H1 2025", "XAUUSDm", "H1", "2025.01.01", "2026.02.01", 780),
    ("XAUUSDm H1 2024", "XAUUSDm", "H1", "2024.01.01", "2025.01.01", 780),
    ("XAUUSDm M15 2025", "XAUUSDm", "M15", "2025.01.01", "2026.02.01", 900),
    ("XAUUSDm M15 2024", "XAUUSDm", "M15", "2024.01.01", "2025.01.01", 900),
]


def main():
    results = []

    for (label, symbol, tf, from_d, to_d, mw) in TESTS:
        print(f"\n[{label}]")
        kill_mt5()

        cfg = dict(BASE)
        date_str = write_ini_and_run(symbol, tf, from_d, to_d, cfg)
        wait_done(max_wait=mw)
        raw = read_log(date_str)
        parsed = parse_log(raw)

        if parsed:
            old = OLD_RESULTS.get(label)
            delta = ""
            if old:
                diff = parsed['pct'] - old['pct']
                deal_diff = parsed['deals'] - old['deals']
                delta = f"  (vs old: {diff:+.2f}%, deals {deal_diff:+d})"
            print(f"  P&L: ${parsed['profit']:+.2f} ({parsed['pct']:+.2f}%)  "
                  f"Deals={parsed['deals']}  SL={parsed['sl']}  WR={parsed['wr']}%{delta}")
            results.append({"label": label, "symbol": symbol, "tf": tf, **parsed})
        else:
            print(f"  No result: {raw[:200]}")
            results.append({"label": label, "symbol": symbol, "tf": tf, "error": raw[:160]})

    # ── Markdown ──
    ts = datetime.now().strftime("%Y-%m-%d %H:%M")
    md = [
        f"# Candle Counter v1.5 + Trend Structure Filter",
        f"*Generated: {ts}*",
        f"**EMA50 + ADX25 + Higher Low/Lower High Filter | Lot=0.01 | SL Lookback=5**\n",
        f"New filter: BUY requires 3 green candles with higher lows; SELL requires 3 red candles with lower highs.\n",
        "| Symbol | TF | Year | P&L (new) | P&L% (new) | Deals (new) | WR% (new) | P&L% (old) | Deals (old) | Delta |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]

    for r in results:
        yr = r['label'].split()[-1]
        old = OLD_RESULTS.get(r['label'])
        if "error" in r:
            md.append(f"| {r['symbol']} | {r['tf']} | {yr} | — | — | — | — | — | — | error |")
        elif old:
            diff = r['pct'] - old['pct']
            arrow = "▲" if diff > 0 else "▼" if diff < 0 else "="
            md.append(f"| {r['symbol']} | {r['tf']} | {yr} | ${r['profit']:+.2f} | "
                      f"{r['pct']:+.2f}% | {r['deals']} | {r['wr']}% | "
                      f"{old['pct']:+.2f}% | {old['deals']} | {arrow} {diff:+.2f}% |")
        else:
            md.append(f"| {r['symbol']} | {r['tf']} | {yr} | ${r['profit']:+.2f} | "
                      f"{r['pct']:+.2f}% | {r['deals']} | {r['wr']}% | — | — | — |")

    with open(RESULT_MD, "w") as f:
        f.write("\n".join(md) + "\n")
    print(f"\nResults → {RESULT_MD}")

    # Summary
    print("\n── Comparison Summary ──")
    improved = 0
    worse = 0
    for r in results:
        if "error" not in r:
            old = OLD_RESULTS.get(r['label'])
            if old:
                diff = r['pct'] - old['pct']
                deal_diff = r['deals'] - old['deals']
                arrow = "▲" if diff > 0 else "▼"
                tag = "✅" if diff > 0 else "❌"
                print(f"  {tag} {r['label']}: {r['pct']:+.2f}% vs {old['pct']:+.2f}% ({arrow}{abs(diff):.2f}%)  "
                      f"Deals: {r['deals']} vs {old['deals']} ({deal_diff:+d})")
                if diff > 0:
                    improved += 1
                else:
                    worse += 1

    print(f"\n  Improved: {improved}/{improved+worse}  Worse: {worse}/{improved+worse}")


if __name__ == "__main__":
    main()
