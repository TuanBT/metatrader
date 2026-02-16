"""
optimize_v4.py — Focused optimization with CORRECT simulation.
Each config calls run_mst_medio() directly (no resim bug).
Tests targeted parameter ranges with trailing stop via resimulation only on
filled trades (using confirm_time → scan forward to find actual fill bar first).
"""
import pandas as pd
import numpy as np
import sys, time, copy
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


def trailing_resim(signals, df, be_at_r=1.0, extended_tp_r=0):
    """
    Re-simulate closed trades with trailing stop (BE move).
    Finds the actual fill bar by scanning from confirm_time.
    If extended_tp_r > 0, use fixed RR TP instead of original.
    """
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

        # Find fill bar: scan from confirm_time to find where entry was hit
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


def test_config_direct(params: dict, exclude_pairs=None) -> tuple:
    """Test a configuration directly using run_mst_medio (no resim)."""
    total_closed = 0
    total_wins = 0
    total_pnl = 0.0
    pair_pnls = {}

    for pair, df in data.items():
        if exclude_pairs and pair in exclude_pairs:
            continue
        sigs, _ = run_mst_medio(df, **params)
        filt = [s for s in sigs if DATE_FROM <= s.time <= DATE_TO]
        closed = [s for s in filt if s.result in ("TP", "SL", "CLOSE_REVERSE")]

        wins = sum(1 for s in closed if s.pnl_r > 0)
        pnl = sum(s.pnl_r for s in closed)

        pair_pnls[pair] = pnl
        total_closed += len(closed)
        total_wins += wins
        total_pnl += pnl

    total_wr = total_wins / total_closed * 100 if total_closed > 0 else 0
    avg = total_pnl / total_closed if total_closed > 0 else 0
    return total_closed, total_wr, total_pnl, avg, pair_pnls


def test_config_trailing(params: dict, be_at_r: float, ext_tp_r: float = 0, exclude_pairs=None) -> tuple:
    """Test config with trailing stop re-simulation (using correct fill bar)."""
    total_closed = 0
    total_wins = 0
    total_pnl = 0.0
    pair_pnls = {}

    for pair, df in data.items():
        if exclude_pairs and pair in exclude_pairs:
            continue
        sigs, _ = run_mst_medio(df, **params)
        filt = [s for s in sigs if DATE_FROM <= s.time <= DATE_TO]

        # Re-simulate with trailing
        filt = trailing_resim(filt, df, be_at_r=be_at_r, extended_tp_r=ext_tp_r)

        closed = [s for s in filt if s.result in ("TP", "SL", "CLOSE_REVERSE")]
        wins = sum(1 for s in closed if s.pnl_r > 0)
        pnl = sum(s.pnl_r for s in closed)

        pair_pnls[pair] = pnl
        total_closed += len(closed)
        total_wins += wins
        total_pnl += pnl

    total_wr = total_wins / total_closed * 100 if total_closed > 0 else 0
    avg = total_pnl / total_closed if total_closed > 0 else 0
    return total_closed, total_wr, total_pnl, avg, pair_pnls


# ============================================================================
# PHASE 1: Focused grid search (correct, direct run_mst_medio)
# ============================================================================
print("=" * 90)
print("  PHASE 1: Direct Grid Search (no resim bug)")
print("=" * 90)

configs = []

# Focused ranges:
# pivot_len: 3,5,7,10
# break_mult: 0, 0.1, 0.25
# impulse_mult: 1.0, 1.25, 1.5, 1.75, 2.0, 2.5
# sl_buffer: 0%, 3%, 5%
# tp_mode: confirm only (fastest, and TP mode can be applied via trailing later)

# Core grid: pivot_len × break_mult × impulse_mult (SL buffer always 0 — we know it barely matters)
for pl in [3, 5, 7]:
    for bm in [0, 0.25]:
        for imp in [1.0, 1.5, 1.75, 2.0, 2.5]:
            params = dict(
                pivot_len=pl, break_mult=bm, impulse_mult=imp,
                sl_buffer_pct=0, tp_mode="confirm", limit_order=True,
            )
            name = f"P{pl}_B{bm}_I{imp}_SL0%_Conf"
            configs.append((name, params))

# Fixed RR TP with promising params
for fr in [1.0, 1.5, 2.0, 3.0]:
    for pl, bm, imp in [(5, 0.25, 1.75), (3, 0, 1.0), (5, 0, 1.5)]:
        params = dict(
            pivot_len=pl, break_mult=bm, impulse_mult=imp,
            sl_buffer_pct=0, tp_mode="fixed_rr", fixed_rr=fr, limit_order=True,
        )
        name = f"P{pl}_B{bm}_I{imp}_SL0%_FR{fr}"
        configs.append((name, params))

