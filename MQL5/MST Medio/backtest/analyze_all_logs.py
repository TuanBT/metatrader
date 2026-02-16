"""
analyze_all_logs.py — Parse ALL MT5 Strategy Tester logs and compare with Python backtest.

Usage:
  python analyze_all_logs.py                # Analyze all logs in ../logs/
  python analyze_all_logs.py --pair BTCUSDm # Analyze only BTCUSDm

Log files expected in: ../logs/<PAIR>.log
  e.g. BTCUSDm.log, XAUUSDm.log, EURUSDm.log, USDJPYm.log, ETHUSDm.log, USOILm.log
"""

import re
import sys
import os
import pandas as pd
import numpy as np
from pathlib import Path

# Add strategy module path
SCRIPT_DIR = Path(__file__).parent
STRATEGY_DIR = Path("/Users/tuan/GitProject/tradingview/MST Medio/backtest")
sys.path.insert(0, str(STRATEGY_DIR))
from strategy_mst_medio import run_mst_medio, Signal

CANDLE_DIR = Path("/Users/tuan/GitProject/metatrader/candle data")
LOG_DIR = SCRIPT_DIR.parent / "logs"

PAIRS = ["BTCUSDm", "XAUUSDm", "EURUSDm", "USDJPYm", "ETHUSDm", "USOILm"]


# ============================================================================
# MT5 LOG PARSER
# ============================================================================
def parse_mt5_log(log_path: str) -> dict:
    """Parse MT5 Strategy Tester log file and extract all trade events."""
    
    # Try different encodings
    content = None
    for enc in ["utf-16-le", "utf-16", "utf-8", "latin-1"]:
        try:
            with open(log_path, "r", encoding=enc, errors="replace") as f:
                content = f.readlines()
            break
        except:
            continue
    
    if content is None:
        print(f"  ❌ Cannot read {log_path}")
        return {}
    
    result = {
        "pair": "",
        "period": "",
        "date_from": "",
        "date_to": "",
        "deposit": 0,
        "settings": {},
        "signals": [],       # Alert signals (Entry/SL/TP)
        "pending_starts": [],  # Pending BUY/SELL: ...
        "pending_cancels": [], # Cancelled pending
        "orders": [],        # buy limit, sell limit, etc.
        "deals": [],         # deal done (fill, sl, tp)
        "tp_hits": 0,
        "sl_hits": 0,
        "final_balance": 0,
        "total_lines": len(content),
    }
    
    for line in content:
        line = line.strip()
        
        # Test info
        m = re.search(r'testing of .+ from (\d{4}\.\d{2}\.\d{2}) .* to (\d{4}\.\d{2}\.\d{2})', line)
        if m:
            result["date_from"] = m.group(1)
            result["date_to"] = m.group(2)
        
        # Symbol
        m = re.search(r'Expert MST Medio \((\w+),(\w+)\)', line)
        if m:
            if not result["pair"]:
                result["pair"] = m.group(1)
                result["period"] = m.group(2)
        
        # Deposit
        m = re.search(r'initial deposit (\d+)', line)
        if m:
            result["deposit"] = int(m.group(1))
        
        # Settings
        m = re.search(r'(Inp\w+)=([\w.]+)', line)
        if m:
            result["settings"][m.group(1)] = m.group(2)
        
        # Signal alerts
        m = re.search(r'(\d{4}\.\d{2}\.\d{2}\s+\d{2}:\d{2}:\d{2}).*Alert: MST Medio:\s*(BUY|SELL)\s*\|\s*Entry=([\d.]+)\s*SL=([\d.]+)\s*TP=([\d.]+)', line)
        if m:
            result["signals"].append({
                "time": m.group(1),
                "dir": m.group(2),
                "entry": float(m.group(3)),
                "sl": float(m.group(4)),
                "tp": float(m.group(5)),
            })
        
        # Pending start
        if ("Pending BUY:" in line or "Pending SELL:" in line) and "cancelled" not in line:
            m = re.search(r'(\d{4}\.\d{2}\.\d{2}\s+\d{2}:\d{2}:\d{2}).*Pending (BUY|SELL): Break .* SH0=([\d.]+)|SL0=([\d.]+)', line)
            if m:
                result["pending_starts"].append({
                    "time": m.group(1),
                    "dir": m.group(2),
                })
        
        # Pending cancel
        if "cancelled" in line:
            result["pending_cancels"].append(line)
        
        # Order events (buy limit, sell limit, etc.)
        m = re.search(r'(\d{4}\.\d{2}\.\d{2}\s+\d{2}:\d{2}:\d{2})\s+(buy|sell)\s+(limit|stop|market)\s+([\d.]+)\s+\w+\s+at\s+([\d.]+)', line)
        if m:
            result["orders"].append({
                "time": m.group(1),
                "type": f"{m.group(2)} {m.group(3)}",
                "lot": float(m.group(4)),
                "price": float(m.group(5)),
            })
        
        # Deal events
        m = re.search(r'deal\s+#\d+\s+.*?(buy|sell)\s+([\d.]+)\s+\w+\s+at\s+([\d.]+)\s+done', line)
        if m:
            result["deals"].append({
                "type": m.group(1),
                "lot": float(m.group(2)),
                "price": float(m.group(3)),
            })
        
        # TP/SL hits
        if "take profit triggered" in line:
            result["tp_hits"] += 1
        if "stop loss triggered" in line:
            result["sl_hits"] += 1
        
        # Final balance
        m = re.search(r'final balance\s+([\d.-]+)', line)
        if m:
            result["final_balance"] = float(m.group(1))
        
        # SKIP TRADE
        if "SKIP TRADE" in line:
            if "skips" not in result:
                result["skips"] = 0
            result["skips"] += 1
    
    return result


