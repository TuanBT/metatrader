//+------------------------------------------------------------------+
//|                                                 Exness Order.mq5 |
//|         Exness-style order + management EA (v1.06)               |
//|         Trade tay + Trail/BE/Auto TP management                 |
//+------------------------------------------------------------------+
#property copyright "Exness Order 1.05"
#property version   "1.05"
#property strict

// ═══════════════════════════════════════════════════════════════════
// INPUTS
// ═══════════════════════════════════════════════════════════════════
enum ENUM_TRAIL_MODE
{
   TRAIL_NONE      = 0,  // No trail
   TRAIL_CLOSE     = 1,  // Close (bar[1] wick)
   TRAIL_SWING     = 2,  // Swing (swing low/high)
};

input double InpRiskDollar   = 10;       // Risk $ per trade
input int    InpATRPeriod    = 14;       // ATR period (for Trail/BE/TP)
input ENUM_TIMEFRAMES InpATRTF = PERIOD_CURRENT; // ATR timeframe
input int    InpTrailLookback = 20;      // Swing lookback bars (Swing mode)
input ulong  InpMagic        = 202503;   // Magic number
input int    InpDeviation    = 20;       // Max slippage (points)

// ═══════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════
#define PREFIX "exo_"

// Panel objects
#define OBJ_BG          PREFIX "bg"
#define OBJ_TITLE       PREFIX "title"
#define OBJ_RISK_LBL    PREFIX "risk_lbl"
#define OBJ_RISK_EDT    PREFIX "risk_edt"
#define OBJ_RISK_MINUS  PREFIX "risk_minus"
#define OBJ_RISK_PLUS   PREFIX "risk_plus"
#define OBJ_SEP1        PREFIX "sep1"
#define OBJ_INFO1       PREFIX "info1"
#define OBJ_INFO2       PREFIX "info2"
#define OBJ_INFO3       PREFIX "info3"
#define OBJ_SEP2        PREFIX "sep2"
#define OBJ_BUY_BTN     PREFIX "buy_btn"
#define OBJ_SELL_BTN    PREFIX "sell_btn"
#define OBJ_BUY_PND     PREFIX "buy_pnd"
#define OBJ_SELL_PND    PREFIX "sell_pnd"
#define OBJ_EXECUTE     PREFIX "execute"
#define OBJ_CANCEL      PREFIX "cancel"
// Management buttons
#define OBJ_SEP3        PREFIX "sep3"
#define OBJ_TM_CLOSE    PREFIX "tm_close"
#define OBJ_TM_SWING    PREFIX "tm_swing"
#define OBJ_BE_BTN      PREFIX "be_btn"
#define OBJ_AUTOTP_BTN  PREFIX "autotp_btn"
#define OBJ_CLOSE_BTN   PREFIX "close_btn"

// Chart line objects
#define OBJ_ENTRY_LINE  PREFIX "entry"
#define OBJ_SL_LINE     PREFIX "sl"
#define OBJ_SL_ACTIVE   PREFIX "sl_active"

// Price labels (OBJ_LABEL anchored to Y from price)
#define OBJ_ENTRY_TAG   PREFIX "entry_tag"
#define OBJ_SL_TAG      PREFIX "sl_tag"
#define OBJ_SL_ACT_TAG  PREFIX "sl_act_tag"
#define OBJ_WARN_LBL    PREFIX "warn_lbl"

// Colors
#define COL_BG        C'30,33,40'
#define COL_BORDER    C'55,60,75'
#define COL_TEXT      C'200,205,220'
#define COL_DIM       C'140,145,165'
#define COL_WHITE     C'230,235,250'
#define COL_BUY       C'0,150,80'
#define COL_SELL      C'200,50,50'
#define COL_ENTRY     C'255,165,0'
#define COL_SL        C'230,60,60'
#define COL_PROFIT    C'0,190,90'
#define COL_LOSS      C'230,60,60'
#define COL_LOCK_UP   C'0,130,75'
#define COL_LOCK_DN   C'170,55,55'
#define COL_EXEC      C'0,120,200'
#define COL_CANCEL_BG C'80,80,100'
#define COL_EDIT_BG   C'40,43,55'
#define COL_EDIT_BD   C'65,70,90'
#define COL_ON        C'0,120,70'
#define COL_OFF       C'60,60,85'
#define COL_WARN      C'220,180,40'

// Layout
#define PX 20
#define PY 50
#define PW 210
#define IX 28
#define IW 195

#define FONT_MAIN "Segoe UI"
#define FONT_BOLD "Segoe UI Semibold"
#define FONT_MONO "Consolas"

// ═══════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════
int    g_atrHandle    = INVALID_HANDLE;
double g_cachedATR    = 0;
double g_riskMoney    = 0;
int    g_orderMode    = 0;  // 0=none, 1=buy pending, 2=sell pending
bool   g_linesActive  = false;

// Position state
bool   g_hasPos       = false;
bool   g_isBuy        = true;
double g_entryPx      = 0;
double g_currentSL    = 0;
double g_origSL       = 0;

// Management toggles
ENUM_TRAIL_MODE g_trailRef = TRAIL_NONE;
bool   g_beEnabled    = false;
bool   g_beReached    = false;
bool   g_autoTPEnabled = false;
bool   g_tp1Hit       = false;
double g_tpDist       = 0;

// ═══════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════
double NormPrice(double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0) tick = _Point;
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
}

double NormLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathFloor(lot / step) * step;
   lot = MathMax(lot, minL);
   lot = MathMin(lot, maxL);
   return NormalizeDouble(lot, 8);
}

double PipSize()
{
   return (_Digits == 3 || _Digits == 5) ? 10 * _Point : _Point;
}

double CalcLot(double slDist)
{
   if(slDist <= 0 || g_riskMoney <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSz <= 0 || tickVal <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double riskPerLot = (slDist / tickSz) * tickVal;
   double lot = g_riskMoney / riskPerLot;
   return NormLot(lot);
}

double CalcMoney(double lot, double dist)
{
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSz <= 0 || tickVal <= 0 || dist <= 0) return 0;
   return lot * (dist / tickSz) * tickVal;
}

bool IsBuyMode() { return (g_orderMode == 1); }

// ═══════════════════════════════════════════════════════════════════
// POSITION FUNCTIONS
// ═══════════════════════════════════════════════════════════════════
bool HasOwnPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }
   return false;
}

double GetPositionPnL()
{
   double pnl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      pnl += PositionGetDouble(POSITION_PROFIT)
           + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

double GetTotalLots()
{
   double lots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      lots += PositionGetDouble(POSITION_VOLUME);
   }
   return lots;
}

