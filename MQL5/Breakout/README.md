# Breakout — Session Range Breakout

## Strategy Overview
Trades breakouts of the Asian session consolidation range during London/NY active hours.

## Logic
1. **Range Build** (Asian Session): Track highest high / lowest low from hour 0 to hour 8 (GMT)
2. **Range Lock**: At hour 8, lock the range → ready for breakout
3. **BUY**: Price closes above range high + buffer → BUY (market order)
4. **SELL**: Price closes below range low - buffer → SELL (market order)
5. **SL**: Opposite side of range + buffer
6. **TP**: Fixed RR (risk-reward) or range extension
7. **EOD Close**: All positions closed at end of day (hour 22)
8. **Max Trades/Day**: 1-2 trades per day to avoid whipsaw

## Expected Frequency
- **M15**: ~1 trade/day = **~20 trades/month** per pair
- **M5**: ~1-2 trades/day = **~25-30 trades/month** per pair

## Best Market Conditions
- **Pairs with clear Asian consolidation → London volatility:**
  - EURUSD, GBPUSD (best)
  - XAUUSD (gold breaks Asian range well)
- Worst during: holidays, low-volatility Fridays

## Key Feature: Range Filters
- **Min Range**: Skip if Asian range is too small (noise)
- **Max Range**: Skip if Asian range is too large (already moved)
- This prevents entries on meaningless days

## Initial Test Config
```
Timeframe: M15
Range Start Hour: 0
Range End Hour: 8
Trade Start Hour: 8
Trade End Hour: 18
GMT Offset: 0
Breakout Buffer: 3.0 points
Min Range: 30 points
Max Range: 500 points
SL Buffer: 10%
TP RR: 1.5
EOD Close Hour: 22
Max Trades/Day: 2
Deposit: $500
Lot: 0.02
```

## Advantages vs MST Medio
| Feature | MST Medio | Breakout |
|---------|-----------|--------------|
| Signal source | Swing structure + FVG | Session range |
| Trade freq | ~1.8/month | ~20/month |
| Entry | Limit (may unfill) | Market (100% fill) |
| Timeframe | H1 | M15 |
| Holding time | Hours-Days | Hours (intraday) |
| Complexity | Very high | Low |
| Daily cycle | None | Asian → London |
| EOD close | No | Yes |

## How to Adjust GMT Offset
The EA uses `InpGMTOffset` to adjust for broker server time:
- If broker is UTC+2 (common for MT5 brokers), set `InpGMTOffset = 2`
- Asian session 00:00-08:00 GMT becomes 02:00-10:00 server time
- Check your broker's server time in MT5 terminal → Market Watch

## Risk Management
- Uses `OrderCalcProfit()` for accurate risk % calculation (no JPY bug)
- Max risk per trade configurable
- Daily loss limit: stops trading if daily loss exceeds threshold
- Breakeven + Partial TP for runner management
