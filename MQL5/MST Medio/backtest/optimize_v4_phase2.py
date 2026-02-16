"""
optimize_v4_phase2.py — Phase 2 ONLY: Trailing Stop / Breakeven on top 5 configs.
Phase 1 results are hardcoded (already verified correct).
"""
import pandas as pd
import numpy as np
import sys, time, copy
from pathlib import Path

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


def trailing_resim(signals, df, be_at_r=1.0, extended_tp_r=0):
    """Re-simulate with trailing stop. Finds actual fill bar correctly."""
    highs = df["High"].values
    lows = df["Low"].values
    times = df.index
    n = len(df)
    new_results = []

    for sig in signals:
        if sig.result not in ("TP", "SL", "CLOSE_REVERSE"):
            new_results.append(sig)
            continue

        risk = abs(sig.entry - sig.sl)
        if risk == 0:
            new_results.append(sig)
            continue

        try:
            confirm_idx = times.get_loc(sig.confirm_time)
        except:
            new_results.append(sig)
            continue
        if isinstance(confirm_idx, slice):
            confirm_idx = confirm_idx.start

        fill_idx = None
        for i in range(confirm_idx, min(confirm_idx + 5000, n)):
            if sig.direction == "BUY":
                if lows[i] <= sig.entry:
                    fill_idx = i
                    break
            else:
                if highs[i] >= sig.entry:
                    fill_idx = i
                    break

        if fill_idx is None:
            new_results.append(sig)
            continue

        # Determine TP
        if extended_tp_r > 0:
            if sig.direction == "BUY":
                tp = sig.entry + extended_tp_r * risk
            else:
                tp = sig.entry - extended_tp_r * risk
        else:
            tp = sig.tp

        # Re-simulate from fill bar
        current_sl = sig.sl
        be_moved = False
        result = None
        pnl_r = 0.0

        for i in range(fill_idx + 1, min(fill_idx + 5000, n)):
            h = highs[i]
            l = lows[i]

            if sig.direction == "BUY":
                if l <= current_sl:
                    pnl_r = (current_sl - sig.entry) / risk
                    result = "SL"
                    break
                if tp > 0 and h >= tp:
                    pnl_r = (tp - sig.entry) / risk
                    result = "TP"
                    break
                if not be_moved and be_at_r > 0:
                    if (h - sig.entry) >= be_at_r * risk:
                        current_sl = sig.entry
                        be_moved = True
            else:
                if h >= current_sl:
                    pnl_r = (sig.entry - current_sl) / risk
                    result = "SL"
                    break
                if tp > 0 and l <= tp:
                    pnl_r = (sig.entry - tp) / risk
                    result = "TP"
                    break
                if not be_moved and be_at_r > 0:
                    if (sig.entry - l) >= be_at_r * risk:
                        current_sl = sig.entry
                        be_moved = True

        new_sig = copy.copy(sig)
        if result:
            new_sig.result = result
            new_sig.pnl_r = pnl_r
        new_results.append(new_sig)

    return new_results


def test_trailing(params, be_at_r, ext_tp_r=0, exclude_pairs=None):
    total_closed = 0
    total_wins = 0
    total_pnl = 0.0
    pair_pnls = {}

    for pair, df in data.items():
        if exclude_pairs and pair in exclude_pairs:
            continue
        sigs, _ = run_mst_medio(df, **params)
        filt = [s for s in sigs if DATE_FROM <= s.time <= DATE_TO]
        filt = trailing_resim(filt, df, be_at_r=be_at_r, extended_tp_r=ext_tp_r)
        closed = [s for s in filt if s.result in ("TP", "SL", "CLOSE_REVERSE")]
        wins = sum(1 for s in closed if s.pnl_r > 0)
        pnl = sum(s.pnl_r for s in closed)
        pair_pnls[pair] = pnl
        total_closed += len(closed)
        total_wins += wins
        total_pnl += pnl

    wr = total_wins / total_closed * 100 if total_closed > 0 else 0
    avg = total_pnl / total_closed if total_closed > 0 else 0
    return total_closed, wr, total_pnl, avg, pair_pnls


