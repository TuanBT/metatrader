"""
deep_compare.py — Deep comparison of MT5 Strategy Tester vs Python backtest.

Goals:
1. Match signals with proper tolerance per pair
2. For matched signals: compare Entry/SL/TP precision
3. For unmatched signals: figure out WHY
4. Test both limit_order modes and find optimal approach
"""

import re
import sys
import os
import pandas as pd
import numpy as np
from pathlib import Path
from collections import defaultdict

SCRIPT_DIR = Path(__file__).parent
STRATEGY_DIR = Path("/Users/tuan/GitProject/tradingview/MST Medio/backtest")
sys.path.insert(0, str(STRATEGY_DIR))
from strategy_mst_medio import run_mst_medio, Signal

CANDLE_DIR = Path("/Users/tuan/GitProject/metatrader/candle data")
LOG_DIR = SCRIPT_DIR.parent / "logs"

PAIRS = ["BTCUSDm", "XAUUSDm", "EURUSDm", "USDJPYm", "ETHUSDm", "USOILm"]

# Matching tolerance per pair (as absolute price difference)
TOLERANCES = {
    "BTCUSDm": 1.0,       # BTC ±$1 
    "XAUUSDm": 0.10,      # Gold ±$0.10
    "EURUSDm": 0.00010,   # FX ±1 pip
    "USDJPYm": 0.010,     # JPY ±1 pip
    "ETHUSDm": 0.50,      # ETH ±$0.50
    "USOILm":  0.05,      # Oil ±$0.05
}


def parse_mt5_signals(log_path: str) -> list:
    """Parse only alert signals from MT5 log."""
    for enc in ["utf-16-le", "utf-16", "utf-8", "latin-1"]:
        try:
            with open(log_path, "r", encoding=enc, errors="replace") as f:
                content = f.readlines()
            break
        except:
            continue
    
    signals = []
    for line in content:
        m = re.search(
            r'(\d{4}\.\d{2}\.\d{2}\s+\d{2}:\d{2}:\d{2}).*'
            r'Alert: MST Medio:\s*(BUY|SELL)\s*\|\s*Entry=([\d.]+)\s*SL=([\d.]+)\s*TP=([\d.]+)',
            line
        )
        if m:
            signals.append({
                "time": pd.Timestamp(m.group(1).replace(".", "-", 2)),
                "dir": m.group(2),
                "entry": float(m.group(3)),
                "sl": float(m.group(4)),
                "tp": float(m.group(5)),
            })
    
    # Also extract final balance and TP/SL counts
    tp_hits = sum(1 for l in content if "take profit triggered" in l)
    sl_hits = sum(1 for l in content if "stop loss triggered" in l)
    final_bal = 0
    for l in reversed(content):
        m = re.search(r'final balance\s+([\d.-]+)', l)
        if m:
            final_bal = float(m.group(1))
            break
    
    # Get date range
    date_from = date_to = None
    for l in content:
        m = re.search(r'testing of .+ from (\d{4}\.\d{2}\.\d{2}) .* to (\d{4}\.\d{2}\.\d{2})', l)
        if m:
            date_from = pd.Timestamp(m.group(1).replace(".", "-", 2))
            date_to = pd.Timestamp(m.group(2).replace(".", "-", 2))
            break
    
    return signals, tp_hits, sl_hits, final_bal, date_from, date_to


def run_python(pair: str, limit_order: bool, date_from=None, date_to=None):
    """Run Python backtest for a pair."""
    csv_file = CANDLE_DIR / f"{pair}_M5.csv"
    if not csv_file.exists():
        return []
    
    df = pd.read_csv(csv_file, parse_dates=["datetime"])
    df.set_index("datetime", inplace=True)
    df.sort_index(inplace=True)
    
    signals, _ = run_mst_medio(
        df, pivot_len=5, break_mult=0.25, impulse_mult=1.0,
        sl_buffer_pct=5.0, tp_mode="confirm", limit_order=limit_order,
    )
    
    # Filter to date range
    if date_from:
        signals = [s for s in signals if s.time >= date_from]
    if date_to:
        signals = [s for s in signals if s.time <= date_to]
    
    return signals


