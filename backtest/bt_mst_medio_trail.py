#!/usr/bin/env python3
"""
MST Medio v4.10 — Pure Trail (No Partial TP)
Test best configs with partial TP disabled.
Sole exit = trailing SL + hard SL + safety TP at 10R.

Configs tested:
  A: M5  EURUSD MTF=5/5  No Partial TP
  B: H1  EURUSD MTF=3/5  No Partial TP
  C: M5  EURUSD MTF=5/5  With Partial TP  ← reference comparison
  D: H1  EURUSD MTF=3/5  With Partial TP  ← reference comparison
2024 + 2025 to confirm consistency.
"""

import subprocess, time, re, os
from datetime import datetime

SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")

MT5_DATA   = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
AGENT_LOGS = MT5_TESTER + r"\Agent-127.0.0.1-3000\logs"
EA_PATH    = r"MST Medio\Expert MST Medio"
DEPOSIT    = 500
LEVERAGE   = 100
RESULT_MD  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mst_medio_m5_multipair_results.md")

# ── BASE D_GongLoi settings ───────────────────────────────────────────────────
BASE = {
    "InpUseDynamicLot":        "false",
    "InpLotSize":              "0.01",
    "InpUseMoneyRisk":         "true",
    "InpRiskMoney":            "5.0",
    "InpMaxRiskPct":           "5.0",
    "InpMaxDailyLossPct":      "5.0",
    "InpMaxSLRiskPct":         "30.0",
    "InpPivotLen":             "5",
    "InpBreakMult":            "0.25",
    "InpImpulseMult":          "1.5",
    "InpTPFixedRR":            "10.0",
    "InpATRMultiplier":        "3.0",
    "InpSLBufferPct":          "10",
    "InpEntryOffsetPts":       "0",
    "InpMinSLDistPts":         "0",
    "InpUseATRSL":             "true",
    "InpATRPeriod":            "14",
    "InpTrailAfterPartialPts": "0",
    "InpUseTrendFilter":       "true",
    "InpEMAFastPeriod":        "20",
    "InpEMASlowPeriod":        "50",
    "InpUseHTFFilter":         "true",
    "InpMTFTrailOnConsensus":  "true",
    "InpMTFTrailStartR":       "0.5",
    "InpMTFTrailStepR":        "0.25",
    "InpSmartFlip":            "true",
    "InpRequireConfirmCandle": "false",
    "InpMagic":                "20241201",
    "InpMaxPositions":         "1",
    # No partial TP
    "InpUsePartialTP":         "false",
    "InpPartialTPAtR":         "2.0",
    "InpPartialLotPct":        "50",
}

