"""
optimize_v2.py — Deeper optimization combining top findings.
Focus on the two most impactful factors:
1. NoSLBuffer (best single change)
2. Impulse=2.0 (second best)
3. Combinations
"""
import pandas as pd
import sys
from pathlib import Path

sys.path.insert(0, "/Users/tuan/GitProject/tradingview/MST Medio/backtest")
from strategy_mst_medio import run_mst_medio

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


def test_config(name, **kwargs):
    total_closed = 0
    total_wins = 0
    total_pnl = 0.0
    pair_results = {}
    
    for pair, df in data.items():
        sigs, _ = run_mst_medio(df, **kwargs)
        filt = [s for s in sigs if DATE_FROM <= s.time <= DATE_TO]
        closed = [s for s in filt if s.result in ("TP", "SL", "CLOSE_REVERSE")]
        
        if closed:
            wins = sum(1 for s in closed if s.pnl_r > 0)
            pnl = sum(s.pnl_r for s in closed)
            wr = wins / len(closed) * 100
            avg_win = sum(s.pnl_r for s in closed if s.pnl_r > 0) / wins if wins > 0 else 0
        else:
            wins = 0; pnl = 0; wr = 0; avg_win = 0
        
        pair_results[pair] = {"closed": len(closed), "wr": wr, "pnl": pnl, "wins": wins, "avg_win": avg_win}
        total_closed += len(closed)
        total_wins += wins
        total_pnl += pnl
    
    total_wr = total_wins / total_closed * 100 if total_closed > 0 else 0
    return name, total_closed, total_wr, total_pnl, pair_results


configs = [
    # name, kwargs
    ("Current baseline", dict(impulse_mult=1.0, sl_buffer_pct=5.0, tp_mode="confirm", limit_order=True)),
    ("NoSLBuffer", dict(impulse_mult=1.0, sl_buffer_pct=0.0, tp_mode="confirm", limit_order=True)),
    ("Impulse2.0", dict(impulse_mult=2.0, sl_buffer_pct=5.0, tp_mode="confirm", limit_order=True)),
    ("NoSLBuf + Imp2.0", dict(impulse_mult=2.0, sl_buffer_pct=0.0, tp_mode="confirm", limit_order=True)),
    ("NoSLBuf + Imp1.5", dict(impulse_mult=1.5, sl_buffer_pct=0.0, tp_mode="confirm", limit_order=True)),
    ("SLBuf2% + Imp2.0", dict(impulse_mult=2.0, sl_buffer_pct=2.0, tp_mode="confirm", limit_order=True)),
    ("SLBuf3% + Imp2.0", dict(impulse_mult=2.0, sl_buffer_pct=3.0, tp_mode="confirm", limit_order=True)),
    ("NoSLBuf + FixRR1.5", dict(impulse_mult=1.0, sl_buffer_pct=0.0, tp_mode="fixed_rr", fixed_rr=1.5, limit_order=True)),
    ("NoSLBuf + FixRR2.0", dict(impulse_mult=1.0, sl_buffer_pct=0.0, tp_mode="fixed_rr", fixed_rr=2.0, limit_order=True)),
    ("NoSLBuf + Imp2 + FixRR1.5", dict(impulse_mult=2.0, sl_buffer_pct=0.0, tp_mode="fixed_rr", fixed_rr=1.5, limit_order=True)),
    ("NoSLBuf + Imp2 + FixRR2.0", dict(impulse_mult=2.0, sl_buffer_pct=0.0, tp_mode="fixed_rr", fixed_rr=2.0, limit_order=True)),
    # Wider impulse + no buffer combos
    ("NoSLBuf + Imp1.75", dict(impulse_mult=1.75, sl_buffer_pct=0.0, tp_mode="confirm", limit_order=True)),
    ("NoSLBuf + Imp2.5", dict(impulse_mult=2.5, sl_buffer_pct=0.0, tp_mode="confirm", limit_order=True)),
    ("NoSLBuf + Imp3.0", dict(impulse_mult=3.0, sl_buffer_pct=0.0, tp_mode="confirm", limit_order=True)),
    # SL buffer variations with high impulse
    ("SLBuf1% + Imp2.0", dict(impulse_mult=2.0, sl_buffer_pct=1.0, tp_mode="confirm", limit_order=True)),
]

results = []
for name, kwargs in configs:
    print(f"Testing: {name}...", end="", flush=True)
    r = test_config(name, **kwargs)
    results.append(r)
    print(f" → {r[1]} trades, WR={r[2]:.1f}%, PnL={r[3]:+.2f}R")

# Sort by PnL
results.sort(key=lambda x: x[3], reverse=True)

print(f"\n{'='*90}")
print(f"  RESULTS (sorted by Total PnL)")
print(f"{'='*90}")
print(f"  {'#':>3s} {'Config':<30s} {'Trades':>7s} {'WR%':>7s} {'PnL(R)':>10s} {'Avg/T':>8s}")
print(f"  {'-'*65}")

for i, (name, trades, wr, pnl, _) in enumerate(results):
    avg = pnl / trades if trades > 0 else 0
    marker = "🟢" if pnl > 0 else "🔴"
    print(f"  {i+1:>3d} {name:<30s} {trades:>7d} {wr:>6.1f}% {pnl:>+10.2f} {avg:>+8.4f} {marker}")

# Per-pair for top 3
print(f"\n\n  TOP 3 — PER PAIR DETAILS")
print(f"  {'='*80}")

for i, (name, trades, wr, pnl, pairs) in enumerate(results[:3]):
    print(f"\n  #{i+1}: {name} (PnL: {pnl:+.2f}R)")
    print(f"  {'Pair':<10s} {'Closed':>7s} {'WR%':>7s} {'PnL(R)':>10s} {'AvgWin':>8s}")
    for pair in PAIRS:
        if pair in pairs:
            p = pairs[pair]
            print(f"  {pair:<10s} {p['closed']:>7d} {p['wr']:>6.1f}% {p['pnl']:>+10.2f} {p['avg_win']:>+8.3f}")

print(f"\n\n  💡 RECOMMENDATION:")
best = results[0]
print(f"  Best config: {best[0]}")
print(f"  Total PnL: {best[3]:+.2f}R over {best[1]} trades ({best[3]/best[1]:+.4f}R per trade)")
print(f"  WR: {best[2]:.1f}%")
