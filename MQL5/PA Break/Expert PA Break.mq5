//+------------------------------------------------------------------+
//| Expert PA Break.mq5                                              |
//| PA Break EA — Trade + Visual on Swing HH/LL Breakout            |
//| Converted from TradingView Pine Script v0.4.0                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MTS"
#property link      ""
#property version   "1.40"
#property strict

//--- Inputs: Signal
input int    InpPivotLen    = 5;     // Pivot Lookback
input double InpBreakMult   = 0;     // Break Strength (x Swing Range, 0=OFF)

//--- Inputs: Trade
input double InpLotSize     = 0.01;  // Lot Size
input int    InpATRLen       = 14;    // ATR Period (for SL buffer)
input double InpSLBufferATR  = 0.2;   // SL Buffer (x ATR)
input double InpRRRatio      = 2.0;   // TP Risk:Reward Ratio (0=OFF)
input int    InpDeviation   = 20;    // Max Deviation (points)
input ulong  InpMagic       = 20260207; // Magic Number
input int    InpExpiryMin   = 0;     // Pending Expiry (min, 0=none)
input bool   InpEnableAlerts= true;  // Enable Alerts
input bool   InpEnableTrade = true;  // Enable Trading

//--- Inputs: Visual
input bool   InpShowVisual     = true;           // Show Visual on Chart
input bool   InpShowSwings     = true;           // Show Swing Points
input bool   InpShowBreakLabel = true;           // Show Break Labels
input bool   InpShowBreakLine  = true;           // Show Entry/SL Lines
input color  InpColBreakUp     = clrLime;        // Break UP Label Color
input color  InpColBreakDown   = clrRed;         // Break DOWN Label Color
input color  InpColEntryBuy    = clrDodgerBlue;  // Entry Buy Line Color
input color  InpColEntrySell   = clrHotPink;     // Entry Sell Line Color
input color  InpColSL          = clrYellow;      // SL Line Color
input color  InpColTP          = clrLimeGreen;   // TP Line Color
input color  InpColSwingHigh   = clrOrange;      // Swing High Color
input color  InpColSwingLow    = clrCornflowerBlue; // Swing Low Color

//--- Object prefix
string g_objPrefix = "PAB_";

//--- State
static datetime g_lastBarTime = 0;

// Swing history (persistent)
static double g_sh1 = EMPTY_VALUE, g_sh0 = EMPTY_VALUE;
static double g_sl1 = EMPTY_VALUE, g_sl0 = EMPTY_VALUE;
static datetime g_sh1_time = 0, g_sh0_time = 0;
static datetime g_sl1_time = 0, g_sl0_time = 0;
static double g_slBeforeSH = EMPTY_VALUE;
static datetime g_slBeforeSH_time = 0;
static double g_shBeforeSL = EMPTY_VALUE;
static datetime g_shBeforeSL_time = 0;

// Group tracking: highest SH / lowest SL in swing group before break
static double   g_shGroupMax      = EMPTY_VALUE;
static datetime g_shGroupMax_time = 0;
static double   g_slGroupMin      = EMPTY_VALUE;
static datetime g_slGroupMin_time = 0;

// Track last signal to avoid duplicates
static datetime g_lastBuySignal  = 0;
static datetime g_lastSellSignal = 0;

// Active Entry/SL line tracking
static string g_activeEntryLineName = "";
static string g_activeSLLineName    = "";
static string g_activeEntryLblName  = "";
static string g_activeSLLblName     = "";
static double g_activeEntryPrice    = EMPTY_VALUE;
static double g_activeSLPrice       = EMPTY_VALUE;
static double g_activeTPPrice       = EMPTY_VALUE;
static bool   g_activeIsBuy         = false;
static bool   g_hasActiveLine       = false;
static string g_activeTPLineName    = "";
static string g_activeTPLblName     = "";

// Break count for unique naming
static int g_breakCount = 0;

