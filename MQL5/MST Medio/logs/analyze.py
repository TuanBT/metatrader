import subprocess, re

raw = subprocess.run(['iconv', '-f', 'UTF-16LE', '-t', 'UTF-8', '20260217.log'], capture_output=True, text=True).stdout

lines = [l for l in raw.split('\n') if 'take profit' in l or 'stop loss' in l]

trades = []
for l in lines:
    is_tp = 'take profit' in l
    m = re.search(r'(buy|sell) 0\.01 BTCUSDm (\d+\.\d+)', l)
    sl_m = re.search(r'sl: (\d+\.\d+)', l)
    close_m = re.search(r'at (\d+\.\d+)\]', l)
    date_m = re.search(r'(2025\.\d+\.\d+ \d+:\d+:\d+)', l)
    if m and sl_m and close_m:
        d = m.group(1)
        entry = float(m.group(2))
        sl = float(sl_m.group(1))
        close_p = float(close_m.group(1))
        sl_dist = abs(entry - sl)
        if d == 'buy':
            pnl = close_p - entry
        else:
            pnl = entry - close_p
        trades.append({
            'type': 'TP' if is_tp else 'SL',
            'date': date_m.group(1) if date_m else '',
            'dir': d,
            'entry': entry,
            'sl': sl,
            'sl_dist': sl_dist,
            'pnl': pnl,
            'risk_pct_1000': sl_dist / 1000 * 100,
        })

sl_dists = [t['sl_dist'] for t in trades]
print(f"Total trades: {len(trades)}")
print(f"TP: {sum(1 for t in trades if t['type']=='TP')}, SL: {sum(1 for t in trades if t['type']=='SL')}")
print(f"SL dist: min={min(sl_dists):.0f}, max={max(sl_dists):.0f}, avg={sum(sl_dists)/len(sl_dists):.0f} pips")
print()

# Distribution
bins = [(0,100),(100,200),(200,400),(400,600),(600,1000),(1000,2000)]
for lo,hi in bins:
    c = sum(1 for x in sl_dists if lo <= x < hi)
    print(f"  SL {lo}-{hi} pips: {c} trades ({c*100//len(sl_dists)}%) → risk {lo*100//1000}-{hi*100//1000}% of $1000")

print()

# Simulate with OrderCalcProfit-like: 0.01 lot BTC, 1 pip ~ $0.01 (contract size 1)
# Actually in "profit in pips" mode, the profit IS the pip distance
# So SL distance 500 pips = $500 loss equivalent
# Check how many trades would be blocked at risk% thresholds
balance = 1000
for max_risk_pct in [5, 10, 15, 20]:
    max_sl = balance * max_risk_pct / 100  # e.g. 10% of $1000 = $100 = 100 pips
    blocked = sum(1 for x in sl_dists if x > max_sl)
    passed = len(sl_dists) - blocked
    # Simulate PnL with only passed trades
    sim_pnl = sum(min(t['pnl'], 0) if t['sl_dist'] > max_sl else t['pnl'] for t in trades if t['sl_dist'] <= max_sl)
    tp_passed = sum(1 for t in trades if t['sl_dist'] <= max_sl and t['type'] == 'TP')
    sl_passed = sum(1 for t in trades if t['sl_dist'] <= max_sl and t['type'] == 'SL')
    print(f"MaxSLRisk={max_risk_pct}% (max {max_sl:.0f} pips): {passed} trades pass, {blocked} blocked | TP:{tp_passed} SL:{sl_passed} | Net PnL: {sim_pnl:.0f} pips")

print()
print("=== Balance needed for trades at different MaxSLRisk ===")
for max_risk_pct in [10, 15, 20]:
    # What balance needed so 50%, 75%, 100% of trades pass?
    sorted_dists = sorted(sl_dists)
    for pctile in [50, 75, 100]:
        idx = min(int(len(sorted_dists) * pctile / 100), len(sorted_dists)-1)
        sl_at_pctile = sorted_dists[idx]
        balance_needed = sl_at_pctile / (max_risk_pct / 100)
        print(f"  MaxSLRisk={max_risk_pct}%, {pctile}% trades pass (SL<={sl_at_pctile:.0f}): need ${balance_needed:.0f}")

print()
print("=== Dynamic balance sim (starting bal varies) ===")
for start_bal in [1000, 2000, 3000, 5000, 10000]:
    for max_risk_pct in [10, 15, 20]:
        bal = start_bal
        peak = start_bal
        n_trades = 0
        n_blocked = 0
        n_tp = 0
        n_sl = 0
        for t in trades:
            max_sl = bal * max_risk_pct / 100
            if t['sl_dist'] > max_sl:
                n_blocked += 1
                continue
            n_trades += 1
            bal += t['pnl']
            if t['type'] == 'TP':
                n_tp += 1
            else:
                n_sl += 1
            if bal > peak:
                peak = bal
            if bal <= 0:
                print(f"  ${start_bal} MaxSLRisk={max_risk_pct}%: BLOWN at trade#{n_trades} | {n_tp}TP {n_sl}SL")
                break
        else:
            ret = (bal-start_bal)/start_bal*100
            print(f"  ${start_bal} MaxSLRisk={max_risk_pct}%: ${bal:.0f} ({ret:+.1f}%) | {n_trades} trades ({n_tp}TP {n_sl}SL) | {n_blocked} blocked | peak=${peak:.0f}")