def reconstruct_mt5_trades(parsed: dict) -> list:
    """Reconstruct trade-by-trade results from MT5 log signals."""
    signals = parsed["signals"]
    if not signals:
        return []
    
    trades = []
    for i, sig in enumerate(signals):
        entry = sig["entry"]
        sl = sig["sl"]
        tp = sig["tp"]
        direction = sig["dir"]
        risk = abs(entry - sl)
        
        trades.append({
            "time": sig["time"],
            "dir": direction,
            "entry": entry,
            "sl": sl,
            "tp": tp,
            "risk": risk,
        })
    
    return trades


# ============================================================================
# PYTHON BACKTEST RUNNER
# ============================================================================
def run_python_backtest(pair: str, limit_order: bool = True) -> list:
    """Run Python backtest for a given pair and return signals."""
    csv_file = CANDLE_DIR / f"{pair}_M5.csv"
    if not csv_file.exists():
        print(f"  ❌ No data file: {csv_file}")
        return []
    
    df = pd.read_csv(csv_file, parse_dates=["datetime"])
    df.set_index("datetime", inplace=True)
    df.sort_index(inplace=True)
    
    signals, _ = run_mst_medio(
        df,
        pivot_len=5,
        break_mult=0.25,
        impulse_mult=1.0,
        sl_buffer_pct=5.0,
        tp_mode="confirm",
        limit_order=limit_order,
    )
    return signals


