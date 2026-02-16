"""
backtest_5year.py — Multi-Year Backtest with Time Period Analysis
=================================================================
Tests strategy across different time windows:
  - Per Year breakdown (2021, 2022, 2023, 2024, 2025, 2026)
  - Short-term (last 3 months, 6 months)
  - Medium-term (last 1 year, 2 years)
  - Long-term (3 years, all data)
  - Per quarter breakdown
  - SL Buffer comparison: 0% vs 5%
  - Full TP vs Partial TP over time
"""
import sys
import os

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_TV_BACKTEST = os.path.join(_THIS_DIR, "..", "..", "..", "..", "tradingview", "MST Medio", "backtest")
sys.path.insert(0, _TV_BACKTEST)

import pandas as pd
import numpy as np
from typing import List, Dict, Tuple
from strategy_mst_medio import run_mst_medio, Signal
from backtest_partial_tp import simulate_partial_tp, PartialTrade

DATA_DIR = os.path.join(_THIS_DIR, "..", "..", "..", "candle data")

PAIRS = [
    ("XAUUSD", "XAUUSDm_M5.csv"),
    ("BTCUSD", "BTCUSDm_M5.csv"),
    ("ETHUSD", "ETHUSDm_M5.csv"),
    ("USOIL",  "USOILm_M5.csv"),
    ("EURUSD", "EURUSDm_M5.csv"),
    ("USDJPY", "USDJPYm_M5.csv"),
]

# Optimal settings
IMPULSE_MULT = 1.0
BREAK_MULT = 0.25
PIVOT_LEN = 5
SL_BUFFER = 0.05

# ═══════════════════════════════════════════════════════════════
# GLOBAL CACHE — load data + run strategy ONCE, reuse everywhere
# ═══════════════════════════════════════════════════════════════
_cache_df = {}       # symbol → DataFrame
_cache_sigs = {}     # (symbol, sl_buffer) → signals list
_cache_swings = {}   # symbol → swings list
_period_start = None # set from CLI


def _get_df(symbol: str, filename: str) -> pd.DataFrame:
    """Get cached DataFrame (load once)."""
    if symbol not in _cache_df:
        filepath = os.path.join(DATA_DIR, filename)
        if not os.path.exists(filepath):
            return None
        _cache_df[symbol] = load_data(filepath)
    return _cache_df[symbol]


def _get_signals(symbol: str, filename: str, sl_buffer: float = SL_BUFFER) -> List[Signal]:
    """Get cached signals (run strategy once per symbol+sl_buffer combo)."""
    key = (symbol, sl_buffer)
    if key not in _cache_sigs:
        df = _get_df(symbol, filename)
        if df is None:
            return []
        sigs, swings = run_mst_medio(df, PIVOT_LEN, BREAK_MULT, IMPULSE_MULT,
                                      sl_buffer_pct=sl_buffer, tp_mode="confirm")
        _cache_sigs[key] = sigs
        if symbol not in _cache_swings:
            _cache_swings[symbol] = swings
    return _cache_sigs[key]


def preload_all():
    """Pre-load all data and run strategy for all pairs. Shows progress."""
    import time as _t
    print("\n  Loading data & running strategy...")
    for symbol, filename in PAIRS:
        t0 = _t.time()
        df = _get_df(symbol, filename)
        if df is None:
            print(f"    ⚠️ {symbol}: No data file")
            continue
        sigs = _get_signals(symbol, filename)
        closed = [s for s in sigs if s.result in ("TP", "SL", "CLOSE_REVERSE")]
        elapsed = _t.time() - t0
        print(f"    ✅ {symbol}: {len(df):>8,} bars → {len(closed):>5} trades ({elapsed:.1f}s)")
    print()


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


