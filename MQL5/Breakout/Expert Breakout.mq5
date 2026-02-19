//+------------------------------------------------------------------+
//| Expert Breakout.mq5                                             |
//| Breakout — Session Range Breakout                               |
//|                                                                  |
//| Logic:                                                           |
//|   1. Track Asian session range (configurable hours)              |
//|   2. During London/NY session, wait for breakout of range        |
//|   3. Entry on close beyond range high/low                        |
//|   4. SL = opposite side of range (+ buffer)                     |
//|   5. TP = RR multiple or range size extension                   |
//|   6. Max trades per day                                         |
//|   7. Close all trades at end of NY session                      |
//|                                                                  |
//| Target: 1 trade/day = ~20 trades/month, consistent              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MTS"
#property link      ""
#property version   "1.00"
#property strict

// ============================================================================
// INPUTS — POSITION SIZING
// ============================================================================
input bool   InpUseDynamicLot   = false;     // Use Dynamic Position Sizing
input double InpLotSize         = 0.02;      // Fixed Lot Size
input double InpRiskPct         = 2.0;       // Risk % per trade (dynamic)
input double InpMaxRiskPct      = 5.0;       // Max Risk % per trade

// ============================================================================
// INPUTS — SESSION TIMES (Server time)
// ============================================================================
input int    InpRangeStartHour  = 0;         // Range Start Hour (Asian session)
input int    InpRangeEndHour    = 8;         // Range End Hour
input int    InpTradeStartHour  = 8;         // Trade Start Hour (London open)
input int    InpTradeEndHour    = 18;        // Trade End Hour
input int    InpGMTOffset       = 2;         // Server GMT Offset (Exness=GMT+2)

// ============================================================================
// INPUTS — BREAKOUT SETTINGS
// ============================================================================
input int    InpBreakoutBuffer  = 0;         // Breakout buffer (points)
input double InpMinRangePts     = 100;       // Minimum range size (points)
input double InpMaxRangePts     = 1000;      // Maximum range size (points)
input bool   InpRequireClose    = true;      // Require candle CLOSE beyond range

// ============================================================================
// INPUTS — SL/TP
// ============================================================================
input double InpSLBufferPct     = 10;        // SL buffer % beyond opposite range
input double InpTPRR            = 1.5;       // TP as RR multiple
input bool   InpTPRangeExt      = false;     // TP = range extension (override RR)

// ============================================================================
// INPUTS — TRADE MANAGEMENT
// ============================================================================
input double InpBEAtR           = 0.5;       // Move SL to BE at X×R (0=disabled)
input bool   InpUsePartialTP    = true;      // Use Partial TP
input double InpPartialTPAtR    = 1.0;       // Close partial at X×R
input double InpPartialTPPct    = 50.0;      // % to close at partial TP
input bool   InpCloseAtEndDay   = true;      // Close all at trade end hour
input int    InpMaxTradesPerDay = 2;         // Max trades per day (0=unlimited)

// ============================================================================
// INPUTS — GENERAL
// ============================================================================
input ulong  InpMagic           = 20260303;  // Magic Number

// ============================================================================
// CONSTANTS
// ============================================================================
#define DEVIATION 20

