//+------------------------------------------------------------------+
//| Expert PA Break.mq5                                              |
//| PA Break EA — Trade + Visual on Swing HH/LL Breakout            |
//| Converted from TradingView Pine Script v0.2.0                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MTS"
#property link      ""
#property version   "1.10"
#property strict

//--- Inputs: Signal
input int    InpPivotLen    = 5;     // Pivot Lookback
input double InpBreakMult   = 1.0;   // Break Strength (x Swing Range)

//--- Inputs: Trade
input double InpLotSize     = 0.01;  // Lot Size
input int    InpATRLen       = 14;    // ATR Period (for SL buffer)
input double InpSLBufferATR  = 0.2;   // SL Buffer (x ATR)
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
static bool   g_activeIsBuy         = false;
static bool   g_hasActiveLine       = false;

// Break count for unique naming
static int g_breakCount = 0;

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
   // Move labels to end
   if(g_activeEntryLblName != "")
      DrawTextLabel(g_activeEntryLblName, endTime, g_activeEntryPrice,
                   g_activeIsBuy ? "Entry Buy" : "Entry Sell",
                   g_activeIsBuy ? InpColEntryBuy : InpColEntrySell, 7);
   if(g_activeSLLblName != "")
      DrawTextLabel(g_activeSLLblName, endTime, g_activeSLPrice, "SL", InpColSL, 7);
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
      g_sl0 = g_sl1;       g_sl0_time = g_sl1_time;
      g_sl1 = checkLow;    g_sl1_time = checkTime;
   }

   // ── Update Swing High ──
   if(isSwH)
   {
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

   // ── Detect HH / LL ──
   bool isNewHH = isSwH && g_sh0 != EMPTY_VALUE && g_sh1 > g_sh0;
   bool isNewLL = isSwL && g_sl0 != EMPTY_VALUE && g_sl1 < g_sl0;

   // ── Break Strength Filter ──
   bool breakUp   = false;
   bool breakDown = false;
   double entryBuy = 0, slBuy = 0;
   double entrySell = 0, slSell = 0;

   if(isNewHH && g_slBeforeSH != EMPTY_VALUE)
   {
      double swingRange = g_sh0 - g_slBeforeSH;
      double breakDist  = g_sh1 - g_sh0;
      if(swingRange > 0 && breakDist >= swingRange * InpBreakMult)
      {
         breakUp  = true;
         entryBuy = g_sh0;
         slBuy    = g_slBeforeSH;
      }
   }

   if(isNewLL && g_shBeforeSL != EMPTY_VALUE)
   {
      double swingRange = g_shBeforeSL - g_sl0;
      double breakDist  = g_sl0 - g_sl1;
      if(swingRange > 0 && breakDist >= swingRange * InpBreakMult)
      {
         breakDown = true;
         entrySell = g_sl0;
         slSell    = g_shBeforeSL;
      }
   }

   // ── Process Break UP ──
   if(breakUp)
   {
      g_breakCount++;
      string suffix = IntegerToString(g_breakCount);

      // Visual
      if(InpShowVisual)
      {
         // Terminate old lines
         if(InpShowBreakLine)
            TerminateActiveLines(checkTime);

         // Break label
         if(InpShowBreakLabel)
         {
            double pad = (g_sh1 - g_slBeforeSH) * 0.08;
            if(pad < _Point * 10) pad = _Point * 10;
            string lblName = g_objPrefix + "BRK_UP_" + suffix;
            DrawTextLabel(lblName, g_sh1_time, g_sh1 + pad, "▲ Break", InpColBreakUp, 9);
         }

         // New Entry/SL lines
         if(InpShowBreakLine && g_sh0_time > 0 && g_slBeforeSH_time > 0)
         {
            g_activeIsBuy = true;
            g_activeEntryPrice = g_sh0;
            g_activeSLPrice    = g_slBeforeSH;

            g_activeEntryLineName = g_objPrefix + "ENT_" + suffix;
            g_activeSLLineName    = g_objPrefix + "SL_" + suffix;
            g_activeEntryLblName  = g_objPrefix + "ENTLBL_" + suffix;
            g_activeSLLblName     = g_objPrefix + "SLLBL_" + suffix;
            g_hasActiveLine = true;

            datetime now = TimeCurrent();
            DrawHLine(g_activeEntryLineName, g_sh0_time, g_sh0, now,
                      InpColEntryBuy, STYLE_DASH, 1);
            DrawTextLabel(g_activeEntryLblName, now, g_sh0, "Entry Buy", InpColEntryBuy, 7);
            DrawHLine(g_activeSLLineName, g_slBeforeSH_time, g_slBeforeSH, now,
                      InpColSL, STYLE_DASH, 1);
            DrawTextLabel(g_activeSLLblName, now, g_slBeforeSH, "SL", InpColSL, 7);
         }
      }

      // Trade
      if(checkTime > g_lastBuySignal)
      {
         g_lastBuySignal = checkTime;

         // Lấy ATR hiện tại làm buffer
         double atrBuf[1];
         double slBuffer = 0;
         if(g_atrHandle != INVALID_HANDLE && CopyBuffer(g_atrHandle, 0, 0, 1, atrBuf) == 1)
            slBuffer = atrBuf[0] * InpSLBufferATR;
         double slBuffered = slBuy - slBuffer; // SL ra xa thêm ATR buffer

         if(InpEnableAlerts)
            Alert("PA Break BUY: ", _Symbol,
                  " Entry=", DoubleToString(entryBuy, _Digits),
                  " SL=", DoubleToString(slBuffered, _Digits));

         if(InpEnableTrade)
         {
            // Đóng tất cả lệnh cũ + xóa pending cũ
            CloseAllPositions();
            DeleteAllPendingOrders();
            // Đặt lệnh BUY mới, TP = 0 (chốt lời khi có break kế tiếp)
            PlaceOrder(true, entryBuy, slBuffered, 0);
         }
      }
   }

   // ── Process Break DOWN ──
   if(breakDown)
   {
      g_breakCount++;
      string suffix = IntegerToString(g_breakCount);

      // Visual
      if(InpShowVisual)
      {
         // Terminate old lines
         if(InpShowBreakLine)
            TerminateActiveLines(checkTime);

         // Break label
         if(InpShowBreakLabel)
         {
            double pad = (g_shBeforeSL - g_sl1) * 0.08;
            if(pad < _Point * 10) pad = _Point * 10;
            string lblName = g_objPrefix + "BRK_DN_" + suffix;
            DrawTextLabel(lblName, g_sl1_time, g_sl1 - pad, "▼ Break", InpColBreakDown, 9);
         }

         // New Entry/SL lines
         if(InpShowBreakLine && g_sl0_time > 0 && g_shBeforeSL_time > 0)
         {
            g_activeIsBuy = false;
            g_activeEntryPrice = g_sl0;
            g_activeSLPrice    = g_shBeforeSL;

            g_activeEntryLineName = g_objPrefix + "ENT_" + suffix;
            g_activeSLLineName    = g_objPrefix + "SL_" + suffix;
            g_activeEntryLblName  = g_objPrefix + "ENTLBL_" + suffix;
            g_activeSLLblName     = g_objPrefix + "SLLBL_" + suffix;
            g_hasActiveLine = true;

            datetime now = TimeCurrent();
            DrawHLine(g_activeEntryLineName, g_sl0_time, g_sl0, now,
                      InpColEntrySell, STYLE_DASH, 1);
            DrawTextLabel(g_activeEntryLblName, now, g_sl0, "Entry Sell", InpColEntrySell, 7);
            DrawHLine(g_activeSLLineName, g_shBeforeSL_time, g_shBeforeSL, now,
                      InpColSL, STYLE_DASH, 1);
            DrawTextLabel(g_activeSLLblName, now, g_shBeforeSL, "SL", InpColSL, 7);
         }
      }

      // Trade
      if(checkTime > g_lastSellSignal)
      {
         g_lastSellSignal = checkTime;

         // Lấy ATR hiện tại làm buffer
         double atrBuf[1];
         double slBuffer = 0;
         if(g_atrHandle != INVALID_HANDLE && CopyBuffer(g_atrHandle, 0, 0, 1, atrBuf) == 1)
            slBuffer = atrBuf[0] * InpSLBufferATR;
         double slBuffered = slSell + slBuffer; // SL ra xa thêm ATR buffer

         if(InpEnableAlerts)
            Alert("PA Break SELL: ", _Symbol,
                  " Entry=", DoubleToString(entrySell, _Digits),
                  " SL=", DoubleToString(slBuffered, _Digits));

         if(InpEnableTrade)
         {
            // Đóng tất cả lệnh cũ + xóa pending cũ
            CloseAllPositions();
            DeleteAllPendingOrders();
            // Đặt lệnh SELL mới, TP = 0 (chốt lời khi có break kế tiếp)
            PlaceOrder(false, entrySell, slBuffered, 0);
         }
      }
   }

   // Extend active lines to now
   if(InpShowVisual && InpShowBreakLine)
      ExtendActiveLines();
}
//+------------------------------------------------------------------+