double GetAvgEntry()
{
   double sumPV = 0, sumV = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      double v = PositionGetDouble(POSITION_VOLUME);
      sumPV += PositionGetDouble(POSITION_PRICE_OPEN) * v;
      sumV  += v;
   }
   return (sumV > 0) ? sumPV / sumV : 0;
}

double GetLockedPnL()
{
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSz == 0 || tickVal == 0) return 0;

   double lockedPnL = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double lot   = PositionGetDouble(POSITION_VOLUME);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double swap  = PositionGetDouble(POSITION_SWAP);
      long   type  = PositionGetInteger(POSITION_TYPE);
      if(sl == 0) continue;

      double dist = (type == POSITION_TYPE_BUY) ? (sl - entry) : (entry - sl);
      lockedPnL += lot * (dist / tickSz) * tickVal + swap;
   }
   return lockedPnL;
}

void SyncFromPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      g_isBuy     = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      g_entryPx   = PositionGetDouble(POSITION_PRICE_OPEN);
      g_currentSL = PositionGetDouble(POSITION_SL);
      if(g_origSL == 0) g_origSL = g_currentSL;
      return;
   }
}

// ═══════════════════════════════════════════════════════════════════
// SL MODIFICATION
// ═══════════════════════════════════════════════════════════════════
void ModifySL(double newSL)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      MqlTradeRequest rq;
      MqlTradeResult  rs;
      ZeroMemory(rq);
      ZeroMemory(rs);

      rq.action   = TRADE_ACTION_SLTP;
      rq.symbol   = _Symbol;
      rq.position = t;
      rq.sl       = newSL;
      rq.tp       = PositionGetDouble(POSITION_TP);

      if(OrderSend(rq, rs))
      {
         g_currentSL = newSL;
         Print("[ExO] SL -> ", DoubleToString(newSL, _Digits));
      }
      else
         Print("[ExO] Modify FAILED rc=", rs.retcode);
   }
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      MqlTradeRequest rq;
      MqlTradeResult  rs;
      ZeroMemory(rq);
      ZeroMemory(rs);

      bool isBuyPos = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      rq.action    = TRADE_ACTION_DEAL;
      rq.symbol    = _Symbol;
      rq.position  = t;
      rq.volume    = PositionGetDouble(POSITION_VOLUME);
      rq.type      = isBuyPos ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      rq.price     = isBuyPos ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                               : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      rq.deviation = InpDeviation;
      rq.magic     = InpMagic;

      if(OrderSend(rq, rs))
         Print("[ExO] Closed #", t);
      else
         Print("[ExO] Close FAIL rc=", rs.retcode);
   }
}

bool PartialClose50()
{
   ulong   tickets[];
   double  lots[], profits[];
   int n = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      ArrayResize(tickets, n + 1);
      ArrayResize(lots,    n + 1);
      ArrayResize(profits, n + 1);
      tickets[n] = t;
      lots[n]    = PositionGetDouble(POSITION_VOLUME);
      profits[n] = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      n++;
   }
   if(n == 0) return false;

   double totalLots = 0;
   for(int i = 0; i < n; i++) totalLots += lots[i];

   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double closeLots = MathFloor(totalLots * 0.5 / lotStep) * lotStep;
   if(closeLots < minLot) closeLots = minLot;
   if(closeLots >= totalLots) return false;

   // Sort by profit descending
   for(int i = 0; i < n - 1; i++)
      for(int j = 0; j < n - 1 - i; j++)
         if(profits[j] < profits[j + 1])
         {
            ulong  tt = tickets[j]; tickets[j] = tickets[j+1]; tickets[j+1] = tt;
            double tl = lots[j];    lots[j]    = lots[j+1];    lots[j+1]    = tl;
            double tp = profits[j]; profits[j] = profits[j+1]; profits[j+1] = tp;
         }

   double remaining = closeLots;
   bool anyClose = false;

   for(int i = 0; i < n && remaining >= minLot; i++)
   {
      if(!PositionSelectByTicket(tickets[i])) continue;
      double vol = MathMin(lots[i], remaining);
      vol = MathFloor(vol / lotStep) * lotStep;
      if(vol < minLot) continue;

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);

      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = _Symbol;
      req.position  = tickets[i];
      req.volume    = vol;
      req.type      = g_isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price     = g_isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                               : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      req.deviation = InpDeviation;
      req.magic     = InpMagic;

      if(OrderSend(req, res))
      {
         Print("[ExO] TP: Closed ", vol, " from #", tickets[i]);
         remaining -= vol;
         anyClose = true;
      }
   }
   return anyClose;
}

