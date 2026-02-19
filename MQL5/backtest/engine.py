"""
engine.py — Shared backtest engine for all strategies.

Features:
- Load CSV candle data (MT5 exported format)
- Resample M5 → M15, H1 etc.
- Position tracking: entry, SL, TP, partial TP, breakeven
- P&L calculation in $ (pip-based)
- Summary report generation

Usage:
    from engine import BacktestEngine, Position, load_data, resample

"""

import pandas as pd
import numpy as np
from dataclasses import dataclass, field
from typing import List, Optional, Dict, Tuple
from pathlib import Path
import os

# ─── Data directory ───
CANDLE_DIR = Path(__file__).resolve().parent.parent.parent / "candle data"

# ─── Pip / point info per symbol ───
SYMBOL_INFO = {
    "EURUSDm": {"pip": 0.0001, "pip_value_per_lot": 10.0, "digits": 5},
    "USDJPYm": {"pip": 0.01,   "pip_value_per_lot": 6.7,  "digits": 3},
    "GBPUSDm": {"pip": 0.0001, "pip_value_per_lot": 10.0, "digits": 5},
    "XAUUSDm": {"pip": 0.01,   "pip_value_per_lot": 1.0,  "digits": 2},
    "BTCUSDm": {"pip": 0.01,   "pip_value_per_lot": 1.0,  "digits": 2},
    "ETHUSDm": {"pip": 0.01,   "pip_value_per_lot": 1.0,  "digits": 2},
    "USOILm":  {"pip": 0.01,   "pip_value_per_lot": 10.0, "digits": 2},
}


@dataclass
class Position:
    """Represents an open position."""
    open_time: pd.Timestamp
    direction: str           # "BUY" or "SELL"
    entry: float
    sl: float
    tp: float
    lot: float
    orig_sl: float = 0.0    # Original SL for risk calc
    partial_done: bool = False
    be_done: bool = False
    close_time: Optional[pd.Timestamp] = None
    close_price: float = 0.0
    result: str = ""         # "TP", "SL", "PARTIAL+TP", "PARTIAL+SL", "EOD", etc.
    pnl: float = 0.0        # P&L in $

    def __post_init__(self):
        if self.orig_sl == 0.0:
            self.orig_sl = self.sl


@dataclass
class TradeResult:
    """Summary of a closed trade."""
    open_time: pd.Timestamp
    close_time: pd.Timestamp
    direction: str
    entry: float
    sl: float
    tp: float
    close_price: float
    result: str
    pnl: float
    pnl_r: float            # P&L in R multiples
    lot: float


def load_data(symbol: str, timeframe: str = "M5") -> pd.DataFrame:
    """
    Load candle data for a symbol.
    
    Args:
        symbol: e.g. "EURUSDm", "XAUUSDm"
        timeframe: "M5" or "H1" (file suffix)
    
    Returns:
        DataFrame with columns: Open, High, Low, Close, Volume
        Index: DatetimeIndex
    """
    filename = f"{symbol}_{timeframe}.csv"
    filepath = CANDLE_DIR / filename
    
    if not filepath.exists():
        raise FileNotFoundError(f"Data file not found: {filepath}")
    
    df = pd.read_csv(filepath, parse_dates=["datetime"])
    df.set_index("datetime", inplace=True)
    df.sort_index(inplace=True)
    
    # Keep only OHLCV
    for col in ["symbol"]:
        if col in df.columns:
            df.drop(columns=[col], inplace=True)
    
    df.dropna(subset=["Open", "High", "Low", "Close"], inplace=True)
    
    # Remove weekends
    df = df[df.index.dayofweek < 5]
    
    return df


def resample(df: pd.DataFrame, target_tf: str) -> pd.DataFrame:
    """
    Resample M5 data to a higher timeframe.
    
    Args:
        df: M5 DataFrame
        target_tf: "M15", "M30", "H1", "H4"
    
    Returns:
        Resampled DataFrame
    """
    tf_map = {
        "M5": "5min",
        "M15": "15min",
        "M30": "30min",
        "H1": "1h",
        "H4": "4h",
        "D1": "1D",
    }
    
    if target_tf not in tf_map:
        raise ValueError(f"Unknown timeframe: {target_tf}")
    
    rule = tf_map[target_tf]
    
    resampled = df.resample(rule).agg({
        "Open": "first",
        "High": "max",
        "Low": "min",
        "Close": "last",
        "Volume": "sum",
    }).dropna()
    
    return resampled


