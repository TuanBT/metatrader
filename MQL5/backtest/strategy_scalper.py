"""
strategy_scalper.py — Scalper: EMA Crossover + RSI Filter

Logic:
1. EMA Fast (9) crosses above EMA Slow (21) + Price > EMA Trend (50) → BUY
2. EMA Fast (9) crosses below EMA Slow (21) + Price < EMA Trend (50) → SELL
3. RSI filter: Skip BUY if RSI > OB, skip SELL if RSI < OS
4. SL = ATR × multiplier below/above entry
5. TP = SL distance × RR ratio

Designed for M15 timeframe, high frequency (~15-20 trades/month).
"""

import pandas as pd
import numpy as np
from typing import Optional, Dict
from engine import BacktestEngine, calc_ema, calc_rsi, calc_atr, load_data, resample, filter_date_range


def run_scalper(
    symbol: str = "EURUSDm",
    timeframe: str = "M15",
    start_date: str = None,
    end_date: str = None,
    # Strategy params
    ema_fast: int = 9,
    ema_slow: int = 21,
    ema_trend: int = 50,
    rsi_period: int = 14,
    rsi_ob: float = 70.0,
    rsi_os: float = 30.0,
    atr_period: int = 14,
    atr_sl_mult: float = 1.5,
    tp_rr: float = 1.5,
    min_sl_pips: float = 5.0,
    # Engine params
    initial_balance: float = 500.0,
    lot_size: float = 0.02,
    max_risk_pct: float = 5.0,
    partial_tp_r: float = 0.5,
    be_at_r: float = 0.5,
    max_positions: int = 1,
    daily_loss_limit: float = 3.0,
    verbose: bool = False,
) -> BacktestEngine:
    """
    Run Scalper backtest.
    
    Returns:
        BacktestEngine with results
    """
    # Load data
    df = load_data(symbol, "M5")
    if timeframe != "M5":
        df = resample(df, timeframe)
    df = filter_date_range(df, start_date, end_date)
    
    if len(df) < ema_trend + 10:
        print(f"⚠️  Not enough data ({len(df)} bars)")
        return None
    
    # Calculate indicators
    df["ema_fast"] = calc_ema(df["Close"], ema_fast)
    df["ema_slow"] = calc_ema(df["Close"], ema_slow)
    df["ema_trend"] = calc_ema(df["Close"], ema_trend)
    df["rsi"] = calc_rsi(df["Close"], rsi_period)
    df["atr"] = calc_atr(df, atr_period)
    
    # Drop warm-up period
    warmup = max(ema_trend, atr_period, rsi_period) + 5
    df = df.iloc[warmup:]
    
    # Initialize engine
    engine = BacktestEngine(
        symbol=symbol,
        initial_balance=initial_balance,
        lot_size=lot_size,
        max_risk_pct=max_risk_pct,
        partial_tp_r=partial_tp_r,
        be_at_r=be_at_r,
        daily_loss_limit=daily_loss_limit,
        max_positions=max_positions,
    )
    
    # Get arrays for fast access
    times = df.index
    opens = df["Open"].values
    highs = df["High"].values
    lows = df["Low"].values
    closes = df["Close"].values
    ema_f = df["ema_fast"].values
    ema_s = df["ema_slow"].values
    ema_t = df["ema_trend"].values
    rsi_vals = df["rsi"].values
    atr_vals = df["atr"].values
    
    n = len(df)
    signals_generated = 0
    signals_filtered_rsi = 0
    signals_filtered_trend = 0
    signals_filtered_risk = 0
    
    for i in range(1, n):
        t = times[i]
        o, h, l, c = opens[i], highs[i], lows[i], closes[i]
        
        # Process existing positions first
        engine.process_bar(t, o, h, l, c)
        
        # --- Signal detection (use previous bar's indicators) ---
        prev_ema_f = ema_f[i-1]
        prev_ema_s = ema_s[i-1]
        prev2_ema_f = ema_f[i-2] if i >= 2 else prev_ema_f
        prev2_ema_s = ema_s[i-2] if i >= 2 else prev_ema_s
        prev_rsi = rsi_vals[i-1]
        prev_atr = atr_vals[i-1]
        prev_close = closes[i-1]
        prev_ema_t = ema_t[i-1]
        
        if prev_atr <= 0 or np.isnan(prev_atr):
            continue
        
        # EMA crossover detection (on previous bar close)
        cross_up = prev2_ema_f <= prev2_ema_s and prev_ema_f > prev_ema_s
        cross_down = prev2_ema_f >= prev2_ema_s and prev_ema_f < prev_ema_s
        
        signal = None
        
        if cross_up:
            signals_generated += 1
            # Trend filter: price must be above EMA trend
            if prev_close < prev_ema_t:
                signals_filtered_trend += 1
                continue
            # RSI filter: skip if overbought
            if prev_rsi > rsi_ob:
                signals_filtered_rsi += 1
                continue
            signal = "BUY"
            
        elif cross_down:
            signals_generated += 1
            # Trend filter: price must be below EMA trend
            if prev_close > prev_ema_t:
                signals_filtered_trend += 1
                continue
            # RSI filter: skip if oversold
            if prev_rsi < rsi_os:
                signals_filtered_rsi += 1
                continue
            signal = "SELL"
        
        if signal is None:
            continue
        
        # Calculate entry, SL, TP
        entry = o  # Market order at next bar open
        sl_dist = prev_atr * atr_sl_mult
        
        # Min SL distance
        min_sl_dist = min_sl_pips * engine.pip
        if sl_dist < min_sl_dist:
            sl_dist = min_sl_dist
        
        if signal == "BUY":
            sl = entry - sl_dist
            tp = entry + sl_dist * tp_rr
        else:
            sl = entry + sl_dist
            tp = entry - sl_dist * tp_rr
        
        # Try to open position
        pos = engine.open_position(t, signal, entry, sl, tp)
        if pos is None:
            signals_filtered_risk += 1
        elif verbose:
            print(f"  📈 {t} {signal} @ {entry:.{engine.digits}f}  SL={sl:.{engine.digits}f}  TP={tp:.{engine.digits}f}")
    
    # Close any remaining positions at last close
    if engine.positions:
        engine.close_all(times[-1], closes[-1], "END")
    
    # Print funnel
    print(f"\n  Signal Funnel:")
    print(f"    Total crossovers:   {signals_generated}")
    print(f"    Filtered (trend):   {signals_filtered_trend}")
    print(f"    Filtered (RSI):     {signals_filtered_rsi}")
    print(f"    Filtered (risk):    {signals_filtered_risk}")
    print(f"    Trades opened:      {len(engine.trades) + len(engine.positions)}")
    
    return engine


if __name__ == "__main__":
    import sys
    
    symbols = ["EURUSDm", "XAUUSDm", "USDJPYm"]
    start = "2023-01-01"
    end = "2026-01-01"
    
    if len(sys.argv) > 1:
        symbols = [sys.argv[1]]
    
    for sym in symbols:
        print(f"\n{'#'*60}")
        print(f"  Scalper — {sym} M15")
        print(f"  Period: {start} → {end}")
        print(f"{'#'*60}")
        
        try:
            engine = run_scalper(
                symbol=sym,
                timeframe="M15",
                start_date=start,
                end_date=end,
            )
            if engine:
                engine.print_summary(f"Scalper — {sym} M15")
                engine.print_trades(last_n=10)
        except FileNotFoundError as e:
            print(f"  ⚠️  {e}")
