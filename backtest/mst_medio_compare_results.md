# MST Medio v4.10 — Scenario Comparison

**Date:** 2026-02-24 10:35  
**Deposit:** $500  |  **Leverage:** 1:100  |  **Risk:** $5/trade  

## Scenarios

| ID | ATR× | TP | MTF Consensus | Intent |
|----|------|----|---------------|--------|
| A_Baseline | 2.0 | 3R | ≥3/5 | Baseline |
| B_WideSL   | 3.0 | 3R | ≥3/5 | Wider SL = more room |
| C_NoMTF    | 2.0 | 3R | Off  | Isolate MTF effect |
| D_GongLoi  | 3.0 | 10R| ≥3/5 | Ride profits via trail |

## Results by Period


### A_Baseline (ATR×2.0 | TP 3.0R | MTF true)

| Period | Balance | P&L | % | Deals | SL | TP | BE | Win% |
|--------|---------|-----|---|-------|----|----|----|------|
| H1-2025 | $501.37 | $+1.37 | 🟢 +0.27% | 69 | 23 | 0 | 0 | 0% |
| M15-2025 | $402.20 | $-97.80 | 🔴 -19.56% | 140 | 60 | 3 | 1 | 2% |

### B_WideSL (ATR×3.0 | TP 3.0R | MTF true)

| Period | Balance | P&L | % | Deals | SL | TP | BE | Win% |
|--------|---------|-----|---|-------|----|----|----|------|
| H1-2025 | — | — | ❌ No log file | — | — | — | — | — |
| M15-2025 | $477.97 | $-22.03 | 🔴 -4.41% | 141 | 49 | 6 | 2 | 4% |

### C_NoMTF (ATR×2.0 | TP 3.0R | MTF false)

| Period | Balance | P&L | % | Deals | SL | TP | BE | Win% |
|--------|---------|-----|---|-------|----|----|----|------|
| H1-2025 | $516.03 | $+16.03 | 🟢 +3.21% | 75 | 21 | 1 | 1 | 1% |
| M15-2025 | $427.94 | $-72.06 | 🔴 -14.41% | 179 | 64 | 9 | 20 | 5% |

### D_GongLoi (ATR×3.0 | TP 10.0R | MTF true)

| Period | Balance | P&L | % | Deals | SL | TP | BE | Win% |
|--------|---------|-----|---|-------|----|----|----|------|
| H1-2025 | $527.29 | $+27.29 | 🟢 +5.46% | 68 | 30 | 0 | 0 | 0% |
| M15-2025 | $457.72 | $-42.28 | 🔴 -8.46% | 131 | 62 | 0 | 3 | 0% |

## Summary Comparison (Avg across all periods)

| Scenario | Avg P&L% | Total P&L | Avg Win% | Notes |
|----------|----------|-----------|----------|-------|
| A_Baseline | 🔴 -9.64% | $-96.43 | 1% | |
| B_WideSL | 🔴 -4.41% | $-22.03 | 4% | |
| C_NoMTF | 🔴 -5.60% | $-56.03 | 4% | |
| D_GongLoi | 🔴 -1.50% | $-14.99 | 0% | |