// ═══════════════════════════════════════════════════════════════════
// TRAIL / BE / AUTO TP LOGIC
// ═══════════════════════════════════════════════════════════════════
void ManageTrailBE()
{
   if(!g_hasPos) return;
   if(g_trailRef == TRAIL_NONE && !g_beEnabled) return;
   if(g_cachedATR <= 0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double avgEntry = GetAvgEntry();
   if(avgEntry <= 0) return;

   double moveFromEntry = g_isBuy ? (bid - avgEntry) : (avgEntry - ask);
   double fullATR = g_cachedATR;

   // ── BE Phase 1: Move SL to breakeven ──
   if(g_beEnabled && !g_beReached)
   {
      if(moveFromEntry >= fullATR)
      {
         double spread = ask - bid;
         double buffer = spread + _Point;
         double beSL = g_isBuy ? NormPrice(avgEntry + buffer)
                                : NormPrice(avgEntry - buffer);

         bool advance = g_isBuy ? (beSL > g_currentSL) : (beSL < g_currentSL);
         if(advance)
         {
            if(g_isBuy && beSL >= bid) return;
            if(!g_isBuy && beSL <= ask) return;
            g_beReached = true;
            Print("[ExO] BE reached: SL -> ", DoubleToString(beSL, _Digits));
            ModifySL(beSL);
         }
         else
         {
            g_beReached = true;
         }
      }
      return;
   }

   // ── Trail Close / Swing: per-bar trailing ──
   if(g_trailRef == TRAIL_CLOSE || g_trailRef == TRAIL_SWING)
   {
      if(g_beEnabled && !g_beReached) return;
      if(!g_beEnabled && moveFromEntry < fullATR) return;

      double minDist = fullATR * 0.5;
      double newSL = 0;

      switch(g_trailRef)
      {
         case TRAIL_CLOSE:
         {
            if(g_isBuy)
            {
               newSL = NormPrice(iLow(_Symbol, _Period, 1));
               if((bid - newSL) < minDist) return;
            }
            else
            {
               newSL = NormPrice(iHigh(_Symbol, _Period, 1));
               if((newSL - ask) < minDist) return;
            }
            break;
         }
         case TRAIL_SWING:
         {
            int N = InpTrailLookback;
            if(N < 5) N = 20;
            double swingPrice = 0;
            int pivotWidth = 3;  // check 3 bars each side minimum
            double promMin = fullATR * 0.3;  // swing must protrude 0.3×ATR from neighbors avg

            if(g_isBuy)
            {
               // Find real swing low: must be lower than 'pivotWidth' bars on each side
               // AND protrude significantly (prominence check)
               for(int i = pivotWidth; i <= N; i++)
               {
                  double lo = iLow(_Symbol, _Period, i);
                  bool isSwing = true;
                  double sumNeighbors = 0;
                  int cnt = 0;
                  for(int j = 1; j <= pivotWidth; j++)
                  {
                     if(iLow(_Symbol, _Period, i - j) <= lo) { isSwing = false; break; }
                     if(iLow(_Symbol, _Period, i + j) <= lo) { isSwing = false; break; }
                     sumNeighbors += iLow(_Symbol, _Period, i - j);
                     sumNeighbors += iLow(_Symbol, _Period, i + j);
                     cnt += 2;
                  }
                  if(!isSwing) continue;
                  // Prominence: avg neighbor lows must be above this low by promMin
                  double avgL = sumNeighbors / cnt;
                  if(avgL - lo < promMin) continue;
                  swingPrice = lo;
                  break;
               }
               if(swingPrice <= 0) return;
               newSL = NormPrice(swingPrice);
               if((bid - newSL) < minDist) return;
            }
            else
            {
               // Find real swing high: must be higher than 'pivotWidth' bars on each side
               // AND protrude significantly (prominence check)
               for(int i = pivotWidth; i <= N; i++)
               {
                  double hi = iHigh(_Symbol, _Period, i);
                  bool isSwing = true;
                  double sumNeighbors = 0;
                  int cnt = 0;
                  for(int j = 1; j <= pivotWidth; j++)
                  {
                     if(iHigh(_Symbol, _Period, i - j) >= hi) { isSwing = false; break; }
                     if(iHigh(_Symbol, _Period, i + j) >= hi) { isSwing = false; break; }
                     sumNeighbors += iHigh(_Symbol, _Period, i - j);
                     sumNeighbors += iHigh(_Symbol, _Period, i + j);
                     cnt += 2;
                  }
                  if(!isSwing) continue;
                  double avgH = sumNeighbors / cnt;
                  if(hi - avgH < promMin) continue;
                  swingPrice = hi;
                  break;
               }
               if(swingPrice <= 0) return;
               newSL = NormPrice(swingPrice);
               if((newSL - ask) < minDist) return;
            }
            break;
         }
         default: return;
      }

      if(newSL <= 0) return;
      bool advance = g_isBuy ? (newSL > g_currentSL) : (newSL < g_currentSL);
      if(!advance) return;
      if(g_isBuy && newSL >= bid) return;
      if(!g_isBuy && newSL <= ask) return;

      string mName = (g_trailRef == TRAIL_CLOSE) ? "Close" : "Swing";
      Print("[ExO] Trail ", mName, ": SL -> ", DoubleToString(newSL, _Digits));
      ModifySL(newSL);
   }
}

void ManageAutoTP()
{
   if(!g_autoTPEnabled || !g_hasPos || g_tp1Hit) return;
   if(g_tpDist <= 0) return;

   double avgEntry = GetAvgEntry();
   if(avgEntry <= 0) return;

   double cur = g_isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double moveFromEntry = g_isBuy ? (cur - avgEntry) : (avgEntry - cur);

   if(moveFromEntry >= g_tpDist)
   {
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double totalLot = GetTotalLots();
      if(totalLot <= minLot) return;

      Print("[ExO] Auto TP hit at ", DoubleToString(cur, _Digits));
      if(PartialClose50())
      {
         g_tp1Hit = true;
         Print("[ExO] 50% closed at TP1");
      }
   }
}

// ═══════════════════════════════════════════════════════════════════
// GUI BUILDERS
// ═══════════════════════════════════════════════════════════════════
void MakeRect(string name, int x, int y, int w, int h, color clrBg, color clrBd)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrBg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBd);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void MakeLabel(string name, int x, int y, string text, color clr, int fontSize, string font = FONT_MAIN)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void MakeButton(string name, int x, int y, int w, int h,
                string text, color clrTxt, color clrBg, int fontSize, string font = FONT_BOLD)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrTxt);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrBg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBg);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void MakeEdit(string name, int x, int y, int w, int h,
              string text, color clrTxt, color clrBg, color clrBd)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, FONT_MONO);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrTxt);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrBg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBd);
   ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void HideObject(string name)
{
   if(ObjectFind(0, name) >= 0)
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
}

void ShowObject(string name)
{
   if(ObjectFind(0, name) >= 0)
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

// Price tag label (positioned at price level, right side of chart)
void MakePriceTag(string name, double price, string text, color clrTxt, color clrBg)
{
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int x = 0, y = 0;
   datetime t = 0;
   double p = 0;
   // Convert price to pixel Y
   ChartTimePriceToXY(0, 0, TimeCurrent(), price, x, y);
   // Position label at right side, offset from price line objects
   int tagX = chartW - 280;
   int tagY = y - 10;

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, tagX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, tagY);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetString (0, name, OBJPROP_FONT, FONT_MONO);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrTxt);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

