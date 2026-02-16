"""
Analyze: Is the Partial TP R-calculation correct?

With Partial TP (Hedging, 50/50 split):
- totalLot = 0.02, part1 = 0.01, part2 = 0.01
- R = totalLot × SL_dist (in pip value)

When LOSS (both hit SL):
  Part1 PnL = -SL_dist × 0.01 (in pip terms: -SL_dist)
  Part2 PnL = -SL_dist × 0.01 (in pip terms: -SL_dist)
  Total PnL = -SL_dist × 0.02 (in pip terms: -2 × SL_dist)
  This is -1R of totalLot (0.02)

When WIN (Part1 hits TP, Part2 moves SL to entry → BE):
  Part1 PnL = +TP_dist × 0.01
  Part2 PnL = 0 (breakeven)
  Total PnL = +TP_dist × 0.01
  In R terms: TP_dist × 0.01 / (SL_dist × 0.02) = TP_dist/(2×SL_dist) = RR/2

So if RR = 1.0:
  Win = +0.5R
  Loss = -1.0R
  Need WR > 66.7% to break even!

If RR = 1.5:
  Win = +0.75R
  Loss = -1.0R
  Need WR > 57.1% to break even!

PYTHON BACKTEST says ~85% WR → should be profitable even with Partial TP!
"""

# From BTC log:
trades = [
    {'dir': 'BUY',  'entry': 94256.91, 'sl': 93963.34, 'tp': 94754.56, 'result': 'WIN'},
    {'dir': 'BUY',  'entry': 94620.73, 'sl': 94191.85, 'tp': 95422.47, 'result': 'CANCEL'},
    {'dir': 'BUY',  'entry': 97033.64, 'sl': 96493.04, 'tp': 97497.89, 'result': 'LOSS'},
    {'dir': 'BUY',  'entry': 98242.34, 'sl': 97858.16, 'tp': 98433.19, 'result': 'WIN'},
    {'dir': 'SELL', 'entry': 97980.66, 'sl': 98247.72, 'tp': 97790.19, 'result': 'WIN'},
    {'dir': 'SELL', 'entry': 97920.77, 'sl': 98350.88, 'tp': 97648.33, 'result': 'LOSS'},
    {'dir': 'BUY',  'entry': 98124.99, 'sl': 97520.12, 'tp': 98751.33, 'result': 'WIN'},
    {'dir': 'BUY',  'entry': 99582.10, 'sl': 98620.36, 'tp':101539.50, 'result': 'LOSS'},
    {'dir': 'SELL', 'entry': 96066.42, 'sl': 96707.08, 'tp': 95309.98, 'result': 'WIN'},
    {'dir': 'BUY',  'entry': 94227.90, 'sl': 93503.44, 'tp': 94777.38, 'result': 'CANCEL'},
    {'dir': 'BUY',  'entry': 94550.44, 'sl': 93487.32, 'tp': 95046.10, 'result': 'LOSS'},
    {'dir': 'SELL', 'entry': 94217.21, 'sl': 94861.71, 'tp': 93765.42, 'result': 'WIN'},
    {'dir': 'SELL', 'entry': 92347.89, 'sl': 93335.22, 'tp': 91526.91, 'result': 'LOSS'},
    {'dir': 'BUY',  'entry': 94791.68, 'sl': 94786.12, 'tp': 94995.47, 'result': 'LOSS'},
    {'dir': 'SELL', 'entry': 94730.93, 'sl': 95129.60, 'tp': 92171.72, 'result': 'LOSS'},
    {'dir': 'BUY',  'entry': 93982.08, 'sl': 93082.35, 'tp': 94453.92, 'result': 'STOPOUT'},
]

lot = 0.02
part1_lot = 0.01
part2_lot = 0.01

print("=" * 90)
print("CORRECT R CALCULATION (totalLot = 0.02, split 0.01 + 0.01)")
print("=" * 90)

total_R = 0
wins = 0
losses = 0

for t in trades:
    if t['result'] in ('CANCEL', 'STOPOUT'):
        continue
    
    sl_dist = abs(t['entry'] - t['sl'])
    tp_dist = abs(t['tp'] - t['entry'])
    rr = tp_dist / sl_dist if sl_dist > 0 else 0
    
    # Total risk = totalLot × sl_dist (in pip terms = 2 × sl_dist since 2 parts)
    total_risk = lot * sl_dist  # Not used for R calc, just for reference
    
    if t['result'] == 'WIN':
        # Part1 hits TP → profit = tp_dist × part1_lot
        # Part2 hits BE → profit = 0
        # Total profit in pip terms = tp_dist (only for part1 with 0.01 lot)
        # In R terms: (tp_dist × part1_lot) / (sl_dist × totalLot)
        r_val = (tp_dist * part1_lot) / (sl_dist * lot)  # = RR/2
        total_R += r_val
        wins += 1
        print(f"  {t['dir']:4s} SL_dist={sl_dist:8.2f} TP_dist={tp_dist:8.2f} RR={rr:.2f} → WIN  = +{r_val:.2f}R")
    else:
        # Both parts hit SL
        # Total loss in pip terms = sl_dist × 2 (for 2 parts)
        # In R terms: (sl_dist × totalLot) / (sl_dist × totalLot) = -1.0R
        r_val = -1.0
        total_R += r_val
        losses += 1
        print(f"  {t['dir']:4s} SL_dist={sl_dist:8.2f} TP_dist={tp_dist:8.2f} RR={rr:.2f} → LOSS = {r_val:.2f}R")

print()
print(f"Wins: {wins}, Losses: {losses}, WR: {wins/(wins+losses)*100:.1f}%")
print(f"Total R: {total_R:+.2f}R")
print()
print("=" * 90)
print("COMPARISON: WITHOUT Partial TP (single position, full TP)")
print("=" * 90)

total_R_no_partial = 0

for t in trades:
    if t['result'] in ('CANCEL', 'STOPOUT'):
        continue
    
    sl_dist = abs(t['entry'] - t['sl'])
    tp_dist = abs(t['tp'] - t['entry'])
    rr = tp_dist / sl_dist if sl_dist > 0 else 0
    
    if t['result'] == 'WIN':
        r_val = rr  # Full RR
        total_R_no_partial += r_val
        print(f"  {t['dir']:4s} RR={rr:.2f} → WIN  = +{r_val:.2f}R")
    else:
        r_val = -1.0
        total_R_no_partial += r_val
        print(f"  {t['dir']:4s} RR={rr:.2f} → LOSS = {r_val:.2f}R")

print()
print(f"Wins: {wins}, Losses: {losses}, WR: {wins/(wins+losses)*100:.1f}%")
print(f"Total R (no partial): {total_R_no_partial:+.2f}R")
print()
print("=" * 90)
print("VERDICT:")
print(f"  With Partial TP:    {total_R:+.2f}R")
print(f"  Without Partial TP: {total_R_no_partial:+.2f}R")
print(f"  Difference:         {total_R_no_partial - total_R:+.2f}R")
print()
print("The REAL problem is the 46% win rate (6W/7L), NOT the Partial TP math!")
print("Python backtest gives 85% WR → need to investigate WHY EA WR is so different.")
