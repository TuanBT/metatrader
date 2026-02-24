#!/usr/bin/env python3
"""
Candle Counter v1.3 — H4 ADX Regime Filter Backtest
Tests ADX20/25/30 combined with EMA50 across 4 years.
Goal: find config where all 4 years are positive.
"""

import subprocess, time, re, os
from datetime import datetime
from collections import defaultdict

SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")

MT5_DATA   = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
AGENT_LOGS = MT5_TESTER + r"\Agent-127.0.0.1-3000\logs"
EA_PATH    = r"Candle Counter\Expert Candle Counter"
DEPOSIT    = 500
LEVERAGE   = 100
RESULT_MD  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bt_candle_counter_adx_results.md")


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


def wait_done(max_wait=660):
    start = time.time()
    time.sleep(35)   # H4 backtests run fast; wait a bit longer to avoid log caching
    while time.time() - start < max_wait:
        if not mt5_running():
            time.sleep(12)
            return True
        time.sleep(12)
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
                "deals": gi(r'DEALS=(\d+)'), "sl": gi(r'SL=(\d+)')}
    if "thread finished" in log.lower():
        return {"balance": DEPOSIT, "profit": 0.0, "profit_pct": 0.0, "deals": 0, "sl": 0}
    return {"error": f"No result: {log[:120]}"}


BASE = {
    "InpLotSize":       "0.01",
    "InpDeviation":     "20",
    "InpMagic":         "20260225",
    "InpOnePosition":   "true",
    "InpMinBodyPct":    "0.0",
    "InpMinCandleATR":  "0.0",
    "InpATRPeriod":     "14",
    "InpUseTimeFilter": "false",
    "InpStartHour":     "7",
    "InpEndHour":       "21",
    "InpEMATF":         "0",
    "InpADXPeriod":     "14",
}

# Configs: (label, use_ema, ema_p, use_adx, adx_min)
CONFIGS = [
    ("H4 ADX20 only",       "false", "50", "true",  "20.0"),
    ("H4 ADX25 only",       "false", "50", "true",  "25.0"),
    ("H4 ADX30 only",       "false", "50", "true",  "30.0"),
    ("H4 EMA50+ADX20",      "true",  "50", "true",  "20.0"),
    ("H4 EMA50+ADX25",      "true",  "50", "true",  "25.0"),
    ("H4 EMA50+ADX30",      "true",  "50", "true",  "30.0"),
]

YEARS = [
    ("2022.01.01", "2023.01.01", "2022"),
    ("2023.01.01", "2024.01.01", "2023"),
    ("2024.01.01", "2025.01.01", "2024"),
    ("2025.01.01", "2026.02.01", "2025"),
]

TESTS = []
for (cfg_name, use_ema, ema_p, use_adx, adx_min) in CONFIGS:
    for (yr_from, yr_to, yr) in YEARS:
        TESTS.append((cfg_name, use_ema, ema_p, use_adx, adx_min, yr_from, yr_to, yr))


def main():
    results = []

    for (cfg_name, use_ema, ema_p, use_adx, adx_min, yr_from, yr_to, yr) in TESTS:
        label = f"{cfg_name} {yr}"
        print(f"\n[{label}]")

        kill_mt5()
        date_str = get_server_date()

        cfg = dict(BASE)
        cfg["InpUseEMAFilter"]  = use_ema
        cfg["InpEMAPeriod"]     = ema_p
        cfg["InpUseADXFilter"]  = use_adx
        cfg["InpADXMinValue"]   = adx_min

        ok = write_ini_and_run("XAUUSDm", "H4", yr_from, yr_to, cfg)
        if not ok:
            print("  ERROR: launch failed")
            results.append({"label": label, "cfg": cfg_name, "yr": yr, "error": "launch"})
            continue

        wait_done(max_wait=660)
        log_raw = read_agent_log(date_str)
        parsed  = parse_log(log_raw)

        if "error" in parsed:
            print(f"  ERROR: {parsed['error']}")
        else:
            wr = round((parsed['deals'] - parsed['sl']) / parsed['deals'] * 100) if parsed['deals'] else 0
            print(f"  P&L: ${parsed['profit']:+.2f} ({parsed['profit_pct']:+.2f}%)  "
                  f"Deals={parsed['deals']}  SL={parsed['sl']}  WR={wr}%")

        results.append({"label": label, "cfg": cfg_name, "yr": yr, **parsed})

    ts = datetime.now().strftime("%Y-%m-%d %H:%M")

    # Build markdown table
    by_cfg = defaultdict(dict)
    for r in results:
        if "error" not in r:
            by_cfg[r["cfg"]][r["yr"]] = r

    md = [f"# Candle Counter v1.3 — H4 ADX Filter Results",
          f"*Generated: {ts}*",
          f"**XAUUSDm H4 | Lot=0.01**\n",
          "| Config | 2022 | 2023 | 2024 | 2025 | All+ |",
          "|---|---|---|---|---|---|"]

    for (cfg_name, *_) in CONFIGS:
        yrs_data = by_cfg.get(cfg_name, {})
        cells = []
        all_pos = True
        for yr in ["2022", "2023", "2024", "2025"]:
            d = yrs_data.get(yr)
            if d and "error" not in d:
                pp = d["profit_pct"]
                dl = d["deals"]
                cells.append(f"**{pp:+.1f}%** ({dl}d)" if pp > 0 else f"{pp:+.1f}% ({dl}d)")
                if pp <= 0:
                    all_pos = False
            else:
                cells.append("—")
                all_pos = False
        md.append(f"| {cfg_name} | {' | '.join(cells)} | {'✅' if all_pos else '⚠'} |")

    with open(RESULT_MD, "w") as f:
        f.write("\n".join(md) + "\n")
    print(f"\nResults → {RESULT_MD}")

    # Console summary
    print("\n── Summary ──")
    for (cfg_name, *_) in CONFIGS:
        yrs_data = by_cfg.get(cfg_name, {})
        parts = []
        all_pos = True
        for yr in ["2022", "2023", "2024", "2025"]:
            d = yrs_data.get(yr)
            if d and "error" not in d:
                parts.append(f"{yr}={d['profit_pct']:+.1f}%({d['deals']}d)")
                if d["profit_pct"] <= 0:
                    all_pos = False
        tag = "✅" if all_pos and len(parts) == 4 else "⚠ "
        print(f"  {tag} {cfg_name}: {' | '.join(parts)}")


if __name__ == "__main__":
    main()