def stats(signals: List[Signal]) -> Dict:
    closed = [s for s in signals if s.result in ("TP", "SL", "CLOSE_REVERSE")]
    n = len(closed)
    if n == 0:
        return {"n": 0, "wr": 0, "pnl": 0, "avg": 0, "max_dd": 0}
    wins = sum(1 for s in closed if s.pnl_r > 0)
    pnl = sum(s.pnl_r for s in closed)

    # Max drawdown
    equity = [0.0]
    for s in closed:
        equity.append(equity[-1] + s.pnl_r)
    peak = max_dd = 0
    for e in equity:
        if e > peak: peak = e
        dd = peak - e
        if dd > max_dd: max_dd = dd

    return {"n": n, "wr": wins / n * 100, "pnl": pnl, "avg": pnl / n, "max_dd": max_dd}


def partial_stats(trades: List[PartialTrade]) -> Dict:
    n = len(trades)
    if n == 0:
        return {"n": 0, "wr": 0, "pnl": 0, "avg": 0}
    pnl = sum((t.part1_pnl_r + t.part2_pnl_r) / 2 for t in trades)
    wins = sum(1 for t in trades if (t.part1_pnl_r + t.part2_pnl_r) > 0)
    return {"n": n, "wr": wins / n * 100, "pnl": pnl, "avg": pnl / n}


def filter_signals_by_period(signals: List[Signal], start: pd.Timestamp, end: pd.Timestamp) -> List[Signal]:
    """Filter signals where confirm_time falls within the period."""
    return [s for s in signals if start <= s.confirm_time < end]


# ═══════════════════════════════════════════════════════════════
# SECTION 1: DATA OVERVIEW
# ═══════════════════════════════════════════════════════════════

def show_data_overview():
    """Show available data ranges."""
    print("\n" + "═" * 80)
    print("DATA OVERVIEW")
    print("═" * 80)

    for symbol, filename in PAIRS:
        df = _get_df(symbol, filename)
        if df is None:
            print(f"  ⚠️ {symbol}: No data file ({filename})")
            continue
        days = (df.index[-1] - df.index[0]).days
        years = days / 365.25
        print(f"  {symbol}: {len(df):>8,} bars | {df.index[0].strftime('%Y-%m-%d')} → {df.index[-1].strftime('%Y-%m-%d')} | {days} days ({years:.1f} years)")


# ═══════════════════════════════════════════════════════════════
# SECTION 2: PER-YEAR BREAKDOWN
# ═══════════════════════════════════════════════════════════════

def test_per_year():
    """Break down strategy performance by calendar year."""
    print("\n" + "═" * 80)
    print("SECTION 1 — PER-YEAR PERFORMANCE")
    print("═" * 80)

    for symbol, filename in PAIRS:
        df = _get_df(symbol, filename)
        if df is None:
            continue
        sigs = _get_signals(symbol, filename)

        # Get year range
        min_year = df.index[0].year
        max_year = df.index[-1].year

        print(f"\n  {symbol} ({df.index[0].strftime('%Y-%m')} → {df.index[-1].strftime('%Y-%m')})")
        print(f"  {'Year':>6} │ {'Trades':>6} │ {'WR%':>6} │ {'PnL(R)':>10} │ {'Avg/Trade':>9} │ {'MaxDD(R)':>8}")
        print(f"  {'─' * 6}─┼─{'─' * 6}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 9}─┼─{'─' * 8}")

        total_n = total_pnl = 0
        total_wins = 0

        for year in range(min_year, max_year + 1):
            start = pd.Timestamp(f"{year}-01-01")
            end = pd.Timestamp(f"{year+1}-01-01")
            year_sigs = filter_signals_by_period(sigs, start, end)
            s = stats(year_sigs)

            if s["n"] > 0:
                total_n += s["n"]
                total_pnl += s["pnl"]
                total_wins += int(s["wr"] * s["n"] / 100)
                tag = " 🔴" if s["pnl"] < 0 else " 🟢"
                print(f"  {year:>6} │ {s['n']:>6} │ {s['wr']:>5.1f}% │ {s['pnl']:>+10.1f} │ {s['avg']:>+9.2f} │ {s['max_dd']:>8.1f}{tag}")
            else:
                print(f"  {year:>6} │ {0:>6} │    -  │          - │         - │        -")

        if total_n > 0:
            total_wr = total_wins / total_n * 100
            print(f"  {'─' * 6}─┼─{'─' * 6}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 9}─┼─{'─' * 8}")
            print(f"  {'TOTAL':>6} │ {total_n:>6} │ {total_wr:>5.1f}% │ {total_pnl:>+10.1f} │ {total_pnl/total_n:>+9.2f} │")