// Confirmation state machine
static int      g_pendingState     = 0;           // 0=idle, 1=pendingBuy, -1=pendingSell
static double   g_pendBreakPoint   = EMPTY_VALUE;  // Break point (sh1 for buy, sl1 for sell)
static double   g_pendEntry        = EMPTY_VALUE;  // Entry level (sh0 for buy, sl0 for sell)
static double   g_pendSL           = EMPTY_VALUE;  // SL level
static datetime g_pendEntry_time   = 0;
static datetime g_pendSL_time      = 0;
static datetime g_pendBreak_time   = 0;

// ATR handle for SL buffer
static int g_atrHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   string number = StringFormat("%I64d", GetTickCount64());
   g_objPrefix = StringSubstr(number, MathMax(0, StringLen(number) - 4)) + "_PAB_";

   g_atrHandle = iATR(_Symbol, _Period, InpATRLen);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle.");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteObjectsByPrefix(g_objPrefix);
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   g_atrHandle = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
// Terminate current active Entry/SL lines at given time
void TerminateActiveLines(datetime endTime)
{
   if(!g_hasActiveLine) return;

   // Update x2 of existing lines
   if(g_activeEntryLineName != "")
      DrawHLine(g_activeEntryLineName, 0, g_activeEntryPrice, endTime,
                g_activeIsBuy ? InpColEntryBuy : InpColEntrySell, STYLE_DASH, 1);
   if(g_activeSLLineName != "")
      DrawHLine(g_activeSLLineName, 0, g_activeSLPrice, endTime,
                InpColSL, STYLE_DASH, 1);
   if(g_activeTPLineName != "" && g_activeTPPrice != EMPTY_VALUE)
      DrawHLine(g_activeTPLineName, 0, g_activeTPPrice, endTime,
                InpColTP, STYLE_DASH, 1);
   // Move labels to end
   if(g_activeEntryLblName != "")
      DrawTextLabel(g_activeEntryLblName, endTime, g_activeEntryPrice,
                   g_activeIsBuy ? "Entry Buy" : "Entry Sell",
                   g_activeIsBuy ? InpColEntryBuy : InpColEntrySell, 7);
   if(g_activeSLLblName != "")
      DrawTextLabel(g_activeSLLblName, endTime, g_activeSLPrice, "SL", InpColSL, 7);
   if(g_activeTPLblName != "")
      DrawTextLabel(g_activeTPLblName, endTime, g_activeTPPrice, "TP", InpColTP, 7);
}

//+------------------------------------------------------------------+
// Extend active lines to current time (called every bar)
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

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
// Close all positions belonging to this EA
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
      ZeroMemory(req);
      ZeroMemory(res);

      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = _Symbol;
      req.volume    = PositionGetDouble(POSITION_VOLUME);
      req.deviation = InpDeviation;
      req.magic     = InpMagic;

      long posType = PositionGetInteger(POSITION_TYPE);
      if(posType == POSITION_TYPE_BUY)
      {
         req.type  = ORDER_TYPE_SELL;
         req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      }
      else
      {
         req.type  = ORDER_TYPE_BUY;
         req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      }
      req.position = ticket;
      req.comment  = "PA_BREAK_CLOSE";

      if(!OrderSend(req, res))
         Print("Close position failed. Ticket=", ticket, " Retcode=", res.retcode);
      else
         Print("✅ Closed position. Ticket=", ticket);
   }
}

//+------------------------------------------------------------------+
// Delete all pending orders belonging to this EA
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
      ZeroMemory(req);
      ZeroMemory(res);

      req.action = TRADE_ACTION_REMOVE;
      req.order  = ticket;

      if(!OrderSend(req, res))
         Print("Delete order failed. Ticket=", ticket, " Retcode=", res.retcode);
      else
         Print("✅ Deleted pending order. Ticket=", ticket);
   }
}

