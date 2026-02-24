//+------------------------------------------------------------------+
//| M15 Impulse FVG Entry EA                                         |
//| Converted from TradingView logic                                 |
//+------------------------------------------------------------------+
#property strict

input int    InpATRLen        = 14;    // ATR Length (M15)
input double InpATRMult       = 1.2;   // ATR Multiplier
input double InpBodyRatioMin  = 0.55;  // Min Body/Range
input double InpLotSize       = 0.01;  // Lot size
input int    InpDeviation     = 20;    // Max deviation (points)
input ulong  InpMagic         = 20260109;
input bool   InpOnePosition   = true;  // Block if any position/order exists
input int    InpExpiryMinutes = 0;     // Pending expiry minutes (0 = no expiry)

// Time Filter (Server time GMT+0)
input bool   InpUseTimeFilter = false; // Enable time filter
input int    InpStartHour     = 8;     // Start hour (0-23, server time)
input int    InpEndHour       = 20;    // End hour (0-23, server time)

// Risk:Reward adjustment
input double InpTPMultiplier  = 1.0;   // TP multiplier (1.0 = zone edge, >1 = extend TP)

// Zone quality filters
input double InpMinZonePips   = 0.0;   // Min zone size in pips (0 = no filter)
input double InpSLBufferPips  = 0.0;   // Extra SL buffer in pips (0 = no buffer)
input int    InpMaxZoneBars   = 0;     // Max bars to wait for OUT signal (0 = unlimited)

// State
static datetime g_lastBarTime     = 0;
static datetime g_lastM15Time     = 0;
static datetime g_m15ImpulseTime  = 0;
static datetime g_inTime          = 0;
static datetime g_lastOutTime     = 0;

static double g_zoneH   = EMPTY_VALUE;
static double g_zoneL   = EMPTY_VALUE;
static double g_inHigh  = 0.0;
static double g_inLow   = 0.0;
static double g_minLow  = 0.0;
static double g_maxHigh = 0.0;

static bool g_waitingIN  = false;
static bool g_waitingOUT = false;
static int g_atrHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   g_atrHandle = iATR(_Symbol, PERIOD_M15, InpATRLen);
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
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   g_atrHandle = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
bool HasActiveOrders()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) == Symbol() &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }

   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) == Symbol() &&
         (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
double NormalizePrice(const double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0)
      tick = _Point;
   double normalized = MathRound(price / tick) * tick;
   return NormalizeDouble(normalized, _Digits);
}

//+------------------------------------------------------------------+
bool PlaceFvgOrder(const bool isBuy, const double entry, const double sl, const double tp, const datetime signalTime)
{
   double entryNorm = NormalizePrice(entry);
   double slNorm    = NormalizePrice(sl);
   double tpNorm    = NormalizePrice(tp);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   if(isBuy && entryNorm >= ask)
   {
      Print("Skip buy limit: entry >= ask.");
      return false;
   }
   if(!isBuy && entryNorm <= bid)
   {
      Print("Skip sell limit: entry <= bid.");
      return false;
   }

   if(isBuy && !(slNorm < entryNorm && entryNorm < tpNorm))
   {
      Print("Invalid buy SL/TP placement.");
      return false;
   }
   if(!isBuy && !(tpNorm < entryNorm && entryNorm < slNorm))
   {
      Print("Invalid sell SL/TP placement.");
      return false;
   }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action    = TRADE_ACTION_PENDING;
   req.symbol    = _Symbol;
   req.volume    = InpLotSize;
   req.type      = type;
   req.price     = entryNorm;
   req.sl        = slNorm;
   req.tp        = tpNorm;
   req.magic     = InpMagic;
   req.deviation = InpDeviation;
   req.comment   = "M15_FVG_ENTRY";

   if(InpExpiryMinutes > 0)
   {
      req.type_time  = ORDER_TIME_SPECIFIED;
      req.expiration = signalTime + InpExpiryMinutes * 60;
   }

   if(!OrderSend(req, res))
   {
      Print("OrderSend failed. Retcode=", res.retcode);
      return false;
   }

   Print("Pending order placed. Ticket=", res.order, " Entry=", entryNorm, " SL=", slNorm, " TP=", tpNorm);
   return true;
}

