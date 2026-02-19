//+------------------------------------------------------------------+
//| Expert MST Medio.mq5                                            |
//| MST Medio (Make Simple Trading by Medio)                        |
//| EA — 2-Step Breakout Confirmation System                        |
//|                                                                  |
//| Logic:                                                           |
//|   1. Detect HH/LL breakout (with impulse body filter)            |
//|   2. Find W1 Peak (first impulse wave extreme after break)       |
//|   3. Wait for CLOSE beyond W1 Peak → Confirmed! → Signal         |
//|   4. Entry = old SH/SL, SL = swing opposite                     |
//|   5. TP = Fixed RR or Confirm Break candle H/L                  |
//|   6. Breakeven: move SL to entry when profit >= BE_AT_R × risk   |
//|   7. On new signal: close all existing positions → open new      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MTS"
#property link      ""
#property version   "4.00"
#property strict

// ============================================================================
// ============================================================================
// INPUTS
// ============================================================================
// ============================================================================
// POSITION SIZING & RISK MANAGEMENT
// ============================================================================
input bool   InpUseDynamicLot   = false;    // Use Dynamic Position Sizing
input double InpLotSize         = 0.02;    // Fixed Lot Size (if dynamic=false)
input double InpRiskPct         = 2.0;     // Risk % per trade (dynamic sizing)
input double InpMaxRiskPct      = 2.0;     // Max Risk % per trade (0=no limit)
input double InpMaxDailyLossPct = 3.0;     // Max Daily Loss % (0=no limit)
input double InpMaxSLRiskPct    = 30.0;    // Max SL Risk % of balance (0=no limit)

// ============================================================================
// TRADING LOGIC PARAMETERS
// ============================================================================
input int    InpPivotLen     = 5;       // Pivot Length (5=significant swings, 3=frequent)
input double InpBreakMult    = 0.25;    // Break Multiplier
input double InpImpulseMult  = 1.5;     // Impulse Multiplier (1.5=strong breakouts only)
input double InpTPFixedRR    = 3.0;     // TP Fixed RR (0=confirm candle)
input double InpBEAtR        = 0.5;     // Breakeven at R (0=disabled)
input int    InpSLBufferPct  = 10;      // SL Buffer % (push SL 10% further to avoid stop hunts)
input int    InpEntryOffsetPts = 0;     // Entry Offset Pts (shift entry deeper vs exact swing level, 0=disabled)
input int    InpMinSLDistPts = 0;       // Min SL Distance Pts (skip tiny swings, 0=disabled)
input bool   InpUseATRSL     = false;   // Use ATR-based SL (vs swing-based)
input double InpATRMultiplier = 1.5;    // ATR Multiplier for SL distance
input int    InpATRPeriod    = 14;      // ATR calculation period

// ============================================================================
// TREND FILTER
// ============================================================================
input bool   InpUseTrendFilter = true;    // Use EMA Trend Filter
input int    InpEMAFastPeriod  = 50;      // EMA Fast Period
input int    InpEMASlowPeriod  = 200;     // EMA Slow Period
input bool   InpUseHTFFilter   = true;    // Use Higher Timeframe Trend Filter
input ENUM_TIMEFRAMES InpHTFTimeframe = PERIOD_H1; // HTF Timeframe for trend
input bool   InpAllowNoTrend   = false;   // Allow trades when trend=NONE/CONFLICT (only block opposite trend)

// ============================================================================
// PARTIAL TAKE PROFIT
// ============================================================================
input bool   InpUsePartialTP      = true;    // Use Partial TP (close partial at X×R, move SL to BE)
input double InpPartialTPAtR      = 0.5;     // Close partial at X × risk (R-multiple)
input double InpPartialTPPct      = 50.0;    // % of position to close at partial TP
input int    InpTrailAfterPartialPts = 0;    // Trailing stop pts after partial TP (0=use fixed BE)
input bool   InpSmartFlip          = true;   // Smart flip: keep profitable position when new signal arrives
input bool   InpRequireConfirmCandle = true;  // Require 1 confirm candle after entry fills (anti-chop)

input bool   InpShowVisual   = false;   // Show indicator on chart
input ulong  InpMagic        = 20260210;// Magic Number

// ============================================================================
// CONSTANTS
// ============================================================================
#define DEVIATION        20
#define SHOW_VISUAL      InpShowVisual
#define SHOW_SWINGS      false
#define SHOW_BREAK_LABEL true
#define SHOW_BREAK_LINE  true
#define COL_BREAK_UP     clrLime
#define COL_BREAK_DOWN   clrRed
#define COL_ENTRY_BUY    clrDodgerBlue
#define COL_ENTRY_SELL   clrHotPink
#define COL_SL           clrYellow
#define COL_TP           clrLimeGreen
#define COL_SWING_HIGH   clrOrange
#define COL_SWING_LOW    clrCornflowerBlue

// ============================================================================
// GLOBAL STATE
// ============================================================================
string g_objPrefix = "MSM_";
static datetime g_lastBarTime = 0;

// -- Swing History --
static double   g_sh1 = EMPTY_VALUE, g_sh0 = EMPTY_VALUE;
static datetime g_sh1_time = 0,      g_sh0_time = 0;
static double   g_sl1 = EMPTY_VALUE, g_sl0 = EMPTY_VALUE;
static datetime g_sl1_time = 0,      g_sl0_time = 0;

static double   g_slBeforeSH = EMPTY_VALUE;
static datetime g_slBeforeSH_time = 0;
static double   g_shBeforeSL = EMPTY_VALUE;
static datetime g_shBeforeSL_time = 0;

// -- 2-Step Confirmation State --
// States: 0=idle, 1=waiting confirm BUY, -1=waiting confirm SELL
static int    g_pendingState   = 0;
static double g_pendBreakPoint = EMPTY_VALUE;  // Entry level (sh0 for BUY, sl0 for SELL)
static double g_pendW1Peak     = EMPTY_VALUE;  // W1 peak (BUY) or W1 trough (SELL)
static double g_pendW1Trough   = EMPTY_VALUE;  // W1 trough tracking
static double g_pendSL         = EMPTY_VALUE;  // SL level
static datetime g_pendSL_time  = 0;
static datetime g_pendBreak_time = 0;          // Entry line start time

// -- Signal tracking --
static datetime g_lastBuySignal  = 0;

// -- Daily Loss Protection --
static double   g_dailyStartBalance = 0;
static datetime g_lastTradingDay    = 0;
static bool     g_dailyTradingPaused = false;
static datetime g_lastSellSignal = 0;

// -- Breakeven tracking --
static bool   g_beDone          = false;  // Has BE been moved for current trade?
static double g_beEntryPrice    = 0;      // Entry price for BE calculation
static double g_beOrigSL        = 0;      // Original SL price (for risk distance)
static bool   g_beIsBuy         = false;  // Direction of position

// -- Partial TP tracking --
static bool   g_partialTPDone   = false;  // Has partial TP been executed for current trade?
static bool   g_trailingActive  = false;  // Is trailing stop active after partial TP?

// -- Confirmation candle tracking --
static bool   g_confirmCandlePassed = false;  // Has 1 confirm candle closed after entry fill?
static int    g_confirmBarsWaited   = 0;       // Bars elapsed since entry (for confirm candle check)

// -- Active Lines --
static string g_activeEntryLineName = "";
static string g_activeSLLineName    = "";
static string g_activeTPLineName    = "";
static string g_activeEntryLblName  = "";
static string g_activeSLLblName     = "";
static string g_activeTPLblName     = "";
static double g_activeEntryPrice    = EMPTY_VALUE;
static double g_activeSLPrice       = EMPTY_VALUE;
static double g_activeTPPrice       = EMPTY_VALUE;
static bool   g_activeIsBuy         = false;
static bool   g_hasActiveLine       = false;

// -- Break count --
static int g_breakCount = 0;

// -- Indicator Handles (cached for efficiency) --
static int g_atrHandle = INVALID_HANDLE;
static int g_emaFastHandle = INVALID_HANDLE;
static int g_emaSlowHandle = INVALID_HANDLE;
static int g_htfEmaFastHandle = INVALID_HANDLE;
static int g_htfEmaSlowHandle = INVALID_HANDLE;

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

// Calculate ATR-based Stop Loss distance
// Returns SL price based on current ATR instead of swing levels
double CalculateATRSL(const bool isBuy, const double entry)
{
   if(!InpUseATRSL)
      return 0.0;  // Use swing-based SL
   
   // Use cached ATR handle
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("⚠️ ATR indicator handle not initialized - using swing-based SL");
      return 0.0;
   }
   
   double atrArray[1];
   if(CopyBuffer(g_atrHandle, 0, 0, 1, atrArray) <= 0)
   {
      Print("⚠️ ATR buffer copy failed - using swing-based SL");
      return 0.0;
   }
   
   double currentATR = atrArray[0];
   
   if(currentATR <= 0)
   {
      Print("⚠️ Invalid ATR value: ", currentATR, " - using swing-based SL");
      return 0.0;
   }
   
   // Calculate SL distance = ATR × Multiplier
   double slDistance = currentATR * InpATRMultiplier;
   double slPrice;
   
   if(isBuy)
      slPrice = entry - slDistance;
   else
      slPrice = entry + slDistance;
   
   // Log the calculation
   double slPips = slDistance / (_Point * 10);
   Print("📏 ATR-based SL: ATR=", NormalizeDouble(currentATR/_Point, 1), "pts",
         " × ", InpATRMultiplier, " = ", NormalizeDouble(slDistance/_Point, 1), "pts",
         " (", NormalizeDouble(slPips, 1), " pips)",
         " → SL=", NormalizeDouble(slPrice, _Digits));
   
   return slPrice;
}

