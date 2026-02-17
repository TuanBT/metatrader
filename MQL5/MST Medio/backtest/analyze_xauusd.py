"""Quick XAUUSD risk analysis for $500 account with 0.01 lot"""
import pandas as pd
import numpy as np
import sys

sys.path.insert(0, "/Users/tuan/GitProject/tradingview/MST Medio/backtest")
from strategy_mst_medio import run_mst_medio

df = pd.read_csv("/Users/tuan/GitProject/metatrader/candle data/XAUUSDm_M5.csv",
                 parse_dates=["datetime"])
df.set_index("datetime", inplace=True)
df.sort_index(inplace=True)
df = df[df.index >= pd.Timestamp("2024-01-01")]

sigs, _ = run_mst_medio(df, pivot_len=3, break_mult=0.25, impulse_mult=0.75,
                         tp_mode="fixed_rr", fixed_rr=1.0, limit_order=True)

date_from = pd.Timestamp("2025-01-01")
date_to = pd.Timestamp("2026-02-15")
filt = [s for s in sigs if date_from <= s.time <= date_to
        and s.result in ("TP", "SL", "CLOSE_REVERSE")]

sl_dists = [abs(s.entry - s.sl) for s in filt]

print("XAUUSD FR1.0 Analysis:")
print(f"  Total trades: {len(filt)}")
print(f"  SL distance (price):")
print(f"    Mean: {np.mean(sl_dists):.2f}")
print(f"    Median: {np.median(sl_dists):.2f}")
print(f"    Min: {np.min(sl_dists):.2f}")
print(f"    Max: {np.max(sl_dists):.2f}")
print(f"    P90: {np.percentile(sl_dists, 90):.2f}")

# XAUUSD on Exness: 1 standard lot = 100 oz
# 1 point = $0.01 price change
# For 0.01 lot: value per point = 100 * 0.01 * 0.01 = $0.01
# But SL distance is in PRICE (e.g. 2610 - 2600 = 10.00)
# In points: 10.00 / 0.01 = 1000 points
# Dollar risk = sl_dist_price / point_size * tick_value * lots
# For XAUUSD: point_size = 0.01, tick_value = $0.01 per lot
# Risk = sl_dist / 0.01 * 0.01 * 0.01 = sl_dist * 0.01
# Actually: 0.01 lot = 1 oz. Price move of $1 = $0.01 per 0.01 lot? No...
# 0.01 lot = 1 oz. If price moves $10, PnL = 1 oz * $10 = $10
# So risk per trade = sl_dist_price * lot_size_oz = sl_dist * (lots * 100)
# For 0.01 lot: risk = sl_dist * 0.01 * 100 = sl_dist * 1.0

risks = [d * 1.0 for d in sl_dists]  # $1 per $1 price move for 0.01 lot (1 oz)
print()
print("  Risk per trade (lot=0.01 = 1 oz):")
print(f"    Mean: ${np.mean(risks):.2f}")
print(f"    Median: ${np.median(risks):.2f}")
print(f"    Max: ${np.max(risks):.2f}")
print(f"    P90: ${np.percentile(risks, 90):.2f}")
print()
print("  With $500 balance:")
print(f"    Mean risk %: {np.mean(risks)/500*100:.1f}%")
print(f"    Max risk %: {np.max(risks)/500*100:.1f}%")
print(f"    8 consec losses (mean): ${8*np.mean(risks):.0f} = {8*np.mean(risks)/500*100:.0f}%")

# PnL in dollars
pnls_dollar = [s.pnl_r * abs(s.entry - s.sl) * 1.0 for s in filt]
eq = np.cumsum(pnls_dollar)
max_dd_dollar = np.max(np.maximum.accumulate(eq) - eq)
print()
print(f"  Total PnL: ${sum(pnls_dollar):.2f}")
print(f"  Max Drawdown: ${max_dd_dollar:.2f}")

# First 50 trades equity
print()
print("  First 50 trades (cumulative R):")
pnls_r = [s.pnl_r for s in filt[:50]]
cum = np.cumsum(pnls_r)
for i in range(0, 50, 10):
    vals = [f"{cum[j]:+.1f}" for j in range(i, min(i+10, len(cum)))]
    print(f"    [{i+1:2d}-{min(i+10,50):2d}]: {', '.join(vals)}")

# Check: what if account starts and first trades are losses?
print()
print("  Worst starting streak:")
min_equity = 0
min_idx = 0
for i, r in enumerate(pnls_r):
    if cum[i] < min_equity:
        min_equity = cum[i]
        min_idx = i
print(f"    After trade #{min_idx+1}: equity = {min_equity:+.1f}R")
print(f"    In dollars: ${min_equity * np.mean(risks):.2f}")
print(f"    Account would be: ${500 + min_equity * np.mean(risks):.2f}")
