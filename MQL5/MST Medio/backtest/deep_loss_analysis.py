#!/usr/bin/env python3
"""
Deep analysis of trading performance to understand WHY the bot keeps losing.
Phân tích sâu lý do bot thua lỗ liên tục.
"""
import re
from collections import defaultdict
from datetime import datetime

def analyze():
    with open("/Users/tuan/GitProject/metatrader/MQL5/MST Medio/logs/20260218.log", 'r', encoding='utf-16') as f:
        lines = f.readlines()
    
    # ── Extract all key events ──
    trades = []         # Executed trades
    blocked = []        # Blocked trades  
    signals = []        # All signals generated
    pending = []        # Pending signals
    cancelled = []      # Cancelled signals
    balance_changes = []
    daily_loss_pauses = []
    be_events = []      # Breakeven events
    tp_events = []      # Take profit events
    sl_events = []      # Stop loss events
    
    current_trade = {}
    balance = 1000.0
    
    for line in lines:
        line = line.strip()
        
        # Extract timestamp
        ts_match = re.search(r'(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2})', line)
        timestamp = ts_match.group(1) if ts_match else ""
        
        # ── Signals ──
        sig_match = re.search(r'🔔 MST Medio: (BUY|SELL) \| Entry=([\d.]+) SL=([\d.]+) TP=([\d.]+)', line)
        if sig_match:
            direction, entry, sl, tp = sig_match.groups()
            entry, sl, tp = float(entry), float(sl), float(tp)
            sl_dist = abs(entry - sl)
            tp_dist = abs(tp - entry)
            rr_ratio = tp_dist / sl_dist if sl_dist > 0 else 0
            signals.append({
                'time': timestamp, 'dir': direction,
                'entry': entry, 'sl': sl, 'tp': tp,
                'sl_dist': sl_dist, 'tp_dist': tp_dist,
                'rr': rr_ratio
            })
        
        # ── Blocked trades ──
        if '🛑 MAX SL RISK' in line:
            blocked.append({'time': timestamp, 'line': line})
        
        # ── Pending signals ──
        pend_match = re.search(r'ℹ️ Pending (BUY|SELL):', line)
        if pend_match:
            pending.append({'time': timestamp, 'dir': pend_match.group(1)})
        
        # ── Cancelled signals ──
        if 'cancelled' in line.lower():
            cancelled.append({'time': timestamp, 'line': line})
        
        # ── Trade execution (order filled) ──
        fill_match = re.search(r'(buy|sell)\s+([\d.]+)\s+.*?at\s+([\d.]+)', line, re.IGNORECASE)
        if fill_match and 'order' in line.lower():
            pass  # MT5 tester format may differ
        
        # ── Position closed / Deal ──
        deal_match = re.search(r'deal\s+#(\d+)\s+(buy|sell)\s+([\d.]+)\s+.*?at\s+([\d.]+)', line, re.IGNORECASE)
        if deal_match:
            trades.append({'time': timestamp, 'line': line})
        
        # ── Breakeven moved ──
        if 'BE' in line and ('move' in line.lower() or 'breakeven' in line.lower()):
            be_events.append({'time': timestamp, 'line': line})
        
        # ── TP/SL hits ──
        if 'tp' in line.lower() and ('hit' in line.lower() or 'take profit' in line.lower()):
            tp_events.append({'time': timestamp})
        if 'sl' in line.lower() and ('hit' in line.lower() or 'stop loss' in line.lower()):
            sl_events.append({'time': timestamp})
        
        # ── Daily loss pause ──
        if 'daily' in line.lower() and 'paus' in line.lower():
            daily_loss_pauses.append({'time': timestamp, 'line': line})
        
        # ── Balance tracking ──
        bal_match = re.search(r'Balance[=:]\s*\$([\d.]+)', line)
        if bal_match:
            balance_changes.append({'time': timestamp, 'balance': float(bal_match.group(1))})
        
        # ── Risk info ──
        risk_match = re.search(r'Risk[=:]\s*([\d.]+)%\s*\(\$([\d.]+)\)', line)
        
        # ── "Cần nạp thêm" ──
        nap_match = re.search(r'Cần nạp thêm: \$([\d.]+) \(tổng \$([\d.]+)\)', line)
    
    # ══════════ ANALYSIS ══════════
    print("=" * 60)
    print("   DEEP TRADE PERFORMANCE ANALYSIS - MST Medio")
    print("=" * 60)
    
    print(f"\n📡 **SIGNAL OVERVIEW:**")
    print(f"   Total Pending Signals: {len(pending)}")
    print(f"   Total Confirmed Signals (🔔): {len(signals)}")
    print(f"   Cancelled Signals: {len(cancelled)}")
    print(f"   Blocked by SL Risk: {len(blocked)}")
    
    if signals:
        executed = len(signals) - len(blocked) 
        print(f"   Executed Trades: ~{executed}")
        print(f"   Execution Rate: {executed/len(signals)*100:.1f}%")
    
    # ── Risk:Reward Analysis ──
    if signals:
        rr_ratios = [s['rr'] for s in signals]
        sl_dists = [s['sl_dist'] for s in signals]
        tp_dists = [s['tp_dist'] for s in signals]
        
        print(f"\n📊 **RISK:REWARD RATIO ANALYSIS:**")
        print(f"   Average RR: 1:{sum(rr_ratios)/len(rr_ratios):.2f}")
        print(f"   Min RR: 1:{min(rr_ratios):.2f}")
        print(f"   Max RR: 1:{max(rr_ratios):.2f}")
        print(f"   Target RR (1:3): {'✅ MET' if sum(rr_ratios)/len(rr_ratios) >= 3.0 else '❌ NOT MET'}")
        
        print(f"\n📏 **SL DISTANCE DISTRIBUTION:**")
        print(f"   Average SL: {sum(sl_dists)/len(sl_dists):.0f} pts ({sum(sl_dists)/len(sl_dists)/10:.0f} pips)")
        print(f"   Min SL: {min(sl_dists):.0f} pts")  
        print(f"   Max SL: {max(sl_dists):.0f} pts")
        
        print(f"\n🎯 **TP DISTANCE DISTRIBUTION:**")
        print(f"   Average TP: {sum(tp_dists)/len(tp_dists):.0f} pts ({sum(tp_dists)/len(tp_dists)/10:.0f} pips)")
    
    # ── Temporal Analysis: Performance over time ──
    if signals:
        print(f"\n📅 **MONTHLY SIGNAL DISTRIBUTION:**")
        monthly = defaultdict(list)
        for s in signals:
            month = s['time'][:7]  # YYYY.MM
            monthly[month].append(s)
        
        for month in sorted(monthly.keys()):
            sigs = monthly[month]
            buy_count = len([s for s in sigs if s['dir'] == 'BUY'])
            sell_count = len([s for s in sigs if s['dir'] == 'SELL'])
            avg_rr = sum(s['rr'] for s in sigs) / len(sigs)
            print(f"   {month}: {len(sigs)} signals (BUY:{buy_count} SELL:{sell_count}) | Avg RR 1:{avg_rr:.2f}")
    
    # ── Balance Curve Analysis ──
    if balance_changes:
        print(f"\n💰 **BALANCE PROGRESSION:**")
        # Group by month
        monthly_bal = defaultdict(list)
        for b in balance_changes:
            month = b['time'][:7]
            monthly_bal[month].append(b['balance'])
        
        for month in sorted(monthly_bal.keys()):
            bals = monthly_bal[month]
            print(f"   {month}: Start=${bals[0]:.0f} End=${bals[-1]:.0f} (Change: ${bals[-1]-bals[0]:+.0f})")
    
    # ── Detailed: cancelled vs retro ──
    retro_count = sum(1 for c in cancelled if 'retro' in c['line'].lower())
    price_touch = sum(1 for c in cancelled if 'Price touched' in c['line'])
    other_cancel = len(cancelled) - retro_count - price_touch
    
    print(f"\n🔍 **SIGNAL CANCELLATION BREAKDOWN:**")
    print(f"   Retro-cancelled (Entry touched before confirm): {retro_count}")
    print(f"   Price touched Entry (invalidated): {price_touch}")
    print(f"   Other cancellations: {other_cancel}")
    print(f"   Total cancelled: {len(cancelled)}")
    
    if len(cancelled) > 0 and len(pending) > 0:
        cancel_rate = len(cancelled) / len(pending) * 100
        print(f"   Cancellation Rate: {cancel_rate:.1f}%")
    
    # ── Look for actual trade results (profit/loss) ──
    print(f"\n📋 **SEARCHING FOR ACTUAL TRADE RESULTS...**")
    
    profit_lines = []
    loss_lines = []
    trade_results = []
    
    for line in lines:
        line = line.strip()
        # Look for profit/loss patterns
        if any(kw in line for kw in ['profit', 'loss', 'closed', 'deal', 'SL hit', 'TP hit', 'stopped']):
            if 'Expert' in line:
                trade_results.append(line[:200])
    
    if trade_results:
        print(f"   Found {len(trade_results)} trade result lines")
        for r in trade_results[:10]:
            print(f"   → {r}")
    else:
        print(f"   ⚠️ No explicit trade result lines found")
        print(f"   Checking for order/deal events...")
        
        order_events = []
        for line in lines:
            line = line.strip()
            if re.search(r'(order|deal|position|close|filled)', line, re.IGNORECASE):
                if 'Expert' not in line and 'Tester' not in line:
                    continue
                order_events.append(line[:200])
        
        if order_events:
            print(f"   Found {len(order_events)} order/deal events:")
            for e in order_events[:15]:
                print(f"   → {e}")
        else:
            print(f"   No order events found - checking final tester summary...")
    
    # ── Look for tester summary (usually at end of log) ──
    print(f"\n📈 **TESTER SUMMARY (last 50 lines):**")
    for line in lines[-50:]:
        line = line.strip()
        if line and len(line) > 10:
            print(f"   {line[:150]}")
    
    # ── Key Patterns Analysis ──
    print(f"\n" + "=" * 60)
    print(f"   ROOT CAUSE ANALYSIS")
    print(f"=" * 60)
    
    print(f"""
🔍 **VẤN ĐỀ CHÍNH CẦN XÁC ĐỊNH:**

1. **Signal Quality vs Trend**
   - Signals: {len(signals)} confirmed
   - Cancelled: {len(cancelled)} ({len(cancelled)/len(pending)*100:.0f}% of pending)
   - Pattern: Nhiều signal bị cancel → thị trường sideway/choppy
   
2. **Capital Constraint**  
   - Blocked trades: {len(blocked)} ({len(blocked)/len(signals)*100:.0f}% of signals)
   - ➡️ Account $1000 quá nhỏ cho BTC volatility
   
3. **Risk:Reward Ratio**
   - Current avg: 1:{sum(rr_ratios)/len(rr_ratios):.2f}
   - Target: 1:3.0
   - {'✅ RR đã đạt target 1:3' if sum(rr_ratios)/len(rr_ratios) >= 2.9 else '❌ RR chưa đạt target 1:3'}

4. **Trend Detection Gap**
   - Hiện tại: Pure breakout strategy (no trend filter)
   - Vấn đề: Trade cả 2 chiều trong sideway → whipsaw losses
   - Cần: HTF trend filter để chỉ trade theo trend chính
""")

if __name__ == "__main__":
    analyze()
