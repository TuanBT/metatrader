"""
optimize_v5.py — Comprehensive optimization for Expert MST Medio.mq5
Uses run_mst_medio() DIRECTLY (integrated BE + Fixed RR, no trailing_resim bug).

Tests:
  Phase 1: Core params grid (pivot_len, break_mult, impulse_mult)
           TP = confirm candle only. No BE. Establish baseline.
  Phase 2: Top Phase1 configs + BE + Fixed RR TP (integrated, not post-process)
  Phase 3: Multi-pair consistency analysis on final top configs
"""
import pandas as pd
import numpy as np
import sys, time
from pathlib import Path
from itertools import product

sys.path.insert(0, "/Users/tuan/GitProject/tradingview/MST Medio/backtest")
from strategy_mst_medio import run_mst_medio, Signal

CANDLE_DIR = Path("/Users/tuan/GitProject/metatrader/candle data")
PAIRS = ["BTCUSDm", "XAUUSDm", "EURUSDm", "USDJPYm", "ETHUSDm", "USOILm"]
DATE_FROM = pd.Timestamp("2025-01-01")
DATE_TO = pd.Timestamp("2026-02-15")

print("Loading data...")
data = {}
for pair in PAIRS:
    csv = CANDLE_DIR / f"{pair}_M5.csv"
    if csv.exists():
        df = pd.read_csv(csv, parse_dates=["datetime"])
        df.set_index("datetime", inplace=True)
        df.sort_index(inplace=True)
        df = df[df.index >= pd.Timestamp("2024-01-01")]
        data[pair] = df
print(f"Loaded {len(data)} pairs.\n")


def test_config(params: dict, exclude_pairs=None) -> dict:
    """Test a configuration using run_mst_medio directly."""
    total_closed = 0
    total_wins = 0
    total_pnl = 0.0
    pair_results = {}

    for pair, df in data.items():
        if exclude_pairs and pair in exclude_pairs:
            continue
        sigs, _ = run_mst_medio(df, **params)
        filt = [s for s in sigs if DATE_FROM <= s.time <= DATE_TO]
        closed = [s for s in filt if s.result in ("TP", "SL", "CLOSE_REVERSE")]

        wins = sum(1 for s in closed if s.pnl_r > 0)
        pnl = sum(s.pnl_r for s in closed)
        wr = wins / len(closed) * 100 if closed else 0

        pair_results[pair] = {
            "trades": len(closed), "wins": wins, "wr": wr, "pnl": pnl,
            "avg": pnl / len(closed) if closed else 0,
        }
        total_closed += len(closed)
        total_wins += wins
        total_pnl += pnl

    total_wr = total_wins / total_closed * 100 if total_closed > 0 else 0
    avg = total_pnl / total_closed if total_closed > 0 else 0

    # Profit factor
    gross_profit = sum(max(0, pr["pnl"]) for pr in pair_results.values())
    gross_loss = sum(abs(min(0, pr["pnl"])) for pr in pair_results.values())
    pf = gross_profit / gross_loss if gross_loss > 0 else float("inf")

    # Pairs profitable
    pairs_positive = sum(1 for pr in pair_results.values() if pr["pnl"] > 0)

    return {
        "trades": total_closed, "wr": total_wr, "pnl": total_pnl,
        "avg": avg, "pf": pf, "pairs_pos": pairs_positive,
        "pairs": pair_results,
    }


# ============================================================================
# PHASE 1: Core parameter grid — Confirm TP, no BE
# ============================================================================
print("=" * 95)
print("  PHASE 1: Core Parameter Grid (Confirm TP, no BE, limit_order=True)")
print("=" * 95)

p1_configs = []
for pl in [3, 5, 7]:
    for bm in [0, 0.25]:
        for imp in [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]:
            params = dict(
                pivot_len=pl, break_mult=bm, impulse_mult=imp,
                sl_buffer_pct=0, tp_mode="confirm", limit_order=True,
            )
            name = f"P{pl}_B{bm}_I{imp}"
            p1_configs.append((name, params))

print(f"  Testing {len(p1_configs)} configs...")
t0 = time.time()

p1_results = []
for i, (name, params) in enumerate(p1_configs):
    res = test_config(params)
    p1_results.append((name, res, params))
    if (i + 1) % 20 == 0 or (i + 1) == len(p1_configs):
        print(f"    [{i+1}/{len(p1_configs)}] ({time.time()-t0:.0f}s)")

p1_results.sort(key=lambda x: x[1]["pnl"], reverse=True)

print(f"\n  TOP 30 Phase 1 (by PnL):")
print(f"  {'#':>3s} {'Config':<25s} {'Trades':>7s} {'WR%':>7s} {'PnL(R)':>10s} {'R/Trade':>8s} {'PF':>6s} {'Pairs+':>6s}")
print(f"  {'-'*76}")
for i, (name, res, _) in enumerate(p1_results[:30]):
    pf_str = f"{res['pf']:.2f}" if res['pf'] < 100 else "∞"
    print(f"  {i+1:>3d} {name:<25s} {res['trades']:>7d} {res['wr']:>6.1f}% {res['pnl']:>+10.2f} {res['avg']:>+8.4f} {pf_str:>6s} {res['pairs_pos']:>3d}/6")

# Show pair breakdown for top 5
print(f"\n  Top 5 per-pair breakdown:")
for i, (name, res, _) in enumerate(p1_results[:5]):
    print(f"\n  #{i+1} {name} (PnL={res['pnl']:+.1f}R, WR={res['wr']:.1f}%)")
    for pair in PAIRS:
        pr = res["pairs"].get(pair, {"pnl": 0, "trades": 0, "wr": 0})
        mk = "✅" if pr["pnl"] > 0 else "❌"
        print(f"    {mk} {pair}: {pr['pnl']:+.2f}R ({pr['trades']} trades, WR={pr['wr']:.0f}%)")


