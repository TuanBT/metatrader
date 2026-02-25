#!/usr/bin/env python3
"""
MST Medio v4.11 (no BE) — XAUUSD H1 + M5 Session Analysis
Tests:
  1. XAUUSD H1 5/5 NoPart 2025
  2. XAUUSD H1 5/5 NoPart 2024
  3. XAUUSD M5 5/5 NoPart 2025  ← session analysis by hour
  4. XAUUSD M5 5/5 NoPart 2024  ← session analysis by hour

Session analysis: After each M5 run, fetch the agent log from VPS,
parse deal times by hour (UTC), and compute win rate per hour.
Helps identify which trading sessions to avoid.
"""

import subprocess, time, re, os, tempfile
from datetime import datetime
from collections import defaultdict

SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")

MT5_DATA   = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_TESTER = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06"
AGENT_LOGS = MT5_TESTER + r"\Agent-127.0.0.1-3000\logs"
EA_PATH    = r"MST Medio\Expert MST Medio"
DEPOSIT    = 500
LEVERAGE   = 100
RESULT_MD  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mst_medio_h1_session_results.md")

# ── BASE config (v4.11 — no InpBEAtR) ────────────────────────────────────────
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
    "InpUseMTFConsensus":      "true",
    "InpMTFMinAgree":          "5",
    "InpMTFTrailOnConsensus":  "true",
    "InpMTFTrailStartR":       "0.5",
    "InpMTFTrailStepR":        "0.25",
    "InpUsePartialTP":         "false",
    "InpPartialTPAtR":         "2.0",
    "InpPartialLotPct":        "50",
    "InpSmartFlip":            "true",
    "InpRequireConfirmCandle": "false",
    "InpMagic":                "20241201",
    "InpMaxPositions":         "1",
}