// ═══════════════════════════════════════════════════════════════════
// PANEL CREATION
// ═══════════════════════════════════════════════════════════════════
void CreatePanel()
{
   int y = PY;
   MakeRect(OBJ_BG, PX, PY, PW, 400, COL_BG, COL_BORDER);

   MakeLabel(OBJ_TITLE, IX, y + 6, "Exness Order v1.06", COL_WHITE, 11, FONT_BOLD);
   y += 28;

   // Risk row
   MakeLabel(OBJ_RISK_LBL, IX, y + 3, "Risk $", COL_DIM, 9);
   MakeEdit(OBJ_RISK_EDT, IX + 50, y, 65, 22,
            IntegerToString((int)g_riskMoney), COL_WHITE, COL_EDIT_BG, COL_EDIT_BD);
   MakeButton(OBJ_RISK_MINUS, IX + 118, y, 28, 22, "-", COL_WHITE, C'80,40,40', 10, FONT_BOLD);
   MakeButton(OBJ_RISK_PLUS,  IX + 149, y, 28, 22, "+", COL_WHITE, C'40,80,40', 10, FONT_BOLD);
   y += 28;

   // INFO section
   MakeRect(OBJ_SEP1, IX, y, IW, 1, COL_BORDER, COL_BORDER);
   y += 6;
   MakeLabel(OBJ_INFO1, IX, y, " ", COL_WHITE, 11, FONT_BOLD);
   y += 20;
   MakeLabel(OBJ_INFO2, IX, y, " ", COL_DIM, 8, FONT_MONO);
   y += 14;
   MakeLabel(OBJ_INFO3, IX, y, " ", COL_DIM, 8, FONT_MONO);
   y += 16;
   MakeLabel(OBJ_WARN_LBL, IX, y, " ", COL_SL, 8, FONT_MONO);
   HideObject(OBJ_WARN_LBL);
   y += 16;

   // TRADE section
   MakeRect(OBJ_SEP2, IX, y, IW, 1, COL_BORDER, COL_BORDER);
   y += 6;
   int bw = (IW - 6) / 2;
   MakeButton(OBJ_BUY_BTN,  PX + 5, y, bw, 36, "BUY", COL_WHITE, COL_BUY, 11);
   MakeButton(OBJ_SELL_BTN, PX + 5 + bw + 6, y, bw, 36, "SELL", COL_WHITE, COL_SELL, 11);
   y += 40;
   MakeButton(OBJ_BUY_PND,  PX + 5, y, bw, 28, "Buy Pending", COL_WHITE, C'0,90,55', 8);
   MakeButton(OBJ_SELL_PND, PX + 5 + bw + 6, y, bw, 28, "Sell Pending", COL_WHITE, C'150,40,40', 8);
   y += 32;
   MakeButton(OBJ_EXECUTE, PX + 5, y, IW, 32, "PLACE ORDER", COL_WHITE, COL_EXEC, 10, FONT_BOLD);
   y += 36;
   MakeButton(OBJ_CANCEL, PX + 5, y, IW, 24, "Cancel", COL_DIM, COL_CANCEL_BG, 8);
   y += 30;

   // MANAGEMENT section
   MakeRect(OBJ_SEP3, IX, y, IW, 1, COL_BORDER, COL_BORDER);
   y += 6;
   int mw3 = (IW - 12) / 3;
   MakeButton(OBJ_TM_CLOSE, PX + 5, y, mw3, 28, "Close", COL_DIM, COL_OFF, 8);
   MakeButton(OBJ_TM_SWING, PX + 5 + mw3 + 6, y, mw3, 28, "Swing", COL_DIM, COL_OFF, 8);
   MakeButton(OBJ_BE_BTN, PX + 5 + 2*(mw3 + 6), y, mw3, 28, "BE", COL_DIM, COL_OFF, 8);
   y += 32;
   MakeButton(OBJ_AUTOTP_BTN, PX + 5, y, IW, 28, "Auto TP: OFF", COL_DIM, COL_OFF, 8);
   y += 32;
   MakeButton(OBJ_CLOSE_BTN, PX + 5, y, IW, 32, "CLOSE POSITION", COL_WHITE, COL_SELL, 10, FONT_BOLD);
   y += 36;

   // Tooltips
   ObjectSetString(0, OBJ_TM_CLOSE, OBJPROP_TOOLTIP,
      "Trail CLOSE: SL = bar[1] wick\n"
      "BUY: SL = Low[1] | SELL: SL = High[1]\n"
      "Min distance: 0.5 x ATR\n"
      "Click again to turn OFF");
   ObjectSetString(0, OBJ_TM_SWING, OBJPROP_TOOLTIP,
      "Trail SWING: SL = real swing low/high\n"
      "Must stand out 0.3×ATR from neighbors\n"
      "BUY: SL = Swing Low | SELL: SL = Swing High\n"
      "Lookback: " + IntegerToString(InpTrailLookback) + " bars\n"
      "Click again to turn OFF");
   ObjectSetString(0, OBJ_BE_BTN, OBJPROP_TOOLTIP,
      "BE: Move SL to breakeven at >= 1 ATR profit\n"
      "Combine with Close/Swing: BE first, then trail\n"
      "Green = reached | Orange = waiting | Gray = off");
   ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TOOLTIP,
      "Auto TP: Close 50% at 1:1 RR (SL distance)\n"
      "If lot = min, cannot partial close");
   ObjectSetString(0, OBJ_CLOSE_BTN, OBJPROP_TOOLTIP,
      "Close ALL positions immediately. Cannot undo!");
   ObjectSetString(0, OBJ_BUY_BTN, OBJPROP_TOOLTIP,
      "Market BUY at Ask. SL auto = 1 ATR below");
   ObjectSetString(0, OBJ_SELL_BTN, OBJPROP_TOOLTIP,
      "Market SELL at Bid. SL auto = 1 ATR above");
   ObjectSetString(0, OBJ_BUY_PND, OBJPROP_TOOLTIP,
      "Buy Pending: auto Stop/Limit based on price\nDrag Entry + SL lines on chart");
   ObjectSetString(0, OBJ_SELL_PND, OBJPROP_TOOLTIP,
      "Sell Pending: auto Stop/Limit based on price\nDrag Entry + SL lines on chart");
   ObjectSetString(0, OBJ_EXECUTE, OBJPROP_TOOLTIP,
      "Place the pending order with current Entry + SL lines");
   ObjectSetString(0, OBJ_CANCEL, OBJPROP_TOOLTIP,
      "Cancel and remove order lines from chart");

   ObjectSetInteger(0, OBJ_BG, OBJPROP_YSIZE, y - PY + 5);
   UpdatePanelVisibility();
   ChartRedraw();
}

void UpdatePanelVisibility()
{
   bool hasPos = HasOwnPosition();

   if(hasPos)
   {
      HideObject(OBJ_BUY_BTN);    HideObject(OBJ_SELL_BTN);
      HideObject(OBJ_BUY_PND);    HideObject(OBJ_SELL_PND);
      HideObject(OBJ_EXECUTE);     HideObject(OBJ_CANCEL);
      HideObject(OBJ_SEP2);
   }
   else
   {
      ShowObject(OBJ_BUY_BTN);    ShowObject(OBJ_SELL_BTN);
      ShowObject(OBJ_BUY_PND);    ShowObject(OBJ_SELL_PND);
      ShowObject(OBJ_EXECUTE);     ShowObject(OBJ_CANCEL);
      ShowObject(OBJ_SEP2);
   }

   // Management section always visible (for pending orders filling overnight)
   ShowObject(OBJ_SEP3);        ShowObject(OBJ_TM_CLOSE);
   ShowObject(OBJ_TM_SWING);    ShowObject(OBJ_BE_BTN);
   ShowObject(OBJ_AUTOTP_BTN);
   ShowObject(OBJ_CLOSE_BTN);
}

