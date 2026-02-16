"""
backtest_htf_1year.py — 1-Year Backtest: HTF Trend Filter (H1 EMA50)
=====================================================================
Uses real H1 data from MT5 (not resampled from M5).
Compares 4 modes across 6 pairs:
  1. No Filter + Full TP
  2. No Filter + Partial TP
  3. HTF Filter + Full TP
  4. HTF Filter + Partial TP
"""
import sys
import os

# Add tradingview backtest module to path
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_TV_BACKTEST = os.path.join(_THIS_DIR, "..", "..", "..", "..", "tradingview", "MST Medio", "backtest")
sys.path.insert(0, _TV_BACKTEST)

import pandas as pd
import numpy as np
from typing import List
from strategy_mst_medio import run_mst_medio, Signal
from backtest_partial_tp import simulate_partial_tp

DATA_DIR = os.path.join(_THIS_DIR, "..", "..", "..", "candle data")

# HTF Filter settings
HTF_EMA_LEN = 50


def load_data(path: str) -> pd.DataFrame:
    """Load CSV from MT5 export."""
    df = pd.read_csv(path, parse_dates=["datetime"])
    df.set_index("datetime", inplace=True)
    df.sort_index(inplace=True)
    # Standardize column names
    for cu, cl in [("Open","open"),("High","high"),("Low","low"),("Close","close"),("Volume","volume")]:
        if cu in df.columns and cl in df.columns:
            df[cu] = df[cu].fillna(df[cl])
            df.drop(columns=[cl], inplace=True, errors="ignore")
    df.drop(columns=["symbol"], inplace=True, errors="ignore")
    df.dropna(subset=["Open","High","Low","Close"], inplace=True)
    # Filter weekdays only
    df = df[df.index.dayofweek < 5]
    return df


def calc_h1_ema(df_h1: pd.DataFrame, ema_len: int = 50) -> pd.Series:
    """Calculate EMA on real H1 data."""
    ema = df_h1["Close"].ewm(span=ema_len, adjust=False).mean()
    return ema


def apply_htf_filter(signals: List[Signal], df_m5: pd.DataFrame,
                      ema_h1: pd.Series) -> tuple[List[Signal], dict]:
    """
    Filter signals using HTF EMA trend.
    BUY only when close > EMA(H1), SELL only when close < EMA(H1).
    Returns (filtered_signals, stats_dict).
    """
    filtered = []
    skipped_buy = 0
    skipped_sell = 0
    skipped_buy_results = {"TP": 0, "SL": 0, "CLOSE_REVERSE": 0, "OPEN": 0}
    skipped_sell_results = {"TP": 0, "SL": 0, "CLOSE_REVERSE": 0, "OPEN": 0}
    skipped_pnl = 0.0

    for sig in signals:
        # Get the most recent completed H1 bar EMA value
        h1_time = sig.confirm_time.floor("1h") - pd.Timedelta(hours=1)
        valid_ema = ema_h1[ema_h1.index <= h1_time]
        if valid_ema.empty:
            filtered.append(sig)
            continue

        ema_val = valid_ema.iloc[-1]

        # Get M5 close at confirm time
        if sig.confirm_time in df_m5.index:
            confirm_close = df_m5.loc[sig.confirm_time, "Close"]
            if isinstance(confirm_close, pd.Series):
                confirm_close = confirm_close.iloc[0]
        else:
            confirm_close = sig.entry

        if sig.direction == "BUY" and confirm_close < ema_val:
            skipped_buy += 1
            skipped_buy_results[sig.result] = skipped_buy_results.get(sig.result, 0) + 1
            if sig.result in ("TP", "SL", "CLOSE_REVERSE"):
                skipped_pnl += sig.pnl_r
            continue

        if sig.direction == "SELL" and confirm_close > ema_val:
            skipped_sell += 1
            skipped_sell_results[sig.result] = skipped_sell_results.get(sig.result, 0) + 1
            if sig.result in ("TP", "SL", "CLOSE_REVERSE"):
                skipped_pnl += sig.pnl_r
            continue

        filtered.append(sig)

    stats = {
        "skipped_buy": skipped_buy,
        "skipped_sell": skipped_sell,
        "skipped_buy_results": skipped_buy_results,
        "skipped_sell_results": skipped_sell_results,
        "skipped_pnl": skipped_pnl,
    }
    return filtered, stats


def calc_stats(signals: List[Signal]):
    """Calculate basic stats."""
    closed = [s for s in signals if s.result in ("TP", "SL", "CLOSE_REVERSE")]
    n = len(closed)
    if n == 0:
        return 0, 0, 0.0, 0.0
    wins = sum(1 for s in closed if s.pnl_r > 0)
    wr = wins / n * 100
    total_r = sum(s.pnl_r for s in closed)
    return n, wins, wr, total_r