// ============================================================================
// GLOBAL STATE
// ============================================================================
static datetime g_lastBarTime    = 0;
static double   g_rangeHigh      = 0;
static double   g_rangeLow       = 0;
static bool     g_rangeSet       = false;
static int      g_rangeDate      = 0;
static bool     g_tradedBuyToday = false;
static bool     g_tradedSellToday = false;
static int      g_tradeDateTrack = 0;
static int      g_tradesToday    = 0;
static bool     g_partialDone    = false;
static double   g_entryPrice     = 0;
static double   g_entrySL        = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("ℹ️ Breakout: Range=", InpRangeStartHour, ":00-", InpRangeEndHour, ":00",
         " | Trade=", InpTradeStartHour, ":00-", InpTradeEndHour, ":00",
         " | GMT+", InpGMTOffset);
   Print("📊 Settings: MinRange=", DoubleToString(InpMinRangePts, 0), "pts",
         " | MaxRange=", DoubleToString(InpMaxRangePts, 0), "pts",
         " | TP_RR=", DoubleToString(InpTPRR, 1),
         " | CloseEOD=", InpCloseAtEndDay ? "ON" : "OFF",
         " | MaxTrades=", InpMaxTradesPerDay);
   Print("💰 Risk: Lot=", DoubleToString(InpLotSize, 2),
         " | MaxRisk=", DoubleToString(InpMaxRiskPct, 1), "%");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;

   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   int dayOfYear = dt.day_of_year;

   // Reset daily tracking
   if(dayOfYear != g_tradeDateTrack)
   {
      g_tradeDateTrack  = dayOfYear;
      g_tradedBuyToday  = false;
      g_tradedSellToday = false;
      g_tradesToday     = 0;
      g_rangeSet        = false;
      g_rangeHigh       = 0;
      g_rangeLow        = DBL_MAX;
      g_rangeDate       = dayOfYear;
   }

   // Phase 1: Build range during Asian session
   if(hour >= InpRangeStartHour && hour < InpRangeEndHour)
   {
      BuildRange();
   }
   // Phase 2: Lock range
   else if(hour >= InpRangeEndHour && !g_rangeSet && g_rangeLow < DBL_MAX)
   {
      g_rangeSet = true;
      double rangePts = (g_rangeHigh - g_rangeLow) / _Point;
      Print("📐 Range set: High=", DoubleToString(g_rangeHigh, _Digits),
            " Low=", DoubleToString(g_rangeLow, _Digits),
            " | Size=", DoubleToString(rangePts, 0), " pts");
   }

   // Phase 3: Look for breakout
   if(hour >= InpTradeStartHour && hour < InpTradeEndHour && g_rangeSet)
   {
      ManagePositions();
      CheckBreakout();
   }

   // Phase 4: EOD Close
   if(hour >= InpTradeEndHour && InpCloseAtEndDay)
   {
      CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| BuildRange                                                       |
//+------------------------------------------------------------------+
void BuildRange()
{
   double high1 = iHigh(_Symbol, _Period, 1);
   double low1  = iLow(_Symbol, _Period, 1);

   if(high1 > g_rangeHigh) g_rangeHigh = high1;
   if(low1 < g_rangeLow)   g_rangeLow  = low1;
}

//+------------------------------------------------------------------+
//| CheckBreakout                                                    |
//+------------------------------------------------------------------+
void CheckBreakout()
{
   if(!g_rangeSet) return;

   double rangePts = (g_rangeHigh - g_rangeLow) / _Point;
   if(rangePts < InpMinRangePts || rangePts > InpMaxRangePts) return;

   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay) return;
   if(CountPositions() > 0) return;

   double close1 = iClose(_Symbol, _Period, 1);
   double high1  = iHigh(_Symbol, _Period, 1);
   double low1   = iLow(_Symbol, _Period, 1);
   double bufferDist = InpBreakoutBuffer * _Point;

   bool breakUp   = false;
   bool breakDown = false;

   if(InpRequireClose)
   {
      breakUp   = (close1 > g_rangeHigh + bufferDist) && !g_tradedBuyToday;
      breakDown = (close1 < g_rangeLow - bufferDist)  && !g_tradedSellToday;
   }
   else
   {
      breakUp   = (high1 > g_rangeHigh + bufferDist) && !g_tradedBuyToday;
      breakDown = (low1 < g_rangeLow - bufferDist)    && !g_tradedSellToday;
   }

   if(!breakUp && !breakDown) return;

   double rangeSize = g_rangeHigh - g_rangeLow;
   double slBuffer  = rangeSize * InpSLBufferPct / 100.0;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double entry, sl, tp;
   bool isBuy = breakUp;

   if(breakUp)
   {
      entry = ask;
      sl    = NormalizeDouble(g_rangeLow - slBuffer, _Digits);
      double slDist = entry - sl;
      if(InpTPRangeExt)
         tp = NormalizeDouble(g_rangeHigh + rangeSize, _Digits);
      else
         tp = NormalizeDouble(entry + slDist * InpTPRR, _Digits);

      Print("📈 BREAKOUT UP: Close=", DoubleToString(close1, _Digits),
            " > RangeHigh=", DoubleToString(g_rangeHigh, _Digits),
            " | Range=", DoubleToString(rangePts, 0), "pts");
   }
   else
   {
      entry = bid;
      sl    = NormalizeDouble(g_rangeHigh + slBuffer, _Digits);
      double slDist = sl - entry;
      if(InpTPRangeExt)
         tp = NormalizeDouble(g_rangeLow - rangeSize, _Digits);
      else
         tp = NormalizeDouble(entry - slDist * InpTPRR, _Digits);

      Print("📉 BREAKOUT DOWN: Close=", DoubleToString(close1, _Digits),
            " < RangeLow=", DoubleToString(g_rangeLow, _Digits),
            " | Range=", DoubleToString(rangePts, 0), "pts");
   }

   if(!CheckMaxRisk(isBuy, entry, sl)) return;

   double lot = CalculateLot(entry, sl);

   Print("🔄 PlaceOrder: ", (isBuy ? "BUY" : "SELL"),
         " Entry=", DoubleToString(entry, _Digits),
         " SL=", DoubleToString(sl, _Digits),
         " TP=", DoubleToString(tp, _Digits));

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price     = isBuy ? ask : bid;
   req.sl        = sl;
   req.tp        = tp;
   req.magic     = InpMagic;
   req.deviation = DEVIATION;
   req.comment   = isBuy ? "Breakout_BUY" : "Breakout_SELL";

   if(OrderSend(req, res))
   {
      if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED)
      {
         if(isBuy)  g_tradedBuyToday  = true;
         else       g_tradedSellToday = true;
         g_tradesToday++;
         g_partialDone = false;
         g_entryPrice  = entry;
         g_entrySL     = sl;
         Print("✅ Order placed: Lot=", DoubleToString(lot, 2),
               " | Trade #", g_tradesToday, " today");
      }
      else
         Print("❌ Order failed: retcode=", res.retcode);
   }
   else
      Print("❌ OrderSend failed: retcode=", res.retcode);
}

