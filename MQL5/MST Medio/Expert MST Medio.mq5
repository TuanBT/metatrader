//+------------------------------------------------------------------+
//| Expert MST Medio.mq5                                            |
//| MST Medio (Make Simple Trading by Medio)                        |
//| EA — 2-Step Breakout Confirmation System                        |
//| Synced with TradingView Pine Script MST Medio v2.0               |
//|                                                                  |
//| Logic:                                                           |
//|   1. Detect HH/LL breakout (with impulse body filter)            |
//|   2. Find W1 Peak (first impulse wave extreme after break)       |
//|   3. Wait for CLOSE beyond W1 Peak → Confirmed! → Signal         |
//|   4. Entry = old SH/SL, SL = swing opposite                     |
//|   5. TP = Fixed RR (3R) or Confirm Break candle H/L              |
//|   6. SL buffer = auto % of risk distance (disabled)              |
//|   7. Max risk % safety filter (skip trade if risk > limit)       |
//|   8. Auto lot normalization (min/max/step)                       |
//|   9. On new signal: close all existing positions → open new      |
//|  10. HTF Trend Filter: H1 EMA50 — BUY above, SELL below         |
//|  11. Breakeven: move SL to entry when profit >= BE_AT_R × risk   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MTS"
#property link      ""
#property version   "3.00"
#property strict

// ============================================================================
// STRATEGY PRESETS
// ============================================================================
enum ENUM_STRATEGY_PRESET
{
   PRESET_V3_OPTIMAL  = 0,  // V3 Optimal (P3 B0 I1.0 FR3R BE@0.5R) +205R
   PRESET_V3_SAFE     = 1,  // V3 Safe (P3 B0.25 I1.5 Confirm) +163R
   PRESET_V2_ORIGINAL = 2,  // V2 Original (P5 B0.25 I1.75 Confirm) +107R
   PRESET_CUSTOM      = 3,  // Custom (use manual inputs below)
};

// ============================================================================
// INPUTS
// ============================================================================
input ENUM_STRATEGY_PRESET InpPreset = PRESET_V3_OPTIMAL; // Strategy Preset
input double InpMaxRiskPct   = 0;       // Max Risk % per trade (0=no limit)
input double InpLotSize      = 0.01;    // Lot Size
input bool   InpShowVisual   = false;   // Show indicator on chart
input ulong  InpMagic        = 20260210;// Magic Number

// -- Custom preset inputs (only used when Preset = Custom) --
input int    InpPivotLen     = 3;       // [Custom] Pivot Length
input double InpBreakMult    = 0;       // [Custom] Break Multiplier
input double InpImpulseMult  = 1.0;     // [Custom] Impulse Multiplier
input double InpTPFixedRR    = 3.0;     // [Custom] TP Fixed RR (0=confirm candle)
input double InpBEAtR        = 0.5;     // [Custom] Breakeven at R (0=disabled)
input int    InpSLBufferPct  = 0;       // [Custom] SL Buffer % (0=disabled)

// ============================================================================
// STRATEGY PARAMETERS (set in OnInit from preset)
// ============================================================================
int    g_pivotLen     = 3;
double g_breakMult    = 0;
double g_impulseMult  = 1.0;
double g_tpFixedRR    = 3.0;
double g_beAtR        = 0.5;
int    g_slBufferPct  = 0;

// ============================================================================
// FIXED SETTINGS
// ============================================================================
#define DEVIATION        20

// HTF Trend Filter (Higher Timeframe)
#define HTF_PERIOD       PERIOD_H1    // Higher timeframe for trend
#define HTF_EMA_LEN      50           // EMA period on HTF
#define HTF_FILTER       false        // Enable/disable HTF filter
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
static datetime g_lastSellSignal = 0;

// -- Breakeven tracking --
static bool   g_beDone          = false;  // Has BE been moved for current trade?
static double g_beEntryPrice    = 0;      // Entry price for BE calculation
static double g_beOrigSL        = 0;      // Original SL price (for risk distance)
static bool   g_beIsBuy         = false;  // Direction of position

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

// -- HTF Trend Filter --
static int g_htfEmaHandle = INVALID_HANDLE;

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================
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