def calc_partial_stats(trades):
    """Calculate partial TP stats."""
    n = len(trades)
    if n == 0:
        return 0, 0, 0.0, 0.0
    pnl = sum((t.part1_pnl_r + t.part2_pnl_r) / 2 for t in trades)
    wins = sum(1 for t in trades if (t.part1_pnl_r + t.part2_pnl_r) > 0)
    wr = wins / n * 100
    return n, wins, wr, pnl


def main():
    PAIRS = [
        ("XAUUSD",  "XAUUSDm_M5.csv",  "XAUUSDm_H1.csv"),
        ("BTCUSD",  "BTCUSDm_M5.csv",  "BTCUSDm_H1.csv"),
        ("ETHUSD",  "ETHUSDm_M5.csv",  "ETHUSDm_H1.csv"),
        ("USOIL",   "USOILm_M5.csv",   "USOILm_H1.csv"),
        ("EURUSD",  "EURUSDm_M5.csv",  "EURUSDm_H1.csv"),
        ("USDJPY",  "USDJPYm_M5.csv",  "USDJPYm_H1.csv"),
    ]

    print("=" * 80)
    print("MST Medio v2.0 — 1-YEAR HTF Trend Filter Backtest")
    print(f"Filter: EMA{HTF_EMA_LEN} on H1 (real H1 data from MT5)")
    print("BUY only when Close > EMA, SELL only when Close < EMA")
    print("=" * 80)

    all_results = []

    for symbol, m5_file, h1_file in PAIRS:
        m5_path = os.path.join(DATA_DIR, m5_file)
        h1_path = os.path.join(DATA_DIR, h1_file)

        if not os.path.exists(m5_path):
            print(f"\n⚠️ {symbol}: No M5 data ({m5_file})")
            continue
        if not os.path.exists(h1_path):
            print(f"\n⚠️ {symbol}: No H1 data ({h1_file})")
            continue

        df_m5 = load_data(m5_path)
        df_h1 = load_data(h1_path)
        ema_h1 = calc_h1_ema(df_h1, HTF_EMA_LEN)

        date_range = f"{df_m5.index[0].strftime('%Y-%m-%d')} → {df_m5.index[-1].strftime('%Y-%m-%d')}"
        days = (df_m5.index[-1] - df_m5.index[0]).days

        print(f"\n{'─' * 80}")
        print(f"  {symbol} | {len(df_m5):,} M5 bars | {len(df_h1):,} H1 bars | {date_range} ({days} days)")
        print(f"{'─' * 80}")

        # Generate signals (no filter)
        signals_all, _ = run_mst_medio(df_m5, pivot_len=5, break_mult=0.25, impulse_mult=1.5,
                                         min_rr=0, tp_mode="confirm", debug=False)
        if not signals_all:
            print(f"  No signals")
            continue

        # Apply HTF filter
        signals_htf, filt_stats = apply_htf_filter(signals_all, df_m5, ema_h1)

        # No Filter stats
        n_all, w_all, wr_all, pnl_all = calc_stats(signals_all)
        trades_all = simulate_partial_tp(df_m5, signals_all)
        n_p_all, w_p_all, wr_p_all, pnl_p_all = calc_partial_stats(trades_all)

        # HTF Filter stats
        n_htf, w_htf, wr_htf, pnl_htf = calc_stats(signals_htf)
        trades_htf = simulate_partial_tp(df_m5, signals_htf)
        n_p_htf, w_p_htf, wr_p_htf, pnl_p_htf = calc_partial_stats(trades_htf)

        # Per direction breakdown
        buy_all = [s for s in signals_all if s.direction == "BUY"]
        sell_all = [s for s in signals_all if s.direction == "SELL"]
        buy_htf = [s for s in signals_htf if s.direction == "BUY"]
        sell_htf = [s for s in signals_htf if s.direction == "SELL"]

        # Show comparison
        print(f"\n  {'Mode':<30} {'N':>5} {'WR%':>7} {'PnL(R)':>10} {'Avg(R)':>8}")
        print(f"  {'─'*62}")
        avg_all = pnl_all / n_all if n_all > 0 else 0
        avg_p_all = pnl_p_all / n_p_all if n_p_all > 0 else 0
        avg_htf = pnl_htf / n_htf if n_htf > 0 else 0
        avg_p_htf = pnl_p_htf / n_p_htf if n_p_htf > 0 else 0

        print(f"  {'No Filter + Full TP':<30} {n_all:>5} {wr_all:>6.1f}% {pnl_all:>+9.2f} {avg_all:>+7.2f}")
        print(f"  {'No Filter + Partial TP':<30} {n_p_all:>5} {wr_p_all:>6.1f}% {pnl_p_all:>+9.2f} {avg_p_all:>+7.2f}")
        print(f"  {'HTF EMA50 + Full TP':<30} {n_htf:>5} {wr_htf:>6.1f}% {pnl_htf:>+9.2f} {avg_htf:>+7.2f}")
        print(f"  {'HTF EMA50 + Partial TP':<30} {n_p_htf:>5} {wr_p_htf:>6.1f}% {pnl_p_htf:>+9.2f} {avg_p_htf:>+7.2f}")

        # Filter details
        total_filtered = filt_stats["skipped_buy"] + filt_stats["skipped_sell"]
        print(f"\n  Signals: {len(signals_all)} → {len(signals_htf)} ({total_filtered} filtered)")
        print(f"  BUY: {len(buy_all)} → {len(buy_htf)} ({filt_stats['skipped_buy']} filtered)")
        print(f"  SELL: {len(sell_all)} → {len(sell_htf)} ({filt_stats['skipped_sell']} filtered)")
        print(f"  Filtered signals PnL: {filt_stats['skipped_pnl']:+.2f}R "
              f"({'GOOD: removed losers' if filt_stats['skipped_pnl'] < 0 else 'removed winners'})")

        # Filtered outcomes breakdown
        sb = filt_stats["skipped_buy_results"]
        ss = filt_stats["skipped_sell_results"]
        print(f"  Filtered BUY outcomes:  TP={sb.get('TP',0)} SL={sb.get('SL',0)} Rev={sb.get('CLOSE_REVERSE',0)} Open={sb.get('OPEN',0)}")
        print(f"  Filtered SELL outcomes: TP={ss.get('TP',0)} SL={ss.get('SL',0)} Rev={ss.get('CLOSE_REVERSE',0)} Open={ss.get('OPEN',0)}")

        all_results.append({
            "symbol": symbol, "days": days,
            "n_all": n_all, "wr_all": wr_all, "pnl_all": pnl_all,
            "n_p_all": n_p_all, "wr_p_all": wr_p_all, "pnl_p_all": pnl_p_all,
            "n_htf": n_htf, "wr_htf": wr_htf, "pnl_htf": pnl_htf,
            "n_p_htf": n_p_htf, "wr_p_htf": wr_p_htf, "pnl_p_htf": pnl_p_htf,
            "filtered": total_filtered,
            "filtered_pnl": filt_stats["skipped_pnl"],
            "total_signals": len(signals_all),
        })

    if not all_results:
        print("\nNo results to summarize.")
        return

    # ══════════════════════════════════════════════════════════════
    # GRAND SUMMARY
    # ══════════════════════════════════════════════════════════════
    print(f"\n\n{'═' * 80}")
    print("GRAND SUMMARY — 1 YEAR, ALL PAIRS")
    print(f"{'═' * 80}")

    # Full TP table
    print(f"\n  Full TP:")
    print(f"  {'Symbol':<10} │ {'No Filter':^24} │ {'HTF EMA50':^24} │ {'Diff':>7}")
    print(f"  {'─'*72}")
    tn_all = tw_all = tn_htf = tw_htf = 0
    tpnl_all = tpnl_htf = 0.0
    for r in all_results:
        diff = r["pnl_htf"] - r["pnl_all"]
        mark = "✅" if diff >= 0 else "❌"
        print(f"  {r['symbol']:<10} │ {r['n_all']:>4}sig {r['wr_all']:>5.1f}% {r['pnl_all']:>+8.2f}R │ "
              f"{r['n_htf']:>4}sig {r['wr_htf']:>5.1f}% {r['pnl_htf']:>+8.2f}R │ {diff:>+7.2f} {mark}")
        tn_all += r["n_all"]; tpnl_all += r["pnl_all"]
        tn_htf += r["n_htf"]; tpnl_htf += r["pnl_htf"]
        tw_all += round(r["n_all"] * r["wr_all"] / 100)
        tw_htf += round(r["n_htf"] * r["wr_htf"] / 100)

    diff_total = tpnl_htf - tpnl_all
    twr_all = tw_all / tn_all * 100 if tn_all > 0 else 0
    twr_htf = tw_htf / tn_htf * 100 if tn_htf > 0 else 0
    print(f"  {'─'*72}")
    mark = "✅" if diff_total >= 0 else "❌"
    print(f"  {'TOTAL':<10} │ {tn_all:>4}sig {twr_all:>5.1f}% {tpnl_all:>+8.2f}R │ "
          f"{tn_htf:>4}sig {twr_htf:>5.1f}% {tpnl_htf:>+8.2f}R │ {diff_total:>+7.2f} {mark}")

    # Partial TP table
    print(f"\n  Partial TP:")
    print(f"  {'Symbol':<10} │ {'No Filter':^24} │ {'HTF EMA50':^24} │ {'Diff':>7}")
    print(f"  {'─'*72}")
    tn_p_all = tw_p_all = tn_p_htf = tw_p_htf = 0
    tpnl_p_all = tpnl_p_htf = 0.0
    for r in all_results:
        diff = r["pnl_p_htf"] - r["pnl_p_all"]
        mark = "✅" if diff >= 0 else "❌"
        print(f"  {r['symbol']:<10} │ {r['n_p_all']:>4}sig {r['wr_p_all']:>5.1f}% {r['pnl_p_all']:>+8.2f}R │ "
              f"{r['n_p_htf']:>4}sig {r['wr_p_htf']:>5.1f}% {r['pnl_p_htf']:>+8.2f}R │ {diff:>+7.2f} {mark}")
        tn_p_all += r["n_p_all"]; tpnl_p_all += r["pnl_p_all"]
        tn_p_htf += r["n_p_htf"]; tpnl_p_htf += r["pnl_p_htf"]
        tw_p_all += round(r["n_p_all"] * r["wr_p_all"] / 100)
        tw_p_htf += round(r["n_p_htf"] * r["wr_p_htf"] / 100)

    diff_p_total = tpnl_p_htf - tpnl_p_all
    twr_p_all = tw_p_all / tn_p_all * 100 if tn_p_all > 0 else 0
    twr_p_htf = tw_p_htf / tn_p_htf * 100 if tn_p_htf > 0 else 0
    print(f"  {'─'*72}")
    mark = "✅" if diff_p_total >= 0 else "❌"
    print(f"  {'TOTAL':<10} │ {tn_p_all:>4}sig {twr_p_all:>5.1f}% {tpnl_p_all:>+8.2f}R │ "
          f"{tn_p_htf:>4}sig {twr_p_htf:>5.1f}% {tpnl_p_htf:>+8.2f}R │ {diff_p_total:>+7.2f} {mark}")

    # Overall statistics
    total_filtered = sum(r["filtered"] for r in all_results)
    total_signals = sum(r["total_signals"] for r in all_results)
    total_filtered_pnl = sum(r["filtered_pnl"] for r in all_results)

    print(f"\n  {'═' * 65}")
    print(f"  FILTER IMPACT:")
    print(f"    Signals: {total_signals} → {total_signals - total_filtered} ({total_filtered} filtered, {total_filtered/total_signals*100:.1f}%)")
    print(f"    Filtered signals original PnL: {total_filtered_pnl:+.2f}R")
    print(f"    {'→ Filter correctly removes NET LOSERS ✅' if total_filtered_pnl < 0 else '→ Filter removes NET WINNERS ⚠️'}")

    print(f"\n  Win Rate:")
    print(f"    Full TP:    {twr_all:.1f}% → {twr_htf:.1f}% ({twr_htf - twr_all:+.1f}%)")
    print(f"    Partial TP: {twr_p_all:.1f}% → {twr_p_htf:.1f}% ({twr_p_htf - twr_p_all:+.1f}%)")

    print(f"\n  PnL per trade (quality):")
    avg_all = tpnl_all / tn_all if tn_all > 0 else 0
    avg_htf = tpnl_htf / tn_htf if tn_htf > 0 else 0
    avg_p_all = tpnl_p_all / tn_p_all if tn_p_all > 0 else 0
    avg_p_htf = tpnl_p_htf / tn_p_htf if tn_p_htf > 0 else 0
    print(f"    Full TP:    {avg_all:+.2f}R → {avg_htf:+.2f}R ({avg_htf - avg_all:+.2f}R/trade)")
    print(f"    Partial TP: {avg_p_all:+.2f}R → {avg_p_htf:+.2f}R ({avg_p_htf - avg_p_all:+.2f}R/trade)")

    print(f"\n  {'═' * 65}")
    if diff_total > 0:
        print(f"  ✅ VERDICT: HTF Filter IMPROVES Full TP by {diff_total:+.2f}R")
    elif diff_total == 0:
        print(f"  ⚖️ VERDICT: HTF Filter is NEUTRAL for Full TP")
    else:
        print(f"  ❌ VERDICT: HTF Filter HURTS Full TP by {diff_total:+.2f}R")

    if diff_p_total > 0:
        print(f"  ✅ VERDICT: HTF Filter IMPROVES Partial TP by {diff_p_total:+.2f}R")
    elif diff_p_total == 0:
        print(f"  ⚖️ VERDICT: HTF Filter is NEUTRAL for Partial TP")
    else:
        print(f"  ❌ VERDICT: HTF Filter HURTS Partial TP by {diff_p_total:+.2f}R")
    print(f"  {'═' * 65}")


if __name__ == "__main__":
    main()
