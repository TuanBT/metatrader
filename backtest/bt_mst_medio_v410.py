#!/usr/bin/env python3
"""
MST Medio v4.10 Single-Pair Backtest
Settings: $5 risk, 3R TP, MTF Consensus filter
Pair:     EURUSDm H1
"""

import subprocess, time, re, os
from datetime import datetime

# ── CONNECTION ────────────────────────────────────────────────────────────────
SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")

MT5_DATA    = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER  = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
AGENT_LOGS  = MT5_TESTER + r"\Agent-127.0.0.1-3000\logs"

EA_PATH    = r"MST Medio\Expert MST Medio"
DEPOSIT    = 500
LEVERAGE   = 100

RESULT_MD  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mst_medio_v410_results.md")

# ── TEST MATRIX ───────────────────────────────────────────────────────────────
# (symbol, tf, from_date, to_date, label)
TESTS = [
    ("EURUSDm", "H1",  "2024.01.01", "2025.01.01", "EURUSD H1 2024"),
    ("EURUSDm", "H1",  "2025.01.01", "2026.02.01", "EURUSD H1 2025"),
    ("EURUSDm", "M15", "2024.01.01", "2025.01.01", "EURUSD M15 2024"),
    ("EURUSDm", "M15", "2025.01.01", "2026.02.01", "EURUSD M15 2025"),
]

# ── EA INPUTS (v4.10 specific) ─────────────────────────────────────────────────
EA_INPUTS = {
    # Position sizing — money-based $5 risk
    "InpUseDynamicLot":       "false",
    "InpLotSize":             "0.01",
    "InpUseMoneyRisk":        "true",
    "InpRiskMoney":           "5.0",
    "InpMaxRiskPct":          "5.0",
    "InpMaxDailyLossPct":     "5.0",
    "InpMaxSLRiskPct":        "30.0",
    # Signal detection
    "InpPivotLen":            "5",
    "InpBreakMult":           "0.25",
    "InpImpulseMult":         "1.5",
    # TP / SL — 3R target
    "InpTPFixedRR":           "3.0",
    "InpBEAtR":               "1.0",     # Move SL to BE at 1R profit
    "InpSLBufferPct":         "10",
    "InpEntryOffsetPts":      "0",
    "InpMinSLDistPts":        "0",
    "InpUseATRSL":            "true",
    "InpATRMultiplier":       "2.0",
    "InpATRPeriod":           "14",
    # Partial TP
    "InpUsePartialTP":        "true",
    "InpPartialTPAtR":        "1.5",
    "InpPartialLotPct":       "50",
    "InpTrailAfterPartialPts": "0",
    # Trend filter
    "InpUseTrendFilter":      "true",
    "InpEMAFastPeriod":       "20",
    "InpEMASlowPeriod":       "50",
    "InpUseHTFFilter":        "true",
    # MTF Consensus (new v4.10)
    "InpUseMTFConsensus":     "true",
    "InpMTFMinAgree":         "3",
    "InpMTFTrailOnConsensus": "true",
    "InpMTFTrailStartR":      "1.0",
    "InpMTFTrailStepR":       "0.5",
    # Misc
    "InpSmartFlip":           "true",
    "InpRequireConfirmCandle": "false",
    "InpMagic":               "20241201",
    "InpMaxPositions":        "1",
}


# ── SSH HELPERS ───────────────────────────────────────────────────────────────
def ssh(cmd, timeout=90):
    full = ["sshpass", "-p", SSH_PASS, "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=15",
            "-o", "ServerAliveInterval=20",
            f"{SSH_USER}@{SSH_HOST}", cmd]
    try:
        r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
        # Combine stdout + stderr so we don't miss compile output
        combined = (r.stdout + "\n" + r.stderr).strip()
        return combined
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
    return out.strip() if out and len(out) == 8 else datetime.now().strftime("%Y%m%d")


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
        f"$b=(Select-String $log -Pattern 'SL moved to breakeven').Count;"
        f"$bal=(Select-String $log -Pattern 'final balance'|Select -Last 1);"
        f"$fin=(Select-String $log -Pattern 'thread finished'|Select -Last 1);"
        f"Write-Host \"DEALS=$d\";"
        f"Write-Host \"SL=$s\";"
        f"Write-Host \"TP=$t\";"
        f"Write-Host \"BE=$b\";"
        f"if($bal){{Write-Host $bal.Line}};"
        f"if($fin){{Write-Host $fin.Line}}"
    )
    return ssh(f'powershell -Command "{ps}"', timeout=60)


