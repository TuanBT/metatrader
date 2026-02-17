"""
optimize_btc.py — Comprehensive optimization for BTCUSD only.
Find the best config for Bitcoin trading with MST Medio strategy.
"""
import pandas as pd
import numpy as np
import sys, time
from pathlib import Path
from itertools import product
from collections import defaultdict

sys.path.insert(0, "/Users/tuan/GitProject/tradingview/MST Medio/backtest")
from strategy_mst_medio import run_mst_medio

CANDLE_DIR = Path("/Users/tuan/GitProject/metatrader/candle data")
DATE_FROM = pd.Timestamp("2025-01-01")
DATE_TO = pd.Timestamp("2026-02-15")

print("Loading BTCUSDm M5 data...")
df = pd.read_csv(CANDLE_DIR / "BTCUSDm_M5.csv", parse_dates=["datetime"])
df.set_index("datetime", inplace=True)
df.sort_index(inplace=True)
df = df[df.index >= pd.Timestamp("2024-01-01")]
print(f"  Rows: {len(df)}, Range: {df.index.min()} to {df.index.max()}\n")


def test_btc(params: dict) -> dict:
    """Test a config on BTCUSD only, return detailed stats."""
    sigs, _ = run_mst_medio(df, **params)
    filt = [s for s in sigs if DATE_FROM <= s.time <= DATE_TO
            and s.result in ("TP", "SL", "CLOSE_REVERSE")]

    if not filt:
        return {"trades": 0, "pnl": 0, "wr": 0, "dd": 0, "consec": 0,
                "rf": 0, "avg": 0, "monthly": {}}

    pnls = [s.pnl_r for s in filt]
    wins = sum(1 for p in pnls if p > 0)
    wr = wins / len(pnls) * 100
    pnl = sum(pnls)
    avg = pnl / len(pnls)

    # Max drawdown
    equity = np.cumsum(pnls)
    peak = np.maximum.accumulate(equity)
    dd = np.max(peak - equity)

    # Max consecutive losses
    max_consec = 0
    curr = 0
    for p in pnls:
        if p < 0:
            curr += 1
            max_consec = max(max_consec, curr)
        else:
            curr = 0

    # Recovery factor
    rf = pnl / dd if dd > 0 else float("inf")

    # Profit factor
    gross_profit = sum(p for p in pnls if p > 0)
    gross_loss = sum(abs(p) for p in pnls if p < 0)
    pf = gross_profit / gross_loss if gross_loss > 0 else float("inf")

    # Monthly breakdown
    monthly = defaultdict(list)
    for s in filt:
        key = s.time.strftime("%Y-%m")
        monthly[key].append(s.pnl_r)

    months_pos = sum(1 for pls in monthly.values() if sum(pls) > 0)
    months_total = len(monthly)

    # Avg win/loss
    avg_win = np.mean([p for p in pnls if p > 0]) if any(p > 0 for p in pnls) else 0
    avg_loss = np.mean([p for p in pnls if p < 0]) if any(p < 0 for p in pnls) else 0

    # SL distances
    sl_dists = [abs(s.entry - s.sl) for s in filt]

    return {
        "trades": len(pnls), "wins": wins, "pnl": pnl, "wr": wr,
        "avg": avg, "dd": dd, "consec": max_consec, "rf": rf, "pf": pf,
        "months_pos": months_pos, "months_total": months_total,
        "avg_win": avg_win, "avg_loss": avg_loss,
        "sl_mean": np.mean(sl_dists), "sl_max": np.max(sl_dists),
        "monthly": {k: sum(v) for k, v in monthly.items()},
    }


# ============================================================================
# PHASE 1: Wide grid search
# ============================================================================
print("=" * 80)
print("  PHASE 1: Wide Grid Search for BTCUSD")
print("=" * 80)

pivot_lens = [3, 5, 7]
break_mults = [0, 0.25, 0.5]
impulse_mults = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5]
tp_modes = [
    ("confirm", 0),
    ("fixed_rr", 0.5),
    ("fixed_rr", 1.0),
    ("fixed_rr", 1.5),
    ("fixed_rr", 2.0),
]
be_options = [0, 0.5, 1.0]

configs = []
for pl, bm, im in product(pivot_lens, break_mults, impulse_mults):
    for tp_mode, fr in tp_modes:
        for be in be_options:
            params = dict(pivot_len=pl, break_mult=bm, impulse_mult=im,
                          tp_mode=tp_mode, limit_order=True)
            if tp_mode == "fixed_rr":
                params["fixed_rr"] = fr
            if be > 0:
                params["be_at_r"] = be
            name_parts = [f"P{pl}", f"B{bm}", f"I{im}"]
            if tp_mode == "fixed_rr":
                name_parts.append(f"FR{fr}")
            else:
                name_parts.append("Conf")
            if be > 0:
                name_parts.append(f"BE{be}")
            name = "_".join(name_parts)
            configs.append((name, params))

print(f"  Testing {len(configs)} configs...\n")
t0 = time.time()

results = []
for i, (name, params) in enumerate(configs):
    r = test_btc(params)
    r["name"] = name
    r["params"] = params
    results.append(r)
    if (i + 1) % 100 == 0:
        print(f"    [{i+1}/{len(configs)}] ({time.time()-t0:.0f}s)")

print(f"    [{len(configs)}/{len(configs)}] ({time.time()-t0:.0f}s)\n")

# Filter: only profitable configs with trades > 50
profitable = [r for r in results if r["pnl"] > 0 and r["trades"] > 50]
profitable.sort(key=lambda x: x["rf"], reverse=True)

