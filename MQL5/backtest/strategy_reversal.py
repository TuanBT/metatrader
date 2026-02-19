"""
strategy_reversal.py — Reversal: Bollinger Band + RSI Mean Reversion

Logic:
1. Price closes below Lower BB + RSI < OS → potential BUY zone
2. Next bar: reversal candle (close > open for BUY) → BUY at close
3. SL = Low of signal bar - ATR buffer
4. TP = Middle BB (dynamic, updates each bar)
5. Same logic inverted for SELL

Designed for H1 timeframe, mean-reversion (~5-10 trades/month).
"""

import pandas as pd
import numpy as np
from typing import Optional, Dict
from engine import BacktestEngine, calc_bollinger, calc_rsi, calc_atr, load_data, resample, filter_date_range


def run_reversal(
    symbol: str = "EURUSDm",
    timeframe: str = "H1",
    start_date: str = None,
    end_date: str = None,
    # Strategy params
    bb_period: int = 20,
    bb_deviation: float = 2.0,
    rsi_period: int = 14,
    rsi_ob: float = 70.0,
    rsi_os: float = 30.0,
    require_reversal: bool = True,
    atr_period: int = 14,
    sl_atr_buffer: float = 0.5,
    use_mid_bb_tp: bool = True,
    fixed_tp_rr: float = 1.5,        # Used when use_mid_bb_tp=False
    min_sl_pips: float = 10.0,
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
    Run Reversal backtest.
    
    Returns:
        BacktestEngine with results
    """
    # Load data
    df = load_data(symbol, "H1" if timeframe in ["H1", "H4"] else "M5")
    if timeframe not in ["H1", "M5"]:
        df = resample(df, timeframe)
    df = filter_date_range(df, start_date, end_date)
    
    if len(df) < bb_period + 10:
        print(f"⚠️  Not enough data ({len(df)} bars)")
        return None
    
    # Calculate indicators
    df["bb_upper"], df["bb_mid"], df["bb_lower"] = calc_bollinger(df["Close"], bb_period, bb_deviation)
    df["rsi"] = calc_rsi(df["Close"], rsi_period)
    df["atr"] = calc_atr(df, atr_period)
    
    # Drop warm-up
    warmup = max(bb_period, atr_period, rsi_period) + 5
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
    
    # Arrays
    times = df.index
    opens = df["Open"].values
    highs = df["High"].values
    lows = df["Low"].values
    closes = df["Close"].values
    bb_upper = df["bb_upper"].values
    bb_mid = df["bb_mid"].values
    bb_lower = df["bb_lower"].values
    rsi_vals = df["rsi"].values
    atr_vals = df["atr"].values
    
    n = len(df)
    zone_detected = 0
    reversal_confirmed = 0
    signals_filtered_risk = 0
    
    # State: waiting for reversal candle after zone detection
    pending_zone = None  # ("BUY" or "SELL", bar_index)
    
    for i in range(2, n):
        t = times[i]
        o, h, l, c = opens[i], highs[i], lows[i], closes[i]
        
        # Process existing positions
        engine.process_bar(t, o, h, l, c)
        
        # Dynamic TP update: move TP to current middle BB
        if use_mid_bb_tp and engine.positions:
            for pos in engine.positions:
                current_mid = bb_mid[i]
                if pos.direction == "BUY" and current_mid > pos.entry:
                    engine.update_tp(pos, current_mid)
                elif pos.direction == "SELL" and current_mid < pos.entry:
                    engine.update_tp(pos, current_mid)
        
        # --- Zone Detection (bar i-1) ---
        prev_close = closes[i-1]
        prev_low = lows[i-1]
        prev_high = highs[i-1]
        prev_rsi = rsi_vals[i-1]
        prev_bb_lower = bb_lower[i-1]
        prev_bb_upper = bb_upper[i-1]
        prev_atr = atr_vals[i-1]
        
        if prev_atr <= 0 or np.isnan(prev_atr):
            continue
        
        # Check for zone on previous completed bar
        buy_zone = prev_close < prev_bb_lower and prev_rsi < rsi_os
        sell_zone = prev_close > prev_bb_upper and prev_rsi > rsi_ob
        
        if buy_zone or sell_zone:
            zone_detected += 1
            direction = "BUY" if buy_zone else "SELL"
            
            if require_reversal:
                # Wait: check if CURRENT bar is a reversal candle
                is_reversal = False
                if direction == "BUY":
                    # Bullish reversal: close > open (green candle)
                    is_reversal = c > o
                else:
                    # Bearish reversal: close < open (red candle)
                    is_reversal = c < o
                
                if not is_reversal:
                    continue
            
            reversal_confirmed += 1
            
            # Calculate entry, SL, TP
            entry = c  # Enter at current bar close
            sl_buffer = prev_atr * sl_atr_buffer
            min_sl_dist = min_sl_pips * engine.pip
            
            if direction == "BUY":
                # SL below the low of the zone bar
                sl = prev_low - sl_buffer
                sl_dist = entry - sl
                if sl_dist < min_sl_dist:
                    sl = entry - min_sl_dist
                    sl_dist = min_sl_dist
                
                if use_mid_bb_tp:
                    tp = bb_mid[i]
                    # Make sure TP > entry
                    if tp <= entry:
                        tp = entry + sl_dist * fixed_tp_rr
                else:
                    tp = entry + sl_dist * fixed_tp_rr
            else:
                sl = prev_high + sl_buffer
                sl_dist = sl - entry
                if sl_dist < min_sl_dist:
                    sl = entry + min_sl_dist
                    sl_dist = min_sl_dist
                
                if use_mid_bb_tp:
                    tp = bb_mid[i]
                    if tp >= entry:
                        tp = entry - sl_dist * fixed_tp_rr
                else:
                    tp = entry - sl_dist * fixed_tp_rr
            
            pos = engine.open_position(t, direction, entry, sl, tp)
            if pos is None:
                signals_filtered_risk += 1
            elif verbose:
                print(f"  📊 {t} {direction} @ {entry:.{engine.digits}f}  SL={sl:.{engine.digits}f}  TP={tp:.{engine.digits}f}  (BB mid={bb_mid[i]:.{engine.digits}f})")
    
    # Close remaining
    if engine.positions:
        engine.close_all(times[-1], closes[-1], "END")
    
    # Print funnel
    print(f"\n  Signal Funnel:")
    print(f"    BB+RSI zones:       {zone_detected}")
    print(f"    Reversal confirmed: {reversal_confirmed}")
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
        print(f"  Reversal — {sym} H1")
        print(f"  Period: {start} → {end}")
        print(f"{'#'*60}")
        
        try:
            engine = run_reversal(
                symbol=sym,
                timeframe="H1",
                start_date=start,
                end_date=end,
            )
            if engine:
                engine.print_summary(f"Reversal — {sym} H1")
                engine.print_trades(last_n=10)
        except FileNotFoundError as e:
            print(f"  ⚠️  {e}")
