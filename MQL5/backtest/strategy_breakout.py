"""
strategy_breakout.py — Breakout: Session Range Breakout

Logic:
1. Asian session (00:00-08:00 GMT): Record highest High / lowest Low
2. At 08:00: Lock the range
3. London/NY session (08:00-18:00):
   - Price closes above range high + buffer → BUY
   - Price closes below range low - buffer → SELL
4. SL = Opposite side of range + % buffer
5. TP = SL distance × RR
6. EOD: Close all positions at 22:00

Designed for M15 timeframe (~1 trade/day = ~20 trades/month).
"""

import pandas as pd
import numpy as np
from typing import Optional, Dict
from engine import BacktestEngine, calc_atr, load_data, resample, filter_date_range


def run_breakout(
    symbol: str = "EURUSDm",
    timeframe: str = "M15",
    start_date: str = None,
    end_date: str = None,
    # Session params (in server time)
    range_start_hour: int = 0,
    range_end_hour: int = 8,
    trade_start_hour: int = 8,
    trade_end_hour: int = 18,
    eod_close_hour: int = 22,
    gmt_offset: int = 2,        # Broker offset from GMT (Exness = UTC+2 typically)
    # Strategy params
    breakout_buffer_pips: float = 3.0,
    min_range_pips: float = 30.0,
    max_range_pips: float = 500.0,
    sl_buffer_pct: float = 10.0,  # SL buffer as % of range
    tp_rr: float = 1.5,
    max_trades_per_day: int = 2,
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
    Run Breakout backtest.
    
    Returns:
        BacktestEngine with results
    """
    # Load data
    df = load_data(symbol, "M5")
    if timeframe != "M5":
        df = resample(df, timeframe)
    df = filter_date_range(df, start_date, end_date)
    
    if len(df) < 100:
        print(f"⚠️  Not enough data ({len(df)} bars)")
        return None
    
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
    
    # Adjust hours for GMT offset
    adj_range_start = (range_start_hour + gmt_offset) % 24
    adj_range_end = (range_end_hour + gmt_offset) % 24
    adj_trade_start = (trade_start_hour + gmt_offset) % 24
    adj_trade_end = (trade_end_hour + gmt_offset) % 24
    adj_eod = (eod_close_hour + gmt_offset) % 24
    
    # Arrays
    times = df.index
    opens = df["Open"].values
    highs = df["High"].values
    lows = df["Low"].values
    closes = df["Close"].values
    
    n = len(df)
    pip = engine.pip
    
    # Daily state
    current_date = None
    range_high = -np.inf
    range_low = np.inf
    range_locked = False
    trades_today = 0
    
    # Stats
    total_days = 0
    range_days = 0
    breakout_signals = 0
    filtered_range_size = 0
    filtered_max_trades = 0
    filtered_risk = 0
    
    def in_range(hour, start, end):
        """Check if hour is in the session range (handles midnight wrap)."""
        if start <= end:
            return start <= hour < end
        else:
            return hour >= start or hour < end
    
    for i in range(n):
        t = times[i]
        o, h, l, c = opens[i], highs[i], lows[i], closes[i]
        hour = t.hour
        bar_date = t.date()
        
        # Process existing positions
        engine.process_bar(t, o, h, l, c)
        
        # --- Daily reset ---
        if bar_date != current_date:
            current_date = bar_date
            range_high = -np.inf
            range_low = np.inf
            range_locked = False
            trades_today = 0
            total_days += 1
        
        # --- EOD Close ---
        if hour >= adj_eod and engine.positions:
            engine.close_all(t, c, "EOD")
        
        # --- Range building phase ---
        if in_range(hour, adj_range_start, adj_range_end):
            if h > range_high:
                range_high = h
            if l < range_low:
                range_low = l
        
        # --- Lock range at transition ---
        if not range_locked and hour >= adj_range_end and range_high > -np.inf:
            range_locked = True
            range_size_pips = (range_high - range_low) / pip
            
            if range_size_pips >= min_range_pips and range_size_pips <= max_range_pips:
                range_days += 1
            else:
                filtered_range_size += 1
                range_locked = False  # Invalidate this day's range
        
        # --- Breakout detection (trade session) ---
        if not range_locked:
            continue
        
        if not in_range(hour, adj_trade_start, adj_trade_end):
            continue
        
        range_size_pips = (range_high - range_low) / pip
        if range_size_pips < min_range_pips or range_size_pips > max_range_pips:
            continue
        
        if trades_today >= max_trades_per_day:
            if c > range_high + breakout_buffer_pips * pip or c < range_low - breakout_buffer_pips * pip:
                filtered_max_trades += 1
            continue
        
        # Skip if already in a position
        if engine.positions:
            continue
        
        buffer = breakout_buffer_pips * pip
        sl_buffer = (range_high - range_low) * (sl_buffer_pct / 100.0)
        
        signal = None
        entry = None
        sl = None
        tp = None
        
        # BUY: Close above range high + buffer
        if c > range_high + buffer:
            signal = "BUY"
            entry = c
            sl = range_low - sl_buffer
            sl_dist = entry - sl
            tp = entry + sl_dist * tp_rr
        
        # SELL: Close below range low - buffer
        elif c < range_low - buffer:
            signal = "SELL"
            entry = c
            sl = range_high + sl_buffer
            sl_dist = sl - entry
            tp = entry - sl_dist * tp_rr
        
        if signal is None:
            continue
        
        breakout_signals += 1
        
        pos = engine.open_position(t, signal, entry, sl, tp)
        if pos:
            trades_today += 1
            if verbose:
                print(f"  🔥 {t} {signal} @ {entry:.{engine.digits}f}  SL={sl:.{engine.digits}f}  TP={tp:.{engine.digits}f}  Range=[{range_low:.{engine.digits}f}-{range_high:.{engine.digits}f}]")
        else:
            filtered_risk += 1
    
    # Close remaining
    if engine.positions:
        engine.close_all(times[-1], closes[-1], "END")
    
    # Print funnel
    print(f"\n  Signal Funnel:")
    print(f"    Total trading days:     {total_days}")
    print(f"    Valid range days:       {range_days}")
    print(f"    Filtered (range size):  {filtered_range_size}")
    print(f"    Breakout signals:       {breakout_signals}")
    print(f"    Filtered (max trades):  {filtered_max_trades}")
    print(f"    Filtered (risk):        {filtered_risk}")
    print(f"    Trades opened:          {len(engine.trades) + len(engine.positions)}")
    
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
        print(f"  Breakout — {sym} M15")
        print(f"  Period: {start} → {end}")
        print(f"{'#'*60}")
        
        try:
            engine = run_breakout(
                symbol=sym,
                timeframe="M15",
                start_date=start,
                end_date=end,
            )
            if engine:
                engine.print_summary(f"Breakout — {sym} M15")
                engine.print_trades(last_n=10)
        except FileNotFoundError as e:
            print(f"  ⚠️  {e}")