// ═══════════════════════════════════════════════════════════════════
// CHART LINES
// ═══════════════════════════════════════════════════════════════════
void CreateOrderLines(bool isBuy)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double offset = 50 * _Point;
   if(g_cachedATR > 0) offset = g_cachedATR * 0.5;
   double entryPx;

   // Default: place entry above (buy) or below (sell)
   if(isBuy)
      entryPx = ask + offset;
   else
      entryPx = bid - offset;
   entryPx = NormPrice(entryPx);

   double slDist = 100 * _Point;
   if(g_cachedATR > 0) slDist = g_cachedATR;
   double slPx = isBuy ? NormPrice(entryPx - slDist) : NormPrice(entryPx + slDist);

   if(ObjectFind(0, OBJ_ENTRY_LINE) < 0)
      ObjectCreate(0, OBJ_ENTRY_LINE, OBJ_HLINE, 0, 0, entryPx);
   ObjectSetDouble (0, OBJ_ENTRY_LINE, OBJPROP_PRICE, entryPx);
   ObjectSetInteger(0, OBJ_ENTRY_LINE, OBJPROP_COLOR, COL_ENTRY);
   ObjectSetInteger(0, OBJ_ENTRY_LINE, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, OBJ_ENTRY_LINE, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, OBJ_ENTRY_LINE, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, OBJ_ENTRY_LINE, OBJPROP_SELECTED, true);
   ObjectSetInteger(0, OBJ_ENTRY_LINE, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, OBJ_ENTRY_LINE, OBJPROP_BACK, false);

   if(ObjectFind(0, OBJ_SL_LINE) < 0)
      ObjectCreate(0, OBJ_SL_LINE, OBJ_HLINE, 0, 0, slPx);
   ObjectSetDouble (0, OBJ_SL_LINE, OBJPROP_PRICE, slPx);
   ObjectSetInteger(0, OBJ_SL_LINE, OBJPROP_COLOR, COL_SL);
   ObjectSetInteger(0, OBJ_SL_LINE, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, OBJ_SL_LINE, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, OBJ_SL_LINE, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, OBJ_SL_LINE, OBJPROP_SELECTED, true);
   ObjectSetInteger(0, OBJ_SL_LINE, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, OBJ_SL_LINE, OBJPROP_BACK, false);

   g_linesActive = true;
   UpdateLineLabels();
   ChartRedraw();
}

void CreateActiveSLLine()
{
   if(g_currentSL <= 0) return;

   if(ObjectFind(0, OBJ_SL_ACTIVE) < 0)
      ObjectCreate(0, OBJ_SL_ACTIVE, OBJ_HLINE, 0, 0, g_currentSL);
   ObjectSetDouble (0, OBJ_SL_ACTIVE, OBJPROP_PRICE, g_currentSL);
   ObjectSetInteger(0, OBJ_SL_ACTIVE, OBJPROP_COLOR, COL_SL);
   ObjectSetInteger(0, OBJ_SL_ACTIVE, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, OBJ_SL_ACTIVE, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, OBJ_SL_ACTIVE, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, OBJ_SL_ACTIVE, OBJPROP_SELECTED, true);
   ObjectSetInteger(0, OBJ_SL_ACTIVE, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, OBJ_SL_ACTIVE, OBJPROP_BACK, false);
   UpdateActiveSLLabel();
}

void RemoveOrderLines()
{
   ObjectDelete(0, OBJ_ENTRY_LINE);
   ObjectDelete(0, OBJ_SL_LINE);
   ObjectDelete(0, OBJ_ENTRY_TAG);
   ObjectDelete(0, OBJ_SL_TAG);
   HideObject(OBJ_WARN_LBL);
   g_linesActive = false;
   g_orderMode = 0;
   HighlightActiveButton();
   UpdateInfo();
   ChartRedraw();
}

void RemoveActiveSLLine()
{
   ObjectDelete(0, OBJ_SL_ACTIVE);
   ObjectDelete(0, OBJ_SL_ACT_TAG);
}

// ═══════════════════════════════════════════════════════════════════
// LINE LABELS (Exness-style)
// ═══════════════════════════════════════════════════════════════════
void UpdateLineLabels()
{
   if(!g_linesActive) return;

   double entryPx = ObjectGetDouble(0, OBJ_ENTRY_LINE, OBJPROP_PRICE);
   double slPx    = ObjectGetDouble(0, OBJ_SL_LINE, OBJPROP_PRICE);
   double slDist  = MathAbs(entryPx - slPx);
   double lot     = CalcLot(slDist);
   double slMoney = CalcMoney(lot, slDist);
   double pips    = slDist / PipSize();
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double spread  = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Detect if lot is clamped at min
   bool isMinLotMode = false;
   double idealLot = 0;
   double tickSz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(slDist > 0 && g_riskMoney > 0 && tickSz > 0 && tickVal > 0)
      idealLot = g_riskMoney / ((slDist / tickSz) * tickVal);
   if(idealLot > 0 && idealLot < minLot)
      isMinLotMode = true;

   // HLINE tooltips
   ObjectSetString(0, OBJ_ENTRY_LINE, OBJPROP_TOOLTIP,
      StringFormat("Entry: %." + IntegerToString(_Digits) + "f | Lot: %.2f", entryPx, lot));
   ObjectSetString(0, OBJ_SL_LINE, OBJPROP_TOOLTIP,
      StringFormat("SL: %." + IntegerToString(_Digits) + "f | -$%.2f | %.0f pips", slPx, slMoney, pips));

   // Entry tag
   string entryTxt;
   color  entryClr = COL_WHITE;
   if(isMinLotMode)
   {
      entryTxt = StringFormat("ENTRY %.2f lot (MIN)", lot);
      entryClr = COL_WARN;
   }
   else
      entryTxt = StringFormat("ENTRY %.2f lot", lot);
   MakePriceTag(OBJ_ENTRY_TAG, entryPx, entryTxt, entryClr, COL_ENTRY);

   // SL tag
   string slTxt;
   color  slClr = COL_WHITE;
   if(isMinLotMode && slMoney > g_riskMoney)
   {
      slTxt = StringFormat("SL -$%.2f (>$%.0f)  %.0f pips", slMoney, g_riskMoney, pips);
      slClr = COL_WARN;
   }
   else
      slTxt = StringFormat("SL -$%.2f  %.0f pips", slMoney, pips);
   MakePriceTag(OBJ_SL_TAG, slPx, slTxt, slClr, COL_SL);

   // Warning label: 3 levels
   if(slDist > 0 && slDist <= spread)
   {
      ObjectSetString(0, OBJ_WARN_LBL, OBJPROP_TEXT,
         StringFormat("\x26A0 SL < Spread! (%.1f < %.1f pts)",
                      slDist / _Point, spread / _Point));
      ObjectSetInteger(0, OBJ_WARN_LBL, OBJPROP_COLOR, COL_SL);
      ShowObject(OBJ_WARN_LBL);
   }
   else if(isMinLotMode)
   {
      ObjectSetString(0, OBJ_WARN_LBL, OBJPROP_TEXT,
         StringFormat("\x26A0 Min lot %.2f | Real risk $%.2f/$%.0f",
                      minLot, slMoney, g_riskMoney));
      ObjectSetInteger(0, OBJ_WARN_LBL, OBJPROP_COLOR, COL_WARN);
      ShowObject(OBJ_WARN_LBL);
   }
   else
      HideObject(OBJ_WARN_LBL);
}

