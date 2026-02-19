# Scalper — EMA Crossover + RSI Filter

## Strategy Overview
High-frequency trend-following scalper using EMA crossover with RSI confirmation.

## Logic
1. **Entry Signal**: EMA Fast (9) crosses EMA Slow (21)
2. **RSI Filter**: Skip BUY if RSI > 70 (overbought), skip SELL if RSI < 30 (oversold)
3. **Trend Filter**: Price must be above EMA 50 for BUY, below for SELL
4. **Entry**: Market order on bar close after cross confirmed
5. **SL**: ATR × 1.5 from entry
6. **TP**: Fixed RR (1.5× SL distance)
7. **Management**: Partial TP at 1R (50%), Breakeven at 0.5R

## Expected Frequency
- **M15**: 10-20+ signals/month per pair
- **H1**: 5-10 signals/month per pair

## Recommended Pairs
- XAUUSD, BTCUSD (volatile, trending)
- EURUSD, GBPUSD (moderate)
- Indices (NAS100, US30)

## Initial Test Config
```
Timeframe: M15
EMA Fast: 9
EMA Slow: 21
Trend EMA: 50
RSI Period: 14
RSI OB/OS: 70/30
ATR Period: 14
ATR SL Mult: 1.5
TP RR: 1.5
BE at R: 0.5
Partial TP at R: 1.0
Deposit: $500
Lot: 0.02
```

## Advantages vs MST Medio
| Feature | MST Medio | Scalper |
|---------|-----------|-------------|
| Signal type | Structure breakout | EMA crossover |
| Confirmation | 2-step (slow) | Immediate (fast) |
| Entry | Limit order (may unfill) | Market order (100% fill) |
| Frequency | ~1.8/month | ~15/month |
| Complexity | Very high (1900+ lines) | Low (~400 lines) |
