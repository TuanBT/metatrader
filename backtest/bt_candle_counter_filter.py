#!/usr/bin/env python3
"""
Candle Counter EA v1.1 — Filtered Backtest
Tests with MinBodyPct + ATR filter + time filter.
Goal: reduce trade count, improve quality.
"""

import subprocess, time, re, os
from datetime import datetime

SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")

MT5_DATA   = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
AGENT_LOGS = MT5_TESTER + r"\Agent-127.0.0.1-3000\logs"
EA_PATH    = r"Candle Counter\Expert Candle Counter"
DEPOSIT    = 500
LEVERAGE   = 100
RESULT_MD  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bt_candle_counter_filter_results.md")

BASE = {
    "InpLotSize":       "0.01",
    "InpDeviation":     "20",
    "InpMagic":         "20260225",
    "InpOnePosition":   "true",
    "InpATRPeriod":     "14",
}

# (tf, body_pct, atr_mult, start_h, end_h, label_suffix)
FILTER_CONFIGS = [
    # M5 tests
    ("M5",  "30", "0.0", "10", "19", "M5  Body30 Time10-19 NoATR"),
    ("M5",  "30", "0.3", "10", "19", "M5  Body30 Time10-19 ATR0.3"),
    ("M5",  "40", "0.5", "10", "19", "M5  Body40 Time10-19 ATR0.5"),
    # H1 tests
    ("H1",  "30", "0.0", "10", "19", "H1  Body30 Time10-19 NoATR"),
    ("H1",  "30", "0.3", "10", "19", "H1  Body30 Time10-19 ATR0.3"),
    ("H1",  "40", "0.5", "10", "19", "H1  Body40 Time10-19 ATR0.5"),
]

TESTS = []
for cfg in FILTER_CONFIGS:
    tf = cfg[0]
    for (yr_from, yr_to, yr) in [("2025.01.01", "2026.02.01", "2025"),
                                   ("2024.01.01", "2025.01.01", "2024")]:
        TESTS.append((*cfg, yr_from, yr_to, yr))


def ssh(cmd, timeout=90):
    full = ["sshpass", "-p", SSH_PASS, "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=15",
            "-o", "ServerAliveInterval=20",
            f"{SSH_USER}@{SSH_HOST}", cmd]
    try:
        r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
        return (r.stdout + "\n" + r.stderr).strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return f"ERROR: {e}"


def kill_mt5():
    ssh('taskkill /f /im terminal64.exe 2>nul')
    time.sleep(3)


def mt5_running():
    return "terminal64.exe" in ssh('tasklist /fi "IMAGENAME eq terminal64.exe" /nh 2>nul').lower()


def get_server_date():
    out = ssh('powershell -Command "Get-Date -Format yyyyMMdd"')
    for ln in out.splitlines():
        ln = ln.strip()
        if len(ln) == 8 and ln.isdigit():
            return ln
    return datetime.now().strftime("%Y%m%d")


def read_agent_log(date_str):
    log = f"{AGENT_LOGS}\\{date_str}.log"
    ps = (f"$log='{log}';"
          f"if(-not(Test-Path $log)){{Write-Host 'NO_LOG_FILE';exit}};"
          f"$d=(Select-String $log -Pattern 'deal performed').Count;"
          f"$s=(Select-String $log -Pattern 'stop loss triggered').Count;"
          f"$bal=(Select-String $log -Pattern 'final balance'|Select -Last 1);"
          f"Write-Host \"DEALS=$d\"; Write-Host \"SL=$s\";"
          f"if($bal){{Write-Host $bal.Line}}")
    return ssh(f'powershell -Command "{ps}"', timeout=60)


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
    out = ssh(" && ".join(lines), timeout=60)
    if "ERROR" in (out or "").upper():
        return False
    ssh(f'del "{AGENT_LOGS}\\{get_server_date()}.log" 2>nul')
    ssh('schtasks /delete /tn "MT5BT" /f 2>nul')
    ssh(f'schtasks /create /tn "MT5BT" '
        f'/tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\" /config:\\"{ini}\\"" '
        f'/sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5BT" 2>&1')
    return True