//+------------------------------------------------------------------+
void UpdateM15Impulse()
{
   datetime m15Time = iTime(_Symbol, PERIOD_M15, 1);
   if(m15Time == 0 || m15Time == g_lastM15Time)
      return;

   g_lastM15Time = m15Time;

   double h = iHigh(_Symbol, PERIOD_M15, 1);
   double l = iLow(_Symbol, PERIOD_M15, 1);
   double o = iOpen(_Symbol, PERIOD_M15, 1);
   double c = iClose(_Symbol, PERIOD_M15, 1);
   double rng = h - l;

   if(g_atrHandle == INVALID_HANDLE)
      return;
   double atrBuf[1];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) != 1)
      return;
   double atr = atrBuf[0];
   double bodyRatio = (rng > 0.0) ? MathAbs(c - o) / rng : 0.0;

   bool imp = (rng >= InpATRMult * atr) && (bodyRatio >= InpBodyRatioMin);
   if(!imp)
      return;

   g_zoneH = h;
   g_zoneL = l;
   g_m15ImpulseTime = m15Time;

   g_waitingIN  = true;
   g_waitingOUT = false;

   g_inTime  = 0;
   g_inHigh  = 0.0;
   g_inLow   = 0.0;
   g_minLow  = 0.0;
   g_maxHigh = 0.0;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == g_lastBarTime)
      return;
   g_lastBarTime = currentBarTime;

   UpdateM15Impulse();

   datetime barTime = iTime(_Symbol, _Period, 1);
   if(barTime == 0)
      return;

   double high1  = iHigh(_Symbol, _Period, 1);
   double low1   = iLow(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   double close2 = iClose(_Symbol, _Period, 2);

   bool inZone = (g_zoneH != EMPTY_VALUE && g_zoneL != EMPTY_VALUE && high1 < g_zoneH && low1 > g_zoneL);

   bool canIN = g_waitingIN && g_m15ImpulseTime > 0 && barTime > g_m15ImpulseTime;
   if(canIN && inZone)
   {
      g_inTime  = barTime;
      g_inHigh  = high1;
      g_inLow   = low1;
      g_minLow  = low1;
      g_maxHigh = high1;
      g_waitingIN  = false;
      g_waitingOUT = true;
   }

   if(g_waitingOUT && g_inTime > 0)
   {
      g_minLow  = MathMin(g_minLow, low1);
      g_maxHigh = MathMax(g_maxHigh, high1);
   }

   bool prevUp   = (g_zoneH != EMPTY_VALUE && close2 > g_zoneH);
   bool prevDown = (g_zoneL != EMPTY_VALUE && close2 < g_zoneL);

   bool outUp   = (g_zoneH != EMPTY_VALUE && close1 > g_zoneH && low1 > g_zoneH && prevUp);
   bool outDown = (g_zoneL != EMPTY_VALUE && close1 < g_zoneL && high1 < g_zoneL && prevDown);

   bool noRevBuy  = g_waitingOUT && (g_minLow >= g_inLow);
   bool noRevSell = g_waitingOUT && (g_maxHigh <= g_inHigh);

   bool outBuy  = g_waitingOUT && outUp   && (low1  > g_inHigh) && noRevBuy;
   bool outSell = g_waitingOUT && outDown && (high1 < g_inLow)  && noRevSell;

   bool outSignal = (outBuy || outSell);
   if(!outSignal || barTime == g_lastOutTime)
      return;

   // Max zone bars filter - skip stale signals
   if(InpMaxZoneBars > 0 && g_m15ImpulseTime > 0)
   {
      int barsSinceImpulse = iBarShift(_Symbol, _Period, g_m15ImpulseTime, false);
      if(barsSinceImpulse > InpMaxZoneBars)
      {
         g_waitingOUT = false;
         return;
      }
   }

   // Time filter check
   if(InpUseTimeFilter)
   {
      MqlDateTime dt;
      TimeToStruct(barTime, dt);
      int hour = dt.hour;
      
      if(InpStartHour <= InpEndHour)
      {
         // Normal range: e.g. 8-20
         if(hour < InpStartHour || hour >= InpEndHour)
            return;
      }
      else
      {
         // Wrap-around: e.g. 20-4 (evening to early morning)
         if(hour < InpStartHour && hour >= InpEndHour)
            return;
      }
   }

   g_lastOutTime = barTime;

   double top    = 0.0;
   double bottom = 0.0;
   if(outBuy)
   {
      top    = low1;
      bottom = g_inHigh;
   }
   else if(outSell)
   {
      top    = g_inLow;
      bottom = high1;
   }

   double mid = (top + bottom) / 2.0;
   
   // Min zone size filter (in pips)
   double zoneSizePips = MathAbs(top - bottom) / (_Point * 10);
   if(InpMinZonePips > 0.0 && zoneSizePips < InpMinZonePips)
   {
      Print("Zone too small: ", DoubleToString(zoneSizePips, 1), " pips < ", DoubleToString(InpMinZonePips, 1));
      return;
   }
   
   // Apply SL and TP based on direction
   // For BUY:  SL at bottom (below entry), TP above entry
   // For SELL: SL at top (above entry), TP below entry
   double slBufferPrice = InpSLBufferPips * _Point * 10;
   double sl_price, tp_price, sl_dist;
   
   if(outBuy)
   {
      sl_price = bottom - slBufferPrice;           // SL below entry
      sl_dist  = MathAbs(mid - sl_price);
      tp_price = mid + sl_dist * InpTPMultiplier;   // TP above entry
   }
   else
   {
      sl_price = top + slBufferPrice;               // SL above entry
      sl_dist  = MathAbs(sl_price - mid);
      tp_price = mid - sl_dist * InpTPMultiplier;   // TP below entry
   }

   if(!InpOnePosition || !HasActiveOrders())
      PlaceFvgOrder(outBuy, mid, sl_price, tp_price, TimeCurrent());

   g_waitingOUT = false;
}
//+------------------------------------------------------------------+
