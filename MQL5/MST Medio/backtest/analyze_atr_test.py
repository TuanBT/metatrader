#!/usr/bin/env python3
"""
Analyze 20260218.log to determine ATR implementation status
"""

import re
from pathlib import Path

def analyze_atr_test():
    log_file = Path("../logs/20260218.log")
    
    if not log_file.exists():
        print("❌ Log file not found")
        return
    
    # Read the log file
    try:
        with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        print(f"❌ Error reading log: {e}")
        return
    
    lines = content.strip().split('\n')
    print(f"📊 **ATR Implementation Test Analysis**")
    print(f"📁 Log File: {log_file.name} ({len(lines):,} lines)")
    print()
    
    # Check for EA initialization
    strategy_lines = [line for line in lines if "Strategy:" in line or "Risk Management:" in line]
    if strategy_lines:
        print("✅ **EA INITIALIZATION FOUND:**")
        for line in strategy_lines[-2:]:  # Last 2 initialization messages
            print(f"   {line.split(') ')[-1] if ') ' in line else line}")
    else:
        print("❌ No EA initialization messages found")
    print()
    
    # Check for ATR-related messages
    atr_patterns = [
        r"ATR",
        r"🔧",
        r"📏", 
        r"ATR-based SL",
        r"Using ATR",
        r"ATR.*failed"
    ]
    
    atr_messages = []
    for pattern in atr_patterns:
        matches = [line for line in lines if re.search(pattern, line, re.IGNORECASE)]
        atr_messages.extend(matches)
    
    if atr_messages:
        print("✅ **ATR IMPLEMENTATION DETECTED:**")
        for msg in atr_messages[:5]:  # First 5 messages
            print(f"   {msg.split(') ')[-1] if ') ' in msg else msg}")
        if len(atr_messages) > 5:
            print(f"   ... và {len(atr_messages)-5} messages khác")
    else:
        print("❌ **NO ATR MESSAGES FOUND - ATR not executing**")
    print()
    
    # Check for trade signals and outcomes
    pending_signals = [line for line in lines if "Pending BUY:" in line or "Pending SELL:" in line]
    alerts = [line for line in lines if "Alert: MST Medio:" in line]
    trades = [line for line in lines if "order performed" in line and "BTCUSDm" in line]
    
    print(f"📊 **SIGNAL ACTIVITY:**")
    print(f"   Pending Signals: {len(pending_signals)}")
    print(f"   Trade Alerts: {len(alerts)}")  
    print(f"   Executed Trades: {len(trades)}")
    print()
    
    # Check for risk validation messages
    risk_patterns = [
        "MAX.*RISK",
        "Risk.*OK",
        "SL.*Risk.*OK", 
        "POSITION SIZING",
        "CheckMaxSLRisk",
        "CalculateLotSize"
    ]
    
    risk_messages = []
    for pattern in risk_patterns:
        matches = [line for line in lines if re.search(pattern, line, re.IGNORECASE)]
        risk_messages.extend(matches)
    
    if risk_messages:
        print("✅ **RISK VALIDATION FOUND:**")
        for msg in risk_messages[:3]:
            print(f"   {msg.split(') ')[-1] if ') ' in msg else msg}")
    else:
        print("❌ **NO RISK VALIDATION** - signals died before reaching trade logic")
    print()
    
    # Test period analysis
    first_line = lines[0] if lines else ""
    last_line = lines[-1] if lines else ""
    
    # Extract dates
    first_date = None
    last_date = None
    
    for line in lines[:10]:
        if "Expert MST Medio" in line and "202" in line:
            match = re.search(r'(\d{4}\.\d{2}\.\d{2})', line)
            if match and not first_date:
                first_date = match.group(1)
    
    for line in reversed(lines[-20:]):
        if "Expert MST Medio" in line and "202" in line:
            match = re.search(r'(\d{4}\.\d{2}\.\d{2})', line)
            if match:
                last_date = match.group(1)
                break
    
    print(f"📅 **TEST PERIOD:**")
    print(f"   Start: {first_date or 'Unknown'}")
    print(f"   End: {last_date or 'Unknown'}")
    
    # Final balance
    balance_lines = [line for line in lines if "final balance" in line]
    if balance_lines:
        balance = balance_lines[-1]
        print(f"   Final: {balance.split('final balance')[-1].strip()}")
    print()
    
    # CONCLUSION
    print("🔍 **ASSESSMENT:**")
    if atr_messages:
        print("✅ ATR implementation IS WORKING")
    elif not alerts and not trades:
        print("⚠️  NO TRADES ATTEMPTED - ATR status UNKNOWN")
        print("   Possible reasons:")
        print("   • Market conditions didn't trigger confirmations")  
        print("   • All signals cancelled before reaching trade logic")
        print("   • Need different test period with more volatility")
    else:
        print("❌ ATR implementation NOT WORKING - using old EA version")
    
    print()
    print("**RECOMMENDATION:**")
    if not atr_messages and (alerts or trades):
        print("🔄 RECOMPILE EA with ATR code and retest")
    elif not alerts and not trades:
        print("📊 TEST với different time period có nhiều trade signals")
    else:
        print("✅ ATR working - analyze SL distances for effectiveness")

if __name__ == "__main__":
    analyze_atr_test()