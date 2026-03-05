#!/usr/bin/env python3
"""
Regime Analyzer — Auto‐parameter optimizer for MT5 Trading Panel.

Connects to MetaTrader 5 via the MetaTrader5 Python package,
analyzes recent price history per symbol+timeframe,
classifies the market regime, and writes config INI files
that the MQL5 EA reads to adjust parameters in real‐time.

Usage:
    python regime_analyzer.py              # analyze all charts on Instance 1
    python regime_analyzer.py --instance 2 # analyze Instance 2
    python regime_analyzer.py --loop 300   # re‐analyze every 5 min

Requirements:
    pip install MetaTrader5 numpy pandas
"""

import argparse
import os
import sys
import time
from datetime import datetime
from pathlib import Path

import MetaTrader5 as mt5
import numpy as np
import pandas as pd


# ── MT5 Instance configuration ──────────────────────────────────────
INSTANCES = {
    1: {
        "terminal": r"C:\Program Files\MetaTrader 5 EXNESS\terminal64.exe",
        "files":    r"C:\Users\administrator\AppData\Roaming\MetaQuotes\Terminal"
                    r"\53785E099C927DB68A545C249CDBCE06\MQL5\Files",
        "label":    "Demo",
    },
    2: {
        "terminal": r"C:\MetaTrader 5 EXNESS Real\terminal64.exe",
        "files":    r"C:\MetaTrader 5 EXNESS Real\MQL5\Files",
        "label":    "EXNESS Real",
    },
}

# ── Analysis parameters ─────────────────────────────────────────────
LOOKBACK     = 500       # bars to analyze
ADX_PERIOD   = 14
ATR_PERIOD   = 14
EMA_FAST     = 20
EMA_SLOW     = 50

# ── Regime → parameter mapping ──────────────────────────────────────
#   Each regime maps to recommended EA parameters.
#   Risk is NOT changed (user controls risk $ manually).
REGIME_PARAMS = {
    "trending_strong": {
        "atr_mult":       1.5,
        "atr_min_mult":   0.3,
        "break_mult":     0.05,
        "be_start_mult":  0.8,    # BE trigger tighter
        "trail_min_dist": 0.3,    # trail closer
        "tp_atr_factor":  1.0,    # TP at 1× ATR
    },
    "trending_weak": {
        "atr_mult":       1.5,
        "atr_min_mult":   0.4,
        "break_mult":     0.10,
        "be_start_mult":  1.0,
        "trail_min_dist": 0.5,
        "tp_atr_factor":  1.0,
    },
    "ranging": {
        "atr_mult":       2.0,
        "atr_min_mult":   0.5,
        "break_mult":     0.15,
        "be_start_mult":  1.5,    # BE trigger wider (avoid chop)
        "trail_min_dist": 0.8,    # trail wider
        "tp_atr_factor":  0.5,    # TP at 0.5× ATR (quick exit)
    },
    "high_volatile": {
        "atr_mult":       2.5,
        "atr_min_mult":   0.3,
        "break_mult":     0.10,
        "be_start_mult":  1.2,
        "trail_min_dist": 0.5,
        "tp_atr_factor":  1.0,
    },
}


# ═════════════════════════════════════════════════════════════════════
# INDICATORS
# ═════════════════════════════════════════════════════════════════════

def calc_atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
    """Average True Range."""
    high = df["high"]
    low  = df["low"]
    close = df["close"]
    tr = pd.concat([
        high - low,
        (high - close.shift(1)).abs(),
        (low  - close.shift(1)).abs(),
    ], axis=1).max(axis=1)
    return tr.rolling(period).mean()


def calc_adx(df: pd.DataFrame, period: int = 14) -> pd.Series:
    """Average Directional Index (simplified Wilder)."""
    high  = df["high"]
    low   = df["low"]
    close = df["close"]

    up   = high - high.shift(1)
    down = low.shift(1) - low
    plus_dm  = np.where((up > down) & (up > 0), up, 0.0)
    minus_dm = np.where((down > up) & (down > 0), down, 0.0)

    tr = pd.concat([
        high - low,
        (high - close.shift(1)).abs(),
        (low  - close.shift(1)).abs(),
    ], axis=1).max(axis=1)

    atr_s   = tr.ewm(alpha=1/period, min_periods=period).mean()
    plus_s  = pd.Series(plus_dm).ewm(alpha=1/period, min_periods=period).mean()
    minus_s = pd.Series(minus_dm).ewm(alpha=1/period, min_periods=period).mean()

    plus_di  = 100 * plus_s / atr_s
    minus_di = 100 * minus_s / atr_s

    dx = (plus_di - minus_di).abs() / (plus_di + minus_di) * 100
    adx = dx.ewm(alpha=1/period, min_periods=period).mean()
    return adx