# ── TEST MATRIX — M5 strict 5/5 on GBPUSD and XAUUSD ─────────────────────────
# (symbol, tf, from_date, to_date, mtf_min, use_partial, label)
TESTS = [
    ("GBPUSDm", "M5", "2025.01.01", "2026.02.01", "5", False, "M5 GBPUSD MTF=5/5 NoPart 2025"),
    ("GBPUSDm", "M5", "2024.01.01", "2025.01.01", "5", False, "M5 GBPUSD MTF=5/5 NoPart 2024"),
    ("XAUUSDm", "M5", "2025.01.01", "2026.02.01", "5", False, "M5 XAUUSD MTF=5/5 NoPart 2025"),
    ("XAUUSDm", "M5", "2024.01.01", "2025.01.01", "5", False, "M5 XAUUSD MTF=5/5 NoPart 2024"),
    # EURUSD reference
    ("EURUSDm", "M5", "2025.01.01", "2026.02.01", "5", False, "M5 EURUSD MTF=5/5 NoPart 2025"),
    ("EURUSDm", "M5", "2024.01.01", "2025.01.01", "5", False, "M5 EURUSD MTF=5/5 NoPart 2024"),
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


def scp_upload(local, remote):
    full = ["sshpass", "-p", SSH_PASS, "scp", "-o", "StrictHostKeyChecking=no",
            local, f"{SSH_USER}@{SSH_HOST}:{remote}"]
    r = subprocess.run(full, capture_output=True, text=True, timeout=30)
    return r.returncode == 0


def kill_mt5():
    ssh('taskkill /f /im terminal64.exe 2>nul')
    time.sleep(3)


def mt5_running():
    out = ssh('tasklist /fi "IMAGENAME eq terminal64.exe" /nh 2>nul')
    return "terminal64.exe" in out.lower()


def get_server_date():
    out = ssh('powershell -Command "Get-Date -Format yyyyMMdd"')
    for l in out.splitlines():
        l = l.strip()
        if len(l) == 8 and l.isdigit():
            return l
    return datetime.now().strftime("%Y%m%d")


def read_agent_log(date_str):
    log = f"{AGENT_LOGS}\\{date_str}.log"
    ps = (
        f"$log='{log}';"
        f"if(-not(Test-Path $log)){{Write-Host 'NO_LOG_FILE';exit}};"
        f"$d=(Select-String $log -Pattern 'deal performed').Count;"
        f"$s=(Select-String $log -Pattern 'stop loss triggered').Count;"
        f"$t=(Select-String $log -Pattern 'take profit triggered').Count;"
        f"$b=(Select-String $log -Pattern 'breakeven').Count;"
        f"$bal=(Select-String $log -Pattern 'final balance'|Select -Last 1);"
        f"Write-Host \"DEALS=$d\";"
        f"Write-Host \"SL=$s\";"
        f"Write-Host \"TP=$t\";"
        f"Write-Host \"BE=$b\";"
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
    # Launch
    ssh('schtasks /delete /tn "MT5BT" /f 2>nul')
    ssh(f'schtasks /create /tn "MT5BT" '
        f'/tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\" /config:\\"{ini}\\"" '
        f'/sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5BT" 2>&1')
    return True


def wait_done(max_wait=480):
    start = time.time()
    time.sleep(20)
    while time.time() - start < max_wait:
        if not mt5_running():
            time.sleep(6)
            return True
        time.sleep(6)
    kill_mt5()
    return False


def parse_log(log):
    if not log or "NO_LOG_FILE" in log:
        return {"error": "No log"}
    m = re.search(r'final balance\s+([\d.]+)\s+USD', log, re.IGNORECASE)
    if m:
        bal = float(m.group(1))
        p = bal - DEPOSIT

        def gi(pat):
            mm = re.search(pat, log)
            return int(mm.group(1)) if mm else 0

        return {"balance": bal, "profit": p, "profit_pct": p/DEPOSIT*100,
                "deals": gi(r'DEALS=(\d+)'), "sl": gi(r'(?<!\w)SL=(\d+)'),
                "tp": gi(r'TP=(\d+)'), "be": gi(r'BE=(\d+)')}
    if "thread finished" in log.lower():
        return {"balance": DEPOSIT, "profit": 0, "profit_pct": 0, "deals": 0, "sl": 0, "tp": 0, "be": 0}
    return {"error": f"No result: {log[:120]}"}


def run_one(symbol, tf, from_d, to_d, mtf_min, use_partial):
    if mt5_running():
        kill_mt5()
    cfg = {**BASE, "InpUseMTFConsensus": "true", "InpMTFMinAgree": mtf_min}
    time.sleep(1)
    if not write_ini_and_run(symbol, tf, from_d, to_d, cfg):
        return {"error": "INI failed"}
    time.sleep(10)
    for _ in range(8):
        if mt5_running():
            break
        time.sleep(4)
    if not wait_done(480):
        return {"error": "Timeout"}
    date_str = get_server_date()
    log = read_agent_log(date_str)
    r = parse_log(log)
    if "error" in r:
        time.sleep(8)
        r = parse_log(read_agent_log(date_str))
    return r


def fmt(r):
    if "error" in r:
        return f"❌ {r['error']}"
    icon = "🟢" if r['profit_pct'] > 0 else ("🔴" if r['profit_pct'] < 0 else "⚪")
    sign = "+" if r['profit_pct'] >= 0 else ""
    win = f"{r['tp']/r['deals']*100:.0f}%" if r['deals'] else "—"
    return f"{icon} ${r['balance']:,.2f} ({sign}{r['profit_pct']:.2f}%)  D:{r['deals']} SL:{r['sl']} BE:{r['be']} Win:{win}"


def main():
    print("=" * 70)
    print("  MST Medio v4.10 — M5 Strict MTF=5/5 Multi-Pair (GBPUSD + XAUUSD)")
    print(f"  {len(TESTS)} tests")
    print("=" * 70)
    print("\n🔌 SSH...", end=" ", flush=True)
    if "OK" not in ssh("echo OK"):
        print("❌"); return
    print("✅")
    print("  📤 Upload + Compile...", end=" ", flush=True)
    scp_upload(
        "/Users/tuan/GitProject/metatrader/MQL5/MST Medio/Expert MST Medio.mq5",
        "C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/"
        "53785E099C927DB68A545C249CDBCE06/MQL5/Experts/MST Medio/Expert MST Medio.mq5"
    )
    out = ssh("powershell -ExecutionPolicy Bypass -File C:\\Temp\\compile_mst.ps1", timeout=60)
    print("✅" if "0 errors" in out else "⚠️")
    print()

    results = []
    for i, (sym, tf, fd, td, mtf, part, label) in enumerate(TESTS, 1):
        print(f"{'─'*70}")
        mode = "Partial" if part else "NoPart"
        print(f"  [{i}/{len(TESTS)}] {label}  [{mode} TP | MTF={mtf}/5]")
        r = run_one(sym, tf, fd, td, mtf, part)
        results.append((label, sym, tf, fd[-4:], mtf, part, r))
        print(f"  → {fmt(r)}")

    # Report
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [
        "# MST Medio v4.10 — M5 Strict 5/5 Multi-Pair (GBPUSD + XAUUSD + EURUSD ref)\n",
        f"**Date:** {now}   **Risk:** $5/trade   **Deposit:** ${DEPOSIT}\n",
        "## Results\n",
        "| Label | Year | Mode | % | Deals | SL | BE |",
        "|-------|------|------|---|-------|----|-----|",
    ]
    for label, sym, tf, yr, mtf, part, r in results:
        mode = "Partial" if part else "**NoPart**"
        if "error" in r:
            lines.append(f"| {label} | {yr} | {mode} | ❌ | — | — | — |")
        else:
            pct = r['profit_pct']
            icon = "🟢" if pct > 0 else ("🔴" if pct < 0 else "⚪")
            sign = "+" if pct >= 0 else ""
            lines.append(f"| {label} | {yr} | {mode} | {icon} {sign}{pct:.2f}% | {r['deals']} | {r['sl']} | {r['be']} |")

    # Winner summary
    valid = [(lb, r) for lb, *_, r in results if "error" not in r]
    if valid:
        best = max(valid, key=lambda x: x[1]['profit_pct'])
        lines += ["\n## Best Config", f"**{best[0]}** → {best[1]['profit_pct']:+.2f}%"]

    report = "\n".join(lines) + "\n"
    with open(RESULT_MD, "w") as f:
        f.write(report)
    print(f"\n\n{'='*70}")
    print(f"📄 {RESULT_MD}")
    print(f"\n{report}")

    ssh('schtasks /delete /tn "MT5BT" /f 2>nul')
    ssh('schtasks /create /tn "MT5Start" /tr '
        '"\\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\\"" '
        '/sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5Start" 2>&1')
    ssh('schtasks /delete /tn "MT5Start" /f 2>nul')
    print("✅ Done!")


if __name__ == "__main__":
    main()
