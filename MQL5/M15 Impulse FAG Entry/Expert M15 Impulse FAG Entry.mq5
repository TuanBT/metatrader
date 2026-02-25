//+------------------------------------------------------------------+
//| M15 Impulse FVG Entry EA — v2.0                                  |
//|                                                                  |
//| v2.0 additions:                                                  |
//|   - Fixed dollar risk sizing (InpRiskMoney)                      |
//|   - MTF consensus filter (M1/M5/M15/H1/H4 — 5 TFs)              |
//|   - MTF trailing SL (step-based by R multiples)                  |
//|   - Max daily loss protection                                     |
//|   - No fixed TP — trailing SL + original hard SL only            |
//+------------------------------------------------------------------+
#property strict

// ── Risk Management ───────────────────────────────────────────────
input bool   InpUseMoneyRisk    = true;   // Use fixed dollar risk per trade
input double InpRiskMoney       = 10.0;   // Risk $ per trade (if UseMoneyRisk=true)
input double InpLotSize         = 0.01;   // Fixed lot (fallback if UseMoneyRisk=false)
input double InpMaxDailyLossPct = 3.0;    // Max daily loss % (0=disabled)

// ── Signal Detection ─────────────────────────────────────────────
input int    InpATRLen          = 14;     // ATR Length (M15)
input double InpATRMult         = 1.2;    // ATR Multiplier for impulse
input double InpBodyRatioMin    = 0.55;   // Min Body/Range for impulse
input int    InpDeviation       = 20;     // Max deviation (points)
input ulong  InpMagic           = 20260224;
input bool   InpOnePosition     = true;   // Block new order if position exists
input int    InpExpiryMinutes   = 0;      // Pending expiry minutes (0=no expiry)

// ── Zone Quality ─────────────────────────────────────────────────
input double InpMinZonePips     = 0.0;    // Min zone size in pips (0=no filter)
input double InpSLBufferPips    = 0.0;    // Extra SL buffer pips
input int    InpMaxZoneBars     = 0;      // Max bars since impulse for OUT signal

// ── Time Filter (Server Time) ─────────────────────────────────────
input bool   InpUseTimeFilter   = true;   // Enable time filter
input int    InpStartHour       = 2;      // Start hour (server time, for Gold: London pre-open)
input int    InpEndHour         = 21;     // End hour (server time, NY close)

// ── MTF Consensus Filter ─────────────────────────────────────────
input bool   InpUseMTFConsensus = true;   // Enable MTF consensus filter
input int    InpMTFMinAgree     = 3;      // Min TFs must agree (out of 5: M1/M5/M15/H1/H4)
input int    InpEMAFastPeriod   = 20;     // EMA fast period
input int    InpEMASlowPeriod   = 50;     // EMA slow period

// ── MTF Trailing SL ──────────────────────────────────────────────
input bool   InpMTFTrail        = true;   // Enable MTF trailing SL
input double InpMTFTrailStartR  = 0.5;   // Start trailing after +X*R profit
input double InpMTFTrailStepR   = 0.25;  // Advance SL by X*risk per step

// ────────────────────────────────────────────────────────────────
// STATE VARIABLES
// ────────────────────────────────────────────────────────────────
static datetime g_lastBarTime    = 0;
static datetime g_lastM15Time    = 0;
static datetime g_m15ImpulseTime = 0;
static datetime g_inTime         = 0;
static datetime g_lastOutTime    = 0;

static double g_zoneH   = EMPTY_VALUE;
static double g_zoneL   = EMPTY_VALUE;
static double g_inHigh  = 0.0;
static double g_inLow   = 0.0;
static double g_minLow  = 0.0;
static double g_maxHigh = 0.0;

static bool   g_waitingIN   = false;
static bool   g_waitingOUT  = false;

// Trade tracking for trailing + daily loss
static bool   g_trailActive     = false;
static double g_trailEntryPrice = 0.0;
static double g_trailOrigSL     = 0.0;
static bool   g_trailIsBuy      = false;
static double g_trailLast       = 0.0;

