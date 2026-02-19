# Reversal — Bollinger Band + RSI Mean Reversion

## Strategy Overview
Mean-reversion strategy that enters when price reaches extreme levels (beyond Bollinger Bands + RSI confirmation).

## Logic
1. **Zone Detection**: Price closes beyond outer BB + RSI in extreme zone
2. **Reversal Candle**: (Optional) Wait for reversal candle after extreme
3. **BUY**: Price < Lower BB + RSI < 30 + bullish candle → BUY
4. **SELL**: Price > Upper BB + RSI > 70 + bearish candle → SELL
5. **SL**: Beyond the outer BB + ATR buffer
6. **TP**: Middle Bollinger Band (mean reversion target) or Fixed RR
7. **Dynamic TP**: TP updates each bar to track middle BB movement
8. **Management**: Partial TP + Breakeven

## Expected Frequency
- **H1**: 5-10 signals/month per pair
- **M30**: 8-15 signals/month per pair

## Best Market Conditions
- **Ranging markets** (NOT strong trending)
- Works best on EURUSD, USDJPY, GBPUSD in range periods
- Avoid during major news events / trend breakouts

## Recommended Pairs
- EURUSD (ranges often)
- USDJPY (ranges in consolidation)
- GBPUSD, AUDUSD

## Initial Test Config
```
Timeframe: H1
BB Period: 20
BB Deviation: 2.0
RSI Period: 14
RSI OB: 70
RSI OS: 30
Require Reversal: true
SL Buffer: ATR × 0.5
TP: Middle BB
Min SL: 50 points
BE at R: 0.5
Partial TP at R: 0.5
Deposit: $500
Lot: 0.02
```

## Advantages vs MST Medio
| Feature | MST Medio | Reversal |
|---------|-----------|--------------|
| Market type | Trending | Ranging |
| Signal type | Breakout | Mean reversion |
| Entry | Limit (may unfill) | Market (100% fill) |
| Win rate target | 15-30% | 50-60% |
| TP style | Fixed RR | Dynamic (middle BB) |
| Complexity | Very high | Medium |