def match_signals(mt5_sigs, py_sigs, tol):
    """Match MT5 signals with Python signals within tolerance."""
    matched = []       # (mt5_idx, py_idx, entry_diff)
    mt5_used = set()
    py_used = set()
    
    # First pass: match by time + direction + entry within tolerance
    for i, mt5 in enumerate(mt5_sigs):
        best_j = None
        best_diff = float('inf')
        
        for j, py in enumerate(py_sigs):
            if j in py_used:
                continue
            if mt5["dir"] != py.direction:
                continue
            
            entry_diff = abs(mt5["entry"] - py.entry)
            if entry_diff <= tol:
                # Also check time proximity (within 24 hours)
                time_diff = abs((mt5["time"] - py.time).total_seconds())
                if time_diff < 86400:  # 24h
                    if entry_diff < best_diff:
                        best_diff = entry_diff
                        best_j = j
        
        if best_j is not None:
            matched.append((i, best_j, best_diff))
            mt5_used.add(i)
            py_used.add(best_j)
    
    # Second pass: relaxed matching (same direction, wider tolerance)
    for i, mt5 in enumerate(mt5_sigs):
        if i in mt5_used:
            continue
        best_j = None
        best_diff = float('inf')
        
        for j, py in enumerate(py_sigs):
            if j in py_used:
                continue
            if mt5["dir"] != py.direction:
                continue
            
            entry_diff = abs(mt5["entry"] - py.entry)
            if entry_diff <= tol * 5:  # 5x tolerance
                time_diff = abs((mt5["time"] - py.time).total_seconds())
                if time_diff < 3600 * 48:  # 48h
                    if entry_diff < best_diff:
                        best_diff = entry_diff
                        best_j = j
        
        if best_j is not None:
            matched.append((i, best_j, best_diff))
            mt5_used.add(i)
            py_used.add(best_j)
    
    mt5_only = [i for i in range(len(mt5_sigs)) if i not in mt5_used]
    py_only = [j for j in range(len(py_sigs)) if j not in py_used]
    
    return matched, mt5_only, py_only


def analyze_pair(pair: str, verbose: bool = False):
    """Full analysis for a single pair."""
    log_file = LOG_DIR / f"{pair}.log"
    if not log_file.exists():
        print(f"  ⚠️ No log for {pair}")
        return None
    
    tol = TOLERANCES.get(pair, 1.0)
    
    # Parse MT5
    mt5_sigs, mt5_tp, mt5_sl, mt5_bal, date_from, date_to = parse_mt5_signals(str(log_file))
    
    if not mt5_sigs:
        print(f"  ❌ No signals in {pair} log")
        return None
    
    # Run Python both modes
    py_limit = run_python(pair, limit_order=True, date_from=date_from, date_to=date_to)
    py_instant = run_python(pair, limit_order=False, date_from=date_from, date_to=date_to)
    
    # Match signals
    matched, mt5_only, py_only = match_signals(mt5_sigs, py_limit, tol)
    
    # Python stats
    def pystats(sigs):
        closed = [s for s in sigs if s.result in ("TP", "SL", "CLOSE_REVERSE")]
        unfilled = [s for s in sigs if s.result == "UNFILLED"]
        if not closed:
            return 0, 0, 0, 0, 0
        wins = sum(1 for s in closed if s.pnl_r > 0)
        wr = wins / len(closed) * 100
        pnl = sum(s.pnl_r for s in closed)
        tp = sum(1 for s in closed if s.result == "TP")
        sl = sum(1 for s in closed if s.result == "SL")
        return len(closed), wr, pnl, tp, sl
    
    py_lim_closed, py_lim_wr, py_lim_pnl, py_lim_tp, py_lim_sl = pystats(py_limit)
    py_ins_closed, py_ins_wr, py_ins_pnl, py_ins_tp, py_ins_sl = pystats(py_instant)
    
    # Calculate MT5 WR (approximate from TP/SL counts, 
    # note: TP+SL might not = total due to reversed signals)
    mt5_total = mt5_tp + mt5_sl
    mt5_wr = mt5_tp / mt5_total * 100 if mt5_total > 0 else 0
    
    result = {
        "pair": pair,
        "mt5_signals": len(mt5_sigs),
        "mt5_tp": mt5_tp,
        "mt5_sl": mt5_sl,
        "mt5_wr": mt5_wr,
        "mt5_balance": mt5_bal,
        "py_limit_signals": len(py_limit),
        "py_limit_closed": py_lim_closed,
        "py_limit_wr": py_lim_wr,
        "py_limit_pnl": py_lim_pnl,
        "py_instant_signals": len(py_instant),
        "py_instant_closed": py_ins_closed,
        "py_instant_wr": py_ins_wr,
        "py_instant_pnl": py_ins_pnl,
        "matched": len(matched),
        "mt5_only": len(mt5_only),
        "py_only": len(py_only),
        "match_rate": len(matched) / len(mt5_sigs) * 100 if mt5_sigs else 0,
    }
    
    if verbose:
        print(f"\n  --- {pair} Details ---")
        print(f"  First 5 matched signals:")
        for mi, pi, diff in matched[:5]:
            mt5 = mt5_sigs[mi]
            py = py_limit[pi]
            print(f"    MT5: {mt5['time']} {mt5['dir']:4s} E={mt5['entry']:.5f} SL={mt5['sl']:.5f} TP={mt5['tp']:.5f}")
            print(f"    PY:  {py.time} {py.direction:4s} E={py.entry:.5f} SL={py.sl:.5f} TP={py.tp:.5f} | diff={diff:.5f}")
            print()
        
        if mt5_only:
            print(f"  First 5 MT5-only (unmatched):")
            for idx in mt5_only[:5]:
                s = mt5_sigs[idx]
                print(f"    {s['time']} {s['dir']:4s} E={s['entry']:.5f} SL={s['sl']:.5f}")
    
    return result