void UpdateActiveSLLabel()
{
   if(ObjectFind(0, OBJ_SL_ACTIVE) < 0) return;

   double slPx = ObjectGetDouble(0, OBJ_SL_ACTIVE, OBJPROP_PRICE);
   double lockedPnL = GetLockedPnL();

   ObjectSetString(0, OBJ_SL_ACTIVE, OBJPROP_TOOLTIP,
      StringFormat("SL: %." + IntegerToString(_Digits) + "f | Lock: $%+.2f", slPx, lockedPnL));

   string slTxt = StringFormat("SL $%+.2f", lockedPnL);
   color clr = lockedPnL >= 0 ? COL_LOCK_UP : COL_LOCK_DN;
   MakePriceTag(OBJ_SL_ACT_TAG, slPx, slTxt, clr, COL_SL);
}

// ═══════════════════════════════════════════════════════════════════
// PANEL INFO UPDATE
// ═══════════════════════════════════════════════════════════════════
void UpdateInfo()
{
   string riskTxt = ObjectGetString(0, OBJ_RISK_EDT, OBJPROP_TEXT);
   double riskVal = StringToDouble(riskTxt);
   if(riskVal > 0) g_riskMoney = riskVal;

   g_hasPos = HasOwnPosition();

   if(g_hasPos)
   {
      SyncFromPosition();
      double pnl = GetPositionPnL();
      double lots = GetTotalLots();
      string dir = g_isBuy ? "LONG" : "SHORT";
      double lockedPnL = GetLockedPnL();

      ObjectSetString(0, OBJ_INFO1, OBJPROP_TEXT,
         StringFormat("%.2f %s    $%+.2f", lots, dir, pnl));
      ObjectSetInteger(0, OBJ_INFO1, OBJPROP_COLOR,
         pnl >= 0 ? COL_PROFIT : COL_LOSS);

      ObjectSetString(0, OBJ_INFO2, OBJPROP_TEXT,
         StringFormat("SL $%+.2f  |  %." + IntegerToString(_Digits) + "f",
                      lockedPnL, g_currentSL));
      ObjectSetInteger(0, OBJ_INFO2, OBJPROP_COLOR,
         lockedPnL >= 0 ? COL_LOCK_UP : COL_LOCK_DN);

      double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
      ObjectSetString(0, OBJ_INFO3, OBJPROP_TEXT,
         StringFormat("Entry %." + IntegerToString(_Digits) + "f  |  Spread %.0f",
                      g_entryPx, spread));
      ObjectSetInteger(0, OBJ_INFO3, OBJPROP_COLOR, COL_DIM);

      // SL line on chart
      if(ObjectFind(0, OBJ_SL_ACTIVE) >= 0)
      {
         ObjectSetDouble(0, OBJ_SL_ACTIVE, OBJPROP_PRICE, g_currentSL);
         UpdateActiveSLLabel();
      }
      else
         CreateActiveSLLine();
   }
   else
   {
      // No position
      RemoveActiveSLLine();

      if(g_linesActive && g_orderMode != 0)
      {
         double entryPx = ObjectGetDouble(0, OBJ_ENTRY_LINE, OBJPROP_PRICE);
         double slPx    = ObjectGetDouble(0, OBJ_SL_LINE, OBJPROP_PRICE);
         double slDist  = MathAbs(entryPx - slPx);
         double lot     = CalcLot(slDist);
         double slMoney = CalcMoney(lot, slDist);
         double pips    = slDist / PipSize();
         double spread  = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;

         // Detect min lot mode
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         bool isMinLotMode = false;
         double tickSz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         if(slDist > 0 && g_riskMoney > 0 && tickSz > 0 && tickVal > 0)
         {
            double idealLot = g_riskMoney / ((slDist / tickSz) * tickVal);
            if(idealLot < minLot) isMinLotMode = true;
         }

         if(isMinLotMode)
         {
            ObjectSetString(0, OBJ_INFO1, OBJPROP_TEXT,
               StringFormat("%.2f lot(MIN) -$%.2f", lot, slMoney));
            ObjectSetInteger(0, OBJ_INFO1, OBJPROP_COLOR,
               slMoney > g_riskMoney ? COL_WARN : COL_WHITE);
         }
         else
         {
            ObjectSetString(0, OBJ_INFO1, OBJPROP_TEXT,
               StringFormat("Lot %.2f    SL -$%.2f", lot, slMoney));
            ObjectSetInteger(0, OBJ_INFO1, OBJPROP_COLOR, COL_WHITE);
         }

         // Auto-detect order type name based on entry vs market
         string orderName = "";
         double ask2 = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid2 = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(g_orderMode == 1)
            orderName = (entryPx > ask2) ? "BUY STOP" : "BUY LIMIT";
         else if(g_orderMode == 2)
            orderName = (entryPx < bid2) ? "SELL STOP" : "SELL LIMIT";
         ObjectSetString(0, OBJ_INFO2, OBJPROP_TEXT,
            StringFormat("%s  |  %.0f pips SL", orderName, pips));
         ObjectSetInteger(0, OBJ_INFO2, OBJPROP_COLOR, COL_DIM);

         double pct = 0;
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         if(bal > 0) pct = NormalizeDouble(slMoney / bal * 100.0, 1);
         ObjectSetString(0, OBJ_INFO3, OBJPROP_TEXT,
            StringFormat("Risk $%.1f (%.1f%%)  |  Spread %.0f", slMoney, pct, spread));
         ObjectSetInteger(0, OBJ_INFO3, OBJPROP_COLOR, COL_DIM);

         UpdateLineLabels();
      }
      else
      {
         double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
         ObjectSetString(0, OBJ_INFO1, OBJPROP_TEXT, "Select order type");
         ObjectSetInteger(0, OBJ_INFO1, OBJPROP_COLOR, COL_DIM);
         ObjectSetString(0, OBJ_INFO2, OBJPROP_TEXT,
            StringFormat("Risk $%d  |  Spread %.0f pts", (int)g_riskMoney, spread));
         ObjectSetInteger(0, OBJ_INFO2, OBJPROP_COLOR, COL_DIM);
         ObjectSetString(0, OBJ_INFO3, OBJPROP_TEXT, " ");

         g_entryPx  = 0;   g_origSL    = 0;
         g_currentSL = 0;
         g_tpDist = 0;
      }
   }

   // Management button rendering (always, regardless of position)
   {
      bool trailActive = false;
      if(g_trailRef != TRAIL_NONE && g_hasPos)
      {
         double refE = GetAvgEntry();
         if(refE <= 0) refE = g_entryPx;
         double cur2 = g_isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                               : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double mv = g_isBuy ? (cur2 - refE) : (refE - cur2);
         if(g_beEnabled && g_beReached)
            trailActive = true;
         else
            trailActive = (g_cachedATR > 0 && mv >= g_cachedATR);
      }

      if(g_trailRef == TRAIL_CLOSE)
      {
         ObjectSetString(0, OBJ_TM_CLOSE, OBJPROP_TEXT, "Close");
         ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_BGCOLOR, trailActive ? COL_ON : C'30,80,140');
         ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_COLOR, COL_WHITE);
      }
      else
      {
         ObjectSetString(0, OBJ_TM_CLOSE, OBJPROP_TEXT, "Close");
         ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_BGCOLOR, COL_OFF);
         ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_COLOR, COL_DIM);
      }

      if(g_trailRef == TRAIL_SWING)
      {
         ObjectSetString(0, OBJ_TM_SWING, OBJPROP_TEXT, "Swing");
         ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_BGCOLOR, trailActive ? COL_ON : C'30,80,140');
         ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_COLOR, COL_WHITE);
      }
      else
      {
         ObjectSetString(0, OBJ_TM_SWING, OBJPROP_TEXT, "Swing");
         ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_BGCOLOR, COL_OFF);
         ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_COLOR, COL_DIM);
      }
   }

   ObjectSetString(0, OBJ_BE_BTN, OBJPROP_TEXT,
      g_beReached ? "BE: \x2713" : (g_beEnabled ? "BE: ON" : "BE: OFF"));
   ObjectSetInteger(0, OBJ_BE_BTN, OBJPROP_BGCOLOR,
      g_beReached ? C'0,100,60' : (g_beEnabled ? COL_ON : COL_OFF));
   ObjectSetInteger(0, OBJ_BE_BTN, OBJPROP_COLOR,
      (g_beEnabled || g_beReached) ? COL_WHITE : COL_DIM);

   ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT,
      g_tp1Hit ? "Auto TP: \x2713 Done" : (g_autoTPEnabled ? "Auto TP: ON" : "Auto TP: OFF"));
   ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_BGCOLOR,
      g_tp1Hit ? C'0,100,60' : (g_autoTPEnabled ? COL_ON : COL_OFF));
   ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_COLOR,
      (g_autoTPEnabled || g_tp1Hit) ? COL_WHITE : COL_DIM);

   UpdatePanelVisibility();
}