def filter_date_range(df: pd.DataFrame, start: str = None, end: str = None) -> pd.DataFrame:
    """Filter DataFrame to a date range."""
    if start:
        df = df[df.index >= pd.Timestamp(start)]
    if end:
        df = df[df.index <= pd.Timestamp(end)]
    return df


def calc_atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
    """Calculate ATR (Average True Range)."""
    high = df["High"]
    low = df["Low"]
    close = df["Close"].shift(1)
    
    tr = pd.DataFrame({
        "hl": high - low,
        "hc": (high - close).abs(),
        "lc": (low - close).abs(),
    }).max(axis=1)
    
    return tr.rolling(period).mean()


def calc_ema(series: pd.Series, period: int) -> pd.Series:
    """Calculate EMA."""
    return series.ewm(span=period, adjust=False).mean()


def calc_rsi(series: pd.Series, period: int = 14) -> pd.Series:
    """Calculate RSI."""
    delta = series.diff()
    gain = delta.clip(lower=0)
    loss = (-delta).clip(lower=0)
    
    avg_gain = gain.ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    avg_loss = loss.ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    
    rs = avg_gain / avg_loss
    rsi = 100 - (100 / (1 + rs))
    return rsi


def calc_bollinger(series: pd.Series, period: int = 20, deviation: float = 2.0) -> Tuple[pd.Series, pd.Series, pd.Series]:
    """
    Calculate Bollinger Bands.
    
    Returns:
        (upper, middle, lower) Series
    """
    middle = series.rolling(period).mean()
    std = series.rolling(period).std()
    upper = middle + deviation * std
    lower = middle - deviation * std
    return upper, middle, lower


