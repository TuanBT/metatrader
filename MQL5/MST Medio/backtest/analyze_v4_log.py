import re

log_file = "logs/20260218.log"
with open(log_file, 'r', encoding='utf-16', errors='ignore') as f:
    lines = f.readlines()

placed = sum(1 for l in lines if 'PlaceOrder:' in l)
sl_hits = sum(1 for l in lines if 'stop loss triggered' in l)
tp_hits = sum(1 for l in lines if 'take profit triggered' in l)
partial = [l for l in lines if 'PARTIAL TP:' in l]
be_moved = [l for l in lines if 'SL moved to breakeven' in l]
blocked = sum(1 for l in lines if 'blocked' in l.lower() and ('SELL' in l or 'BUY' in l))

# final balance
final = None
for l in lines:
    m = re.search(r'final balance ([\d.]+)', l)
    if m:
        final = float(m.group(1))

# get all balance values to track progression
balances = []
for l in lines:
    m = re.search(r'Balance=\$([0-9,.]+)', l)
    if m:
        balances.append(float(m.group(1).replace(',','')))

print("=== BACKTEST v4 RESULTS (AllowNoTrend + PartialTP) ===")
print(f"Orders placed: {placed}")
print(f"SL hits: {sl_hits}")
print(f"TP hits: {tp_hits}")
print(f"Partial TP hits: {len(partial)}")
print(f"BE moves: {len(be_moved)}")
print(f"Trend blocks: {blocked}")
print(f"Final balance (from tester): ${final}")
if balances:
    print(f"Balance range: ${min(balances):.2f} - ${max(balances):.2f}")
    print(f"Last logged balance: ${balances[-1]:.2f}")

total_closed = sl_hits + tp_hits
if total_closed > 0:
    print(f"Win rate (full TP): {tp_hits}/{total_closed} = {tp_hits/total_closed*100:.1f}%")

print()
print("Sample partial TPs:")
for l in partial[:5]:
    print(" ", l.strip())

print()
print("Sample BE moves:")
for l in be_moved[:5]:
    print(" ", l.strip())