def write_ini(symbol, period, from_date, to_date):
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
    for k, v in EA_INPUTS.items():
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
    finished = "thread finished" in log.lower()

    m = re.search(r'final balance\s+([\d.]+)\s+USD', log, re.IGNORECASE)
    if m:
        bal = float(m.group(1))
        profit = bal - DEPOSIT
        return {
            "balance": bal,
            "profit": profit,
            "profit_pct": profit / DEPOSIT * 100,
            "deals": int(re.search(r'DEALS=(\d+)', log).group(1)) if re.search(r'DEALS=(\d+)', log) else 0,
            "sl":    int(re.search(r'(?<!\w)SL=(\d+)', log).group(1)) if re.search(r'(?<!\w)SL=(\d+)', log) else 0,
            "tp":    int(re.search(r'TP=(\d+)', log).group(1)) if re.search(r'TP=(\d+)', log) else 0,
            "be":    int(re.search(r'BE=(\d+)', log).group(1)) if re.search(r'BE=(\d+)', log) else 0,
        }
    if finished:
        return {"balance": DEPOSIT, "profit": 0, "profit_pct": 0, "deals": 0, "sl": 0, "tp": 0, "be": 0}
    return {"error": "No results in log"}


# ── COMPILE ───────────────────────────────────────────────────────────────────
def compile_ea():
    print("  🔨 Compiling EA...", end=" ", flush=True)
    ok = scp_upload(
        "/Users/tuan/GitProject/metatrader/MQL5/MST Medio/Expert MST Medio.mq5",
        "C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/"
        "53785E099C927DB68A545C249CDBCE06/MQL5/Experts/MST Medio/Expert MST Medio.mq5"
    )
    if not ok:
        print("❌ Upload failed"); return False

    # Use the known-working compile script already on the VPS
    out = ssh("powershell -ExecutionPolicy Bypass -File C:\\Temp\\compile_mst.ps1", timeout=60)
    if "0 errors" in out:
        w = re.search(r'(\d+) warnings', out)
        print(f"✅  ({w.group(1)} warnings)" if w else "✅")
        return True
    # If compile_mst.ps1 not found, fallback: skip and assume already compiled
    if "Cannot find" in out or "not found" in out.lower():
        print("⚠️  (compile script missing, using existing .ex5)")
        return True
    print(f"❌\n{out}")
    return False


# ── MAIN ──────────────────────────────────────────────────────────────────────
def main():
    print("=" * 65)
    print("  MST Medio v4.10 — Single-Pair Backtest")
    print(f"  Risk: $5/trade  |  TP: 3R  |  MTF Consensus: 3/5 TFs")
    print(f"  Deposit: ${DEPOSIT}  |  Leverage: 1:{LEVERAGE}")
    print("=" * 65)

    # Test connection
    print("\n🔌 SSH...", end=" ", flush=True)
    if "OK" not in ssh("echo OK"):
        print("❌ Cannot connect"); return
    print("✅")

    # Compile
    if not compile_ea():
        return

    date_str = get_server_date()
    print(f"📅 Server date: {date_str}\n")

    all_results = []

    for i, (symbol, tf, from_d, to_d, label) in enumerate(TESTS, 1):
        print(f"{'─'*65}")
        print(f"  [{i}/{len(TESTS)}] {label}")
        print(f"{'─'*65}")

        if mt5_running():
            print("  🔄 Kill MT5...", end=" "); kill_mt5(); print("done")

        clear_agent_log(date_str)
        time.sleep(1)

        print("  📄 Write INI...", end=" ", flush=True)
        if not write_ini(symbol, tf, from_d, to_d):
            print("❌"); all_results.append((label, {"error": "INI failed"})); continue
        print("✅")

        print("  🚀 Launch...", end=" ", flush=True)
        launch_mt5()
        time.sleep(8)

        started = False
        for _ in range(6):
            if mt5_running(): started = True; break
            time.sleep(5)

        if not started:
            # May have already finished (fast test)
            log = read_agent_log(date_str)
            r = parse_log(log)
            if "error" not in r:
                print("✅ (instant)")
                all_results.append((label, r))
                _print_result(r)
                continue
            print("❌ Not started"); all_results.append((label, {"error": "MT5 not started"})); continue

        print("✅ Running")
        print("  ⏳ Waiting for completion...", end=" ", flush=True)
        done = wait_done(max_wait=420)

        if not done:
            print("⚠️ TIMEOUT"); all_results.append((label, {"error": "Timeout"})); continue

        log = read_agent_log(date_str)
        r = parse_log(log)
        if "error" in r:
            time.sleep(6)
            log = read_agent_log(date_str)
            r = parse_log(log)

        all_results.append((label, r))
        print("✅")
        _print_result(r)

    # ── REPORT ──
    print(f"\n{'='*65}")
    report = build_report(all_results)
    with open(RESULT_MD, "w") as f:
        f.write(report)
    print(f"📄 Report: {RESULT_MD}")
    print(f"\n{report}")

    print("🔄 Restarting MT5...")
    ssh('schtasks /delete /tn "MT5BT" /f 2>nul')
    ssh('schtasks /create /tn "MT5Start" /tr '
        '"\\\"C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe\\\"" '
        '/sc once /st 00:00 /f /rl highest /it 2>&1')
    ssh('schtasks /run /tn "MT5Start" 2>&1')
    ssh('schtasks /delete /tn "MT5Start" /f 2>nul')

    print("\n✅ Done!")