# ── TEST MATRIX ───────────────────────────────────────────────────────────────
# (symbol, tf, from_date, to_date, run_session_analysis, label)
TESTS = [
    ("XAUUSDm", "H1", "2025.01.01", "2026.02.01", False, "XAUUSD H1 5/5 NoPart 2025"),
    ("XAUUSDm", "H1", "2024.01.01", "2025.01.01", False, "XAUUSD H1 5/5 NoPart 2024"),
    ("XAUUSDm", "M5", "2025.01.01", "2026.02.01", True,  "XAUUSD M5 5/5 NoPart 2025 [session]"),
    ("XAUUSDm", "M5", "2024.01.01", "2025.01.01", True,  "XAUUSD M5 5/5 NoPart 2024 [session]"),
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


def scp_download(remote, local):
    """Download file from VPS to local path."""
    full = ["sshpass", "-p", SSH_PASS, "scp", "-o", "StrictHostKeyChecking=no",
            f"{SSH_USER}@{SSH_HOST}:{remote}", local]
    r = subprocess.run(full, capture_output=True, text=True, timeout=60)
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


def wait_done(max_wait=540):
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

        return {"balance": bal, "profit": p, "profit_pct": p / DEPOSIT * 100,
                "deals": gi(r'DEALS=(\d+)'), "sl": gi(r'(?<!\w)SL=(\d+)'),
                "tp": gi(r'TP=(\d+)'), "be": gi(r'BE=(\d+)')}
    if "thread finished" in log.lower():
        return {"balance": DEPOSIT, "profit": 0, "profit_pct": 0, "deals": 0, "sl": 0, "tp": 0, "be": 0}
    return {"error": f"No result: {log[:120]}"}


# ── SESSION ANALYSIS ─────────────────────────────────────────────────────────
def fetch_log_for_session(date_str):
    """Copy agent log to C:\\Temp, then SCP it locally. Returns local path or None."""
    remote_log = f"{AGENT_LOGS}\\{date_str}.log"
    tmp_remote  = r"C:\Temp\agent_log_session.log"
    # Copy via PowerShell (handles backslash paths reliably)
    cp_out = ssh(f'powershell -Command "Copy-Item \'{remote_log}\' \'{tmp_remote}\' -Force; Write-Host COPIED"')
    if "COPIED" not in cp_out and "COPIED" not in cp_out.upper():
        # Try date -1 (in case test finished just after midnight)
        from datetime import datetime, timedelta
        d = datetime.strptime(date_str, "%Y%m%d") - timedelta(days=1)
        remote_log = f"{AGENT_LOGS}\\{d.strftime('%Y%m%d')}.log"
        cp_out = ssh(f'powershell -Command "Copy-Item \'{remote_log}\' \'{tmp_remote}\' -Force; Write-Host COPIED"')
        if "COPIED" not in cp_out:
            return None
    local_log = os.path.join(tempfile.gettempdir(), f"mst_agent_{date_str}.log")
    if scp_download("C:/Temp/agent_log_session.log", local_log):
        return local_log
    return None


def analyze_session(log_path):
    """
    Parse agent log and group trades by entry hour (UTC).
    Returns dict: {hour: {"entries": n, "sl": n, "tp_or_trail": n}}
    
    Strategy:
      - 'deal performed' lines that are NOT "stop loss" or "take profit" = entries
        (Actually MT5 logs all deals as 'deal performed'; we look for "buy " or "sell " to isolate entries)
      - 'stop loss triggered' lines = SL exits
      - Anything else closing = profit exit
    """
    if not log_path or not os.path.exists(log_path):
        return None

    # Pattern: timestamp at start of line (YYYY.MM.DD HH:MM)
    ts_pattern = re.compile(r'^(\d{4})\.(\d{2})\.(\d{2})\s+(\d{2}):(\d{2})')

    hour_data = defaultdict(lambda: {"entries": 0, "sl": 0, "win": 0})

    try:
        with open(log_path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except Exception as e:
        return None

    for line in lines:
        m = ts_pattern.match(line)
        if not m:
            continue
        hour = int(m.group(4))
        lower = line.lower()

        # Entry deals: 'deal performed' with direction
        if "deal performed" in lower and ("buy " in lower or "sell " in lower):
            # Skip if it's also a close keyword
            if "stop loss" not in lower and "take profit" not in lower:
                hour_data[hour]["entries"] += 1

        # Losing exits
        elif "stop loss triggered" in lower:
            hour_data[hour]["sl"] += 1

        # Winning exits (TP or trail close)
        elif "take profit triggered" in lower:
            hour_data[hour]["win"] += 1

    if not hour_data:
        return None

    return dict(hour_data)


def format_session_table(session_data, label):
    """Format session analysis as a readable table."""
    if not session_data:
        return f"\n*Session data unavailable for {label}*\n"

    lines = [f"\n### Session Analysis — {label}", ""]
    lines.append("| Hour (UTC) | Entries | SL | Win | Win Rate |")
    lines.append("|-----------|---------|----|----|---------|")

    good_hours = []
    bad_hours  = []

    for h in range(24):
        d = session_data.get(h, {"entries": 0, "sl": 0, "win": 0})
        if d["entries"] == 0:
            continue
        wr = (d["win"] / d["entries"] * 100) if d["entries"] > 0 else 0
        icon = "🟢" if wr >= 50 else ("🔴" if wr < 30 else "🟡")
        lines.append(f"| {h:02d}:00 | {d['entries']} | {d['sl']} | {d['win']} | {icon} {wr:.0f}% |")
        if wr >= 50 and d["entries"] >= 3:
            good_hours.append(h)
        elif wr < 30 and d["entries"] >= 3:
            bad_hours.append(h)

    if good_hours:
        lines.append(f"\n**Best hours (≥50% WR, ≥3 entries):** {', '.join(f'{h:02d}:00' for h in sorted(good_hours))}")
    if bad_hours:
        lines.append(f"**Avoid hours (<30% WR, ≥3 entries):** {', '.join(f'{h:02d}h' for h in sorted(bad_hours))}")

    return "\n".join(lines)


# ── MAIN BACKTEST LOOP ────────────────────────────────────────────────────────
def run_one(symbol, tf, from_d, to_d):
    if mt5_running():
        kill_mt5()
    cfg = {**BASE}
    time.sleep(1)
    if not write_ini_and_run(symbol, tf, from_d, to_d, cfg):
        return {"error": "INI failed"}, None

    time.sleep(10)
    for _ in range(8):
        if mt5_running():
            break
        time.sleep(4)
    if not wait_done(540):
        return {"error": "Timeout"}, None

    date_str = get_server_date()
    log_text = read_agent_log(date_str)
    r = parse_log(log_text)
    if "error" in r:
        time.sleep(8)
        log_text = read_agent_log(date_str)
        r = parse_log(log_text)

    local_log = fetch_log_for_session(date_str)
    return r, local_log


def fmt(r):
    if "error" in r:
        return f"❌ {r['error']}"
    icon = "🟢" if r['profit_pct'] > 0 else ("🔴" if r['profit_pct'] < 0 else "⚪")
    sign = "+" if r['profit_pct'] >= 0 else ""
    win = f"{r['tp'] / r['deals'] * 100:.0f}%" if r['deals'] else "—"
    return f"{icon} ${r['balance']:,.2f} ({sign}{r['profit_pct']:.2f}%)  D:{r['deals']} SL:{r['sl']} Win:{win}"


def main():
    print("=" * 70)
    print("  MST Medio v4.11 — XAUUSD H1 + M5 Session Analysis")
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
    compiled_ok = "0 errors" in out
    print("✅" if compiled_ok else f"⚠️ {out[-200:]}")
    if not compiled_ok:
        print("Compile failed — check EA"); return
    print()

    results = []
    session_tables = []

    for i, (sym, tf, fd, td, do_session, label) in enumerate(TESTS, 1):
        print(f"{'─' * 70}")
        print(f"  [{i}/{len(TESTS)}] {label}")
        r, local_log = run_one(sym, tf, fd, td)
        results.append((label, sym, tf, fd[-4:], r))
        print(f"  → {fmt(r)}")

        if do_session and local_log:
            print(f"  📊 Analyzing session from log...", end=" ")
            sdata = analyze_session(local_log)
            if sdata:
                print(f"✅ ({len(sdata)} hours with data)")
                session_tables.append(format_session_table(sdata, label))
            else:
                # Fallback: try simple timestamp extraction via PS
                print("⚠️ local parse failed")
                session_tables.append(f"\n*Session parse failed for {label}*\n")
        elif do_session:
            print("  ⚠️ Could not download log for session analysis")
            session_tables.append(f"\n*Log download failed for {label}*\n")

    # ── Report ────────────────────────────────────────────────────────────────
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [
        "# MST Medio v4.11 — XAUUSD H1 + M5 Session Analysis\n",
        f"**Date:** {now}   **Risk:** $5/trade   **Deposit:** ${DEPOSIT}",
        f"**Config:** ATR×3 | TP 10R | MTF 5/5 | Trail 0.5R start, 0.25R step | No BE | No Partial TP\n",
        "## Results\n",
        "| Label | Year | % | Deals | SL |",
        "|-------|------|---|-------|----|",
    ]
    for label, sym, tf, yr, r in results:
        if "error" in r:
            lines.append(f"| {label} | {yr} | ❌ | — | — |")
        else:
            pct  = r['profit_pct']
            icon = "🟢" if pct > 0 else ("🔴" if pct < 0 else "⚪")
            sign = "+" if pct >= 0 else ""
            lines.append(f"| {label} | {yr} | {icon} {sign}{pct:.2f}% | {r['deals']} | {r['sl']} |")

    valid = [(lb, r) for lb, *_, r in results if "error" not in r]
    if valid:
        best = max(valid, key=lambda x: x[1]['profit_pct'])
        lines += ["", f"**Best:** {best[0]} → {best[1]['profit_pct']:+.2f}%"]

    # Append session tables
    if session_tables:
        lines += ["", "## Session Analysis (by Entry Hour UTC)"]
        lines += session_tables

    lines += [
        "",
        "## Reference: Previous M5 Multi-Pair (v4.10)",
        "| Pair | 2025 | 2024 |",
        "|------|------|------|",
        "| XAUUSD M5 5/5 | +12.72% | -6.73% |",
        "| EURUSD M5 5/5 | +4.85%  | -10.25% |",
        "| GBPUSD M5 5/5 | +1.50%  | -0.20% |",
    ]

    report = "\n".join(lines) + "\n"
    with open(RESULT_MD, "w") as f:
        f.write(report)
    print(f"\n\n{'=' * 70}")
    print(f"📄 {RESULT_MD}")
    print(f"\n{report}")

    ssh('schtasks /delete /tn "MT5BT" /f 2>nul')


if __name__ == "__main__":
    main()