# ============================================================================
# PHASE 2: Top Phase1 + BE + Fixed RR TP (integrated, no resim)
# ============================================================================
print(f"\n\n{'='*95}")
print(f"  PHASE 2: Top configs + BE + Fixed RR TP (INTEGRATED, no trailing_resim)")
print(f"{'='*95}")

# Take top 5 base configs
top_base = p1_results[:5]
p2_configs = []

for name, res, base_params in top_base:
    # Test Fixed RR TP (without BE)
    for fr in [1.0, 1.5, 2.0, 3.0]:
        params = {**base_params, "tp_mode": "fixed_rr", "fixed_rr": fr}
        p2_configs.append((f"{name}_FR{fr}", params))

    # Test BE only (confirm TP)
    for be in [0.5, 1.0]:
        params = {**base_params, "be_at_r": be}
        p2_configs.append((f"{name}_BE{be}", params))

    # Test Fixed RR + BE combos
    for fr in [1.5, 2.0, 3.0]:
        for be in [0.5, 1.0]:
            params = {**base_params, "tp_mode": "fixed_rr", "fixed_rr": fr, "be_at_r": be}
            p2_configs.append((f"{name}_FR{fr}_BE{be}", params))

print(f"  Testing {len(p2_configs)} configs...")
t1 = time.time()

p2_results = []
# Include Phase 1 baselines
for name, res, params in top_base:
    p2_results.append((f"{name} (base)", res, params))

for i, (name, params) in enumerate(p2_configs):
    res = test_config(params)
    p2_results.append((name, res, params))
    if (i + 1) % 20 == 0 or (i + 1) == len(p2_configs):
        print(f"    [{i+1}/{len(p2_configs)}] ({time.time()-t1:.0f}s)")

p2_results.sort(key=lambda x: x[1]["pnl"], reverse=True)

print(f"\n  TOP 40 Phase 2 (by PnL):")
print(f"  {'#':>3s} {'Config':<40s} {'Trades':>7s} {'WR%':>7s} {'PnL(R)':>10s} {'R/Trade':>8s} {'PF':>6s} {'Pairs+':>6s}")
print(f"  {'-'*90}")
for i, (name, res, _) in enumerate(p2_results[:40]):
    pf_str = f"{res['pf']:.2f}" if res['pf'] < 100 else "∞"
    print(f"  {i+1:>3d} {name:<40s} {res['trades']:>7d} {res['wr']:>6.1f}% {res['pnl']:>+10.2f} {res['avg']:>+8.4f} {pf_str:>6s} {res['pairs_pos']:>3d}/6")


# ============================================================================
# PHASE 3: Final analysis — Top 10 configs (pair consistency + stats)
# ============================================================================
print(f"\n\n{'='*95}")
print(f"  PHASE 3: Final Analysis — Top 10 configs")
print(f"{'='*95}")

final_top = p2_results[:10]
for rank, (name, res, params) in enumerate(final_top):
    print(f"\n  ── #{rank+1} {name} ──")
    print(f"  PnL: {res['pnl']:+.2f}R | Trades: {res['trades']} | WR: {res['wr']:.1f}% | Avg: {res['avg']:+.4f}R | PF: {res['pf']:.2f}")
    print(f"  Params: {params}")
    print(f"  Per-pair:")
    for pair in PAIRS:
        pr = res["pairs"].get(pair, {"pnl": 0, "trades": 0, "wr": 0, "avg": 0})
        mk = "✅" if pr["pnl"] > 0 else "❌"
        print(f"    {mk} {pair:<10s}: {pr['pnl']:>+8.2f}R  ({pr['trades']:>4d} trades, WR={pr['wr']:>5.1f}%, Avg={pr['avg']:>+.4f})")


# ============================================================================
# RECOMMENDED CONFIG FOR EA
# ============================================================================
best_name, best_res, best_params = p2_results[0]
print(f"\n\n{'='*95}")
print(f"  🏆 RECOMMENDED CONFIG FOR Expert MST Medio.mq5")
print(f"{'='*95}")
print(f"  Config: {best_name}")
print(f"  PnL: {best_res['pnl']:+.2f}R | Trades: {best_res['trades']} | WR: {best_res['wr']:.1f}%")
print(f"  R/Trade: {best_res['avg']:+.4f} | PF: {best_res['pf']:.2f}")
print(f"  Pairs profitable: {best_res['pairs_pos']}/6")
print(f"\n  EA Settings:")
print(f"    InpPreset = PRESET_CUSTOM")
print(f"    InpPivotLen = {best_params.get('pivot_len', 3)}")
print(f"    InpBreakMult = {best_params.get('break_mult', 0)}")
print(f"    InpImpulseMult = {best_params.get('impulse_mult', 1.0)}")
tp_mode = best_params.get("tp_mode", "confirm")
fr = best_params.get("fixed_rr", 0)
if tp_mode == "fixed_rr" and fr > 0:
    print(f"    InpTPFixedRR = {fr}")
else:
    print(f"    InpTPFixedRR = 0  (use confirm candle TP)")
be = best_params.get("be_at_r", 0)
print(f"    InpBEAtR = {be}")
print(f"    InpSLBufferPct = 0")
print(f"\nTotal runtime: {time.time()-t0:.0f}s")
