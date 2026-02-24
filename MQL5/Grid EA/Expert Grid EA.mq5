//+------------------------------------------------------------------+
//| Expert Grid EA.mq5                                              |
//| Trend-Following Grid Trading Strategy                           |
//| v4.6 - Sharp Move / News Exit detector                         |
//|         If price moves > N pts in M minutes -> CLOSE ALL +     |
//|         pause K minutes. Protects against news spikes.         |
//|         Also: Fibonacci sizing, ADXMax=35, TP=60, SL=90        |
//|                                                                 |
//| Logic:                                                          |
//|   1. Determine trend from D1 EMA50/EMA200 crossover            |
//|   2. UPTREND  -> place BUY LIMIT orders below current price    |
//|      DOWNTREND -> place SELL LIMIT orders above current price  |
//|   3. Each order: TP = GridTP pts, SL = GridSL pts (hard cut)   |
//|   4. When trend REVERSES: close all grid, reopen opposite dir  |
//|   5. ADX filter: grid only when D1 ADX in [min, max] range     |
//|   6. Time filter: block grid during known volatile windows     |
//|   7. ATR filter: if current bar ATR > InpATRMultiplier x avg  |
//|      -> market is spiking -> block NEW grid orders             |
//|   8. Cooldown: drawdown > N% -> pause X days then RESUME       |
//|   9. Fibonacci sizing: level 0 (nearest) = BaseRisk*1.0        |
//|      level 1 = *0.618  level 2 = *0.382                        |
//|      level 3 = *0.236  level 4+ = *0.146                       |
//|  10. Sharp Move: price moves > SharpMovePts in SharpMoveMin    |
//|      -> CLOSE ALL open positions/orders immediately            |
//|      -> pause SharpMovePauseMins before resuming               |
//|      Unlike ATR filter, this EXITS existing trades on news     |
//|                                                                 |
//| Best Assets: EURUSD, EURGBP, AUDNZD (low volatility pairs)    |
//| Cooldown:   15% drawdown -> pause 5 days -> resume             |
//| Hard Stop:  30% drawdown -> permanent halt (circuit breaker)   |
//| Daily Limit: 3% -> pause until tomorrow                        |
//| Grid:       Step=30pts TP=60pts SL=90pts                       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MTS"
#property link      ""
#property version   "4.60"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//=============================================================================
// INPUTS
//=============================================================================
// GRID
input int    InpGridLevels      = 5;      // Max grid levels open at once
input int    InpGridStep        = 30;     // Grid step in POINTS (30 = 3 pips EURUSD)
input int    InpGridTP          = 60;     // TP per level in POINTS (2:1 vs step)
input int    InpGridSL          = 90;     // SL per level in POINTS (3:1 SL vs step - grid style)
input int    InpGridOffset      = 50;     // Start first level X points from current price

// POSITION SIZING
input bool   InpUseDynamicLot   = true;   // Dynamic lot sizing
input double InpLotSize         = 0.01;   // Fixed lot (if dynamic=false)
input double InpRiskPctPerLevel = 0.15;   // Risk % per grid level (base, applied to level 0)
// FIBONACCI SIZING
input bool   InpUseFiboSizing   = true;   // Fibonacci lot: nearest level = largest, further = smaller
// Fibo multipliers per level index (0=nearest price, 4=farthest)
// Default: 1.000, 0.618, 0.382, 0.236, 0.146 (standard Fibo retracement ratios)

// TREND FILTER
input bool   InpUseTrendFilter  = true;   // Use D1 EMA trend filter
input int    InpEMAFast         = 50;     // D1 EMA fast period
input int    InpEMASlow         = 200;    // D1 EMA slow period
input ENUM_TIMEFRAMES InpTrendTF= PERIOD_D1; // Trend timeframe

// ADX FILTER
// For TREND-FOLLOWING grids: require ADX > threshold to confirm trend is strong
// (opposite of anti-trend/ranging grids which use ADX < threshold)
input bool   InpUseADXFilter    = true;   // Filter by ADX
input int    InpADXPeriod       = 14;     // ADX period
input int    InpADXMinTrend     = 20;     // Grid only when D1 ADX > this (trend confirmed)
input int    InpADXMaxTrend     = 35;     // Block grid when D1 ADX > this (trend too strong = dangerous)
input ENUM_TIMEFRAMES InpADXTF  = PERIOD_D1; // ADX timeframe