// Check if trade risk exceeds max allowed risk %
// Returns true if trade is safe, false if risk too high (skip trade)
bool CheckMaxRisk(const double entry, const double sl, const double lot)
{
   if(InpMaxRiskPct <= 0) return true;  // No limit

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0) return true;

   double slPoints  = MathAbs(entry - sl) / _Point;
   if(slPoints <= 0) return true;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return true;

   double pointValue = tickValue * (_Point / tickSize);
   double riskMoney  = lot * slPoints * pointValue;
   double riskPct    = riskMoney / balance * 100.0;

   if(riskPct > InpMaxRiskPct)
   {
      Print("⚠️ SKIP TRADE: Risk=", NormalizeDouble(riskPct, 2), "% ($",
            NormalizeDouble(riskMoney, 2), ") > MaxRisk=", InpMaxRiskPct,
            "% | Balance=$", NormalizeDouble(balance, 2),
            " Lot=", lot, " SL_pts=", NormalizeDouble(slPoints, 1));
      return false;
   }

   Print("ℹ️ Risk check OK: ", NormalizeDouble(riskPct, 2), "% ($",
         NormalizeDouble(riskMoney, 2), ") ≤ MaxRisk=", InpMaxRiskPct,
         "% | Balance=$", NormalizeDouble(balance, 2));
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
   double entryN = NormalizePrice(entry);
   double slN    = NormalizePrice(sl);
   double tpN    = (tp > 0) ? NormalizePrice(tp) : 0;

   // Normalize lot to symbol constraints
   double lot     = InpLotSize;
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   if(stepLot > 0) lot = MathFloor(lot / stepLot) * stepLot;
   lot = NormalizeDouble(lot, 2);

   // Max risk check
   if(!CheckMaxRisk(entryN, slN, lot))
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
// BREAKEVEN TRAILING — Move SL to entry when profit >= g_beAtR × risk
// ============================================================================
void CheckBreakevenMove()
{
   if(g_beDone || g_beAtR <= 0) return;
   if(g_beEntryPrice == 0 || g_beOrigSL == 0) return;

   double risk = MathAbs(g_beEntryPrice - g_beOrigSL);
   if(risk <= 0) return;

   double beTarget = g_beAtR * risk;  // Distance needed for BE move

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
            " | Profit was >= ", g_beAtR, "R | Ticket=", ticket);
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

   // ── Apply strategy preset ──
   switch(InpPreset)
   {
      case PRESET_V3_OPTIMAL:
         g_pivotLen = 3;  g_breakMult = 0;  g_impulseMult = 1.0;
         g_tpFixedRR = 3.0;  g_beAtR = 0.5;  g_slBufferPct = 0;
         break;
      case PRESET_V3_SAFE:
         g_pivotLen = 3;  g_breakMult = 0.25;  g_impulseMult = 1.5;
         g_tpFixedRR = 0;  g_beAtR = 0;  g_slBufferPct = 0;
         break;
      case PRESET_V2_ORIGINAL:
         g_pivotLen = 5;  g_breakMult = 0.25;  g_impulseMult = 1.75;
         g_tpFixedRR = 0;  g_beAtR = 0;  g_slBufferPct = 0;
         break;
      case PRESET_CUSTOM:
         g_pivotLen = InpPivotLen;  g_breakMult = InpBreakMult;  g_impulseMult = InpImpulseMult;
         g_tpFixedRR = InpTPFixedRR;  g_beAtR = InpBEAtR;  g_slBufferPct = InpSLBufferPct;
         break;
   }
   Print("ℹ️ Strategy: Preset=", EnumToString(InpPreset),
         " | PivotLen=", g_pivotLen, " BreakMult=", g_breakMult,
         " ImpulseMult=", g_impulseMult, " TP_RR=", g_tpFixedRR,
         " BE@R=", g_beAtR, " SLBuf=", g_slBufferPct, "%");

   // HTF Trend Filter: create EMA indicator on higher timeframe
   if(HTF_FILTER)
   {
      g_htfEmaHandle = iMA(_Symbol, HTF_PERIOD, HTF_EMA_LEN, 0, MODE_EMA, PRICE_CLOSE);
      if(g_htfEmaHandle == INVALID_HANDLE)
      {
         Print("⚠️ Failed to create HTF EMA handle! Trend filter disabled.");
      }
      else
      {
         Print("ℹ️ HTF Trend Filter: EMA", HTF_EMA_LEN, " on ",
               EnumToString(HTF_PERIOD), " — BUY only above, SELL only below");
      }
   }

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteObjectsByPrefix(g_objPrefix);
   if(g_htfEmaHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_htfEmaHandle);
      g_htfEmaHandle = INVALID_HANDLE;
   }
}

