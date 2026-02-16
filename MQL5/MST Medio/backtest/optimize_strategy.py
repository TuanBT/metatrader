"""
optimize_strategy.py — Find configurations that make MST Medio profitable.

Tests various combinations of:
1. min_rr filter (skip low RR signals)
2. tp_mode: "confirm" vs "fixed_rr" with various values
3. impulse_mult values
4. SL buffer percentages

Uses limit_order=True for realistic simulation.
Tests on 2024-2026 data (2024 for warmup, 2025+ for results).
"""
import pandas as pd
import numpy as np
import sys
import itertools
from pathlib import Path
from collections import Counter

sys.path.insert(0, "/Users/tuan/GitProject/tradingview/MST Medio/backtest")
from strategy_mst_medio import run_mst_medio

CANDLE_DIR = Path("/Users/tuan/GitProject/metatrader/candle data")
PAIRS = ["BTCUSDm", "XAUUSDm", "EURUSDm", "USDJPYm", "ETHUSDm", "USOILm"]

DATE_FROM = pd.Timestamp("2025-01-01")
DATE_TO = pd.Timestamp("2026-02-15")

# Load all data
print("Loading data...")
data = {}
for pair in PAIRS:
    csv = CANDLE_DIR / f"{pair}_M5.csv"
    if csv.exists():
        df = pd.read_csv(csv, parse_dates=["datetime"])
        df.set_index("datetime", inplace=True)
        df.sort_index(inplace=True)
        # Keep from 2024 for warmup
        df = df[df.index >= pd.Timestamp("2024-01-01")]
        data[pair] = df
        print(f"  {pair}: {len(df)} bars ({df.index[0]} → {df.index[-1]})")

print(f"\nLoaded {len(data)} pairs.\n")


def test_config(params: dict) -> dict:
    """Test a configuration across all pairs."""
    results = {}
    total_signals = 0
    total_closed = 0
    total_wins = 0
    total_pnl = 0.0
    total_tp = 0
    total_sl = 0
    
    for pair, df in data.items():
        sigs, _ = run_mst_medio(
            df,
            pivot_len=params.get("pivot_len", 5),
            break_mult=params.get("break_mult", 0.25),
            impulse_mult=params.get("impulse_mult", 1.0),
            min_rr=params.get("min_rr", 0.0),
            sl_buffer_pct=params.get("sl_buffer_pct", 5.0),
            tp_mode=params.get("tp_mode", "confirm"),
            fixed_rr=params.get("fixed_rr", 2.0),
            limit_order=True,
        )
        
        # Filter to test period
        filt = [s for s in sigs if DATE_FROM <= s.time <= DATE_TO]
        closed = [s for s in filt if s.result in ("TP", "SL", "CLOSE_REVERSE")]
        
        if closed:
            wins = sum(1 for s in closed if s.pnl_r > 0)
            pnl = sum(s.pnl_r for s in closed)
            tp = sum(1 for s in closed if s.result == "TP")
            sl = sum(1 for s in closed if s.result == "SL")
            wr = wins / len(closed) * 100
        else:
            wins = pnl = tp = sl = 0
            wr = 0
        
        results[pair] = {
            "signals": len(filt),
            "closed": len(closed),
            "wins": wins,
            "wr": wr,
            "pnl": pnl,
            "tp": tp,
            "sl": sl,
        }
        
        total_signals += len(filt)
        total_closed += len(closed)
        total_wins += wins
        total_pnl += pnl
        total_tp += tp
        total_sl += sl
    
    total_wr = total_wins / total_closed * 100 if total_closed > 0 else 0
    avg_per_trade = total_pnl / total_closed if total_closed > 0 else 0
    
    return {
        "params": params,
        "pairs": results,
        "total_signals": total_signals,
        "total_closed": total_closed,
        "total_wr": total_wr,
        "total_pnl": total_pnl,
        "avg_per_trade": avg_per_trade,
        "total_tp": total_tp,
        "total_sl": total_sl,
    }


# ============================================================================
# OPTIMIZATION RUNS
# ============================================================================
configs = []

# 1. Baseline (current config)
configs.append({"name": "Baseline (current)", "impulse_mult": 1.0, "min_rr": 0.0, "tp_mode": "confirm", "sl_buffer_pct": 5.0})

# 2. Min RR filters
for min_rr in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]:
    configs.append({"name": f"MinRR>={min_rr}", "impulse_mult": 1.0, "min_rr": min_rr, "tp_mode": "confirm", "sl_buffer_pct": 5.0})

