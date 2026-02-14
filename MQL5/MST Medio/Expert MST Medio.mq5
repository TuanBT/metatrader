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
//|   5. TP = Confirm Break candle H/L (W1 Peak area)               |
//|   6. SL buffer = auto 5% of risk distance                       |
//|   7. Auto lot normalization (min/max/step)                       |
//|   8. Partial TP (optional):                                      |
//|      - Close 50% at TP (Confirm Break level)                     |
//|      - Move SL to breakeven                                      |
//|      - Hold remaining 50% until next opposite signal             |
//|   9. On new signal: close all existing positions → open new      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MTS"
#property link      ""
#property version   "2.00"
#property strict

// ============================================================================
// INPUTS
// ============================================================================
input double InpLotSize      = 0.01;    // Lot Size
input bool   InpPartialTP    = false;   // Partial TP (close half at TP, hold rest)
input ulong  InpMagic        = 20260210;// Magic Number

// ============================================================================
// FIXED SETTINGS (not exposed as inputs)
// ============================================================================
#define PIVOT_LEN        5
#define BREAK_MULT       0.25
#define IMPULSE_MULT     1.5
#define PARTIAL_PCT      50
#define SL_BUFFER_PCT    5      // SL buffer = 5% of risk distance
#define DEVIATION        20
#define SHOW_VISUAL      true
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

// -- Partial TP tracking --
static bool   g_partialTPDone  = false;  // Has Part1 been closed?
static double g_partialTPLevel = 0;      // TP1 level to monitor
static double g_partialEntry   = 0;      // Entry level for BE SL
static bool   g_partialIsBuy   = false;  // Direction of partial position

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

   // Normalize lot size to symbol constraints
   double lot = InpLotSize;
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   if(stepLot > 0) lot = MathFloor(lot / stepLot) * stepLot;
   lot = NormalizeDouble(lot, 2);

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
// PARTIAL TP — Close Part1, move SL to breakeven for Part2
// ============================================================================
void CheckPartialTP()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long posType = PositionGetInteger(POSITION_TYPE);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool tpHit = false;
      if(posType == POSITION_TYPE_BUY && bid >= g_partialTPLevel)
         tpHit = true;
      if(posType == POSITION_TYPE_SELL && ask <= g_partialTPLevel)
         tpHit = true;

      if(!tpHit) continue;

      // ── TP1 hit! Close partial volume ──
      double fullVol  = PositionGetDouble(POSITION_VOLUME);
      double closeVol = NormalizeDouble(fullVol * PARTIAL_PCT / 100.0, 2);
      double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double stepLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

      if(closeVol < minLot) closeVol = minLot;
      if(stepLot > 0) closeVol = MathFloor(closeVol / stepLot) * stepLot;
      closeVol = NormalizeDouble(closeVol, 2);

      // Don't close more than available
      if(closeVol >= fullVol) closeVol = fullVol;

      // Close Part1
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = _Symbol;
      req.volume    = closeVol;
      req.deviation = DEVIATION;
      req.magic     = InpMagic;
      req.position  = ticket;
      req.comment   = "MST_MEDIO_TP1";

      if(posType == POSITION_TYPE_BUY)
      {  req.type = ORDER_TYPE_SELL; req.price = bid; }
      else
      {  req.type = ORDER_TYPE_BUY;  req.price = ask; }

      if(!OrderSend(req, res))
      {
         Print("⚠️ Partial close failed. Retcode=", res.retcode);
         continue;
      }
      Print("✅ Partial TP1 closed ", closeVol, " lots. Remaining=", NormalizeDouble(fullVol - closeVol, 2));

      // ── Move SL to breakeven (entry) on remaining position ──
      double remainVol = NormalizeDouble(fullVol - closeVol, 2);
      if(remainVol > 0)
      {
         // Need to re-select position after partial close
         Sleep(200);
         if(PositionSelectByTicket(ticket))
         {
            double entryBE = NormalizePrice(g_partialEntry);
            MqlTradeRequest modReq; MqlTradeResult modRes;
            ZeroMemory(modReq); ZeroMemory(modRes);
            modReq.action   = TRADE_ACTION_SLTP;
            modReq.symbol   = _Symbol;
            modReq.position = ticket;
            modReq.sl       = entryBE;
            modReq.tp       = 0;  // Remove TP — let it run

            if(!OrderSend(modReq, modRes))
               Print("⚠️ Move SL to BE failed. Retcode=", modRes.retcode);
            else
               Print("✅ SL moved to breakeven=", entryBE, " | TP removed → Part2 runs until next signal");
         }
      }

      g_partialTPDone = true;
      break;
   }
}

// ============================================================================
// INIT / DEINIT
// ============================================================================
int OnInit()
{
   string number = StringFormat("%I64d", GetTickCount64());
   g_objPrefix = StringSubstr(number, MathMax(0, StringLen(number) - 4)) + "_MSM_";
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteObjectsByPrefix(g_objPrefix);
}