// ATR SPIKE FILTER (NEW v4.0)
// Blocks new grid orders when current candle ATR >> average ATR (spike detected)
input bool   InpUseATRFilter    = true;   // Enable ATR spike filter
input int    InpATRPeriod       = 14;     // ATR averaging period
input double InpATRMultiplier   = 2.5;    // Block if current ATR > X * avg ATR (2.5 = ~8-12% of candles)
input ENUM_TIMEFRAMES InpATRTF  = PERIOD_H1; // ATR timeframe (H1 catches events well)

// MONEY MANAGEMENT
// Cooldown: when drawdown > InpMaxLossPct, EA pauses InpCooldownDays then RESUMES
// Hard Stop (permanent): only if drawdown > InpHardStopPct (circuit breaker, set high)
input double InpMaxLossPct      = 15.0;   // COOLDOWN: drawdown > X% -> pause N days
input int    InpCooldownDays    = 5;      // Days to pause after hitting MaxLoss drawdown
input double InpHardStopPct     = 30.0;   // HARD STOP (permanent): drawdown > X% -> EA disabled
input double InpMaxDailyLossPct = 3.0;    // Daily loss > X% -> pause until tomorrow
input double InpTakeProfitPct   = 6.0;    // Total profit > X% -> bank gains and reset

// SESSION FILTER
input bool   InpUseSessionFilter= true;   // Restrict to trading sessions
input int    InpSessionStart    = 2;      // GMT session open hour (default 02:00 = Asia open)
input int    InpSessionEnd      = 20;     // GMT session close hour (default 20:00 = before NY close)
// HIGH-VOLATILITY WINDOWS (block new grid orders during these windows, GMT)
// Window 1: London open volatility
input bool   InpBlockLondonOpen = true;   // Block London open (07:00-08:30 GMT)
// Window 2: NY open volatility (NFP, retail sales, etc.)
input bool   InpBlockNYOpen     = true;   // Block NY open (13:00-14:30 GMT)
// Window 3: global session close / rollover
input bool   InpBlockRollover   = true;   // Block rollover period (21:00-23:00 GMT)

// SHARP MOVE / NEWS EXIT DETECTOR (v4.6)
// If price moves more than InpSharpMovePts within InpSharpMoveMinutes:
//   -> CLOSE ALL open positions and pending orders immediately
//   -> Pause trading for InpSharpMovePauseMins minutes
// This is the "news exit" - unlike ATR filter (blocks new orders only),
// this actively CLOSES existing trades to protect against sudden directional moves.
input bool   InpUseSharpMove      = true;  // Enable sharp move / news exit
input int    InpSharpMovePts      = 150;   // Points moved in window = news event (150 = 15 pips EURUSD)
input int    InpSharpMoveMinutes  = 5;     // Look-back window in minutes (compare current price vs N min ago)
input int    InpSharpMovePauseMins= 30;    // Minutes to pause after sharp move detected

// VISUAL
input bool   InpShowLevels      = true;   // Draw grid lines on chart
input color  InpBuyColor        = clrDodgerBlue;
input color  InpSellColor       = clrTomato;
input ulong  InpMagic           = 20260222;

//=============================================================================
// GLOBALS
//=============================================================================
CTrade         trade;
CPositionInfo  pos;
COrderInfo     ord;

double g_startBalance   = 0.0;
double g_dailyStartBal  = 0.0;
int    g_dailyDate       = 0;
bool   g_hardStopFired   = false;
bool   g_gridPaused      = false;
datetime g_pauseUntil   = 0;

int    g_trendDir        = 0;
int    g_lastTrendDir    = 0;

int    g_emaFastHandle   = INVALID_HANDLE;
int    g_emaSlowHandle   = INVALID_HANDLE;
int    g_adxHandle       = INVALID_HANDLE;
int    g_atrHandle       = INVALID_HANDLE;

double g_point;
int    g_digits;
datetime g_sharpMoveLastFire = 0;  // Timestamp of last sharp move exit (prevent rapid re-firing)

