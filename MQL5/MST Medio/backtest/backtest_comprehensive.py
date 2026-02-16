"""
backtest_comprehensive.py — Comprehensive 1-Year Strategy Optimization
======================================================================
Tests ALL combinations of:
  1. HTF Filter: OFF / EMA20 / EMA50 / EMA100
  2. TP Mode: Full TP / Partial TP
  3. SL Buffer: 0% / 5% / 10%
  4. Trailing SL: OFF / BE after TP1 (partial only)
  5. Min R:R: 0 (no filter) / 0.5 / 1.0
  6. Break Mult: 0 / 0.25 / 0.5

Also tests individual improvements:
  - Move SL to BE after price reaches +1R (breakeven trailing)
  - TP at fixed R:R (2.0, 3.0) instead of confirm candle
"""
import sys
import os

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_TV_BACKTEST = os.path.join(_THIS_DIR, "..", "..", "..", "..", "tradingview", "MST Medio", "backtest")
sys.path.insert(0, _TV_BACKTEST)

import pandas as pd
import numpy as np
from typing import List, Dict, Any
from strategy_mst_medio import run_mst_medio, Signal
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


def calc_h1_ema(df_h1: pd.DataFrame, ema_len: int) -> pd.Series:
    return df_h1["Close"].ewm(span=ema_len, adjust=False).mean()


def apply_htf_filter(signals: List[Signal], df_m5: pd.DataFrame,
                      ema_h1: pd.Series) -> List[Signal]:
    filtered = []
    for sig in signals:
        h1_time = sig.confirm_time.floor("1h") - pd.Timedelta(hours=1)
        valid_ema = ema_h1[ema_h1.index <= h1_time]
        if valid_ema.empty:
            filtered.append(sig)
            continue
        ema_val = valid_ema.iloc[-1]
        if sig.confirm_time in df_m5.index:
            cc = df_m5.loc[sig.confirm_time, "Close"]
            if isinstance(cc, pd.Series):
                cc = cc.iloc[0]
        else:
            cc = sig.entry

        if sig.direction == "BUY" and cc < ema_val:
            continue
        if sig.direction == "SELL" and cc > ema_val:
            continue
        filtered.append(sig)
    return filtered


