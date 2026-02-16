"""
Analyze MT5 logs to understand WHY the strategy loses.
Focus on: TP/SL counts, implied RR, and what would make it profitable.
"""
import re
import sys
from pathlib import Path

LOG_DIR = Path("/Users/tuan/GitProject/metatrader/MQL5/MST Medio/logs")
PAIRS = ["BTCUSDm", "XAUUSDm", "EURUSDm", "USDJPYm", "ETHUSDm", "USOILm"]


def parse_log(log_path):
    for enc in ["utf-16-le", "utf-16", "utf-8", "latin-1"]:
        try:
            with open(log_path, "r", encoding=enc, errors="replace") as f:
                content = f.readlines()
            break
        except:
            continue
    
    signals = []
    for line in content:
        m = re.search(
            r'(\d{4}\.\d{2}\.\d{2}\s+\d{2}:\d{2}:\d{2}).*'
            r'Alert: MST Medio:\s*(BUY|SELL)\s*\|\s*Entry=([\d.]+)\s*SL=([\d.]+)\s*TP=([\d.]+)',
            line
        )
        if m:
            entry = float(m.group(3))
            sl = float(m.group(4))
            tp = float(m.group(5))
            risk = abs(entry - sl)
            reward = abs(tp - entry)
            rr = reward / risk if risk > 0 else 0
            signals.append({
                "time": m.group(1),
                "dir": m.group(2),
                "entry": entry,
                "sl": sl,
                "tp": tp,
                "risk": risk,
                "reward": reward,
                "rr": rr,
            })
    
    tp_hits = sum(1 for l in content if "take profit triggered" in l)
    sl_hits = sum(1 for l in content if "stop loss triggered" in l)
    
    final_bal = 0
    deposit = 0
    for l in content:
        m = re.search(r'initial deposit\s+(\d+)', l)
        if m:
            deposit = int(m.group(1))
    for l in reversed(content):
        m = re.search(r'final balance\s+([\d.-]+)', l)
        if m:
            final_bal = float(m.group(1))
            break
    
    return signals, tp_hits, sl_hits, final_bal, deposit


print("=" * 80)
print("  MT5 STRATEGY TESTER — DETAILED ANALYSIS")
print("=" * 80)

all_rr = []
all_pairs = {}