// ============================================================================
// TREND FILTER: EMA-based trend detection on current + HTF timeframe
// Returns: +1 = uptrend (only BUY), -1 = downtrend (only SELL), 0 = no trend/conflicting
// ============================================================================
int GetTrendDirection()
{
   if(!InpUseTrendFilter)
      return 0;  // No filter = allow all trades
   
   // ── Current TF EMA check ──
   double emaFast[1], emaSlow[1];
   if(g_emaFastHandle == INVALID_HANDLE || g_emaSlowHandle == INVALID_HANDLE)
      return 0;
   
   if(CopyBuffer(g_emaFastHandle, 0, 1, 1, emaFast) <= 0 ||
      CopyBuffer(g_emaSlowHandle, 0, 1, 1, emaSlow) <= 0)
      return 0;
   
   int ctfTrend = 0;
   if(emaFast[0] > emaSlow[0]) ctfTrend = +1;   // EMA50 > EMA200 = uptrend
   else if(emaFast[0] < emaSlow[0]) ctfTrend = -1;  // EMA50 < EMA200 = downtrend
   
   // ── HTF EMA check (optional) ──
   if(!InpUseHTFFilter)
      return ctfTrend;
   
   double htfFast[1], htfSlow[1];
   if(g_htfEmaFastHandle == INVALID_HANDLE || g_htfEmaSlowHandle == INVALID_HANDLE)
      return ctfTrend;
   
   if(CopyBuffer(g_htfEmaFastHandle, 0, 1, 1, htfFast) <= 0 ||
      CopyBuffer(g_htfEmaSlowHandle, 0, 1, 1, htfSlow) <= 0)
      return ctfTrend;
   
   int htfTrend = 0;
   if(htfFast[0] > htfSlow[0]) htfTrend = +1;
   else if(htfFast[0] < htfSlow[0]) htfTrend = -1;
   
   // Both timeframes must agree for a valid trend signal
   if(ctfTrend == htfTrend)
      return ctfTrend;
   
   // Conflicting trends → no trade (protect capital)
   return 0;
}

// Check if a specific trade direction is allowed by trend filter
bool IsTrendAligned(const bool isBuy)
{
   int trend = GetTrendDirection();
   if(trend == 0)
   {
      // No clear trend / conflicting
      if(InpAllowNoTrend) return true;   // Relaxed: allow when no strong opposing trend
      return false;                       // Strict: skip (capital preservation)
   }
   if(isBuy && trend == +1) return true;   // BUY in uptrend ✓
   if(!isBuy && trend == -1) return true;  // SELL in downtrend ✓
   return false;  // Counter-trend → always blocked
}

void DeleteObjectsByPrefix(const string prefix)
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; --i)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

void DrawHLine(const string name, datetime t1, double price, datetime t2,
               color clr, ENUM_LINE_STYLE style, int width)
{
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price))
   {
      ObjectMove(0, name, 0, t1, price);
      ObjectMove(0, name, 1, t2, price);
   }
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawTextLabel(const string name, datetime t, double price,
                   const string text, color clr, int fontSize = 8)
{
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
      ObjectMove(0, name, 0, t, price);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawArrowIcon(const string name, datetime t, double price,
                   int code, color clr, int width)
{
   if(!ObjectCreate(0, name, OBJ_ARROW, 0, t, price))
      ObjectMove(0, name, 0, t, price);

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

// ============================================================================
// LINE MANAGEMENT
// ============================================================================
void TerminateActiveLines(datetime endTime)
{
   if(!g_hasActiveLine) return;
   if(g_activeEntryLineName != "")
      DrawHLine(g_activeEntryLineName, 0, g_activeEntryPrice, endTime,
                g_activeIsBuy ? COL_ENTRY_BUY : COL_ENTRY_SELL, STYLE_DASH, 1);
   if(g_activeSLLineName != "")
      DrawHLine(g_activeSLLineName, 0, g_activeSLPrice, endTime,
                COL_SL, STYLE_DASH, 1);
   if(g_activeTPLineName != "" && g_activeTPPrice != EMPTY_VALUE)
      DrawHLine(g_activeTPLineName, 0, g_activeTPPrice, endTime,
                COL_TP, STYLE_DASH, 1);
}

void ClearActiveLines()
{
   g_activeEntryLineName = "";
   g_activeSLLineName    = "";
   g_activeTPLineName    = "";
   g_activeEntryLblName  = "";
   g_activeSLLblName     = "";
   g_activeTPLblName     = "";
   g_activeEntryPrice    = EMPTY_VALUE;
   g_activeSLPrice       = EMPTY_VALUE;
   g_activeTPPrice       = EMPTY_VALUE;
   g_hasActiveLine       = false;
}

void ExtendActiveLines()
{
   if(!g_hasActiveLine) return;
   datetime now = TimeCurrent();
   if(g_activeEntryLineName != "")
      ObjectMove(0, g_activeEntryLineName, 1, now, g_activeEntryPrice);
   if(g_activeSLLineName != "")
      ObjectMove(0, g_activeSLLineName, 1, now, g_activeSLPrice);
   if(g_activeEntryLblName != "")
      ObjectMove(0, g_activeEntryLblName, 0, now, g_activeEntryPrice);
   if(g_activeSLLblName != "")
      ObjectMove(0, g_activeSLLblName, 0, now, g_activeSLPrice);
   if(g_activeTPLineName != "" && g_activeTPPrice != EMPTY_VALUE)
      ObjectMove(0, g_activeTPLineName, 1, now, g_activeTPPrice);
   if(g_activeTPLblName != "" && g_activeTPPrice != EMPTY_VALUE)
      ObjectMove(0, g_activeTPLblName, 0, now, g_activeTPPrice);
}

// ============================================================================
// PIVOT DETECTION
// ============================================================================
bool IsPivotHigh(int barIdx, int pivotLen)
{
   double val = iHigh(_Symbol, _Period, barIdx);
   for(int j = barIdx - pivotLen; j <= barIdx + pivotLen; j++)
   {
      if(j == barIdx || j < 0) continue;
      if(iHigh(_Symbol, _Period, j) >= val)
         return false;
   }
   return true;
}

bool IsPivotLow(int barIdx, int pivotLen)
{
   double val = iLow(_Symbol, _Period, barIdx);
   for(int j = barIdx - pivotLen; j <= barIdx + pivotLen; j++)
   {
      if(j == barIdx || j < 0) continue;
      if(iLow(_Symbol, _Period, j) <= val)
         return false;
   }
   return true;
}

// ============================================================================
// TRADE MANAGEMENT
// ============================================================================
double NormalizePrice(const double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) tick = _Point;
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
}

// ============================================================================
// ENHANCED POSITION SIZING WITH TIERED RISK SYSTEM
// ============================================================================
// Enhanced Position Sizing với Tiered Risk System
// Adaptive risk management dựa trên account growth
double CalculateEnhancedLotSize(const double entry, const double sl)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double tieredRisk;
   
   // Tiered risk based on account growth stages
   if (balance < 1500)
      tieredRisk = 0.75;      // Conservative start - focus on preservation
   else if (balance < 2500) 
      tieredRisk = 1.0;       // Growing phase - moderate risk
   else if (balance < 5000)
      tieredRisk = 1.5;       // Standard phase - normal operations
   else
      tieredRisk = 2.0;       // Aggressive phase - maximize growth
   
   double riskAmount = balance * (tieredRisk / 100.0);
   
   // SL is already finalized (ATR or swing) — no double calculation
   double slDistance = MathAbs(entry - sl);
   double lossPer1Lot;
   
   // Use OrderCalcProfit for accurate loss calculation
   if (!OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, entry, sl, lossPer1Lot))
   {
      // Fallback calculation  
      lossPer1Lot = slDistance / _Point * 10.0;
      Print("⚠️ OrderCalcProfit failed in CalculateEnhancedLotSize, using fallback");
   }
   else
   {
      lossPer1Lot = MathAbs(lossPer1Lot);
   }
   
   double calculatedLot = (lossPer1Lot > 0) ? riskAmount / lossPer1Lot : InpLotSize;
   
   // Normalize to broker specifications
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   calculatedLot = NormalizeDouble(calculatedLot / lotStep, 0) * lotStep;
   calculatedLot = MathMax(minLot, MathMin(maxLot, calculatedLot));
   
   Print("📊 Enhanced Position Sizing: Balance=$", balance, 
         " | Tier=", tieredRisk, "% | Risk=$", riskAmount, 
         " | SL=", slDistance/_Point, "pts | Lot=", calculatedLot);
   
   return calculatedLot;
}

