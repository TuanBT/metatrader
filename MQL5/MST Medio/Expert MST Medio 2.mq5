//+------------------------------------------------------------------+
//| Expert MST Medio 2.mq5                                          |
//| MST Medio 2 — Simplified 2-Step Breakout Confirmation EA       |
//|                                                                  |
//| Core logic (same as MST Medio v2.0):                            |
//|   1. Swing High/Low (pivotLen=3) → HH/LL detection             |
//|   2. Impulse body filter (impulseMult=1.0)                      |
//|   3. W1 Peak scan → Confirm close beyond W1 → Signal           |
//|   4. Entry = old SH/SL, SL = swing opposite                    |
//|   5. TP = confirm break candle High (BUY) / Low (SELL)          |
//|   6. On new signal → close all → place limit/stop order         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MTS"
#property link      ""
#property version   "1.00"
#property strict

//--- Inputs
input double InpLotSize = 0.01;       // Lot Size
input ulong  InpMagic   = 20260301;   // Magic Number

//--- Fixed strategy params
#define PIVOT_LEN     3
#define IMPULSE_MULT  1.0
#define DEVIATION     20

// ============================================================================
// GLOBAL STATE
// ============================================================================
static datetime g_lastBarTime = 0;

// Swing history
static double   g_sh1 = EMPTY_VALUE, g_sh0 = EMPTY_VALUE;
static datetime g_sh1_t = 0, g_sh0_t = 0;
static double   g_sl1 = EMPTY_VALUE, g_sl0 = EMPTY_VALUE;
static datetime g_sl1_t = 0, g_sl0_t = 0;
static double   g_slBeforeSH = EMPTY_VALUE, g_shBeforeSL = EMPTY_VALUE;
static datetime g_slBeforeSH_t = 0, g_shBeforeSL_t = 0;

// Pending confirmation
static int    g_pState = 0;           // 0=idle, 1=BUY, -1=SELL
static double g_pEntry = EMPTY_VALUE; // Entry level
static double g_pW1Peak = EMPTY_VALUE;// W1 peak / trough
static double g_pW1Track = EMPTY_VALUE;
static double g_pSL = EMPTY_VALUE;
static datetime g_pSL_t = 0, g_pEntry_t = 0;

// Signal dedup
static datetime g_lastBuySig = 0, g_lastSellSig = 0;

// ============================================================================
// HELPERS
// ============================================================================
bool IsPivotHigh(int bar, int len)
{
   double val = iHigh(_Symbol, _Period, bar);
   for(int j = bar - len; j <= bar + len; j++)
   {
      if(j == bar || j < 0) continue;
      if(iHigh(_Symbol, _Period, j) >= val) return false;
   }
   return true;
}

bool IsPivotLow(int bar, int len)
{
   double val = iLow(_Symbol, _Period, bar);
   for(int j = bar - len; j <= bar + len; j++)
   {
      if(j == bar || j < 0) continue;
      if(iLow(_Symbol, _Period, j) <= val) return false;
   }
   return true;
}

double CalcAvgBody(int from, int period = 20)
{
   double sum = 0; int cnt = 0;
   int bars = Bars(_Symbol, _Period);
   for(int i = from; i < from + period && i < bars; i++)
   { sum += MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i)); cnt++; }
   return cnt > 0 ? sum / cnt : 0;
}

int TimeToShift(datetime t)
{ return t == 0 ? -1 : iBarShift(_Symbol, _Period, t, false); }

double NormalizePrice(double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0) tick = _Point;
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
}

// ============================================================================
// ORDER MANAGEMENT
// ============================================================================
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action = TRADE_ACTION_DEAL;
      req.symbol = _Symbol;
      req.volume = PositionGetDouble(POSITION_VOLUME);
      req.deviation = DEVIATION;
      req.magic = InpMagic;
      req.position = ticket;
      req.comment = "MST2_CLOSE";

      long pType = PositionGetInteger(POSITION_TYPE);
      if(pType == POSITION_TYPE_BUY)
      { req.type = ORDER_TYPE_SELL; req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); }
      else
      { req.type = ORDER_TYPE_BUY; req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); }

      if(!OrderSend(req, res))
         Print("Close failed. Ticket=", ticket, " Ret=", res.retcode);
   }
}

void DeleteAllPending()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;

      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action = TRADE_ACTION_REMOVE;
      req.order = ticket;
      if(!OrderSend(req, res))
         Print("Delete order failed. Ticket=", ticket, " Ret=", res.retcode);
   }
}