// Daily loss protection
static double   g_dailyStartBalance = 0;
static datetime g_lastTradingDay    = 0;
static bool     g_dailyPaused       = false;

// Indicator handles
static int g_atrHandle  = INVALID_HANDLE;
static int g_mtfFast[5];  // EMA fast handles: M1, M5, M15, H1, H4
static int g_mtfSlow[5];  // EMA slow handles
static ENUM_TIMEFRAMES g_mtfTFs[5] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4};

// ────────────────────────────────────────────────────────────────
// INIT / DEINIT
// ────────────────────────────────────────────────────────────────
int OnInit()
{
   g_atrHandle = iATR(_Symbol, PERIOD_M15, InpATRLen);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("Warning: Failed to create ATR handle.");
      return INIT_FAILED;
   }

   for(int i = 0; i < 5; i++)
   {
      g_mtfFast[i] = iMA(_Symbol, g_mtfTFs[i], InpEMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      g_mtfSlow[i] = iMA(_Symbol, g_mtfTFs[i], InpEMASlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_mtfFast[i] == INVALID_HANDLE || g_mtfSlow[i] == INVALID_HANDLE)
         Print("Warning: Failed MTF EMA handle for TF index ", i);
   }

   Print("M15 Impulse FAG v2.0 | RiskMoney=", InpRiskMoney,
         " | MTF=", (InpUseMTFConsensus ? "ON" : "OFF"),
         " MinAgree=", InpMTFMinAgree, "/5",
         " | Trail=", (InpMTFTrail ? "ON" : "OFF"),
         " StartR=", InpMTFTrailStartR, " StepR=", InpMTFTrailStepR);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
   }
   for(int i = 0; i < 5; i++)
   {
      if(g_mtfFast[i] != INVALID_HANDLE) { IndicatorRelease(g_mtfFast[i]); g_mtfFast[i] = INVALID_HANDLE; }
      if(g_mtfSlow[i] != INVALID_HANDLE) { IndicatorRelease(g_mtfSlow[i]); g_mtfSlow[i] = INVALID_HANDLE; }
   }
}

// ────────────────────────────────────────────────────────────────
// UTILITY
// ────────────────────────────────────────────────────────────────
double NormalizePrice(const double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) tick = _Point;
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
}

double CalcLotSize(const double entry, const double sl)
{
   if(!InpUseMoneyRisk)
      return InpLotSize;

   double slDist = MathAbs(entry - sl);
   if(slDist <= 0) return InpLotSize;

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0) return InpLotSize;

   double slTicks    = slDist / tickSize;
   double lossPerLot = slTicks * tickValue;
   if(lossPerLot <= 0) return InpLotSize;

   double lot     = InpRiskMoney / lossPerLot;
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot > 0)
      lot = MathFloor(lot / stepLot) * stepLot;

   return NormalizeDouble(MathMax(minLot, MathMin(maxLot, lot)), 2);
}

// ────────────────────────────────────────────────────────────────
// MTF CONSENSUS
// Returns count of TFs agreeing with direction (isBuy)
// Agreement = fast EMA > slow EMA (buy) or fast < slow (sell)
// ────────────────────────────────────────────────────────────────
int GetMTFCount(const bool isBuy)
{
   if(!InpUseMTFConsensus)
      return 5;

   int agree = 0;
   for(int i = 0; i < 5; i++)
   {
      if(g_mtfFast[i] == INVALID_HANDLE || g_mtfSlow[i] == INVALID_HANDLE)
         continue;
      double fast[1], slow[1];
      if(CopyBuffer(g_mtfFast[i], 0, 1, 1, fast) != 1) continue;
      if(CopyBuffer(g_mtfSlow[i], 0, 1, 1, slow) != 1) continue;
      if(isBuy  && fast[0] > slow[0]) agree++;
      if(!isBuy && fast[0] < slow[0]) agree++;
   }
   return agree;
}