// Check if trade risk exceeds max allowed risk %
// Uses OrderCalcProfit() for accurate cross-currency risk calculation
// Returns true if trade is safe, false if risk too high (skip trade)
bool CheckMaxRisk(const bool isBuy, const double entry, const double sl, const double lot)
{
   if(InpMaxRiskPct <= 0) return true;  // No limit

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0) return true;

   double slPoints  = MathAbs(entry - sl) / _Point;
   if(slPoints <= 0) return true;

   // Use OrderCalcProfit for accurate loss calculation (handles JPY pairs, cross rates, pip mode)
   double slLoss = 0;
   ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(orderType, _Symbol, lot, entry, sl, slLoss))
   {
      // Fallback: manual calculation
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0 || tickSize <= 0) return true;
      double pointValue = tickValue * (_Point / tickSize);
      slLoss = -(lot * slPoints * pointValue);
   }

   double riskMoney  = MathAbs(slLoss);
   double riskPct    = riskMoney / balance * 100.0;

   if(riskPct > InpMaxRiskPct)
   {
      Print("🛑 MAX RISK EXCEEDED: Calculated=", NormalizeDouble(riskPct, 2), "% ($",
            NormalizeDouble(riskMoney, 2), ") > MaxRisk=", InpMaxRiskPct,
            "% | Balance=$", NormalizeDouble(balance, 2),
            " | Lot=", lot, " | SL_Distance=", NormalizeDouble(slPoints, 1), "pts");
      return false;
   }

   Print("✅ Risk OK: ", NormalizeDouble(riskPct, 2), "% ($",
         NormalizeDouble(riskMoney, 2), ") ≤ MaxRisk=", InpMaxRiskPct,
         "% | Balance=$", NormalizeDouble(balance, 2));
   return true;
}

// Check if SL risk exceeds max allowed % of current balance
// Uses OrderCalcProfit() for accurate loss calculation
// Returns true if trade is safe, false if risk too high (skip trade)
bool CheckMaxSLRisk(const bool isBuy, const double entry, const double sl, const double lot)
{
   if(InpMaxSLRiskPct <= 0) return true;  // Disabled

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0) return true;

   // SL is already finalized — no ATR override needed
   double actualSL = sl;

   // Use OrderCalcProfit to get actual $ loss at SL price
   double slLoss = 0;
   ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(orderType, _Symbol, lot, entry, actualSL, slLoss))
   {
      // Fallback: manual calculation
      double slPoints  = MathAbs(entry - actualSL) / _Point;
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue > 0 && tickSize > 0)
      {
         double pointValue = tickValue * (_Point / tickSize);
         slLoss = -(lot * slPoints * pointValue);
      }
   }

   // slLoss is negative (it's a loss)
   double absLoss = MathAbs(slLoss);
   double riskPct = absLoss / balance * 100.0;

   if(riskPct > InpMaxSLRiskPct)
   {
      double balanceNeeded = absLoss / (InpMaxSLRiskPct / 100.0);
      double slDist = MathAbs(entry - actualSL);
      double slPips = slDist / (_Point * 10); // Convert to pips for display
      Print("🛑 MAX SL RISK — TRADE BLOCKED");
      Print("   Risk: ", NormalizeDouble(riskPct, 1), "% ($",
            NormalizeDouble(absLoss, 2), ") > MaxSLRisk=", InpMaxSLRiskPct, "%");
      Print("   Balance: $", NormalizeDouble(balance, 2),
            " | SL Distance: ", NormalizeDouble(slPips, 1), " pips",
            " | Lot: ", lot);
      Print("   ➡️ Cần nạp thêm: $", NormalizeDouble(balanceNeeded - balance, 2),
            " (tổng $", NormalizeDouble(balanceNeeded, 0),
            ") để trade lệnh này ở ", InpMaxSLRiskPct, "% risk");
      return false;
   }

   Print("✅ SL Risk OK: ", NormalizeDouble(riskPct, 1), "% ($",
         NormalizeDouble(absLoss, 2), ") ≤ MaxSLRisk=", InpMaxSLRiskPct,
         "% | Balance=$", NormalizeDouble(balance, 2));
   return true;
}

// Check if daily loss limit exceeded — pause trading for the rest of the day
// Uses BALANCE only (realized P/L) — so open positions can run to TP/SL
bool CheckDailyLoss()
{
   if(InpMaxDailyLossPct <= 0) return true;  // No limit

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentValue = balance;  // Only realized P/L — let positions run

   if(g_dailyStartBalance <= 0) return true;

   double lossPct = (g_dailyStartBalance - currentValue) / g_dailyStartBalance * 100.0;

   if(lossPct >= InpMaxDailyLossPct)
   {
      if(!g_dailyTradingPaused)
      {
         g_dailyTradingPaused = true;
         Print("🛑 DAILY LOSS LIMIT HIT: Loss=", NormalizeDouble(lossPct, 2),
               "% ($", NormalizeDouble(g_dailyStartBalance - currentValue, 2),
               ") >= MaxDailyLoss=", InpMaxDailyLossPct,
               "% | StartBalance=$", NormalizeDouble(g_dailyStartBalance, 2),
               " CurrentValue=$", NormalizeDouble(currentValue, 2),
               " | Trading PAUSED until next day");
         Alert("MST Medio: Daily loss limit ", NormalizeDouble(lossPct, 2),
               "% reached! Trading paused until next day.");
      }
      return false;
   }
   return true;
}

bool HasActiveOrders()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic)
         return true;
   }
   return false;
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req); ZeroMemory(res);
      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = _Symbol;
      req.volume    = PositionGetDouble(POSITION_VOLUME);
      req.deviation = DEVIATION;
      req.magic     = InpMagic;

      long posType = PositionGetInteger(POSITION_TYPE);
      if(posType == POSITION_TYPE_BUY)
      {  req.type = ORDER_TYPE_SELL; req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); }
      else
      {  req.type = ORDER_TYPE_BUY;  req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); }
      req.position = ticket;
      req.comment  = "MST_MEDIO_CLOSE";

      if(!OrderSend(req, res))
         Print("Close position failed. Ticket=", ticket, " Retcode=", res.retcode);
      else
         Print("✅ Closed position. Ticket=", ticket);
   }
}

// Close only positions that are in profit — let losing positions hit SL naturally
void ClosePositionsInProfit()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double profit = PositionGetDouble(POSITION_PROFIT);
      if(profit <= 0) continue;  // Skip losing positions — let SL handle them

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req); ZeroMemory(res);
      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = _Symbol;
      req.volume    = PositionGetDouble(POSITION_VOLUME);
      req.deviation = DEVIATION;
      req.magic     = InpMagic;

      long posType = PositionGetInteger(POSITION_TYPE);
      if(posType == POSITION_TYPE_BUY)
      {  req.type = ORDER_TYPE_SELL; req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); }
      else
      {  req.type = ORDER_TYPE_BUY;  req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); }
      req.position = ticket;
      req.comment  = "MST_MEDIO_CLOSE_PROFIT";

      if(!OrderSend(req, res))
         Print("Close profit position failed. Ticket=", ticket, " Retcode=", res.retcode);
      else
         Print("✅ Closed profit position. Ticket=", ticket, " Profit=", NormalizeDouble(profit, 2));
   }
}

void DeleteAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req); ZeroMemory(res);
      req.action = TRADE_ACTION_REMOVE;
      req.order  = ticket;

      if(!OrderSend(req, res))
         Print("Delete order failed. Ticket=", ticket, " Retcode=", res.retcode);
      else
         Print("✅ Deleted pending order. Ticket=", ticket);
   }
}