def _print_result(r):
    if "error" in r:
        print(f"  ❌ {r['error']}")
    else:
        sign = "+" if r['profit_pct'] >= 0 else ""
        icon = "🟢" if r['profit_pct'] > 0 else ("🔴" if r['profit_pct'] < 0 else "⚪")
        print(f"  {icon} Balance: ${r['balance']:,.2f}  ({sign}{r['profit_pct']:.2f}%")
        print(f"     Deals: {r['deals']}  |  SL: {r['sl']}  |  TP: {r['tp']}  |  BE: {r['be']}")
        if r['deals'] > 0:
            win_rate = r['tp'] / r['deals'] * 100
            print(f"     Win rate (TP): {win_rate:.0f}%")


def build_report(results):
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [
        "# MST Medio v4.10 — Backtest Results\n",
        f"**Date:** {now}  ",
        f"**Risk:** $5/trade  |  **TP:** 3R  |  **MTF Consensus:** ≥3/5 TFs  ",
        f"**Deposit:** ${DEPOSIT}  |  **Leverage:** 1:{LEVERAGE}  \n",
        "## Settings\n",
        "| Parameter | Value |",
        "|-----------|-------|",
    ]
    for k, v in EA_INPUTS.items():
        lines.append(f"| {k} | {v} |")

    lines += [
        "\n## Results\n",
        "| # | Test | Balance | P&L | % | Deals | SL | TP | BE | Win% |",
        "|---|------|---------|-----|---|-------|----|----|----|------|",
    ]
    for i, (label, r) in enumerate(results, 1):
        if "error" in r:
            lines.append(f"| {i} | {label} | — | — | ❌ {r['error']} | — | — | — | — | — |")
        else:
            pct = r['profit_pct']
            icon = "🟢" if pct > 0 else ("🔴" if pct < 0 else "⚪")
            sign = "+" if pct >= 0 else ""
            win = f"{r['tp']/r['deals']*100:.0f}%" if r['deals'] > 0 else "—"
            lines.append(
                f"| {i} | {label} | ${r['balance']:,.2f} | ${r['profit']:+,.2f} "
                f"| {icon} {sign}{pct:.2f}% | {r['deals']} | {r['sl']} | {r['tp']} | {r['be']} | {win} |"
            )

    valid = [(l, r) for l, r in results if "error" not in r]
    if valid:
        avg = sum(r['profit_pct'] for _, r in valid) / len(valid)
        total_pnl = sum(r['profit'] for _, r in valid)
        best = max(valid, key=lambda x: x[1]['profit_pct'])
        worst = min(valid, key=lambda x: x[1]['profit_pct'])
        lines += [
            "\n## Summary\n",
            f"- **Average P&L:** {avg:+.2f}%",
            f"- **Total P&L (across all tests):** ${total_pnl:+,.2f}",
            f"- **Best:** {best[0]} → {best[1]['profit_pct']:+.2f}%",
            f"- **Worst:** {worst[0]} → {worst[1]['profit_pct']:+.2f}%",
        ]

    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    main()