def main():
    print(f"{'='*80}")
    print(f"  MST Medio — Deep Comparison: MT5 Strategy Tester vs Python Backtest")
    print(f"{'='*80}")
    
    verbose = "--verbose" in sys.argv or "-v" in sys.argv
    
    target_pair = None
    if "--pair" in sys.argv:
        idx = sys.argv.index("--pair")
        if idx + 1 < len(sys.argv):
            target_pair = sys.argv[idx + 1]
    
    pairs = [target_pair] if target_pair else PAIRS
    
    results = []
    for pair in pairs:
        print(f"\n📊 Analyzing {pair}...")
        r = analyze_pair(pair, verbose=verbose)
        if r:
            results.append(r)
    
    if not results:
        print("No results to display.")
        return
    
    # Summary table
    print(f"\n\n{'='*100}")
    print(f"  COMPREHENSIVE SUMMARY")
    print(f"{'='*100}")
    
    # MT5 results
    print(f"\n  📋 MT5 Strategy Tester Results:")
    print(f"  {'Pair':<10s} {'Signals':>8s} {'TP':>5s} {'SL':>5s} {'WR%':>7s} {'Balance':>12s}")
    print(f"  {'-'*50}")
    for r in results:
        print(f"  {r['pair']:<10s} {r['mt5_signals']:>8d} {r['mt5_tp']:>5d} {r['mt5_sl']:>5d} {r['mt5_wr']:>6.1f}% {r['mt5_balance']:>12.2f}")
    
    # Python limit order results
    print(f"\n  🐍 Python Backtest (Limit Order — Realistic):")
    print(f"  {'Pair':<10s} {'Signals':>8s} {'Closed':>7s} {'WR%':>7s} {'PnL(R)':>10s}")
    print(f"  {'-'*45}")
    total_pnl_limit = 0
    for r in results:
        print(f"  {r['pair']:<10s} {r['py_limit_signals']:>8d} {r['py_limit_closed']:>7d} {r['py_limit_wr']:>6.1f}% {r['py_limit_pnl']:>+10.2f}")
        total_pnl_limit += r['py_limit_pnl']
    print(f"  {'TOTAL':<10s} {'':>8s} {'':>7s} {'':>7s} {total_pnl_limit:>+10.2f}")
    
    # Python instant fill results
    print(f"\n  🐍 Python Backtest (Instant Fill — Legacy):")
    print(f"  {'Pair':<10s} {'Signals':>8s} {'Closed':>7s} {'WR%':>7s} {'PnL(R)':>10s}")
    print(f"  {'-'*45}")
    total_pnl_instant = 0
    for r in results:
        print(f"  {r['pair']:<10s} {r['py_instant_signals']:>8d} {r['py_instant_closed']:>7d} {r['py_instant_wr']:>6.1f}% {r['py_instant_pnl']:>+10.2f}")
        total_pnl_instant += r['py_instant_pnl']
    print(f"  {'TOTAL':<10s} {'':>8s} {'':>7s} {'':>7s} {total_pnl_instant:>+10.2f}")
    
    # Signal matching
    print(f"\n  🔗 Signal Matching (MT5 ↔ Python):")
    print(f"  {'Pair':<10s} {'Matched':>8s} {'MT5-only':>9s} {'PY-only':>8s} {'Match%':>8s}")
    print(f"  {'-'*46}")
    for r in results:
        print(f"  {r['pair']:<10s} {r['matched']:>8d} {r['mt5_only']:>9d} {r['py_only']:>8d} {r['match_rate']:>7.1f}%")
    
    # Key findings
    print(f"\n\n{'='*80}")
    print(f"  KEY FINDINGS")
    print(f"{'='*80}")
    
    # Which pairs profitable in MT5?
    mt5_profitable = [r for r in results if r['mt5_balance'] > 10000]
    mt5_losing = [r for r in results if r['mt5_balance'] < 10000]
    
    print(f"\n  MT5 Profitable pairs (bal > deposit):")
    for r in mt5_profitable:
        print(f"    ✅ {r['pair']}: {r['mt5_balance']:.2f} pips")
    print(f"  MT5 Losing pairs:")
    for r in mt5_losing:
        print(f"    ❌ {r['pair']}: {r['mt5_balance']:.2f} pips")
    
    # Python limit order vs MT5
    print(f"\n  Python (Limit Order) vs MT5 WR comparison:")
    for r in results:
        diff = r['py_limit_wr'] - r['mt5_wr']
        marker = "✅" if abs(diff) < 5 else "⚠️"
        print(f"    {marker} {r['pair']}: MT5={r['mt5_wr']:.1f}% PY={r['py_limit_wr']:.1f}% (diff={diff:+.1f}%)")
    
    print(f"\n  Total PnL: Instant={total_pnl_instant:+.2f}R | Limit={total_pnl_limit:+.2f}R")


if __name__ == "__main__":
    main()