# ═══════════════════════════════════════════════════════════════
# SECTION 3: PER-QUARTER BREAKDOWN
# ═══════════════════════════════════════════════════════════════

def test_per_quarter():
    """Break down strategy by quarter."""
    print("\n" + "═" * 80)
    print("SECTION 2 — PER-QUARTER PERFORMANCE (ALL PAIRS COMBINED)")
    print("═" * 80)

    # Collect all signals across all pairs with symbol tag
    all_sigs = []
    min_date = pd.Timestamp("2099-01-01")
    max_date = pd.Timestamp("2000-01-01")

    for symbol, filename in PAIRS:
        df = _get_df(symbol, filename)
        if df is None:
            continue
        sigs = _get_signals(symbol, filename)
        all_sigs.extend(sigs)
        if df.index[0] < min_date: min_date = df.index[0]
        if df.index[-1] > max_date: max_date = df.index[-1]

    if not all_sigs:
        print("  No signals found.")
        return

    # Generate quarter ranges
    quarters = []
    year = min_date.year
    q = (min_date.month - 1) // 3 + 1
    while True:
        start = pd.Timestamp(f"{year}-{(q-1)*3+1:02d}-01")
        if q < 4:
            end = pd.Timestamp(f"{year}-{q*3+1:02d}-01")
        else:
            end = pd.Timestamp(f"{year+1}-01-01")
        if start > max_date:
            break
        quarters.append((f"{year}Q{q}", start, end))
        q += 1
        if q > 4:
            q = 1
            year += 1

    print(f"\n  {'Quarter':>8} │ {'Trades':>6} │ {'WR%':>6} │ {'PnL(R)':>10} │ {'Avg/Trade':>9}")
    print(f"  {'─' * 8}─┼─{'─' * 6}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 9}")

    running_pnl = 0
    for qname, start, end in quarters:
        q_sigs = filter_signals_by_period(all_sigs, start, end)
        s = stats(q_sigs)
        if s["n"] > 0:
            running_pnl += s["pnl"]
            tag = " 🔴" if s["pnl"] < 0 else ""
            print(f"  {qname:>8} │ {s['n']:>6} │ {s['wr']:>5.1f}% │ {s['pnl']:>+10.1f} │ {s['avg']:>+9.2f}{tag}")

    print(f"\n  Running Total: {running_pnl:+.1f}R")


# ═══════════════════════════════════════════════════════════════
# SECTION 4: SHORT / MEDIUM / LONG TERM WINDOWS
# ═══════════════════════════════════════════════════════════════

def test_time_windows():
    """Test performance over different time windows (from the end of data)."""
    print("\n" + "═" * 80)
    print("SECTION 3 — TIME WINDOWS (from most recent data)")
    print("═" * 80)

    windows = [
        ("Last 3 months",   90),
        ("Last 6 months",  180),
        ("Last 1 year",    365),
        ("Last 2 years",   730),
        ("Last 3 years",  1095),
        ("Last 5 years",  1825),
        ("All data",         0),
    ]

    for symbol, filename in PAIRS:
        df = _get_df(symbol, filename)
        if df is None:
            continue
        sigs = _get_signals(symbol, filename)

        end_date = df.index[-1]

        print(f"\n  {symbol}:")
        print(f"  {'Window':<16} │ {'Trades':>6} │ {'WR%':>6} │ {'PnL(R)':>10} │ {'Avg/Trade':>9} │ {'MaxDD':>6}")
        print(f"  {'─' * 16}─┼─{'─' * 6}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 9}─┼─{'─' * 6}")

        for wname, days in windows:
            if days > 0:
                start = end_date - pd.Timedelta(days=days)
                if start < df.index[0]:
                    start = df.index[0]
            else:
                start = df.index[0]

            w_sigs = filter_signals_by_period(sigs, start, end_date + pd.Timedelta(days=1))
            s = stats(w_sigs)
            if s["n"] > 0:
                tag = " 🔴" if s["pnl"] < 0 else ""
                print(f"  {wname:<16} │ {s['n']:>6} │ {s['wr']:>5.1f}% │ {s['pnl']:>+10.1f} │ {s['avg']:>+9.2f} │ {s['max_dd']:>6.1f}{tag}")
            else:
                print(f"  {wname:<16} │ {0:>6} │    -  │          - │         - │      -")