def simulate_trailing_be(df_m5: pd.DataFrame, signals: List[Signal]) -> List[Signal]:
    """
    Trailing SL: Move SL to breakeven after price reaches +1R profit.
    This simulates a simple breakeven trail on Full TP mode.
    """
    times = df_m5.index.values
    highs = df_m5["High"].values
    lows = df_m5["Low"].values

    time_to_idx = {}
    for i, t in enumerate(times):
        time_to_idx[t] = i

    results = []
    for sig in signals:
        new_sig = Signal(
            time=sig.time, direction=sig.direction, entry=sig.entry,
            sl=sig.sl, tp=sig.tp, w1_peak=sig.w1_peak,
            break_time=sig.break_time, confirm_time=sig.confirm_time,
        )
        risk = abs(sig.entry - sig.sl)
        if risk == 0:
            new_sig.result = sig.result
            new_sig.pnl_r = sig.pnl_r
            results.append(new_sig)
            continue

        confirm_idx = time_to_idx.get(sig.confirm_time)
        if confirm_idx is None:
            new_sig.result = sig.result
            new_sig.pnl_r = sig.pnl_r
            results.append(new_sig)
            continue

        be_activated = False
        current_sl = sig.sl

        # Find next signal time for close-on-reverse
        next_sig_idx = None
        for future in signals:
            if future.confirm_time > sig.confirm_time:
                idx = time_to_idx.get(future.confirm_time)
                if idx is not None:
                    next_sig_idx = idx
                    break

        done = False
        for bar_i in range(confirm_idx + 1, len(times)):
            if next_sig_idx is not None and bar_i >= next_sig_idx:
                # Closed by reverse signal
                close_price = df_m5.iloc[bar_i]["Close"]
                if sig.direction == "BUY":
                    new_sig.pnl_r = (close_price - sig.entry) / risk
                else:
                    new_sig.pnl_r = (sig.entry - close_price) / risk
                new_sig.result = "CLOSE_REVERSE"
                done = True
                break

            bar_h = highs[bar_i]
            bar_l = lows[bar_i]

            if sig.direction == "BUY":
                # Check SL hit
                if bar_l <= current_sl:
                    if be_activated:
                        new_sig.result = "BE"
                        new_sig.pnl_r = 0.0
                    else:
                        new_sig.result = "SL"
                        new_sig.pnl_r = -1.0
                    done = True
                    break
                # Check TP hit
                if sig.tp > 0 and bar_h >= sig.tp:
                    rr = abs(sig.tp - sig.entry) / risk
                    new_sig.result = "TP"
                    new_sig.pnl_r = rr
                    done = True
                    break
                # Check +1R → move SL to BE
                if not be_activated and bar_h >= sig.entry + risk:
                    be_activated = True
                    current_sl = sig.entry
            else:
                # SELL
                if bar_h >= current_sl:
                    if be_activated:
                        new_sig.result = "BE"
                        new_sig.pnl_r = 0.0
                    else:
                        new_sig.result = "SL"
                        new_sig.pnl_r = -1.0
                    done = True
                    break
                if sig.tp > 0 and bar_l <= sig.tp:
                    rr = abs(sig.entry - sig.tp) / risk
                    new_sig.result = "TP"
                    new_sig.pnl_r = rr
                    done = True
                    break
                if not be_activated and bar_l <= sig.entry - risk:
                    be_activated = True
                    current_sl = sig.entry

        if not done:
            close_price = df_m5.iloc[-1]["Close"]
            if sig.direction == "BUY":
                new_sig.pnl_r = (close_price - sig.entry) / risk
            else:
                new_sig.pnl_r = (sig.entry - close_price) / risk
            new_sig.result = "OPEN"

        results.append(new_sig)
    return results


def calc_stats(signals):
    closed = [s for s in signals if s.result in ("TP", "SL", "CLOSE_REVERSE", "BE")]
    n = len(closed)
    if n == 0:
        return {"n": 0, "wins": 0, "wr": 0, "pnl": 0, "avg": 0}
    wins = sum(1 for s in closed if s.pnl_r > 0)
    wr = wins / n * 100
    pnl = sum(s.pnl_r for s in closed)
    return {"n": n, "wins": wins, "wr": wr, "pnl": pnl, "avg": pnl / n}


def calc_partial_stats(trades):
    n = len(trades)
    if n == 0:
        return {"n": 0, "wins": 0, "wr": 0, "pnl": 0, "avg": 0}
    pnl = sum((t.part1_pnl_r + t.part2_pnl_r) / 2 for t in trades)
    wins = sum(1 for t in trades if (t.part1_pnl_r + t.part2_pnl_r) > 0)
    wr = wins / n * 100
    return {"n": n, "wins": wins, "wr": wr, "pnl": pnl, "avg": pnl / n}