# 3. Fixed RR TP modes
for fixed_rr in [1.0, 1.5, 2.0, 2.5, 3.0]:
    configs.append({"name": f"FixedRR={fixed_rr}", "impulse_mult": 1.0, "min_rr": 0.0, "tp_mode": "fixed_rr", "fixed_rr": fixed_rr, "sl_buffer_pct": 5.0})

# 4. Impulse mult variations
for imp in [0.5, 0.75, 1.5, 2.0]:
    configs.append({"name": f"Impulse={imp}", "impulse_mult": imp, "min_rr": 0.0, "tp_mode": "confirm", "sl_buffer_pct": 5.0})

# 5. Combined: MinRR + FixedRR
for min_rr in [0.75, 1.0]:
    for fixed_rr in [1.5, 2.0, 2.5]:
        configs.append({
            "name": f"MinRR{min_rr}_Fixed{fixed_rr}",
            "impulse_mult": 1.0, "min_rr": min_rr,
            "tp_mode": "fixed_rr", "fixed_rr": fixed_rr, "sl_buffer_pct": 5.0,
        })

# 6. No SL buffer
configs.append({"name": "NoSLBuffer", "impulse_mult": 1.0, "min_rr": 0.0, "tp_mode": "confirm", "sl_buffer_pct": 0.0})

# 7. Larger SL buffer
configs.append({"name": "SLBuf10%", "impulse_mult": 1.0, "min_rr": 0.0, "tp_mode": "confirm", "sl_buffer_pct": 10.0})


# Run all configs
print(f"Testing {len(configs)} configurations...")
print(f"{'='*100}")

results_all = []
for i, cfg in enumerate(configs):
    name = cfg.pop("name")
    print(f"\n[{i+1}/{len(configs)}] {name}...", end="", flush=True)
    r = test_config(cfg)
    r["name"] = name
    results_all.append(r)
    print(f" → {r['total_closed']} trades, WR={r['total_wr']:.1f}%, PnL={r['total_pnl']:+.2f}R, Avg={r['avg_per_trade']:+.3f}R")

# Sort by total PnL
results_all.sort(key=lambda x: x["total_pnl"], reverse=True)

print(f"\n\n{'='*100}")
print(f"  OPTIMIZATION RESULTS (sorted by Total PnL)")
print(f"{'='*100}")
print(f"\n  {'#':>3s} {'Config':<25s} {'Trades':>7s} {'WR%':>7s} {'TotalR':>10s} {'Avg/T':>8s} {'TP':>5s} {'SL':>5s}")
print(f"  {'-'*70}")

for i, r in enumerate(results_all):
    marker = "🟢" if r["total_pnl"] > 0 else "🔴"
    print(f"  {i+1:>3d} {r['name']:<25s} {r['total_closed']:>7d} {r['total_wr']:>6.1f}% {r['total_pnl']:>+10.2f} {r['avg_per_trade']:>+8.3f} {r['total_tp']:>5d} {r['total_sl']:>5d} {marker}")

# Top 5 details
print(f"\n\n{'='*100}")
print(f"  TOP 5 CONFIGS — PER PAIR BREAKDOWN")
print(f"{'='*100}")

for i, r in enumerate(results_all[:5]):
    print(f"\n  #{i+1}: {r['name']} (Total PnL: {r['total_pnl']:+.2f}R)")
    print(f"  {'Pair':<10s} {'Closed':>7s} {'WR%':>7s} {'PnL(R)':>10s} {'TP':>5s} {'SL':>5s}")
    print(f"  {'-'*42}")
    for pair in PAIRS:
        if pair in r["pairs"]:
            p = r["pairs"][pair]
            print(f"  {pair:<10s} {p['closed']:>7d} {p['wr']:>6.1f}% {p['pnl']:>+10.2f} {p['tp']:>5d} {p['sl']:>5d}")

# Best profitable config
profitable = [r for r in results_all if r["total_pnl"] > 0]
if profitable:
    best = profitable[0]
    print(f"\n\n{'='*100}")
    print(f"  ✅ BEST PROFITABLE CONFIG: {best['name']}")
    print(f"     Total PnL: {best['total_pnl']:+.2f}R | WR: {best['total_wr']:.1f}% | Trades: {best['total_closed']}")
    print(f"     Avg per trade: {best['avg_per_trade']:+.3f}R")
    print(f"{'='*100}")
else:
    print(f"\n\n⚠️ NO PROFITABLE CONFIGURATION FOUND with limit_order=True")
    print(f"  Best config: {results_all[0]['name']} with PnL={results_all[0]['total_pnl']:+.2f}R")
