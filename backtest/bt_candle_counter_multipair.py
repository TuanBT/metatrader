#!/usr/bin/env python3
"""
Candle Counter v1.3 - H4 EMA50+ADX25 Comprehensive Multi-Pair
8 pairs x 6 years (2020-2025) = 48 tests.
"""
import subprocess, time, re, os
from datetime import datetime
from collections import defaultdict

SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")
MT5_DATA   = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
AGENT_BASE  = MT5_TESTER  # logs live under Agent-127.0.0.1-30xx\logs\yyyymmdd.log
EA_PATH    = r"Candle Counter\Expert Candle Counter"
DEPOSIT    = 500
LEVERAGE   = 100
RESULT_MD  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bt_candle_counter_multipair_results.md")


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
    ssh("taskkill /f /im terminal64.exe 2>nul")
    time.sleep(3)


def mt5_running():
    return "terminal64.exe" in ssh("tasklist /fi \"IMAGENAME eq terminal64.exe\" /nh 2>nul").lower()


def get_server_date():
    out = ssh("powershell -Command \"Get-Date -Format yyyyMMdd\"")
    for ln in out.splitlines():
        ln = ln.strip()
        if len(ln) == 8 and ln.isdigit():
            return ln
    return datetime.now().strftime("%Y%m%d")


def find_agent_log(date_str):
    """Find the most recently written agent log for today across all agents."""
    ps = (f"$f=Get-ChildItem '{MT5_TESTER}\\Agent-127.0.0.1-*\\logs\\{date_str}.log' "
          f"-ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select -First 1;"
          f"if($f){{Write-Host $f.FullName}}else{{Write-Host 'NOT_FOUND'}}")
    out = ssh(f'powershell -Command "{ps}"', timeout=30)
    for ln in out.splitlines():
        ln = ln.strip()
        if ln and ".log" in ln and "NOT_FOUND" not in ln:
            return ln
    return None


def del_agent_logs(date_str):
    """Delete today's log from ALL agent directories."""
    ps = (f"Get-ChildItem '{MT5_TESTER}\\Agent-127.0.0.1-*\\logs\\{date_str}.log' "
          f"-ErrorAction SilentlyContinue | Remove-Item -Force")
    ssh(f'powershell -Command "{ps}"', timeout=30)


def read_agent_log(date_str):
    log = find_agent_log(date_str)
    if not log:
        return "NO_LOG_FILE"
    ps = (f"$log='{log}';"
          f"$d=(Select-String $log -Pattern 'deal performed').Count;"
          f"$s=(Select-String $log -Pattern 'stop loss triggered').Count;"
          f"$bal=(Select-String $log -Pattern 'final balance'|Select -Last 1);"
          f"Write-Host \"DEALS=$d\"; Write-Host \"SL=$s\";"
          f"if($bal){{Write-Host $bal.Line}}")
    return ssh(f'powershell -Command "{ps}"', timeout=60)


def write_ini_and_run(symbol, period, from_d, to_d, inputs):
    ini = f"{MT5_DATA}\\tester\\backtest_auto.ini"
    lines = [
        f"echo [Tester] > \"{ini}\"",
        f"echo Expert={EA_PATH} >> \"{ini}\"",
        f"echo Symbol={symbol} >> \"{ini}\"",
        f"echo Period={period} >> \"{ini}\"",
        f"echo Model=1 >> \"{ini}\"",
        f"echo Optimization=0 >> \"{ini}\"",
        f"echo FromDate={from_d} >> \"{ini}\"",
        f"echo ToDate={to_d} >> \"{ini}\"",
        f"echo ReplaceReport=1 >> \"{ini}\"",
        f"echo ShutdownTerminal=1 >> \"{ini}\"",
        f"echo Deposit={DEPOSIT} >> \"{ini}\"",
        f"echo Currency=USD >> \"{ini}\"",
        f"echo Leverage={LEVERAGE} >> \"{ini}\"",
        f"echo [TesterInputs] >> \"{ini}\"",
    ]
    for k, v in inputs.items():
        lines.append(f"echo {k}={v} >> \"{ini}\"")
    ssh(" && ".join(lines), timeout=60)
    date_str = get_server_date()
    del_agent_logs(date_str)
    ssh("schtasks /delete /tn \"MT5BT\" /f 2>nul")
    ssh(f'schtasks /create /tn "MT5BT" '
        f'/tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\" /config:\\"{ini}\\"" '
        f'/sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5BT" 2>&1')
    return date_str


def wait_done(max_wait=660):
    start = time.time()
    time.sleep(35)
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
    m = re.search(r"final balance\s+([\d.]+)\s+USD", log, re.IGNORECASE)
    if m:
        bal = float(m.group(1))
        p   = bal - DEPOSIT
        def gi(pat):
            mm = re.search(pat, log)
            return int(mm.group(1)) if mm else 0
        return {"balance": bal, "profit": p, "profit_pct": p / DEPOSIT * 100,
                "deals": gi(r"DEALS=(\d+)"), "sl": gi(r"SL=(\d+)")}
    if "thread finished" in log.lower():
        return {"balance": DEPOSIT, "profit": 0.0, "profit_pct": 0.0, "deals": 0, "sl": 0}
    return {"error": f"No result: {log[:120]}"}