bool PlaceOrder(const bool isBuy, const double entry, const double sl, const double tp)
{
   // SL/TP already finalized by ProcessConfirmedSignal — no more overriding
   double entryN = NormalizePrice(entry);
   double slN    = NormalizePrice(sl);
   double tpN    = (tp > 0) ? NormalizePrice(tp) : 0;
   
   Print("🔄 PlaceOrder: ", (isBuy ? "BUY" : "SELL"), 
         " Entry=", entryN, " SL=", slN, " TP=", tpN);

   // Calculate lot size (single, consistent calculation)
   double lot;
   if(InpUseDynamicLot)
      lot = CalculateEnhancedLotSize(entryN, slN);
   else
      lot = InpLotSize;
   
   // Validate and clamp lot
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   if(stepLot > 0) lot = MathFloor(lot / stepLot) * stepLot;
   lot = NormalizeDouble(lot, 2);
   if(lot < minLot) lot = minLot;

   // Risk checks
   if(!CheckMaxRisk(isBuy, entryN, slN, lot))
      return false;
   if(!CheckMaxSLRisk(isBuy, entryN, slN, lot))
      return false;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Validate SL
   if(isBuy && slN >= entryN)
   { Print("Invalid BUY SL. SL=", slN, " >= Entry=", entryN); return false; }
   if(!isBuy && slN <= entryN)
   { Print("Invalid SELL SL. SL=", slN, " <= Entry=", entryN); return false; }

   ENUM_ORDER_TYPE type;
   if(isBuy)
   {
      if(entryN < ask)      type = ORDER_TYPE_BUY_LIMIT;
      else if(entryN > ask) type = ORDER_TYPE_BUY_STOP;
      else
      {
         // Market buy
         MqlTradeRequest req; MqlTradeResult res;
         ZeroMemory(req); ZeroMemory(res);
         req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol;
         req.volume = lot; req.type = ORDER_TYPE_BUY;
         req.price = ask; req.sl = slN; req.tp = tpN;
         req.magic = InpMagic; req.deviation = DEVIATION;
         req.comment = "MST_MEDIO_BUY";
         if(!OrderSend(req, res))
         { Print("OrderSend BUY market failed. Retcode=", res.retcode); return false; }
         Print("✅ BUY market. Ticket=", res.order, " Lot=", lot, " Entry=", ask, " SL=", slN, " TP=", tpN);
         return true;
      }
   }
   else
   {
      if(entryN > bid)      type = ORDER_TYPE_SELL_LIMIT;
      else if(entryN < bid) type = ORDER_TYPE_SELL_STOP;
      else
      {
         // Market sell
         MqlTradeRequest req; MqlTradeResult res;
         ZeroMemory(req); ZeroMemory(res);
         req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol;
         req.volume = lot; req.type = ORDER_TYPE_SELL;
         req.price = bid; req.sl = slN; req.tp = tpN;
         req.magic = InpMagic; req.deviation = DEVIATION;
         req.comment = "MST_MEDIO_SELL";
         if(!OrderSend(req, res))
         { Print("OrderSend SELL market failed. Retcode=", res.retcode); return false; }
         Print("✅ SELL market. Ticket=", res.order, " Lot=", lot, " Entry=", bid, " SL=", slN, " TP=", tpN);
         return true;
      }
   }

   // Pending order
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req); ZeroMemory(res);
   req.action    = TRADE_ACTION_PENDING;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = type;
   req.price     = entryN;
   req.sl        = slN;
   req.tp        = tpN;
   req.magic     = InpMagic;
   req.deviation = DEVIATION;
   req.comment   = isBuy ? "MST_MEDIO_BUY" : "MST_MEDIO_SELL";

   if(!OrderSend(req, res))
   {
      Print("OrderSend pending failed. Retcode=", res.retcode);
      return false;
   }
   Print("✅ Pending ", (isBuy ? "BUY" : "SELL"),
         " Ticket=", res.order, " Lot=", lot, " Entry=", entryN, " SL=", slN, " TP=", tpN);
   return true;
}

// ============================================================================
// AVERAGE BODY (for Impulse Filter)
// ============================================================================
double CalcAvgBody(int atBar, int period = 20)
{
   double sum = 0;
   int cnt = 0;
   for(int i = atBar; i < atBar + period && i < Bars(_Symbol, _Period); i++)
   {
      sum += MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i));
      cnt++;
   }
   return (cnt > 0) ? sum / cnt : 0;
}

// Convert datetime to bar shift. Returns -1 if not found.
int TimeToShift(datetime t)
{
   if(t == 0) return -1;
   return iBarShift(_Symbol, _Period, t, false);
}

// ============================================================================
// CONFIRMATION CANDLE — Close position if first candle after fill closes opposite
// Protects against entering into chop/liquidity sweeps on M15
// Only runs once per trade (until g_confirmCandlePassed = true)
// ============================================================================
void CheckConfirmCandle()
{
   if(!InpRequireConfirmCandle || g_confirmCandlePassed) return;
   if(g_beEntryPrice == 0) return;

   // Need at least 1 open position
   int posCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      posCount++;
   }
   if(posCount == 0) { g_confirmCandlePassed = true; return; }  // No position, reset

   // Count bars elapsed since entry (approximate using bar shift of entry)
   // We track bars waited by incrementing on each new bar in OnTick
   g_confirmBarsWaited++;

   if(g_confirmBarsWaited < 1) return;  // Wait at least 1 bar

   // Check last CLOSED candle (bar 1) direction vs trade direction
   double barOpen  = iOpen(_Symbol, _Period, 1);
   double barClose = iClose(_Symbol, _Period, 1);
   bool candleIsBull = (barClose > barOpen);
   bool candleIsBear = (barClose < barOpen);

   bool isConfirmed = (g_beIsBuy && candleIsBull) || (!g_beIsBuy && candleIsBear);
   bool isAgainst   = (g_beIsBuy && candleIsBear) || (!g_beIsBuy && candleIsBull);

   if(isConfirmed)
   {
      g_confirmCandlePassed = true;
      Print("[CONFIRM] ✅ Confirm candle OK — trade continues. Bar=", g_confirmBarsWaited);
      return;
   }

   if(isAgainst && g_confirmBarsWaited >= 2)
   {
      // 2 candles gone against us = close position early (anti-chop)
      Print("[CONFIRM] ⚠️ Confirm candle FAILED (", g_confirmBarsWaited, " bars against) — closing position early");
      CloseAllPositions();
      DeleteAllPendingOrders();
      g_confirmCandlePassed = true;  // Reset so we don't loop
      g_beDone = true;
      g_partialTPDone = true;
   }
}

// ============================================================================
// PARTIAL TP — Close InpPartialTPPct% of position at InpPartialTPAtR × risk
// Then move SL to entry (breakeven) to protect remaining position
// ============================================================================
void CheckPartialTP()
{
   if(!InpUsePartialTP || g_partialTPDone) return;
   if(g_beEntryPrice == 0 || g_beOrigSL == 0) return;

   double risk = MathAbs(g_beEntryPrice - g_beOrigSL);
   if(risk <= 0) return;

   double partialTarget = InpPartialTPAtR * risk;  // Price distance to trigger partial TP

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double posOpen     = PositionGetDouble(POSITION_PRICE_OPEN);
      double posVolume   = PositionGetDouble(POSITION_VOLUME);
      double currentSL   = PositionGetDouble(POSITION_SL);
      double currentTP   = PositionGetDouble(POSITION_TP);

      // Check if price reached partial TP level
      bool reachedPartial = false;
      if(g_beIsBuy)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if((bid - posOpen) >= partialTarget) reachedPartial = true;
      }
      else
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if((posOpen - ask) >= partialTarget) reachedPartial = true;
      }

      if(!reachedPartial) continue;

      // Calculate lots to close (partial %)
      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double closeLot = posVolume * (InpPartialTPPct / 100.0);
      closeLot = MathFloor(closeLot / lotStep) * lotStep;
      closeLot = MathMax(minLot, closeLot);
      if(closeLot >= posVolume) closeLot = posVolume;  // Close all if rounding

      // Partial close
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = _Symbol;
      req.volume    = NormalizeDouble(closeLot, 2);
      req.deviation = DEVIATION;
      req.magic     = InpMagic;
      req.position  = ticket;
      req.comment   = "MST_MEDIO_PARTIAL_TP";

      if(g_beIsBuy)
      { req.type = ORDER_TYPE_SELL; req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); }
      else
      { req.type = ORDER_TYPE_BUY;  req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); }

      if(!OrderSend(req, res))
      {
         Print("⚠️ Partial TP close failed. Ticket=", ticket, " Retcode=", res.retcode);
         continue;
      }

      double partialPips = partialTarget / (_Point * 10);
      Print("✅ PARTIAL TP: Closed ", NormalizeDouble(closeLot, 2), " lots at ", InpPartialTPAtR,
            "R (", NormalizeDouble(partialPips, 1), " pips) | Ticket=", ticket,
            " | Remaining=", NormalizeDouble(posVolume - closeLot, 2), " lots");

      // Move SL to breakeven OR activate trailing stop on remaining position
      if(posVolume - closeLot >= minLot)
      {
         if(InpTrailAfterPartialPts > 0)
         {
            // Trailing stop mode: activate trailing, initial SL = breakeven
            g_trailingActive = true;
            double newSL = NormalizePrice(posOpen);  // Start at BE
            if((g_beIsBuy && newSL < SymbolInfoDouble(_Symbol, SYMBOL_BID)) ||
               (!g_beIsBuy && newSL > SymbolInfoDouble(_Symbol, SYMBOL_ASK)))
            {
               MqlTradeRequest modReq; MqlTradeResult modRes;
               ZeroMemory(modReq); ZeroMemory(modRes);
               modReq.action   = TRADE_ACTION_SLTP;
               modReq.symbol   = _Symbol;
               modReq.position = ticket;
               modReq.sl       = newSL;
               modReq.tp       = currentTP;
               if(OrderSend(modReq, modRes))
                  Print("✅ SL set to BE=", newSL, " (trailing will follow). TrailPts=", InpTrailAfterPartialPts);
               else
                  Print("⚠️ Initial trail BE move failed. Retcode=", modRes.retcode);
            }
         }
         else
         {
            // Fixed BE mode (original behavior)
            double newSL = NormalizePrice(posOpen);
            if((g_beIsBuy && newSL < SymbolInfoDouble(_Symbol, SYMBOL_BID)) ||
               (!g_beIsBuy && newSL > SymbolInfoDouble(_Symbol, SYMBOL_ASK)))
            {
               MqlTradeRequest modReq; MqlTradeResult modRes;
               ZeroMemory(modReq); ZeroMemory(modRes);
               modReq.action   = TRADE_ACTION_SLTP;
               modReq.symbol   = _Symbol;
               modReq.position = ticket;
               modReq.sl       = newSL;
               modReq.tp       = currentTP;  // Keep original TP

               if(OrderSend(modReq, modRes))
                  Print("✅ SL moved to breakeven=", newSL, " after partial TP");
               else
                  Print("⚠️ BE move after partial TP failed. Retcode=", modRes.retcode);
            }
         }
      }

      g_partialTPDone = true;
      g_beDone = true;  // Also mark BE as done (partial TP already moved SL to entry)
      break;
   }
}

