"""
backtest_final.py — Final Backtest with Optimal Settings
========================================================
ImpulseMult=1.0 (changed from 1.5), SL Buffer=5%, BreakMult=0.25
Compares: Full TP vs Partial TP, per pair breakdown
"""
import sys
import os

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_THIS_DIR, "..", "..", "..", "..", "tradingview", "MST Medio", "backtest"))

import pandas as pd
from typing import List
from strategy_mst_medio import run_mst_medio, Signal, signals_to_dataframe
from backtest_partial_tp import simulate_partial_tp

DATA_DIR = os.path.join(_THIS_DIR, "..", "..", "..", "candle data")


def load_data(path: str) -> pd.DataFrame:
    df = pd.read_csv(path, parse_dates=["datetime"])
    df.set_index("datetime", inplace=True)
    df.sort_index(inplace=True)
    for cu, cl in [("Open","open"),("High","high"),("Low","low"),("Close","close"),("Volume","volume")]:
        if cu in df.columns and cl in df.columns:
            df[cu] = df[cu].fillna(df[cl])
            df.drop(columns=[cl], inplace=True, errors="ignore")
    df.drop(columns=["symbol"], inplace=True, errors="ignore")
    df.dropna(subset=["Open","High","Low","Close"], inplace=True)
    df = df[df.index.dayofweek < 5]
    return df