bool PlaceOrder(bool isBuy, double entry, double sl, double tp)
{
   double entryN = NormalizePrice(entry);
   double slN = NormalizePrice(sl);
   double tpN = tp > 0 ? NormalizePrice(tp) : 0;

   // Normalize lot
   double lot = InpLotSize;
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lot < minL) lot = minL;
   if(lot > maxL) lot = maxL;
   if(step > 0) lot = MathFloor(lot / step) * step;
   lot = NormalizeDouble(lot, 2);

   // Validate SL
   if(isBuy && slN >= entryN) { Print("Invalid BUY SL"); return false; }
   if(!isBuy && slN <= entryN) { Print("Invalid SELL SL"); return false; }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   ENUM_ORDER_TYPE type;
   if(isBuy)
   {
      if(entryN < ask) type = ORDER_TYPE_BUY_LIMIT;
      else if(entryN > ask) type = ORDER_TYPE_BUY_STOP;
      else
      {  // Market
         MqlTradeRequest r; MqlTradeResult s;
         ZeroMemory(r); ZeroMemory(s);
         r.action = TRADE_ACTION_DEAL; r.symbol = _Symbol;
         r.volume = lot; r.type = ORDER_TYPE_BUY;
         r.price = ask; r.sl = slN; r.tp = tpN;
         r.magic = InpMagic; r.deviation = DEVIATION;
         r.comment = "MST2_BUY";
         if(!OrderSend(r, s)) { Print("BUY market failed. Ret=", s.retcode); return false; }
         Print("✅ BUY market Lot=", lot, " E=", ask, " SL=", slN, " TP=", tpN);
         return true;
      }
   }
   else
   {
      if(entryN > bid) type = ORDER_TYPE_SELL_LIMIT;
      else if(entryN < bid) type = ORDER_TYPE_SELL_STOP;
      else
      {  // Market
         MqlTradeRequest r; MqlTradeResult s;
         ZeroMemory(r); ZeroMemory(s);
         r.action = TRADE_ACTION_DEAL; r.symbol = _Symbol;
         r.volume = lot; r.type = ORDER_TYPE_SELL;
         r.price = bid; r.sl = slN; r.tp = tpN;
         r.magic = InpMagic; r.deviation = DEVIATION;
         r.comment = "MST2_SELL";
         if(!OrderSend(r, s)) { Print("SELL market failed. Ret=", s.retcode); return false; }
         Print("✅ SELL market Lot=", lot, " E=", bid, " SL=", slN, " TP=", tpN);
         return true;
      }
   }

   // Pending order
   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   req.action = TRADE_ACTION_PENDING;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type = type;
   req.price = entryN;
   req.sl = slN;
   req.tp = tpN;
   req.magic = InpMagic;
   req.deviation = DEVIATION;
   req.comment = isBuy ? "MST2_BUY" : "MST2_SELL";

   if(!OrderSend(req, res))
   { Print("Pending failed. Ret=", res.retcode); return false; }
   Print("✅ ", (isBuy ? "BUY" : "SELL"), " pending Lot=", lot,
         " E=", entryN, " SL=", slN, " TP=", tpN);
   return true;
}

