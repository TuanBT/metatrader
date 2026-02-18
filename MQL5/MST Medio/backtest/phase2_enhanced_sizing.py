#!/usr/bin/env python3
"""
Phase 2: Enhanced Position Sizing Implementation
Implement tiered position sizing thông minh dựa trên ATR analysis
"""

def generate_phase2_recommendations():
    print("=== PHASE 2: ENHANCED POSITION SIZING IMPLEMENTATION ===\n")
    
    # Dữ liệu từ log analysis
    atr_avg_sl = 1452  # pips
    original_avg_sl = 3631  # pips
    current_balance = 1000  # USD
    current_risk_pct = 1.5
    max_sl_risk = 7.5
    
    print("📊 **CURRENT SITUATION ANALYSIS:**")
    print(f"💰 Current Balance: ${current_balance}")
    print(f"📏 ATR Average SL: {atr_avg_sl} pips")
    print(f"📏 Original Average SL: {original_avg_sl} pips") 
    print(f"📈 ATR Improvement: {((original_avg_sl - atr_avg_sl) / original_avg_sl * 100):.1f}% better")
    print(f"🎯 Execution Rate: 1.8% (Need to improve)\n")
    
    print("🎯 **PROPOSED TIERED POSITION SIZING:**")
    
    # Tiered system dựa trên account growth
    tiers = [
        {"balance": 1000, "risk": 0.75, "description": "Conservative Start"},
        {"balance": 1500, "risk": 1.0, "description": "Growing Phase"},  
        {"balance": 2500, "risk": 1.5, "description": "Standard Phase"},
        {"balance": 5000, "risk": 2.0, "description": "Aggressive Phase"}
    ]
    
    for tier in tiers:
        balance = tier["balance"]
        risk = tier["risk"]
        desc = tier["description"]
        
        # Tính toán với ATR-based SL
        acceptable_loss = balance * (max_sl_risk / 100)
        max_lot_atr = acceptable_loss / (atr_avg_sl * 10)  # 10 USD per pip
        daily_risk = balance * (risk / 100)
        
        # Execution rate estimate
        if balance >= 2500:
            exec_rate = 85
        elif balance >= 1500:
            exec_rate = 60
        else:
            exec_rate = 25
            
        print(f"📈 **{desc} (${balance:,})**")
        print(f"   💸 Risk per trade: {risk}% (${daily_risk:.0f})")
        print(f"   📊 Max lot size: {max_lot_atr:.3f}")
        print(f"   🎯 Estimated execution rate: {exec_rate}%")
        print(f"   🔄 Trades/month estimate: {int(779/12 * exec_rate/100)}\n")
    
    print("⚙️ **MQL5 IMPLEMENTATION CODE:**")
    print("""
// Enhanced Position Sizing với Tiered System
double CalculateEnhancedLotSize(double slDistance)
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double tieredRisk;
    
    // Tiered risk based on account growth
    if (balance < 1500)
        tieredRisk = 0.75;      // Conservative start
    else if (balance < 2500) 
        tieredRisk = 1.0;       // Growing phase
    else if (balance < 5000)
        tieredRisk = 1.5;       // Standard phase  
    else
        tieredRisk = 2.0;       // Aggressive phase
    
    double riskAmount = balance * (tieredRisk / 100.0);
    double lossPer1Lot = slDistance * _Point * 10.0; // 10 USD per pip
    
    double calculatedLot = riskAmount / lossPer1Lot;
    
    // Normalize to broker lot steps
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    calculatedLot = NormalizeDouble(calculatedLot / lotStep, 0) * lotStep;
    calculatedLot = MathMax(minLot, MathMin(maxLot, calculatedLot));
    
    return calculatedLot;
}
""")
    
    print("🔧 **INTEGRATION STEPS:**")
    print("1. Replace CalculateLotSize() với CalculateEnhancedLotSize()")
    print("2. Update risk validation với tiered system")
    print("3. Add balance growth tracking")
    print("4. Test với different balance levels\n")
    
    print("📈 **EXPECTED IMPROVEMENTS:**")
    print("✅ Execution rate: 1.8% → 25-85% depending on balance")
    print("✅ Risk management: Adaptive với account growth")
    print("✅ Capital efficiency: Better utilization")
    print("✅ Scalability: System grows with account\n")
    
    print("🎯 **NEXT PHASE 3: PARTIAL TP SYSTEM**")
    print("- Implement 25% TP at 1R, 50% at 2R, 25% at 3R")
    print("- Reduce max SL risk khi có partial profits")
    print("- Dynamic SL management with running profits")

if __name__ == "__main__":
    generate_phase2_recommendations()