def wait_done(max_wait=780):
    start = time.time()
    time.sleep(25)
    while time.time() - start < max_wait:
        if not mt5_running():
            time.sleep(8)
            return True
        time.sleep(8)
    kill_mt5()
    return False


def parse_log(log):
    if not log or "NO_LOG_FILE" in log:
        return {"error": "No log"}
    m = re.search(r'final balance\s+([\d.]+)\s+USD', log, re.IGNORECASE)
    if m:
        bal = float(m.group(1))
        p   = bal - DEPOSIT
        def gi(pat):
            mm = re.search(pat, log)
            return int(mm.group(1)) if mm else 0
        return {"balance": bal, "profit": p, "profit_pct": p / DEPOSIT * 100,
                "deals": gi(r'DEALS=(\d+)'), "sl": gi(r'(?<!\w)SL=(\d+)')}
    if "thread finished" in log.lower():
        return {"balance": DEPOSIT, "profit": 0.0, "profit_pct": 0.0, "deals": 0, "sl": 0}
    return {"error": f"No result: {log[:160]}"}


def main():
    results = []

    for (tf, body, atr_m, sh, eh, lbl_short, yr_from, yr_to, yr) in TESTS:
        label = f"{lbl_short} {yr}"
        print(f"\n{'='*62}")
        print(f"  {label}")
        print(f"{'='*62}")

        kill_mt5()
        date_str = get_server_date()

        cfg = dict(BASE)
        cfg["InpMinBodyPct"]    = body
        cfg["InpMinCandleATR"]  = atr_m
        cfg["InpUseTimeFilter"] = "true"
        cfg["InpStartHour"]     = sh
        cfg["InpEndHour"]       = eh

        ok = write_ini_and_run("XAUUSDm", tf, yr_from, yr_to, cfg)
        if not ok:
            print("  ERROR: launch failed")
            results.append({"label": label, "error": "launch failed"})
            continue

        wait_done(max_wait=780)
        log_raw = read_agent_log(date_str)
        parsed  = parse_log(log_raw)

        if "error" in parsed:
            print(f"  ERROR: {parsed['error']}")
        else:
            wr = round((parsed['deals'] - parsed['sl']) / parsed['deals'] * 100) if parsed['deals'] else 0
            print(f"  P&L: ${parsed['profit']:+.2f} ({parsed['profit_pct']:+.2f}%)  "
                  f"Deals={parsed['deals']}  SL={parsed['sl']}  WR={wr}%")

        results.append({"label": label, **parsed})

    ts = datetime.now().strftime("%Y-%m-%d %H:%M")
    md = [f"# Candle Counter v1.1 — Filtered Results",
          f"*Generated: {ts}*",
          f"**XAUUSDm | Lot=0.01 | TimeFilter=10-19 (server)**\n",
          "| Config | Year | P&L% | Deals | SL | WR% |",
          "|---|---|---|---|---|---|"]
    for r in results:
        if "error" in r:
            md.append(f"| {r['label']} | — | — | — | — | {r['error']} |")
        else:
            wr  = round((r['deals'] - r['sl']) / r['deals'] * 100) if r['deals'] else 0
            yr  = r['label'].split()[-1]
            lbl = " ".join(r['label'].split()[:-1])
            md.append(f"| {lbl} | {yr} | {r['profit_pct']:+.2f}% | {r['deals']} | {r['sl']} | {wr}% |")

    with open(RESULT_MD, "w") as f:
        f.write("\n".join(md) + "\n")
    print(f"\nResults → {RESULT_MD}")

    # Summary
    print("\n── Combined (2y) ──")
    from collections import defaultdict
    by_cfg = defaultdict(dict)
    for r in results:
        yr  = r['label'].split()[-1]
        lbl = " ".join(r['label'].split()[:-1])
        by_cfg[lbl][yr] = r.get('profit_pct')

    for cfg_name, yrs in by_cfg.items():
        y24 = yrs.get('2024')
        y25 = yrs.get('2025')
        if y24 is not None and y25 is not None:
            both_ok = y24 > 0 and y25 > 0
            print(f"  {'✅' if both_ok else '⚠ '} {cfg_name}: 2024={y24:+.2f}%  2025={y25:+.2f}%")


if __name__ == "__main__":
    main()