// ============================================================================
// MAIN TICK HANDLER
// ============================================================================
void OnTick()
{
   // Extend lines on every tick
   if(SHOW_VISUAL && SHOW_BREAK_LINE)
      ExtendActiveLines();

   // ── Breakeven: Move SL to entry when profit >= BE_AT_R × risk ──
   if(!g_beDone && g_beAtR > 0)
      CheckBreakevenMove();

   // Only process on new bar
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == g_lastBarTime) return;
   g_lastBarTime = currentBarTime;

   int bars = Bars(_Symbol, _Period);
   if(bars < g_pivotLen * 2 + 25) return;  // Need enough bars for avg body

   // ================================================================
   // STEP 1: SWING DETECTION (at bar = PIVOT_LEN, the confirmed pivot)
   // ================================================================
   int checkBar = g_pivotLen;
   bool isSwH = IsPivotHigh(checkBar, g_pivotLen);
   bool isSwL = IsPivotLow(checkBar, g_pivotLen);

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
   if(isNewHH && g_impulseMult > 0)
   {
      double avgBody = CalcAvgBody(1, 20);
      int sh0Shift = TimeToShift(g_sh0_time);
      int toBar    = g_pivotLen;  // sh1 position
      bool found   = false;
      if(sh0Shift >= 0)
      {
         for(int i = sh0Shift; i >= toBar; i--)
         {
            if(i < 0) continue;
            if(iClose(_Symbol, _Period, i) > g_sh0)
            {
               double body = MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i));
               found = (body >= g_impulseMult * avgBody);
               break;
            }
         }
      }
      if(!found) isNewHH = false;
   }

   if(isNewLL && g_impulseMult > 0)
   {
      double avgBody = CalcAvgBody(1, 20);
      int sl0Shift = TimeToShift(g_sl0_time);
      int toBar    = g_pivotLen;
      bool found   = false;
      if(sl0Shift >= 0)
      {
         for(int i = sl0Shift; i >= toBar; i--)
         {
            if(i < 0) continue;
            if(iClose(_Symbol, _Period, i) < g_sl0)
            {
               double body = MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i));
               found = (body >= g_impulseMult * avgBody);
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
      if(g_breakMult <= 0)
         rawBreakUp = true;
      else
      {
         double swR = g_sh0 - g_slBeforeSH;
         double brD = g_sh1 - g_sh0;
         if(swR > 0 && brD >= swR * g_breakMult)
            rawBreakUp = true;
      }
   }

   if(isNewLL && g_shBeforeSL != EMPTY_VALUE)
   {
      if(g_breakMult <= 0)
         rawBreakDown = true;
      else
      {
         double swR = g_shBeforeSL - g_sl0;
         double brD = g_sl0 - g_sl1;
         if(swR > 0 && brD >= swR * g_breakMult)
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
   // STEP 5: HTF TREND FILTER + PROCESS CONFIRMED SIGNALS
   // ================================================================
   // Check HTF trend: only trade in direction of higher timeframe EMA
   if((confirmedBuy || confirmedSell) && HTF_FILTER && g_htfEmaHandle != INVALID_HANDLE)
   {
      double emaVal[1];
      if(CopyBuffer(g_htfEmaHandle, 0, 0, 1, emaVal) == 1)
      {
         double currentClose = iClose(_Symbol, _Period, 1);
         if(confirmedBuy && currentClose < emaVal[0])
         {
            Print("⚠️ HTF FILTER: BUY skipped — Price=", NormalizeDouble(currentClose, _Digits),
                  " < EMA", HTF_EMA_LEN, "(", EnumToString(HTF_PERIOD), ")=",
                  NormalizeDouble(emaVal[0], _Digits), " → Downtrend");
            // Draw visual with HTF Filtered note (signal detected but not traded)
            if(SHOW_VISUAL && SHOW_BREAK_LABEL)
            {
               g_breakCount++;
               string suffix = IntegerToString(g_breakCount);
               string lblName = g_objPrefix + "CONF_UP_" + suffix;
               DrawTextLabel(lblName, confWaveTime, confWaveHigh,
                             "▲ Confirm Break (HTF Filtered)", clrGray, 9);
            }
            confirmedBuy = false;
         }
         if(confirmedSell && currentClose > emaVal[0])
         {
            Print("⚠️ HTF FILTER: SELL skipped — Price=", NormalizeDouble(currentClose, _Digits),
                  " > EMA", HTF_EMA_LEN, "(", EnumToString(HTF_PERIOD), ")=",
                  NormalizeDouble(emaVal[0], _Digits), " → Uptrend");
            // Draw visual with HTF Filtered note (signal detected but not traded)
            if(SHOW_VISUAL && SHOW_BREAK_LABEL)
            {
               g_breakCount++;
               string suffix = IntegerToString(g_breakCount);
               string lblName = g_objPrefix + "CONF_DN_" + suffix;
               DrawTextLabel(lblName, confWaveTime, confWaveLow,
                             "▼ Confirm Break (HTF Filtered)", clrGray, 9);
            }
            confirmedSell = false;
         }
      }
   }

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

   // Calculate SL with buffer (auto 5% of risk distance)
   double slBuffered = sl;
   double riskDist = MathAbs(entry - sl);
   if(g_slBufferPct > 0 && riskDist > 0)
   {
      double bufferAmt = riskDist * g_slBufferPct / 100.0;
      if(isBuy)  slBuffered = sl - bufferAmt;
      else       slBuffered = sl + bufferAmt;
   }

   // Calculate TP
   double tp;
   if(g_tpFixedRR > 0)
   {
      // Fixed RR TP: TP = entry ± g_tpFixedRR × risk
      if(isBuy)  tp = entry + g_tpFixedRR * riskDist;
      else       tp = entry - g_tpFixedRR * riskDist;
   }
   else
   {
      // Confirm Break TP: high/low of confirm break candle
      tp = isBuy ? waveHigh : waveLow;
   }

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
         DrawHLine(entName, entryTime, entry, now,
                   isBuy ? COL_ENTRY_BUY : COL_ENTRY_SELL, STYLE_DASH, 1);
         DrawHLine(slName, slTime, sl, now,
                   COL_SL, STYLE_DASH, 1);

         // Labels
         string entLbl = g_objPrefix + "ENTLBL_" + suffix;
         string slLbl  = g_objPrefix + "SLLBL_"  + suffix;
         DrawTextLabel(entLbl, now, entry,
                       isBuy ? "Entry Buy" : "Entry Sell",
                       isBuy ? COL_ENTRY_BUY : COL_ENTRY_SELL, 7);
         DrawTextLabel(slLbl, now, sl, "SL", COL_SL, 7);

         // TP line
         if(tp > 0)
         {
            string tpName = g_objPrefix + "TP_" + suffix;
            string tpLbl  = g_objPrefix + "TPLBL_" + suffix;
            DrawHLine(tpName, entryTime, tp, now, COL_TP, STYLE_DASH, 1);
            string tpText = (g_tpFixedRR > 0)
               ? StringFormat("TP (%.1fR)", g_tpFixedRR)
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
                                 entry, slBuffered, tp, _Symbol);
      Alert(msg);
      Print("🔔 ", msg);
   }

   // ── Trade ──
   {
      DeleteAllPendingOrders();
      CloseAllPositions();

      // Reset breakeven state for new trade
      g_beDone       = false;
      g_beEntryPrice = entry;
      g_beOrigSL     = slBuffered;
      g_beIsBuy      = isBuy;

      // Normalize lot to symbol constraints
      double totalLot = InpLotSize;
      double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double stepLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(totalLot < minLot) totalLot = minLot;
      if(totalLot > maxLot) totalLot = maxLot;
      if(stepLot > 0) totalLot = MathFloor(totalLot / stepLot) * stepLot;
      totalLot = NormalizeDouble(totalLot, 2);

      // Max risk check — use InpLotSize (NOT doubled) for risk check
      if(!CheckMaxRisk(entry, slBuffered, totalLot))
         return;

      // Place order
      PlaceOrder(isBuy, entry, slBuffered, tp);
   }
}
//+------------------------------------------------------------------+