// ═══════════════════════════════════════════════════════════════════
// BUTTON HIGHLIGHTING
// ═══════════════════════════════════════════════════════════════════
void HighlightActiveButton()
{
   ObjectSetInteger(0, OBJ_BUY_PND,  OBJPROP_BGCOLOR, C'0,90,55');
   ObjectSetInteger(0, OBJ_SELL_PND, OBJPROP_BGCOLOR, C'150,40,40');

   switch(g_orderMode)
   {
      case 1: ObjectSetInteger(0, OBJ_BUY_PND,  OBJPROP_BGCOLOR, C'0,180,100'); break;
      case 2: ObjectSetInteger(0, OBJ_SELL_PND, OBJPROP_BGCOLOR, C'230,60,60'); break;
   }
}

// ═══════════════════════════════════════════════════════════════════
// ORDER EXECUTION
// ═══════════════════════════════════════════════════════════════════
bool ExecuteMarketOrder(bool isBuy)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entryPx = isBuy ? ask : bid;

   double slDist = g_cachedATR;
   if(slDist <= 0) slDist = 100 * _Point;
   double slPx;

   if(g_linesActive && ObjectFind(0, OBJ_SL_LINE) >= 0)
   {
      slPx = NormPrice(ObjectGetDouble(0, OBJ_SL_LINE, OBJPROP_PRICE));
      slDist = MathAbs(entryPx - slPx);
   }
   else
      slPx = isBuy ? NormPrice(entryPx - slDist) : NormPrice(entryPx + slDist);

   double lot = CalcLot(slDist);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price     = isBuy ? ask : bid;
   req.sl        = slPx;
   req.tp        = 0;
   req.deviation = InpDeviation;
   req.magic     = InpMagic;
   req.comment   = StringFormat("ExO|%s|$%.0f", _Symbol, g_riskMoney);

   if(!OrderSend(req, res))
   {
      Print("[ExO] Market FAILED: ", res.retcode, " - ", res.comment);
      return false;
   }

   if(res.retcode == TRADE_RETCODE_DONE)
   {
      Print("[ExO] Market ", (isBuy ? "BUY" : "SELL"),
            " Lot=", lot, " SL=", slPx, " Risk=$", DoubleToString(CalcMoney(lot, slDist), 2));
      g_tpDist = slDist;
      g_entryPx = entryPx;
      g_origSL = slPx;
      g_currentSL = slPx;
      g_isBuy = isBuy;
      RemoveOrderLines();
      return true;
   }

   Print("[ExO] Unexpected retcode: ", res.retcode);
   return false;
}

bool ExecutePendingOrder()
{
   if(g_orderMode == 0 || !g_linesActive) return false;

   double entryPx = NormPrice(ObjectGetDouble(0, OBJ_ENTRY_LINE, OBJPROP_PRICE));
   double slPx    = NormPrice(ObjectGetDouble(0, OBJ_SL_LINE, OBJPROP_PRICE));
   double slDist  = MathAbs(entryPx - slPx);
   double lot     = CalcLot(slDist);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool isBuy = IsBuyMode();

   // Auto-detect Stop vs Limit based on entry price vs market
   ENUM_ORDER_TYPE orderType;
   if(isBuy)
      orderType = (entryPx > ask) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_BUY_LIMIT;
   else
      orderType = (entryPx < bid) ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_SELL_LIMIT;

   // Validate SL direction
   if(isBuy  && slPx >= entryPx) { Print("[ExO] Buy SL must be below entry"); return false; }
   if(!isBuy && slPx <= entryPx) { Print("[ExO] Sell SL must be above entry"); return false; }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_PENDING;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = orderType;
   req.price     = entryPx;
   req.sl        = slPx;
   req.tp        = 0;
   req.deviation = InpDeviation;
   req.magic     = InpMagic;
   req.comment   = StringFormat("ExO|%s|$%.0f", _Symbol, g_riskMoney);

   if(!OrderSend(req, res))
   {
      Print("[ExO] Pending FAILED: ", res.retcode, " - ", res.comment);
      return false;
   }

   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED)
   {
      Print("[ExO] ", EnumToString(orderType),
            " Lot=", lot, " Entry=", entryPx, " SL=", slPx,
            " Risk=$", DoubleToString(CalcMoney(lot, slDist), 2));
      g_tpDist = slDist;
      RemoveOrderLines();
      return true;
   }

   Print("[ExO] Unexpected retcode: ", res.retcode);
   return false;
}

