#!/usr/bin/env python3
"""
MST Medio v4.10 — M5 + Multi-pair H1 Backtest
Tests:
  1. M5  EURUSD  D_GongLoi (ATR×3, TP 10R, MTF 3/5, trail)
  2. M5  EURUSD  StrictMTF  (ATR×3, TP 10R, MTF 5/5, trail)
  3. H1  GBPUSD  D_GongLoi
  4. H1  XAUUSD  D_GongLoi
  5. H1  USDJPY  D_GongLoi
  6. H1  EURUSD  D_GongLoi   ← reference (known: +5.46% in 2025)
Period: 2025.01.01 → 2026.02.01
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
FROM_DATE  = "2025.01.01"
TO_DATE    = "2026.02.01"

RESULT_MD  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mst_medio_m5_results.md")

# ── SHARED BASE ───────────────────────────────────────────────────────────────
GONGLOI_BASE = {
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
    "InpBEAtR":                "1.5",
    "InpSLBufferPct":          "10",
    "InpEntryOffsetPts":       "0",
    "InpMinSLDistPts":         "0",
    "InpUseATRSL":             "true",
    "InpATRPeriod":            "14",
    "InpUsePartialTP":         "true",
    "InpPartialTPAtR":         "2.0",
    "InpPartialLotPct":        "50",
    "InpTrailAfterPartialPts": "0",
    "InpUseTrendFilter":       "true",
    "InpEMAFastPeriod":        "20",
    "InpEMASlowPeriod":        "50",
    "InpUseHTFFilter":         "true",
    "InpUseMTFConsensus":      "true",
    "InpMTFMinAgree":          "3",
    "InpMTFTrailOnConsensus":  "true",
    "InpMTFTrailStartR":       "0.5",
    "InpMTFTrailStepR":        "0.25",
    "InpSmartFlip":            "true",
    "InpRequireConfirmCandle": "false",
    "InpMagic":                "20241201",
    "InpMaxPositions":         "1",
}

# ── TEST CASES ────────────────────────────────────────────────────────────────
# (symbol, tf, label, overrides)
TESTS = [
    # M5 — user's primary timeframe
    ("EURUSDm", "M5",  "M5  EURUSD D_GongLoi",  {}),
    ("EURUSDm", "M5",  "M5  EURUSD StrictMTF",   {"InpMTFMinAgree": "5"}),
    # H1 multi-pair (D_GongLoi settings)
    ("EURUSDm", "H1",  "H1  EURUSD D_GongLoi",  {}),
    ("GBPUSDm", "H1",  "H1  GBPUSD D_GongLoi",  {}),
    ("XAUUSDm", "H1",  "H1  XAUUSD D_GongLoi",  {"InpPivotLen": "5"}),
    ("USDJPYm", "H1",  "H1  USDJPY D_GongLoi",  {}),
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
    full = ["sshpass", "-p", SSH_PASS, "scp",
            "-o", "StrictHostKeyChecking=no",
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


def clear_agent_log(date_str):
    ssh(f'del "{AGENT_LOGS}\\{date_str}.log" 2>nul')


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


def write_ini(symbol, period, inputs):
    ini = f"{MT5_DATA}\\tester\\backtest_auto.ini"
    lines = [
        f'echo [Tester] > "{ini}"',
        f'echo Expert={EA_PATH} >> "{ini}"',
        f'echo Symbol={symbol} >> "{ini}"',
        f'echo Period={period} >> "{ini}"',
        f'echo Model=1 >> "{ini}"',
        f'echo Optimization=0 >> "{ini}"',
        f'echo FromDate={FROM_DATE} >> "{ini}"',
        f'echo ToDate={TO_DATE} >> "{ini}"',
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
    return "ERROR" not in (out or "").upper()


def launch_mt5():
    ini = f"{MT5_DATA}\\tester\\backtest_auto.ini"
    ssh('schtasks /delete /tn "MT5BT" /f 2>nul')
    ssh(f'schtasks /create /tn "MT5BT" '
        f'/tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\" /config:\\"{ini}\\"" '
        f'/sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5BT" 2>&1')


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
        return {"error": "No log file"}
    m = re.search(r'final balance\s+([\d.]+)\s+USD', log, re.IGNORECASE)
    if m:
        bal = float(m.group(1))
        profit = bal - DEPOSIT

        def gi(pat):
            mm = re.search(pat, log)
            return int(mm.group(1)) if mm else 0

        return {
            "balance":    bal,
            "profit":     profit,
            "profit_pct": profit / DEPOSIT * 100,
            "deals":      gi(r'DEALS=(\d+)'),
            "sl":         gi(r'(?<!\w)SL=(\d+)'),
            "tp":         gi(r'TP=(\d+)'),
            "be":         gi(r'BE=(\d+)'),
        }
    if "thread finished" in log.lower():
        return {"balance": DEPOSIT, "profit": 0, "profit_pct": 0, "deals": 0, "sl": 0, "tp": 0, "be": 0}
    return {"error": f"No result | {log[:200]}"}


def run_one(symbol, tf, inputs):
    if mt5_running():
        kill_mt5()
    date_str = get_server_date()
    clear_agent_log(date_str)
    time.sleep(1)
    if not write_ini(symbol, tf, inputs):
        return {"error": "INI write failed"}
    launch_mt5()
    time.sleep(10)
    # Wait for MT5 to start or immediately finish
    for _ in range(8):
        if mt5_running():
            break
        time.sleep(4)
    done = wait_done(max_wait=480)
    if not done:
        return {"error": "Timeout"}
    log = read_agent_log(date_str)
    r = parse_log(log)
    if "error" in r:
        time.sleep(8)
        r = parse_log(read_agent_log(date_str))
    return r


def fmt_result(r):
    if "error" in r:
        return f"❌ {r['error']}"
    sign = "+" if r['profit_pct'] >= 0 else ""
    icon = "🟢" if r['profit_pct'] > 0 else ("🔴" if r['profit_pct'] < 0 else "⚪")
    win = f"{r['tp']/r['deals']*100:.0f}%" if r['deals'] > 0 else "—"
    return (f"{icon} ${r['balance']:,.2f}  ({sign}{r['profit_pct']:.2f}%)  "
            f"D:{r['deals']} SL:{r['sl']} TP:{r['tp']} BE:{r['be']} Win:{win}")


# ── MAIN ──────────────────────────────────────────────────────────────────────
def main():
    print("=" * 70)
    print("  MST Medio v4.10 — M5 + Multi-pair H1 Backtest")
    print(f"  Period: {FROM_DATE} → {TO_DATE}")
    print(f"  {len(TESTS)} tests  |  $5 risk  |  D_GongLoi settings")
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
    print("✅" if "0 errors" in out else "⚠️  continuing")

    print()
    all_results = []

    for i, (symbol, tf, label, overrides) in enumerate(TESTS, 1):
        print(f"{'─'*70}")
        print(f"  [{i}/{len(TESTS)}] {label}")
        combined = {**GONGLOI_BASE, **overrides}
        r = run_one(symbol, tf, combined)
        all_results.append((label, symbol, tf, overrides, r))
        print(f"  → {fmt_result(r)}")

    # ── REPORT ──────────────────────────────────────────────────────────────
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [
        "# MST Medio v4.10 — M5 + Multi-pair H1 Backtest\n",
        f"**Date:** {now}  ",
        f"**Period:** {FROM_DATE} → {TO_DATE}  ",
        f"**Settings:** D_GongLoi (ATR×3, TP 10R, $5 risk, trail 0.5R/0.25R steps)  \n",
        "## Results\n",
        "| # | Symbol | TF | Label | Balance | P&L | % | Deals | SL | TP | BE | Win% |",
        "|---|--------|----|-------|---------|-----|---|-------|----|----|----|------|",
    ]
    for i, (label, symbol, tf, overrides, r) in enumerate(all_results, 1):
        note = f"MTF={overrides.get('InpMTFMinAgree','3')}/5" if overrides else "MTF=3/5"
        if "error" in r:
            lines.append(f"| {i} | {symbol} | {tf} | {note} | — | — | ❌ {r['error']} | — | — | — | — | — |")
        else:
            pct = r['profit_pct']
            icon = "🟢" if pct > 0 else ("🔴" if pct < 0 else "⚪")
            sign = "+" if pct >= 0 else ""
            win = f"{r['tp']/r['deals']*100:.0f}%" if r['deals'] > 0 else "—"
            lines.append(
                f"| {i} | {symbol} | {tf} | {note} "
                f"| ${r['balance']:,.2f} | ${r['profit']:+,.2f} "
                f"| {icon} {sign}{pct:.2f}% | {r['deals']} | {r['sl']} | {r['tp']} | {r['be']} | {win} |"
            )

    # Summary
    valid = [(lb, r) for lb, sym, tf, ov, r in all_results if "error" not in r]
    if valid:
        avg = sum(r['profit_pct'] for _, r in valid) / len(valid)
        best = max(valid, key=lambda x: x[1]['profit_pct'])
        worst = min(valid, key=lambda x: x[1]['profit_pct'])
        lines += [
            "\n## Summary\n",
            f"- **Average P&L:** {avg:+.2f}%",
            f"- **Best:** {best[0]} → {best[1]['profit_pct']:+.2f}%",
            f"- **Worst:** {worst[0]} → {worst[1]['profit_pct']:+.2f}%",
        ]

    report = "\n".join(lines) + "\n"
    with open(RESULT_MD, "w") as f:
        f.write(report)

    print(f"\n\n{'='*70}")
    print(f"📄 {RESULT_MD}")
    print(f"\n{report}")

    # Restart MT5
    ssh('schtasks /delete /tn "MT5BT" /f 2>nul')
    ssh('schtasks /create /tn "MT5Start" /tr '
        '"\\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\\"" '
        '/sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5Start" 2>&1')
    ssh('schtasks /delete /tn "MT5Start" /f 2>nul')
    print("✅ Done!")


if __name__ == "__main__":
    main()
