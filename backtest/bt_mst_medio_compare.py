#!/usr/bin/env python3
"""
MST Medio v4.10 — Comparison Backtest
Tests 3 scenarios vs baseline to diagnose:
  A) Baseline  : ATR 2x, TP 3R, MTF 3/5
  B) Wide SL   : ATR 3x, TP 3R, MTF 3/5  ← give trade room to breathe
  C) No MTF    : ATR 2x, TP 3R, no MTF   ← isolate MTF impact
  D) Gong loi  : ATR 3x, TP 10R, MTF 3/5, trail active ← ride profits intent
"""

import subprocess, time, re, os
from datetime import datetime

# ── CONNECTION ────────────────────────────────────────────────────────────────
SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")

MT5_DATA   = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
AGENT_LOGS = MT5_TESTER + r"\Agent-127.0.0.1-3000\logs"

EA_PATH  = r"MST Medio\Expert MST Medio"
DEPOSIT  = 500
LEVERAGE = 100

RESULT_MD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mst_medio_compare_results.md")

# ── BASE CONFIG (shared across all scenarios) ─────────────────────────────────
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
    "InpBEAtR":                "1.0",
    "InpSLBufferPct":          "10",
    "InpEntryOffsetPts":       "0",
    "InpMinSLDistPts":         "0",
    "InpUseATRSL":             "true",
    "InpATRPeriod":            "14",
    "InpUsePartialTP":         "true",
    "InpPartialTPAtR":         "1.5",
    "InpPartialLotPct":        "50",
    "InpTrailAfterPartialPts": "0",
    "InpUseTrendFilter":       "true",
    "InpEMAFastPeriod":        "20",
    "InpEMASlowPeriod":        "50",
    "InpUseHTFFilter":         "true",
    "InpSmartFlip":            "true",
    "InpRequireConfirmCandle": "false",
    "InpMagic":                "20241201",
    "InpMaxPositions":         "1",
}

# ── SCENARIOS ─────────────────────────────────────────────────────────────────
SCENARIOS = {
    "A_Baseline": {
        **BASE,
        "InpTPFixedRR":          "3.0",
        "InpATRMultiplier":      "2.0",
        "InpUseMTFConsensus":    "true",
        "InpMTFMinAgree":        "3",
        "InpMTFTrailOnConsensus":"true",
        "InpMTFTrailStartR":     "1.0",
        "InpMTFTrailStepR":      "0.5",
    },
    "B_WideSL": {
        **BASE,
        "InpTPFixedRR":          "3.0",
        "InpATRMultiplier":      "3.0",   # ← wider SL
        "InpUseMTFConsensus":    "true",
        "InpMTFMinAgree":        "3",
        "InpMTFTrailOnConsensus":"true",
        "InpMTFTrailStartR":     "1.0",
        "InpMTFTrailStepR":      "0.5",
    },
    "C_NoMTF": {
        **BASE,
        "InpTPFixedRR":          "3.0",
        "InpATRMultiplier":      "2.0",
        "InpUseMTFConsensus":    "false",  # ← no MTF filter
        "InpMTFMinAgree":        "3",
        "InpMTFTrailOnConsensus":"false",
        "InpMTFTrailStartR":     "1.0",
        "InpMTFTrailStepR":      "0.5",
    },
    "D_GongLoi": {
        **BASE,
        "InpTPFixedRR":          "10.0",   # ← very high TP (trail is the exit)
        "InpATRMultiplier":      "3.0",    # ← wider SL
        "InpBEAtR":              "1.5",    # ← BE at 1.5R (give more room)
        "InpPartialTPAtR":       "2.0",    # ← partial at 2R
        "InpUseMTFConsensus":    "true",
        "InpMTFMinAgree":        "3",
        "InpMTFTrailOnConsensus":"true",
        "InpMTFTrailStartR":     "0.5",    # ← start trailing earlier (0.5R)
        "InpMTFTrailStepR":      "0.25",   # ← smaller steps = tighter trail
    },
}

# ── TEST PAIRS (symbol, tf, from, to, label_short) ───────────────────────────
# Using 2 most critical periods (worst performers from initial test)
PERIODS = [
    ("EURUSDm", "H1",  "2025.01.01", "2026.02.01", "H1-2025"),
    ("EURUSDm", "M15", "2025.01.01", "2026.02.01", "M15-2025"),
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


# ── MT5 HELPERS ───────────────────────────────────────────────────────────────
def kill_mt5():
    ssh('taskkill /f /im terminal64.exe 2>nul')
    time.sleep(3)


def mt5_running():
    out = ssh('tasklist /fi "IMAGENAME eq terminal64.exe" /nh 2>nul')
    return "terminal64.exe" in out.lower()


def get_server_date():
    out = ssh('powershell -Command "Get-Date -Format yyyyMMdd"')
    lines = [l.strip() for l in out.splitlines() if l.strip()]
    for l in lines:
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
        f"$b=(Select-String $log -Pattern 'SL moved to breakeven|breakeven').Count;"
        f"$bal=(Select-String $log -Pattern 'final balance'|Select -Last 1);"
        f"Write-Host \"DEALS=$d\";"
        f"Write-Host \"SL=$s\";"
        f"Write-Host \"TP=$t\";"
        f"Write-Host \"BE=$b\";"
        f"if($bal){{Write-Host $bal.Line}}"
    )
    return ssh(f'powershell -Command "{ps}"', timeout=60)