def calc_ema(series: pd.Series, period: int) -> pd.Series:
    return series.ewm(span=period, adjust=False).mean()


def atr_percentile(df: pd.DataFrame, period: int = 14, window: int = 100) -> float:
    """Return percentile rank of latest ATR vs recent ATR values."""
    atr_vals = calc_atr(df, period).dropna()
    if len(atr_vals) < window:
        return 50.0
    recent = atr_vals.iloc[-window:]
    current = atr_vals.iloc[-1]
    pct = (recent < current).sum() / len(recent) * 100
    return float(pct)


# ═════════════════════════════════════════════════════════════════════
# REGIME CLASSIFIER
# ═════════════════════════════════════════════════════════════════════

def classify_regime(df: pd.DataFrame) -> tuple[str, float]:
    """
    Classify market regime using ADX + ATR percentile + EMA slope.

    Returns: (regime_name, confidence)
        regime_name: trending_strong | trending_weak | ranging | high_volatile
        confidence:  0.0 .. 1.0
    """
    if len(df) < LOOKBACK // 2:
        return "unknown", 0.0

    adx = calc_adx(df, ADX_PERIOD)
    atr_pct = atr_percentile(df, ATR_PERIOD)

    ema_fast = calc_ema(df["close"], EMA_FAST)
    ema_slow = calc_ema(df["close"], EMA_SLOW)

    latest_adx = float(adx.iloc[-1]) if not np.isnan(adx.iloc[-1]) else 20.0
    ema_spread = float((ema_fast.iloc[-1] - ema_slow.iloc[-1]) / ema_slow.iloc[-1] * 100)

    # Decision tree
    if latest_adx >= 30 and abs(ema_spread) > 0.3:
        regime = "trending_strong"
        conf = min(1.0, latest_adx / 50)
    elif latest_adx >= 20 and abs(ema_spread) > 0.1:
        regime = "trending_weak"
        conf = min(1.0, latest_adx / 40)
    elif atr_pct >= 80:
        regime = "high_volatile"
        conf = min(1.0, atr_pct / 100)
    else:
        regime = "ranging"
        conf = min(1.0, (100 - latest_adx) / 80)

    return regime, round(conf, 2)


# ═════════════════════════════════════════════════════════════════════
# CONFIG WRITER
# ═════════════════════════════════════════════════════════════════════

