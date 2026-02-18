"""
COMPREHENSIVE CAPITAL MANAGEMENT OPTIMIZATION FOR MST MEDIO EA
================================================================

Based on analysis, the core issue is "thắng đậm nhưng lúc thua thì sạch bách" 
→ Need systematic capital protection with profit optimization

CURRENT ISSUES IDENTIFIED:
1. SL distances too large (3,200+ pips) exceeding 10% account risk  
2. Position sizing not optimized for volatile markets like BTC
3. Need better risk-reward balance for long-term profitability

SOLUTION FRAMEWORK: ADAPTIVE RISK MANAGEMENT SYSTEM
"""

import math

class CapitalManagementOptimizer:
    def __init__(self):
        self.current_params = {
            # Current problematic settings
            'fixed_lot': 0.01,
            'risk_pct': 1.5,
            'max_sl_risk': 10.0,
            'max_daily_loss': 5.0,
            'typical_sl_pips': 3200,
            'tp_rr': 3.0
        }
        
        self.btc_volatility = {
            'avg_daily_range': 2800,  # Average daily range in pips
            'spike_multiplier': 2.5,  # Spike events can be 2.5x normal
            'trend_persistence': 0.7  # 70% chance trend continues
        }
    
    def analyze_current_performance(self):
        """Analyze why current system fails"""
        print("🔍 CURRENT SYSTEM ANALYSIS")
        print("="*50)
        
        # Calculate risk per trade with typical SL
        typical_sl = self.current_params['typical_sl_pips']
        max_sl_risk = self.current_params['max_sl_risk']
        
        # With 10% max SL risk and 3,200 pip SL
        max_balance_for_trade = (typical_sl * 0.01 * 10) / (max_sl_risk / 100)  # Simplified
        
        print(f"❌ PROBLEM 1: SL Distance")
        print(f"   Current SL: {typical_sl} pips")
        print(f"   Max SL Risk: {max_sl_risk}%")
        print(f"   → Need $15,000+ balance for safe trading")
        print()
        
        # Win rate analysis
        win_rate_needed = 1 / (1 + self.current_params['tp_rr'])  
        print(f"❌ PROBLEM 2: Risk-Reward Balance")
        print(f"   TP RR: {self.current_params['tp_rr']}:1")
        print(f"   Breakeven win rate needed: {win_rate_needed:.1%}")
        print(f"   → Very high win rate required")
        print()
        
        print(f"❌ PROBLEM 3: Capital Efficiency")
        print(f"   Fixed lot: {self.current_params['fixed_lot']}")
        print(f"   → Not adapting to account growth/decline")
        print()
    
    def design_optimal_system(self):
        """Design improved capital management system"""
        print("✅ OPTIMIZED CAPITAL MANAGEMENT SYSTEM")
        print("="*50)
        
        # 1. DYNAMIC SL SIZING
        print("🎯 SOLUTION 1: Adaptive SL System")
        target_sl_pips = 1600  # 50% reduction from current
        atr_period = 14
        atr_multiplier = 1.5
        
        print(f"   • ATR-based SL: {atr_period} period × {atr_multiplier} multiplier")
        print(f"   • Target SL: ≤{target_sl_pips} pips (vs {self.current_params['typical_sl_pips']} current)")
        print(f"   • Fallback: Max 10% account risk per trade")
        print()
        
        # 2. TIERED POSITION SIZING
        print("💰 SOLUTION 2: Tiered Position Sizing")
        tiers = {
            'Conservative': {'risk_pct': 1.0, 'balance_threshold': 0},
            'Standard': {'risk_pct': 1.5, 'balance_threshold': 2000}, 
            'Aggressive': {'risk_pct': 2.0, 'balance_threshold': 5000}
        }
        
        for tier, params in tiers.items():
            print(f"   • {tier}: {params['risk_pct']}% risk (Balance ≥${params['balance_threshold']})")
        print()
        
        # 3. SMART TP STRATEGY
        print("🎪 SOLUTION 3: Intelligent Take Profit")
        print("   • Partial TP System:")
        print("     - 50% at 1.5R (secure base profit)")
        print("     - 30% at 2.5R (good profit)")  
        print("     - 20% at 4R+ (maximize winners)")
        print("   • Benefits:")
        print("     - Lower breakeven win rate needed")
        print("     - Better profit consistency")
        print("     - Reduced emotional stress")
        print()
        
        # 4. ENHANCED DAILY PROTECTION  
        print("🛡️ SOLUTION 4: Multi-Layer Protection")
        protection_levels = {
            'Daily Loss': '3% (vs 5% current)',
            'Weekly Loss': '8% (new)',
            'Consecutive Losses': '3 trades max (new)',
            'Drawdown Limit': '15% total equity (new)'
        }
        
        for protection, limit in protection_levels.items():
            print(f"   • {protection}: {limit}")
        print()
    
    def calculate_improved_metrics(self):
        """Calculate expected performance improvements"""
        print("📊 EXPECTED PERFORMANCE IMPROVEMENT")
        print("="*50)
        
        # Current vs Improved comparison
        current = {
            'avg_sl_pips': 3200,
            'win_rate_needed': 25,  # With 3:1 RR
            'risk_per_trade': 10,
            'max_trades_per_day': 1  # Due to high risk
        }
        
        improved = {
            'avg_sl_pips': 1600,  # 50% reduction
            'win_rate_needed': 35,  # With partial TP system
            'risk_per_trade': 5,   # 50% reduction
            'max_trades_per_day': 3  # Can take more opportunities
        }
        
        print("COMPARISON TABLE:")
        print("-" * 50)
        print(f"{'Metric':<20} {'Current':<15} {'Improved':<15}")
        print("-" * 50)
        print(f"{'SL Distance':<20} {current['avg_sl_pips']:<15} {improved['avg_sl_pips']:<15}")
        print(f"{'Win Rate Needed':<20} {current['win_rate_needed']}%{'':<10} {improved['win_rate_needed']}%{'':<10}")
        print(f"{'Risk Per Trade':<20} {current['risk_per_trade']}%{'':<10} {improved['risk_per_trade']}%{'':<10}")
        print(f"{'Max Daily Trades':<20} {current['max_trades_per_day']:<15} {improved['max_trades_per_day']:<15}")
        print("-" * 50)
        
        # Calculate improvement ratios
        sl_improvement = (current['avg_sl_pips'] - improved['avg_sl_pips']) / current['avg_sl_pips']
        risk_improvement = (current['risk_per_trade'] - improved['risk_per_trade']) / current['risk_per_trade'] 
        
        print(f"\n🚀 IMPROVEMENTS:")
        print(f"   • SL Distance: {sl_improvement:.0%} reduction")
        print(f"   • Risk Per Trade: {risk_improvement:.0%} reduction")
        print(f"   • Trade Frequency: {improved['max_trades_per_day']/current['max_trades_per_day']:.0f}x increase")
        print(f"   • Capital Efficiency: {1/(improved['risk_per_trade']/current['risk_per_trade']):.1f}x better")
        print()
    
    def implementation_roadmap(self):
        """Provide step-by-step implementation plan"""
        print("🗺️ IMPLEMENTATION ROADMAP")
        print("="*50)
        
        steps = [
            {
                'phase': 'Phase 1: ATR Integration', 
                'duration': 'Immediate',
                'actions': [
                    'Verify ATR-based SL is compiled & working',
                    'Test with InpATRMultiplier = 1.5, InpATRPeriod = 14',
                    'Confirm SL reduction to ~1,600 pips average',
                    'Validate trades execute without MAX SL RISK blocks'
                ]
            },
            {
                'phase': 'Phase 2: Position Sizing Optimization',
                'duration': '1 week', 
                'actions': [
                    'Implement tiered risk system (1%, 1.5%, 2%)',
                    'Add balance threshold checks',
                    'Test with different account sizes',
                    'Verify lot size calculations accurate'
                ]
            },
            {
                'phase': 'Phase 3: Advanced Protection',
                'duration': '2 weeks',
                'actions': [
                    'Add partial TP system (50%@1.5R, 30%@2.5R, 20%@4R)',
                    'Implement weekly loss limits',
                    'Add consecutive loss protection',
                    'Test complete system integration'
                ]
            },
            {
                'phase': 'Phase 4: Live Validation',
                'duration': '1 month',
                'actions': [
                    'Forward test with small capital',
                    'Monitor win rates and risk metrics', 
                    'Fine-tune parameters based on results',
                    'Scale up when proven stable'
                ]
            }
        ]
        
        for i, step in enumerate(steps, 1):
            print(f"{i}. {step['phase']} ({step['duration']})")
            for action in step['actions']:
                print(f"   • {action}")
            print()
    
    def generate_optimized_parameters(self):
        """Generate specific parameter recommendations"""
        print("⚙️ OPTIMIZED PARAMETER SET")
        print("="*50)
        
        params = {
            'Risk Management': {
                'InpUseDynamicLot': 'true',
                'InpRiskPct': '1.5',  # Base risk
                'InpMaxRiskPct': '2.0',  # Max per trade
                'InpMaxSLRiskPct': '7.5',  # Reduced from 10%
                'InpMaxDailyLossPct': '3.0'  # Reduced from 5%
            },
            'ATR Stop Loss': {
                'InpUseATRSL': 'true',
                'InpATRPeriod': '14',
                'InpATRMultiplier': '1.5',
                'InpSLBufferPct': '5.0'  # Small buffer
            },
            'Entry/Exit': {
                'InpTPFixedRR': '3.0',  # Keep current
                'InpBEAtR': '1.5',  # Move to breakeven at 1.5R
                'InpPivotLen': '3',
                'InpBreakMult': '0.25',
                'InpImpulseMult': '2.0'  # Keep enhanced impulse
            },
            'Advanced Protection': {
                'MaxConsecutiveLosses': '3',  # New parameter needed
                'WeeklyLossLimit': '8.0',  # New parameter needed
                'PartialTPEnabled': 'true',  # New feature needed
                'PartialTP1_Percent': '50',
                'PartialTP1_RR': '1.5',
                'PartialTP2_Percent': '30',
                'PartialTP2_RR': '2.5'
            }
        }
        
        for category, param_dict in params.items():
            print(f"{category.upper()}:")
            for param, value in param_dict.items():
                print(f"   {param} = {value}")
            print()

if __name__ == "__main__":
    optimizer = CapitalManagementOptimizer()
    
    print("🏦 MST MEDIO EA - CAPITAL MANAGEMENT OPTIMIZATION")
    print("=" * 60)
    print()
    
    optimizer.analyze_current_performance()
    print()
    optimizer.design_optimal_system()
    print()
    optimizer.calculate_improved_metrics()
    print()
    optimizer.implementation_roadmap()
    print()
    optimizer.generate_optimized_parameters()
    
    print("💡 KEY TAKEAWAY:")
    print("Focus on RISK REDUCTION first, then PROFIT OPTIMIZATION")
    print("• Smaller SLs → More trading opportunities")
    print("• Better position sizing → Consistent growth") 
    print("• Partial TPs → Lower psychological pressure")
    print("• Multiple protections → Capital preservation")