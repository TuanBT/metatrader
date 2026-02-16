"""
backtest_recent.py - Recent Performance Summary
Shows stats for: last 1 day, 3 days, 1 week, 2 weeks, 1 month, etc.
Per-pair + combined.
"""
import sys, os, time

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _THIS_DIR)

from backtest_5year import (
    PAIRS, preload_all, _get_signals,
    _get_df, SL_BUFFER
)
import pandas as pd

WINDOWS = [
    ("Last 1 day",      1),
    ("Last 3 days",     3),
    ("Last 1 week",     7),
    ("Last 2 weeks",   14),
    ("Last 1 month",   30),
    ("Last 3 months",  90),
    ("Last 6 months", 180),
    ("Last 1 year",   365),
    ("Last 2 years",  730),
    ("Last 5 years", 1825),
    ("All data",        0),
]


def calc_stats(sigs):
    n = len(sigs)
    if n == 0:
        return None
    wins = sum(1 for s in sigs if s.pnl_r > 0)
    pnl = sum(s.pnl_r for s in sigs)
    wr = wins / n * 100
    avg = pnl / n
    # Max drawdown
    eq = [0.0]
    for s in sigs:
        eq.append(eq[-1] + s.pnl_r)
    peak = mdd = 0.0
    for e in eq:
        if e > peak:
            peak = e
        dd = peak - e
        if dd > mdd:
            mdd = dd
    # Max consecutive losses
    max_cl = cl = 0
    for s in sigs:
        if s.pnl_r <= 0:
            cl += 1
            if cl > max_cl:
                max_cl = cl
        else:
            cl = 0
    return {"n": n, "wins": wins, "wr": wr, "pnl": pnl, "avg": avg, "mdd": mdd, "max_cl": max_cl}


def print_header(sym, end_date):
    print()
    print("  %s (data until %s):" % (sym, end_date.strftime("%Y-%m-%d %H:%M")))
    print("  %-16s | %6s | %5s | %6s | %10s | %7s | %6s | %5s" % (
        "Window", "Trades", "Wins", "WR%", "PnL(R)", "Avg/T", "MaxDD", "MaxCL"))
    print("  %s-+-%s-+-%s-+-%s-+-%s-+-%s-+-%s-+-%s" % (
        "-"*16, "-"*6, "-"*5, "-"*6, "-"*10, "-"*7, "-"*6, "-"*5))


def print_row(wname, st):
    if st is None:
        print("  %-16s | %6d |     - |    -  |          - |       - |      - |     -" % (wname, 0))
        return
    tag = " <<" if st["pnl"] < 0 else ""
    print("  %-16s | %6d | %5d | %5.1f%% | %+10.1f | %+7.2f | %6.1f | %5d%s" % (
        wname, st["n"], st["wins"], st["wr"], st["pnl"], st["avg"], st["mdd"], st["max_cl"], tag))


if __name__ == "__main__":
    t0 = time.time()

    print("=" * 95)
    print("MST Medio v2.0 - Recent Performance Summary")
    print("=" * 95)
    print("  ImpulseMult = 1.0 | BreakMult = 0.25 | SL Buffer = 5%%")
    print("=" * 95)

    preload_all()

    # Build per-pair closed signals + end dates
    pair_data = {}
    global_end = pd.Timestamp("2000-01-01")
    for sym, fn in PAIRS:
        df = _get_df(sym, fn)
        if df is None:
            continue
        sigs = _get_signals(sym, fn)
        closed = [s for s in sigs if s.result in ("TP", "SL", "CLOSE_REVERSE")]
        end_dt = df.index[-1]
        pair_data[sym] = {"closed": closed, "end": end_dt}
        if end_dt > global_end:
            global_end = end_dt

    # Per-pair tables
    for sym, fn in PAIRS:
        if sym not in pair_data:
            continue
        closed = pair_data[sym]["closed"]
        end_dt = pair_data[sym]["end"]
        print_header(sym, end_dt)
        for wname, days in WINDOWS:
            if days > 0:
                start = end_dt - pd.Timedelta(days=days)
            else:
                start = pd.Timestamp("2000-01-01")
            w = [s for s in closed if s.confirm_time >= start]
            print_row(wname, calc_stats(w))

    # Combined
    print()
    print("-" * 95)
    print("  ALL 6 PAIRS COMBINED:")
    print("  %-16s | %6s | %5s | %6s | %10s | %7s | %5s" % (
        "Window", "Trades", "Wins", "WR%", "PnL(R)", "Avg/T", "MaxCL"))
    print("  %s-+-%s-+-%s-+-%s-+-%s-+-%s-+-%s" % (
        "-"*16, "-"*6, "-"*5, "-"*6, "-"*10, "-"*7, "-"*5))

    all_closed = []
    for sym in pair_data:
        all_closed.extend(pair_data[sym]["closed"])

    for wname, days in WINDOWS:
        if days > 0:
            start = global_end - pd.Timedelta(days=days)
        else:
            start = pd.Timestamp("2000-01-01")
        w = [s for s in all_closed if s.confirm_time >= start]
        st = calc_stats(w)
        if st is None:
            continue
        tag = " <<" if st["pnl"] < 0 else ""
        print("  %-16s | %6d | %5d | %5.1f%% | %+10.1f | %+7.2f | %5d%s" % (
            wname, st["n"], int(st["wr"]*st["n"]/100), st["wr"], st["pnl"], st["avg"], st["max_cl"], tag))

    elapsed = time.time() - t0
    print()
    print("=" * 95)
    print("  Done (%.1fs)" % elapsed)
    print("=" * 95)
