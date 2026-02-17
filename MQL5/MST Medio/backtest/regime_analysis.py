"""
regime_analysis.py — Analyze when the strategy works and when it doesn't.
Break down performance by month/quarter to identify favorable regimes.
"""
import pandas as pd
import numpy as np
import sys
from pathlib import Path
from collections import defaultdict

sys.path.insert(0, "/Users/tuan/GitProject/tradingview/MST Medio/backtest")
from strategy_mst_medio import run_mst_medio

CANDLE_DIR = Path("/Users/tuan/GitProject/metatrader/candle data")
DATE_FROM = pd.Timestamp("2025-01-01")
DATE_TO = pd.Timestamp("2026-02-15")

# Load XAUUSD only for detailed analysis
df = pd.read_csv(CANDLE_DIR / "XAUUSDm_M5.csv", parse_dates=["datetime"])
df.set_index("datetime", inplace=True)
df.sort_index(inplace=True)
df = df[df.index >= pd.Timestamp("2024-01-01")]


def analyze_regime(name, params):
    sigs, _ = run_mst_medio(df, **params)
    filt = [s for s in sigs if DATE_FROM <= s.time <= DATE_TO
            and s.result in ("TP", "SL", "CLOSE_REVERSE")]

    # Group by month
    monthly = defaultdict(list)
    for s in filt:
        key = s.time.strftime("%Y-%m")
        monthly[key].append(s.pnl_r)

    print(f"\n{'='*70}")
    print(f"  {name} — XAUUSD Monthly Breakdown")
    print(f"{'='*70}")
    print(f"  {'Month':<10} {'Trades':>7} {'Wins':>5} {'WR%':>6} {'PnL(R)':>8} "
          f"{'AvgR':>7} {'CumR':>8}")
    print(f"  {'-'*10} {'-'*7} {'-'*5} {'-'*6} {'-'*8} {'-'*7} {'-'*8}")

    cum = 0
    months_data = []
    for month in sorted(monthly.keys()):
        pnls = monthly[month]
        trades = len(pnls)
        wins = sum(1 for p in pnls if p > 0)
        wr = wins / trades * 100 if trades else 0
        pnl = sum(pnls)
        avg = pnl / trades if trades else 0
        cum += pnl
        symbol = "✅" if pnl > 0 else "❌"
        print(f"  {symbol} {month:<8} {trades:7d} {wins:5d} {wr:5.1f}% {pnl:+8.1f} "
              f"{avg:+7.3f} {cum:+8.1f}")
        months_data.append({"month": month, "pnl": pnl, "trades": trades, "wr": wr})

    # Analyze what market conditions affect performance
    # Use volatility (ATR) as a proxy
    print(f"\n  Total: {len(filt)} trades, PnL={cum:+.1f}R")
    winning_months = [m for m in months_data if m["pnl"] > 0]
    losing_months = [m for m in months_data if m["pnl"] <= 0]
    print(f"  Winning months: {len(winning_months)}/{len(months_data)}")
    if winning_months:
        avg_win_month = np.mean([m["pnl"] for m in winning_months])
        print(f"  Avg winning month: {avg_win_month:+.1f}R")
    if losing_months:
        avg_lose_month = np.mean([m["pnl"] for m in losing_months])
        print(f"  Avg losing month: {avg_lose_month:+.1f}R")

    return months_data


# ============================================================================
# TEST KEY CONFIGS
# ============================================================================
configs = {
    "FR1.0 (optimal)": dict(pivot_len=3, break_mult=0.25, impulse_mult=0.75,
                             tp_mode="fixed_rr", fixed_rr=1.0, limit_order=True),
    "Confirm TP": dict(pivot_len=3, break_mult=0.25, impulse_mult=0.75,
                        tp_mode="confirm", limit_order=True),
    "Confirm+BE0.5": dict(pivot_len=3, break_mult=0.25, impulse_mult=0.75,
                           tp_mode="confirm", be_at_r=0.5, limit_order=True),
}

for name, params in configs.items():
    analyze_regime(name, params)


# ============================================================================
# VOLATILITY REGIME ANALYSIS
# ============================================================================
print("\n\n" + "="*70)
print("  VOLATILITY REGIME ANALYSIS")
print("="*70)

# Calculate monthly ATR for XAUUSD
df_range = df[(df.index >= DATE_FROM) & (df.index <= DATE_TO)].copy()
df_range["atr"] = (df_range["high"] - df_range["low"])
monthly_atr = df_range.resample("M")["atr"].mean()

print(f"\n  {'Month':<10} {'Avg M5 Range':>12} {'Regime':>10}")
print(f"  {'-'*10} {'-'*12} {'-'*10}")
for dt, atr in monthly_atr.items():
    regime = "HIGH" if atr > monthly_atr.median() else "LOW"
    print(f"  {dt.strftime('%Y-%m'):<10} {atr:12.2f} {regime:>10}")

# Correlate volatility with PnL
print("\n  Correlation between volatility and strategy PnL:")
sigs, _ = run_mst_medio(df, pivot_len=3, break_mult=0.25, impulse_mult=0.75,
                         tp_mode="fixed_rr", fixed_rr=1.0, limit_order=True)
filt = [s for s in sigs if DATE_FROM <= s.time <= DATE_TO
        and s.result in ("TP", "SL", "CLOSE_REVERSE")]

monthly_pnl = defaultdict(float)
for s in filt:
    key = s.time.strftime("%Y-%m")
    monthly_pnl[key] += s.pnl_r

# Match months
common_months = sorted(set(monthly_pnl.keys()) & set(m.strftime("%Y-%m") for m in monthly_atr.index))
if common_months:
    atrs = []
    pnls = []
    for m in common_months:
        dt = pd.Timestamp(m + "-01")
        # Find closest month end
        for idx_dt, atr_val in monthly_atr.items():
            if idx_dt.strftime("%Y-%m") == m:
                atrs.append(atr_val)
                break
        pnls.append(monthly_pnl[m])

    corr = np.corrcoef(atrs, pnls)[0, 1] if len(atrs) > 2 else 0
    print(f"  Pearson correlation (ATR vs PnL): {corr:+.3f}")
    if corr > 0.3:
        print("  → Strategy performs BETTER in HIGH volatility months")
    elif corr < -0.3:
        print("  → Strategy performs BETTER in LOW volatility months")
    else:
        print("  → No strong correlation with volatility")

# Trend vs Range analysis
print("\n  TREND REGIME ANALYSIS (Monthly price direction):")
monthly_close = df_range.resample("M")["close"].last()
monthly_open = df_range.resample("M")["open"].first()
monthly_change = monthly_close - monthly_open

print(f"\n  {'Month':<10} {'Direction':>10} {'Change':>10} {'FR1.0 PnL':>10}")
print(f"  {'-'*10} {'-'*10} {'-'*10} {'-'*10}")
for dt in monthly_change.index:
    m = dt.strftime("%Y-%m")
    change = monthly_change[dt]
    direction = "UP" if change > 0 else "DOWN"
    pnl = monthly_pnl.get(m, 0)
    symbol = "✅" if pnl > 0 else "❌"
    print(f"  {symbol} {m:<8} {direction:>10} {change:+10.1f} {pnl:+10.1f}R")

trends = []
for dt in monthly_change.index:
    m = dt.strftime("%Y-%m")
    trends.append(abs(monthly_change[dt]))

if len(trends) > 2:
    corr2 = np.corrcoef(trends, [monthly_pnl.get(dt.strftime("%Y-%m"), 0) for dt in monthly_change.index])[0, 1]
    print(f"\n  Correlation (trend strength vs PnL): {corr2:+.3f}")