//+------------------------------------------------------------------+
double NormalizePrice(const double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) tick = _Point;
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
}

//+------------------------------------------------------------------+
bool PlaceOrder(const bool isBuy, const double entry, const double sl, const double tp)
{
   double entryN = NormalizePrice(entry);
   double slN    = NormalizePrice(sl);
   double tpN    = NormalizePrice(tp);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   ENUM_ORDER_TYPE type;
   if(isBuy)
   {
      if(entryN < ask)
         type = ORDER_TYPE_BUY_LIMIT;
      else if(entryN > ask)
         type = ORDER_TYPE_BUY_STOP;
      else
      {
         // Market buy
         MqlTradeRequest req; MqlTradeResult res;
         ZeroMemory(req); ZeroMemory(res);
         req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol;
         req.volume = InpLotSize; req.type = ORDER_TYPE_BUY;
         req.price = ask; req.sl = slN;
         req.tp = (tpN > 0) ? tpN : 0; // TP=0 means close on next break
         req.magic = InpMagic; req.deviation = InpDeviation;
         req.comment = "PA_BREAK_BUY";
         if(!OrderSend(req, res))
         { Print("OrderSend failed. Retcode=", res.retcode); return false; }
         Print("✅ BUY market. Ticket=", res.order);
         return true;
      }
   }
   else
   {
      if(entryN > bid)
         type = ORDER_TYPE_SELL_LIMIT;
      else if(entryN < bid)
         type = ORDER_TYPE_SELL_STOP;
      else
      {
         MqlTradeRequest req; MqlTradeResult res;
         ZeroMemory(req); ZeroMemory(res);
         req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol;
         req.volume = InpLotSize; req.type = ORDER_TYPE_SELL;
         req.price = bid; req.sl = slN;
         req.tp = (tpN > 0) ? tpN : 0; // TP=0 means close on next break
         req.magic = InpMagic; req.deviation = InpDeviation;
         req.comment = "PA_BREAK_SELL";
         if(!OrderSend(req, res))
         { Print("OrderSend failed. Retcode=", res.retcode); return false; }
         Print("✅ SELL market. Ticket=", res.order);
         return true;
      }
   }

   // Validate SL placement (TP can be 0 = no TP, will close on next break)
   if(isBuy && slN >= entryN)
   { Print("Invalid BUY SL. SL=", slN, " >= Entry=", entryN); return false; }
   if(!isBuy && slN <= entryN)
   { Print("Invalid SELL SL. SL=", slN, " <= Entry=", entryN); return false; }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action    = TRADE_ACTION_PENDING;
   req.symbol    = _Symbol;
   req.volume    = InpLotSize;
   req.type      = type;
   req.price     = entryN;
   req.sl        = slN;
   req.tp        = (tpN > 0) ? tpN : 0; // TP=0 means close on next break
   req.magic     = InpMagic;
   req.deviation = InpDeviation;
   req.comment   = isBuy ? "PA_BREAK_BUY" : "PA_BREAK_SELL";

   if(InpExpiryMin > 0)
   {
      req.type_time  = ORDER_TIME_SPECIFIED;
      req.expiration = TimeCurrent() + InpExpiryMin * 60;
   }

   if(!OrderSend(req, res))
   {
      Print("OrderSend failed. Retcode=", res.retcode);
      return false;
   }
   Print("✅ Pending ", (isBuy ? "BUY" : "SELL"),
         " Ticket=", res.order, " Entry=", entryN, " SL=", slN, " TP=", tpN);
   return true;
}