// ═══════════════════════════════════════════════════════════════════
// OnInit
// ═══════════════════════════════════════════════════════════════════
int OnInit()
{
   g_riskMoney = InpRiskDollar;

   g_atrHandle = iATR(_Symbol, InpATRTF, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("[ExO] Failed to create ATR indicator");
      return INIT_FAILED;
   }

   double atr[1];
   for(int i = 0; i < 50; i++)
   {
      if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1 && atr[0] > 0)
      { g_cachedATR = atr[0]; break; }
      Sleep(100);
   }

   CreatePanel();
   UpdateInfo();
   EventSetMillisecondTimer(500);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
   }
   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw();
}

// ═══════════════════════════════════════════════════════════════════
// OnTick
// ═══════════════════════════════════════════════════════════════════
void OnTick()
{
   double atr[1];
   if(g_atrHandle != INVALID_HANDLE && CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1)
      g_cachedATR = atr[0];

   bool hadPos = g_hasPos;
   g_hasPos = HasOwnPosition();
   if(hadPos && !g_hasPos)
   {
      Print("[ExO] Position closed");
      RemoveActiveSLLine();
      g_trailRef = TRAIL_NONE;
      g_beEnabled = false;
      g_beReached = false; g_autoTPEnabled = false;
      g_tp1Hit = false;
   }

   if(g_hasPos)
   {
      SyncFromPosition();
      ManageTrailBE();
      ManageAutoTP();
   }

   UpdateInfo();
}

void OnTimer()
{
   UpdateInfo();
   ChartRedraw();
}

// ═══════════════════════════════════════════════════════════════════
// OnChartEvent
// ═══════════════════════════════════════════════════════════════════
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(StringFind(sparam, PREFIX) == 0)
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

      if(sparam == OBJ_BUY_BTN && !g_hasPos)
         ExecuteMarketOrder(true);
      else if(sparam == OBJ_SELL_BTN && !g_hasPos)
         ExecuteMarketOrder(false);
      else if(sparam == OBJ_BUY_PND && !g_hasPos)
      {
         if(g_orderMode == 1) RemoveOrderLines();
         else { g_orderMode = 1; CreateOrderLines(true); }
         HighlightActiveButton();
      }
      else if(sparam == OBJ_SELL_PND && !g_hasPos)
      {
         if(g_orderMode == 2) RemoveOrderLines();
         else { g_orderMode = 2; CreateOrderLines(false); }
         HighlightActiveButton();
      }
      else if(sparam == OBJ_EXECUTE && !g_hasPos)
         ExecutePendingOrder();
      else if(sparam == OBJ_CANCEL && !g_hasPos)
         RemoveOrderLines();
      else if(sparam == OBJ_TM_CLOSE)
      {
         g_trailRef = (g_trailRef == TRAIL_CLOSE) ? TRAIL_NONE : TRAIL_CLOSE;
         Print("[ExO] Trail -> ", (g_trailRef == TRAIL_CLOSE) ? "Close" : "None");
         UpdateInfo(); ChartRedraw();
      }
      else if(sparam == OBJ_TM_SWING)
      {
         g_trailRef = (g_trailRef == TRAIL_SWING) ? TRAIL_NONE : TRAIL_SWING;
         Print("[ExO] Trail -> ", (g_trailRef == TRAIL_SWING) ? "Swing" : "None");
         UpdateInfo(); ChartRedraw();
      }
      else if(sparam == OBJ_BE_BTN)
      {
         if(!g_beReached) g_beEnabled = !g_beEnabled;
         UpdateInfo(); ChartRedraw();
      }
      else if(sparam == OBJ_AUTOTP_BTN)
      {
         if(!g_tp1Hit)
         {
            g_autoTPEnabled = !g_autoTPEnabled;
            if(g_autoTPEnabled && g_tpDist <= 0)
               g_tpDist = MathAbs(g_entryPx - g_currentSL);
         }
         UpdateInfo(); ChartRedraw();
      }
      else if(sparam == OBJ_CLOSE_BTN && g_hasPos)
      {
         CloseAllPositions();
         RemoveActiveSLLine();
         UpdateInfo(); ChartRedraw();
      }
      else if(sparam == OBJ_RISK_PLUS)
      {
         g_riskMoney += (g_riskMoney < 50) ? 5 : 10;
         ObjectSetString(0, OBJ_RISK_EDT, OBJPROP_TEXT, IntegerToString((int)g_riskMoney));
         UpdateInfo(); ChartRedraw();
      }
      else if(sparam == OBJ_RISK_MINUS)
      {
         g_riskMoney -= (g_riskMoney <= 50) ? 5 : 10;
         if(g_riskMoney < 1) g_riskMoney = 1;
         ObjectSetString(0, OBJ_RISK_EDT, OBJPROP_TEXT, IntegerToString((int)g_riskMoney));
         UpdateInfo(); ChartRedraw();
      }
   }

   if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == OBJ_RISK_EDT)
   {
      UpdateInfo(); ChartRedraw();
   }

   // Line drag — pending setup
   if(id == CHARTEVENT_OBJECT_DRAG && g_linesActive && g_orderMode != 0)
   {
      if(sparam == OBJ_ENTRY_LINE)
      {
         double entryPx = ObjectGetDouble(0, OBJ_ENTRY_LINE, OBJPROP_PRICE);
         double slDist = g_cachedATR;
         if(slDist <= 0) slDist = 100 * _Point;
         bool isBuy = IsBuyMode();
         double newSL = isBuy ? NormPrice(entryPx - slDist) : NormPrice(entryPx + slDist);
         ObjectSetDouble(0, OBJ_SL_LINE, OBJPROP_PRICE, newSL);
         UpdateInfo(); ChartRedraw();
      }
      else if(sparam == OBJ_SL_LINE)
      {
         UpdateInfo(); ChartRedraw();
      }
   }

   // Line drag — active position SL
   if(id == CHARTEVENT_OBJECT_DRAG && g_hasPos && sparam == OBJ_SL_ACTIVE)
   {
      double newSL = NormPrice(ObjectGetDouble(0, OBJ_SL_ACTIVE, OBJPROP_PRICE));
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(g_isBuy && newSL >= bid) return;
      if(!g_isBuy && newSL <= ask) return;
      ModifySL(newSL);
      UpdateInfo(); ChartRedraw();
   }

   // Reposition price tags on chart scroll/zoom
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      if(g_linesActive) UpdateLineLabels();
      if(g_hasPos) UpdateActiveSLLabel();
      ChartRedraw();
   }
}
//+------------------------------------------------------------------+