# ═══════════════════════════════════════════════════════════════
# SECTION 5: SL BUFFER OVER TIME
# ═══════════════════════════════════════════════════════════════

def test_sl_buffer_over_time():
    """Compare SL buffer 0% vs 5% across time periods."""
    print("\n" + "═" * 80)
    print("SECTION 4 — SL BUFFER 0% vs 5% OVER TIME")
    print("═" * 80)

    for symbol, filename in PAIRS:
        df = _get_df(symbol, filename)
        if df is None:
            continue
        sigs_0 = _get_signals(symbol, filename, sl_buffer=0.0)
        sigs_5 = _get_signals(symbol, filename, sl_buffer=0.05)

        min_year = df.index[0].year
        max_year = df.index[-1].year

        print(f"\n  {symbol}:")
        print(f"  {'Year':>6} │ {'0% WR':>6} │ {'0% PnL':>10} │ {'5% WR':>6} │ {'5% PnL':>10} │ {'Diff':>8}")
        print(f"  {'─' * 6}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 8}")

        for year in range(min_year, max_year + 1):
            start = pd.Timestamp(f"{year}-01-01")
            end = pd.Timestamp(f"{year+1}-01-01")

            y0 = stats(filter_signals_by_period(sigs_0, start, end))
            y5 = stats(filter_signals_by_period(sigs_5, start, end))

            if y0["n"] > 0 or y5["n"] > 0:
                diff = y0["pnl"] - y5["pnl"]
                tag = " ✅0%" if diff > 0 else " ✅5%"
                print(f"  {year:>6} │ {y0['wr']:>5.1f}% │ {y0['pnl']:>+10.1f} │ {y5['wr']:>5.1f}% │ {y5['pnl']:>+10.1f} │ {diff:>+8.1f}{tag}")


# ═══════════════════════════════════════════════════════════════
# SECTION 6: FULL TP vs PARTIAL TP OVER TIME
# ═══════════════════════════════════════════════════════════════

def test_tp_over_time():
    """Compare Full TP vs Partial TP across time periods."""
    print("\n" + "═" * 80)
    print("SECTION 5 — FULL TP vs PARTIAL TP OVER TIME")
    print("═" * 80)

    for symbol, filename in PAIRS:
        df = _get_df(symbol, filename)
        if df is None:
            continue
        sigs = _get_signals(symbol, filename)
        trades = simulate_partial_tp(df, sigs)

        min_year = df.index[0].year
        max_year = df.index[-1].year

        print(f"\n  {symbol}:")
        print(f"  {'Year':>6} │ {'Full N':>6} │ {'Full WR':>7} │ {'Full PnL':>10} │ {'Part WR':>7} │ {'Part PnL':>10} │ {'Better':>8}")
        print(f"  {'─' * 6}─┼─{'─' * 6}─┼─{'─' * 7}─┼─{'─' * 10}─┼─{'─' * 7}─┼─{'─' * 10}─┼─{'─' * 8}")

        for year in range(min_year, max_year + 1):
            start = pd.Timestamp(f"{year}-01-01")
            end = pd.Timestamp(f"{year+1}-01-01")

            year_sigs = filter_signals_by_period(sigs, start, end)
            sf = stats(year_sigs)

            year_trades = [t for t in trades if start <= t.signal.confirm_time < end]
            sp = partial_stats(year_trades)

            if sf["n"] > 0:
                diff = sp["pnl"] - sf["pnl"]
                tag = "PARTIAL" if diff > 0 else "FULL"
                print(f"  {year:>6} │ {sf['n']:>6} │ {sf['wr']:>6.1f}% │ {sf['pnl']:>+10.1f} │ {sp['wr']:>6.1f}% │ {sp['pnl']:>+10.1f} │ {tag:>8}")