for pair in PAIRS:
    log = LOG_DIR / f"{pair}.log"
    if not log.exists():
        continue
    
    signals, tp, sl, bal, dep = parse_log(str(log))
    
    total_trades = tp + sl
    wr = tp / total_trades * 100 if total_trades > 0 else 0
    profit = bal - dep if dep > 0 else bal
    
    # RR analysis
    rrs = [s["rr"] for s in signals]
    avg_rr = sum(rrs) / len(rrs) if rrs else 0
    med_rr = sorted(rrs)[len(rrs)//2] if rrs else 0
    
    # RR distribution
    rr_under_0_5 = sum(1 for r in rrs if r < 0.5)
    rr_0_5_1 = sum(1 for r in rrs if 0.5 <= r < 1.0)
    rr_1_2 = sum(1 for r in rrs if 1.0 <= r < 2.0)
    rr_2_plus = sum(1 for r in rrs if r >= 2.0)
    
    all_pairs[pair] = {
        "signals": len(signals), "tp": tp, "sl": sl,
        "wr": wr, "profit": profit, "avg_rr": avg_rr, "med_rr": med_rr,
        "rr_dist": (rr_under_0_5, rr_0_5_1, rr_1_2, rr_2_plus),
    }
    all_rr.extend(rrs)
    
    print(f"\n📊 {pair}:")
    print(f"  Signals: {len(signals)}")
    print(f"  TP: {tp} | SL: {sl} | WR: {wr:.1f}%")
    print(f"  Profit: {profit:+.2f} pips")
    print(f"  Avg RR (signal): {avg_rr:.2f} | Median: {med_rr:.2f}")
    print(f"  RR distribution: <0.5={rr_under_0_5}({rr_under_0_5/len(signals)*100:.0f}%) | "
          f"0.5-1={rr_0_5_1}({rr_0_5_1/len(signals)*100:.0f}%) | "
          f"1-2={rr_1_2}({rr_1_2/len(signals)*100:.0f}%) | "
          f"2+={rr_2_plus}({rr_2_plus/len(signals)*100:.0f}%)")
    
    # Expected value per trade
    # If WR=wr%, avg_win=avg_rr (in R), avg_loss=-1R
    # EV = wr * avg_rr - (1-wr) * 1
    if wr > 0:
        ev = (wr/100) * avg_rr - (1 - wr/100) * 1.0
        print(f"  Expected Value: {ev:+.3f}R per trade (if avg win = avg RR)")


# Overall
print(f"\n\n{'='*80}")
print(f"  OVERALL ANALYSIS")
print(f"{'='*80}")

print(f"\n  All signals RR distribution:")
if all_rr:
    avg = sum(all_rr) / len(all_rr)
    med = sorted(all_rr)[len(all_rr)//2]
    print(f"  Total signals: {len(all_rr)}")
    print(f"  Avg RR: {avg:.2f} | Median: {med:.2f}")
    print(f"  Min: {min(all_rr):.2f} | Max: {max(all_rr):.2f}")

# What WR is needed for breakeven?
print(f"\n  🔑 Breakeven Analysis:")
for avg_win_rr in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]:
    # breakeven: wr * avg_win - (1-wr) * 1 = 0
    # wr * (avg_win + 1) = 1
    # wr = 1 / (avg_win + 1)
    be_wr = 1.0 / (avg_win_rr + 1.0) * 100
    print(f"  If avg win = {avg_win_rr:.2f}R → need WR >= {be_wr:.1f}% to breakeven")

print(f"\n  📋 Summary per pair:")
print(f"  {'Pair':<10s} {'Sigs':>5s} {'TP':>4s} {'SL':>4s} {'WR%':>6s} {'AvgRR':>6s} {'Profit':>10s} {'Verdict':>10s}")
print(f"  {'-'*60}")
for pair in PAIRS:
    if pair not in all_pairs:
        continue
    p = all_pairs[pair]
    verdict = "✅ WIN" if p["profit"] > 0 else "❌ LOSE"
    print(f"  {pair:<10s} {p['signals']:>5d} {p['tp']:>4d} {p['sl']:>4d} {p['wr']:>5.1f}% {p['avg_rr']:>6.2f} {p['profit']:>+10.2f} {verdict:>10s}")

total_profit = sum(p["profit"] for p in all_pairs.values())
print(f"  {'TOTAL':<10s} {'':>5s} {'':>4s} {'':>4s} {'':>6s} {'':>6s} {total_profit:>+10.2f}")

# Key insight
print(f"\n\n{'='*80}")
print(f"  💡 KEY INSIGHT")
print(f"{'='*80}")
print(f"""
  Current strategy performance in MT5:
  - WR: ~45-54% across all pairs
  - Average RR on signal: ~1.0-1.5
  - BUT actual avg win RR is lower because many TPs are tiny
  
  The problem:
  - TP = high/low of confirm candle → often very close to entry
  - SL = swing opposite + 5% buffer → can be far from entry
  - Many signals have RR < 1.0 → even winning these doesn't cover losses
  
  To be profitable with ~50% WR, need avg win > 1.0R
  To be profitable with ~45% WR, need avg win > 1.22R
  
  Possible solutions:
  1. Filter: Only trade signals with RR >= 1.0 (skip low-RR setups)
  2. Fixed RR: Use fixed TP at 1.5R or 2.0R instead of confirm candle
  3. Trailing stop: Let winners run beyond TP
  4. Different exit: Move SL to BE after reaching 1R, let price run
""")
