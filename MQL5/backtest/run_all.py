"""
run_all.py — Auto-backtest all strategies across multiple pairs.

Usage:
    python run_all.py                    # Run all strategies, all pairs
    python run_all.py scalper            # Run only scalper
    python run_all.py reversal EURUSDm   # Run reversal on EURUSD only
    python run_all.py --start 2024-01-01 --end 2025-01-01   # Custom date range
"""

import sys
import os
import time
from datetime import datetime

# Add backtest directory to path
sys.path.insert(0, os.path.dirname(__file__))

from strategy_scalper import run_scalper
from strategy_reversal import run_reversal
from strategy_breakout import run_breakout


DEFAULT_SYMBOLS = ["EURUSDm", "XAUUSDm", "USDJPYm"]
DEFAULT_START = "2023-01-01"
DEFAULT_END = "2026-01-01"


def run_all_strategies(symbols=None, start=None, end=None, strategies=None):
    """Run selected strategies on selected symbols."""
    symbols = symbols or DEFAULT_SYMBOLS
    start = start or DEFAULT_START
    end = end or DEFAULT_END
    strategies = strategies or ["scalper", "reversal", "breakout"]
    
    results = {}
    
    print(f"\n{'╔'+'═'*68+'╗'}")
    print(f"║{'Auto-Backtest':^68}║")
    print(f"║{'':^68}║")
    print(f"║  Period: {start} → {end}{'':>{68-22-len(start)-len(end)}}║")
    print(f"║  Symbols: {', '.join(symbols)}{'':>{68-12-len(', '.join(symbols))}}║")
    print(f"║  Strategies: {', '.join(strategies)}{'':>{68-15-len(', '.join(strategies))}}║")
    print(f"{'╚'+'═'*68+'╝'}")
    
    total_start = time.time()
    
    for strategy in strategies:
        for sym in symbols:
            key = f"{strategy}_{sym}"
            print(f"\n{'█'*70}")
            print(f"█  {strategy.upper()} — {sym}")
            print(f"{'█'*70}")
            
            t0 = time.time()
            
            try:
                if strategy == "scalper":
                    engine = run_scalper(
                        symbol=sym,
                        timeframe="M15",
                        start_date=start,
                        end_date=end,
                    )
                elif strategy == "reversal":
                    engine = run_reversal(
                        symbol=sym,
                        timeframe="H1",
                        start_date=start,
                        end_date=end,
                    )
                elif strategy == "breakout":
                    engine = run_breakout(
                        symbol=sym,
                        timeframe="M15",
                        start_date=start,
                        end_date=end,
                    )
                else:
                    print(f"  ⚠️  Unknown strategy: {strategy}")
                    continue
                
                if engine:
                    engine.print_summary(f"{strategy.upper()} — {sym}")
                    engine.print_trades(last_n=5)
                    results[key] = engine.summary()
                    results[key]["time_sec"] = time.time() - t0
                    
            except FileNotFoundError as e:
                print(f"  ⚠️  {e}")
            except Exception as e:
                print(f"  ❌  Error: {e}")
                import traceback
                traceback.print_exc()
    
    # ── Comparison Table ──
    if results:
        print_comparison(results)
    
    elapsed = time.time() - total_start
    print(f"\n✅ Total time: {elapsed:.1f}s")
    
    return results


def print_comparison(results):
    """Print comparison table of all results."""
    print(f"\n\n{'╔'+'═'*100+'╗'}")
    print(f"║{'COMPARISON TABLE':^100}║")
    print(f"{'╠'+'═'*100+'╣'}")
    
    header = f"║ {'Strategy':>20} │ {'Trades':>6} │ {'WR%':>6} │ {'Return%':>8} │ {'MaxDD%':>7} │ {'PF':>6} │ {'R̄':>6} │ {'Tr/Mo':>5} │ {'Time':>5} ║"
    print(header)
    print(f"{'╠'+'═'*100+'╣'}")
    
    for key, s in sorted(results.items()):
        row = (
            f"║ {key:>20} │ "
            f"{s['total_trades']:>6} │ "
            f"{s['win_rate']:>5.1f}% │ "
            f"{s['return_pct']:>+7.1f}% │ "
            f"{s['max_drawdown']:>6.1f}% │ "
            f"{s['profit_factor']:>6.2f} │ "
            f"{s['avg_pnl_r']:>+5.2f} │ "
            f"{s['trades_per_month']:>5.1f} │ "
            f"{s.get('time_sec', 0):>4.1f}s ║"
        )
        print(row)
    
    print(f"{'╚'+'═'*100+'╝'}")
    
    # Best strategy highlight
    if results:
        best_return = max(results.items(), key=lambda x: x[1]["return_pct"])
        best_wr = max(results.items(), key=lambda x: x[1]["win_rate"])
        best_freq = max(results.items(), key=lambda x: x[1]["trades_per_month"])
        
        print(f"\n  🏆 Best Return:    {best_return[0]} ({best_return[1]['return_pct']:+.1f}%)")
        print(f"  🏆 Best Win Rate:  {best_wr[0]} ({best_wr[1]['win_rate']:.1f}%)")
        print(f"  🏆 Most Active:    {best_freq[0]} ({best_freq[1]['trades_per_month']:.1f} trades/month)")


def parse_args():
    """Simple arg parser."""
    strategies = None
    symbols = None
    start = DEFAULT_START
    end = DEFAULT_END
    
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--start" and i + 1 < len(args):
            start = args[i + 1]
            i += 2
        elif args[i] == "--end" and i + 1 < len(args):
            end = args[i + 1]
            i += 2
        elif args[i] in ("scalper", "reversal", "breakout"):
            if strategies is None:
                strategies = []
            strategies.append(args[i])
            i += 1
        elif args[i].endswith("m") or args[i].endswith("M"):
            if symbols is None:
                symbols = []
            symbols.append(args[i])
            i += 1
        else:
            i += 1
    
    return strategies, symbols, start, end


if __name__ == "__main__":
    strategies, symbols, start, end = parse_args()
    run_all_strategies(strategies=strategies, symbols=symbols, start=start, end=end)
