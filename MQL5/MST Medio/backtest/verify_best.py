"""
verify_best.py — Verify the best config P3_B0_I1.0 vs current P5_B0.25_I1.75
and check if the high WR/PnL is real or a bug.
"""
import pandas as pd
import numpy as np
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

# ============================================================
# Config 1: BEST = P3 B0 I1.0 SL0% Confirm (limit order)
# ============================================================
print("\n=== BEST: P3 B0 I1.0 SL0% Confirm (limit_order=True) ===")
total_t = total_w = 0; total_p = 0.0
for pair, df in data.items():
    sigs, _ = run_mst_medio(
        df, pivot_len=3, break_mult=0, impulse_mult=1.0,
        sl_buffer_pct=0, tp_mode="confirm", limit_order=True,
    )
    filt = [s for s in sigs if DATE_FROM <= s.time <= DATE_TO]
    closed = [s for s in filt if s.result in ("TP", "SL", "CLOSE_REVERSE")]
    unfilled = [s for s in filt if s.result == "UNFILLED"]
    pending = [s for s in filt if s.result == "PENDING"]
    still_open = [s for s in filt if s.result == "OPEN"]
    
    wins = sum(1 for s in closed if s.pnl_r > 0)
    pnl = sum(s.pnl_r for s in closed)
    
    # Analyze RR and pnl_r distribution
    pnl_rs = [s.pnl_r for s in closed]
    rrs = [abs(s.entry - s.tp) / abs(s.entry - s.sl) if abs(s.entry - s.sl) > 0 else 0 for s in closed]
    
    print(f"  {pair}:")
    print(f"    Signals={len(filt)} Closed={len(closed)} Unfilled={len(unfilled)} Pending={len(pending)} Open={len(still_open)}")
    print(f"    W={wins} L={len(closed)-wins} WR={wins/len(closed)*100 if closed else 0:.1f}%")
    print(f"    PnL={pnl:+.1f}R  Avg PnL/trade={pnl/len(closed) if closed else 0:+.2f}R")
    print(f"    RR range: min={min(rrs):.2f} median={np.median(rrs):.2f} max={max(rrs):.2f}")
    print(f"    PnL_R range: min={min(pnl_rs):.2f} median={np.median(pnl_rs):.2f} max={max(pnl_rs):.2f}")
    total_t += len(closed); total_w += wins; total_p += pnl

print(f"\n  TOTAL: {total_t} trades, WR={total_w/total_t*100 if total_t else 0:.1f}%, PnL={total_p:+.1f}R, Avg={total_p/total_t if total_t else 0:+.3f}R/trade")


# ============================================================
# Config 2: CURRENT = P5 B0.25 I1.75 SL0% Confirm (limit order)
# ============================================================
print("\n\n=== CURRENT: P5 B0.25 I1.75 SL0% Confirm (limit_order=True) ===")
total_t = total_w = 0; total_p = 0.0
for pair, df in data.items():
    sigs, _ = run_mst_medio(
        df, pivot_len=5, break_mult=0.25, impulse_mult=1.75,
        sl_buffer_pct=0, tp_mode="confirm", limit_order=True,
    )
    filt = [s for s in sigs if DATE_FROM <= s.time <= DATE_TO]
    closed = [s for s in filt if s.result in ("TP", "SL", "CLOSE_REVERSE")]
    unfilled = [s for s in filt if s.result == "UNFILLED"]
    
    wins = sum(1 for s in closed if s.pnl_r > 0)
    pnl = sum(s.pnl_r for s in closed)
    
    rrs = [abs(s.entry - s.tp) / abs(s.entry - s.sl) if abs(s.entry - s.sl) > 0 else 0 for s in closed]
    pnl_rs = [s.pnl_r for s in closed]
    
    print(f"  {pair}:")
    print(f"    Signals={len(filt)} Closed={len(closed)} Unfilled={len(unfilled)}")
    print(f"    W={wins} L={len(closed)-wins} WR={wins/len(closed)*100 if closed else 0:.1f}%")
    print(f"    PnL={pnl:+.1f}R  Avg PnL/trade={pnl/len(closed) if closed else 0:+.2f}R")
    if rrs:
        print(f"    RR range: min={min(rrs):.2f} median={np.median(rrs):.2f} max={max(rrs):.2f}")
    total_t += len(closed); total_w += wins; total_p += pnl

print(f"\n  TOTAL: {total_t} trades, WR={total_w/total_t*100 if total_t else 0:.1f}%, PnL={total_p:+.1f}R, Avg={total_p/total_t if total_t else 0:+.3f}R/trade")


# ============================================================
# Key question: Why is P3_B0 so much better?
# The answer: pivot_len=3 creates smaller swings → SL is closer to entry → 
# same TP (confirm candle) gives MUCH higher R:R.
# But: smaller SL = higher chance of getting stopped out in real trading
# (spread, slippage, M1 wicks).
# ============================================================
print("\n\n=== ANALYSIS ===")
print("P3_B0_I1.0: pivot_len=3 → very short swings → SL very close to entry")
print("This creates huge R:R (median likely >2R) because TP is same confirm candle level.")
print("BUT: In real trading, small SL = very sensitive to spread/slippage!")
print()

# Show a few sample trades from P3_B0 to understand the SL distances
print("Sample trades from P3_B0_I1.0 (XAUUSDm):")
sigs, _ = run_mst_medio(
    data["XAUUSDm"], pivot_len=3, break_mult=0, impulse_mult=1.0,
    sl_buffer_pct=0, tp_mode="confirm", limit_order=True,
)
filt = [s for s in sigs if DATE_FROM <= s.time <= DATE_TO and s.result in ("TP", "SL", "CLOSE_REVERSE")]
for s in filt[:10]:
    risk = abs(s.entry - s.sl)
    reward = abs(s.entry - s.tp)
    rr = reward / risk if risk > 0 else 0
    print(f"  {s.time} {s.direction} Entry={s.entry:.2f} SL={s.sl:.2f} TP={s.tp:.2f} Risk={risk:.2f} Reward={reward:.2f} RR={rr:.1f} Result={s.result} PnL={s.pnl_r:+.2f}R")
