#!/usr/bin/env python3
"""
BTC-Adaptive SL Strategy Design
Goal: Reduce median SL distance from 3,217 pips to <1,000 pips while maintaining profitability

Strategy Ideas:
1. Volatility-based SL tightening
2. Multi-layer SL with partial exits
3. ATR-based dynamic SL positioning
4. Trend strength filtering for tighter SLs
"""

import math

def analyze_current_vs_adaptive():
    """Compare current strategy with adaptive approach"""
    
    # Current strategy stats (from analysis)
    current_median_sl = 3217  # pips
    current_iqr = 3701       # pips
    current_risk_at_median = 3.2  # % for 0.01 lot on $1000
    
    print("=" * 80)
    print("BTC-ADAPTIVE SL STRATEGY DESIGN")
    print("=" * 80)
    print()
    print("CURRENT STRATEGY ISSUES:")
    print(f"  • Median SL Distance: {current_median_sl:,} pips")
    print(f"  • Risk per 0.01 lot: {current_risk_at_median}% of $1000")
    print(f"  • Only 0% of trades execute due to risk constraints")
    print(f"  • Need MaxSLRisk ≥{current_risk_at_median*10:.0f}% to trade 0.01 lot")
    print()
    
    # Adaptive strategy targets
    target_sl_reduction = [25, 50, 75]  # % reduction
    
    print("ADAPTIVE STRATEGY TARGETS:")
    for reduction in target_sl_reduction:
        new_sl = current_median_sl * (1 - reduction/100)
        new_risk = current_risk_at_median * (1 - reduction/100)
        max_lot_10pct = 1000 * 0.10 / new_sl  # Max lot for 10% risk
        
        print(f"  {reduction}% SL reduction:")
        print(f"    → New median SL: {new_sl:,.0f} pips")
        print(f"    → Risk/0.01 lot: {new_risk:.1f}%")
        print(f"    → Max lot @10% risk: {max_lot_10pct:.3f}")
        print(f"    → Feasible with current constraints: {'✅ Yes' if new_risk <= 2.0 else '❌ No'}")
        print()

def design_adaptive_approaches():
    """Design specific adaptive SL approaches"""
    
    print("ADAPTIVE SL APPROACHES:")
    print()
    
    # Approach 1: ATR-based dynamic SL
    print("1. ATR-BASED DYNAMIC SL:")
    print("   Logic: SL = Entry ± (ATR_multiplier × Current_ATR)")
    print("   Benefits:")
    print("     • Adapts to current volatility")
    print("     • Tighter SLs in low volatility")
    print("     • Wider SLs only when market demands")
    print()
    
    # Example calculations
    # Assuming BTC M5 ATR ≈ 500-1500 pips in various conditions
    atr_multipliers = [1.0, 1.5, 2.0]
    typical_atr_ranges = [(500, 800), (800, 1200), (1200, 1800)]
    
    print("   ATR-SL Distance Examples:")
    for mult in atr_multipliers:
        print(f"     ATR Multiplier {mult}:")
        for atr_min, atr_max in typical_atr_ranges:
            sl_min = atr_min * mult
            sl_max = atr_max * mult
            print(f"       ATR {atr_min}-{atr_max} pips → SL {sl_min:.0f}-{sl_max:.0f} pips")
    print()
    
    # Approach 2: Trend strength filtering
    print("2. TREND STRENGTH FILTERING:")
    print("   Logic: Only trade when breakout has strong momentum")
    print("   Implementation:")
    print("     • Require impulse body ≥ 2.0 × average (vs current 0.75)")
    print("     • Add volume confirmation (if available)")  
    print("     • Filter weak breakouts that lead to large SLs")
    print()
    
    # Approach 3: Multi-layer SL
    print("3. MULTI-LAYER SL SYSTEM:")
    print("   Logic: Split position into layers with different SL distances")
    print("   Example Setup:")
    layer_configs = [
        {"layer": 1, "lot_pct": 40, "sl_mult": 0.5, "description": "Tight SL for quick exit"},
        {"layer": 2, "lot_pct": 40, "sl_mult": 1.0, "description": "Normal SL for main position"},
        {"layer": 3, "lot_pct": 20, "sl_mult": 2.0, "description": "Wide SL for trend capture"}
    ]
    
    for config in layer_configs:
        print(f"     Layer {config['layer']}: {config['lot_pct']}% of position")
        print(f"       SL: {config['sl_mult']}× base distance")
        print(f"       Purpose: {config['description']}")
    print()
    
    print("   Multi-layer Risk Calculation:")
    base_sl = 1000  # pips
    for config in layer_configs:
        layer_sl = base_sl * config['sl_mult']
        layer_risk = (config['lot_pct'] / 100) * 0.01 * layer_sl / 1000  # % of balance
        print(f"     Layer {config['layer']}: {layer_sl:,.0f} pips SL → {layer_risk:.2f}% risk")
    
    total_risk = sum((c['lot_pct']/100) * 0.01 * base_sl * c['sl_mult'] / 1000 for c in layer_configs)
    print(f"     Total Risk: {total_risk:.2f}% (vs {base_sl*0.01/1000:.1f}% single layer)")
    print()

def implementation_priority():
    """Suggest implementation priority order"""
    
    print("IMPLEMENTATION PRIORITY:")
    print()
    
    approaches = [
        {
            "id": 1,
            "name": "ATR-Based Dynamic SL",
            "difficulty": "Medium",
            "impact": "High", 
            "implementation": "Add ATR calculation, replace fixed SL logic",
            "timeline": "2-3 hours"
        },
        {
            "id": 2, 
            "name": "Stronger Impulse Filter",
            "difficulty": "Easy",
            "impact": "Medium",
            "implementation": "Increase InpImpulseMult from 0.75 to 2.0+",
            "timeline": "5 minutes"
        },
        {
            "id": 3,
            "name": "Multi-layer SL System", 
            "difficulty": "Hard",
            "impact": "High",
            "implementation": "Rewrite position management completely",
            "timeline": "1-2 days"
        }
    ]
    
    for approach in approaches:
        print(f"{approach['id']}. {approach['name']}")
        print(f"   Difficulty: {approach['difficulty']}")
        print(f"   Impact: {approach['impact']}") 
        print(f"   Implementation: {approach['implementation']}")
        print(f"   Timeline: {approach['timeline']}")
        print()
    
    print("RECOMMENDED START:")
    print("  → Begin with #2 (Stronger Impulse Filter) - quick win")
    print("  → Then implement #1 (ATR-Based SL) - highest ROI")
    print("  → Consider #3 (Multi-layer) if others don't achieve target")

if __name__ == "__main__":
    analyze_current_vs_adaptive()
    design_adaptive_approaches()
    implementation_priority()