def main():
    PAIRS = [
        ("XAUUSD",  "XAUUSDm_M5.csv"),
        ("BTCUSD",  "BTCUSDm_M5.csv"),
        ("ETHUSD",  "ETHUSDm_M5.csv"),
        ("USOIL",   "USOILm_M5.csv"),
        ("EURUSD",  "EURUSDm_M5.csv"),
        ("USDJPY",  "USDJPYm_M5.csv"),
    ]

    # New optimal settings
    IMPULSE_MULT = 1.0  # Changed from 1.5
    BREAK_MULT = 0.25
    SL_BUFFER = 0.05    # 5%
    PIVOT_LEN = 5

    print("=" * 80)
    print("MST Medio v2.0 — FINAL BACKTEST (Optimal Settings)")
    print("=" * 80)
    print(f"  Settings: ImpulseMult={IMPULSE_MULT}, BreakMult={BREAK_MULT}, SL_Buffer={SL_BUFFER*100:.0f}%")
    print(f"  Compare old (1.5) vs new (1.0) ImpulseMult")
    print("=" * 80)

    # Store results for comparison
    old_totals = {"n": 0, "wins": 0, "pnl": 0, "pnl_p": 0, "wins_p": 0}
    new_totals = {"n": 0, "wins": 0, "pnl": 0, "pnl_p": 0, "wins_p": 0}
    pair_results = []

    for symbol, m5_file in PAIRS:
        m5_path = os.path.join(DATA_DIR, m5_file)
        if not os.path.exists(m5_path):
            print(f"\n⚠️ {symbol}: No data")
            continue

        df = load_data(m5_path)
        days = (df.index[-1] - df.index[0]).days

        # OLD settings (ImpulseMult=1.5)
        old_sigs, _ = run_mst_medio(df, pivot_len=PIVOT_LEN, break_mult=BREAK_MULT,
                                      impulse_mult=1.5, min_rr=0, sl_buffer_pct=SL_BUFFER,
                                      tp_mode="confirm")
        old_closed = [s for s in old_sigs if s.result in ("TP", "SL", "CLOSE_REVERSE")]
        old_n = len(old_closed)
        old_wins = sum(1 for s in old_closed if s.pnl_r > 0)
        old_pnl = sum(s.pnl_r for s in old_closed)
        old_wr = old_wins / old_n * 100 if old_n > 0 else 0

        old_trades = simulate_partial_tp(df, old_sigs)
        old_pnl_p = sum((t.part1_pnl_r + t.part2_pnl_r) / 2 for t in old_trades)
        old_wins_p = sum(1 for t in old_trades if (t.part1_pnl_r + t.part2_pnl_r) > 0)
        old_wr_p = old_wins_p / len(old_trades) * 100 if old_trades else 0

        # NEW settings (ImpulseMult=1.0)
        new_sigs, _ = run_mst_medio(df, pivot_len=PIVOT_LEN, break_mult=BREAK_MULT,
                                      impulse_mult=IMPULSE_MULT, min_rr=0, sl_buffer_pct=SL_BUFFER,
                                      tp_mode="confirm")
        new_closed = [s for s in new_sigs if s.result in ("TP", "SL", "CLOSE_REVERSE")]
        new_n = len(new_closed)
        new_wins = sum(1 for s in new_closed if s.pnl_r > 0)
        new_pnl = sum(s.pnl_r for s in new_closed)
        new_wr = new_wins / new_n * 100 if new_n > 0 else 0

        new_trades = simulate_partial_tp(df, new_sigs)
        new_pnl_p = sum((t.part1_pnl_r + t.part2_pnl_r) / 2 for t in new_trades)
        new_wins_p = sum(1 for t in new_trades if (t.part1_pnl_r + t.part2_pnl_r) > 0)
        new_wr_p = new_wins_p / len(new_trades) * 100 if new_trades else 0

        # Accumulate totals
        old_totals["n"] += old_n; old_totals["wins"] += old_wins; old_totals["pnl"] += old_pnl
        old_totals["pnl_p"] += old_pnl_p; old_totals["wins_p"] += old_wins_p
        new_totals["n"] += new_n; new_totals["wins"] += new_wins; new_totals["pnl"] += new_pnl
        new_totals["pnl_p"] += new_pnl_p; new_totals["wins_p"] += new_wins_p

        pair_results.append({
            "symbol": symbol, "days": days,
            "old_n": old_n, "old_wr": old_wr, "old_pnl": old_pnl,
            "old_wr_p": old_wr_p, "old_pnl_p": old_pnl_p,
            "new_n": new_n, "new_wr": new_wr, "new_pnl": new_pnl,
            "new_wr_p": new_wr_p, "new_pnl_p": new_pnl_p,
            "extra_sigs": new_n - old_n,
        })

        # Print per-pair
        print(f"\n{'─' * 80}")
        print(f"  {symbol} | {days} days | {len(df):,} bars")
        print(f"{'─' * 80}")
        print(f"  {'Mode':<35} {'N':>5} {'WR%':>6} {'PnL(R)':>9} {'Avg':>7}")
        print(f"  {'─'*62}")
        print(f"  {'OLD(1.5) Full TP':<35} {old_n:>5} {old_wr:>5.1f}% {old_pnl:>+8.2f} {old_pnl/old_n if old_n else 0:>+6.2f}")
        print(f"  {'OLD(1.5) Partial TP':<35} {old_n:>5} {old_wr_p:>5.1f}% {old_pnl_p:>+8.2f} {old_pnl_p/old_n if old_n else 0:>+6.2f}")
        print(f"  {'NEW(1.0) Full TP':<35} {new_n:>5} {new_wr:>5.1f}% {new_pnl:>+8.2f} {new_pnl/new_n if new_n else 0:>+6.2f}")
        print(f"  {'NEW(1.0) Partial TP':<35} {new_n:>5} {new_wr_p:>5.1f}% {new_pnl_p:>+8.2f} {new_pnl_p/new_n if new_n else 0:>+6.2f}")

        diff_full = new_pnl - old_pnl
        diff_part = new_pnl_p - old_pnl_p
        print(f"\n  Improvement: Full={diff_full:+.2f}R  Partial={diff_part:+.2f}R  +{new_n - old_n} extra signals")

        # Per direction breakdown for new settings
        buy_new = [s for s in new_closed if s.direction == "BUY"]
        sell_new = [s for s in new_closed if s.direction == "SELL"]
        if buy_new:
            b_w = sum(1 for s in buy_new if s.pnl_r > 0)
            b_pnl = sum(s.pnl_r for s in buy_new)
            print(f"  NEW BUY:  {len(buy_new)} trades, WR={b_w/len(buy_new)*100:.1f}%, PnL={b_pnl:+.2f}R")
        if sell_new:
            s_w = sum(1 for s in sell_new if s.pnl_r > 0)
            s_pnl = sum(s.pnl_r for s in sell_new)
            print(f"  NEW SELL: {len(sell_new)} trades, WR={s_w/len(sell_new)*100:.1f}%, PnL={s_pnl:+.2f}R")

    # ══════════════════════════════════════════════════════════════
    # GRAND SUMMARY
    # ══════════════════════════════════════════════════════════════
    print(f"\n\n{'═' * 80}")
    print("GRAND SUMMARY — OLD (ImpulseMult=1.5) vs NEW (ImpulseMult=1.0)")
    print(f"{'═' * 80}")

    # Full TP comparison
    print(f"\n  Full TP:")
    print(f"  {'Symbol':<10} │ {'OLD (1.5)':^23} │ {'NEW (1.0)':^23} │ {'Diff':>7} │ +Sigs")
    print(f"  {'─'*75}")
    for r in pair_results:
        diff = r["new_pnl"] - r["old_pnl"]
        mark = "✅" if diff > 0 else "❌"
        print(f"  {r['symbol']:<10} │ {r['old_n']:>4} {r['old_wr']:>5.1f}% {r['old_pnl']:>+8.2f}R │ "
              f"{r['new_n']:>4} {r['new_wr']:>5.1f}% {r['new_pnl']:>+8.2f}R │ {diff:>+6.2f}{mark} │ +{r['extra_sigs']}")

    o_wr = old_totals["wins"] / old_totals["n"] * 100 if old_totals["n"] > 0 else 0
    n_wr = new_totals["wins"] / new_totals["n"] * 100 if new_totals["n"] > 0 else 0
    diff_f = new_totals["pnl"] - old_totals["pnl"]
    print(f"  {'─'*75}")
    mark = "✅" if diff_f > 0 else "❌"
    print(f"  {'TOTAL':<10} │ {old_totals['n']:>4} {o_wr:>5.1f}% {old_totals['pnl']:>+8.2f}R │ "
          f"{new_totals['n']:>4} {n_wr:>5.1f}% {new_totals['pnl']:>+8.2f}R │ {diff_f:>+6.2f}{mark} │ +{new_totals['n']-old_totals['n']}")

    # Partial TP comparison
    print(f"\n  Partial TP:")
    print(f"  {'Symbol':<10} │ {'OLD (1.5)':^23} │ {'NEW (1.0)':^23} │ {'Diff':>7}")
    print(f"  {'─'*68}")
    for r in pair_results:
        diff = r["new_pnl_p"] - r["old_pnl_p"]
        mark = "✅" if diff > 0 else "❌"
        print(f"  {r['symbol']:<10} │ {r['old_n']:>4} {r['old_wr_p']:>5.1f}% {r['old_pnl_p']:>+8.2f}R │ "
              f"{r['new_n']:>4} {r['new_wr_p']:>5.1f}% {r['new_pnl_p']:>+8.2f}R │ {diff:>+6.2f}{mark}")

    o_wr_p = old_totals["wins_p"] / old_totals["n"] * 100 if old_totals["n"] > 0 else 0
    n_wr_p = new_totals["wins_p"] / new_totals["n"] * 100 if new_totals["n"] > 0 else 0
    diff_p = new_totals["pnl_p"] - old_totals["pnl_p"]
    print(f"  {'─'*68}")
    mark = "✅" if diff_p > 0 else "❌"
    print(f"  {'TOTAL':<10} │ {old_totals['n']:>4} {o_wr_p:>5.1f}% {old_totals['pnl_p']:>+8.2f}R │ "
          f"{new_totals['n']:>4} {n_wr_p:>5.1f}% {new_totals['pnl_p']:>+8.2f}R │ {diff_p:>+6.2f}{mark}")

    # Final verdict
    print(f"\n  {'═' * 65}")
    print(f"  📊 FINAL VERDICT:")
    print(f"  Full TP:    {old_totals['pnl']:+.2f}R → {new_totals['pnl']:+.2f}R ({diff_f:+.2f}R, {diff_f/old_totals['pnl']*100:+.1f}%)")
    print(f"  Partial TP: {old_totals['pnl_p']:+.2f}R → {new_totals['pnl_p']:+.2f}R ({diff_p:+.2f}R, {diff_p/old_totals['pnl_p']*100:+.1f}%)")
    print(f"  Signals:    {old_totals['n']} → {new_totals['n']} (+{new_totals['n']-old_totals['n']} more)")
    print(f"  Win Rate:   {o_wr:.1f}% → {n_wr:.1f}% ({n_wr-o_wr:+.1f}%)")
    print(f"  Avg/Trade:  {old_totals['pnl']/old_totals['n']:+.2f}R → {new_totals['pnl']/new_totals['n']:+.2f}R")
    print(f"  {'═' * 65}")

    # Best recommended config
    print(f"\n  🏆 RECOMMENDED CONFIG:")
    print(f"    ImpulseMult = 1.0 (was 1.5)")
    print(f"    BreakMult   = 0.25 (unchanged)")
    print(f"    SL Buffer   = 5% (unchanged)")
    print(f"    Partial TP  = ON (user choice)")
    print(f"    HTF Filter  = OFF")


if __name__ == "__main__":
    main()
