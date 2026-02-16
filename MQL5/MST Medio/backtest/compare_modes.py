"""Compare Python backtest: instant fill (legacy) vs limit order (realistic)."""
import sys
sys.path.insert(0, "/Users/tuan/GitProject/tradingview/MST Medio/backtest")
import pandas as pd
from strategy_mst_medio import run_mst_medio, print_summary

# Load BTC M5 data
data_dir = "/Users/tuan/GitProject/metatrader/candle data"
btc_m5 = f"{data_dir}/BTCUSDm_M5.csv"

df = pd.read_csv(btc_m5, parse_dates=["datetime"], index_col="datetime")
df.index.name = "Time"

# Filter to same period as MT5 test: 2025.01.01 - 2025.01.11
df_test = df["2025-01-01":"2025-01-11"].copy()
print(f"Test data: {len(df_test)} bars ({df_test.index[0]} → {df_test.index[-1]})")

# Run with instant fill (legacy mode)
print("\n" + "=" * 70)
print("MODE 1: INSTANT FILL (legacy) — limit_order=False")
print("=" * 70)
signals_legacy, _ = run_mst_medio(df_test, impulse_mult=1.0, limit_order=False)
print_summary(signals_legacy, "INSTANT FILL (legacy)")

# Run with limit order (realistic mode)
print("\n" + "=" * 70)
print("MODE 2: LIMIT ORDER (realistic) — limit_order=True")
print("=" * 70)
signals_limit, _ = run_mst_medio(df_test, impulse_mult=1.0, limit_order=True)
print_summary(signals_limit, "LIMIT ORDER (realistic)")

# Detailed comparison
print("\n" + "=" * 70)
print("DETAILED COMPARISON")
print("=" * 70)

for s in signals_legacy:
    if s.result in ("TP", "SL", "CLOSE_REVERSE"):
        # Find matching signal in limit mode
        match = None
        for s2 in signals_limit:
            if abs(s.entry - s2.entry) < 0.01 and s.direction == s2.direction:
                match = s2
                break
        
        if match:
            icon = "✅" if s.result == match.result else "❌"
            print(f"  {s.time.strftime('%Y-%m-%d %H:%M')} {s.direction:4s} "
                  f"Entry={s.entry:10.2f} "
                  f"Legacy={s.result}({s.pnl_r:+.2f}R) "
                  f"Limit={match.result}({match.pnl_r:+.2f}R) "
                  f"{'Filled' if match.filled else 'UNFILLED'} {icon}")
        else:
            print(f"  {s.time.strftime('%Y-%m-%d %H:%M')} {s.direction:4s} "
                  f"Entry={s.entry:10.2f} "
                  f"Legacy={s.result}({s.pnl_r:+.2f}R) "
                  f"Limit=NO MATCH ❓")

# Also run on full data for broader comparison
print("\n" + "=" * 70)
print("FULL DATA COMPARISON (all available data)")
print("=" * 70)

print("\n--- Instant fill (legacy) ---")
signals_all_legacy, _ = run_mst_medio(df, impulse_mult=1.0, limit_order=False)
print_summary(signals_all_legacy, "ALL DATA - Instant Fill")

print("\n--- Limit order (realistic) ---")
signals_all_limit, _ = run_mst_medio(df, impulse_mult=1.0, limit_order=True)
print_summary(signals_all_limit, "ALL DATA - Limit Order")

# Count unfilled
unfilled = [s for s in signals_all_limit if s.result == "UNFILLED"]
if unfilled:
    print(f"\n  Unfilled signals: {len(unfilled)}/{len(signals_all_limit)} "
          f"({len(unfilled)/len(signals_all_limit)*100:.1f}%)")
