"""Quick MaxRisk 2% analysis on multi-year data."""
import sys, os

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_TV_BACKTEST = os.path.join(_THIS_DIR, "..", "..", "..", "..", "tradingview", "MST Medio", "backtest")
sys.path.insert(0, _TV_BACKTEST)

import pandas as pd
from strategy_mst_medio import run_mst_medio, Signal

DATA_DIR = os.path.join(_THIS_DIR, "..", "..", "..", "candle data")
PAIRS = [
    ("XAUUSD", "XAUUSDm_M5.csv"),
    ("BTCUSD", "BTCUSDm_M5.csv"),
    ("ETHUSD", "ETHUSDm_M5.csv"),
    ("USOIL",  "USOILm_M5.csv"),
    ("EURUSD", "EURUSDm_M5.csv"),
    ("USDJPY", "USDJPYm_M5.csv"),
]

def load_data(path):
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

print("=" * 90)
print("MaxRisk 2% Filter Analysis — Multi-Year Data (8-12 years)")
print("=" * 90)
print("  MaxRisk = skip trade if SL distance > X% of entry price")
print()

risk_levels = [0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0]
all_closed_global = []

for symbol, filename in PAIRS:
    filepath = os.path.join(DATA_DIR, filename)
    if not os.path.exists(filepath):
        continue
    df = load_data(filepath)
    sigs, _ = run_mst_medio(df, 5, 0.25, 1.0, sl_buffer_pct=0.05, tp_mode="confirm")
    closed = [s for s in sigs if s.result in ("TP", "SL", "CLOSE_REVERSE")]

    print(f"\n  {symbol}: {len(closed)} total trades")
    print(f"  {'MaxRisk%':>8} │ {'Kept':>6} │ {'Filtered':>8} │ {'WR%':>6} │ {'PnL(R)':>10} │ {'Avg/T':>7} │ {'Filt WR%':>8} │ {'Filt PnL':>10}")
    print(f"  {'─'*8}─┼─{'─'*6}─┼─{'─'*8}─┼─{'─'*6}─┼─{'─'*10}─┼─{'─'*7}─┼─{'─'*8}─┼─{'─'*10}")

    for mr in risk_levels:
        if mr == 0:
            kept, filt = closed, []
        else:
            kept = [s for s in closed if abs(s.entry - s.sl) / s.entry * 100 <= mr]
            filt = [s for s in closed if abs(s.entry - s.sl) / s.entry * 100 > mr]
        
        nk, nf = len(kept), len(filt)
        k_w = sum(1 for s in kept if s.pnl_r > 0)
        k_pnl = sum(s.pnl_r for s in kept)
        k_wr = k_w / nk * 100 if nk else 0
        k_avg = k_pnl / nk if nk else 0
        f_w = sum(1 for s in filt if s.pnl_r > 0)
        f_pnl = sum(s.pnl_r for s in filt)
        f_wr = f_w / nf * 100 if nf else 0
        tag = " ◄ default" if mr == 2.0 else (" (no limit)" if mr == 0 else "")
        print(f"  {mr:>7.1f}% │ {nk:>6} │ {nf:>8} │ {k_wr:>5.1f}% │ {k_pnl:>+10.1f} │ {k_avg:>+7.2f} │ {f_wr:>7.1f}% │ {f_pnl:>+10.1f}{tag}")

    for s in closed:
        all_closed_global.append((symbol, s))

# Aggregate
print(f"\n{'─'*90}")
print(f"  AGGREGATE ALL 6 PAIRS: {len(all_closed_global)} total trades")
print(f"  {'MaxRisk%':>8} │ {'Kept':>6} │ {'Filtered':>8} │ {'Filter%':>7} │ {'WR%':>6} │ {'PnL(R)':>10} │ {'Avg/T':>7} │ {'Filt WR%':>8} │ {'Filt PnL':>10}")
print(f"  {'─'*8}─┼─{'─'*6}─┼─{'─'*8}─┼─{'─'*7}─┼─{'─'*6}─┼─{'─'*10}─┼─{'─'*7}─┼─{'─'*8}─┼─{'─'*10}")

for mr in risk_levels:
    if mr == 0:
        kept = all_closed_global
    else:
        kept = [(sym, s) for sym, s in all_closed_global if abs(s.entry - s.sl) / s.entry * 100 <= mr]
    
    nk = len(kept)
    nf = len(all_closed_global) - nk
    filt_pct = nf / len(all_closed_global) * 100
    k_w = sum(1 for _, s in kept if s.pnl_r > 0)
    k_pnl = sum(s.pnl_r for _, s in kept)
    k_wr = k_w / nk * 100 if nk else 0
    k_avg = k_pnl / nk if nk else 0
    
    f_pnl = sum(s.pnl_r for _, s in all_closed_global) - k_pnl if mr > 0 else 0
    f_w = sum(1 for _, s in all_closed_global if s.pnl_r > 0) - sum(1 for _, s in kept if s.pnl_r > 0) if mr > 0 else 0
    f_wr = f_w / nf * 100 if nf else 0
    
    tag = " ◄ default" if mr == 2.0 else (" (no limit)" if mr == 0 else "")
    print(f"  {mr:>7.1f}% │ {nk:>6} │ {nf:>8} │ {filt_pct:>6.1f}% │ {k_wr:>5.1f}% │ {k_pnl:>+10.1f} │ {k_avg:>+7.2f} │ {f_wr:>7.1f}% │ {f_pnl:>+10.1f}{tag}")

# SL distance distribution
print(f"\n{'─'*90}")
print("  SL DISTANCE DISTRIBUTION (% of entry price):")
all_sl_pct = [abs(s.entry - s.sl) / s.entry * 100 for _, s in all_closed_global]
import numpy as np
percentiles = [25, 50, 75, 90, 95, 99, 100]
print(f"    Min: {min(all_sl_pct):.3f}%")
for p in percentiles:
    v = np.percentile(all_sl_pct, p)
    print(f"    P{p:>3}: {v:.3f}%")
print(f"    Mean: {np.mean(all_sl_pct):.3f}%")