# ============================================================================
# Phase 1 TOP 5 (hardcoded from verified results)
# ============================================================================
top5 = [
    ("P3_B0_I1.0_SL0%_FR1.0",
     dict(pivot_len=3, break_mult=0, impulse_mult=1.0, sl_buffer_pct=0,
          tp_mode="fixed_rr", fixed_rr=1.0, limit_order=True),
     175.26, None),
    ("P3_B0.25_I1.5_SL0%_Conf",
     dict(pivot_len=3, break_mult=0.25, impulse_mult=1.5, sl_buffer_pct=0,
          tp_mode="confirm", limit_order=True),
     163.11, None),
    ("P3_B0_I1.5_SL0%_Conf_noBTC",
     dict(pivot_len=3, break_mult=0, impulse_mult=1.5, sl_buffer_pct=0,
          tp_mode="confirm", limit_order=True),
     130.98, {"BTCUSDm"}),
    ("P3_B0.25_I1.0_SL0%_Conf",
     dict(pivot_len=3, break_mult=0.25, impulse_mult=1.0, sl_buffer_pct=0,
          tp_mode="confirm", limit_order=True),
     129.13, None),
    ("P5_B0.25_I1.75_SL0%_Conf_noBTC",
     dict(pivot_len=5, break_mult=0.25, impulse_mult=1.75, sl_buffer_pct=0,
          tp_mode="confirm", limit_order=True),
     119.01, {"BTCUSDm"}),
]

# ============================================================================
# PHASE 2: Trailing Stop / Breakeven
# ============================================================================
print("=" * 90)
print("  PHASE 2: Trailing Stop / Breakeven on Top 5")
print("=" * 90)

trail_results = []
t0 = time.time()

be_levels = [0.5, 1.0, 1.5, 2.0]
ext_tps = [0, 2.0, 3.0, 5.0]

total = len(top5) * len(be_levels) * len(ext_tps)
done = 0

for name, params, base_pnl, exclude in top5:
    # Add baseline
    trail_results.append((f"{name} (base)", 0, 0, base_pnl, 0, {}))

    for be_r in be_levels:
        for ext_tp in ext_tps:
            t, w, p, a, pr = test_trailing(params, be_at_r=be_r, ext_tp_r=ext_tp, exclude_pairs=exclude)
            tp_label = f"+TP{ext_tp}R" if ext_tp > 0 else ""
            label = f"{name} +BE@{be_r}R{tp_label}"
            trail_results.append((label, t, w, p, a, pr))
            done += 1
            if done % 5 == 0:
                elapsed = time.time() - t0
                print(f"    [{done}/{total}] ({elapsed:.0f}s)")

trail_results.sort(key=lambda x: x[3], reverse=True)

print(f"\n  TOP 30 Trailing configs:")
print(f"  {'#':>3s} {'Config':<60s} {'Trades':>7s} {'WR%':>7s} {'PnL(R)':>10s} {'R/Trade':>8s}")
print(f"  {'-'*98}")
for i, (name, trades, wr, pnl, avg, pairs) in enumerate(trail_results[:30]):
    mk = "+" if pnl > 0 else "-"
    if "(base)" in name:
        print(f"  {i+1:>3d} {name:<60s} {'--':>7s} {'--':>7s} {pnl:>+10.2f} {'--':>8s} {mk}")
    else:
        print(f"  {i+1:>3d} {name:<60s} {trades:>7d} {wr:>6.1f}% {pnl:>+10.2f} {avg:>+8.4f} {mk}")

# Show pair breakdown for top 5 actual (non-base) configs
print(f"\n  Top 5 trailing per-pair breakdown:")
count = 0
for name, trades, wr, pnl, avg, pairs in trail_results:
    if "(base)" in name:
        continue
    count += 1
    if count > 5:
        break
    print(f"\n  #{count} {name} (PnL={pnl:+.1f}R)")
    for pair in PAIRS:
        p = pairs.get(pair, 0)
        mk = "+" if p > 0 else "-"
        print(f"    {mk} {pair}: {p:+.2f}R")

# FINAL BEST
best = trail_results[0]
print(f"\n\n{'='*90}")
print(f"  BEST OVERALL: {best[0]}")
print(f"  PnL: {best[3]:+.2f}R | WR: {best[2]:.1f}% | Trades: {best[1]} | Avg: {best[4]:+.4f}R/trade")
print(f"{'='*90}")

print(f"\nTotal Phase 2 runtime: {time.time()-t0:.0f}s")
