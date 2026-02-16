"""Parse MT5 Strategy Tester log to analyze trade results."""
import re
import sys

logfile = sys.argv[1] if len(sys.argv) > 1 else "/Users/tuan/GitProject/metatrader/MQL5/MST Medio/20260216.log"

with open(logfile, "r", encoding="utf-16-le", errors="replace") as f:
    lines = f.readlines()

print(f"Total lines: {len(lines)}")

# Count key events
signals = 0
skips = 0
trades_opened = 0
sl_hits = 0
tp_hits = 0
risk_ok = 0
pending_cancel = 0
pending_start = 0
deals = 0

balance_changes = []
current_balance = 500.0

for line in lines:
    if "MST Medio:" in line and ("BUY" in line or "SELL" in line) and "Alert:" in line:
        signals += 1
    if "SKIP TRADE" in line:
        skips += 1
    if "Risk check OK" in line:
        risk_ok += 1
    if "Pending BUY:" in line or "Pending SELL:" in line:
        if "cancelled" not in line:
            pending_start += 1
    if "cancelled" in line:
        pending_cancel += 1
    if "stop loss triggered" in line:
        sl_hits += 1
    if "take profit triggered" in line:
        tp_hits += 1
    if "deal " in line and "done" in line:
        deals += 1
    if "Partial TP [Hedging]:" in line or "Partial TP [Netting]:" in line:
        trades_opened += 1
    if "BUY market" in line or "SELL market" in line:
        trades_opened += 1

# Find final balance
for line in reversed(lines):
    m = re.search(r'final balance\s+([\d.]+)', line)
    if m:
        current_balance = float(m.group(1))
        break

# Find profit/loss info
for line in lines:
    if "calculate profit" in line:
        print(f"  {line.strip()}")
    if "initial deposit" in line:
        print(f"  {line.strip()}")
    if "final balance" in line:
        print(f"  {line.strip()}")

print(f"\n--- Event Summary ---")
print(f"Pending states started: {pending_start}")
print(f"Pending cancelled:      {pending_cancel}")
print(f"Signals detected:       {signals}")
print(f"Skipped (MaxRisk):      {skips}")
print(f"Risk OK (passed):       {risk_ok}")
print(f"Trades opened:          {trades_opened}")
print(f"TP hits:                {tp_hits}")
print(f"SL hits:                {sl_hits}")
print(f"Total deals:            {deals}")
print(f"Final balance:          {current_balance} pips")

# Extract all signal details
print(f"\n--- Signal Details ---")
signal_lines = []
for i, line in enumerate(lines):
    if "Alert: MST Medio:" in line:
        # Get timestamp
        m = re.search(r'(\d{4}\.\d{2}\.\d{2}\s+\d{2}:\d{2}:\d{2})', line)
        ts = m.group(1) if m else "?"
        
        # Get direction and prices
        m2 = re.search(r'(BUY|SELL)\s*\|\s*Entry=([\d.]+)\s*SL=([\d.]+)\s*TP=([\d.]+)', line)
        if m2:
            direction = m2.group(1)
            entry = float(m2.group(2))
            sl = float(m2.group(3))
            tp = float(m2.group(4))
            sl_dist = abs(entry - sl)
            tp_dist = abs(tp - entry)
            rr = tp_dist / sl_dist if sl_dist > 0 else 0
            
            # Check next few lines for skip or ok
            status = "?"
            for j in range(i+1, min(i+10, len(lines))):
                if "SKIP TRADE" in lines[j]:
                    status = "SKIPPED"
                    break
                elif "Risk check OK" in lines[j]:
                    status = "TRADED"
                    break
            
            signal_lines.append((ts, direction, entry, sl, tp, sl_dist, rr, status))

for ts, d, e, sl, tp, sld, rr, st in signal_lines:
    tag = "  <<< SKIP" if st == "SKIPPED" else ""
    print(f"  {ts} {d:4s} Entry={e:.2f} SL={sl:.2f} TP={tp:.2f} SL_dist={sld:.2f} RR={rr:.2f} [{st}]{tag}")

print(f"\nTotal signals: {len(signal_lines)}")
print(f"  Traded: {sum(1 for s in signal_lines if s[-1] == 'TRADED')}")
print(f"  Skipped: {sum(1 for s in signal_lines if s[-1] == 'SKIPPED')}")
print(f"  Unknown: {sum(1 for s in signal_lines if s[-1] == '?')}")