//+------------------------------------------------------------------+
//| CheckMaxRisk                                                     |
//+------------------------------------------------------------------+
bool CheckMaxRisk(bool isBuy, double entry, double sl)
{
   if(InpMaxRiskPct <= 0) return true;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double lot = CalculateLot(entry, sl);
   double profitSL;
   ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(orderType, _Symbol, lot, entry, sl, profitSL))
      return true;
   double riskPct = (balance > 0) ? MathAbs(profitSL) / balance * 100.0 : 0;
   if(riskPct > InpMaxRiskPct)
   {
      Print("🚫 MAX RISK EXCEEDED: ", DoubleToString(riskPct, 1), "% > ",
            DoubleToString(InpMaxRiskPct, 1), "%");
      return false;
   }
   Print("✅ Risk OK: ", DoubleToString(riskPct, 2), "% | Balance=$",
         DoubleToString(balance, 2));
   return true;
}

//+------------------------------------------------------------------+
//| CalculateLot                                                     |
//+------------------------------------------------------------------+
double CalculateLot(double entry, double sl)
{
   if(!InpUseDynamicLot) return InpLotSize;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt = balance * InpRiskPct / 100.0;
   double slDist  = MathAbs(entry - sl);
   if(slDist <= 0) return InpLotSize;
   double profitForOneLot;
   if(!OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, entry, entry - slDist, profitForOneLot))
      return InpLotSize;
   double lossPerLot = MathAbs(profitForOneLot);
   if(lossPerLot <= 0) return InpLotSize;
   double lot = riskAmt / lossPerLot;
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| ManagePositions — BE + Partial TP                                |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double posEntry = PositionGetDouble(POSITION_PRICE_OPEN);
      double posSL    = PositionGetDouble(POSITION_SL);
      double posTP    = PositionGetDouble(POSITION_TP);
      double posLot   = PositionGetDouble(POSITION_VOLUME);
      long   posType  = PositionGetInteger(POSITION_TYPE);
      double curPrice = (posType == POSITION_TYPE_BUY)
                        ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double riskDist = MathAbs(posEntry - g_entrySL);
      if(riskDist <= 0) riskDist = MathAbs(posEntry - posSL);
      if(riskDist <= 0) continue;

      double profitDist = (posType == POSITION_TYPE_BUY)
                          ? curPrice - posEntry : posEntry - curPrice;
      double rMult = profitDist / riskDist;

      // Partial TP
      if(InpUsePartialTP && !g_partialDone && InpPartialTPAtR > 0 && rMult >= InpPartialTPAtR)
      {
         double closeLot = NormalizeDouble(posLot * InpPartialTPPct / 100.0,
                           (int)MathLog10(1.0 / SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)));
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(closeLot >= minLot)
         {
            MqlTradeRequest req;
            MqlTradeResult  res;
            ZeroMemory(req);
            ZeroMemory(res);
            req.action    = TRADE_ACTION_DEAL;
            req.symbol    = _Symbol;
            req.volume    = closeLot;
            req.deviation = DEVIATION;
            req.magic     = InpMagic;
            req.position  = ticket;
            req.comment   = "Breakout_PARTIAL";
            if(posType == POSITION_TYPE_BUY)
            { req.type = ORDER_TYPE_SELL; req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); }
            else
            { req.type = ORDER_TYPE_BUY;  req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); }

            if(OrderSend(req, res) && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED))
            {
               Print("🎯 PARTIAL TP: ", DoubleToString(closeLot, 2), " lots at ",
                     DoubleToString(rMult, 1), "R");
               g_partialDone = true;
            }
         }
      }

      // Breakeven
      if(InpBEAtR > 0 && rMult >= InpBEAtR)
      {
         bool needBE = (posType == POSITION_TYPE_BUY && posSL < posEntry) ||
                       (posType == POSITION_TYPE_SELL && posSL > posEntry);
         if(needBE)
         {
            double newSL = NormalizeDouble(posEntry, _Digits);
            MqlTradeRequest req;
            MqlTradeResult  res;
            ZeroMemory(req);
            ZeroMemory(res);
            req.action   = TRADE_ACTION_SLTP;
            req.symbol   = _Symbol;
            req.position = ticket;
            req.sl       = newSL;
            req.tp       = posTP;

            if(OrderSend(req, res) && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED))
               Print("✅ Breakeven at ", DoubleToString(newSL, _Digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CountPositions                                                   |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| CloseAllPositions — EOD close                                    |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
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
      req.deviation = DEVIATION;
      req.magic     = InpMagic;
      req.position  = ticket;
      req.comment   = "Breakout_EOD";

      long posType = PositionGetInteger(POSITION_TYPE);
      if(posType == POSITION_TYPE_BUY)
      { req.type = ORDER_TYPE_SELL; req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); }
      else
      { req.type = ORDER_TYPE_BUY;  req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); }

      if(OrderSend(req, res) && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED))
         Print("🔒 EOD Close: Position closed");
   }
}
//+------------------------------------------------------------------+