//=============================================================================
// INIT
//=============================================================================
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagic);
    trade.SetDeviationInPoints(20);

    g_point  = _Point;
    g_digits = _Digits;

    g_startBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
    g_dailyStartBal = g_startBalance;
    MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
    g_dailyDate = dt.day;

    if(InpUseTrendFilter)
    {
        g_emaFastHandle = iMA(_Symbol, InpTrendTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
        g_emaSlowHandle = iMA(_Symbol, InpTrendTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
        if(g_emaFastHandle == INVALID_HANDLE || g_emaSlowHandle == INVALID_HANDLE)
        {
            Print("[Grid EA] ERROR: Cannot create EMA handles");
            return INIT_FAILED;
        }
    }

    if(InpUseADXFilter)
    {
        g_adxHandle = iADX(_Symbol, InpADXTF, InpADXPeriod);
        if(g_adxHandle == INVALID_HANDLE)
        {
            Print("[Grid EA] ERROR: Cannot create ADX handle");
            return INIT_FAILED;
        }
    }

    if(InpUseATRFilter)
    {
        g_atrHandle = iATR(_Symbol, InpATRTF, InpATRPeriod);
        if(g_atrHandle == INVALID_HANDLE)
        {
            Print("[Grid EA] ERROR: Cannot create ATR handle");
            return INIT_FAILED;
        }
    }

    Print("[Grid EA] v4.6 Init OK. Balance=", DoubleToString(g_startBalance,2),
          " Step=", InpGridStep, "pts TP=", InpGridTP, "pts SL=", InpGridSL, "pts Levels=", InpGridLevels,
          " Cooldown=", InpMaxLossPct, "%/", InpCooldownDays, "d HardStop=", InpHardStopPct,
          "% DailyLoss=", InpMaxDailyLossPct, "%",
          " ADX=", InpADXMinTrend, "~", InpADXMaxTrend, " ATRFilter=", InpUseATRFilter, "(x", InpATRMultiplier,
          ") FiboSizing=", InpUseFiboSizing,
          " SharpMove=", InpUseSharpMove, "(", InpSharpMovePts, "pts/", InpSharpMoveMinutes, "min pause=", InpSharpMovePauseMins, "min)",
          " BlockLondon=", InpBlockLondonOpen, " BlockNY=", InpBlockNYOpen);
    return INIT_SUCCEEDED;
}

//=============================================================================
// DEINIT
//=============================================================================
void OnDeinit(const int reason)
{
    if(g_emaFastHandle != INVALID_HANDLE) IndicatorRelease(g_emaFastHandle);
    if(g_emaSlowHandle != INVALID_HANDLE) IndicatorRelease(g_emaSlowHandle);
    if(g_adxHandle     != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
    if(g_atrHandle     != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
    if(InpShowLevels) DeleteAllObjects();
}

//=============================================================================
// ON TICK
//=============================================================================
void OnTick()
{
    if(g_hardStopFired) return;

    // New day reset
    MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
    if(dt.day != g_dailyDate)
    {
        g_dailyDate     = dt.day;
        g_dailyStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
    }

    // Check cooldown/pause expiry every tick
    if(g_gridPaused && !g_hardStopFired && g_pauseUntil > 0 && TimeCurrent() >= g_pauseUntil)
    {
        g_gridPaused     = false;
        g_pauseUntil     = 0;
        // Reset balance reference so cooldown period loss doesn't keep triggering again
        g_startBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
        g_dailyStartBal  = g_startBalance;
        Print("[Grid EA] Cooldown ENDED. Resuming. New balance ref=", DoubleToString(g_startBalance,2));
    }

    // Sharp move / news exit: check and close ALL positions if price spiked
    // Must run BEFORE pause check so it can exit even in new trades
    if(CheckSharpMove()) return;

    if(CheckStops()) return;
    if(g_gridPaused) return;
    if(InpUseSessionFilter && !IsInSession()) return;
    if(InpUseATRFilter    && IsHighVolatility()) return;

    // Get trend
    int newTrend = GetTrendDir();

    // Trend reversal: clear grid and switch
    if(newTrend != 0 && newTrend != g_lastTrendDir && g_lastTrendDir != 0)
    {
        Print("[Grid EA] Trend REVERSED ", g_lastTrendDir, " -> ", newTrend, ". Clearing grid.");
        CloseAllGrid();
        g_lastTrendDir = newTrend;
        g_trendDir     = newTrend;
    }
    else if(newTrend != 0)
    {
        g_trendDir     = newTrend;
        g_lastTrendDir = newTrend;
    }

    if(g_trendDir == 0) return;

    // ADX filter
    if(InpUseADXFilter && !IsRanging()) return;

    // Manage grid
    ManageGrid(g_trendDir);

    if(InpShowLevels) DrawGrid(g_trendDir);
}

//=============================================================================
// GET TREND DIRECTION (D1 EMA cross)
//=============================================================================
int GetTrendDir()
{
    if(!InpUseTrendFilter) return +1;

    double fast[], slow[];
    ArraySetAsSeries(fast, true);
    ArraySetAsSeries(slow, true);

    if(CopyBuffer(g_emaFastHandle, 0, 0, 2, fast) < 2) return g_trendDir;
    if(CopyBuffer(g_emaSlowHandle, 0, 0, 2, slow) < 2) return g_trendDir;

    if(fast[0] > slow[0]) return +1;
    if(fast[0] < slow[0]) return -1;
    return 0;
}

//=============================================================================
// ADX FILTER
//=============================================================================
bool IsRanging()
{
    if(!InpUseADXFilter) return true;

    double adx[];
    ArraySetAsSeries(adx, true);
    if(CopyBuffer(g_adxHandle, 0, 0, 1, adx) < 1) return true;
    // Trend-following grid: ADX must be in range [min, max]
    // Below min = not trending enough, above max = trending too hard (dangerous for grid)
    if(InpADXMaxTrend > 0 && adx[0] > InpADXMaxTrend) return false;
    return (adx[0] > InpADXMinTrend);
}

//=============================================================================
// MANAGE GRID
//=============================================================================
void ManageGrid(int trendDir)
{
    double step   = InpGridStep   * g_point;
    double tp     = InpGridTP     * g_point;
    double offset = InpGridOffset * g_point;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    int activeCount = CountActive(trendDir);
    if(activeCount >= InpGridLevels) return;

    int needed = InpGridLevels - activeCount;

    double existingLevels[];
    GetActiveLevels(trendDir, existingLevels);

    int placed = 0;

    if(trendDir == +1)
    {
        double basePrice = bid - offset;
        for(int i = 0; i < InpGridLevels && placed < needed; i++)
        {
            double lvl = NormalizeDouble(basePrice - i * step, g_digits);
            if(lvl <= 0) break;
            if(LevelExists(existingLevels, lvl)) continue;
            double lot = CalcLotFibo(i);
            double tpPrice = NormalizeDouble(lvl + tp, g_digits);
            double slPrice = (InpGridSL > 0) ? NormalizeDouble(lvl - InpGridSL * g_point, g_digits) : 0.0;
            if(trade.BuyLimit(lot, lvl, _Symbol, slPrice, tpPrice, ORDER_TIME_GTC, 0, "TFG Buy"))
                placed++;
        }
    }
    else
    {
        double basePrice = ask + offset;
        for(int i = 0; i < InpGridLevels && placed < needed; i++)
        {
            double lvl = NormalizeDouble(basePrice + i * step, g_digits);
            if(LevelExists(existingLevels, lvl)) continue;
            double lot = CalcLotFibo(i);
            double tpPrice = NormalizeDouble(lvl - tp, g_digits);
            double slPrice = (InpGridSL > 0) ? NormalizeDouble(lvl + InpGridSL * g_point, g_digits) : 0.0;
            if(trade.SellLimit(lot, lvl, _Symbol, slPrice, tpPrice, ORDER_TIME_GTC, 0, "TFG Sell"))
                placed++;
        }
    }
}

//=============================================================================
// COUNT ACTIVE (positions + pending)
//=============================================================================
int CountActive(int trendDir)
{
    int count = 0;
    for(int i = PositionsTotal()-1; i >= 0; i--)
        if(pos.SelectByIndex(i) && pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
            if((trendDir==+1 && pos.PositionType()==POSITION_TYPE_BUY) ||
               (trendDir==-1 && pos.PositionType()==POSITION_TYPE_SELL)) count++;

    for(int i = OrdersTotal()-1; i >= 0; i--)
        if(ord.SelectByIndex(i) && ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
            if((trendDir==+1 && ord.OrderType()==ORDER_TYPE_BUY_LIMIT) ||
               (trendDir==-1 && ord.OrderType()==ORDER_TYPE_SELL_LIMIT)) count++;
    return count;
}

//=============================================================================
// GET ACTIVE LEVELS
//=============================================================================
void GetActiveLevels(int trendDir, double &out[])
{
    ArrayResize(out, 0);
    for(int i = PositionsTotal()-1; i >= 0; i--)
        if(pos.SelectByIndex(i) && pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
            if((trendDir==+1 && pos.PositionType()==POSITION_TYPE_BUY) ||
               (trendDir==-1 && pos.PositionType()==POSITION_TYPE_SELL))
            { int n=ArraySize(out); ArrayResize(out,n+1); out[n]=pos.PriceOpen(); }

    for(int i = OrdersTotal()-1; i >= 0; i--)
        if(ord.SelectByIndex(i) && ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
            if((trendDir==+1 && ord.OrderType()==ORDER_TYPE_BUY_LIMIT) ||
               (trendDir==-1 && ord.OrderType()==ORDER_TYPE_SELL_LIMIT))
            { int n=ArraySize(out); ArrayResize(out,n+1); out[n]=ord.PriceOpen(); }
}

//=============================================================================
// LEVEL EXISTS
//=============================================================================
bool LevelExists(double &levels[], double price)
{
    double tol = InpGridStep * g_point * 0.4;
    for(int i = 0; i < ArraySize(levels); i++)
        if(MathAbs(levels[i] - price) < tol) return true;
    return false;
}

//=============================================================================
// FIBONACCI MULTIPLIER FOR LEVEL INDEX
// Level 0 (nearest price) = 1.000 (largest)
// Level 1 = 0.618, Level 2 = 0.382, Level 3 = 0.236, Level 4+ = 0.146
// These are standard Fibonacci retracement ratios (descending)
//=============================================================================
double GetFiboMultiplier(int levelIndex)
{
    if(!InpUseFiboSizing) return 1.0;
    static double fibo[] = {1.000, 0.618, 0.382, 0.236, 0.146};
    int idx = (levelIndex < ArraySize(fibo)) ? levelIndex : ArraySize(fibo) - 1;
    return fibo[idx];
}

//=============================================================================
// CALCULATE LOT (BASE — for level 0 / uniform)
//=============================================================================
double CalcLot()
{
    return CalcLotFibo(0);
}

//=============================================================================
// CALCULATE LOT WITH FIBONACCI SIZING
// levelIndex: 0 = nearest to price (biggest lot), higher = farther (smaller lot)
//=============================================================================
double CalcLotFibo(int levelIndex)
{
    if(!InpUseDynamicLot)
    {
        if(!InpUseFiboSizing) return InpLotSize;
        double fiboLot = InpLotSize * GetFiboMultiplier(levelIndex);
        double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
        double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
        fiboLot = MathFloor(fiboLot / lotStep) * lotStep;
        return MathMax(minLot, MathMin(maxLot, fiboLot));
    }

    double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmt  = balance * InpRiskPctPerLevel / 100.0;
    // Apply Fibonacci multiplier to risk amount
    riskAmt *= GetFiboMultiplier(levelIndex);

    // Use SL distance for risk-accurate sizing (not TP)
    // If no SL set (InpGridSL=0), fall back to TP distance
    double riskDist = (InpGridSL > 0) ? InpGridSL * g_point : InpGridTP * g_point;

    double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tickVal <= 0 || tickSize <= 0) return InpLotSize;

    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    double lot = riskAmt / (riskDist / tickSize * tickVal);
    lot = MathFloor(lot / lotStep) * lotStep;
    lot = MathMax(minLot, MathMin(maxLot, lot));
    return lot;
}

//=============================================================================
// CLOSE ALL GRID
//=============================================================================
void CloseAllGrid()
{
    for(int i = PositionsTotal()-1; i >= 0; i--)
        if(pos.SelectByIndex(i) && pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
            trade.PositionClose(pos.Ticket());
    for(int i = OrdersTotal()-1; i >= 0; i--)
        if(ord.SelectByIndex(i) && ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
            trade.OrderDelete(ord.Ticket());
}

//=============================================================================
// SHARP MOVE / NEWS EXIT DETECTOR  (v4.6)
// Compares current BID to the closing price of the M1 bar N minutes ago.
// If move > InpSharpMovePts -> close all grid immediately + pause K minutes.
// Unlike ATR filter (blocks new orders only), this EXITS existing trades.
//=============================================================================
bool CheckSharpMove()
{
    if(!InpUseSharpMove || g_hardStopFired) return false;

    // Prevent re-firing while already paused from a sharp move
    if(g_gridPaused && g_sharpMoveLastFire > 0 &&
       TimeCurrent() - g_sharpMoveLastFire < (datetime)(InpSharpMovePauseMins * 60))
        return false;

    double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Get close price of M1 bar that was InpSharpMoveMinutes bars ago
    double pastClose[];
    ArraySetAsSeries(pastClose, true);
    if(CopyClose(_Symbol, PERIOD_M1, InpSharpMoveMinutes, 1, pastClose) < 1) return false;

    double movedPts = MathAbs(currentBid - pastClose[0]) / g_point;

    if(movedPts >= InpSharpMovePts)
    {
        Print("[Grid EA] SHARP MOVE DETECTED! Price moved ", DoubleToString(movedPts, 1),
              " pts in ", InpSharpMoveMinutes, " min (threshold=", InpSharpMovePts, " pts).",
              " Closing all + pausing ", InpSharpMovePauseMins, " min.");
        CloseAllGrid();
        g_gridPaused        = true;
        g_pauseUntil        = TimeCurrent() + (datetime)(InpSharpMovePauseMins * 60);
        g_sharpMoveLastFire = TimeCurrent();
        return true;
    }
    return false;
}

// Override cooldown end to also reset sharp move state
// (handled in OnTick cooldown expiry block — g_sharpMoveLastFire stays set
//  so the move is logged, but g_gridPaused=false allows resuming)

//=============================================================================
// CHECK STOPS
//=============================================================================
bool CheckStops()
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);

    // Permanent hard stop (circuit breaker - only for extreme loss)
    if(InpHardStopPct > 0)
    {
        double dd = (g_startBalance - equity) / g_startBalance * 100.0;
        if(dd >= InpHardStopPct)
        {
            Print("[Grid EA] HARD STOP! Drawdown=", DoubleToString(dd,2),
                  "% >= ", InpHardStopPct, "%. EA DISABLED permanently.");
            CloseAllGrid();
            g_hardStopFired = true;
            g_gridPaused    = true;
            return true;
        }
    }

    // Cooldown: drawdown > threshold -> pause N days then resume
    if(InpMaxLossPct > 0 && !g_gridPaused)
    {
        double dd = (g_startBalance - equity) / g_startBalance * 100.0;
        if(dd >= InpMaxLossPct)
        {
            datetime resumeAt = TimeCurrent() + (datetime)(InpCooldownDays * 86400);
            Print("[Grid EA] Cooldown! Drawdown=", DoubleToString(dd,2),
                  "% >= ", InpMaxLossPct, "%. Pausing ", InpCooldownDays, " days until ",
                  TimeToString(resumeAt, TIME_DATE|TIME_MINUTES));
            CloseAllGrid();
            g_gridPaused = true;
            g_pauseUntil = resumeAt;
            // Reset balance reference after cooldown gap - will re-evaluate fresh
            return true;
        }
    }

    if(InpMaxDailyLossPct > 0)
    {
        double dLoss = (g_dailyStartBal - equity) / g_dailyStartBal * 100.0;
        if(dLoss >= InpMaxDailyLossPct)
        {
            Print("[Grid EA] Daily loss ", DoubleToString(dLoss,2),
                  "% >= ", InpMaxDailyLossPct, "%. Pausing until tomorrow.");
            CloseAllGrid();
            g_gridPaused = true;
            MqlDateTime dt2; TimeToStruct(TimeCurrent(), dt2);
            dt2.hour = 0; dt2.min = 5; dt2.sec = 0;
            g_pauseUntil = StructToTime(dt2) + 86400;
            return true;
        }
    }

    if(InpTakeProfitPct > 0)
    {
        double prof = (equity - g_startBalance) / g_startBalance * 100.0;
        if(prof >= InpTakeProfitPct)
        {
            Print("[Grid EA] Profit target ", DoubleToString(prof,2),
                  "%. Banking gains. Resetting balance reference.");
            CloseAllGrid();
            g_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
            return false;
        }
    }

    return false;
}

//=============================================================================
// ATR SPIKE FILTER  (v4.0)
// Compares current H1 ATR to average ATR. If current >> average = spike event.
// Blocking logic: no new grid orders when spiking. Existing positions kept.
//=============================================================================
bool IsHighVolatility()
{
    if(!InpUseATRFilter || g_atrHandle == INVALID_HANDLE) return false;

    // Need InpATRPeriod+2 bars: [0]=current, [1..N]=history for average
    int bufSize = InpATRPeriod + 2;
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(g_atrHandle, 0, 0, bufSize, atr) < bufSize) return false;

    double currentATR = atr[0];
    double sumATR = 0.0;
    for(int i = 1; i <= InpATRPeriod; i++) sumATR += atr[i];
    double avgATR = sumATR / InpATRPeriod;

    if(avgATR <= 0) return false;

    bool spike = (currentATR > avgATR * InpATRMultiplier);
    if(spike)
    {
        static datetime lastLog4 = 0;
        if(TimeCurrent() - lastLog4 > 1800)
        {
            Print("[Grid EA] ATR spike! Current=", DoubleToString(currentATR/g_point,1),
                  "pts Avg=", DoubleToString(avgATR/g_point,1),
                  "pts Ratio=", DoubleToString(currentATR/avgATR,2));
            lastLog4 = TimeCurrent();
        }
    }
    return spike;
}

//=============================================================================
// SESSION FILTER
// Returns false during high-volatility windows → no new grid orders placed
// Existing positions are NOT closed; just no NEW orders during blocked times
//=============================================================================
bool IsInSession()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int h = dt.hour;
    int m = dt.min;
    int hm = h * 100 + m;  // e.g. 730 = 07:30

    // 1. Outside main trading window
    if(h < InpSessionStart || h >= InpSessionEnd) return false;

    // 2. London open: 07:00 - 08:30 GMT (high spike risk)
    if(InpBlockLondonOpen && hm >= 700 && hm < 830)
    {
        static datetime lastLog = 0;
        if(TimeCurrent() - lastLog > 3600) { Print("[Grid EA] Blocked: London open window"); lastLog = TimeCurrent(); }
        return false;
    }

    // 3. NY open: 13:00 - 14:30 GMT (major data releases overlap)
    if(InpBlockNYOpen && hm >= 1300 && hm < 1430)
    {
        static datetime lastLog2 = 0;
        if(TimeCurrent() - lastLog2 > 3600) { Print("[Grid EA] Blocked: NY open window"); lastLog2 = TimeCurrent(); }
        return false;
    }

    // 4. Rollover: 21:00 - 23:00 GMT (thin liquidity, spread spikes)
    if(InpBlockRollover && hm >= 2100 && hm < 2300)
    {
        static datetime lastLog3 = 0;
        if(TimeCurrent() - lastLog3 > 3600) { Print("[Grid EA] Blocked: Rollover window"); lastLog3 = TimeCurrent(); }
        return false;
    }

    return true;
}

//=============================================================================
// DRAW GRID LINES
//=============================================================================
void DrawGrid(int trendDir)
{
    double step   = InpGridStep   * g_point;
    double offset = InpGridOffset * g_point;
    double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    DeleteAllObjects();

    if(trendDir == +1)
    {
        for(int i = 0; i < InpGridLevels; i++)
        {
            double lvl = bid - offset - i * step;
            double tp  = lvl + InpGridTP * g_point;
            DrawHLine("TFG_B_"  + IntegerToString(i), lvl, InpBuyColor, STYLE_DOT,        1);
            DrawHLine("TFG_BT_" + IntegerToString(i), tp,  InpBuyColor, STYLE_DASHDOTDOT, 1);
        }
    }
    else if(trendDir == -1)
    {
        for(int i = 0; i < InpGridLevels; i++)
        {
            double lvl = ask + offset + i * step;
            double tp  = lvl - InpGridTP * g_point;
            DrawHLine("TFG_S_"  + IntegerToString(i), lvl, InpSellColor, STYLE_DOT,        1);
            DrawHLine("TFG_ST_" + IntegerToString(i), tp,  InpSellColor, STYLE_DASHDOTDOT, 1);
        }
    }
}

void DrawHLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width)
{
    if(ObjectFind(0, name) < 0)
        ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
    ObjectSetDouble (0, name, OBJPROP_PRICE, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, name, OBJPROP_BACK,  true);
}

void DeleteAllObjects()
{
    ObjectsDeleteAll(0, "TFG_");
}
