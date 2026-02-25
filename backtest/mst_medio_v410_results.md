# MST Medio v4.10 — Backtest Results

**Date:** 2026-02-24 10:22  
**Risk:** $5/trade  |  **TP:** 3R  |  **MTF Consensus:** ≥3/5 TFs  
**Deposit:** $500  |  **Leverage:** 1:100  

## Settings

| Parameter | Value |
|-----------|-------|
| InpUseDynamicLot | false |
| InpLotSize | 0.01 |
| InpUseMoneyRisk | true |
| InpRiskMoney | 5.0 |
| InpMaxRiskPct | 5.0 |
| InpMaxDailyLossPct | 5.0 |
| InpMaxSLRiskPct | 30.0 |
| InpPivotLen | 5 |
| InpBreakMult | 0.25 |
| InpImpulseMult | 1.5 |
| InpTPFixedRR | 3.0 |
| InpBEAtR | 1.0 |
| InpSLBufferPct | 10 |
| InpEntryOffsetPts | 0 |
| InpMinSLDistPts | 0 |
| InpUseATRSL | true |
| InpATRMultiplier | 2.0 |
| InpATRPeriod | 14 |
| InpUsePartialTP | true |
| InpPartialTPAtR | 1.5 |
| InpPartialLotPct | 50 |
| InpTrailAfterPartialPts | 0 |
| InpUseTrendFilter | true |
| InpEMAFastPeriod | 20 |
| InpEMASlowPeriod | 50 |
| InpUseHTFFilter | true |
| InpUseMTFConsensus | true |
| InpMTFMinAgree | 3 |
| InpMTFTrailOnConsensus | true |
| InpMTFTrailStartR | 1.0 |
| InpMTFTrailStepR | 0.5 |
| InpSmartFlip | true |
| InpRequireConfirmCandle | false |
| InpMagic | 20241201 |
| InpMaxPositions | 1 |

## Results

| # | Test | Balance | P&L | % | Deals | SL | TP | BE | Win% |
|---|------|---------|-----|---|-------|----|----|----|------|
| 1 | EURUSD H1 2024 | $498.71 | $-1.29 | 🔴 -0.26% | 61 | 21 | 3 | 0 | 5% |
| 2 | EURUSD H1 2025 | $501.37 | $+1.37 | 🟢 +0.27% | 69 | 23 | 0 | 0 | 0% |
| 3 | EURUSD M15 2024 | $508.70 | $+8.70 | 🟢 +1.74% | 150 | 57 | 8 | 3 | 5% |
| 4 | EURUSD M15 2025 | $402.20 | $-97.80 | 🔴 -19.56% | 140 | 60 | 3 | 1 | 2% |

## Summary

- **Average P&L:** -4.45%
- **Total P&L (across all tests):** $-89.02
- **Best:** EURUSD M15 2024 → +1.74%
- **Worst:** EURUSD M15 2025 → -19.56%