bool IsMTFOK(const bool isBuy)
{
   if(!InpUseMTFConsensus) return true;
   int cnt = GetMTFCount(isBuy);
   if(cnt < InpMTFMinAgree)
   {
      Print("[MTF-BLOCK] ", (isBuy ? "BUY" : "SELL"),
            " | Agree=", cnt, "/5 < need=", InpMTFMinAgree);
      return false;
   }
   return true;
}

// ────────────────────────────────────────────────────────────────
// TRAILING SL (step-based by R multiples)
// ────────────────────────────────────────────────────────────────
void CheckMTFTrailing()
{
   if(!InpMTFTrail || !g_trailActive) return;
   if(g_trailEntryPrice == 0 || g_trailOrigSL == 0) return;

   double risk      = MathAbs(g_trailEntryPrice - g_trailOrigSL);
   if(risk <= 0) return;
   double startDist = InpMTFTrailStartR * risk;
   double stepDist  = InpMTFTrailStepR  * risk;

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

      double price   = g_trailIsBuy
                       ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                       : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double advance = g_trailIsBuy ? (price - posOpen) : (posOpen - price);
      if(advance < startDist) return;

      double steps = MathFloor((advance - startDist) / stepDist);
      double newSL;
      if(g_trailIsBuy)
         newSL = NormalizePrice(posOpen + steps * stepDist);
      else
         newSL = NormalizePrice(posOpen - steps * stepDist);

      bool shouldUpdate = g_trailIsBuy  ? (newSL > g_trailLast && newSL > currentSL)
                                        : (newSL < g_trailLast && newSL < currentSL);
      if(!shouldUpdate) return;

      if(g_trailIsBuy  && newSL >= SymbolInfoDouble(_Symbol, SYMBOL_BID)) return;
      if(!g_trailIsBuy && newSL <= SymbolInfoDouble(_Symbol, SYMBOL_ASK)) return;

      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action   = TRADE_ACTION_SLTP;
      req.symbol   = _Symbol;
      req.position = ticket;
      req.sl       = newSL;
      req.tp       = currentTP;

      if(OrderSend(req, res))
      {
         g_trailLast = newSL;
         double lockedR = MathAbs(newSL - posOpen) / risk;
         Print("[TRAIL] SL->", DoubleToString(newSL, _Digits),
               " | Locked=", DoubleToString(lockedR, 2), "R");
      }
      else
         Print("[TRAIL] Warning: Modify failed. Retcode=", res.retcode);
   }
}

// ────────────────────────────────────────────────────────────────
// DAILY LOSS
// ────────────────────────────────────────────────────────────────
bool CheckDailyLoss()
{
   if(InpMaxDailyLossPct <= 0) return true;

   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(today != g_lastTradingDay)
   {
      g_lastTradingDay    = today;
      g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyPaused       = false;
   }
   if(g_dailyPaused) return false;

   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPct = (g_dailyStartBalance - equity) / g_dailyStartBalance * 100.0;
   if(lossPct >= InpMaxDailyLossPct)
   {
      if(!g_dailyPaused)
         Print("[FAG] Daily loss limit hit: ", DoubleToString(lossPct, 2), "% | Paused");
      g_dailyPaused = true;
      return false;
   }
   return true;
}

// ────────────────────────────────────────────────────────────────
// ORDER HELPERS
// ────────────────────────────────────────────────────────────────
bool HasActiveOrders()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(!OrderSelect(t)) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic)
         return true;
   }
   return false;
}

void CheckResetTrail()
{
   if(!g_trailActive) return;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return;  // position still open
   }
   g_trailActive     = false;
   g_trailEntryPrice = 0;
   g_trailOrigSL     = 0;
   g_trailLast       = 0;
}