def write_ini(symbol, period, from_date, to_date, inputs):
    ini = f"{MT5_DATA}\\tester\\backtest_auto.ini"
    lines = [
        f'echo [Tester] > "{ini}"',
        f'echo Expert={EA_PATH} >> "{ini}"',
        f'echo Symbol={symbol} >> "{ini}"',
        f'echo Period={period} >> "{ini}"',
        f'echo Model=1 >> "{ini}"',
        f'echo Optimization=0 >> "{ini}"',
        f'echo FromDate={from_date} >> "{ini}"',
        f'echo ToDate={to_date} >> "{ini}"',
        f'echo ReplaceReport=1 >> "{ini}"',
        f'echo ShutdownTerminal=1 >> "{ini}"',
        f'echo Deposit={DEPOSIT} >> "{ini}"',
        f'echo Currency=USD >> "{ini}"',
        f'echo Leverage={LEVERAGE} >> "{ini}"',
        f'echo [TesterInputs] >> "{ini}"',
    ]
    for k, v in inputs.items():
        lines.append(f'echo {k}={v} >> "{ini}"')
    cmd = " && ".join(lines)
    out = ssh(cmd, timeout=60)
    return "ERROR" not in (out or "").upper()


def launch_mt5():
    ini = f"{MT5_DATA}\\tester\\backtest_auto.ini"
    ssh('schtasks /delete /tn "MT5BT" /f 2>nul')
    ssh(f'schtasks /create /tn "MT5BT" '
        f'/tr "\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\" /config:\\"{ini}\\"" '
        f'/sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5BT" 2>&1')


def wait_done(max_wait=360):
    start = time.time()
    time.sleep(18)
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
    return {"error": f"No result | log head: {log[:200]}"}


def run_one(symbol, tf, from_d, to_d, label, inputs):
    """Run a single backtest. Returns parsed result dict."""
    if mt5_running():
        kill_mt5()

    date_str = get_server_date()
    clear_agent_log(date_str)
    time.sleep(1)

    if not write_ini(symbol, tf, from_d, to_d, inputs):
        return {"error": "INI write failed"}

    launch_mt5()
    time.sleep(8)

    # Wait for MT5 to start
    started = any(mt5_running() or not time.sleep(4) for _ in range(6))
    done = wait_done(max_wait=420)

    if not done:
        return {"error": "Timeout"}

    log = read_agent_log(date_str)
    r = parse_log(log)
    if "error" in r:
        time.sleep(8)
        log = read_agent_log(date_str)
        r = parse_log(log)
    return r