// ============================================================================
// INIT
// ============================================================================
int OnInit()
{
   Print("ℹ️ MST Medio 2 | PivotLen=", PIVOT_LEN, " ImpulseMult=", IMPULSE_MULT,
         " | Lot=", InpLotSize, " Magic=", InpMagic);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {}

// ============================================================================
// TICK HANDLER
// ============================================================================
void OnTick()
{
   // Only process on new bar
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;

   int bars = Bars(_Symbol, _Period);
   if(bars < PIVOT_LEN * 2 + 25) return;

   // ── STEP 1: Swing Detection ──
   int cb = PIVOT_LEN;  // confirmed pivot bar
   bool swH = IsPivotHigh(cb, PIVOT_LEN);
   bool swL = IsPivotLow(cb, PIVOT_LEN);

   datetime cbTime = iTime(_Symbol, _Period, cb);
   double   cbHigh = iHigh(_Symbol, _Period, cb);
   double   cbLow  = iLow(_Symbol, _Period, cb);

   // Update swing history (same order as Pine)
   if(swL) { g_sl0 = g_sl1; g_sl0_t = g_sl1_t; g_sl1 = cbLow; g_sl1_t = cbTime; }
   if(swH) { g_slBeforeSH = g_sl1; g_slBeforeSH_t = g_sl1_t;
             g_sh0 = g_sh1; g_sh0_t = g_sh1_t; g_sh1 = cbHigh; g_sh1_t = cbTime; }
   if(swL) { g_shBeforeSL = g_sh1; g_shBeforeSL_t = g_sh1_t; }

   // ── STEP 2: HH/LL + Impulse Filter ──
   bool hh = swH && g_sh0 != EMPTY_VALUE && g_sh1 > g_sh0;
   bool ll = swL && g_sl0 != EMPTY_VALUE && g_sl1 < g_sl0;

   if(hh)
   {
      double avg = CalcAvgBody(1, 20);
      int sh0s = TimeToShift(g_sh0_t);
      bool ok = false;
      if(sh0s >= 0)
         for(int i = sh0s; i >= cb; i--)
         { if(i < 0) continue;
           if(iClose(_Symbol, _Period, i) > g_sh0)
           { ok = MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i)) >= IMPULSE_MULT * avg; break; } }
      if(!ok) hh = false;
   }
   if(ll)
   {
      double avg = CalcAvgBody(1, 20);
      int sl0s = TimeToShift(g_sl0_t);
      bool ok = false;
      if(sl0s >= 0)
         for(int i = sl0s; i >= cb; i--)
         { if(i < 0) continue;
           if(iClose(_Symbol, _Period, i) < g_sl0)
           { ok = MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i)) >= IMPULSE_MULT * avg; break; } }
      if(!ok) ll = false;
   }

   // Break (breakMult=0 → always pass)
   bool breakUp = hh && g_slBeforeSH != EMPTY_VALUE;
   bool breakDn = ll && g_shBeforeSL != EMPTY_VALUE;

   // ── STEP 3: Pending State Machine ──
   bool confBuy = false, confSell = false;
   double cEntry = 0, cSL = 0, cTP = 0;
   datetime cWave_t = 0;

   double prevH = iHigh(_Symbol, _Period, 1);
   double prevL = iLow(_Symbol, _Period, 1);
   double prevC = iClose(_Symbol, _Period, 1);

   if(g_pState == 1)
   {
      if(g_pW1Track == EMPTY_VALUE || prevL < g_pW1Track) g_pW1Track = prevL;
      if(g_pSL != EMPTY_VALUE && prevL <= g_pSL)
      { Print("ℹ️ BUY pending cancelled: SL hit"); g_pState = 0; }
      else if(g_pEntry != EMPTY_VALUE && prevL <= g_pEntry)
      { Print("ℹ️ BUY pending cancelled: Entry touched"); g_pState = 0; }
      else if(g_pW1Peak != EMPTY_VALUE && prevC > g_pW1Peak)
      {
         confBuy = true;
         cEntry = g_pEntry; cSL = g_pSL; cTP = prevH;
         cWave_t = iTime(_Symbol, _Period, 1);
         g_pState = 0;
      }
   }
   if(g_pState == -1)
   {
      if(g_pW1Track == EMPTY_VALUE || prevH > g_pW1Track) g_pW1Track = prevH;
      if(g_pSL != EMPTY_VALUE && prevH >= g_pSL)
      { Print("ℹ️ SELL pending cancelled: SL hit"); g_pState = 0; }
      else if(g_pEntry != EMPTY_VALUE && prevH >= g_pEntry)
      { Print("ℹ️ SELL pending cancelled: Entry touched"); g_pState = 0; }
      else if(g_pW1Peak != EMPTY_VALUE && prevC < g_pW1Peak)
      {
         confSell = true;
         cEntry = g_pEntry; cSL = g_pSL; cTP = prevL;
         cWave_t = iTime(_Symbol, _Period, 1);
         g_pState = 0;
      }
   }

   // ── STEP 4: New Break → W1 Scan ──
   if(breakUp)
   {
      double w1 = EMPTY_VALUE;
      int w1s = -1;
      double w1Init = EMPTY_VALUE;
      bool found = false;

      int sh0s = TimeToShift(g_sh0_t);
      if(sh0s >= 0)
      {
         for(int i = sh0s; i >= 1; i--)
         {
            double cl = iClose(_Symbol, _Period, i);
            double op = iOpen(_Symbol, _Period, i);
            double hi = iHigh(_Symbol, _Period, i);
            double lo = iLow(_Symbol, _Period, i);
            if(!found)
            { if(cl > g_sh0) { found = true; w1 = hi; w1s = i; w1Init = lo; } }
            else
            { if(hi > w1) { w1 = hi; w1s = i; }
              if(w1Init == EMPTY_VALUE || lo < w1Init) w1Init = lo;
              if(cl < op) break; }
         }
      }

      if(w1 != EMPTY_VALUE)
      {
         g_pState = 1; g_pEntry = g_sh0; g_pW1Peak = w1;
         g_pW1Track = w1Init; g_pSL = g_slBeforeSH;
         g_pSL_t = g_slBeforeSH_t; g_pEntry_t = g_sh0_t;
         Print("ℹ️ Pending BUY: Entry=", g_sh0, " W1=", w1, " SL=", g_slBeforeSH);

         // Retro scan
         int rf = w1s - 1; if(rf < 1) rf = 1;
         for(int i = rf; i >= 1; i--)
         {
            if(g_pState != 1) break;
            double rH = iHigh(_Symbol, _Period, i);
            double rL = iLow(_Symbol, _Period, i);
            double rC = iClose(_Symbol, _Period, i);
            if(g_pW1Track == EMPTY_VALUE || rL < g_pW1Track) g_pW1Track = rL;
            if(g_pSL != EMPTY_VALUE && rL <= g_pSL)
            { g_pState = 0; break; }
            if(rL <= g_pEntry) { g_pState = 0; break; }
            if(rC > g_pW1Peak)
            {
               confBuy = true;
               cEntry = g_pEntry; cSL = g_pSL; cTP = rH;
               cWave_t = iTime(_Symbol, _Period, i);
               g_pState = 0; break;
            }
         }
      }
   }

   if(breakDn)
   {
      double w1 = EMPTY_VALUE;
      int w1s = -1;
      double w1Init = EMPTY_VALUE;
      bool found = false;

      int sl0s = TimeToShift(g_sl0_t);
      if(sl0s >= 0)
      {
         for(int i = sl0s; i >= 1; i--)
         {
            double cl = iClose(_Symbol, _Period, i);
            double op = iOpen(_Symbol, _Period, i);
            double lo = iLow(_Symbol, _Period, i);
            double hi = iHigh(_Symbol, _Period, i);
            if(!found)
            { if(cl < g_sl0) { found = true; w1 = lo; w1s = i; w1Init = hi; } }
            else
            { if(lo < w1) { w1 = lo; w1s = i; }
              if(w1Init == EMPTY_VALUE || hi > w1Init) w1Init = hi;
              if(cl > op) break; }
         }
      }

      if(w1 != EMPTY_VALUE)
      {
         g_pState = -1; g_pEntry = g_sl0; g_pW1Peak = w1;
         g_pW1Track = w1Init; g_pSL = g_shBeforeSL;
         g_pSL_t = g_shBeforeSL_t; g_pEntry_t = g_sl0_t;
         Print("ℹ️ Pending SELL: Entry=", g_sl0, " W1=", w1, " SL=", g_shBeforeSL);

         // Retro scan
         int rf = w1s - 1; if(rf < 1) rf = 1;
         for(int i = rf; i >= 1; i--)
         {
            if(g_pState != -1) break;
            double rH = iHigh(_Symbol, _Period, i);
            double rL = iLow(_Symbol, _Period, i);
            double rC = iClose(_Symbol, _Period, i);
            if(g_pW1Track == EMPTY_VALUE || rH > g_pW1Track) g_pW1Track = rH;
            if(g_pSL != EMPTY_VALUE && rH >= g_pSL)
            { g_pState = 0; break; }
            if(rH >= g_pEntry) { g_pState = 0; break; }
            if(rC < g_pW1Peak)
            {
               confSell = true;
               cEntry = g_pEntry; cSL = g_pSL; cTP = rL;
               cWave_t = iTime(_Symbol, _Period, i);
               g_pState = 0; break;
            }
         }
      }
   }

   // ── STEP 5: Process Signal ──
   if(confBuy)
      ProcessSignal(true, cEntry, cSL, cTP);
   else if(confSell)
      ProcessSignal(false, cEntry, cSL, cTP);
}

// ============================================================================
// PROCESS SIGNAL
// ============================================================================
void ProcessSignal(bool isBuy, double entry, double sl, double tp)
{
   datetime sigTime = iTime(_Symbol, _Period, 1);

   // Dedup
   datetime lastSig = isBuy ? g_lastBuySig : g_lastSellSig;
   if(sigTime <= lastSig) return;
   if(isBuy) g_lastBuySig = sigTime;
   else      g_lastSellSig = sigTime;

   string dir = isBuy ? "BUY" : "SELL";
   string msg = StringFormat("MST Medio 2: %s | E=%.2f SL=%.2f TP=%.2f | %s",
                              dir, entry, sl, tp, _Symbol);
   Alert(msg);
   Print("🔔 ", msg);

   // Close existing → place new order
   DeleteAllPending();
   CloseAllPositions();
   PlaceOrder(isBuy, entry, sl, tp);
}
//+------------------------------------------------------------------+
