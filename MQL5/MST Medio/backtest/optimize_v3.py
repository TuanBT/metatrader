"""
optimize_v3.py — Wide search for higher PnL configuration.

Strategy: pre-compute raw signals per unique (pivot_len, break_mult, impulse_mult)
then apply post-filters (sl_buffer, tp_mode, trailing) cheaply.
This avoids re-running the expensive `run_mst_medio()` for every minor param change.
"""
import pandas as pd
import numpy as np
import sys, copy, time
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

# ============================================================================
# STEP 1: Pre-compute raw signals for each unique (pivot_len, break_mult, impulse_mult)
# using sl_buffer_pct=0 and tp_mode="confirm" as base. Other params derived later.
# ============================================================================
print("Pre-computing base signals...")
t0 = time.time()

PIVOT_LENS = [3, 5, 7, 10]
BREAK_MULTS = [0, 0.1, 0.25, 0.5]
IMPULSE_MULTS = [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

# cache: (pivot_len, break_mult, impulse_mult) → { pair: (signals_list, df) }
signal_cache = {}
total_combos = len(PIVOT_LENS) * len(BREAK_MULTS) * len(IMPULSE_MULTS)
done = 0

for pl, bm, imp in product(PIVOT_LENS, BREAK_MULTS, IMPULSE_MULTS):
    key = (pl, bm, imp)
    signal_cache[key] = {}
    for pair, df in data.items():
        sigs, _ = run_mst_medio(
            df, pivot_len=pl, break_mult=bm, impulse_mult=imp,
            sl_buffer_pct=0.0, tp_mode="confirm", limit_order=True,
        )
        filt = [s for s in sigs if DATE_FROM <= s.time <= DATE_TO]
        signal_cache[key][pair] = filt
    done += 1
    if done % 10 == 0 or done == total_combos:
        elapsed = time.time() - t0
        print(f"  [{done}/{total_combos}] combos done  ({elapsed:.0f}s)")

print(f"Pre-computed {total_combos} combos in {time.time()-t0:.0f}s\n")


# ============================================================================
# Helpers
# ============================================================================

def apply_sl_buffer(sig, sl_buf_pct):
    """Adjust SL with buffer percentage. Returns new SL."""
    risk = abs(sig.entry - sig.sl)
    if sig.direction == "BUY":
        return sig.sl - risk * sl_buf_pct
    else:
        return sig.sl + risk * sl_buf_pct


def resimulate_trade(sig, df, new_sl, new_tp, be_at_r=0.0):
    """
    Re-simulate a single trade with new SL/TP and optional breakeven move.
    Returns (result, pnl_r) or None if can't simulate.
    """
    risk = abs(sig.entry - new_sl)
    if risk == 0:
        return None

    highs = df["High"].values
    lows = df["Low"].values
    times = df.index

    # Find the bar where this signal's entry was filled
    # For limit orders, we need the fill bar (entry time)
    try:
        start_idx = times.get_loc(sig.time)
    except:
        return None
    if isinstance(start_idx, slice):
        start_idx = start_idx.start

    # For PENDING/UNFILLED signals, skip
    if sig.result in ("PENDING", "UNFILLED"):
        return None

    current_sl = new_sl
    be_moved = False

    for i in range(start_idx + 1, min(start_idx + 5000, len(df))):
        h = highs[i]
        l = lows[i]

        if sig.direction == "BUY":
            if l <= current_sl:
                pnl_r = (current_sl - sig.entry) / risk
                return ("SL", pnl_r)
            if new_tp > 0 and h >= new_tp:
                pnl_r = (new_tp - sig.entry) / risk
                return ("TP", pnl_r)
            if not be_moved and be_at_r > 0:
                if (h - sig.entry) >= be_at_r * risk:
                    current_sl = sig.entry
                    be_moved = True
        else:  # SELL
            if h >= current_sl:
                pnl_r = (sig.entry - current_sl) / risk
                return ("SL", pnl_r)
            if new_tp > 0 and l <= new_tp:
                pnl_r = (sig.entry - new_tp) / risk
                return ("TP", pnl_r)
            if not be_moved and be_at_r > 0:
                if (sig.entry - l) >= be_at_r * risk:
                    current_sl = sig.entry
                    be_moved = True

    return None  # Still open


def evaluate_config(base_key, sl_buf_pct, tp_mode, fixed_rr, min_rr, be_at_r):
    """Evaluate a full config using cached signals + re-simulation."""
    total_closed = 0
    total_wins = 0
    total_pnl = 0.0
    pair_pnls = {}

    for pair in PAIRS:
        if pair not in signal_cache[base_key]:
            continue
        df = data[pair]
        base_sigs = signal_cache[base_key][pair]

        wins = 0
        pnl = 0.0
        closed = 0

        for sig in base_sigs:
            # Skip non-filled
            if sig.result in ("PENDING", "UNFILLED"):
                continue

            orig_risk = abs(sig.entry - sig.sl)
            if orig_risk == 0:
                continue

            # Apply SL buffer
            new_sl = apply_sl_buffer(sig, sl_buf_pct)
            new_risk = abs(sig.entry - new_sl)
            if new_risk == 0:
                continue

            # Compute TP
            if tp_mode == "confirm":
                new_tp = sig.tp  # Original confirm-based TP
            else:
                if sig.direction == "BUY":
                    new_tp = sig.entry + fixed_rr * new_risk
                else:
                    new_tp = sig.entry - fixed_rr * new_risk

            # Min RR filter
            if min_rr > 0:
                actual_rr = abs(sig.entry - new_tp) / new_risk if new_risk > 0 else 0
                if actual_rr < min_rr:
                    continue

            # Need re-simulation if SL/TP changed or using trailing
            need_resim = (sl_buf_pct > 0 or tp_mode != "confirm" or be_at_r > 0)

            if need_resim:
                result = resimulate_trade(sig, df, new_sl, new_tp, be_at_r=be_at_r)
                if result is None:
                    continue
                res, pr = result
            else:
                # Use original result (base was run with sl_buf=0, confirm TP)
                if sig.result not in ("TP", "SL", "CLOSE_REVERSE"):
                    continue
                res = sig.result
                pr = sig.pnl_r

            closed += 1
            pnl += pr
            if pr > 0:
                wins += 1

        pair_pnls[pair] = pnl
        total_closed += closed
        total_wins += wins
        total_pnl += pnl

    total_wr = total_wins / total_closed * 100 if total_closed > 0 else 0
    avg = total_pnl / total_closed if total_closed > 0 else 0
    return total_closed, total_wr, total_pnl, avg, pair_pnls


# ============================================================================
# PHASE 1: Grid search — all combinations
# ============================================================================
print("=" * 90)
print("  PHASE 1: Full Grid Search")
print("=" * 90)

SL_BUFFERS = [0, 0.01, 0.02, 0.03, 0.05]
TP_MODES = [("confirm", 0), ("fixed_rr", 1.0), ("fixed_rr", 1.5), ("fixed_rr", 2.0), ("fixed_rr", 3.0)]
MIN_RRS = [0]
BE_AT_RS = [0]  # Phase 1 = no trailing

configs = []
for pl in PIVOT_LENS:
    for bm in BREAK_MULTS:
        for imp in IMPULSE_MULTS:
            for sl_buf in SL_BUFFERS:
                for tp_mode, fr in TP_MODES:
                    for min_rr in MIN_RRS:
                        key = (pl, bm, imp)
                        name = f"P{pl}_B{bm}_I{imp}_SL{int(sl_buf*100)}%"
                        if tp_mode == "confirm":
                            name += "_Conf"
                        else:
                            name += f"_FR{fr}"
                        configs.append((name, key, sl_buf, tp_mode, fr, min_rr, 0))

print(f"  Testing {len(configs)} configurations...")
t0 = time.time()

results_phase1 = []
for i, (name, key, sl_buf, tp_mode, fr, min_rr, be_r) in enumerate(configs):
    trades, wr, pnl, avg, pairs = evaluate_config(key, sl_buf, tp_mode, fr, min_rr, be_r)
    results_phase1.append((name, trades, wr, pnl, avg, pairs, key, sl_buf, tp_mode, fr))
    if (i+1) % 200 == 0 or (i+1) == len(configs):
        print(f"    [{i+1}/{len(configs)}] ({time.time()-t0:.0f}s)")

results_phase1.sort(key=lambda x: x[3], reverse=True)

print(f"\n  TOP 30 (out of {len(results_phase1)} configs):")
print(f"  {'#':>3s} {'Config':<40s} {'Trades':>7s} {'WR%':>7s} {'PnL(R)':>10s} {'R/Trade':>8s}")
print(f"  {'-'*78}")
for i, (name, trades, wr, pnl, avg, pairs, *_) in enumerate(results_phase1[:30]):
    mk = "+" if pnl > 0 else "-"
    print(f"  {i+1:>3d} {name:<40s} {trades:>7d} {wr:>6.1f}% {pnl:>+10.2f} {avg:>+8.4f} {mk}")


# ============================================================================
# PHASE 2: Trailing Stop / Breakeven simulation on top 10 base configs
# ============================================================================
print(f"\n\n{'='*90}")
print(f"  PHASE 2: Trailing Stop / Breakeven Simulation")
print(f"{'='*90}")

top10_base = results_phase1[:10]
results_phase2 = []

BE_LEVELS = [0.5, 1.0, 1.5, 2.0]
TP_EXTENSIONS = [0, 2.0, 3.0, 5.0]  # 0 = keep original TP

total_trail = len(top10_base) * len(BE_LEVELS) * len(TP_EXTENSIONS) + len(top10_base)
done_trail = 0

for name, trades, wr, pnl, avg, pairs, key, sl_buf, tp_mode, fr in top10_base:
    # Baseline (no trailing)
    results_phase2.append((f"{name} (base)", trades, wr, pnl, avg, pairs))
    done_trail += 1

    for be_r in BE_LEVELS:
        for tp_ext in TP_EXTENSIONS:
            # For trailing: if tp_ext=0, keep original tp_mode; else use fixed_rr
            if tp_ext == 0:
                t, w, p, a, pr = evaluate_config(key, sl_buf, tp_mode, fr, 0, be_r)
                trail_name = f"{name} +BE@{be_r}R"
            else:
                t, w, p, a, pr = evaluate_config(key, sl_buf, "fixed_rr", tp_ext, 0, be_r)
                trail_name = f"{name} +BE@{be_r}R+TP{tp_ext}R"

            results_phase2.append((trail_name, t, w, p, a, pr))
            done_trail += 1
            if done_trail % 20 == 0 or done_trail == total_trail:
                print(f"    [{done_trail}/{total_trail}] trailing configs done")

results_phase2.sort(key=lambda x: x[3], reverse=True)

print(f"\n  TOP 30 Trailing/BE configs:")
print(f"  {'#':>3s} {'Config':<55s} {'Trades':>7s} {'WR%':>7s} {'PnL(R)':>10s} {'R/Trade':>8s}")
print(f"  {'-'*92}")
for i, (name, trades, wr, pnl, avg, pairs) in enumerate(results_phase2[:30]):
    mk = "+" if pnl > 0 else "-"
    print(f"  {i+1:>3d} {name:<55s} {trades:>7d} {wr:>6.1f}% {pnl:>+10.2f} {avg:>+8.4f} {mk}")


# ============================================================================
# PHASE 3: MinRR filter on top 5
# ============================================================================
print(f"\n\n{'='*90}")
print(f"  PHASE 3: MinRR Filter on Top Configs")
print(f"{'='*90}")

# Extract top 5 unique base configs from phase 2
seen_bases = set()
top5_for_minrr = []
for name, trades, wr, pnl, avg, pairs in results_phase2:
    # Get the base part (remove trailing suffix)
    base = name.split(" +BE")[0].split(" (base)")[0]
    if base not in seen_bases and len(top5_for_minrr) < 5:
        seen_bases.add(base)
        # Find matching entry in phase1
        for r in results_phase1:
            if r[0] == base:
                top5_for_minrr.append(r)
                break

results_phase3 = []
for name, trades, wr, pnl, avg, pairs, key, sl_buf, tp_mode, fr in top5_for_minrr:
    for min_rr in [0, 0.5, 1.0, 1.5, 2.0]:
        t, w, p, a, pr = evaluate_config(key, sl_buf, tp_mode, fr, min_rr, 0)
        rr_name = f"{name} MinRR={min_rr}"
        results_phase3.append((rr_name, t, w, p, a, pr))

results_phase3.sort(key=lambda x: x[3], reverse=True)

print(f"\n  MinRR results:")
print(f"  {'#':>3s} {'Config':<50s} {'Trades':>7s} {'WR%':>7s} {'PnL(R)':>10s} {'R/Trade':>8s}")
print(f"  {'-'*85}")
for i, (name, trades, wr, pnl, avg, pairs) in enumerate(results_phase3[:20]):
    mk = "+" if pnl > 0 else "-"
    print(f"  {i+1:>3d} {name:<50s} {trades:>7d} {wr:>6.1f}% {pnl:>+10.2f} {avg:>+8.4f} {mk}")


# ============================================================================
# FINAL: Best config per-pair breakdown
# ============================================================================
all_results = results_phase1[:1] + results_phase2[:1] + results_phase3[:1]
# Pick the absolute best from all phases
all_results.sort(key=lambda x: x[3], reverse=True)
best = all_results[0]

print(f"\n\n{'='*90}")
print(f"  BEST OVERALL CONFIG: {best[0]}")
print(f"  PnL: {best[3]:+.2f}R | WR: {best[2]:.1f}% | Trades: {best[1]} | Avg: {best[4]:+.4f}R/trade")
print(f"{'='*90}")
print(f"\n  Per-pair breakdown:")
for pair in PAIRS:
    if pair in best[5]:
        p = best[5][pair]
        mk = "+" if p > 0 else "-"
        print(f"    {mk} {pair}: {p:+.2f}R")

print(f"\nTotal runtime: {time.time()-t0:.0f}s")