bool PlaceFvgOrder(const bool isBuy, const double entry, const double sl,
                   const double lot, const datetime signalTime)
{
   // No fixed TP — trailing SL is sole exit. Hard TP = 10R safety backstop.
   double risk = MathAbs(entry - sl);
   double tp   = isBuy
                 ? NormalizePrice(entry + risk * 10.0)
                 : NormalizePrice(entry - risk * 10.0);

   double entryNorm = NormalizePrice(entry);
   double slNorm    = NormalizePrice(sl);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   if(isBuy  && entryNorm >= ask)    { Print("[FAG] Skip: buy entry >= ask");   return false; }
   if(!isBuy && entryNorm <= bid)    { Print("[FAG] Skip: sell entry <= bid");  return false; }
   if(isBuy  && !(slNorm < entryNorm && entryNorm < tp))  { Print("[FAG] Invalid buy SL/TP");  return false; }
   if(!isBuy && !(tp < entryNorm && entryNorm < slNorm))  { Print("[FAG] Invalid sell SL/TP"); return false; }

   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   req.action    = TRADE_ACTION_PENDING;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = type;
   req.price     = entryNorm;
   req.sl        = slNorm;
   req.tp        = tp;
   req.magic     = InpMagic;
   req.deviation = InpDeviation;
   req.comment   = "FAG_v2";
   if(InpExpiryMinutes > 0)
   {
      req.type_time  = ORDER_TIME_SPECIFIED;
      req.expiration = signalTime + InpExpiryMinutes * 60;
   }
   if(!OrderSend(req, res))
   {
      Print("[FAG] OrderSend failed. Retcode=", res.retcode);
      return false;
   }

   // Prime trail state — activates in OnTradeTransaction on fill
   g_trailActive     = false;
   g_trailEntryPrice = entryNorm;
   g_trailOrigSL     = slNorm;
   g_trailIsBuy      = isBuy;
   g_trailLast       = slNorm;

   Print("[FAG] Placed Ticket=", res.order,
         " | Dir=", (isBuy ? "BUY" : "SELL"),
         " | Entry=", DoubleToString(entryNorm, _Digits),
         " | SL=", DoubleToString(slNorm, _Digits),
         " | Lot=", DoubleToString(lot, 2),
         " | Risk=$", DoubleToString(lot * MathAbs(entry - sl) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 2));
   return true;
}

// ────────────────────────────────────────────────────────────────
// OnTradeTransaction — activate trail when pending fills
// ────────────────────────────────────────────────────────────────
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& req,
                        const MqlTradeResult&  res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN && InpMTFTrail)
   {
      g_trailActive     = true;
      g_trailEntryPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      Print("[FAG-TRAIL] Activated at fill=", DoubleToString(g_trailEntryPrice, _Digits),
            " | OrigSL=", DoubleToString(g_trailOrigSL, _Digits));
   }
}

// ────────────────────────────────────────────────────────────────
// UPDATE M15 IMPULSE
// ────────────────────────────────────────────────────────────────
void UpdateM15Impulse()
{
   datetime m15Time = iTime(_Symbol, PERIOD_M15, 1);
   if(m15Time == 0 || m15Time == g_lastM15Time) return;
   g_lastM15Time = m15Time;

   double h = iHigh(_Symbol, PERIOD_M15, 1);
   double l = iLow(_Symbol, PERIOD_M15, 1);
   double o = iOpen(_Symbol, PERIOD_M15, 1);
   double c = iClose(_Symbol, PERIOD_M15, 1);
   double rng = h - l;
   if(rng <= 0) return;

   if(g_atrHandle == INVALID_HANDLE) return;
   double atrBuf[1];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) != 1) return;

   double bodyRatio = MathAbs(c - o) / rng;
   if(!((rng >= InpATRMult * atrBuf[0]) && (bodyRatio >= InpBodyRatioMin))) return;

   g_zoneH = h; g_zoneL = l;
   g_m15ImpulseTime = m15Time;
   g_waitingIN  = true;
   g_waitingOUT = false;
   g_inTime  = 0;
   g_inHigh = g_inLow = g_minLow = g_maxHigh = 0;
}