class BacktestEngine:
    """
    Generic backtest engine that manages positions and P&L.
    
    Strategy classes should:
    1. Call engine.check_signals(bar) each bar → list of new position requests
    2. Engine handles order execution, SL/TP checks, partial TP, BE
    """
    
    def __init__(
        self,
        symbol: str = "EURUSDm",
        initial_balance: float = 500.0,
        lot_size: float = 0.02,
        max_risk_pct: float = 5.0,
        partial_tp_r: float = 0.5,    # Partial TP at this R
        partial_close_pct: float = 50.0,  # Close this % at partial
        be_at_r: float = 0.5,         # Move SL to BE at this R
        daily_loss_limit: float = 3.0, # Max daily loss %
        max_positions: int = 1,        # Max simultaneous positions
    ):
        self.symbol = symbol
        self.initial_balance = initial_balance
        self.balance = initial_balance
        self.lot_size = lot_size
        self.max_risk_pct = max_risk_pct
        self.partial_tp_r = partial_tp_r
        self.partial_close_pct = partial_close_pct
        self.be_at_r = be_at_r
        self.daily_loss_limit = daily_loss_limit
        self.max_positions = max_positions
        
        info = SYMBOL_INFO.get(symbol, {"pip": 0.0001, "pip_value_per_lot": 10.0, "digits": 5})
        self.pip = info["pip"]
        self.pip_value_per_lot = info["pip_value_per_lot"]
        self.digits = info["digits"]
        
        self.positions: List[Position] = []
        self.trades: List[TradeResult] = []
        self.equity_curve: List[Dict] = []
        self.daily_pnl: float = 0.0
        self.current_date = None
        self.peak_balance: float = initial_balance
        self.max_drawdown: float = 0.0
        self.daily_loss_hit: bool = False

    def _pip_distance(self, price1: float, price2: float) -> float:
        """Calculate distance in pips between two prices."""
        return abs(price1 - price2) / self.pip
    
    def _pnl_for_distance(self, pips: float, lots: float) -> float:
        """Calculate P&L in $ for a given pip distance and lot size."""
        return pips * self.pip_value_per_lot * lots

    def _calc_risk_pct(self, entry: float, sl: float, lots: float) -> float:
        """Calculate risk % of current balance."""
        pips = self._pip_distance(entry, sl)
        risk_usd = self._pnl_for_distance(pips, lots)
        return (risk_usd / self.balance) * 100.0

    def can_open(self, entry: float, sl: float) -> bool:
        """Check if we can open a new position (risk + position limits)."""
        if len(self.positions) >= self.max_positions:
            return False
        if self.daily_loss_hit:
            return False
        risk_pct = self._calc_risk_pct(entry, sl, self.lot_size)
        if risk_pct > self.max_risk_pct:
            return False
        return True

    def open_position(self, time: pd.Timestamp, direction: str, entry: float, sl: float, tp: float) -> Optional[Position]:
        """Open a new position if risk checks pass."""
        if not self.can_open(entry, sl):
            return None
        
        pos = Position(
            open_time=time,
            direction=direction,
            entry=entry,
            sl=sl,
            tp=tp,
            lot=self.lot_size,
        )
        self.positions.append(pos)
        return pos

    def _close_position(self, pos: Position, time: pd.Timestamp, price: float, result: str, lot_pct: float = 100.0):
        """Close a position (fully or partially)."""
        direction_mult = 1.0 if pos.direction == "BUY" else -1.0
        pips = (price - pos.entry) / self.pip * direction_mult
        lots = pos.lot * (lot_pct / 100.0)
        pnl = self._pnl_for_distance(pips, lots)
        
        if lot_pct < 100.0:
            # Partial close
            pos.lot -= lots
            pos.partial_done = True
            pos.pnl += pnl
        else:
            # Full close
            pos.close_time = time
            pos.close_price = price
            pos.result = result
            pos.pnl += pnl
            
            # Record trade
            risk_pips = self._pip_distance(pos.entry, pos.orig_sl)
            pnl_r = pips / risk_pips if risk_pips > 0 else 0.0
            
            self.trades.append(TradeResult(
                open_time=pos.open_time,
                close_time=time,
                direction=pos.direction,
                entry=pos.entry,
                sl=pos.orig_sl,
                tp=pos.tp,
                close_price=price,
                result=result,
                pnl=pos.pnl,
                pnl_r=pnl_r,
                lot=pos.lot + lots,  # original lot
            ))
            
            self.positions.remove(pos)
        
        self.balance += pnl
        self.daily_pnl += pnl
        
        # Update drawdown
        if self.balance > self.peak_balance:
            self.peak_balance = self.balance
        dd = (self.peak_balance - self.balance) / self.peak_balance * 100
        if dd > self.max_drawdown:
            self.max_drawdown = dd

    def process_bar(self, time: pd.Timestamp, o: float, h: float, l: float, c: float):
        """
        Process a single bar: check SL/TP/partial/BE for all open positions.
        Call this BEFORE checking for new signals on this bar.
        """
        # Daily reset
        bar_date = time.date()
        if bar_date != self.current_date:
            self.current_date = bar_date
            self.daily_pnl = 0.0
            self.daily_loss_hit = False
        
        # Check daily loss limit
        if self.daily_pnl < 0 and abs(self.daily_pnl / self.balance * 100) >= self.daily_loss_limit:
            self.daily_loss_hit = True
        
        # Process open positions (iterate copy since list may change)
        for pos in list(self.positions):
            self._manage_position(pos, time, o, h, l, c)
        
        # Record equity
        unrealized = 0.0
        for pos in self.positions:
            direction_mult = 1.0 if pos.direction == "BUY" else -1.0
            pips = (c - pos.entry) / self.pip * direction_mult
            unrealized += self._pnl_for_distance(pips, pos.lot)
        
        self.equity_curve.append({
            "time": time,
            "balance": self.balance,
            "equity": self.balance + unrealized,
            "open_positions": len(self.positions),
        })

    def _manage_position(self, pos: Position, time: pd.Timestamp, o: float, h: float, l: float, c: float):
        """Check SL, TP, partial TP, breakeven for one position."""
        if pos.direction == "BUY":
            # Check SL first (assume worst case: SL hit before TP in same bar)
            if l <= pos.sl:
                self._close_position(pos, time, pos.sl, "SL")
                return
            
            # Check TP
            if h >= pos.tp:
                self._close_position(pos, time, pos.tp, "TP")
                return
            
            # Check partial TP
            risk_pips = self._pip_distance(pos.entry, pos.orig_sl)
            current_pips = (h - pos.entry) / self.pip
            
            if not pos.partial_done and self.partial_tp_r > 0:
                partial_price = pos.entry + risk_pips * self.partial_tp_r * self.pip
                if h >= partial_price:
                    self._close_position(pos, time, partial_price, "PARTIAL", self.partial_close_pct)
            
            # Check breakeven
            if not pos.be_done and self.be_at_r > 0:
                be_price = pos.entry + risk_pips * self.be_at_r * self.pip
                if h >= be_price:
                    pos.sl = pos.entry
                    pos.be_done = True
        
        else:  # SELL
            if h >= pos.sl:
                self._close_position(pos, time, pos.sl, "SL")
                return
            
            if l <= pos.tp:
                self._close_position(pos, time, pos.tp, "TP")
                return
            
            risk_pips = self._pip_distance(pos.entry, pos.orig_sl)
            current_pips = (pos.entry - l) / self.pip
            
            if not pos.partial_done and self.partial_tp_r > 0:
                partial_price = pos.entry - risk_pips * self.partial_tp_r * self.pip
                if l <= partial_price:
                    self._close_position(pos, time, partial_price, "PARTIAL", self.partial_close_pct)
            
            if not pos.be_done and self.be_at_r > 0:
                be_price = pos.entry - risk_pips * self.be_at_r * self.pip
                if l <= be_price:
                    pos.sl = pos.entry
                    pos.be_done = True

    def close_all(self, time: pd.Timestamp, price: float, reason: str = "EOD"):
        """Close all open positions at given price."""
        for pos in list(self.positions):
            self._close_position(pos, time, price, reason)

    def update_tp(self, pos: Position, new_tp: float):
        """Dynamically update TP for an open position."""
        pos.tp = new_tp

    def summary(self) -> Dict:
        """Generate backtest summary statistics."""
        if not self.trades:
            return {
                "total_trades": 0,
                "win_rate": 0,
                "total_pnl": 0,
                "return_pct": 0,
                "max_drawdown": 0,
                "profit_factor": 0,
                "avg_pnl_r": 0,
            }
        
        wins = [t for t in self.trades if t.pnl > 0]
        losses = [t for t in self.trades if t.pnl <= 0]
        
        total_profit = sum(t.pnl for t in wins)
        total_loss = abs(sum(t.pnl for t in losses))
        
        return {
            "total_trades": len(self.trades),
            "wins": len(wins),
            "losses": len(losses),
            "win_rate": len(wins) / len(self.trades) * 100,
            "total_pnl": self.balance - self.initial_balance,
            "return_pct": (self.balance - self.initial_balance) / self.initial_balance * 100,
            "final_balance": self.balance,
            "peak_balance": self.peak_balance,
            "max_drawdown": self.max_drawdown,
            "profit_factor": total_profit / total_loss if total_loss > 0 else float("inf"),
            "avg_pnl_r": np.mean([t.pnl_r for t in self.trades]),
            "avg_win_r": np.mean([t.pnl_r for t in wins]) if wins else 0,
            "avg_loss_r": np.mean([t.pnl_r for t in losses]) if losses else 0,
            "best_trade": max(t.pnl for t in self.trades),
            "worst_trade": min(t.pnl for t in self.trades),
            "trades_per_month": len(self.trades) / max(1, (self.trades[-1].close_time - self.trades[0].open_time).days / 30),
        }

    def print_summary(self, title: str = "Backtest Summary"):
        """Print formatted summary."""
        s = self.summary()
        print(f"\n{'='*60}")
        print(f"  {title}")
        print(f"{'='*60}")
        print(f"  Symbol:          {self.symbol}")
        print(f"  Initial Balance: ${self.initial_balance:.2f}")
        print(f"  Final Balance:   ${s['final_balance']:.2f}")
        print(f"  Return:          {s['return_pct']:+.1f}% (${s['total_pnl']:+.2f})")
        print(f"  Max Drawdown:    {s['max_drawdown']:.1f}%")
        print(f"  Peak Balance:    ${s['peak_balance']:.2f}")
        print(f"{'─'*60}")
        print(f"  Total Trades:    {s['total_trades']}")
        print(f"  Win Rate:        {s['win_rate']:.1f}% ({s['wins']}W / {s['losses']}L)")
        print(f"  Profit Factor:   {s['profit_factor']:.2f}")
        print(f"  Avg P&L (R):     {s['avg_pnl_r']:+.2f}R")
        print(f"  Avg Win (R):     {s['avg_win_r']:+.2f}R  |  Avg Loss (R): {s['avg_loss_r']:+.2f}R")
        print(f"  Best Trade:      ${s['best_trade']:+.2f}  |  Worst: ${s['worst_trade']:+.2f}")
        print(f"  Trades/Month:    {s['trades_per_month']:.1f}")
        print(f"{'='*60}")

    def print_trades(self, last_n: int = 0):
        """Print trade log."""
        trades = self.trades[-last_n:] if last_n > 0 else self.trades
        print(f"\n{'─'*90}")
        print(f"  {'Time':>19}  {'Dir':>4}  {'Entry':>10}  {'SL':>10}  {'TP':>10}  {'Close':>10}  {'Result':>8}  {'P&L':>8}  {'R':>6}")
        print(f"{'─'*90}")
        for t in trades:
            print(f"  {str(t.open_time):>19}  {t.direction:>4}  {t.entry:>10.{self.digits}f}  {t.sl:>10.{self.digits}f}  {t.tp:>10.{self.digits}f}  {t.close_price:>10.{self.digits}f}  {t.result:>8}  {t.pnl:>+8.2f}  {t.pnl_r:>+6.2f}")
        print(f"{'─'*90}")
