#!/usr/bin/env python3
"""
Candle Counter EA v1.0 — Multi-TF Backtest
Tests XAUUSDm on M1, M5, M15, H1 for 2024 + 2025.
Inputs: Lot=0.01, MinBodyPct=0 (no filter), TimeFilter=off
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
RESULT_MD  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bt_candle_counter_results.md")

BASE = {
    "InpLotSize":       "0.01",
    "InpDeviation":     "20",
    "InpMagic":         "20260225",
    "InpOnePosition":   "true",
    "InpMinBodyPct":    "0.0",
    "InpUseTimeFilter": "false",
    "InpStartHour":     "7",
    "InpEndHour":       "21",
}

# (symbol, tf, from_date, to_date, label)
TESTS = [
    ("XAUUSDm", "M1",  "2025.01.01", "2026.02.01", "M1  2025"),
    ("XAUUSDm", "M1",  "2024.01.01", "2025.01.01", "M1  2024"),
    ("XAUUSDm", "M5",  "2025.01.01", "2026.02.01", "M5  2025"),
    ("XAUUSDm", "M5",  "2024.01.01", "2025.01.01", "M5  2024"),
    ("XAUUSDm", "M15", "2025.01.01", "2026.02.01", "M15 2025"),
    ("XAUUSDm", "M15", "2024.01.01", "2025.01.01", "M15 2024"),
    ("XAUUSDm", "H1",  "2025.01.01", "2026.02.01", "H1  2025"),
    ("XAUUSDm", "H1",  "2024.01.01", "2025.01.01", "H1  2024"),
]


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
          f"$t=(Select-String $log -Pattern 'take profit triggered').Count;"
          f"$bal=(Select-String $log -Pattern 'final balance'|Select -Last 1);"
          f"Write-Host \"DEALS=$d\"; Write-Host \"SL=$s\"; Write-Host \"TP=$t\";"
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


def wait_done(max_wait=900):
    """M1 backtest over 1 year can take 10-15 min, use larger max_wait."""
    start = time.time()
    time.sleep(30)
    while time.time() - start < max_wait:
        if not mt5_running():
            time.sleep(10)
            return True
        time.sleep(10)
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
                "deals": gi(r'DEALS=(\d+)'), "sl": gi(r'(?<!\w)SL=(\d+)'), "tp": gi(r'TP=(\d+)')}
    if "thread finished" in log.lower():
        return {"balance": DEPOSIT, "profit": 0.0, "profit_pct": 0.0, "deals": 0, "sl": 0, "tp": 0}
    return {"error": f"No result: {log[:160]}"}


def main():
    results = []

    for (symbol, tf, from_d, to_d, label) in TESTS:
        print(f"\n{'='*56}")
        print(f"  Candle Counter | {label} | {symbol}")
        print(f"{'='*56}")

        kill_mt5()
        date_str = get_server_date()

        ok = write_ini_and_run(symbol, tf, from_d, to_d, BASE)
        if not ok:
            print("  ERROR: launch failed")
            results.append({"label": label, "tf": tf, "error": "launch failed"})
            continue

        wait_done(max_wait=900)
        log_raw = read_agent_log(date_str)
        parsed  = parse_log(log_raw)

        if "error" in parsed:
            print(f"  ERROR: {parsed['error']}")
        else:
            wr = round((parsed['deals'] - parsed['sl']) / parsed['deals'] * 100) if parsed['deals'] else 0
            print(f"  P&L : ${parsed['profit']:+.2f} ({parsed['profit_pct']:+.2f}%)")
            print(f"  Stats: Deals={parsed['deals']}  SL={parsed['sl']}  WR={wr}%")

        results.append({"label": label, "tf": tf, **parsed})

    # ── Markdown ──────────────────────────────────────────────────
    ts  = datetime.now().strftime("%Y-%m-%d %H:%M")
    md  = [f"# Candle Counter v1.0 — Multi-TF Results",
           f"*Generated: {ts}*",
           f"**XAUUSDm | Lot=0.01 | No body filter | No time filter**\n",
           "| TF | Year | P&L% | Deals | SL | WR% |",
           "|---|---|---|---|---|---|"]

    for r in results:
        if "error" in r:
            md.append(f"| {r['tf']} | {r['label'].split()[-1]} | — | — | — | {r['error']} |")
        else:
            wr  = round((r['deals'] - r['sl']) / r['deals'] * 100) if r['deals'] else 0
            yr  = r['label'].split()[-1]
            md.append(f"| {r['tf']} | {yr} | {r['profit_pct']:+.2f}% | {r['deals']} | {r['sl']} | {wr}% |")

    with open(RESULT_MD, "w") as f:
        f.write("\n".join(md) + "\n")
    print(f"\nResults → {RESULT_MD}")

    # Print summary
    print("\n── Summary ──")
    for r in results:
        if "error" not in r:
            wr  = round((r['deals'] - r['sl']) / r['deals'] * 100) if r['deals'] else 0
            tag = "✅" if r['profit_pct'] > 0 else "❌"
            print(f"  {tag} {r['label']}: {r['profit_pct']:+.2f}% ({r['deals']} deals, WR {wr}%)")


if __name__ == "__main__":
    main()