def write_config(files_dir: str, symbol: str, timeframe: str,
                 regime: str, confidence: float):
    """Write config INI file for the EA to read."""
    params = REGIME_PARAMS.get(regime, REGIME_PARAMS["ranging"])

    fname = f"config_{symbol}_{timeframe}.ini"
    fpath = os.path.join(files_dir, fname)

    lines = [
        f"# Regime Analyzer — auto‐generated {datetime.now():%Y-%m-%d %H:%M:%S}",
        f"# Symbol: {symbol}  Timeframe: {timeframe}",
        f"regime={regime}",
        f"confidence={confidence:.2f}",
        f"atr_mult={params['atr_mult']:.2f}",
        f"atr_min_mult={params['atr_min_mult']:.2f}",
        f"break_mult={params['break_mult']:.2f}",
        f"be_start_mult={params['be_start_mult']:.2f}",
        f"trail_min_dist={params['trail_min_dist']:.2f}",
        f"tp_atr_factor={params['tp_atr_factor']:.2f}",
    ]

    os.makedirs(files_dir, exist_ok=True)
    with open(fpath, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(f"  [OK] {fname}  regime={regime}  conf={confidence:.2f}  "
          f"atrM={params['atr_mult']}  ccMin={params['atr_min_mult']}  "
          f"ccBrk={params['break_mult']}  BE={params['be_start_mult']}  "
          f"trD={params['trail_min_dist']}  TP={params['tp_atr_factor']}")


# ═════════════════════════════════════════════════════════════════════
# MT5 TIMEFRAME MAPPING
# ═════════════════════════════════════════════════════════════════════

TF_MAP = {
    mt5.TIMEFRAME_M1:  "M1",
    mt5.TIMEFRAME_M5:  "M5",
    mt5.TIMEFRAME_M15: "M15",
    mt5.TIMEFRAME_M30: "M30",
    mt5.TIMEFRAME_H1:  "H1",
    mt5.TIMEFRAME_H4:  "H4",
    mt5.TIMEFRAME_D1:  "D1",
    mt5.TIMEFRAME_W1:  "W1",
    mt5.TIMEFRAME_MN1: "MN1",
}

TF_FROM_NAME = {v: k for k, v in TF_MAP.items()}


# ═════════════════════════════════════════════════════════════════════
# MAIN LOGIC
# ═════════════════════════════════════════════════════════════════════

def get_open_charts() -> list[tuple[str, int]]:
    """
    Get list of (symbol, timeframe_mt5) from all open charts.
    Returns unique pairs.
    """
    charts = []
    seen = set()

    # Iterate through all chart windows
    chart_id = mt5.terminal_info()
    if chart_id is None:
        return charts

    # MT5 Python doesn't expose chart list directly.
    # Alternative: use symbols_get() + user‐specified timeframes.
    # For now, we analyze the symbol the EA is attached to.
    # The EA writes which symbol+TF it's on via the filename pattern.
    return charts


def analyze_symbol(symbol: str, tf_name: str, files_dir: str):
    """Fetch bars, classify regime, write config."""
    tf_mt5 = TF_FROM_NAME.get(tf_name)
    if tf_mt5 is None:
        print(f"  [SKIP] Unknown timeframe: {tf_name}")
        return

    rates = mt5.copy_rates_from_pos(symbol, tf_mt5, 0, LOOKBACK)
    if rates is None or len(rates) < 100:
        print(f"  [SKIP] {symbol} {tf_name}: insufficient data ({0 if rates is None else len(rates)} bars)")
        return

    df = pd.DataFrame(rates)
    df["time"] = pd.to_datetime(df["time"], unit="s")

    regime, conf = classify_regime(df)
    write_config(files_dir, symbol, tf_name, regime, conf)


def analyze_instance(inst_id: int, symbols: list[str] | None = None,
                     timeframes: list[str] | None = None):
    """Connect to an MT5 instance and analyze specified symbols/timeframes."""
    inst = INSTANCES[inst_id]
    terminal_path = inst["terminal"]
    files_dir = inst["files"]

    print(f"\n{'='*60}")
    print(f"Instance {inst_id}: {inst['label']}  ({terminal_path})")
    print(f"{'='*60}")

    if not mt5.initialize(path=terminal_path):
        print(f"  [ERROR] Cannot connect to MT5 instance {inst_id}: {mt5.last_error()}")
        return False

    info = mt5.terminal_info()
    acct = mt5.account_info()
    print(f"  Connected: {info.name}  Account: {acct.login}  Balance: ${acct.balance:.2f}")

    # Default: common EXNESS symbols
    if symbols is None:
        symbols = ["XAUUSDm"]

    if timeframes is None:
        timeframes = ["M15"]

    for sym in symbols:
        # Verify symbol exists
        sym_info = mt5.symbol_info(sym)
        if sym_info is None:
            print(f"  [SKIP] {sym}: symbol not found")
            continue
        if not sym_info.visible:
            mt5.symbol_select(sym, True)

        for tf in timeframes:
            print(f"\n  Analyzing {sym} {tf} ...")
            analyze_symbol(sym, tf, files_dir)

    mt5.shutdown()
    return True


def main():
    parser = argparse.ArgumentParser(description="Regime Analyzer for MT5 Trading Panel")
    parser.add_argument("--instance", type=int, default=1, choices=[1, 2],
                        help="MT5 instance (1=Demo, 2=EXNESS Real)")
    parser.add_argument("--symbols", type=str, default="XAUUSDm",
                        help="Comma‐separated symbols (e.g. XAUUSDm,BTCUSDm)")
    parser.add_argument("--timeframes", type=str, default="M15",
                        help="Comma‐separated timeframes (e.g. M15,H1)")
    parser.add_argument("--loop", type=int, default=0,
                        help="Re‐analyze every N seconds (0=run once)")
    parser.add_argument("--all", action="store_true",
                        help="Analyze on both instances")

    args = parser.parse_args()

    symbols = [s.strip() for s in args.symbols.split(",")]
    timeframes = [t.strip() for t in args.timeframes.split(",")]

    instances_to_run = [1, 2] if args.all else [args.instance]

    while True:
        print(f"\n{'#'*60}")
        print(f"# Regime Analyzer  {datetime.now():%Y-%m-%d %H:%M:%S}")
        print(f"{'#'*60}")

        for inst_id in instances_to_run:
            analyze_instance(inst_id, symbols, timeframes)

        if args.loop <= 0:
            break

        print(f"\nNext run in {args.loop}s ...")
        time.sleep(args.loop)

    print("\nDone.")


if __name__ == "__main__":
    main()
