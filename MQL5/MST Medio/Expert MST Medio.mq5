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
//|   7. Max risk % safety filter (skip trade if risk > limit)       |
//|   8. Auto lot normalization (min/max/step)                       |
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
input double InpMaxRiskPct   = 2.0;     // Max Risk % per trade (0=no limit)
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
static bool   g_partialTPDone   = false;  // Has partial TP been handled?
static ulong  g_part1Ticket     = 0;      // Part1 ticket (hedging: has TP — broker closes)
static ulong  g_part2Ticket     = 0;      // Part2 ticket (hedging: no TP — EA manages)
static double g_partialEntry    = 0;      // Entry level for BE SL (fallback)
static bool   g_partialIsBuy    = false;  // Direction of partial position
static double g_partialTPLevel  = 0;      // TP price level (for netting: EA monitors & closes)
static double g_partialCloseVol = 0;      // Volume to close at TP (netting mode)
static bool   g_isHedgingAccount = false; // Detected in OnInit

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

// PlaceOrderEx: Same as PlaceOrder but with explicit lot and comment, returns ticket (0 on failure)
ulong PlaceOrderEx(const bool isBuy, const double entry, const double sl, const double tp,
                   const double lotSize, const string comment)
{
   double entryN = NormalizePrice(entry);
   double slN    = NormalizePrice(sl);
   double tpN    = (tp > 0) ? NormalizePrice(tp) : 0;
   double lot    = lotSize;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Validate SL
   if(isBuy && slN >= entryN)
   { Print("Invalid BUY SL. SL=", slN, " >= Entry=", entryN); return 0; }
   if(!isBuy && slN <= entryN)
   { Print("Invalid SELL SL. SL=", slN, " <= Entry=", entryN); return 0; }

   ENUM_ORDER_TYPE type;
   if(isBuy)
   {
      if(entryN < ask)      type = ORDER_TYPE_BUY_LIMIT;
      else if(entryN > ask) type = ORDER_TYPE_BUY_STOP;
      else
      {
         MqlTradeRequest req; MqlTradeResult res;
         ZeroMemory(req); ZeroMemory(res);
         req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol;
         req.volume = lot; req.type = ORDER_TYPE_BUY;
         req.price = ask; req.sl = slN; req.tp = tpN;
         req.magic = InpMagic; req.deviation = DEVIATION;
         req.comment = comment;
         if(!OrderSend(req, res))
         { Print("OrderSend BUY market failed. Retcode=", res.retcode); return 0; }
         Print("✅ BUY market [", comment, "]. Ticket=", res.order, " Lot=", lot,
               " Entry=", ask, " SL=", slN, " TP=", tpN);
         return res.order;
      }
   }
   else
   {
      if(entryN > bid)      type = ORDER_TYPE_SELL_LIMIT;
      else if(entryN < bid) type = ORDER_TYPE_SELL_STOP;
      else
      {
         MqlTradeRequest req; MqlTradeResult res;
         ZeroMemory(req); ZeroMemory(res);
         req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol;
         req.volume = lot; req.type = ORDER_TYPE_SELL;
         req.price = bid; req.sl = slN; req.tp = tpN;
         req.magic = InpMagic; req.deviation = DEVIATION;
         req.comment = comment;
         if(!OrderSend(req, res))
         { Print("OrderSend SELL market failed. Retcode=", res.retcode); return 0; }
         Print("✅ SELL market [", comment, "]. Ticket=", res.order, " Lot=", lot,
               " Entry=", bid, " SL=", slN, " TP=", tpN);
         return res.order;
      }
   }

   MqlTradeRequest req; MqlTradeResult res;
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
   req.comment   = comment;

   if(!OrderSend(req, res))
   {
      Print("OrderSend pending [", comment, "] failed. Retcode=", res.retcode);
      return 0;
   }
   Print("✅ Pending ", (isBuy ? "BUY" : "SELL"), " [", comment, "]",
         " Ticket=", res.order, " Lot=", lot, " Entry=", entryN, " SL=", slN, " TP=", tpN);
   return res.order;
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
// PARTIAL TP — Detect Part1 closed by broker, move SL to breakeven for Part2
// ============================================================================
void CheckPartialTP()
{
   if(g_isHedgingAccount)
      CheckPartialTP_Hedging();
   else
      CheckPartialTP_Netting();
}

// ── Hedging mode: 2 separate positions, Part1 has TP (broker closes) ──
void CheckPartialTP_Hedging()
{
   // Check if Part1 is still alive
   bool part1Alive = false;
   if(g_part1Ticket > 0)
   {
      // Check as open position
      if(PositionSelectByTicket(g_part1Ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
            part1Alive = true;
      }
      // Also check as pending order (not yet filled)
      if(!part1Alive)
      {
         if(OrderSelect(g_part1Ticket))
         {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
               (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic)
               part1Alive = true;  // Still pending — not filled yet
         }
      }
   }

   if(part1Alive) return;  // Part1 still exists — nothing to do

   // ── Part1 is gone → verify it was TP (not SL) by checking Part2 still exists ──
   bool part2Alive = false;
   if(g_part2Ticket > 0 && PositionSelectByTicket(g_part2Ticket))
   {
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         part2Alive = true;
   }

   if(!part2Alive)
   {
      // Both parts gone — likely SL hit or manual close, not TP
      Print("ℹ️ Part1 & Part2 both gone (SL hit or manual close). ticket1=", g_part1Ticket, " ticket2=", g_part2Ticket);
      g_partialTPDone = true;
      g_part1Ticket   = 0;
      g_part2Ticket   = 0;
      return;
   }

   // Part1 gone but Part2 alive → Part1 closed at TP
   Print("✅ Part1 (ticket=", g_part1Ticket, ") closed by broker at TP");

   // Move SL of Part2 to breakeven using ACTUAL fill price (Bug #5 fix)
   double entryBE = NormalizePrice(PositionGetDouble(POSITION_PRICE_OPEN));
   double currentSL = PositionGetDouble(POSITION_SL);

   // Only move SL if not already at BE (avoid repeated modifications)
   if(MathAbs(currentSL - entryBE) > _Point)
   {
      MqlTradeRequest modReq; MqlTradeResult modRes;
      ZeroMemory(modReq); ZeroMemory(modRes);
      modReq.action   = TRADE_ACTION_SLTP;
      modReq.symbol   = _Symbol;
      modReq.position = g_part2Ticket;
      modReq.sl       = entryBE;
      modReq.tp       = 0;  // No TP — let it run

      if(!OrderSend(modReq, modRes))
      {
         Print("⚠️ Move SL to BE failed. Retcode=", modRes.retcode, " — will retry next tick");
         return;  // Don't mark done — retry next tick
      }
      Print("✅ SL moved to breakeven=", entryBE, " | Part2 runs until next signal");
   }

   g_partialTPDone = true;
   g_part1Ticket   = 0;
}

// ── Netting mode: 1 position (full lot, no TP), EA monitors TP level ──
void CheckPartialTP_Netting()
{
   // Find our position
   if(!PositionSelect(_Symbol))
   {
      // Position gone (SL hit or manual close) before TP was reached
      Print("ℹ️ Netting: Position gone before TP reached (SL hit or manual close)");
      g_partialTPDone = true;
      g_part1Ticket   = 0;
      g_part2Ticket   = 0;
      return;
   }
   if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
   {
      // Position exists but not ours — treat as gone
      Print("ℹ️ Netting: Position magic mismatch — not our position");
      g_partialTPDone = true;
      g_part1Ticket   = 0;
      g_part2Ticket   = 0;
      return;
   }

   double posVol   = PositionGetDouble(POSITION_VOLUME);
   double posOpen  = PositionGetDouble(POSITION_PRICE_OPEN);
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double tpLevel  = g_partialTPLevel;

   // Check if price has reached TP level
   bool tpReached = false;
   if(g_partialIsBuy && bid >= tpLevel)  tpReached = true;
   if(!g_partialIsBuy && ask <= tpLevel) tpReached = true;

   if(!tpReached) return;  // TP not reached yet

   Print("✅ Netting: Price reached TP level=", tpLevel, " | Closing ", g_partialCloseVol, " of ", posVol, " lots");

   // Close partial volume
   double closeVol = MathMin(g_partialCloseVol, posVol);
   double remainVol = NormalizeDouble(posVol - closeVol, 2);

   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = closeVol;
   req.deviation = DEVIATION;
   req.magic     = InpMagic;
   req.comment   = "MST_MEDIO_PARTIAL_CLOSE";

   if(g_partialIsBuy)
   {  req.type = ORDER_TYPE_SELL; req.price = bid; }
   else
   {  req.type = ORDER_TYPE_BUY;  req.price = ask; }

   // On netting, specify the position ticket
   ulong posTicket = PositionGetInteger(POSITION_TICKET);
   req.position = posTicket;

   if(!OrderSend(req, res))
   {
      Print("⚠️ Netting partial close failed. Retcode=", res.retcode, " — will retry next tick");
      return;  // Don't mark done — retry
   }
   Print("✅ Netting: Closed ", closeVol, " lots at TP. Remaining=", remainVol);

   // Move SL to breakeven on remaining position (if any left)
   if(remainVol > 0)
   {
      // Re-select position after partial close
      Sleep(100);  // Brief pause for server to process
      if(PositionSelect(_Symbol) &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
      {
         // Use actual fill price for BE (Bug #5 fix)
         double entryBE = NormalizePrice(PositionGetDouble(POSITION_PRICE_OPEN));
         double currentSL = PositionGetDouble(POSITION_SL);

         if(MathAbs(currentSL - entryBE) > _Point)
         {
            MqlTradeRequest modReq; MqlTradeResult modRes;
            ZeroMemory(modReq); ZeroMemory(modRes);
            modReq.action   = TRADE_ACTION_SLTP;
            modReq.symbol   = _Symbol;
            modReq.position = PositionGetInteger(POSITION_TICKET);
            modReq.sl       = entryBE;
            modReq.tp       = 0;

            if(!OrderSend(modReq, modRes))
            {
               Print("⚠️ Netting: Move SL to BE failed. Retcode=", modRes.retcode);
               // Still mark done to avoid repeated partial closes
            }
            else
               Print("✅ Netting: SL moved to breakeven=", entryBE);
         }
      }
   }

   g_partialTPDone = true;
   g_part1Ticket   = 0;
   g_part2Ticket   = 0;
}

// ============================================================================
// INIT / DEINIT
// ============================================================================
int OnInit()
{
   string number = StringFormat("%I64d", GetTickCount64());
   g_objPrefix = StringSubstr(number, MathMax(0, StringLen(number) - 4)) + "_MSM_";

   // Detect account type: hedging or netting
   ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   g_isHedgingAccount = (marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   Print("ℹ️ Account margin mode: ", EnumToString(marginMode),
         " → ", g_isHedgingAccount ? "HEDGING" : "NETTING", " mode");

   // Reset partial TP state on init
   g_partialTPDone   = false;
   g_part1Ticket     = 0;
   g_part2Ticket     = 0;
   g_partialEntry    = 0;
   g_partialIsBuy    = false;
   g_partialTPLevel  = 0;
   g_partialCloseVol = 0;

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

   // ── Partial TP: Monitor Part1 closed by broker → move SL Part2 to BE ──
   if(InpPartialTP && !g_partialTPDone && g_part1Ticket > 0)
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
      double avgBody = CalcAvgBody(1, 20);
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
      double avgBody = CalcAvgBody(1, 20);
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
   if(SL_BUFFER_PCT > 0 && riskDist > 0)
   {
      double bufferAmt = riskDist * SL_BUFFER_PCT / 100.0;
      if(isBuy)  slBuffered = sl - bufferAmt;
      else       slBuffered = sl + bufferAmt;
   }

   // Calculate TP (Confirm Break: high/low of confirm break candle)
   double tp = isBuy ? waveHigh : waveLow;

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

      // Normalize lot to symbol constraints
      double totalLot = InpLotSize;
      double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double stepLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(totalLot < minLot) totalLot = minLot;
      if(totalLot > maxLot) totalLot = maxLot;
      if(stepLot > 0) totalLot = MathFloor(totalLot / stepLot) * stepLot;
      totalLot = NormalizeDouble(totalLot, 2);

      // Max risk check — skip trade if risk exceeds limit
      if(!CheckMaxRisk(entry, slBuffered, totalLot))
         return;

      if(InpPartialTP)
      {
         // Split lot into Part1 (with TP) and Part2 (no TP)

         // Ensure total lot >= 2x minLot for splitting
         if(totalLot < minLot * 2)
         {
            totalLot = minLot * 2;
            Print("ℹ️ Partial TP: lot adjusted to ", totalLot, " (2x minLot=", minLot, ")");
         }
         if(totalLot > maxLot) totalLot = maxLot;

         double part1Lot = NormalizeDouble(totalLot * PARTIAL_PCT / 100.0, 2);
         if(part1Lot < minLot) part1Lot = minLot;
         if(stepLot > 0) part1Lot = MathFloor(part1Lot / stepLot) * stepLot;
         part1Lot = NormalizeDouble(part1Lot, 2);

         double part2Lot = NormalizeDouble(totalLot - part1Lot, 2);
         if(part2Lot < minLot) part2Lot = minLot;
         if(stepLot > 0) part2Lot = MathFloor(part2Lot / stepLot) * stepLot;
         part2Lot = NormalizeDouble(part2Lot, 2);

         // Reset partial TP state
         g_partialTPDone  = false;
         g_partialEntry   = entry;
         g_partialIsBuy   = isBuy;
         g_partialTPLevel = tp;
         g_partialCloseVol = part1Lot;
         g_part1Ticket    = 0;
         g_part2Ticket    = 0;

         if(g_isHedgingAccount)
         {
            // Hedging: 2 separate positions — Part1 with TP (broker closes), Part2 without TP
            g_part1Ticket = PlaceOrderEx(isBuy, entry, slBuffered, tp, part1Lot, "MST_MEDIO_TP1");
            g_part2Ticket = PlaceOrderEx(isBuy, entry, slBuffered, 0, part2Lot, "MST_MEDIO_TP2");

            if(g_part1Ticket == 0 || g_part2Ticket == 0)
               Print("⚠️ Partial TP [Hedging]: Part1 ticket=", g_part1Ticket, " Part2 ticket=", g_part2Ticket);
            else
               Print("✅ Partial TP [Hedging]: Part1=", part1Lot, " lots (TP=", tp, ") | Part2=", part2Lot, " lots (no TP)");
         }
         else
         {
            // Netting: 1 position (full lot, no TP) — EA monitors TP level and closes partial
            g_part1Ticket = PlaceOrderEx(isBuy, entry, slBuffered, 0, totalLot, "MST_MEDIO_PARTIAL");
            g_part2Ticket = 0;  // Not used in netting mode

            if(g_part1Ticket == 0)
               Print("⚠️ Partial TP [Netting]: Order failed");
            else
               Print("✅ Partial TP [Netting]: ", totalLot, " lots (EA monitors TP=", tp, ", will close ", part1Lot, " lots at TP)");
         }
      }
      else
      {
         PlaceOrder(isBuy, entry, slBuffered, tp);
      }
   }
}
//+------------------------------------------------------------------+