# ============================================================================
# RESULTS
# ============================================================================
print("=" * 80)
print(f"  TOP 30 by Recovery Factor (PnL>0, trades>50)")
print("=" * 80)
print(f"  {'#':>3} {'Config':<35} {'Trades':>6} {'WR%':>5} {'PnL(R)':>8} "
      f"{'MaxDD':>6} {'MCL':>4} {'RF':>6} {'PF':>5} {'M+':>4}")
print(f"  {'-'*3} {'-'*35} {'-'*6} {'-'*5} {'-'*8} {'-'*6} {'-'*4} {'-'*6} "
      f"{'-'*5} {'-'*4}")

for i, r in enumerate(profitable[:30], 1):
    pf_str = f"{r['pf']:.1f}" if r['pf'] < 100 else "∞"
    print(f"  {i:3d} {r['name']:<35} {r['trades']:6d} {r['wr']:4.1f}% "
          f"{r['pnl']:+8.1f} {r['dd']:6.1f} {r['consec']:4d} "
          f"{r['rf']:6.2f} {pf_str:>5} {r['months_pos']:2d}/{r['months_total']}")


# Top 30 by PnL
print()
print("=" * 80)
print(f"  TOP 30 by PnL")
print("=" * 80)
pnl_sorted = sorted([r for r in results if r["trades"] > 50],
                     key=lambda x: x["pnl"], reverse=True)
print(f"  {'#':>3} {'Config':<35} {'Trades':>6} {'WR%':>5} {'PnL(R)':>8} "
      f"{'MaxDD':>6} {'MCL':>4} {'RF':>6} {'PF':>5} {'M+':>4}")
print(f"  {'-'*3} {'-'*35} {'-'*6} {'-'*5} {'-'*8} {'-'*6} {'-'*4} {'-'*6} "
      f"{'-'*5} {'-'*4}")

for i, r in enumerate(pnl_sorted[:30], 1):
    pf_str = f"{r['pf']:.1f}" if r['pf'] < 100 else "∞"
    print(f"  {i:3d} {r['name']:<35} {r['trades']:6d} {r['wr']:4.1f}% "
          f"{r['pnl']:+8.1f} {r['dd']:6.1f} {r['consec']:4d} "
          f"{r['rf']:6.2f} {pf_str:>5} {r['months_pos']:2d}/{r['months_total']}")


# ============================================================================
# PHASE 2: Detailed analysis of Top 10
# ============================================================================
print()
print("=" * 80)
print("  PHASE 2: Detailed Analysis — Top 10 by Recovery Factor")
print("=" * 80)

for i, r in enumerate(profitable[:10], 1):
    print(f"\n  ── #{i} {r['name']} ──")
    print(f"  PnL: {r['pnl']:+.1f}R | Trades: {r['trades']} | WR: {r['wr']:.1f}%")
    print(f"  MaxDD: {r['dd']:.1f}R | MaxConsecLoss: {r['consec']} | "
          f"RecFac: {r['rf']:.2f}")
    print(f"  AvgWin: {r['avg_win']:+.2f}R | AvgLoss: {r['avg_loss']:.2f}R | "
          f"PF: {r['pf']:.2f}")
    print(f"  SL: mean=${r['sl_mean']:.0f}, max=${r['sl_max']:.0f}")
    print(f"  Months: {r['months_pos']}/{r['months_total']} profitable")

    # Monthly breakdown
    if r["monthly"]:
        print(f"  Monthly PnL:")
        for m in sorted(r["monthly"].keys()):
            pnl_m = r["monthly"][m]
            symbol = "✅" if pnl_m > 0 else "❌"
            print(f"    {symbol} {m}: {pnl_m:+.1f}R")

    # Params
    print(f"  EA Settings:")
    p = r["params"]
    print(f"    InpPivotLen = {p['pivot_len']}")
    print(f"    InpBreakMult = {p['break_mult']}")
    print(f"    InpImpulseMult = {p['impulse_mult']}")
    if p["tp_mode"] == "fixed_rr":
        print(f"    InpTPFixedRR = {p['fixed_rr']}")
    else:
        print(f"    InpTPFixedRR = 0  (confirm candle)")
    print(f"    InpBEAtR = {p.get('be_at_r', 0)}")


# ============================================================================
# RECOMMENDATION
# ============================================================================
best = profitable[0]
print()
print("=" * 80)
print(f"  🏆 RECOMMENDED CONFIG FOR BTCUSD")
print("=" * 80)
print(f"  Config: {best['name']}")
print(f"  PnL: {best['pnl']:+.1f}R | Trades: {best['trades']} | WR: {best['wr']:.1f}%")
print(f"  MaxDD: {best['dd']:.1f}R | MaxConsecLoss: {best['consec']} | "
      f"RecFac: {best['rf']:.2f}")
print(f"  Months profitable: {best['months_pos']}/{best['months_total']}")
p = best["params"]
print(f"\n  EA Settings:")
print(f"    InpPivotLen    = {p['pivot_len']}")
print(f"    InpBreakMult   = {p['break_mult']}")
print(f"    InpImpulseMult = {p['impulse_mult']}")
if p["tp_mode"] == "fixed_rr":
    print(f"    InpTPFixedRR   = {p['fixed_rr']}")
else:
    print(f"    InpTPFixedRR   = 0  (confirm candle)")
print(f"    InpBEAtR       = {p.get('be_at_r', 0)}")

print(f"\nTotal runtime: {time.time()-t0:.0f}s")