// ============================================================================
// TRAILING STOP — After partial TP, trail SL at InpTrailAfterPartialPts behind price
// Replaces fixed BE when InpTrailAfterPartialPts > 0
// ============================================================================
void CheckTrailingStop()
{
   if(!g_trailingActive || InpTrailAfterPartialPts <= 0) return;

   double trailDist = InpTrailAfterPartialPts * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double posOpen   = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      double newSL;
      bool   shouldMove = false;

      if(g_beIsBuy)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         newSL = NormalizePrice(bid - trailDist);
         // Only move SL forward (higher for BUY), never back, and must be above BE
         if(newSL > currentSL && newSL >= posOpen && newSL < bid)
            shouldMove = true;
      }
      else
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         newSL = NormalizePrice(ask + trailDist);
         // Only move SL forward (lower for SELL), never back, and must be below BE
         if(newSL < currentSL && newSL <= posOpen && newSL > ask)
            shouldMove = true;
      }

      if(!shouldMove) continue;

      MqlTradeRequest modReq; MqlTradeResult modRes;
      ZeroMemory(modReq); ZeroMemory(modRes);
      modReq.action   = TRADE_ACTION_SLTP;
      modReq.symbol   = _Symbol;
      modReq.position = ticket;
      modReq.sl       = newSL;
      modReq.tp       = currentTP;

      if(OrderSend(modReq, modRes))
      {
         double profitPts = g_beIsBuy
            ? (newSL - posOpen) / _Point
            : (posOpen - newSL) / _Point;
         Print("[TRAIL] ✅ Trailing SL moved to ", newSL,
               " (", NormalizeDouble(profitPts, 0), " pts profit locked)");
      }
      else
         Print("[TRAIL] ⚠️ Trail SL move failed. Retcode=", modRes.retcode);
   }
}

// ============================================================================
// BREAKEVEN TRAILING — Move SL to entry when profit >= InpBEAtR × risk
// ============================================================================
void CheckBreakevenMove()
{
   if(g_beDone || InpBEAtR <= 0) return;
   if(g_beEntryPrice == 0 || g_beOrigSL == 0) return;

   double risk = MathAbs(g_beEntryPrice - g_beOrigSL);
   if(risk <= 0) return;

   double beTarget = InpBEAtR * risk;  // Distance needed for BE move

   // Check all our positions
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      // Check if profit reached BE threshold
      bool reachedBE = false;
      if(g_beIsBuy)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if((bid - posOpen) >= beTarget)
            reachedBE = true;
      }
      else
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if((posOpen - ask) >= beTarget)
            reachedBE = true;
      }

      if(!reachedBE) continue;

      // Move SL to entry (breakeven)
      double newSL = NormalizePrice(posOpen);
      if(MathAbs(currentSL - newSL) <= _Point) continue;  // Already at BE

      // Validate: BUY SL must be below current price, SELL SL above
      if(g_beIsBuy && newSL >= SymbolInfoDouble(_Symbol, SYMBOL_BID)) continue;
      if(!g_beIsBuy && newSL <= SymbolInfoDouble(_Symbol, SYMBOL_ASK)) continue;

      MqlTradeRequest modReq; MqlTradeResult modRes;
      ZeroMemory(modReq); ZeroMemory(modRes);
      modReq.action   = TRADE_ACTION_SLTP;
      modReq.symbol   = _Symbol;
      modReq.position = ticket;
      modReq.sl       = newSL;
      modReq.tp       = currentTP;  // Keep existing TP

      if(!OrderSend(modReq, modRes))
      {
         Print("⚠️ BE move failed. Ticket=", ticket, " Retcode=", modRes.retcode);
         return;  // Retry next tick
      }
      Print("✅ BREAKEVEN: SL moved to entry=", newSL,
            " | Profit was >= ", InpBEAtR, "R | Ticket=", ticket);
   }

   g_beDone = true;  // All positions moved to BE
}