def main():
    PAIRS = [
        ("XAUUSD",  "XAUUSDm_M5.csv",  "XAUUSDm_H1.csv"),
        ("BTCUSD",  "BTCUSDm_M5.csv",  "BTCUSDm_H1.csv"),
        ("ETHUSD",  "ETHUSDm_M5.csv",  "ETHUSDm_H1.csv"),
        ("USOIL",   "USOILm_M5.csv",   "USOILm_H1.csv"),
        ("EURUSD",  "EURUSDm_M5.csv",  "EURUSDm_H1.csv"),
        ("USDJPY",  "USDJPYm_M5.csv",  "USDJPYm_H1.csv"),
    ]

    # Test configurations
    CONFIGS = [
        # (label, sl_buffer, min_rr, tp_mode, fixed_rr, break_mult, impulse_mult, htf_ema, trailing_be, partial_tp)
        # BASELINE
        ("A1 Baseline",                   0.05, 0, "confirm", 0, 0.25, 1.5, 0,   False, False),
        ("A2 Baseline+Partial",           0.05, 0, "confirm", 0, 0.25, 1.5, 0,   False, True),

        # SL BUFFER variations
        ("B1 SL_Buf=0%",                  0.00, 0, "confirm", 0, 0.25, 1.5, 0,   False, False),
        ("B2 SL_Buf=10%",                 0.10, 0, "confirm", 0, 0.25, 1.5, 0,   False, False),
        ("B3 SL_Buf=15%",                 0.15, 0, "confirm", 0, 0.25, 1.5, 0,   False, False),

        # TRAILING SL (BE after +1R)
        ("C1 Trailing BE",                0.05, 0, "confirm", 0, 0.25, 1.5, 0,   True,  False),
        ("C2 Trailing BE+Partial",        0.05, 0, "confirm", 0, 0.25, 1.5, 0,   True,  True),

        # HTF FILTER
        ("D1 HTF EMA20",                  0.05, 0, "confirm", 0, 0.25, 1.5, 20,  False, False),
        ("D2 HTF EMA50",                  0.05, 0, "confirm", 0, 0.25, 1.5, 50,  False, False),
        ("D3 HTF EMA100",                 0.05, 0, "confirm", 0, 0.25, 1.5, 100, False, False),
        ("D4 HTF EMA20+Partial",          0.05, 0, "confirm", 0, 0.25, 1.5, 20,  False, True),

        # FIXED R:R TP
        ("E1 TP=Fixed 2R",               0.05, 0, "fixed_rr", 2.0, 0.25, 1.5, 0, False, False),
        ("E2 TP=Fixed 3R",               0.05, 0, "fixed_rr", 3.0, 0.25, 1.5, 0, False, False),
        ("E3 TP=Fixed 1.5R",             0.05, 0, "fixed_rr", 1.5, 0.25, 1.5, 0, False, False),

        # MIN R:R FILTER
        ("F1 MinRR=0.5",                  0.05, 0.5, "confirm", 0, 0.25, 1.5, 0, False, False),
        ("F2 MinRR=1.0",                  0.05, 1.0, "confirm", 0, 0.25, 1.5, 0, False, False),

        # BREAK MULT variations
        ("G1 BreakMult=0",                0.05, 0, "confirm", 0, 0.00, 1.5, 0,   False, False),
        ("G2 BreakMult=0.5",              0.05, 0, "confirm", 0, 0.50, 1.5, 0,   False, False),

        # IMPULSE MULT variations
        ("H1 ImpulseMult=0",              0.05, 0, "confirm", 0, 0.25, 0.0, 0,   False, False),
        ("H2 ImpulseMult=1.0",            0.05, 0, "confirm", 0, 0.25, 1.0, 0,   False, False),
        ("H3 ImpulseMult=2.0",            0.05, 0, "confirm", 0, 0.25, 2.0, 0,   False, False),

        # COMBO: Best mix candidates
        ("X1 Partial+TrailBE",            0.05, 0, "confirm", 0, 0.25, 1.5, 0,   True,  True),
        ("X2 SL10%+Partial",              0.10, 0, "confirm", 0, 0.25, 1.5, 0,   False, True),
        ("X3 MinRR0.5+Partial",           0.05, 0.5, "confirm", 0, 0.25, 1.5, 0, False, True),
        ("X4 BreakMult0.5+Partial",       0.05, 0, "confirm", 0, 0.50, 1.5, 0,   False, True),
    ]

    print("=" * 90)
    print("MST Medio v2.0 — COMPREHENSIVE 1-YEAR BACKTEST")
    print(f"Testing {len(CONFIGS)} configurations × {len(PAIRS)} pairs")
    print("=" * 90)

    # Load all data first
    pair_data = {}
    for symbol, m5_file, h1_file in PAIRS:
        m5_path = os.path.join(DATA_DIR, m5_file)
        h1_path = os.path.join(DATA_DIR, h1_file)
        if not os.path.exists(m5_path) or not os.path.exists(h1_path):
            continue
        df_m5 = load_data(m5_path)
        df_h1 = load_data(h1_path)
        pair_data[symbol] = {"m5": df_m5, "h1": df_h1}
        days = (df_m5.index[-1] - df_m5.index[0]).days
        print(f"  Loaded {symbol}: {len(df_m5):,} M5 bars, {days} days")

    # Run all configurations
    results = []  # list of (label, total_n, total_wr, total_pnl, avg_per_trade)

    for cfg_idx, (label, sl_buf, min_rr, tp_mode, fixed_rr, break_mult, impulse_mult, htf_ema, trail_be, partial) in enumerate(CONFIGS):
        total_n = 0
        total_wins = 0
        total_pnl = 0.0

        for symbol in pair_data:
            df_m5 = pair_data[symbol]["m5"]
            df_h1 = pair_data[symbol]["h1"]

            # Generate signals
            signals, _ = run_mst_medio(
                df_m5, pivot_len=5, break_mult=break_mult, impulse_mult=impulse_mult,
                min_rr=min_rr, sl_buffer_pct=sl_buf,
                tp_mode=tp_mode, fixed_rr=fixed_rr, debug=False
            )
            if not signals:
                continue

            # Apply HTF filter
            if htf_ema > 0:
                ema_h1 = calc_h1_ema(df_h1, htf_ema)
                signals = apply_htf_filter(signals, df_m5, ema_h1)

            if not signals:
                continue

            # Apply trailing BE
            if trail_be and not partial:
                signals = simulate_trailing_be(df_m5, signals)
                stats = calc_stats(signals)
            elif partial:
                trades = simulate_partial_tp(df_m5, signals)
                if trail_be:
                    # For partial+trail, use partial stats (trail BE is built into partial mode)
                    stats = calc_partial_stats(trades)
                else:
                    stats = calc_partial_stats(trades)
            else:
                stats = calc_stats(signals)

            total_n += stats["n"]
            total_wins += stats["wins"]
            total_pnl += stats["pnl"]

        wr = total_wins / total_n * 100 if total_n > 0 else 0
        avg = total_pnl / total_n if total_n > 0 else 0
        results.append((label, total_n, total_wins, wr, total_pnl, avg))

        # Progress indicator
        bar = "█" * int(total_pnl / 100) if total_pnl > 0 else "░" * int(abs(total_pnl) / 100)
        print(f"  [{cfg_idx+1:>2}/{len(CONFIGS)}] {label:<30} {total_n:>5}sig {wr:>5.1f}% {total_pnl:>+9.2f}R {avg:>+6.2f}R/t {bar}")

    # ══════════════════════════════════════════════════════════════
    # RANKED RESULTS
    # ══════════════════════════════════════════════════════════════
    print(f"\n\n{'═' * 90}")
    print("RANKED BY TOTAL PnL (R)")
    print(f"{'═' * 90}")
    sorted_by_pnl = sorted(results, key=lambda x: x[4], reverse=True)
    print(f"  {'Rank':>4} {'Config':<30} {'N':>5} {'WR%':>6} {'PnL(R)':>10} {'Avg(R)':>8} {'vs Base':>9}")
    print(f"  {'─'*76}")
    baseline_pnl = results[0][4]  # A1 Baseline
    for i, (label, n, wins, wr, pnl, avg) in enumerate(sorted_by_pnl):
        diff = pnl - baseline_pnl
        mark = "🥇" if i == 0 else "🥈" if i == 1 else "🥉" if i == 2 else "  "
        print(f"  {i+1:>3}{mark} {label:<30} {n:>5} {wr:>5.1f}% {pnl:>+9.2f} {avg:>+7.2f} {diff:>+8.2f}")

    # ══════════════════════════════════════════════════════════════
    # RANKED BY AVERAGE R PER TRADE (quality)
    # ══════════════════════════════════════════════════════════════
    print(f"\n{'═' * 90}")
    print("RANKED BY AVG R/TRADE (Quality)")
    print(f"{'═' * 90}")
    sorted_by_avg = sorted(results, key=lambda x: x[5], reverse=True)
    baseline_avg = results[0][5]
    print(f"  {'Rank':>4} {'Config':<30} {'N':>5} {'WR%':>6} {'PnL(R)':>10} {'Avg(R)':>8} {'vs Base':>9}")
    print(f"  {'─'*76}")
    for i, (label, n, wins, wr, pnl, avg) in enumerate(sorted_by_avg):
        diff = avg - baseline_avg
        mark = "🥇" if i == 0 else "🥈" if i == 1 else "🥉" if i == 2 else "  "
        print(f"  {i+1:>3}{mark} {label:<30} {n:>5} {wr:>5.1f}% {pnl:>+9.2f} {avg:>+7.2f} {diff:>+8.2f}")

    # ══════════════════════════════════════════════════════════════
    # RANKED BY WIN RATE
    # ══════════════════════════════════════════════════════════════
    print(f"\n{'═' * 90}")
    print("RANKED BY WIN RATE (%)")
    print(f"{'═' * 90}")
    sorted_by_wr = sorted(results, key=lambda x: x[3], reverse=True)
    baseline_wr = results[0][3]
    print(f"  {'Rank':>4} {'Config':<30} {'N':>5} {'WR%':>6} {'PnL(R)':>10} {'Avg(R)':>8} {'vs Base':>9}")
    print(f"  {'─'*76}")
    for i, (label, n, wins, wr, pnl, avg) in enumerate(sorted_by_wr):
        diff_wr = wr - baseline_wr
        mark = "🥇" if i == 0 else "🥈" if i == 1 else "🥉" if i == 2 else "  "
        print(f"  {i+1:>3}{mark} {label:<30} {n:>5} {wr:>5.1f}% {pnl:>+9.2f} {avg:>+7.2f} {diff_wr:>+7.1f}%")

    # ══════════════════════════════════════════════════════════════
    # KEY INSIGHTS
    # ══════════════════════════════════════════════════════════════
    print(f"\n{'═' * 90}")
    print("KEY INSIGHTS")
    print(f"{'═' * 90}")

    # Find best in each category
    best_pnl = sorted_by_pnl[0]
    best_avg = sorted_by_avg[0]
    best_wr = sorted_by_wr[0]
    baseline = results[0]

    print(f"\n  BASELINE (A1): {baseline[1]} trades, {baseline[3]:.1f}% WR, {baseline[4]:+.2f}R total, {baseline[5]:+.2f}R/trade")
    print(f"\n  🏆 Best Total PnL:   {best_pnl[0]} → {best_pnl[4]:+.2f}R ({best_pnl[4]-baseline[4]:+.2f} vs base)")
    print(f"  🏆 Best Quality:     {best_avg[0]} → {best_avg[5]:+.2f}R/trade ({best_avg[5]-baseline[5]:+.2f} vs base)")
    print(f"  🏆 Best Win Rate:    {best_wr[0]} → {best_wr[3]:.1f}% ({best_wr[3]-baseline[3]:+.1f}% vs base)")

    # Compare specific improvements
    print(f"\n  Individual Improvements vs Baseline:")
    for label, n, wins, wr, pnl, avg in results:
        if label == "A1 Baseline":
            continue
        diff_pnl = pnl - baseline[4]
        diff_wr = wr - baseline[3]
        icon = "✅" if diff_pnl > 0 else "❌" if diff_pnl < -50 else "➖"
        print(f"    {icon} {label:<30} PnL={diff_pnl:>+8.2f}R  WR={diff_wr:>+5.1f}%  Avg={avg-baseline[5]:>+5.2f}R/t")


if __name__ == "__main__":
    main()
