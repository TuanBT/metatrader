#!/usr/bin/env python3
"""
Quick session analysis re-run — XAUUSD M5 5/5 2025 + 2024
Uses same config as bt_mst_medio_h1_session.py but only runs M5 session tests.
Fixes SCP path issue (uses C:\\Temp staging).
"""

import subprocess, time, re, os, tempfile
from datetime import datetime, timedelta
from collections import defaultdict
import sys

# Import helpers from main session script
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bt_mst_medio_h1_session import (
    ssh, scp_upload, scp_download, kill_mt5, mt5_running, get_server_date,
    read_agent_log, write_ini_and_run, wait_done, parse_log, fmt, BASE,
    SSH_PASS, SSH_HOST, SSH_USER, DEPOSIT, RESULT_MD,
    analyze_session, format_session_table
)
from bt_mst_medio_h1_session import fetch_log_for_session  # now fixed

AGENT_LOGS = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\53785E099C927DB68A545C249CDBCE06\Agent-127.0.0.1-3000\logs"

SESSION_TESTS = [
    ("XAUUSDm", "M5", "2025.01.01", "2026.02.01", "XAUUSD M5 5/5 2025"),
    ("XAUUSDm", "M5", "2024.01.01", "2025.01.01", "XAUUSD M5 5/5 2024"),
]

SESSION_RESULT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mst_medio_session_analysis.md")


def run_and_analyze(sym, tf, fd, td, label):
    if mt5_running():
        kill_mt5()
    cfg = {**BASE}
    if not write_ini_and_run(sym, tf, fd, td, cfg):
        return None, None
    time.sleep(10)
    for _ in range(8):
        if mt5_running(): break
        time.sleep(4)
    if not wait_done(540):
        return {"error": "Timeout"}, None
    date_str = get_server_date()
    log_text = read_agent_log(date_str)
    r = parse_log(log_text)
    if "error" in r:
        time.sleep(8)
        r = parse_log(read_agent_log(date_str))
    local_log = fetch_log_for_session(date_str)
    return r, local_log


def main():
    print("=" * 65)
    print("  Session Analysis — XAUUSD M5 5/5 (2025 + 2024)")
    print("=" * 65)
    if "OK" not in ssh("echo OK"):
        print("❌ SSH fail"); return

    # No recompile needed (same EA as bt_mst_medio_h1_session.py just ran)
    print("✅ SSH OK — using already-compiled EA v4.11\n")

    all_results = []
    for sym, tf, fd, td, label in SESSION_TESTS:
        print(f"{'─'*65}")
        print(f"  {label}")
        r, local_log = run_and_analyze(sym, tf, fd, td, label)
        all_results.append((label, r, local_log))
        print(f"  → {fmt(r) if r else '❌ failed'}")
        if local_log:
            sdata = analyze_session(local_log)
            if sdata:
                print(f"  📊 Session data: {len(sdata)} hours")
            else:
                print("  ⚠️ Could not parse session from log")

    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [
        "# MST Medio v4.11 — Session Analysis XAUUSD M5\n",
        f"**Date:** {now}   **Risk:** $5/trade   **Deposit:** ${DEPOSIT}\n",
        "## Summary\n",
        "| Label | % | Deals | SL |",
        "|-------|---|-------|----|",
    ]
    session_blocks = []
    for label, r, local_log in all_results:
        if not r or "error" in r:
            lines.append(f"| {label} | ❌ | — | — |")
        else:
            pct = r['profit_pct']
            icon = "🟢" if pct > 0 else "🔴"
            sign = "+" if pct >= 0 else ""
            lines.append(f"| {label} | {icon} {sign}{pct:.2f}% | {r['deals']} | {r['sl']} |")
        if local_log:
            sdata = analyze_session(local_log)
            session_blocks.append(format_session_table(sdata, label))

    if session_blocks:
        lines += ["", "## Session Analysis (Entry Hour UTC)"]
        lines += session_blocks

    report = "\n".join(lines) + "\n"
    with open(SESSION_RESULT, "w") as f:
        f.write(report)
    print(f"\n📄 {SESSION_RESULT}")
    print(f"\n{report}")


if __name__ == "__main__":
    main()