# Exclude BTC: test excluding worst-performing pair
for pl, bm, imp in [(5, 0.25, 1.75), (3, 0, 1.5), (5, 0, 1.75)]:
    params = dict(
        pivot_len=pl, break_mult=bm, impulse_mult=imp,
        sl_buffer_pct=0, tp_mode="confirm", limit_order=True,
    )
    name = f"P{pl}_B{bm}_I{imp}_SL0%_Conf_noBTC"
    configs.append((name, params))

print(f"  Testing {len(configs)} configurations...")
t0 = time.time()

results = []
for i, (name, params) in enumerate(configs):
    exclude = {"BTCUSDm"} if name.endswith("_noBTC") else None
    trades, wr, pnl, avg, pairs = test_config_direct(params, exclude_pairs=exclude)
    results.append((name, trades, wr, pnl, avg, pairs, params))
    if (i + 1) % 10 == 0 or (i + 1) == len(configs):
        elapsed = time.time() - t0
        print(f"    [{i+1}/{len(configs)}] ({elapsed:.0f}s)")

results.sort(key=lambda x: x[3], reverse=True)

print(f"\n  TOP 30 (out of {len(results)} configs):")
print(f"  {'#':>3s} {'Config':<40s} {'Trades':>7s} {'WR%':>7s} {'PnL(R)':>10s} {'R/Trade':>8s}")
print(f"  {'-'*78}")
for i, (name, trades, wr, pnl, avg, pairs, _) in enumerate(results[:30]):
    mk = "+" if pnl > 0 else "-"
    print(f"  {i+1:>3d} {name:<40s} {trades:>7d} {wr:>6.1f}% {pnl:>+10.2f} {avg:>+8.4f} {mk}")

# Show pair breakdown for top 5
print(f"\n  Top 5 per-pair breakdown:")
for i, (name, trades, wr, pnl, avg, pairs, _) in enumerate(results[:5]):
    print(f"\n  #{i+1} {name} (PnL={pnl:+.1f}R)")
    for pair in PAIRS:
        p = pairs.get(pair, 0)
        mk = "+" if p > 0 else "-"
        print(f"    {mk} {pair}: {p:+.2f}R")


# ============================================================================
# PHASE 2: Trailing stop on top 10 base configs
# ============================================================================
print(f"\n\n{'='*90}")
print(f"  PHASE 2: Trailing Stop / Breakeven (correct fill-bar resim)")
print(f"{'='*90}")

# Take top 5 params
top5 = results[:5]
trail_results = []

total_trail = len(top5) * (1 + 4 * 4)  # baseline + 4 be_levels × 4 tp_options
done = 0

for name, trades, wr, pnl, avg, pairs, params in top5:
    exclude = {"BTCUSDm"} if name.endswith("_noBTC") else None
    # Baseline
    trail_results.append((f"{name} (base)", trades, wr, pnl, avg, pairs))
    done += 1

    for be_r in [0.5, 1.0, 1.5, 2.0]:
        # BE with original TP
        t, w, p, a, pr = test_config_trailing(params, be_at_r=be_r, exclude_pairs=exclude)
        trail_results.append((f"{name} +BE@{be_r}R", t, w, p, a, pr))
        done += 1

        # BE with extended TP
        for ext_tp in [2.0, 3.0, 5.0]:
            t, w, p, a, pr = test_config_trailing(params, be_at_r=be_r, ext_tp_r=ext_tp, exclude_pairs=exclude)
            trail_results.append((f"{name} +BE@{be_r}R+TP{ext_tp}R", t, w, p, a, pr))
            done += 1

        if done % 10 == 0:
            print(f"    [{done}/{total_trail}] ({time.time()-t0:.0f}s)")

trail_results.sort(key=lambda x: x[3], reverse=True)

print(f"\n  TOP 30 Trailing configs:")
print(f"  {'#':>3s} {'Config':<55s} {'Trades':>7s} {'WR%':>7s} {'PnL(R)':>10s} {'R/Trade':>8s}")
print(f"  {'-'*92}")
for i, (name, trades, wr, pnl, avg, pairs) in enumerate(trail_results[:30]):
    mk = "+" if pnl > 0 else "-"
    print(f"  {i+1:>3d} {name:<55s} {trades:>7d} {wr:>6.1f}% {pnl:>+10.2f} {avg:>+8.4f} {mk}")


# ============================================================================
# FINAL BEST
# ============================================================================
best = trail_results[0]
print(f"\n\n{'='*90}")
print(f"  BEST OVERALL: {best[0]}")
print(f"  PnL: {best[3]:+.2f}R | WR: {best[2]:.1f}% | Trades: {best[1]} | Avg: {best[4]:+.4f}R/trade")
print(f"{'='*90}")
print(f"\n  Per-pair breakdown:")
for pair in PAIRS:
    p = best[5].get(pair, 0)
    mk = "+" if p > 0 else "-"
    print(f"    {mk} {pair}: {p:+.2f}R")

print(f"\nTotal runtime: {time.time()-t0:.0f}s")
