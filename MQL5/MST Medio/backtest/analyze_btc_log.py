"""Analyze BTC Strategy Tester log - detailed trade-by-trade PnL."""
import re
import sys

logfile = sys.argv[1] if len(sys.argv) > 1 else "/Users/tuan/GitProject/metatrader/MQL5/MST Medio/20260216_btc.log"

with open(logfile, "r", encoding="utf-16-le", errors="replace") as f:
    lines = f.readlines()

print(f"Total lines: {len(lines)}")

# --- 1. Parse settings ---
for line in lines[:40]:
    l = line.strip()
    if "InpMaxRiskPct" in l or "InpLotSize" in l or "InpPartialTP" in l:
        print(f"  Setting: {l.split('Tester')[-1].strip()}")
    if "initial deposit" in l.lower() or "calculate profit" in l.lower():
        print(f"  {l.split('Tester')[-1].strip()}")

# --- 2. Parse ALL alerts (signals) ---
signals = []
for i, line in enumerate(lines):
    m = re.search(r'Alert: MST Medio: (BUY|SELL) \| Entry=([\d.]+) SL=([\d.]+) TP=([\d.]+)', line)
    if m:
        ts_m = re.search(r'(\d{4}\.\d{2}\.\d{2}\s+\d{2}:\d{2}:\d{2})', line)
        ts = ts_m.group(1) if ts_m else "?"
        signals.append({
            'ts': ts,
            'dir': m.group(1),
            'entry': float(m.group(2)),
            'sl': float(m.group(3)),
            'tp': float(m.group(4)),
            'line': i
        })

# --- 3. Parse ALL deals ---
deals = []
for i, line in enumerate(lines):
    m = re.search(r'deal #(\d+) (buy|sell) ([\d.]+) \w+ at ([\d.]+)', line)
    if m:
        deals.append({
            'id': int(m.group(1)),
            'action': m.group(2),
            'lot': float(m.group(3)),
            'price': float(m.group(4)),
            'line': i
        })

# --- 4. Parse SL/TP triggers with order numbers ---
sl_triggers = []
tp_triggers = []
stop_outs = []
for line in lines:
    m = re.search(r'stop loss triggered #(\d+) (buy|sell) ([\d.]+) \w+ ([\d.]+) sl: ([\d.]+)', line)
    if m:
        sl_triggers.append({
            'order': int(m.group(1)),
            'dir': m.group(2),
            'lot': float(m.group(3)),
            'entry': float(m.group(4)),
            'sl': float(m.group(5))
        })

    m = re.search(r'take profit triggered #(\d+) (buy|sell) ([\d.]+) \w+ ([\d.]+) sl: ([\d.]+) tp: ([\d.]+)', line)
    if m:
        tp_triggers.append({
            'order': int(m.group(1)),
            'dir': m.group(2),
            'lot': float(m.group(3)),
            'entry': float(m.group(4)),
            'sl': float(m.group(5)),
            'tp': float(m.group(6))
        })
    
    if 'stop out' in line.lower() and 'position' in line.lower():
        stop_outs.append(line.strip())

# --- 5. Reconstruct trade PnL ---
print(f"\n{'='*80}")
print(f"SIGNALS: {len(signals)} | DEALS: {len(deals)} | TP triggers: {len(tp_triggers)} | SL triggers: {len(sl_triggers)}")
print(f"{'='*80}")

# For each signal, figure out what happened
# Partial TP creates 2 positions per signal:
#   Part1: has TP → closed by TP or SL 
#   Part2: no TP → SL moves to entry after Part1 TP hit → closed by moved SL (breakeven) or original SL

print(f"\n--- Signal-by-Signal Analysis ---")
total_pnl = 0
wins = 0
losses = 0
breakevens = 0

