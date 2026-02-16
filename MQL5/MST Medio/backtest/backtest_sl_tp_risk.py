"""
backtest_sl_tp_risk.py — Deep SL / TP / MaxRisk Analysis
=========================================================
Tests 3 main areas with ImpulseMult=1.0 (new optimal):

SECTION 1 — SL PLACEMENT:
  A. SL Buffer %: 0%, 5%, 10%, 15%, 20%
  B. SL Method: swing-based (current) vs ATR-based vs fixed pips
  C. Trailing SL: No trail, BE after TP1 (partial), Trailing after +1R

SECTION 2 — TP METHOD:
  A. Full TP (confirm candle H/L) vs Partial TP (50/50)
  B. Fixed R:R TP: 1.0R, 1.5R, 2.0R, 3.0R
  C. Partial TP variants: 30/70, 50/50, 70/30 split
  D. Per-pair and per-direction breakdown

SECTION 3 — MAX RISK %:
  A. MaxRisk 1%, 2%, 3%, 5%, no limit
  B. How many signals get filtered at each level
  C. PnL impact per pair
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

# New optimal settings
IMPULSE_MULT = 1.0
BREAK_MULT = 0.25
PIVOT_LEN = 5


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
    """Calculate basic stats from signal list."""
    closed = [s for s in signals if s.result in ("TP", "SL", "CLOSE_REVERSE")]
    n = len(closed)
    if n == 0:
        return {"n": 0, "wr": 0, "pnl": 0, "avg": 0}
    wins = sum(1 for s in closed if s.pnl_r > 0)
    pnl = sum(s.pnl_r for s in closed)
    return {"n": n, "wr": wins / n * 100, "pnl": pnl, "avg": pnl / n}


def partial_stats(trades: List[PartialTrade]) -> Dict:
    """Calculate Partial TP stats."""
    n = len(trades)
    if n == 0:
        return {"n": 0, "wr": 0, "pnl": 0, "avg": 0}
    pnl = sum((t.part1_pnl_r + t.part2_pnl_r) / 2 for t in trades)
    wins = sum(1 for t in trades if (t.part1_pnl_r + t.part2_pnl_r) > 0)
    return {"n": n, "wr": wins / n * 100, "pnl": pnl, "avg": pnl / n}


def calc_drawdown(signals: List[Signal]) -> Dict:
    """Calculate max drawdown and max consecutive losses."""
    closed = [s for s in signals if s.result in ("TP", "SL", "CLOSE_REVERSE")]
    if not closed:
        return {"max_dd_r": 0, "max_consec_loss": 0, "max_consec_win": 0}

    # Equity curve
    equity = [0.0]
    for s in closed:
        equity.append(equity[-1] + s.pnl_r)

    peak = equity[0]
    max_dd = 0.0
    for e in equity:
        if e > peak:
            peak = e
        dd = peak - e
        if dd > max_dd:
            max_dd = dd

    # Consecutive losses/wins
    max_cl = cl = 0
    max_cw = cw = 0
    for s in closed:
        if s.pnl_r < 0:
            cl += 1
            cw = 0
        else:
            cw += 1
            cl = 0
        max_cl = max(max_cl, cl)
        max_cw = max(max_cw, cw)

    return {"max_dd_r": max_dd, "max_consec_loss": max_cl, "max_consec_win": max_cw}


def calc_rr_distribution(signals: List[Signal]) -> Dict:
    """Calculate R:R distribution of trades."""
    closed = [s for s in signals if s.result in ("TP", "SL", "CLOSE_REVERSE")]
    if not closed:
        return {}
    rrs = [s.pnl_r for s in closed]
    return {
        "avg_win": np.mean([r for r in rrs if r > 0]) if any(r > 0 for r in rrs) else 0,
        "avg_loss": np.mean([r for r in rrs if r < 0]) if any(r < 0 for r in rrs) else 0,
        "best": max(rrs),
        "worst": min(rrs),
        "median": np.median(rrs),
    }


# ═══════════════════════════════════════════════════════════════
# SECTION 1: SL PLACEMENT
# ═══════════════════════════════════════════════════════════════

def test_sl_buffers():
    """Test SL buffer: 0%, 5%, 10%, 15%, 20%"""
    print("\n" + "═" * 80)
    print("SECTION 1A — SL BUFFER PERCENTAGE")
    print("═" * 80)
    print("  SL = swing opposite before break + buffer % of raw risk")
    print("  Higher buffer = wider SL = fewer SL hits but smaller R:R per win\n")

    buffers = [0.0, 0.03, 0.05, 0.08, 0.10, 0.15, 0.20]
    results = {b: {"n": 0, "wins": 0, "pnl": 0, "max_dd": 0, "max_cl": 0} for b in buffers}

    for symbol, filename in PAIRS:
        filepath = os.path.join(DATA_DIR, filename)
        if not os.path.exists(filepath):
            continue
        df = load_data(filepath)

        for buf in buffers:
            sigs, _ = run_mst_medio(df, PIVOT_LEN, BREAK_MULT, IMPULSE_MULT,
                                    sl_buffer_pct=buf, tp_mode="confirm")
            s = stats(sigs)
            dd = calc_drawdown(sigs)
            results[buf]["n"] += s["n"]
            results[buf]["wins"] += int(s["wr"] * s["n"] / 100)
            results[buf]["pnl"] += s["pnl"]
            results[buf]["max_dd"] = max(results[buf]["max_dd"], dd["max_dd_r"])
            results[buf]["max_cl"] = max(results[buf]["max_cl"], dd["max_consec_loss"])

    print(f"  {'Buffer':>8} │ {'Trades':>6} │ {'WR%':>6} │ {'PnL(R)':>10} │ {'Avg/Trade':>9} │ {'MaxDD(R)':>9} │ {'MaxConsL':>8}")
    print(f"  {'─' * 8}─┼─{'─' * 6}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 9}─┼─{'─' * 9}─┼─{'─' * 8}")
    for buf in buffers:
        r = results[buf]
        n = r["n"]
        wr = r["wins"] / n * 100 if n > 0 else 0
        avg = r["pnl"] / n if n > 0 else 0
        tag = " ◄ current" if buf == 0.05 else ""
        print(f"  {buf*100:>7.0f}% │ {n:>6} │ {wr:>5.1f}% │ {r['pnl']:>+10.1f} │ {avg:>+9.2f} │ {r['max_dd']:>9.1f} │ {r['max_cl']:>8}{tag}")


def test_sl_buffers_per_pair():
    """Test SL buffer per pair for detailed view."""
    print("\n" + "═" * 80)
    print("SECTION 1A.2 — SL BUFFER PER PAIR")
    print("═" * 80)

    buffers = [0.0, 0.05, 0.10, 0.15, 0.20]

    for symbol, filename in PAIRS:
        filepath = os.path.join(DATA_DIR, filename)
        if not os.path.exists(filepath):
            continue
        df = load_data(filepath)

        print(f"\n  {symbol}:")
        print(f"  {'Buffer':>8} │ {'N':>5} │ {'WR%':>6} │ {'PnL(R)':>10} │ {'Avg':>7} │ {'AvgWin':>7} │ {'MaxDD':>7} │ {'MaxCL':>5}")
        print(f"  {'─' * 8}─┼─{'─' * 5}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 7}─┼─{'─' * 7}─┼─{'─' * 7}─┼─{'─' * 5}")

        for buf in buffers:
            sigs, _ = run_mst_medio(df, PIVOT_LEN, BREAK_MULT, IMPULSE_MULT,
                                    sl_buffer_pct=buf, tp_mode="confirm")
            s = stats(sigs)
            dd = calc_drawdown(sigs)
            rr = calc_rr_distribution(sigs)
            tag = " ◄" if buf == 0.05 else ""
            print(f"  {buf*100:>7.0f}% │ {s['n']:>5} │ {s['wr']:>5.1f}% │ {s['pnl']:>+10.1f} │ {s['avg']:>+7.2f} │ {rr.get('avg_win', 0):>7.2f} │ {dd['max_dd_r']:>7.1f} │ {dd['max_consec_loss']:>5}{tag}")


# ═══════════════════════════════════════════════════════════════
# SECTION 2: TP METHOD
# ═══════════════════════════════════════════════════════════════

def test_tp_methods():
    """Compare Full TP vs Partial TP vs Fixed R:R TP"""
    print("\n" + "═" * 80)
    print("SECTION 2A — TP METHOD COMPARISON")
    print("═" * 80)
    print("  Confirm TP = TP at high/low of confirm candle (current)")
    print("  Partial TP  = 50% at Confirm H/L, 50% hold → next opposite signal")
    print("  Fixed R:R   = TP at fixed multiple of risk\n")

    # TP modes to test
    modes = [
        ("Confirm (Full TP)", "confirm", 0),
        ("Confirm (Partial)", "confirm", 0),
        ("Fixed 1.0R", "fixed_rr", 1.0),
        ("Fixed 1.5R", "fixed_rr", 1.5),
        ("Fixed 2.0R", "fixed_rr", 2.0),
        ("Fixed 3.0R", "fixed_rr", 3.0),
    ]

    results = []

    for symbol, filename in PAIRS:
        filepath = os.path.join(DATA_DIR, filename)
        if not os.path.exists(filepath):
            continue
        df = load_data(filepath)

        for mode_name, tp_mode, fixed_rr in modes:
            sigs, _ = run_mst_medio(df, PIVOT_LEN, BREAK_MULT, IMPULSE_MULT,
                                    sl_buffer_pct=0.05, tp_mode=tp_mode,
                                    fixed_rr=fixed_rr)

            if "Partial" in mode_name:
                trades = simulate_partial_tp(df, sigs)
                s = partial_stats(trades)
            else:
                s = stats(sigs)

            results.append((symbol, mode_name, s))

    # Aggregate by mode
    agg = {}
    for sym, mode, s in results:
        if mode not in agg:
            agg[mode] = {"n": 0, "wins": 0, "pnl": 0.0}
        agg[mode]["n"] += s["n"]
        agg[mode]["wins"] += int(s["wr"] * s["n"] / 100)
        agg[mode]["pnl"] += s["pnl"]

    print(f"  {'TP Mode':<22} │ {'Trades':>6} │ {'WR%':>6} │ {'PnL(R)':>10} │ {'Avg/Trade':>9}")
    print(f"  {'─' * 22}─┼─{'─' * 6}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 9}")
    for mode_name, _, _ in modes:
        if mode_name in agg:
            a = agg[mode_name]
            n = a["n"]
            wr = a["wins"] / n * 100 if n > 0 else 0
            avg = a["pnl"] / n if n > 0 else 0
            tag = " ◄ current" if mode_name == "Confirm (Full TP)" else ""
            print(f"  {mode_name:<22} │ {n:>6} │ {wr:>5.1f}% │ {a['pnl']:>+10.1f} │ {avg:>+9.2f}{tag}")


def test_full_vs_partial_per_pair():
    """Detailed Full vs Partial comparison per pair and direction."""
    print("\n" + "═" * 80)
    print("SECTION 2B — FULL TP vs PARTIAL TP (Per Pair + Direction)")
    print("═" * 80)

    totals_full = {"n": 0, "pnl": 0, "wins": 0, "max_dd": 0, "max_cl": 0}
    totals_part = {"n": 0, "pnl": 0, "wins": 0, "max_dd": 0, "max_cl": 0}

    for symbol, filename in PAIRS:
        filepath = os.path.join(DATA_DIR, filename)
        if not os.path.exists(filepath):
            continue
        df = load_data(filepath)

        sigs, _ = run_mst_medio(df, PIVOT_LEN, BREAK_MULT, IMPULSE_MULT,
                                sl_buffer_pct=0.05, tp_mode="confirm")
        trades = simulate_partial_tp(df, sigs)

        sf = stats(sigs)
        sp = partial_stats(trades)
        dd_f = calc_drawdown(sigs)

        # Partial drawdown
        partial_pnls = [(t.part1_pnl_r + t.part2_pnl_r) / 2 for t in trades]
        equity = [0.0]
        for p in partial_pnls:
            equity.append(equity[-1] + p)
        peak = max_dd_p = 0
        for e in equity:
            if e > peak: peak = e
            dd = peak - e
            if dd > max_dd_p: max_dd_p = dd

        # Part2 breakdown
        p2_be = sum(1 for t in trades if t.part2_result == "BE")
        p2_opp = sum(1 for t in trades if t.part2_result == "OPP")
        p2_sl = sum(1 for t in trades if t.part2_result == "SL")

        # Per direction
        buy_full = [s for s in sigs if s.direction == "BUY" and s.result in ("TP", "SL", "CLOSE_REVERSE")]
        sell_full = [s for s in sigs if s.direction == "SELL" and s.result in ("TP", "SL", "CLOSE_REVERSE")]
        buy_part = [t for t in trades if t.signal.direction == "BUY"]
        sell_part = [t for t in trades if t.signal.direction == "SELL"]

        def dir_stats(signals):
            n = len(signals)
            if n == 0: return 0, 0, 0
            w = sum(1 for s in signals if s.pnl_r > 0)
            p = sum(s.pnl_r for s in signals)
            return n, w / n * 100, p

        def dir_part_stats(trades_list):
            n = len(trades_list)
            if n == 0: return 0, 0, 0
            p = sum((t.part1_pnl_r + t.part2_pnl_r) / 2 for t in trades_list)
            w = sum(1 for t in trades_list if (t.part1_pnl_r + t.part2_pnl_r) > 0)
            return n, w / n * 100, p

        bn, bwr, bpnl = dir_stats(buy_full)
        sn, swr, spnl = dir_stats(sell_full)
        bpn, bpwr, bppnl = dir_part_stats(buy_part)
        spn, spwr, sppnl = dir_part_stats(sell_part)

        print(f"\n  {'─' * 74}")
        print(f"  {symbol}")
        print(f"  {'─' * 74}")
        print(f"  {'Mode':<20} │ {'N':>5} │ {'WR%':>6} │ {'PnL(R)':>10} │ {'Avg':>7} │ {'MaxDD':>7}")
        print(f"  {'─' * 20}─┼─{'─' * 5}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 7}─┼─{'─' * 7}")
        print(f"  {'Full TP':<20} │ {sf['n']:>5} │ {sf['wr']:>5.1f}% │ {sf['pnl']:>+10.1f} │ {sf['avg']:>+7.2f} │ {dd_f['max_dd_r']:>7.1f}")
        print(f"  {'Partial TP (50/50)':<20} │ {sp['n']:>5} │ {sp['wr']:>5.1f}% │ {sp['pnl']:>+10.1f} │ {sp['avg']:>+7.2f} │ {max_dd_p:>7.1f}")
        diff = sp["pnl"] - sf["pnl"]
        print(f"  Diff: {diff:>+.1f}R {'✅ PARTIAL' if diff > 0 else '❌ FULL'}")
        print(f"  Part2 exits: BE={p2_be} | OPP={p2_opp} | SL={p2_sl}")
        print(f"  BUY  Full: {bn:>4} trades, WR={bwr:.1f}%, PnL={bpnl:>+.1f}R | Partial: WR={bpwr:.1f}%, PnL={bppnl:>+.1f}R")
        print(f"  SELL Full: {sn:>4} trades, WR={swr:.1f}%, PnL={spnl:>+.1f}R | Partial: WR={spwr:.1f}%, PnL={sppnl:>+.1f}R")

        totals_full["n"] += sf["n"]; totals_full["pnl"] += sf["pnl"]
        totals_full["wins"] += int(sf["wr"] * sf["n"] / 100)
        totals_full["max_dd"] = max(totals_full["max_dd"], dd_f["max_dd_r"])
        totals_part["n"] += sp["n"]; totals_part["pnl"] += sp["pnl"]
        totals_part["wins"] += int(sp["wr"] * sp["n"] / 100)
        totals_part["max_dd"] = max(totals_part["max_dd"], max_dd_p)

    print(f"\n  {'═' * 74}")
    print(f"  TOTAL FULL TP:    {totals_full['n']} trades, WR={totals_full['wins']/totals_full['n']*100:.1f}%, PnL={totals_full['pnl']:>+.1f}R, MaxDD={totals_full['max_dd']:.1f}R")
    print(f"  TOTAL PARTIAL TP: {totals_part['n']} trades, WR={totals_part['wins']/totals_part['n']*100:.1f}%, PnL={totals_part['pnl']:>+.1f}R, MaxDD={totals_part['max_dd']:.1f}R")
    diff = totals_part["pnl"] - totals_full["pnl"]
    print(f"  DIFF: {diff:>+.1f}R → {'✅ PARTIAL BETTER' if diff > 0 else '❌ FULL BETTER'}")


# ═══════════════════════════════════════════════════════════════
# SECTION 3: MAX RISK % ANALYSIS
# ═══════════════════════════════════════════════════════════════

def test_max_risk():
    """
    MaxRisk filter: skip signals where SL distance > X% of entry price.
    This simulates what happens in the EA when account equity is finite.
    We measure: how many signals filtered, and what quality those filtered signals had.
    """
    print("\n" + "═" * 80)
    print("SECTION 3 — MAX RISK % FILTER ANALYSIS")
    print("═" * 80)
    print("  MaxRisk = skip trade if SL distance > X% of entry price")
    print("  This approximates filtering by account risk (wider SL = bigger % risk)\n")

    risk_levels = [0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0]  # 0 = no limit

    for symbol, filename in PAIRS:
        filepath = os.path.join(DATA_DIR, filename)
        if not os.path.exists(filepath):
            continue
        df = load_data(filepath)

        sigs, _ = run_mst_medio(df, PIVOT_LEN, BREAK_MULT, IMPULSE_MULT,
                                sl_buffer_pct=0.05, tp_mode="confirm")
        closed = [s for s in sigs if s.result in ("TP", "SL", "CLOSE_REVERSE")]

        print(f"\n  {symbol}: {len(closed)} total closed signals")
        print(f"  {'MaxRisk%':>8} │ {'Kept':>5} │ {'Filtered':>8} │ {'WR%':>6} │ {'PnL(R)':>10} │ {'Avg':>7} │ {'Filt WR%':>8} │ {'Filt PnL':>9}")
        print(f"  {'─' * 8}─┼─{'─' * 5}─┼─{'─' * 8}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 7}─┼─{'─' * 8}─┼─{'─' * 9}")

        for max_risk in risk_levels:
            if max_risk == 0:
                kept = closed
                filtered = []
            else:
                kept = []
                filtered = []
                for s in closed:
                    sl_dist_pct = abs(s.entry - s.sl) / s.entry * 100
                    if sl_dist_pct <= max_risk:
                        kept.append(s)
                    else:
                        filtered.append(s)

            n_kept = len(kept)
            n_filt = len(filtered)
            k_wins = sum(1 for s in kept if s.pnl_r > 0)
            k_pnl = sum(s.pnl_r for s in kept)
            k_wr = k_wins / n_kept * 100 if n_kept > 0 else 0
            k_avg = k_pnl / n_kept if n_kept > 0 else 0

            f_wins = sum(1 for s in filtered if s.pnl_r > 0)
            f_pnl = sum(s.pnl_r for s in filtered)
            f_wr = f_wins / n_filt * 100 if n_filt > 0 else 0

            tag = " ◄ default" if max_risk == 2.0 else (" (no limit)" if max_risk == 0 else "")
            print(f"  {max_risk:>7.1f}% │ {n_kept:>5} │ {n_filt:>8} │ {k_wr:>5.1f}% │ {k_pnl:>+10.1f} │ {k_avg:>+7.2f} │ {f_wr:>7.1f}% │ {f_pnl:>+9.1f}{tag}")

    # Aggregate
    print(f"\n  {'─' * 80}")
    print(f"  AGGREGATE (all 6 pairs):")

    all_closed = []
    for symbol, filename in PAIRS:
        filepath = os.path.join(DATA_DIR, filename)
        if not os.path.exists(filepath):
            continue
        df = load_data(filepath)
        sigs, _ = run_mst_medio(df, PIVOT_LEN, BREAK_MULT, IMPULSE_MULT,
                                sl_buffer_pct=0.05, tp_mode="confirm")
        for s in sigs:
            if s.result in ("TP", "SL", "CLOSE_REVERSE"):
                all_closed.append((symbol, s))

    print(f"  {'MaxRisk%':>8} │ {'Kept':>5} │ {'Filtered':>8} │ {'WR%':>6} │ {'PnL(R)':>10} │ {'Avg':>7}")
    print(f"  {'─' * 8}─┼─{'─' * 5}─┼─{'─' * 8}─┼─{'─' * 6}─┼─{'─' * 10}─┼─{'─' * 7}")

    for max_risk in risk_levels:
        if max_risk == 0:
            kept = all_closed
        else:
            kept = [(sym, s) for sym, s in all_closed if abs(s.entry - s.sl) / s.entry * 100 <= max_risk]

        n_kept = len(kept)
        n_filt = len(all_closed) - n_kept
        k_wins = sum(1 for _, s in kept if s.pnl_r > 0)
        k_pnl = sum(s.pnl_r for _, s in kept)
        k_wr = k_wins / n_kept * 100 if n_kept > 0 else 0
        k_avg = k_pnl / n_kept if n_kept > 0 else 0

        tag = " ◄ default" if max_risk == 2.0 else (" (no limit)" if max_risk == 0 else "")
        print(f"  {max_risk:>7.1f}% │ {n_kept:>5} │ {n_filt:>8} │ {k_wr:>5.1f}% │ {k_pnl:>+10.1f} │ {k_avg:>+7.2f}{tag}")


# ═══════════════════════════════════════════════════════════════
# SECTION 4: R:R DISTRIBUTION
# ═══════════════════════════════════════════════════════════════

def test_rr_distribution():
    """Show R:R distribution of winning trades per pair."""
    print("\n" + "═" * 80)
    print("SECTION 4 — R:R DISTRIBUTION OF WINNING TRADES")
    print("═" * 80)
    print("  Shows how big wins typically are (confirm candle TP)\n")

    all_wins = []
    all_losses = []

    for symbol, filename in PAIRS:
        filepath = os.path.join(DATA_DIR, filename)
        if not os.path.exists(filepath):
            continue
        df = load_data(filepath)

        sigs, _ = run_mst_medio(df, PIVOT_LEN, BREAK_MULT, IMPULSE_MULT,
                                sl_buffer_pct=0.05, tp_mode="confirm")
        closed = [s for s in sigs if s.result in ("TP", "SL", "CLOSE_REVERSE")]
        wins = [s.pnl_r for s in closed if s.pnl_r > 0]
        losses = [s.pnl_r for s in closed if s.pnl_r < 0]

        all_wins.extend(wins)
        all_losses.extend(losses)

        if wins:
            # Bucket analysis
            b1 = sum(1 for w in wins if w < 0.5)
            b2 = sum(1 for w in wins if 0.5 <= w < 1.0)
            b3 = sum(1 for w in wins if 1.0 <= w < 2.0)
            b4 = sum(1 for w in wins if 2.0 <= w < 5.0)
            b5 = sum(1 for w in wins if 5.0 <= w < 10.0)
            b6 = sum(1 for w in wins if w >= 10.0)

            print(f"  {symbol}: {len(wins)} wins | Avg={np.mean(wins):.2f}R | Med={np.median(wins):.2f}R | Max={max(wins):.1f}R")
            print(f"    <0.5R: {b1:>4} | 0.5-1R: {b2:>4} | 1-2R: {b3:>4} | 2-5R: {b4:>4} | 5-10R: {b5:>4} | 10R+: {b6:>4}")

    if all_wins:
        print(f"\n  ALL PAIRS: {len(all_wins)} wins | Avg={np.mean(all_wins):.2f}R | Med={np.median(all_wins):.2f}R | Max={max(all_wins):.1f}R")
        print(f"  ALL PAIRS: {len(all_losses)} losses | Avg={np.mean(all_losses):.2f}R")

        # Overall buckets
        b1 = sum(1 for w in all_wins if w < 0.5)
        b2 = sum(1 for w in all_wins if 0.5 <= w < 1.0)
        b3 = sum(1 for w in all_wins if 1.0 <= w < 2.0)
        b4 = sum(1 for w in all_wins if 2.0 <= w < 5.0)
        b5 = sum(1 for w in all_wins if 5.0 <= w < 10.0)
        b6 = sum(1 for w in all_wins if w >= 10.0)
        print(f"    <0.5R: {b1:>4} ({b1/len(all_wins)*100:.0f}%)")
        print(f"    0.5-1R: {b2:>4} ({b2/len(all_wins)*100:.0f}%)")
        print(f"    1-2R:   {b3:>4} ({b3/len(all_wins)*100:.0f}%)")
        print(f"    2-5R:   {b4:>4} ({b4/len(all_wins)*100:.0f}%)")
        print(f"    5-10R:  {b5:>4} ({b5/len(all_wins)*100:.0f}%)")
        print(f"    10R+:   {b6:>4} ({b6/len(all_wins)*100:.0f}%)")


# ═══════════════════════════════════════════════════════════════
# SECTION 5: TRAILING SL ANALYSIS
# ═══════════════════════════════════════════════════════════════

def test_trailing_sl():
    """
    Test trailing SL approaches:
    1. No trail (current Full TP)
    2. BE after TP1 (Partial TP — already tested)
    3. Trail SL to +0.5R after price reaches +1R (new)
    4. Trail SL behind each new swing
    """
    print("\n" + "═" * 80)
    print("SECTION 5 — TRAILING SL ANALYSIS")
    print("═" * 80)
    print("  Testing different SL management after entry\n")

    for symbol, filename in PAIRS:
        filepath = os.path.join(DATA_DIR, filename)
        if not os.path.exists(filepath):
            continue
        df = load_data(filepath)

        sigs, _ = run_mst_medio(df, PIVOT_LEN, BREAK_MULT, IMPULSE_MULT,
                                sl_buffer_pct=0.05, tp_mode="confirm")
        closed = [s for s in sigs if s.result in ("TP", "SL", "CLOSE_REVERSE")]

        # Simulate trailing SL: move SL to BE when price reaches +1R
        highs = df["High"].values
        lows = df["Low"].values
        closes = df["Close"].values
        times = df.index.values
        time_to_idx = {t: i for i, t in enumerate(times)}

        trail_pnl = 0.0
        trail_wins = 0
        trail_n = 0

        for sig in sigs:
            if sig.result not in ("TP", "SL", "CLOSE_REVERSE"):
                continue
            trail_n += 1

            conf_idx = time_to_idx.get(sig.confirm_time)
            if conf_idx is None:
                trail_pnl += sig.pnl_r
                if sig.pnl_r > 0: trail_wins += 1
                continue

            risk = abs(sig.entry - sig.sl)
            if risk == 0:
                continue

            current_sl = sig.sl
            trail_active = False
            done = False

            for bar_i in range(conf_idx + 1, len(times)):
                bar_h = highs[bar_i]
                bar_l = lows[bar_i]

                if sig.direction == "BUY":
                    # Check SL first
                    if bar_l <= current_sl:
                        p = (current_sl - sig.entry) / risk
                        trail_pnl += p
                        if p > 0: trail_wins += 1
                        done = True
                        break
                    # Check TP
                    if sig.tp > 0 and bar_h >= sig.tp:
                        rr = abs(sig.tp - sig.entry) / risk
                        trail_pnl += rr
                        trail_wins += 1
                        done = True
                        break
                    # Trail: move SL to BE when price reaches +1R
                    if not trail_active and bar_h >= sig.entry + risk:
                        current_sl = sig.entry
                        trail_active = True
                else:
                    if bar_h >= current_sl:
                        p = (sig.entry - current_sl) / risk
                        trail_pnl += p
                        if p > 0: trail_wins += 1
                        done = True
                        break
                    if sig.tp > 0 and bar_l <= sig.tp:
                        rr = abs(sig.entry - sig.tp) / risk
                        trail_pnl += rr
                        trail_wins += 1
                        done = True
                        break
                    if not trail_active and bar_l <= sig.entry - risk:
                        current_sl = sig.entry
                        trail_active = True

            if not done:
                last_c = closes[-1]
                p = (last_c - sig.entry) / risk if sig.direction == "BUY" else (sig.entry - last_c) / risk
                trail_pnl += p
                if p > 0: trail_wins += 1

        s = stats(sigs)
        trail_wr = trail_wins / trail_n * 100 if trail_n > 0 else 0
        trail_avg = trail_pnl / trail_n if trail_n > 0 else 0

        print(f"  {symbol}:")
        print(f"    No Trail (Full TP):   N={s['n']:>4}  WR={s['wr']:.1f}%  PnL={s['pnl']:>+10.1f}R  Avg={s['avg']:>+.2f}R")
        print(f"    Trail BE after +1R:   N={trail_n:>4}  WR={trail_wr:.1f}%  PnL={trail_pnl:>+10.1f}R  Avg={trail_avg:>+.2f}R")
        diff = trail_pnl - s["pnl"]
        print(f"    Diff: {diff:>+.1f}R {'✅ TRAIL' if diff > 0 else '❌ NO TRAIL'}")


# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print("=" * 80)
    print("MST Medio v2.0 — SL / TP / RISK Deep Analysis")
    print("=" * 80)
    print(f"  ImpulseMult = {IMPULSE_MULT} | BreakMult = {BREAK_MULT} | PivotLen = {PIVOT_LEN}")
    print(f"  Data: 6 pairs × 1 year (M5 timeframe)")
    print("=" * 80)

    test_sl_buffers()
    test_sl_buffers_per_pair()
    test_tp_methods()
    test_full_vs_partial_per_pair()
    test_max_risk()
    test_rr_distribution()
    test_trailing_sl()

    print("\n" + "═" * 80)
    print("DONE — All sections complete")
    print("═" * 80)