//+------------------------------------------------------------------+
// Pivot High: high at barIdx is highest in [barIdx-pivotLen, barIdx+pivotLen]
// barIdx is in "series" format: 0 = current bar, 1 = previous bar, etc.
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

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
void OnTick()
{
   // Only on new bar
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == g_lastBarTime)
   {
      // Still extend active lines every tick for visual smoothness
      if(InpShowVisual && InpShowBreakLine)
         ExtendActiveLines();
      return;
   }
   g_lastBarTime = currentBarTime;

   int bars = Bars(_Symbol, _Period);
   if(bars < InpPivotLen * 2 + 5)
      return;

   // Check the most recently confirmed pivot: bar index = InpPivotLen
   int checkBar = InpPivotLen;

   bool isSwH = IsPivotHigh(checkBar, InpPivotLen);
   bool isSwL = IsPivotLow(checkBar, InpPivotLen);

   datetime checkTime = iTime(_Symbol, _Period, checkBar);
   double   checkHigh = iHigh(_Symbol, _Period, checkBar);
   double   checkLow  = iLow(_Symbol, _Period, checkBar);

   // ── Update Swing Low first (same order as Pine) ──
   if(isSwL)
   {
      // Tích lũy sl1 cũ vào slGroupMin trước khi bị đẩy thành sl0
      if(g_sl1 != EMPTY_VALUE)
      {
         if(g_slGroupMin == EMPTY_VALUE || g_sl1 < g_slGroupMin)
         {
            g_slGroupMin      = g_sl1;
            g_slGroupMin_time = g_sl1_time;
         }
      }
      g_sl0 = g_sl1;       g_sl0_time = g_sl1_time;
      g_sl1 = checkLow;    g_sl1_time = checkTime;
   }

   // ── Update Swing High ──
   if(isSwH)
   {
      // Tích lũy sh1 cũ vào shGroupMax trước khi bị đẩy thành sh0
      if(g_sh1 != EMPTY_VALUE)
      {
         if(g_shGroupMax == EMPTY_VALUE || g_sh1 > g_shGroupMax)
         {
            g_shGroupMax      = g_sh1;
            g_shGroupMax_time = g_sh1_time;
         }
      }
      g_slBeforeSH = g_sl1;
      g_slBeforeSH_time = g_sl1_time;

      g_sh0 = g_sh1;       g_sh0_time = g_sh1_time;
      g_sh1 = checkHigh;   g_sh1_time = checkTime;
   }

   // ── Update shBeforeSL ──
   if(isSwL)
   {
      g_shBeforeSL = g_sh1;
      g_shBeforeSL_time = g_sh1_time;
   }

   // ── Visual: Swing markers ──
   if(InpShowVisual && InpShowSwings)
   {
      if(isSwH)
      {
         double pad = (checkHigh - checkLow) * 0.3;
         if(pad < _Point * 5) pad = _Point * 5;
         string name = g_objPrefix + "SWH_" + IntegerToString((long)checkTime);
         DrawArrowIcon(name, checkTime, checkHigh + pad, 234, InpColSwingHigh, 1);
      }
      if(isSwL)
      {
         double pad = (checkHigh - checkLow) * 0.3;
         if(pad < _Point * 5) pad = _Point * 5;
         string name = g_objPrefix + "SWL_" + IntegerToString((long)checkTime);
         DrawArrowIcon(name, checkTime, checkLow - pad, 233, InpColSwingLow, 1);
      }
   }

   // ── HH / LL Detection (simple) ──
   bool isNewHH = isSwH && g_sh0 != EMPTY_VALUE && g_sh1 > g_sh0;
   bool isNewLL = isSwL && g_sl0 != EMPTY_VALUE && g_sl1 < g_sl0;

   // ── Break Strength Filter (optional, default OFF) ──
   bool rawBreakUp   = false;
   bool rawBreakDown = false;

   if(isNewHH && g_slBeforeSH != EMPTY_VALUE)
   {
      if(InpBreakMult <= 0)
         rawBreakUp = true;
      else
      {
         double swingRange = g_sh0 - g_slBeforeSH;
         double breakDist  = g_sh1 - g_sh0;
         if(swingRange > 0 && breakDist >= swingRange * InpBreakMult)
            rawBreakUp = true;
      }
   }

   if(isNewLL && g_shBeforeSL != EMPTY_VALUE)
   {
      if(InpBreakMult <= 0)
         rawBreakDown = true;
      else
      {
         double swingRange = g_shBeforeSL - g_sl0;
         double breakDist  = g_sl0 - g_sl1;
         if(swingRange > 0 && breakDist >= swingRange * InpBreakMult)
            rawBreakDown = true;
      }
   }

   // ============================================================
   // CONFIRMATION STATE MACHINE
   // States: 0=idle, 1=pendingBuy, -1=pendingSell
   //
   // BUY: after HH break, wait for new swing HIGH > break point
   //      Invalidate if price low <= entry.
   //
   // SELL: after LL break, wait for new swing LOW < break point
   //       Invalidate if price high >= entry.
   // ============================================================

   // ── Step 1: Check confirmation FIRST (before new break overwrites) ──
   bool confirmedBuy  = false;
   bool confirmedSell = false;

   if(g_pendingState == 1 && isSwH && g_pendBreakPoint != EMPTY_VALUE)
   {
      if(checkHigh > g_pendBreakPoint)
      {
         confirmedBuy   = true;
         g_pendingState = 0;
      }
   }

   if(g_pendingState == -1 && isSwL && g_pendBreakPoint != EMPTY_VALUE)
   {
      if(checkLow < g_pendBreakPoint)
      {
         confirmedSell  = true;
         g_pendingState = 0;
      }
   }

   // ── Step 2: Check invalidation (price touched entry level) ──
   double prevLow  = iLow(_Symbol, _Period, 1);
   double prevHigh = iHigh(_Symbol, _Period, 1);

   if(g_pendingState == 1 && g_pendEntry != EMPTY_VALUE)
   {
      if(prevLow <= g_pendEntry)
         g_pendingState = 0;
   }

   if(g_pendingState == -1 && g_pendEntry != EMPTY_VALUE)
   {
      if(prevHigh >= g_pendEntry)
         g_pendingState = 0;
   }

   // ── Step 3: Raw break → set pending state ──
   if(rawBreakUp)
   {
      g_pendingState   = 1;
      g_pendBreakPoint = g_sh1;
      if(g_shGroupMax != EMPTY_VALUE && g_shGroupMax < g_sh1)
      {
         g_pendEntry      = g_shGroupMax;
         g_pendEntry_time = g_shGroupMax_time;
      }
      else
      {
         g_pendEntry      = g_sh0;
         g_pendEntry_time = g_sh0_time;
      }
      g_pendSL         = g_slBeforeSH;
      g_pendSL_time    = g_slBeforeSH_time;
      g_pendBreak_time = g_sh1_time;
      g_shGroupMax      = EMPTY_VALUE;
      g_shGroupMax_time = 0;
   }

   if(rawBreakDown)
   {
      g_pendingState   = -1;
      g_pendBreakPoint = g_sl1;
      if(g_slGroupMin != EMPTY_VALUE && g_slGroupMin > g_sl1)
      {
         g_pendEntry      = g_slGroupMin;
         g_pendEntry_time = g_slGroupMin_time;
      }
      else
      {
         g_pendEntry      = g_sl0;
         g_pendEntry_time = g_sl0_time;
      }
      g_pendSL         = g_shBeforeSL;
      g_pendSL_time    = g_shBeforeSL_time;
      g_pendBreak_time = g_sl1_time;
      g_slGroupMin      = EMPTY_VALUE;
      g_slGroupMin_time = 0;
   }

   // ── Process Confirmed BUY ──
   if(confirmedBuy)
   {
      g_breakCount++;
      string suffix = IntegerToString(g_breakCount);
      double entryBuy = g_pendEntry;
      double slBuy    = g_pendSL;

      // Calculate SL with ATR buffer
      double atrBuf[1];
      double slBuffer = 0;
      if(g_atrHandle != INVALID_HANDLE && CopyBuffer(g_atrHandle, 0, 0, 1, atrBuf) == 1)
         slBuffer = atrBuf[0] * InpSLBufferATR;
      double slBuffered = slBuy - slBuffer;

      // Calculate TP based on RR ratio (0=OFF)
      double tpBuy = 0;
      if(InpRRRatio > 0)
      {
         double risk = entryBuy - slBuffered;
         tpBuy = entryBuy + InpRRRatio * risk;
      }

      // Visual
      if(InpShowVisual)
      {
         if(InpShowBreakLine)
            TerminateActiveLines(checkTime);

         if(InpShowBreakLabel)
         {
            double pad = (g_pendBreakPoint - g_pendSL) * 0.08;
            if(pad < _Point * 10) pad = _Point * 10;
            string lblName = g_objPrefix + "BRK_UP_" + suffix;
            DrawTextLabel(lblName, g_pendBreak_time, g_pendBreakPoint + pad,
                          "▲ Break ✓", InpColBreakUp, 9);
         }

         if(InpShowBreakLine && g_pendEntry_time > 0 && g_pendSL_time > 0)
         {
            g_activeIsBuy = true;
            g_activeEntryPrice = entryBuy;
            g_activeSLPrice    = slBuy;
            g_activeTPPrice    = (tpBuy > 0) ? tpBuy : EMPTY_VALUE;

            g_activeEntryLineName = g_objPrefix + "ENT_" + suffix;
            g_activeSLLineName    = g_objPrefix + "SL_" + suffix;
            g_activeEntryLblName  = g_objPrefix + "ENTLBL_" + suffix;
            g_activeSLLblName     = g_objPrefix + "SLLBL_" + suffix;
            g_activeTPLineName    = (tpBuy > 0) ? g_objPrefix + "TP_" + suffix : "";
            g_activeTPLblName     = (tpBuy > 0) ? g_objPrefix + "TPLBL_" + suffix : "";
            g_hasActiveLine = true;

            datetime now = TimeCurrent();
            DrawHLine(g_activeEntryLineName, g_pendEntry_time, entryBuy, now,
                      InpColEntryBuy, STYLE_DASH, 1);
            DrawTextLabel(g_activeEntryLblName, now, entryBuy, "Entry Buy", InpColEntryBuy, 7);
            DrawHLine(g_activeSLLineName, g_pendSL_time, slBuy, now,
                      InpColSL, STYLE_DASH, 1);
            DrawTextLabel(g_activeSLLblName, now, slBuy, "SL", InpColSL, 7);

            if(tpBuy > 0)
            {
               DrawHLine(g_activeTPLineName, g_pendEntry_time, tpBuy, now,
                         InpColTP, STYLE_DASH, 1);
               DrawTextLabel(g_activeTPLblName, now, tpBuy,
                             "TP (1:" + DoubleToString(InpRRRatio, 1) + ")", InpColTP, 7);
            }
         }
      }

      // Trade
      if(g_pendBreak_time > g_lastBuySignal)
      {
         g_lastBuySignal = g_pendBreak_time;

         if(InpEnableAlerts)
            Alert("PA Break CONFIRMED BUY: ", _Symbol,
                  " Entry=", DoubleToString(entryBuy, _Digits),
                  " SL=", DoubleToString(slBuffered, _Digits),
                  (tpBuy > 0 ? " TP=" + DoubleToString(tpBuy, _Digits) : " TP=none"));

         if(InpEnableTrade)
         {
            CloseAllPositions();
            DeleteAllPendingOrders();
            PlaceOrder(true, entryBuy, slBuffered, tpBuy);
         }
      }
   }

   // ── Process Confirmed SELL ──
   if(confirmedSell)
   {
      g_breakCount++;
      string suffix = IntegerToString(g_breakCount);
      double entrySell = g_pendEntry;
      double slSell    = g_pendSL;

      // Calculate SL with ATR buffer
      double atrBuf[1];
      double slBuffer = 0;
      if(g_atrHandle != INVALID_HANDLE && CopyBuffer(g_atrHandle, 0, 0, 1, atrBuf) == 1)
         slBuffer = atrBuf[0] * InpSLBufferATR;
      double slBuffered = slSell + slBuffer;

      // Calculate TP based on RR ratio (0=OFF)
      double tpSell = 0;
      if(InpRRRatio > 0)
      {
         double risk = slBuffered - entrySell;
         tpSell = entrySell - InpRRRatio * risk;
      }

      // Visual
      if(InpShowVisual)
      {
         if(InpShowBreakLine)
            TerminateActiveLines(checkTime);

         if(InpShowBreakLabel)
         {
            double pad = (g_pendSL - g_pendBreakPoint) * 0.08;
            if(pad < _Point * 10) pad = _Point * 10;
            string lblName = g_objPrefix + "BRK_DN_" + suffix;
            DrawTextLabel(lblName, g_pendBreak_time, g_pendBreakPoint - pad,
                          "▼ Break ✓", InpColBreakDown, 9);
         }

         if(InpShowBreakLine && g_pendEntry_time > 0 && g_pendSL_time > 0)
         {
            g_activeIsBuy = false;
            g_activeEntryPrice = entrySell;
            g_activeSLPrice    = slSell;
            g_activeTPPrice    = (tpSell > 0) ? tpSell : EMPTY_VALUE;

            g_activeEntryLineName = g_objPrefix + "ENT_" + suffix;
            g_activeSLLineName    = g_objPrefix + "SL_" + suffix;
            g_activeEntryLblName  = g_objPrefix + "ENTLBL_" + suffix;
            g_activeSLLblName     = g_objPrefix + "SLLBL_" + suffix;
            g_activeTPLineName    = (tpSell > 0) ? g_objPrefix + "TP_" + suffix : "";
            g_activeTPLblName     = (tpSell > 0) ? g_objPrefix + "TPLBL_" + suffix : "";
            g_hasActiveLine = true;

            datetime now = TimeCurrent();
            DrawHLine(g_activeEntryLineName, g_pendEntry_time, entrySell, now,
                      InpColEntrySell, STYLE_DASH, 1);
            DrawTextLabel(g_activeEntryLblName, now, entrySell, "Entry Sell", InpColEntrySell, 7);
            DrawHLine(g_activeSLLineName, g_pendSL_time, slSell, now,
                      InpColSL, STYLE_DASH, 1);
            DrawTextLabel(g_activeSLLblName, now, slSell, "SL", InpColSL, 7);

            if(tpSell > 0)
            {
               DrawHLine(g_activeTPLineName, g_pendEntry_time, tpSell, now,
                         InpColTP, STYLE_DASH, 1);
               DrawTextLabel(g_activeTPLblName, now, tpSell,
                             "TP (1:" + DoubleToString(InpRRRatio, 1) + ")", InpColTP, 7);
            }
         }
      }

      // Trade
      if(g_pendBreak_time > g_lastSellSignal)
      {
         g_lastSellSignal = g_pendBreak_time;

         if(InpEnableAlerts)
            Alert("PA Break CONFIRMED SELL: ", _Symbol,
                  " Entry=", DoubleToString(entrySell, _Digits),
                  " SL=", DoubleToString(slBuffered, _Digits),
                  (tpSell > 0 ? " TP=" + DoubleToString(tpSell, _Digits) : " TP=none"));

         if(InpEnableTrade)
         {
            CloseAllPositions();
            DeleteAllPendingOrders();
            PlaceOrder(false, entrySell, slBuffered, tpSell);
         }
      }
   }

   // Extend active lines to now
   if(InpShowVisual && InpShowBreakLine)
      ExtendActiveLines();
}
//+------------------------------------------------------------------+