for sig in signals:
    entry = sig['entry']
    sl = sig['sl']
    tp = sig['tp']
    d = sig['dir']
    sl_dist = abs(entry - sl)
    tp_dist = abs(tp - entry)
    
    # Find TP/SL triggers for this signal's orders
    sig_tps = [t for t in tp_triggers if abs(t['entry'] - entry) < 0.01]
    sig_sls = [s for s in sl_triggers if abs(s['entry'] - entry) < 0.01]
    
    # Calculate PnL for Part1 and Part2
    part1_pnl = 0  # Part with TP
    part2_pnl = 0  # Part without TP (trailing)
    
    if sig_tps:
        # Part1 hit TP
        part1_pnl = tp_dist  # 1R worth of pips in TP direction
    
    for s in sig_sls:
        if abs(s['sl'] - sl) < 0.01:
            # Hit original SL → full loss on that part
            if d == 'BUY':
                part_pnl = -(entry - s['sl'])  # negative
            else:
                part_pnl = -(s['sl'] - entry)  # negative
            
            if sig_tps:
                part2_pnl = part_pnl  # this is Part2's SL
            else:
                part1_pnl = part_pnl  # Part1 also hit SL
        elif abs(s['sl'] - entry) < 0.01:
            # SL moved to entry (breakeven) → Part2
            part2_pnl = 0  # breakeven
    
    # If both parts hit SL at same price
    num_sls_at_original = sum(1 for s in sig_sls if abs(s['sl'] - sl) < 0.01)
    num_sls_at_entry = sum(1 for s in sig_sls if abs(s['sl'] - entry) < 0.01)
    
    if num_sls_at_original == 2 and not sig_tps:
        # Both parts hit original SL → full loss x2
        part1_pnl = -sl_dist
        part2_pnl = -sl_dist
    elif sig_tps and num_sls_at_entry == 1:
        # Part1 hit TP, Part2 hit BE
        part1_pnl = tp_dist
        part2_pnl = 0
    elif sig_tps and num_sls_at_original == 1:
        # Part1 hit TP, Part2 hit original SL
        part1_pnl = tp_dist
        part2_pnl = -sl_dist
    
    sig_pnl = part1_pnl + part2_pnl
    total_pnl += sig_pnl
    
    if sig_pnl > 0:
        wins += 1
        tag = "WIN"
    elif sig_pnl < 0:
        losses += 1
        tag = "LOSS"
    else:
        breakevens += 1
        tag = "BE"
    
    r_value = sig_pnl / sl_dist if sl_dist > 0 else 0
    
    print(f"  {sig['ts']} {d:4s} Entry={entry:.2f} SL={sl:.2f} TP={tp:.2f} "
          f"SL_dist={sl_dist:.2f} | P1={part1_pnl:+.2f} P2={part2_pnl:+.2f} "
          f"Total={sig_pnl:+.2f} ({r_value:+.2f}R) [{tag}]"
          f" | TPs={len(sig_tps)} SLs={len(sig_sls)}")

print(f"\n{'='*80}")
print(f"SUMMARY: {len(signals)} signals")
print(f"  Wins:       {wins}")
print(f"  Losses:     {losses}")
print(f"  Breakevens: {breakevens}")
print(f"  Win Rate:   {wins/len(signals)*100:.1f}%" if signals else "  N/A")
print(f"  Total PnL:  {total_pnl:+.2f} pips")
print(f"  Total PnL (R): {sum(((abs(s['tp']-s['entry']) + abs(s['entry']-s['sl'])) if any(abs(t['entry']-s['entry'])<0.01 for t in tp_triggers) else -abs(s['entry']-s['sl'])*2) / abs(s['entry']-s['sl']) for s in signals if abs(s['entry']-s['sl'])>0):+.2f}R (approx)")

# Check for stop out
for so in stop_outs:
    print(f"\n  ⚠️ STOP OUT: {so[:200]}")

# Final balance
for line in reversed(lines):
    if 'final balance' in line.lower():
        print(f"\n  Final balance: {line.strip().split('final balance')[-1].strip()}")
        break

# Check test period
first_ts = signals[0]['ts'] if signals else "?"
last_ts = signals[-1]['ts'] if signals else "?"
print(f"\n  Test period: {first_ts} → {last_ts}")
print(f"  ⚠️ Only {len(signals)} signals in ~10 days!")