# ═══════════════════════════════════════════════════════════════
# SECTION 7: CONSISTENCY — MONTHLY WIN RATE
# ═══════════════════════════════════════════════════════════════

def test_monthly_consistency():
    """Show monthly consistency — how many months are profitable?"""
    print("\n" + "═" * 80)
    print("SECTION 6 — MONTHLY CONSISTENCY (ALL PAIRS COMBINED)")
    print("═" * 80)

    all_sigs = []
    for symbol, filename in PAIRS:
        df = _get_df(symbol, filename)
        if df is None:
            continue
        sigs = _get_signals(symbol, filename)
        all_sigs.extend(sigs)

    if not all_sigs:
        print("  No signals.")
        return

    # Group by month
    months = {}
    for s in all_sigs:
        if s.result not in ("TP", "SL", "CLOSE_REVERSE"):
            continue
        key = s.confirm_time.strftime("%Y-%m")
        if key not in months:
            months[key] = {"n": 0, "pnl": 0, "wins": 0}
        months[key]["n"] += 1
        months[key]["pnl"] += s.pnl_r
        if s.pnl_r > 0:
            months[key]["wins"] += 1

    sorted_months = sorted(months.keys())
    profitable = 0
    total_months = len(sorted_months)

    print(f"\n  {'Month':>8} │ {'Trades':>6} │ {'WR%':>6} │ {'PnL(R)':>10} │ {'Avg':>7}")
    print(f"  {'─' * 8}─┼─{'─' * 6}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 7}")

    for month in sorted_months:
        m = months[month]
        wr = m["wins"] / m["n"] * 100 if m["n"] > 0 else 0
        avg = m["pnl"] / m["n"] if m["n"] > 0 else 0
        tag = " 🔴" if m["pnl"] < 0 else ""
        if m["pnl"] > 0:
            profitable += 1
        print(f"  {month:>8} │ {m['n']:>6} │ {wr:>5.1f}% │ {m['pnl']:>+10.1f} │ {avg:>+7.2f}{tag}")

    print(f"\n  Profitable months: {profitable}/{total_months} ({profitable/total_months*100:.0f}%)")
    losing = total_months - profitable
    print(f"  Losing months:     {losing}/{total_months} ({losing/total_months*100:.0f}%)")


# ═══════════════════════════════════════════════════════════════
# SECTION 8: GRAND SUMMARY
# ═══════════════════════════════════════════════════════════════

def grand_summary():
    """Overall summary across all pairs and entire data range."""
    print("\n" + "═" * 80)
    print("GRAND SUMMARY — ALL PAIRS, ALL DATA")
    print("═" * 80)

    print(f"\n  {'Symbol':<8} │ {'Days':>5} │ {'Trades':>6} │ {'WR%':>6} │ {'PnL(R)':>10} │ {'Avg':>7} │ {'MaxDD':>6} │ {'Avg/Month':>9}")
    print(f"  {'─' * 8}─┼─{'─' * 5}─┼─{'─' * 6}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 7}─┼─{'─' * 6}─┼─{'─' * 9}")

    total_n = total_pnl = 0
    total_wins = 0

    for symbol, filename in PAIRS:
        df = _get_df(symbol, filename)
        if df is None:
            continue
        days = (df.index[-1] - df.index[0]).days
        months = days / 30.44

        sigs = _get_signals(symbol, filename)
        s = stats(sigs)

        per_month = s["pnl"] / months if months > 0 else 0
        print(f"  {symbol:<8} │ {days:>5} │ {s['n']:>6} │ {s['wr']:>5.1f}% │ {s['pnl']:>+10.1f} │ {s['avg']:>+7.2f} │ {s['max_dd']:>6.1f} │ {per_month:>+9.1f}")

        total_n += s["n"]
        total_pnl += s["pnl"]
        total_wins += int(s["wr"] * s["n"] / 100)

    if total_n > 0:
        total_wr = total_wins / total_n * 100
        print(f"  {'─' * 8}─┼─{'─' * 5}─┼─{'─' * 6}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 7}─┼─{'─' * 6}─┼─{'─' * 9}")
        print(f"  {'TOTAL':<8} │       │ {total_n:>6} │ {total_wr:>5.1f}% │ {total_pnl:>+10.1f} │ {total_pnl/total_n:>+7.2f} │")


# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

import argparse
import time as _time

def parse_period(period_str: str) -> pd.Timestamp:
    """Parse period string like '1m', '3m', '6m', '1y', '2y', '5y' into a start timestamp."""
    now = pd.Timestamp.now()
    s = period_str.strip().lower()
    if s == "all":
        return pd.Timestamp("2000-01-01")
    if s.endswith("m"):
        months = int(s[:-1])
        return now - pd.DateOffset(months=months)
    elif s.endswith("y"):
        years = int(s[:-1])
        return now - pd.DateOffset(years=years)
    elif s.endswith("d"):
        days = int(s[:-1])
        return now - pd.Timedelta(days=days)
    else:
        raise ValueError(f"Invalid period: {period_str}. Use format: 1m, 3m, 6m, 1y, 2y, 5y, all")


def load_data_with_period(path: str, period_start: pd.Timestamp = None) -> pd.DataFrame:
    """Load data and optionally trim to a period. Returns smaller DataFrame for faster processing."""
    df = load_data(path)
    if period_start is not None and period_start > df.index[0]:
        # Keep some extra lookback for swings/state (~500 bars = ~1.7 days M5)
        lookback = pd.Timedelta(days=30)  # 30 days lookback for swing formation
        trim_start = period_start - lookback
        df = df[df.index >= trim_start]
    return df


def filter_signals_by_start(signals: list, period_start: pd.Timestamp) -> list:
    """Keep only signals confirmed after period_start."""
    return [s for s in signals if s.confirm_time >= period_start]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="MST Medio Multi-Year Backtest")
    parser.add_argument("--period", "-p", type=str, default="all",
                        help="Data period: 1m, 3m, 6m, 1y, 2y, 5y, all (default: all)")
    parser.add_argument("--sections", "-s", type=str, default="all",
                        help="Sections to run: all, summary, year, quarter, windows, sl, tp, monthly (comma-separated)")
    parser.add_argument("--pair", type=str, default=None,
                        help="Single pair to test: XAUUSD, BTCUSD, ETHUSD, USOIL, EURUSD, USDJPY")
    args = parser.parse_args()

    period_start = parse_period(args.period)
    sections = args.sections.lower().split(",") if args.sections != "all" else ["all"]

    # Filter pairs if specified
    if args.pair:
        filtered = [(s, f) for s, f in PAIRS if s.upper() == args.pair.upper()]
        if not filtered:
            print(f"❌ Unknown pair: {args.pair}. Available: {', '.join(s for s, _ in PAIRS)}")
            sys.exit(1)
        PAIRS.clear()
        PAIRS.extend(filtered)

    t0 = _time.time()

    print("=" * 80)
    print("MST Medio v2.0 — Multi-Year Backtest with Time Period Analysis")
    print("=" * 80)
    print(f"  ImpulseMult = {IMPULSE_MULT} | BreakMult = {BREAK_MULT} | SL Buffer = {SL_BUFFER*100:.0f}%")
    print(f"  Period: {args.period} | From: {period_start.strftime('%Y-%m-%d')}")
    if args.pair:
        print(f"  Pair: {args.pair.upper()}")
    print("=" * 80)

    # Pre-load all data + run strategy ONCE (cached)
    preload_all()

    show_data_overview()

    run_all = "all" in sections
    if run_all or "summary" in sections:
        grand_summary()
    if run_all or "year" in sections:
        test_per_year()
    if run_all or "quarter" in sections:
        test_per_quarter()
    if run_all or "windows" in sections:
        test_time_windows()
    if run_all or "sl" in sections:
        test_sl_buffer_over_time()
    if run_all or "tp" in sections:
        test_tp_over_time()
    if run_all or "monthly" in sections:
        test_monthly_consistency()

    elapsed = _time.time() - t0
    print(f"\n" + "═" * 80)
    print(f"DONE — All sections complete ({elapsed:.1f}s)")
    print("═" * 80)