# ============================================================================
# SIGNAL COMPARISON
# ============================================================================
def compare_signals(mt5_signals: list, py_signals: list, pair: str, tolerance_pct: float = 0.001):
    """Compare MT5 signals with Python backtest signals."""
    print(f"\n{'='*70}")
    print(f"  SIGNAL COMPARISON: {pair}")
    print(f"{'='*70}")
    print(f"  MT5 signals: {len(mt5_signals)}")
    print(f"  Python signals: {len(py_signals)}")
    
    if not mt5_signals or not py_signals:
        print("  ⚠️ Cannot compare — one side has no signals")
        return
    
    # Match signals by entry+direction (within tolerance)
    matched = 0
    mt5_only = []
    py_matched_idx = set()
    
    for mt5_sig in mt5_signals:
        found = False
        mt5_entry = mt5_sig["entry"]
        mt5_dir = mt5_sig["dir"]
        
        for j, py_sig in enumerate(py_signals):
            if j in py_matched_idx:
                continue
            py_entry = py_sig.entry
            py_dir = py_sig.direction
            
            if mt5_dir == py_dir:
                # Check if entries match within tolerance
                if mt5_entry > 0:
                    diff_pct = abs(mt5_entry - py_entry) / mt5_entry
                else:
                    diff_pct = abs(mt5_entry - py_entry)
                
                if diff_pct < tolerance_pct:
                    matched += 1
                    py_matched_idx.add(j)
                    found = True
                    break
        
        if not found:
            mt5_only.append(mt5_sig)
    
    py_only = [py_signals[i] for i in range(len(py_signals)) if i not in py_matched_idx]
    
    print(f"\n  Matched: {matched}")
    print(f"  MT5-only: {len(mt5_only)}")
    print(f"  Python-only: {len(py_only)}")
    
    if mt5_only:
        print(f"\n  MT5-only signals (not in Python):")
        for s in mt5_only[:10]:
            print(f"    {s['time']} {s['dir']:4s} Entry={s['entry']:.2f} SL={s['sl']:.2f} TP={s['tp']:.2f}")
        if len(mt5_only) > 10:
            print(f"    ... and {len(mt5_only)-10} more")
    
    if py_only:
        print(f"\n  Python-only signals (not in MT5):")
        for s in py_only[:10]:
            print(f"    {s.time} {s.direction:4s} Entry={s.entry:.2f} SL={s.sl:.2f} TP={s.tp:.2f} Result={s.result}")
        if len(py_only) > 10:
            print(f"    ... and {len(py_only)-10} more")
    
    return matched, len(mt5_only), len(py_only)


# ============================================================================
# MAIN
# ============================================================================
def analyze_pair(pair: str):
    """Full analysis for a single pair."""
    log_file = LOG_DIR / f"{pair}.log"
    
    if not log_file.exists():
        print(f"\n⚠️ No log file for {pair} (expected: {log_file})")
        return None
    
    print(f"\n{'#'*70}")
    print(f"  ANALYZING: {pair}")
    print(f"{'#'*70}")
    
    # 1. Parse MT5 log
    print(f"\n📋 Parsing MT5 log: {log_file.name}")
    parsed = parse_mt5_log(str(log_file))
    
    if not parsed:
        return None
    
    print(f"  Period: {parsed.get('date_from', '?')} → {parsed.get('date_to', '?')}")
    print(f"  Deposit: {parsed.get('deposit', '?')} pips")
    print(f"  Settings: {parsed.get('settings', {})}")
    print(f"  Signals fired: {len(parsed['signals'])}")
    print(f"  Pending starts: {len(parsed['pending_starts'])}")
    print(f"  Pending cancels: {len(parsed['pending_cancels'])}")
    print(f"  TP hits: {parsed['tp_hits']}")
    print(f"  SL hits: {parsed['sl_hits']}")
    print(f"  Skipped (MaxRisk): {parsed.get('skips', 0)}")
    print(f"  Final balance: {parsed['final_balance']} pips")
    
    # MT5 trade results
    mt5_trades = reconstruct_mt5_trades(parsed)
    
    # Signal details
    print(f"\n📊 MT5 Signal Details:")
    for s in parsed["signals"]:
        risk = abs(s["entry"] - s["sl"])
        reward = abs(s["tp"] - s["entry"])
        rr = reward / risk if risk > 0 else 0
        print(f"  {s['time']} {s['dir']:4s} Entry={s['entry']:.2f} SL={s['sl']:.2f} TP={s['tp']:.2f} RR={rr:.2f}")
    
    # 2. Run Python backtest (both modes)
    csv_file = CANDLE_DIR / f"{pair}_M5.csv"
    if not csv_file.exists():
        print(f"\n  ❌ No M5 data for Python backtest")
        return parsed
    
    print(f"\n🐍 Running Python backtest (limit_order=True)...")
    py_signals_limit = run_python_backtest(pair, limit_order=True)
    
    # Filter to same date range as MT5
    if parsed["date_from"] and py_signals_limit:
        date_from = pd.Timestamp(parsed["date_from"].replace(".", "-"))
        date_to = pd.Timestamp(parsed["date_to"].replace(".", "-")) if parsed["date_to"] else None
        
        py_filtered = [s for s in py_signals_limit if s.time >= date_from]
        if date_to:
            py_filtered = [s for s in py_filtered if s.time <= date_to]
        
        py_signals_limit = py_filtered
    
    # Stats for limit order mode
    closed_limit = [s for s in py_signals_limit if s.result in ("TP", "SL", "CLOSE_REVERSE")]
    unfilled = [s for s in py_signals_limit if s.result == "UNFILLED"]
    
    if closed_limit:
        wins = sum(1 for s in closed_limit if s.pnl_r > 0)
        total_r = sum(s.pnl_r for s in closed_limit)
        tp_count = sum(1 for s in closed_limit if s.result == "TP")
        sl_count = sum(1 for s in closed_limit if s.result == "SL")
        wr = wins / len(closed_limit) * 100
        print(f"  Python (Limit Order): {len(py_signals_limit)} signals, {len(closed_limit)} closed, {len(unfilled)} unfilled")
        print(f"  TP={tp_count} SL={sl_count} WR={wr:.1f}% PnL={total_r:+.2f}R")
    else:
        print(f"  Python (Limit Order): {len(py_signals_limit)} signals, 0 closed")
    
    # 3. Compare signals
    if parsed["signals"] and py_signals_limit:
        compare_signals(parsed["signals"], py_signals_limit, pair)
    
    # 4. Summary result
    result = {
        "pair": pair,
        "mt5_signals": len(parsed["signals"]),
        "mt5_tp": parsed["tp_hits"],
        "mt5_sl": parsed["sl_hits"],
        "mt5_balance": parsed["final_balance"],
        "mt5_skipped": parsed.get("skips", 0),
        "py_signals": len(py_signals_limit),
        "py_closed": len(closed_limit),
        "py_unfilled": len(unfilled),
        "py_wr": wins / len(closed_limit) * 100 if closed_limit else 0,
        "py_pnl": sum(s.pnl_r for s in closed_limit) if closed_limit else 0,
    }
    
    return result


