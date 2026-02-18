#!/usr/bin/env python3
"""
Analyze EURUSD M15 log - win rate and trade outcomes
"""
import re

with open('logs/20260218.log', 'r', encoding='utf-16', errors='replace') as f:
    lines = f.readlines()

print(f'Total lines: {len(lines)}')

# Symbol/TF detection
for l in lines[:30]:
    if 'EURUSDm' in l or 'BTCUSDm' in l or 'XAUUSDm' in l:
        print('Symbol/TF:', l.strip()[-80:])
        break

# Count deals
deals = [l for l in lines if 'deal #' in l.lower() and 'done' in l.lower()]
print(f'\nTotal deals: {len(deals)}')

# TP/SL hits
tp_hits = sum(1 for l in lines if 'take profit' in l.lower() and ('deal' in l.lower() or 'order' in l.lower()))
sl_hits = sum(1 for l in lines if 'stop loss' in l.lower() and ('deal' in l.lower() or 'order' in l.lower()))
print(f'TP hits: {tp_hits}')
print(f'SL hits: {sl_hits}')
if tp_hits + sl_hits > 0:
    winrate = tp_hits / (tp_hits + sl_hits) * 100
    print(f'Win rate: {winrate:.1f}%')
    print(f'Expected: need >25% for break-even at 1:3 RR')

# Placed orders
placed = [l for l in lines if 'Pending BUY Ticket=' in l or 'Pending SELL Ticket=' in l]
print(f'\nSuccessful order placements: {len(placed)}')
for l in placed[:3]:
    print(' ', l.strip()[-150:])

# Find cases where CloseAllPositions replaces positions (signal flip)
close_all = [l for l in lines if 'Closed position' in l]
print(f'\nPositions closed by CloseAll: {len(close_all)}')

# Final balance
for l in reversed(lines):
    if 'final balance' in l.lower():
        print(f'\nFinal balance: {l.strip()[-80:]}')
        break

# Monthly win/loss summary from balance
balance_lines = [l for l in lines if 'StartBalance=' in l or 'New trading day' in l]
print(f'\nTrading day resets: {len(balance_lines)}')
for l in balance_lines[:5]:
    print(' ', l.strip()[-120:])

# Check RR on confirmed signals
rr_lines = [l for l in lines if 'CONSISTENT RR' in l and 'Actual RR=1:3' in l]
rr_not3 = [l for l in lines if 'CONSISTENT RR' in l and 'Actual RR=1:3' not in l]
print(f'\nSignals with RR=1:3: {len(rr_lines)}')
print(f'Signals with RR != 1:3: {len(rr_not3)}')
for l in rr_not3[:3]:
    print(' ', l.strip()[-150:])

# Trend filter stats
tf_blocked = [l for l in lines if 'TREND FILTER' in l]
print(f'\nTrend filter blocks: {len(tf_blocked)}')
up_blocked = sum(1 for l in tf_blocked if 'Trend=UP' in l)
down_blocked = sum(1 for l in tf_blocked if 'Trend=DOWN' in l)
none_blocked = sum(1 for l in tf_blocked if 'NONE' in l or 'CONFLICT' in l)
print(f'  Blocked (UP trend, SELL signal): {up_blocked}')
print(f'  Blocked (DOWN trend, BUY signal): {down_blocked}')
print(f'  Blocked (no trend/conflict): {none_blocked}')


with open('logs/20260218.log', 'r', encoding='utf-16', errors='replace') as f:
    content = f.read()

lines = content.split('\n')
print(f'Total lines: {len(lines)}')

trend_blocks = [l for l in lines if 'TREND FILTER' in l]
print(f'\n=== TREND FILTER BLOCKS: {len(trend_blocks)} ===')
for l in trend_blocks[:20]:
    print(l.strip()[-120:])

trades = [l for l in lines if ('BUY market' in l or 'SELL market' in l or
          'BUY stop' in l or 'SELL stop' in l or
          'BUY limit' in l or 'SELL limit' in l)]
print(f'\n=== PLACED TRADES: {len(trades)} ===')
for l in trades:
    print(l.strip()[-150:])

atr_lines = [l for l in lines if 'ATR-based SL: ATR=' in l]
atr_vals = []
for l in atr_lines:
    m = re.search(r'ATR=(\d+\.?\d*)pts', l)
    if m:
        atr_vals.append(float(m.group(1)))
print(f'\n=== ATR SL CALCULATIONS: {len(atr_lines)} ===')
if atr_vals:
    print(f'ATR range: {min(atr_vals):.0f} - {max(atr_vals):.0f} pts  (avg {sum(atr_vals)/len(atr_vals):.0f} pts)')
    for l in atr_lines[:5]:
        print(l.strip()[-150:])

rr_lines = [l for l in lines if 'CONSISTENT RR' in l]
print(f'\n=== PASSED TREND FILTER (CONSISTENT RR): {len(rr_lines)} ===')
for l in rr_lines[:10]:
    print(l.strip()[-150:])

blocked = [l for l in lines if 'MAX SL RISK' in l or 'TRADE BLOCKED' in l]
print(f'\n=== BLOCKED BY SL RISK: {len(blocked)} ===')

final_bal = None
for l in reversed(lines):
    m = re.search(r'Balance=\$(\d+\.?\d*)', l)
    if m:
        final_bal = float(m.group(1))
        break
print(f'\n=== FINAL BALANCE: ${final_bal} ===')
