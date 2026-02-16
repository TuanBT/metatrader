"""
Analyze differences between Python backtest and MT5 Strategy Tester.

KEY DIFFERENCES:
1. Python: Signal fires → price IS at confirm candle close → entry is sh0/sl0 via limit order
   MT5:    Signal fires → places limit order at sh0/sl0 → order may or may NOT fill

2. Python: TP/SL check on SAME BAR as entry (check SL first, then TP)
   MT5:    Limit order fills at some future bar → TP/SL tracked from fill bar

3. Python: No spread/slippage
   MT5:    Spread + slippage in ticks

4. Python: OHLC bar-based → checks SL/TP vs High/Low of bar
   MT5:    Tick-based (even "1 minute OHLC") → more granular SL/TP triggers

5. Python: bar_close > entry → "entry filled" instantly
   MT5:    Limit order: price must COME BACK to entry level to fill

THIS IS THE CRITICAL DIFFERENCE:
In Python backtest, when signal fires on bar N:
  - Entry = sh0 (previous swing high)
  - Current price = close of bar N = ABOVE sh0 (since close > W1 peak > sh0)
  - Python assumes entry at sh0 immediately (as if limit order fills instantly)
  - SL/TP checked from bar N+1 forward

In MT5 Strategy Tester, when signal fires on bar N:
  - Entry = sh0 → places BUY LIMIT at sh0
  - Current price = close of bar N = ABOVE sh0
  - BUY LIMIT only fills when price DROPS back to sh0
  - If price never drops to sh0 → order never fills → trade missed!
  - If price drops to sh0 AND THEN drops to SL → LOSS (price already falling)

CONCLUSION:
Python backtest is OVERLY OPTIMISTIC because it assumes instant entry at sh0,
but in reality, price at signal time is ABOVE sh0 (already moved past entry).
The limit order may never fill, or may fill in bad conditions (price retracing = weakening).
"""

import re
import sys

# Load BTC log and extract signals
logfile = sys.argv[1] if len(sys.argv) > 1 else "/Users/tuan/GitProject/metatrader/MQL5/MST Medio/20260216_btc.log"

with open(logfile, "r", encoding="utf-16-le", errors="replace") as f:
    lines = f.readlines()

# Find ALL signals and their limit order details
print("=" * 100)
print("LIMIT ORDER ANALYSIS: Entry vs Market Price at Signal Time")
print("=" * 100)

for i, line in enumerate(lines):
    # Find alerts
    m = re.search(r'Alert: MST Medio: (BUY|SELL) \| Entry=([\d.]+) SL=([\d.]+) TP=([\d.]+)', line)
    if m:
        direction = m.group(1)
        entry = float(m.group(2))
        sl = float(m.group(3))
        tp = float(m.group(4))
        
        ts_m = re.search(r'(\d{4}\.\d{2}\.\d{2}\s+\d{2}:\d{2}:\d{2})', line)
        ts = ts_m.group(1) if ts_m else "?"
        
        # Find the limit order line (next few lines)
        for j in range(i+1, min(i+10, len(lines))):
            m2 = re.search(r'(buy|sell) limit [\d.]+ \w+ at ([\d.]+) .+\(([\d.]+) / ([\d.]+) / ([\d.]+)\)', lines[j])
            if m2:
                limit_price = float(m2.group(2))
                bid = float(m2.group(3))
                ask = float(m2.group(4))
                
                if direction == 'BUY':
                    # BUY LIMIT: entry < ask (current price)
                    gap = ask - entry
                    gap_pct = gap / entry * 100
                    print(f"  {ts} {direction:4s} Entry={entry:10.2f} Ask={ask:10.2f} Gap={gap:+8.2f} ({gap_pct:+.3f}%)")
                    print(f"         SL={sl:10.2f} TP={tp:10.2f} SL_dist={abs(entry-sl):.2f} | Price must DROP {gap:.2f} to fill")
                else:
                    # SELL LIMIT: entry > bid (current price)
                    gap = entry - bid
                    gap_pct = gap / entry * 100
                    print(f"  {ts} {direction:4s} Entry={entry:10.2f} Bid={bid:10.2f} Gap={gap:+8.2f} ({gap_pct:+.3f}%)")
                    print(f"         SL={sl:10.2f} TP={tp:10.2f} SL_dist={abs(entry-sl):.2f} | Price must RISE {gap:.2f} to fill")
                break

print()
print("KEY INSIGHT:")
print("Python backtest assumes INSTANT FILL at entry price.")
print("MT5 uses LIMIT ORDER → price must RETRACE to entry → may not fill, or fills in worse conditions.")
print()
print("This explains why Python WR is much higher than MT5 WR!")