// ============================================================================
// INIT / DEINIT
// ============================================================================
int OnInit()
{
   string number = StringFormat("%I64d", GetTickCount64());
   g_objPrefix = StringSubstr(number, MathMax(0, StringLen(number) - 4)) + "_MSM_";

   // Initialize daily loss tracking — use balance only (realized P/L)
   g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   MqlDateTime dt;
   TimeCurrent(dt);
   g_lastTradingDay = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   g_dailyTradingPaused = false;

   // ── Create indicator handles (cached for entire EA lifetime) ──
   // ATR handle
   if(InpUseATRSL)
   {
      g_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
      if(g_atrHandle == INVALID_HANDLE)
         Print("⚠️ Failed to create ATR handle");
   }
   
   // EMA handles for trend filter (current timeframe)
   if(InpUseTrendFilter)
   {
      g_emaFastHandle = iMA(_Symbol, _Period, InpEMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      g_emaSlowHandle = iMA(_Symbol, _Period, InpEMASlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_emaFastHandle == INVALID_HANDLE || g_emaSlowHandle == INVALID_HANDLE)
         Print("⚠️ Failed to create EMA handles for trend filter");
   }
   
   // HTF EMA handles
   if(InpUseHTFFilter)
   {
      g_htfEmaFastHandle = iMA(_Symbol, InpHTFTimeframe, InpEMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      g_htfEmaSlowHandle = iMA(_Symbol, InpHTFTimeframe, InpEMASlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_htfEmaFastHandle == INVALID_HANDLE || g_htfEmaSlowHandle == INVALID_HANDLE)
         Print("⚠️ Failed to create HTF EMA handles");
   }

   Print("ℹ️ Strategy:",
         " PivotLen=", InpPivotLen, " BreakMult=", InpBreakMult,
         " ImpulseMult=", InpImpulseMult, " TP_RR=", InpTPFixedRR,
         " BE@R=", InpBEAtR, " SLBuf=", InpSLBufferPct, "%",
         " MinSLDist=", InpMinSLDistPts, "pts");
   Print("💰 Risk Management:", 
         " DynamicLot=", (InpUseDynamicLot ? "ON" : "OFF"),
         " | FixedLot=", InpLotSize, 
         " | RiskPct=", InpRiskPct, "%",
         " | MaxRisk=", InpMaxRiskPct, "%",
         " | MaxDailyLoss=", InpMaxDailyLossPct, "%",
         " | MaxSLRisk=", InpMaxSLRiskPct, "%");
   Print("📊 SL System:",
         " ATR-based=", (InpUseATRSL ? "ON" : "OFF"),
         " | ATRMultiplier=", InpATRMultiplier,
         " | ATRPeriod=", InpATRPeriod,
         " | SLBuffer=", InpSLBufferPct, "%");
   Print("📈 Trend Filter:",
         " EMA=", (InpUseTrendFilter ? "ON" : "OFF"),
         " | Fast=", InpEMAFastPeriod,
         " | Slow=", InpEMASlowPeriod,
         " | HTF=", (InpUseHTFFilter ? "ON" : "OFF"),
         " | HTF_TF=", EnumToString(InpHTFTimeframe));

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteObjectsByPrefix(g_objPrefix);
   // Release all indicator handles
   if(g_atrHandle != INVALID_HANDLE) { IndicatorRelease(g_atrHandle); g_atrHandle = INVALID_HANDLE; }
   if(g_emaFastHandle != INVALID_HANDLE) { IndicatorRelease(g_emaFastHandle); g_emaFastHandle = INVALID_HANDLE; }
   if(g_emaSlowHandle != INVALID_HANDLE) { IndicatorRelease(g_emaSlowHandle); g_emaSlowHandle = INVALID_HANDLE; }
   if(g_htfEmaFastHandle != INVALID_HANDLE) { IndicatorRelease(g_htfEmaFastHandle); g_htfEmaFastHandle = INVALID_HANDLE; }
   if(g_htfEmaSlowHandle != INVALID_HANDLE) { IndicatorRelease(g_htfEmaSlowHandle); g_htfEmaSlowHandle = INVALID_HANDLE; }
}

// OnTradeTransaction removed — daily loss is checked via OnTick using balance only.
// This allows positions to run to TP/SL instead of being killed instantly on fill.

// ============================================================================
// MAIN TICK HANDLER
// ============================================================================
void OnTick()
{
   // ── Daily Loss Reset: check if new trading day ──
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
      if(today != g_lastTradingDay)
      {
         g_lastTradingDay = today;
         // Use balance only (realized P/L) for daily loss tracking
         g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         if(g_dailyTradingPaused)
         {
            g_dailyTradingPaused = false;
            Print("ℹ️ New trading day — Daily loss reset. StartBalance=$",
                  NormalizeDouble(g_dailyStartBalance, 2));
         }
      }
   }

   // ── Daily Loss Check: skip all trading if limit hit ──
   // (still allow breakeven and visual updates for existing positions)
   bool dailyLossHit = !CheckDailyLoss();

   // Extend lines on every tick
   if(SHOW_VISUAL && SHOW_BREAK_LINE)
      ExtendActiveLines();

   // ── Partial TP: Close partial lot at InpPartialTPAtR × risk ──
   if(InpUsePartialTP && !g_partialTPDone)
      CheckPartialTP();

   // ── Trailing Stop: trail SL after partial TP if enabled ──
   if(g_trailingActive && InpTrailAfterPartialPts > 0)
      CheckTrailingStop();

   // ── Breakeven: Move SL to entry when profit >= BE_AT_R × risk ──
   if(!g_beDone && InpBEAtR > 0)
      CheckBreakevenMove();

   // If daily loss limit hit, stop placing new orders (but let existing positions run)
   if(dailyLossHit)
   {
      // Only delete pending orders (unfilled) — let open positions hit TP/SL naturally
      DeleteAllPendingOrders();
      return;
   }

   // Only process on new bar
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == g_lastBarTime) return;
   g_lastBarTime = currentBarTime;

   // ── Confirm Candle: close position if first bars close against direction ──
   if(InpRequireConfirmCandle && !g_confirmCandlePassed)
      CheckConfirmCandle();

   int bars = Bars(_Symbol, _Period);
   if(bars < InpPivotLen * 2 + 25) return;  // Need enough bars for avg body

   // ================================================================
   // STEP 1: SWING DETECTION (at bar = PIVOT_LEN, the confirmed pivot)
   // ================================================================
   int checkBar = InpPivotLen;
   bool isSwH = IsPivotHigh(checkBar, InpPivotLen);
   bool isSwL = IsPivotLow(checkBar, InpPivotLen);

   datetime checkTime = iTime(_Symbol, _Period, checkBar);
   double   checkHigh = iHigh(_Symbol, _Period, checkBar);
   double   checkLow  = iLow(_Symbol, _Period, checkBar);

   // Update Swing Low first (same order as Pine Script)
   if(isSwL)
   {
      g_sl0 = g_sl1;       g_sl0_time = g_sl1_time;
      g_sl1 = checkLow;    g_sl1_time = checkTime;
   }

   // Update Swing High
   if(isSwH)
   {
      g_slBeforeSH = g_sl1;       g_slBeforeSH_time = g_sl1_time;
      g_sh0 = g_sh1;       g_sh0_time = g_sh1_time;
      g_sh1 = checkHigh;   g_sh1_time = checkTime;
   }

   // Update shBeforeSL
   if(isSwL)
   {
      g_shBeforeSL = g_sh1;       g_shBeforeSL_time = g_sh1_time;
   }

   // Visual: Swing markers
   if(SHOW_VISUAL && SHOW_SWINGS)
   {
      if(isSwH)
      {
         double pad = (checkHigh - checkLow) * 0.3;
         if(pad < _Point * 5) pad = _Point * 5;
         string name = g_objPrefix + "SWH_" + IntegerToString((long)checkTime);
         DrawArrowIcon(name, checkTime, checkHigh + pad, 234, COL_SWING_HIGH, 1);
      }
      if(isSwL)
      {
         double pad = (checkHigh - checkLow) * 0.3;
         if(pad < _Point * 5) pad = _Point * 5;
         string name = g_objPrefix + "SWL_" + IntegerToString((long)checkTime);
         DrawArrowIcon(name, checkTime, checkLow - pad, 233, COL_SWING_LOW, 1);
      }
   }

   // ================================================================
   // STEP 2: HH/LL DETECTION + IMPULSE FILTER
   // ================================================================
   bool isNewHH = isSwH && g_sh0 != EMPTY_VALUE && g_sh1 > g_sh0;
   bool isNewLL = isSwL && g_sl0 != EMPTY_VALUE && g_sl1 < g_sl0;

   // Impulse Body Filter
   if(isNewHH && InpImpulseMult > 0)
   {
      double avgBody = CalcAvgBody(1, 20);
      int sh0Shift = TimeToShift(g_sh0_time);
      int toBar    = InpPivotLen;  // sh1 position
      bool found   = false;
      if(sh0Shift >= 0)
      {
         for(int i = sh0Shift; i >= toBar; i--)
         {
            if(i < 0) continue;
            if(iClose(_Symbol, _Period, i) > g_sh0)
            {
               double body = MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i));
               found = (body >= InpImpulseMult * avgBody);
               break;
            }
         }
      }
      if(!found) isNewHH = false;
   }

   if(isNewLL && InpImpulseMult > 0)
   {
      double avgBody = CalcAvgBody(1, 20);
      int sl0Shift = TimeToShift(g_sl0_time);
      int toBar    = InpPivotLen;
      bool found   = false;
      if(sl0Shift >= 0)
      {
         for(int i = sl0Shift; i >= toBar; i--)
         {
            if(i < 0) continue;
            if(iClose(_Symbol, _Period, i) < g_sl0)
            {
               double body = MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i));
               found = (body >= InpImpulseMult * avgBody);
               break;
            }
         }
      }
      if(!found) isNewLL = false;
   }

   // Break Strength Filter
   bool rawBreakUp  = false;
   bool rawBreakDown = false;

   if(isNewHH && g_slBeforeSH != EMPTY_VALUE)
   {
      if(InpBreakMult <= 0)
         rawBreakUp = true;
      else
      {
         double swR = g_sh0 - g_slBeforeSH;
         double brD = g_sh1 - g_sh0;
         if(swR > 0 && brD >= swR * InpBreakMult)
            rawBreakUp = true;
      }
   }

   if(isNewLL && g_shBeforeSL != EMPTY_VALUE)
   {
      if(InpBreakMult <= 0)
         rawBreakDown = true;
      else
      {
         double swR = g_shBeforeSL - g_sl0;
         double brD = g_sl0 - g_sl1;
         if(swR > 0 && brD >= swR * InpBreakMult)
            rawBreakDown = true;
      }
   }

   // ================================================================
   // STEP 3: 2-STEP CONFIRMATION STATE MACHINE
   // ================================================================
   bool confirmedBuy  = false;
   bool confirmedSell = false;
   double confEntry = 0, confSL = 0, confW1Peak = 0;
   datetime confEntryTime = 0, confSLTime = 0;
   datetime confWaveTime = 0;
   double confWaveHigh = 0, confWaveLow = 0;

   // Read bar 1 (previous completed bar) for state checks
   double prevHigh  = iHigh(_Symbol, _Period, 1);
   double prevLow   = iLow(_Symbol, _Period, 1);
   double prevClose = iClose(_Symbol, _Period, 1);
   double prevOpen  = iOpen(_Symbol, _Period, 1);

   // -- Post-signal Entry touch → terminate lines (Pine: lines 214-221) --
   if(g_hasActiveLine && g_activeEntryPrice != EMPTY_VALUE)
   {
      bool touchEntry = false;
      if(g_activeIsBuy && prevLow <= g_activeEntryPrice)  touchEntry = true;
      if(!g_activeIsBuy && prevHigh >= g_activeEntryPrice) touchEntry = true;
      if(touchEntry)
      {
         TerminateActiveLines(iTime(_Symbol, _Period, 1));
         ClearActiveLines();
      }
   }

   // -- Wait for Confirm: CLOSE beyond W1 Peak --
   if(g_pendingState == 1)
   {
      // Track W1 trough
      if(g_pendW1Trough == EMPTY_VALUE || prevLow < g_pendW1Trough)
         g_pendW1Trough = prevLow;
      // SL check
      if(g_pendSL != EMPTY_VALUE && prevLow <= g_pendSL)
      {
         Print("ℹ️ Pending BUY cancelled: Price hit SL=", g_pendSL, " | Low=", prevLow);
         g_pendingState = 0;
      }
      // Entry touch cancel
      else if(g_pendBreakPoint != EMPTY_VALUE && prevLow <= g_pendBreakPoint)
      {
         Print("ℹ️ Pending BUY cancelled: Price touched Entry=", g_pendBreakPoint, " | Low=", prevLow);
         g_pendingState = 0;
      }
      // Confirm: close > W1 peak
      else if(g_pendW1Peak != EMPTY_VALUE && prevClose > g_pendW1Peak)
      {
         // Confirmed BUY! Signal fires immediately.
         confirmedBuy  = true;
         confEntry     = g_pendBreakPoint;
         confSL        = g_pendSL;
         confW1Peak    = g_pendW1Peak;
         confEntryTime = g_pendBreak_time;
         confSLTime    = g_pendSL_time;
         confWaveTime  = iTime(_Symbol, _Period, 1);
         confWaveHigh  = prevHigh;
         confWaveLow   = prevLow;
         g_pendingState = 0;
      }
   }

   if(g_pendingState == -1)
   {
      if(g_pendW1Trough == EMPTY_VALUE || prevHigh > g_pendW1Trough)
         g_pendW1Trough = prevHigh;
      if(g_pendSL != EMPTY_VALUE && prevHigh >= g_pendSL)
      {
         Print("ℹ️ Pending SELL cancelled: Price hit SL=", g_pendSL, " | High=", prevHigh);
         g_pendingState = 0;
      }
      else if(g_pendBreakPoint != EMPTY_VALUE && prevHigh >= g_pendBreakPoint)
      {
         Print("ℹ️ Pending SELL cancelled: Price touched Entry=", g_pendBreakPoint, " | High=", prevHigh);
         g_pendingState = 0;
      }
      else if(g_pendW1Peak != EMPTY_VALUE && prevClose < g_pendW1Peak)
      {
         // Confirmed SELL! Signal fires immediately.
         confirmedSell = true;
         confEntry     = g_pendBreakPoint;
         confSL        = g_pendSL;
         confW1Peak    = g_pendW1Peak;
         confEntryTime = g_pendBreak_time;
         confSLTime    = g_pendSL_time;
         confWaveTime  = iTime(_Symbol, _Period, 1);
         confWaveHigh  = prevHigh;
         confWaveLow   = prevLow;
         g_pendingState = 0;
      }
   }

   // ================================================================
   // STEP 4: NEW RAW BREAK → Start tracking W1 Peak + Phase 1
   // ================================================================
   if(rawBreakUp)
   {
      // Terminate old lines
      if(SHOW_VISUAL && SHOW_BREAK_LINE)
      { TerminateActiveLines(checkTime); ClearActiveLines(); }

      // --- Find W1 Peak: highest high from break candle until first bearish ---
      double w1Peak      = EMPTY_VALUE;
      int    w1BarShift  = -1;      // shift of W1 peak bar
      double w1TroughInit = EMPTY_VALUE;
      bool   foundBreak  = false;

      // Scan from sh0 toward current bar (decreasing shift = forward in time)
      int sh0Shift = TimeToShift(g_sh0_time);
      if(sh0Shift >= 0)
      {
         for(int i = sh0Shift; i >= 1; i--)  // Skip bar 0 (incomplete)
         {
            double cl = iClose(_Symbol, _Period, i);
            double op = iOpen(_Symbol, _Period, i);
            double hi = iHigh(_Symbol, _Period, i);
            double lo = iLow(_Symbol, _Period, i);

            if(!foundBreak)
            {
               if(cl > g_sh0)
               {
                  foundBreak  = true;
                  w1Peak      = hi;
                  w1BarShift  = i;
                  w1TroughInit = lo;
               }
            }
            else
            {
               if(hi > w1Peak) { w1Peak = hi; w1BarShift = i; }
               if(w1TroughInit == EMPTY_VALUE || lo < w1TroughInit) w1TroughInit = lo;
               if(cl < op) break;  // First bearish candle → end of W1 impulse
            }
         }
      }

      if(w1Peak != EMPTY_VALUE)
      {
         g_pendingState    = 1;
         g_pendBreakPoint  = g_sh0;         // Entry level
         g_pendW1Peak      = w1Peak;
         g_pendW1Trough    = w1TroughInit;
         g_pendSL          = g_slBeforeSH;
         g_pendSL_time     = g_slBeforeSH_time;
         g_pendBreak_time  = g_sh0_time;

         Print("ℹ️ Pending BUY: Break above SH0=", g_sh0,
               " | W1Peak=", w1Peak, " | SL=", g_slBeforeSH,
               " | Waiting close > ", w1Peak);

         // Retroactive scan: from w1_bar+1 to bar 1 (skip bar 0 — incomplete)
         int retroFrom = w1BarShift - 1;
         if(retroFrom < 1) retroFrom = 1;
         for(int i = retroFrom; i >= 1; i--)
         {
            double rH = iHigh(_Symbol, _Period, i);
            double rL = iLow(_Symbol, _Period, i);
            double rC = iClose(_Symbol, _Period, i);

            if(g_pendingState == 1)
            {
               if(g_pendW1Trough == EMPTY_VALUE || rL < g_pendW1Trough)
                  g_pendW1Trough = rL;
               if(g_pendSL != EMPTY_VALUE && rL <= g_pendSL)
               { Print("ℹ️ Pending BUY cancelled (retro): SL hit"); g_pendingState = 0; break; }
               if(rL <= g_pendBreakPoint)
               { Print("ℹ️ Pending BUY cancelled (retro): Entry touched"); g_pendingState = 0; break; }
               if(rC > g_pendW1Peak)
               {
                  // Confirmed BUY (retro scan)
                  confirmedBuy  = true;
                  confEntry     = g_pendBreakPoint;
                  confSL        = g_pendSL;
                  confW1Peak    = g_pendW1Peak;
                  confEntryTime = g_pendBreak_time;
                  confSLTime    = g_pendSL_time;
                  confWaveTime  = iTime(_Symbol, _Period, i);
                  confWaveHigh  = rH;
                  confWaveLow   = rL;
                  g_pendingState = 0;
                  break;
               }
            }
            if(g_pendingState == 0) break;
         }
      }
   }

   // rawBreakDown
   if(rawBreakDown)
   {
      if(SHOW_VISUAL && SHOW_BREAK_LINE)
      { TerminateActiveLines(checkTime); ClearActiveLines(); }

      double w1Trough    = EMPTY_VALUE;
      int    w1BarShift  = -1;
      double w1PeakInit  = EMPTY_VALUE;  // highest high during W1 (for W1Trough tracking in SELL)
      bool   foundBreak  = false;

      int sl0Shift = TimeToShift(g_sl0_time);
      if(sl0Shift >= 0)
      {
         for(int i = sl0Shift; i >= 1; i--)  // Skip bar 0 (incomplete)
         {
            double cl = iClose(_Symbol, _Period, i);
            double op = iOpen(_Symbol, _Period, i);
            double lo = iLow(_Symbol, _Period, i);
            double hi = iHigh(_Symbol, _Period, i);

            if(!foundBreak)
            {
               if(cl < g_sl0)
               {
                  foundBreak  = true;
                  w1Trough    = lo;
                  w1BarShift  = i;
                  w1PeakInit  = hi;
               }
            }
            else
            {
               if(lo < w1Trough) { w1Trough = lo; w1BarShift = i; }
               if(w1PeakInit == EMPTY_VALUE || hi > w1PeakInit) w1PeakInit = hi;
               if(cl > op) break;  // First bullish candle → end of W1 impulse
            }
         }
      }

      if(w1Trough != EMPTY_VALUE)
      {
         g_pendingState    = -1;
         g_pendBreakPoint  = g_sl0;         // Entry level
         g_pendW1Peak      = w1Trough;       // W1 trough = confirm level for SELL
         g_pendW1Trough    = w1PeakInit;     // Highest high during W1 (invalidation)
         g_pendSL          = g_shBeforeSL;
         g_pendSL_time     = g_shBeforeSL_time;
         g_pendBreak_time  = g_sl0_time;

         Print("ℹ️ Pending SELL: Break below SL0=", g_sl0,
               " | W1Trough=", w1Trough, " | SL=", g_shBeforeSL,
               " | Waiting close < ", w1Trough);

         int retroFrom = w1BarShift - 1;
         if(retroFrom < 1) retroFrom = 1;
         for(int i = retroFrom; i >= 1; i--)
         {
            double rH = iHigh(_Symbol, _Period, i);
            double rL = iLow(_Symbol, _Period, i);
            double rC = iClose(_Symbol, _Period, i);

            if(g_pendingState == -1)
            {
               if(g_pendW1Trough == EMPTY_VALUE || rH > g_pendW1Trough)
                  g_pendW1Trough = rH;
               if(g_pendSL != EMPTY_VALUE && rH >= g_pendSL)
               { Print("ℹ️ Pending SELL cancelled (retro): SL hit"); g_pendingState = 0; break; }
               if(rH >= g_pendBreakPoint)
               { Print("ℹ️ Pending SELL cancelled (retro): Entry touched"); g_pendingState = 0; break; }
               if(rC < g_pendW1Peak)
               {
                  // Confirmed SELL (retro scan)
                  confirmedSell = true;
                  confEntry     = g_pendBreakPoint;
                  confSL        = g_pendSL;
                  confW1Peak    = g_pendW1Peak;
                  confEntryTime = g_pendBreak_time;
                  confSLTime    = g_pendSL_time;
                  confWaveTime  = iTime(_Symbol, _Period, i);
                  confWaveHigh  = rH;
                  confWaveLow   = rL;
                  g_pendingState = 0;
                  break;
               }
            }
            if(g_pendingState == 0) break;
         }
      }
   }

   // ================================================================
   // STEP 5: PROCESS CONFIRMED SIGNALS
   // ================================================================
   if(confirmedBuy)
      ProcessConfirmedSignal(true, confEntry, confSL, confW1Peak,
                              confEntryTime, confSLTime, confWaveTime,
                              confWaveHigh, confWaveLow);

   else if(confirmedSell)
      ProcessConfirmedSignal(false, confEntry, confSL, confW1Peak,
                              confEntryTime, confSLTime, confWaveTime,
                              confWaveHigh, confWaveLow);
}

