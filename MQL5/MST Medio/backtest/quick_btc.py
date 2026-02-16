"""Quick BTC breakdown analysis."""
import pandas as pd
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, "/Users/tuan/GitProject/tradingview/MST Medio/backtest")
from strategy_mst_medio import run_mst_medio

df = pd.read_csv("/Users/tuan/GitProject/metatrader/candle data/BTCUSDm_M5.csv", parse_dates=["datetime"])
df.set_index("datetime", inplace=True)
df.sort_index(inplace=True)

# Use data from 2024 to have swing history, filter results to 2025+
date_from = pd.Timestamp("2025-01-01")
date_to = pd.Timestamp("2026-02-15")
df = df[df.index >= pd.Timestamp("2024-01-01")]
print(f"Data: {df.index[0]} → {df.index[-1]}, {len(df)} bars")

for mode_name, limit_order in [("Limit Order", True), ("Instant Fill", False)]:
    sigs, _ = run_mst_medio(df, limit_order=limit_order, impulse_mult=1.0)
    filt = [s for s in sigs if date_from <= s.time <= date_to]
    
    c = Counter(s.result for s in filt)
    print(f"\nBTC 2025-2026 ({mode_name}):")
    print(f"  Total signals: {len(filt)}")
    for k, v in c.most_common():
        print(f"  {k}: {v} ({v/len(filt)*100:.1f}%)")
    
    closed = [s for s in filt if s.result in ("TP", "SL", "CLOSE_REVERSE")]
    if closed:
        wins = sum(1 for s in closed if s.pnl_r > 0)
        pnl = sum(s.pnl_r for s in closed)
        tp_count = sum(1 for s in closed if s.result == "TP")
        sl_count = sum(1 for s in closed if s.result == "SL")
        rev_count = sum(1 for s in closed if s.result == "CLOSE_REVERSE")
        print(f"  Closed: {len(closed)}, TP={tp_count}, SL={sl_count}, Rev={rev_count}")
        print(f"  WR: {wins/len(closed)*100:.1f}%, PnL: {pnl:+.2f}R")

# MT5 comparison: 508 signals, 127 TP, 156 SL, WR=44.9%, Bal=-4.41
print(f"\n--- MT5 Reference ---")
print(f"  508 signals, TP=127, SL=156, WR=44.9%, Bal=-4.41 pips")
print(f"\n--- Gap Analysis ---")
print(f"  Python Limit still has ~70% WR vs MT5 ~45%")
print(f"  Main remaining differences:")
print(f"  1. Python uses M5 OHLC → cannot see intra-bar price sequence")
print(f"  2. MT5 uses 'OHLC 1 minute' → more granular TP/SL check")
print(f"  3. SL buffer calc may differ in precision")
print(f"  4. Signal count: Python has MORE signals → swing detection differs")