def main():
    # Parse args
    target_pair = None
    if "--pair" in sys.argv:
        idx = sys.argv.index("--pair")
        if idx + 1 < len(sys.argv):
            target_pair = sys.argv[idx + 1]
    
    pairs_to_analyze = [target_pair] if target_pair else PAIRS
    
    # Check log directory
    if not LOG_DIR.exists():
        print(f"❌ Log directory not found: {LOG_DIR}")
        print(f"   Please create it and add log files.")
        return
    
    available_logs = list(LOG_DIR.glob("*.log"))
    print(f"📂 Log directory: {LOG_DIR}")
    print(f"📄 Available logs: {[f.name for f in available_logs]}")
    
    if not available_logs:
        print(f"\n❌ No log files found in {LOG_DIR}")
        print(f"   Expected files: BTCUSDm.log, XAUUSDm.log, etc.")
        return
    
    # Analyze each pair
    results = []
    for pair in pairs_to_analyze:
        r = analyze_pair(pair)
        if r and isinstance(r, dict) and "pair" in r:
            results.append(r)
    
    # Overall summary
    if results:
        print(f"\n\n{'#'*70}")
        print(f"  OVERALL SUMMARY")
        print(f"{'#'*70}")
        print(f"\n  {'Pair':<10s} {'MT5 Sig':>8s} {'MT5 TP':>7s} {'MT5 SL':>7s} {'MT5 Bal':>10s} {'PY Sig':>7s} {'PY WR':>7s} {'PY PnL':>8s}")
        print(f"  {'-'*66}")
        
        for r in results:
            print(f"  {r['pair']:<10s} {r['mt5_signals']:>8d} {r['mt5_tp']:>7d} {r['mt5_sl']:>7d} {r['mt5_balance']:>10.2f} {r['py_signals']:>7d} {r['py_wr']:>6.1f}% {r['py_pnl']:>+8.2f}")


if __name__ == "__main__":
    main()