// ============================================================================
// PROCESS CONFIRMED SIGNAL
// ============================================================================
void ProcessConfirmedSignal(bool isBuy, double entry, double sl, double w1Peak,
                             datetime entryTime, datetime slTime, datetime waveTime,
                             double waveHigh, double waveLow)
{
   g_breakCount++;
   string suffix = IntegerToString(g_breakCount);

   // ── TREND FILTER: Only trade in direction of the trend ──
   if(InpUseTrendFilter)
   {
      if(!IsTrendAligned(isBuy))
      {
         int trend = GetTrendDirection();
         Print("🚫 TREND FILTER: ", (isBuy ? "BUY" : "SELL"), " blocked. ",
               "Trend=", (trend == +1 ? "UP" : (trend == -1 ? "DOWN" : "NONE/CONFLICT")),
               " | Signal=", (isBuy ? "BUY" : "SELL"));
         return;
      }
   }

   // ── Apply Entry Offset: shift limit entry deeper vs exact swing level ──
   // This avoids placing limit at exact SH/SL level (liquidity sweet spot / stop hunt zone)
   // For SELL: entry shifts UP (further from SL) → fills slightly above swing high
   // For BUY:  entry shifts DOWN (further from SL) → fills slightly below swing low
   double entryFinal = entry;
   if(InpEntryOffsetPts > 0)
   {
      double offsetDist = InpEntryOffsetPts * _Point;
      entryFinal = isBuy ? entry - offsetDist : entry + offsetDist;
      entryFinal = NormalizePrice(entryFinal);
   }

   // ── Determine FINAL SL: ATR-based or swing-based ──
   // This MUST be done BEFORE TP calculation to ensure consistent RR
   double finalSL = sl;
   if(InpUseATRSL)
   {
      double atrSL = CalculateATRSL(isBuy, entry);
      if(atrSL > 0)
      {
         finalSL = atrSL;
         Print("🔧 Using ATR-based SL: Swing=", sl, " → ATR=", finalSL);
      }
      else
      {
         Print("⚠️ ATR SL failed - using swing-based SL: ", sl);
      }
   }

   // Apply SL buffer
   double slBuffered = finalSL;
   double riskDist = MathAbs(entryFinal - finalSL);
   if(InpSLBufferPct > 0 && riskDist > 0)
   {
      double bufferAmt = riskDist * InpSLBufferPct / 100.0;
      if(isBuy)  slBuffered = finalSL - bufferAmt;
      else       slBuffered = finalSL + bufferAmt;
      riskDist = MathAbs(entryFinal - slBuffered);
   }

   // ── SIGNAL QUALITY: Skip tiny swings (noise filter) ──
   if(InpMinSLDistPts > 0)
   {
      double minDist = InpMinSLDistPts * _Point;
      if(riskDist < minDist)
      {
         double slPips = riskDist / (_Point * 10);
         double minPips = minDist / (_Point * 10);
         Print("🚫 SKIP TINY SWING: SL distance=", NormalizeDouble(slPips, 1),
               " pips < Min=", NormalizeDouble(minPips, 1), " pips",
               " | Entry=", entryFinal, " SL=", slBuffered);
         return;
      }
   }

   // ── Calculate TP from FINAL SL distance (consistent RR) ──
   double tp;
   if(InpTPFixedRR > 0)
   {
      // Fixed RR TP based on FINAL SL distance = TRUE 1:1.5 RR etc
      if(isBuy)  tp = entryFinal + InpTPFixedRR * riskDist;
      else       tp = entryFinal - InpTPFixedRR * riskDist;
   }
   else
   {
      // Confirm Break TP: high/low of confirm break candle
      tp = isBuy ? waveHigh : waveLow;
   }

   Print("📐 CONSISTENT RR: Entry=", entryFinal, " SL=", slBuffered, " TP=", tp,
         " | RiskDist=", NormalizeDouble(riskDist, 2),
         " | Actual RR=1:", NormalizeDouble(MathAbs(tp - entryFinal) / riskDist, 2));

   datetime signalTime = iTime(_Symbol, _Period, 1);  // Signal detected on bar 1

   // ── Dedup: only fire once per signal bar ──
   datetime lastSig = isBuy ? g_lastBuySignal : g_lastSellSignal;
   if(signalTime <= lastSig) return;  // Already processed this signal
   if(isBuy) g_lastBuySignal = signalTime;
   else      g_lastSellSignal = signalTime;

   // ── Visual ──
   if(SHOW_VISUAL)
   {
      if(SHOW_BREAK_LINE)
      {
         TerminateActiveLines(signalTime);

         // Create new lines (static — don't extend, same as Pine Script)
         datetime now = signalTime;
         string entName = g_objPrefix + "ENT_" + suffix;
         string slName  = g_objPrefix + "SL_"  + suffix;
         DrawHLine(entName, entryTime, entryFinal, now,
                   isBuy ? COL_ENTRY_BUY : COL_ENTRY_SELL, STYLE_DASH, 1);
         DrawHLine(slName, slTime, slBuffered, now,
                   COL_SL, STYLE_DASH, 1);

         // Labels
         string entLbl = g_objPrefix + "ENTLBL_" + suffix;
         string slLbl  = g_objPrefix + "SLLBL_"  + suffix;
         DrawTextLabel(entLbl, now, entryFinal,
                       isBuy ? "Entry Buy" : "Entry Sell",
                       isBuy ? COL_ENTRY_BUY : COL_ENTRY_SELL, 7);
         DrawTextLabel(slLbl, now, slBuffered, "SL", COL_SL, 7);

         // TP line
         if(tp > 0)
         {
            string tpName = g_objPrefix + "TP_" + suffix;
            string tpLbl  = g_objPrefix + "TPLBL_" + suffix;
            DrawHLine(tpName, entryTime, tp, now, COL_TP, STYLE_DASH, 1);
            string tpText = (InpTPFixedRR > 0)
               ? StringFormat("TP (%.1fR)", InpTPFixedRR)
               : "TP (Conf)";
            DrawTextLabel(tpLbl, now, tp, tpText, COL_TP, 7);
         }

         // Lines are static (don't extend), like Pine Script
         ClearActiveLines();
      }

      if(SHOW_BREAK_LABEL)
      {
         string lblName = g_objPrefix + (isBuy ? "CONF_UP_" : "CONF_DN_") + suffix;
         if(isBuy)
            DrawTextLabel(lblName, waveTime, waveHigh,
                          "▲ Confirm Break", COL_BREAK_UP, 9);
         else
            DrawTextLabel(lblName, waveTime, waveLow,
                          "▼ Confirm Break", COL_BREAK_DOWN, 9);
      }
   }

   // ── Alert ──
   {
      string msg = StringFormat("MST Medio: %s | Entry=%.2f SL=%.2f TP=%.2f | %s",
                                 isBuy ? "BUY" : "SELL",
                                 entryFinal, slBuffered, tp, _Symbol);
      Alert(msg);
      Print("🔔 ", msg);
   }

   // ── Trade ──
   {
      // Cancel pending orders (not yet filled)
      DeleteAllPendingOrders();

      // Smart flip: if InpSmartFlip=true and current position already passed partial TP
      // (SL is at BE or trailing), keep it running — don't close it for a new signal
      // Otherwise: close all existing positions to flip direction
      bool hasProtectedPos = false;
      if(InpSmartFlip && g_partialTPDone)
      {
         // Check if any position is still open and at-or-above BE
         for(int pi = PositionsTotal() - 1; pi >= 0; pi--)
         {
            ulong t = PositionGetTicket(pi);
            if(t == 0) continue;
            if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
            if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit >= 0)  // Position at BE or in profit
            {
               hasProtectedPos = true;
               Print("[SmartFlip] Keeping profitable position Ticket=", t,
                     " P&L=", NormalizeDouble(profit, 2), " while placing new signal");
               break;
            }
         }
      }

      if(!hasProtectedPos)
      {
         // Close all existing positions to flip/reset
         CloseAllPositions();
         // Reset breakeven state for new trade
         g_beDone       = false;
         g_partialTPDone = false;
         g_trailingActive = false;
         g_confirmCandlePassed = false;
         g_confirmBarsWaited   = 0;
         g_beEntryPrice = entryFinal;
         g_beOrigSL     = slBuffered;
         g_beIsBuy      = isBuy;
      }
      else
      {
         // Keep the protected position; reset state for new trade tracking
         g_beDone       = false;
         g_partialTPDone = false;
         g_trailingActive = false;
         g_confirmCandlePassed = false;
         g_confirmBarsWaited   = 0;
         g_beEntryPrice = entryFinal;
         g_beOrigSL     = slBuffered;
         g_beIsBuy      = isBuy;
         Print("[SmartFlip] Placing new order alongside protected position");
      }

      // Pre-check: don't place order if equity already near daily loss limit
      if(InpMaxDailyLossPct > 0 && g_dailyStartBalance > 0)
      {
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         double currentLossPct = (g_dailyStartBalance - equity) / g_dailyStartBalance * 100.0;
         double remainingPct = InpMaxDailyLossPct - currentLossPct;
         if(remainingPct < 1.0)  // Less than 1% room left before daily limit
         {
            Print("⚠️ SKIP TRADE: Equity too close to daily loss limit. ",
                  "CurrentLoss=", NormalizeDouble(currentLossPct, 2),
                  "% | Remaining=", NormalizeDouble(remainingPct, 2), "%");
            return;
         }
      }

      // Place order — PlaceOrder now uses the SAME final SL for lot sizing
      // No more double calculation: SL/TP/Lot are all consistent
      PlaceOrder(isBuy, entryFinal, slBuffered, tp);
   }
}
//+------------------------------------------------------------------+
