"""
Trade Monitor Configuration
All SSH, MT5, and strategy settings in one place.
"""
import os

# ============================================================================
# SSH CONNECTION
# ============================================================================
SSH_HOST = "103.122.221.141"
SSH_USER = "administrator"
SSH_PASS = os.environ.get("MT5_SSH_PASS", "PNS1G3e7oc3h6PWJD4dsA")

# ============================================================================
# MT5 PATHS (on remote Windows server)
# ============================================================================
MT5_DATA = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
MT5_LOGS = f"{MT5_DATA}\\MQL5\\Logs"
MT5_EXE  = r"C:\Program Files\MetaTrader 5 EXNESS\terminal64.exe"

# ============================================================================
# LOCAL DATA PATHS
# ============================================================================
DATA_DIR = os.path.join(os.path.dirname(__file__), "data")

# ============================================================================
# ACTIVE STRATEGIES (deployed on server)
# ============================================================================
STRATEGIES = {
    "Reversal_XAUUSD_H1": {
        "ea": "Expert Reversal",
        "symbol": "XAUUSDm",
        "timeframe": "H1",
        "magic": 20260302,
        "lot": 0.02,
        "params": {
            "SLBufferATR": 0.7,
            "MinSLPts": 100,
            "BB": "20,2.0",
            "RSI": "14 (OB=70, OS=30)",
            "TP": "Middle BB",
            "BE": "0.5R",
            "PartialTP": "50% at 0.5R",
        },
        "backtest_annual_return": 13.6,  # %
    },
    "MST_Medio_USDJPY_H1": {
        "ea": "Expert MST Medio",
        "symbol": "USDJPYm",
        "timeframe": "H1",
        "magic": 20260210,
        "lot": 0.02,
        "params": {
            "ATR_SL": True,
            "ATR_Mult": 2.0,
            "TP_RR": 2.0,
            "PivotLen": 5,
            "BreakMult": 0.25,
            "ImpulseMult": 1.5,
            "BE": "0.5R",
            "PartialTP": "50% at 0.5R",
        },
        "backtest_annual_return": 3.9,  # %
    },
}

# ============================================================================
# MONEY MANAGEMENT STRATEGIES
# ============================================================================
MONEY_MANAGEMENT = {
    # Fixed lot (current default)
    "fixed": {
        "description": "Fixed lot size, no adjustment",
        "lot": 0.02,
    },
    # Risk-based: lot = (account * risk%) / SL_distance
    "risk_percent": {
        "description": "Lot based on % risk per trade",
        "risk_pct": 2.0,
        "max_risk_pct": 5.0,
    },
    # Anti-martingale: increase after wins, decrease after losses
    "anti_martingale": {
        "description": "Increase lot after wins, decrease after losses",
        "base_lot": 0.02,
        "win_multiplier": 1.5,
        "loss_multiplier": 0.5,
        "max_lot": 0.1,
        "min_lot": 0.01,
    },
    # Equity curve: pause trading if equity curve < MA
    "equity_curve": {
        "description": "Pause when equity curve is below its moving average",
        "ma_period": 10,  # number of trades
        "action_below": "half_lot",  # "pause" or "half_lot"
    },
    # Consecutive loss: reduce after N consecutive losses
    "loss_streak": {
        "description": "Reduce lot after consecutive losses",
        "streak_threshold": 3,
        "reduction_pct": 50,  # reduce lot by 50%
        "recovery_wins": 2,   # wins needed to restore normal lot
    },
}