// ============================================================================
// MAIN TICK HANDLER
// ============================================================================
void OnTick()
{
   // Extend lines on every tick
   if(SHOW_VISUAL && SHOW_BREAK_LINE)
      ExtendActiveLines();

   // ── Partial TP: Monitor TP1 hit on every tick ──
   if(InpPartialTP && !g_partialTPDone && g_partialTPLevel > 0)
      CheckPartialTP();

   // Only process on new bar
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == g_lastBarTime) return;
   g_lastBarTime = currentBarTime;

   int bars = Bars(_Symbol, _Period);
   if(bars < PIVOT_LEN * 2 + 25) return;  // Need enough bars for avg body

   // ================================================================
   // STEP 1: SWING DETECTION (at bar = PIVOT_LEN, the confirmed pivot)
   // ================================================================
   int checkBar = PIVOT_LEN;
   bool isSwH = IsPivotHigh(checkBar, PIVOT_LEN);
   bool isSwL = IsPivotLow(checkBar, PIVOT_LEN);

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
   if(isNewHH && IMPULSE_MULT > 0)
   {
      double avgBody = CalcAvgBody(0, 20);
      int sh0Shift = TimeToShift(g_sh0_time);
      int toBar    = PIVOT_LEN;  // sh1 position
      bool found   = false;
      if(sh0Shift >= 0)
      {
         for(int i = sh0Shift; i >= toBar; i--)
         {
            if(i < 0) continue;
            if(iClose(_Symbol, _Period, i) > g_sh0)
            {
               double body = MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i));
               found = (body >= IMPULSE_MULT * avgBody);
               break;
            }
         }
      }
      if(!found) isNewHH = false;
   }

   if(isNewLL && IMPULSE_MULT > 0)
   {
      double avgBody = CalcAvgBody(0, 20);
      int sl0Shift = TimeToShift(g_sl0_time);
      int toBar    = PIVOT_LEN;
      bool found   = false;
      if(sl0Shift >= 0)
      {
         for(int i = sl0Shift; i >= toBar; i--)
         {
            if(i < 0) continue;
            if(iClose(_Symbol, _Period, i) < g_sl0)
            {
               double body = MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i));
               found = (body >= IMPULSE_MULT * avgBody);
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
      if(BREAK_MULT <= 0)
         rawBreakUp = true;
      else
      {
         double swR = g_sh0 - g_slBeforeSH;
         double brD = g_sh1 - g_sh0;
         if(swR > 0 && brD >= swR * BREAK_MULT)
            rawBreakUp = true;
      }
   }

   if(isNewLL && g_shBeforeSL != EMPTY_VALUE)
   {
      if(BREAK_MULT <= 0)
         rawBreakDown = true;
      else
      {
         double swR = g_shBeforeSL - g_sl0;
         double brD = g_sl0 - g_sl1;
         if(swR > 0 && brD >= swR * BREAK_MULT)
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
         g_pendingState = 0;
      // Entry touch cancel
      else if(g_pendBreakPoint != EMPTY_VALUE && prevLow <= g_pendBreakPoint)
         g_pendingState = 0;
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
         g_pendingState = 0;
      else if(g_pendBreakPoint != EMPTY_VALUE && prevHigh >= g_pendBreakPoint)
         g_pendingState = 0;
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
         for(int i = sh0Shift; i >= 0; i--)
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

         // Retroactive scan: from w1_bar+1 to current bar
         int retroFrom = w1BarShift - 1;
         if(retroFrom < 0) retroFrom = 0;
         for(int i = retroFrom; i >= 0; i--)
         {
            double rH = iHigh(_Symbol, _Period, i);
            double rL = iLow(_Symbol, _Period, i);
            double rC = iClose(_Symbol, _Period, i);

            if(g_pendingState == 1)
            {
               if(g_pendW1Trough == EMPTY_VALUE || rL < g_pendW1Trough)
                  g_pendW1Trough = rL;
               if(g_pendSL != EMPTY_VALUE && rL <= g_pendSL)
               { g_pendingState = 0; break; }
               if(rL <= g_pendBreakPoint)
               { g_pendingState = 0; break; }
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
         for(int i = sl0Shift; i >= 0; i--)
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

         int retroFrom = w1BarShift - 1;
         if(retroFrom < 0) retroFrom = 0;
         for(int i = retroFrom; i >= 0; i--)
         {
            double rH = iHigh(_Symbol, _Period, i);
            double rL = iLow(_Symbol, _Period, i);
            double rC = iClose(_Symbol, _Period, i);

            if(g_pendingState == -1)
            {
               if(g_pendW1Trough == EMPTY_VALUE || rH > g_pendW1Trough)
                  g_pendW1Trough = rH;
               if(g_pendSL != EMPTY_VALUE && rH >= g_pendSL)
               { g_pendingState = 0; break; }
               if(rH >= g_pendBreakPoint)
               { g_pendingState = 0; break; }
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

   if(confirmedSell)
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
   if(SL_BUFFER_PCT > 0 && riskDist > 0)
   {
      double bufferAmt = riskDist * SL_BUFFER_PCT / 100.0;
      if(isBuy)  slBuffered = sl - bufferAmt;
      else       slBuffered = sl + bufferAmt;
   }

   // Calculate TP (Confirm Break: high/low of confirm break candle)
   double tp = isBuy ? waveHigh : waveLow;

   datetime signalTime = iTime(_Symbol, _Period, 1);  // Signal detected on bar 1

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
            DrawTextLabel(tpLbl, now, tp, "TP (Conf)", COL_TP, 7);
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
   datetime lastSig = isBuy ? g_lastBuySignal : g_lastSellSignal;
   if(signalTime > lastSig)
   {
      if(isBuy) g_lastBuySignal = signalTime;
      else      g_lastSellSignal = signalTime;

      // Alert (always on)
      {
         string msg = StringFormat("MST Medio: %s | Entry=%.2f SL=%.2f TP=%.2f | %s",
                                    isBuy ? "BUY" : "SELL",
                                    entry, slBuffered, tp, _Symbol);
         Alert(msg);
         Print("🔔 ", msg);
      }

      // ── Trade ──
      {
         CloseAllPositions();
         DeleteAllPendingOrders();

         // If Partial TP: place order with TP, track for partial close
         if(InpPartialTP)
         {
            g_partialTPDone  = false;
            g_partialTPLevel = tp;
            g_partialEntry   = entry;
            g_partialIsBuy   = isBuy;
         }

         PlaceOrder(isBuy, entry, slBuffered, tp);
      }
   }
}
//+------------------------------------------------------------------+