def fmt_result(r, label=""):
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
    print("  MST Medio v4.10 — Scenario Comparison")
    print(f"  {len(SCENARIOS)} scenarios × {len(PERIODS)} periods = {len(SCENARIOS)*len(PERIODS)} tests")
    print("=" * 70)

    # Test connection
    print("\n🔌 SSH...", end=" ", flush=True)
    if "OK" not in ssh("echo OK"):
        print("❌ Cannot connect"); return
    print("✅")

    # EA already compiled — just upload latest
    print("  📤 Uploading EA...", end=" ", flush=True)
    ok = scp_upload(
        "/Users/tuan/GitProject/metatrader/MQL5/MST Medio/Expert MST Medio.mq5",
        "C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/"
        "53785E099C927DB68A545C249CDBCE06/MQL5/Experts/MST Medio/Expert MST Medio.mq5"
    )
    if not ok:
        print("❌ Upload failed, using existing .ex5"); 
    else:
        # Recompile
        out = ssh("powershell -ExecutionPolicy Bypass -File C:\\Temp\\compile_mst.ps1", timeout=60)
        if "0 errors" in out:
            print("✅ (compiled)")
        else:
            print("⚠️  compile uncertain, proceeding")

    print()
    total_tests = len(SCENARIOS) * len(PERIODS)
    test_num = 0

    # results[scenario][period_label] = dict
    results = {s: {} for s in SCENARIOS}

    for scen_name, inputs in SCENARIOS.items():
        print(f"\n{'═'*70}")
        print(f"  SCENARIO {scen_name}")
        atr = inputs.get('InpATRMultiplier', '?')
        tp  = inputs.get('InpTPFixedRR', '?')
        mtf = inputs.get('InpUseMTFConsensus', '?')
        print(f"  ATR×{atr}  |  TP {tp}R  |  MTF={mtf}")
        print(f"{'═'*70}")

        for symbol, tf, from_d, to_d, plabel in PERIODS:
            test_num += 1
            full_label = f"{scen_name} / {plabel}"
            print(f"\n  [{test_num}/{total_tests}] {full_label}")

            r = run_one(symbol, tf, from_d, to_d, full_label, inputs)
            results[scen_name][plabel] = r
            print(f"  → {fmt_result(r)}")

    # ── REPORT ──
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [
        "# MST Medio v4.10 — Scenario Comparison\n",
        f"**Date:** {now}  ",
        f"**Deposit:** ${DEPOSIT}  |  **Leverage:** 1:{LEVERAGE}  |  **Risk:** $5/trade  \n",
        "## Scenarios\n",
        "| ID | ATR× | TP | MTF Consensus | Intent |",
        "|----|------|----|---------------|--------|",
        "| A_Baseline | 2.0 | 3R | ≥3/5 | Baseline |",
        "| B_WideSL   | 3.0 | 3R | ≥3/5 | Wider SL = more room |",
        "| C_NoMTF    | 2.0 | 3R | Off  | Isolate MTF effect |",
        "| D_GongLoi  | 3.0 | 10R| ≥3/5 | Ride profits via trail |",
        "\n## Results by Period\n",
    ]

    period_labels = [pl for _, _, _, _, pl in PERIODS]

    # Per scenario table
    for scen_name in SCENARIOS:
        atr = SCENARIOS[scen_name].get('InpATRMultiplier', '?')
        tp  = SCENARIOS[scen_name].get('InpTPFixedRR', '?')
        mtf = SCENARIOS[scen_name].get('InpUseMTFConsensus', '?')
        lines.append(f"\n### {scen_name} (ATR×{atr} | TP {tp}R | MTF {mtf})\n")
        lines.append("| Period | Balance | P&L | % | Deals | SL | TP | BE | Win% |")
        lines.append("|--------|---------|-----|---|-------|----|----|----|------|")
        for pl in period_labels:
            r = results[scen_name].get(pl, {"error": "not run"})
            if "error" in r:
                lines.append(f"| {pl} | — | — | ❌ {r['error']} | — | — | — | — | — |")
            else:
                pct = r['profit_pct']
                icon = "🟢" if pct > 0 else ("🔴" if pct < 0 else "⚪")
                sign = "+" if pct >= 0 else ""
                win = f"{r['tp']/r['deals']*100:.0f}%" if r['deals'] > 0 else "—"
                lines.append(
                    f"| {pl} | ${r['balance']:,.2f} | ${r['profit']:+,.2f} "
                    f"| {icon} {sign}{pct:.2f}% | {r['deals']} | {r['sl']} | {r['tp']} | {r['be']} | {win} |"
                )

    # Summary table side-by-side comparison
    lines += ["\n## Summary Comparison (Avg across all periods)\n",
              "| Scenario | Avg P&L% | Total P&L | Avg Win% | Notes |",
              "|----------|----------|-----------|----------|-------|"]

    for scen_name in SCENARIOS:
        valid = [(pl, r) for pl, r in results[scen_name].items() if "error" not in r]
        if valid:
            avg_pct = sum(r['profit_pct'] for _, r in valid) / len(valid)
            total_pnl = sum(r['profit'] for _, r in valid)
            total_tp = sum(r['tp'] for _, r in valid)
            total_deals = sum(r['deals'] for _, r in valid)
            avg_win = f"{total_tp/total_deals*100:.0f}%" if total_deals > 0 else "—"
            icon = "🟢" if avg_pct > 0 else ("🔴" if avg_pct < 0 else "⚪")
            sign = "+" if avg_pct >= 0 else ""
            lines.append(f"| {scen_name} | {icon} {sign}{avg_pct:.2f}% | ${total_pnl:+,.2f} | {avg_win} | |")
        else:
            lines.append(f"| {scen_name} | ❌ | ❌ | ❌ | All failed |")

    report = "\n".join(lines) + "\n"
    with open(RESULT_MD, "w") as f:
        f.write(report)

    print(f"\n\n{'='*70}")
    print(f"📄 Report: {RESULT_MD}")
    print(f"\n{report}")

    # Restart MT5
    print("\n🔄 Restarting MT5...")
    ssh('schtasks /delete /tn "MT5BT" /f 2>nul')
    ssh('schtasks /create /tn "MT5Start" /tr '
        '"\\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\\"" '
        '/sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5Start" 2>&1')
    ssh('schtasks /delete /tn "MT5Start" /f 2>nul')
    print("✅ Done!")


if __name__ == "__main__":
    main()
