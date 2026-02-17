"""
analyze_drawdown.py — Analyze max drawdown for top configs
Focus on safety: max consecutive losses, max drawdown in R, equity curve
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
print(f"Loaded {len(data)} pairs.\n")


def analyze_config(name, params):
    """Analyze a config for drawdown and safety."""
    all_trades = []
    pair_stats = {}

    for pair, df in data.items():
        sigs, _ = run_mst_medio(df, **params)
        filt = [s for s in sigs if DATE_FROM <= s.time <= DATE_TO]
        closed = [s for s in filt if s.result in ("TP", "SL", "CLOSE_REVERSE")]

        pnls = [s.pnl_r for s in closed]
        if not pnls:
            pair_stats[pair] = {"trades": 0, "pnl": 0, "max_dd": 0, "max_consec_loss": 0}
            continue

        # Max drawdown in R
        equity = np.cumsum(pnls)
        peak = np.maximum.accumulate(equity)
        dd = peak - equity
        max_dd = np.max(dd) if len(dd) > 0 else 0

        # Max consecutive losses
        max_consec = 0
        curr_consec = 0
        for p in pnls:
            if p < 0:
                curr_consec += 1
                max_consec = max(max_consec, curr_consec)
            else:
                curr_consec = 0

        wins = sum(1 for p in pnls if p > 0)
        wr = wins / len(pnls) * 100

        pair_stats[pair] = {
            "trades": len(pnls), "pnl": sum(pnls), "wr": wr,
            "max_dd": max_dd, "max_consec_loss": max_consec,
            "avg_win": np.mean([p for p in pnls if p > 0]) if any(p > 0 for p in pnls) else 0,
            "avg_loss": np.mean([p for p in pnls if p < 0]) if any(p < 0 for p in pnls) else 0,
        }
        for s in closed:
            all_trades.append({"time": s.time, "pair": pair, "pnl_r": s.pnl_r})

    # Overall stats
    all_pnls = [t["pnl_r"] for t in sorted(all_trades, key=lambda x: x["time"])]
    if all_pnls:
        equity = np.cumsum(all_pnls)
        peak = np.maximum.accumulate(equity)
        dd = peak - equity
        overall_max_dd = np.max(dd)
        max_consec = 0
        curr_consec = 0
        for p in all_pnls:
            if p < 0:
                curr_consec += 1
                max_consec = max(max_consec, curr_consec)
            else:
                curr_consec = 0
    else:
        overall_max_dd = 0
        max_consec = 0

    total_pnl = sum(all_pnls)
    total_trades = len(all_pnls)
    total_wr = sum(1 for p in all_pnls if p > 0) / total_trades * 100 if total_trades else 0

    print(f"\n{'='*70}")
    print(f"  {name}")
    print(f"  PnL: {total_pnl:+.1f}R | Trades: {total_trades} | WR: {total_wr:.1f}%")
    print(f"  MAX DRAWDOWN: {overall_max_dd:.1f}R | Max Consec Losses: {max_consec}")
    print(f"  Recovery Factor: {total_pnl/overall_max_dd:.2f}" if overall_max_dd > 0 else "")
    print(f"{'='*70}")
    for pair in PAIRS:
        ps = pair_stats.get(pair, {})
        if ps.get("trades", 0) == 0:
            print(f"    {pair:12s}: NO TRADES")
            continue
        symbol = "✅" if ps["pnl"] > 0 else "❌"
        print(f"    {symbol} {pair:12s}: {ps['pnl']:+8.1f}R  ({ps['trades']} trades, "
              f"WR={ps['wr']:.0f}%, DD={ps['max_dd']:.1f}R, "
              f"MaxConsecLoss={ps['max_consec_loss']}, "
              f"AvgWin={ps['avg_win']:+.2f}R, AvgLoss={ps['avg_loss']:.2f}R)")

    return {"pnl": total_pnl, "dd": overall_max_dd, "trades": total_trades,
            "wr": total_wr, "consec": max_consec, "pairs": pair_stats}


# ============================================================================
# CONFIGS TO TEST
# ============================================================================
configs = {
    # Current V5 optimal
    "P3_B0.25_I0.75_FR1.0": dict(pivot_len=3, break_mult=0.25, impulse_mult=0.75,
                                   tp_mode="fixed_rr", fixed_rr=1.0, limit_order=True),
    # FR1.5 (higher RR, lower WR)
    "P3_B0.25_I0.75_FR1.5": dict(pivot_len=3, break_mult=0.25, impulse_mult=0.75,
                                   tp_mode="fixed_rr", fixed_rr=1.5, limit_order=True),
    # FR2.0
    "P3_B0.25_I0.75_FR2.0": dict(pivot_len=3, break_mult=0.25, impulse_mult=0.75,
                                   tp_mode="fixed_rr", fixed_rr=2.0, limit_order=True),
    # Confirm TP (original, no fixed RR)
    "P3_B0.25_I0.75_Confirm": dict(pivot_len=3, break_mult=0.25, impulse_mult=0.75,
                                     tp_mode="confirm", limit_order=True),
    # Higher impulse (fewer trades, more selective)
    "P3_B0.25_I1.0_FR1.0": dict(pivot_len=3, break_mult=0.25, impulse_mult=1.0,
                                  tp_mode="fixed_rr", fixed_rr=1.0, limit_order=True),
    "P3_B0.25_I1.5_FR1.0": dict(pivot_len=3, break_mult=0.25, impulse_mult=1.5,
                                  tp_mode="fixed_rr", fixed_rr=1.0, limit_order=True),
    "P3_B0.25_I1.75_FR1.0": dict(pivot_len=3, break_mult=0.25, impulse_mult=1.75,
                                   tp_mode="fixed_rr", fixed_rr=1.0, limit_order=True),
    # Confirm + BE (protective)
    "P3_B0.25_I0.75_Confirm_BE0.5": dict(pivot_len=3, break_mult=0.25, impulse_mult=0.75,
                                           tp_mode="confirm", be_at_r=0.5, limit_order=True),
    # P5 higher pivot (more selective breakouts)
    "P5_B0.25_I1.0_FR1.0": dict(pivot_len=5, break_mult=0.25, impulse_mult=1.0,
                                  tp_mode="fixed_rr", fixed_rr=1.0, limit_order=True),
    "P5_B0.25_I1.75_FR1.0": dict(pivot_len=5, break_mult=0.25, impulse_mult=1.75,
                                   tp_mode="fixed_rr", fixed_rr=1.0, limit_order=True),
}

print("\n" + "="*70)
print("  DRAWDOWN ANALYSIS — Testing", len(configs), "configs")
print("="*70)

results = {}
for name, params in configs.items():
    r = analyze_config(name, params)
    results[name] = r

# Summary table
print("\n\n" + "="*80)
print("  SUMMARY — Sorted by Recovery Factor (PnL / MaxDD)")
print("="*80)
print(f"  {'#':>3} {'Config':<35} {'PnL(R)':>8} {'Trades':>7} {'WR%':>6} "
      f"{'MaxDD':>7} {'MaxCL':>6} {'RecFac':>7} {'Pairs+':>7}")
print(f"  {'-'*3} {'-'*35} {'-'*8} {'-'*7} {'-'*6} {'-'*7} {'-'*6} {'-'*7} {'-'*7}")

sorted_results = sorted(results.items(), key=lambda x: x[1]["pnl"]/x[1]["dd"] if x[1]["dd"] > 0 else 0, reverse=True)
for i, (name, r) in enumerate(sorted_results, 1):
    rf = r["pnl"] / r["dd"] if r["dd"] > 0 else 0
    pp = sum(1 for p in r["pairs"].values() if p.get("pnl", 0) > 0)
    print(f"  {i:3d} {name:<35} {r['pnl']:+8.1f} {r['trades']:7d} {r['wr']:5.1f}% "
          f"{r['dd']:7.1f} {r['consec']:6d} {rf:7.2f} {pp:5d}/6")

# Best recommendation
best = sorted_results[0]
print(f"\n🏆 BEST RECOVERY FACTOR: {best[0]}")
print(f"   PnL={best[1]['pnl']:+.1f}R, MaxDD={best[1]['dd']:.1f}R, "
      f"RecoveryFactor={best[1]['pnl']/best[1]['dd']:.2f}")
