#!/usr/bin/env python3
"""
M15 Impulse FAG Entry EA v2.0 — Backtest
Tests XAUUSD M5 and M15 for 2024 + 2025.
"""

import subprocess, time, re, os
from datetime import datetime

SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")

MT5_DATA   = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
AGENT_LOGS = MT5_TESTER + r"\Agent-127.0.0.1-3000\logs"
EA_PATH    = r"M15 Impulse FAG Entry\Expert M15 Impulse FAG Entry"
DEPOSIT    = 500
LEVERAGE   = 100
RESULT_MD  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bt_m15_fag_v2_results.md")

# ── BASE config (v2.0) ────────────────────────────────────────────────────────
BASE = {
    "InpUseMoneyRisk":      "true",
    "InpRiskMoney":         "10.0",
    "InpLotSize":           "0.01",
    "InpMaxDailyLossPct":   "0.0",       # disabled for backtest (no equity tracking in VPS BT)
    "InpATRLen":            "14",
    "InpATRMult":           "1.2",
    "InpBodyRatioMin":      "0.55",
    "InpDeviation":         "20",
    "InpMagic":             "20260224",
    "InpOnePosition":       "true",
    "InpExpiryMinutes":     "0",
    "InpMinZonePips":       "0.0",
    "InpSLBufferPips":      "0.0",
    "InpMaxZoneBars":       "0",
    "InpUseTimeFilter":     "true",
    "InpStartHour":         "2",
    "InpEndHour":           "21",
    "InpUseMTFConsensus":   "true",
    "InpMTFMinAgree":       "3",
    "InpEMAFastPeriod":     "20",
    "InpEMASlowPeriod":     "50",
    "InpMTFTrail":          "true",
    "InpMTFTrailStartR":    "0.5",
    "InpMTFTrailStepR":     "0.25",
}

# ── TEST MATRIX ───────────────────────────────────────────────────────────────
# (symbol, tf, from_date, to_date, label)
TESTS = [
    ("XAUUSDm", "M5",  "2025.01.01", "2026.02.01", "XAUUSD M5  v2.0 MinAg=3 2025"),
    ("XAUUSDm", "M5",  "2024.01.01", "2025.01.01", "XAUUSD M5  v2.0 MinAg=3 2024"),
    ("XAUUSDm", "M15", "2025.01.01", "2026.02.01", "XAUUSD M15 v2.0 MinAg=3 2025"),
    ("XAUUSDm", "M15", "2024.01.01", "2025.01.01", "XAUUSD M15 v2.0 MinAg=3 2024"),
]


# ── SSH HELPERS ───────────────────────────────────────────────────────────────
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
    out = ssh('tasklist /fi "IMAGENAME eq terminal64.exe" /nh 2>nul')
    return "terminal64.exe" in out.lower()


def get_server_date():
    out = ssh('powershell -Command "Get-Date -Format yyyyMMdd"')
    for ln in out.splitlines():
        ln = ln.strip()
        if len(ln) == 8 and ln.isdigit():
            return ln
    return datetime.now().strftime("%Y%m%d")


def read_agent_log(date_str):
    log = f"{AGENT_LOGS}\\{date_str}.log"
    ps = (
        f"$log='{log}';"
        f"if(-not(Test-Path $log)){{Write-Host 'NO_LOG_FILE';exit}};"
        f"$d=(Select-String $log -Pattern 'deal performed').Count;"
        f"$s=(Select-String $log -Pattern 'stop loss triggered').Count;"
        f"$t=(Select-String $log -Pattern 'take profit triggered').Count;"
        f"$bal=(Select-String $log -Pattern 'final balance'|Select -Last 1);"
        f"Write-Host \"DEALS=$d\";"
        f"Write-Host \"SL=$s\";"
        f"Write-Host \"TP=$t\";"
        f"if($bal){{Write-Host $bal.Line}}"
    )
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


def wait_done(max_wait=600):
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
                "deals": gi(r'DEALS=(\d+)'), "sl": gi(r'(?<!\w)SL=(\d+)'), "tp": gi(r'TP=(\d+)')}
    if "thread finished" in log.lower():
        return {"balance": DEPOSIT, "profit": 0.0, "profit_pct": 0.0, "deals": 0, "sl": 0, "tp": 0}
    return {"error": f"No result: {log[:160]}"}


# ── MAIN ──────────────────────────────────────────────────────────────────────
def main():
    results = []

    for (symbol, tf, from_d, to_d, label) in TESTS:
        print(f"\n{'='*60}")
        print(f"  {label}")
        print(f"{'='*60}")

        kill_mt5()
        date_str = get_server_date()

        cfg = dict(BASE)
        print(f"  Launching MT5 backtest ({symbol} {tf} {from_d}–{to_d}) ...")
        ok = write_ini_and_run(symbol, tf, from_d, to_d, cfg)
        if not ok:
            print("  ERROR: failed to write INI / launch MT5")
            results.append({"label": label, "error": "launch failed"})
            continue

        done = wait_done(max_wait=660)
        log_raw = read_agent_log(date_str)
        parsed = parse_log(log_raw)

        if "error" in parsed:
            print(f"  ERROR: {parsed['error']}")
        else:
            print(f"  Balance : ${parsed['balance']:.2f}")
            print(f"  P&L     : ${parsed['profit']:+.2f} ({parsed['profit_pct']:+.2f}%)")
            print(f"  Deals   : {parsed['deals']}  SL={parsed['sl']}  TP={parsed['tp']}")

        results.append({"label": label, **parsed})

    # ── Write markdown ─────────────────────────────────────────────────────────
    ts = datetime.now().strftime("%Y-%m-%d %H:%M")
    md = [f"# M15 Impulse FAG Entry v2.0 — Backtest Results", f"*Generated: {ts}*\n",
          f"**Deposit**: ${DEPOSIT}  |  **Leverage**: 1:{LEVERAGE}  |  **Risk**: $10/trade",
          f"**Config**: MTF MinAgree=3 (M1/M5/M15/H1/H4)  |  Trail StartR=0.5 StepR=0.25  |  No fixed TP\n",
          "| Label | Balance | P&L | P&L% | Deals | SL | TP |",
          "|---|---|---|---|---|---|---|"]
    for r in results:
        if "error" in r:
            md.append(f"| {r['label']} | — | — | — | ERROR: {r['error']} | — | — |")
        else:
            md.append(f"| {r['label']} | ${r['balance']:.2f} | ${r['profit']:+.2f} | {r['profit_pct']:+.2f}% | {r['deals']} | {r['sl']} | {r['tp']} |")

    with open(RESULT_MD, "w") as f:
        f.write("\n".join(md) + "\n")
    print(f"\nResults saved → {RESULT_MD}")


if __name__ == "__main__":
    main()