CFG = {
    "InpLotSize": "0.01", "InpDeviation": "20", "InpMagic": "20260225",
    "InpOnePosition": "true", "InpMinBodyPct": "0.0", "InpMinCandleATR": "0.0",
    "InpATRPeriod": "14", "InpUseTimeFilter": "false", "InpStartHour": "7",
    "InpEndHour": "21", "InpEMATF": "0", "InpADXPeriod": "14",
    "InpUseEMAFilter": "true", "InpEMAPeriod": "50",
    "InpUseADXFilter": "true", "InpADXMinValue": "25.0",
}

PAIRS = ["XAUUSDm", "USDJPYm", "EURUSDm", "GBPUSDm", "USDCHFm", "USDCADm", "AUDUSDm", "NZDUSDm"]
YR_COLS = ["2020", "2021", "2022", "2023", "2024", "2025"]
YEARS = [
    ("2020.01.01", "2021.01.01", "2020"),
    ("2021.01.01", "2022.01.01", "2021"),
    ("2022.01.01", "2023.01.01", "2022"),
    ("2023.01.01", "2024.01.01", "2023"),
    ("2024.01.01", "2025.01.01", "2024"),
    ("2025.01.01", "2026.02.01", "2025"),
]
TESTS = [(p, f, t, y) for p in PAIRS for (f, t, y) in YEARS]


def save_md(results, final=False):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M")
    by_pair = defaultdict(dict)
    for r in results:
        if "error" not in r:
            by_pair[r["pair"]][r["yr"]] = r
    md = [f"# CC v1.3 - H4 EMA50+ADX25 Multi-Pair [{ts}]",
          "**H4 | EMA50 + ADX(14)>25 | Lot=0.01**\n",
          "| Pair | " + " | ".join(YR_COLS) + " | +/n |",
          "|---|" + "---|" * (len(YR_COLS) + 1)]
    for pair in PAIRS:
        yd = by_pair.get(pair, {})
        cells = []
        pos = 0
        for yr in YR_COLS:
            d = yd.get(yr)
            if d and "error" not in d:
                pp = d["profit_pct"]
                cells.append(f"**{pp:+.1f}%**" if pp > 0 else f"{pp:+.1f}%")
                if pp > 0: pos += 1
            else:
                cells.append("—")
        n = sum(1 for d in yd.values() if "error" not in d)
        sep = " | "
        md.append(f"| {pair} | {sep.join(cells)} | {pos}/{n} |")
    with open(RESULT_MD, "w") as f:
        f.write("\n".join(md) + "\n")
    if final:
        print(f"\nResults -> {RESULT_MD}")


def main():
    results = []
    for idx, (pair, yr_from, yr_to, yr) in enumerate(TESTS, 1):
        label = f"{pair} {yr}"
        print(f"\n[{idx}/{len(TESTS)}] {label}")
        kill_mt5()
        date_str = write_ini_and_run(pair, "H4", yr_from, yr_to, CFG)
        if not date_str:
            results.append({"label": label, "pair": pair, "yr": yr, "error": "launch"})
            continue
        wait_done(660)
        log_raw = read_agent_log(date_str)
        parsed  = parse_log(log_raw)
        if "error" in parsed:
            err_msg = parsed["error"]
            print(f"  ERROR: {err_msg}")
        else:
            wr = round((parsed["deals"]-parsed["sl"])/parsed["deals"]*100) if parsed["deals"] else 0
            pnl = parsed["profit"]; pct = parsed["profit_pct"]; nd = parsed["deals"]
            print(f"  P&L: ${pnl:+.2f} ({pct:+.2f}%)  Deals={nd}  WR={wr}%")
        results.append({"label": label, "pair": pair, "yr": yr, **parsed})
        save_md(results)
    save_md(results, final=True)
    print("\n-- Summary --")
    by_pair = defaultdict(dict)
    for r in results:
        if "error" not in r:
            by_pair[r["pair"]][r["yr"]] = r
    for pair in PAIRS:
        yd = by_pair.get(pair, {})
        pos = sum(1 for d in yd.values() if "error" not in d and d["profit_pct"] > 0)
        n = sum(1 for d in yd.values() if "error" not in d)
        tag = "OK" if pos == n and n > 0 else "NG"
        pts = " | ".join(f"{yr}={yd[yr]['profit_pct']:+.1f}%" for yr in YR_COLS if yr in yd and "error" not in yd[yr])
        print(f"  [{tag}] {pair} [{pos}/{n}+]: {pts}")


if __name__ == "__main__":
    main()
