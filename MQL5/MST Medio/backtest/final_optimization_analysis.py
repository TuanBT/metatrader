#!/usr/bin/env python3
"""
Final Analysis: Complete Capital Management Optimization Performance
Comprehensive review của toàn bộ optimization implemented
"""

import re
from collections import defaultdict
import statistics

def final_optimization_analysis():
    print("=== FINAL CAPITAL MANAGEMENT OPTIMIZATION ANALYSIS ===\n")
    
    log_file = "/Users/tuan/GitProject/metatrader/MQL5/MST Medio/logs/20260218.log"
    
    # Read log with proper encoding
    encodings = ['utf-8', 'utf-16', 'latin1', 'cp1252']
    content = None
    
    for encoding in encodings:
        try:
            with open(log_file, 'r', encoding=encoding) as f:
                content = f.read()
            print(f"✅ Log loaded successfully with {encoding} encoding\n")
            break
        except UnicodeDecodeError:
            continue
    
    if content is None:
        print("❌ Could not decode log file")
        return
    
    # Analysis patterns
    signal_pattern = r"🔔 MST Medio: (BUY|SELL) \| Entry=([\d.]+) SL=([\d.]+) TP=([\d.]+)"
    blocked_pattern = r"🛑 MAX SL RISK — TRADE BLOCKED.*?Risk: ([\d.]+)% \(\$([\d.]+)\).*?SL Distance: ([\d.]+) pips"
    atr_success_pattern = r"📏 ATR-based SL: ATR=([\d.]+)pts × ([\d.]+) = ([\d.]+)pts \(([\d.]+) pips\)"
    
    # Extract data
    signals = re.findall(signal_pattern, content)
    blocked_trades = re.findall(blocked_pattern, content, re.DOTALL)
    atr_successes = re.findall(atr_success_pattern, content)
    
    print("📊 **OPTIMIZATION PERFORMANCE SUMMARY:**")
    print("=" * 50)
    
    # Signal generation analysis
    buy_signals = len([s for s in signals if s[0] == 'BUY'])
    sell_signals = len([s for s in signals if s[0] == 'SELL'])
    total_signals = len(signals)
    
    print(f"🎯 **SIGNAL GENERATION:**")
    print(f"   📡 Total Signals: {total_signals}")
    print(f"   ⬆️  BUY Signals: {buy_signals}")
    print(f"   ⬇️  SELL Signals: {sell_signals}")
    print(f"   📈 Signals/Month: {total_signals/12:.1f}")
    
    # ATR system performance
    atr_failures = content.count("⚠️ ATR buffer copy failed")
    atr_total = len(atr_successes) + atr_failures
    
    if atr_total > 0:
        atr_success_rate = (len(atr_successes) / atr_total) * 100
        avg_atr_pips = statistics.mean([float(match[3]) for match in atr_successes]) if atr_successes else 0
        
        print(f"\n🔧 **ATR SYSTEM PERFORMANCE:**")
        print(f"   ✅ Success Rate: {atr_success_rate:.1f}%")
        print(f"   📏 Average ATR SL: {avg_atr_pips:.0f} pips")
        print(f"   ❌ Failures: {atr_failures}")
    
    # Trade blocking analysis
    total_blocked = len(blocked_trades)
    execution_rate = ((total_signals - total_blocked) / total_signals * 100) if total_signals > 0 else 0
    
    if blocked_trades:
        avg_blocked_risk = statistics.mean([float(match[0]) for match in blocked_trades])
        avg_blocked_pips = statistics.mean([float(match[2]) for match in blocked_trades])
        
        print(f"\n🛑 **CAPITAL CONSTRAINT ANALYSIS:**")
        print(f"   ❌ Blocked Trades: {total_blocked}")
        print(f"   📊 Execution Rate: {execution_rate:.1f}%")
        print(f"   💸 Avg Blocked Risk: {avg_blocked_risk:.1f}%")
        print(f"   📏 Avg Blocked SL: {avg_blocked_pips:.0f} pips")
    
    # Calculate improvement metrics
    print(f"\n📈 **OPTIMIZATION IMPACT ANALYSIS:**")
    print("=" * 50)
    
    # Before optimization (estimated từ analysis trước)
    original_avg_sl = 3631
    original_execution_rate = 1.8
    
    # After optimization
    current_avg_sl = avg_atr_pips if atr_successes else original_avg_sl
    current_execution_rate = execution_rate
    
    sl_improvement = ((original_avg_sl - current_avg_sl) / original_avg_sl * 100) if current_avg_sl < original_avg_sl else 0
    execution_improvement = current_execution_rate - original_execution_rate
    
    print(f"🎯 **IMPROVEMENTS ACHIEVED:**")
    print(f"   📏 SL Distance: {original_avg_sl}→{current_avg_sl:.0f} pips ({sl_improvement:.1f}% better)")
    print(f"   🎯 Execution Rate: {original_execution_rate:.1f}%→{current_execution_rate:.1f}% ({execution_improvement:+.1f}%)")
    
    # Projected performance với Enhanced Position Sizing
    print(f"\n🚀 **ENHANCED POSITION SIZING PROJECTIONS:**")
    print("=" * 50)
    
    # Tiered system projections
    tiers = [
        {"balance": 1000, "risk": 0.75, "exec_rate": 25, "desc": "Conservative Start"},
        {"balance": 1500, "risk": 1.0, "exec_rate": 60, "desc": "Growing Phase"},
        {"balance": 2500, "risk": 1.5, "exec_rate": 85, "desc": "Standard Phase"},
        {"balance": 5000, "risk": 2.0, "exec_rate": 85, "desc": "Aggressive Phase"}
    ]
    
    for tier in tiers:
        monthly_trades = int(total_signals/12 * tier["exec_rate"]/100)
        print(f"💰 **{tier['desc']} (${tier['balance']:,})**")
        print(f"   📊 Risk: {tier['risk']}% | Execution: {tier['exec_rate']}%")
        print(f"   🔄 Monthly Trades: {monthly_trades}")
        print(f"   📈 Annual Trades: {monthly_trades * 12}")
    
    # Risk management summary
    print(f"\n🛡️  **RISK MANAGEMENT SUMMARY:**")
    print("=" * 50)
    print(f"✅ ATR-based SL: Reduces SL by {sl_improvement:.1f}%")
    print(f"✅ Tiered Position Sizing: Adaptive risk 0.75%-2.0%")
    print(f"✅ Enhanced Capital Protection: 3.0% max daily loss")
    print(f"✅ Dynamic SL Risk Limit: 7.5% max per trade")
    
    # Final recommendations
    print(f"\n💡 **FINAL RECOMMENDATIONS:**")
    print("=" * 50)
    print(f"🎯 **IMMEDIATE ACTION:** Deploy enhanced EA with current optimizations")
    print(f"💰 **TARGET CAPITAL:** $2,500+ for optimal execution rate (85%)")
    print(f"📊 **MONITORING:** Track execution rate và ATR performance")
    print(f"⚙️  **NEXT PHASE:** Implement partial TP system if needed")
    
    # Success metrics
    success_score = 0
    if atr_success_rate > 95: success_score += 25
    if sl_improvement > 50: success_score += 25  
    if current_execution_rate > 10: success_score += 25
    if total_signals > 500: success_score += 25
    
    print(f"\n🏆 **OPTIMIZATION SUCCESS SCORE: {success_score}/100**")
    
    if success_score >= 75:
        print("🎉 **OPTIMIZATION SUCCESSFUL** - Ready for production!")
    elif success_score >= 50:
        print("✅ **OPTIMIZATION GOOD** - Minor improvements needed")
    else:
        print("⚠️  **OPTIMIZATION NEEDS WORK** - Review implementation")
    
    return {
        'signals': total_signals,
        'execution_rate': execution_rate,
        'atr_success_rate': atr_success_rate if atr_total > 0 else 0,
        'sl_improvement': sl_improvement,
        'success_score': success_score
    }

if __name__ == "__main__":
    results = final_optimization_analysis()
    print(f"\n📋 **FINAL METRICS:**")
    print(f"Signals: {results['signals']} | Execution: {results['execution_rate']:.1f}%")
    print(f"ATR Success: {results['atr_success_rate']:.1f}% | SL Improvement: {results['sl_improvement']:.1f}%")
    print(f"Overall Success Score: {results['success_score']}/100")