// ────────────────────────────────────────────────────────────────
// MAIN TICK
// ────────────────────────────────────────────────────────────────
void OnTick()
{
   bool tradingOK = CheckDailyLoss();

   if(g_trailActive)
      CheckMTFTrailing();
   CheckResetTrail();

   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == g_lastBarTime) return;
   g_lastBarTime = currentBarTime;

   UpdateM15Impulse();
   if(!tradingOK) return;

   datetime barTime = iTime(_Symbol, _Period, 1);
   if(barTime == 0) return;

   double high1  = iHigh(_Symbol, _Period, 1);
   double low1   = iLow(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   double close2 = iClose(_Symbol, _Period, 2);

   bool inZone = (g_zoneH != EMPTY_VALUE && g_zoneL != EMPTY_VALUE &&
                  high1 < g_zoneH && low1 > g_zoneL);

   bool canIN = g_waitingIN && g_m15ImpulseTime > 0 && barTime > g_m15ImpulseTime;
   if(canIN && inZone)
   {
      g_inTime  = barTime;
      g_inHigh  = high1; g_inLow  = low1;
      g_minLow  = low1;  g_maxHigh = high1;
      g_waitingIN  = false;
      g_waitingOUT = true;
   }

   if(g_waitingOUT && g_inTime > 0)
   {
      g_minLow  = MathMin(g_minLow,  low1);
      g_maxHigh = MathMax(g_maxHigh, high1);
   }

   bool prevUp   = (g_zoneH != EMPTY_VALUE && close2 > g_zoneH);
   bool prevDown = (g_zoneL != EMPTY_VALUE && close2 < g_zoneL);
   bool outUp    = (g_zoneH != EMPTY_VALUE && close1 > g_zoneH && low1  > g_zoneH && prevUp);
   bool outDown  = (g_zoneL != EMPTY_VALUE && close1 < g_zoneL && high1 < g_zoneL && prevDown);

   bool noRevBuy  = g_waitingOUT && (g_minLow  >= g_inLow);
   bool noRevSell = g_waitingOUT && (g_maxHigh <= g_inHigh);

   bool outBuy  = g_waitingOUT && outUp   && (low1  > g_inHigh) && noRevBuy;
   bool outSell = g_waitingOUT && outDown && (high1 < g_inLow)  && noRevSell;

   if(!(outBuy || outSell) || barTime == g_lastOutTime) return;

   if(InpMaxZoneBars > 0 && g_m15ImpulseTime > 0)
   {
      int barsSince = iBarShift(_Symbol, _Period, g_m15ImpulseTime, false);
      if(barsSince > InpMaxZoneBars) { g_waitingOUT = false; return; }
   }

   if(InpUseTimeFilter)
   {
      MqlDateTime dt;
      TimeToStruct(barTime, dt);
      int hour = dt.hour;
      if(InpStartHour <= InpEndHour)
      { if(hour < InpStartHour || hour >= InpEndHour) return; }
      else
      { if(hour < InpStartHour && hour >= InpEndHour) return; }
   }

   if(!IsMTFOK(outBuy)) { g_waitingOUT = false; return; }

   double top = outBuy ? low1    : g_inLow;
   double bot = outBuy ? g_inHigh : high1;
   double mid = (top + bot) / 2.0;

   double zonePips = MathAbs(top - bot) / (_Point * 10);
   if(InpMinZonePips > 0.0 && zonePips < InpMinZonePips)
   {
      Print("[FAG] Zone too small: ", DoubleToString(zonePips, 1), " pips");
      return;
   }

   double slBuf = InpSLBufferPips * _Point * 10;
   double sl    = outBuy ? (bot - slBuf) : (top + slBuf);
   double lot   = CalcLotSize(mid, sl);

   g_lastOutTime = barTime;
   if(!InpOnePosition || !HasActiveOrders())
      PlaceFvgOrder(outBuy, mid, sl, lot, TimeCurrent());

   g_waitingOUT = false;
}
//+------------------------------------------------------------------+
