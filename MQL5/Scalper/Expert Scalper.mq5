//+------------------------------------------------------------------+
//| Expert Scalper.mq5                                              |
//| Scalper — EMA Crossover + RSI Filter                            |
//|                                                                  |
//| Logic:                                                           |
//|   1. Fast EMA crosses Slow EMA → trend direction                 |
//|   2. RSI confirms: not overbought for BUY, not oversold for SELL |
//|   3. Price must be on correct side of Trend EMA (trend filter)   |
//|   4. Entry on next bar open after confirmed cross                |
//|   5. SL = ATR-based (1.5 × ATR)                                 |
//|   6. TP = Fixed RR multiple of SL distance                      |
//|   7. Partial TP + Breakeven management                          |
//|   8. One position at a time, flip on reverse signal              |
//|                                                                  |
//| Target: 10-20+ trades/month per pair on M15                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MTS"
#property link      ""
#property version   "1.00"
#property strict

// ============================================================================
// INPUTS — POSITION SIZING & RISK
// ============================================================================
input bool   InpUseDynamicLot   = false;     // Use Dynamic Position Sizing
input double InpLotSize         = 0.02;      // Fixed Lot Size
input double InpRiskPct         = 2.0;       // Risk % per trade (dynamic)
input double InpMaxRiskPct      = 5.0;       // Max Risk % per trade (0=no limit)
input double InpMaxDailyLossPct = 5.0;       // Max Daily Loss % (0=no limit)

// ============================================================================
// INPUTS — EMA SETTINGS
// ============================================================================
input int    InpEMAFast         = 9;         // Fast EMA Period
input int    InpEMASlow         = 21;        // Slow EMA Period
input int    InpEMATrend        = 50;        // Trend EMA Period (0=disabled)

// ============================================================================
// INPUTS — RSI FILTER
// ============================================================================
input bool   InpUseRSI          = true;      // Use RSI Filter
input int    InpRSIPeriod       = 14;        // RSI Period
input double InpRSIOverbought   = 70.0;      // RSI Overbought (skip BUY above)
input double InpRSIOversold     = 30.0;      // RSI Oversold (skip SELL below)

// ============================================================================
// INPUTS — ATR & SL/TP
// ============================================================================
input int    InpATRPeriod       = 14;        // ATR Period for SL
input double InpATRMultSL       = 1.5;       // ATR Multiplier for SL
input double InpTPFixedRR       = 1.5;       // TP as RR multiple (0=use ATR exit)
input int    InpMinSLPts        = 50;        // Minimum SL distance in points

// ============================================================================
// INPUTS — TRADE MANAGEMENT
// ============================================================================
input double InpBEAtR           = 0.5;       // Move SL to BE at X×R (0=disabled)
input bool   InpUsePartialTP    = true;      // Use Partial TP
input double InpPartialTPAtR    = 1.0;       // Close partial at X×R
input double InpPartialTPPct    = 50.0;      // % to close at partial TP

// ============================================================================
// INPUTS — GENERAL
// ============================================================================
input ulong  InpMagic           = 20260301;  // Magic Number

// ============================================================================
// CONSTANTS
// ============================================================================
#define DEVIATION 20

// ============================================================================
// GLOBAL STATE
// ============================================================================
int g_hEMAFast, g_hEMASlow, g_hEMATrend, g_hRSI, g_hATR;
static datetime g_lastBarTime = 0;
static bool     g_partialDone = false;
static double   g_entryPrice  = 0;
static double   g_entrySL     = 0;
static double   g_dailyLoss   = 0;
static int      g_dailyDate   = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   // Create indicator handles
   g_hEMAFast  = iMA(_Symbol, _Period, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMASlow  = iMA(_Symbol, _Period, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMATrend = (InpEMATrend > 0) ? iMA(_Symbol, _Period, InpEMATrend, 0, MODE_EMA, PRICE_CLOSE) : INVALID_HANDLE;
   g_hRSI      = InpUseRSI ? iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE) : INVALID_HANDLE;
   g_hATR      = iATR(_Symbol, _Period, InpATRPeriod);

   if(g_hEMAFast == INVALID_HANDLE || g_hEMASlow == INVALID_HANDLE || g_hATR == INVALID_HANDLE)
   {
      Print("❌ Failed to create indicator handles");
      return INIT_FAILED;
   }

   Print("ℹ️ Scalper: EMA ", InpEMAFast, "/", InpEMASlow,
         " | Trend EMA=", InpEMATrend,
         " | RSI=", InpUseRSI ? IntegerToString(InpRSIPeriod) : "OFF",
         " | ATR=", InpATRPeriod, "×", DoubleToString(InpATRMultSL, 1),
         " | TP_RR=", DoubleToString(InpTPFixedRR, 1),
         " | BE@", DoubleToString(InpBEAtR, 1), "R");
   Print("💰 Risk: DynamicLot=", InpUseDynamicLot ? "ON" : "OFF",
         " | Lot=", DoubleToString(InpLotSize, 2),
         " | Risk%=", DoubleToString(InpRiskPct, 1),
         " | MaxRisk%=", DoubleToString(InpMaxRiskPct, 1),
         " | MaxDailyLoss%=", DoubleToString(InpMaxDailyLossPct, 1));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_hEMAFast  != INVALID_HANDLE) IndicatorRelease(g_hEMAFast);
   if(g_hEMASlow  != INVALID_HANDLE) IndicatorRelease(g_hEMASlow);
   if(g_hEMATrend != INVALID_HANDLE) IndicatorRelease(g_hEMATrend);
   if(g_hRSI      != INVALID_HANDLE) IndicatorRelease(g_hRSI);
   if(g_hATR      != INVALID_HANDLE) IndicatorRelease(g_hATR);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only process on new bar
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;

   // Check daily loss limit
   if(!CheckDailyLoss()) return;

   // Manage existing positions (BE + Partial TP)
   ManagePositions();

   // Check for new signals on completed bar (bar index 1)
   CheckSignals();
}

//+------------------------------------------------------------------+
//| CheckDailyLoss — track daily P/L                                 |
//+------------------------------------------------------------------+
bool CheckDailyLoss()
{
   if(InpMaxDailyLossPct <= 0) return true;

   MqlDateTime dt;
   TimeCurrent(dt);
   int today = dt.day_of_year;

   if(today != g_dailyDate)
   {
      g_dailyDate = today;
      g_dailyLoss = 0;
   }

   // Calculate today's realized losses
   double todayLoss = 0;
   HistorySelect(StringToTime(TimeToString(TimeCurrent(), TIME_DATE)), TimeCurrent());
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)InpMagic) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      todayLoss += HistoryDealGetDouble(ticket, DEAL_PROFIT);
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double maxLoss = balance * InpMaxDailyLossPct / 100.0;
   if(todayLoss < 0 && MathAbs(todayLoss) >= maxLoss)
   {
      static datetime lastWarnDay = 0;
      if(lastWarnDay != StringToTime(TimeToString(TimeCurrent(), TIME_DATE)))
      {
         Print("🚫 MAX DAILY LOSS reached: ", DoubleToString(todayLoss, 2),
               " | Limit: -", DoubleToString(maxLoss, 2));
         lastWarnDay = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
      }
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Get indicator values                                             |
//+------------------------------------------------------------------+
bool GetIndicators(int shift, double &emaFast, double &emaSlow, double &emaTrend,
                   double &rsi, double &atr)
{
   double bufF[1], bufS[1], bufT[1], bufR[1], bufA[1];

   if(CopyBuffer(g_hEMAFast, 0, shift, 1, bufF) != 1) return false;
   if(CopyBuffer(g_hEMASlow, 0, shift, 1, bufS) != 1) return false;
   if(CopyBuffer(g_hATR,     0, shift, 1, bufA) != 1) return false;

   emaFast = bufF[0];
   emaSlow = bufS[0];
   atr     = bufA[0];

   if(g_hEMATrend != INVALID_HANDLE)
   {
      if(CopyBuffer(g_hEMATrend, 0, shift, 1, bufT) != 1) return false;
      emaTrend = bufT[0];
   }
   else emaTrend = 0;

   if(g_hRSI != INVALID_HANDLE)
   {
      if(CopyBuffer(g_hRSI, 0, shift, 1, bufR) != 1) return false;
      rsi = bufR[0];
   }
   else rsi = 50.0; // Neutral

   return true;
}

//+------------------------------------------------------------------+
//| CheckSignals — detect EMA crossover on bar 1                     |
//+------------------------------------------------------------------+
void CheckSignals()
{
   double emaFast1, emaSlow1, emaTrend1, rsi1, atr1;
   double emaFast2, emaSlow2, emaTrend2, rsi2, atr2;

   if(!GetIndicators(1, emaFast1, emaSlow1, emaTrend1, rsi1, atr1)) return;
   if(!GetIndicators(2, emaFast2, emaSlow2, emaTrend2, rsi2, atr2)) return;

   bool crossUp   = (emaFast2 <= emaSlow2) && (emaFast1 > emaSlow1);
   bool crossDown = (emaFast2 >= emaSlow2) && (emaFast1 < emaSlow1);

   if(!crossUp && !crossDown) return;

   // Trend filter
   double close1 = iClose(_Symbol, _Period, 1);
   if(InpEMATrend > 0 && emaTrend1 != 0)
   {
      if(crossUp && close1 < emaTrend1)
      {
         Print("🚫 TREND FILTER: BUY blocked (price ", DoubleToString(close1, _Digits),
               " < EMA", InpEMATrend, "=", DoubleToString(emaTrend1, _Digits), ")");
         return;
      }
      if(crossDown && close1 > emaTrend1)
      {
         Print("🚫 TREND FILTER: SELL blocked (price ", DoubleToString(close1, _Digits),
               " > EMA", InpEMATrend, "=", DoubleToString(emaTrend1, _Digits), ")");
         return;
      }
   }

   // RSI filter
   if(InpUseRSI)
   {
      if(crossUp && rsi1 >= InpRSIOverbought)
      {
         Print("🚫 RSI FILTER: BUY blocked (RSI=", DoubleToString(rsi1, 1),
               " >= ", DoubleToString(InpRSIOverbought, 0), ")");
         return;
      }
      if(crossDown && rsi1 <= InpRSIOversold)
      {
         Print("🚫 RSI FILTER: SELL blocked (RSI=", DoubleToString(rsi1, 1),
               " <= ", DoubleToString(InpRSIOversold, 0), ")");
         return;
      }
   }

   // Calculate SL/TP
   double slDist = atr1 * InpATRMultSL;
   double minSL  = InpMinSLPts * _Point;
   if(slDist < minSL) slDist = minSL;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool isBuy = crossUp;
   double entry, sl, tp;

   if(isBuy)
   {
      entry = ask;
      sl    = NormalizeDouble(entry - slDist, _Digits);
      tp    = (InpTPFixedRR > 0) ? NormalizeDouble(entry + slDist * InpTPFixedRR, _Digits) : 0;
   }
   else
   {
      entry = bid;
      sl    = NormalizeDouble(entry + slDist, _Digits);
      tp    = (InpTPFixedRR > 0) ? NormalizeDouble(entry - slDist * InpTPFixedRR, _Digits) : 0;
   }

   // Risk check
   if(!CheckMaxRisk(isBuy, entry, sl)) return;

   // Close existing opposite positions
   ClosePositions(!isBuy);

   // Check if already have same-direction position
   if(HasPosition(isBuy))
   {
      Print("ℹ️ Already have ", (isBuy ? "BUY" : "SELL"), " position, skip");
      return;
   }

   // Calculate lot
   double lot = CalculateLot(entry, sl);

   Print("🔄 PlaceOrder: ", (isBuy ? "BUY" : "SELL"),
         " Entry=", DoubleToString(entry, _Digits),
         " SL=", DoubleToString(sl, _Digits),
         " TP=", DoubleToString(tp, _Digits),
         " | ATR=", DoubleToString(atr1, _Digits),
         " | RSI=", DoubleToString(rsi1, 1));

   // Place market order using raw OrderSend
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
   req.comment   = isBuy ? "Scalper_BUY" : "Scalper_SELL";

   if(OrderSend(req, res))
   {
      if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED)
      {
         g_partialDone = false;
         g_entryPrice  = entry;
         g_entrySL     = sl;
         Print("✅ Order placed: Lot=", DoubleToString(lot, 2),
               " | Retcode=", res.retcode);
      }
      else
         Print("❌ Order failed: retcode=", res.retcode,
               " comment=", res.comment);
   }
   else
      Print("❌ OrderSend failed: retcode=", res.retcode,
            " comment=", res.comment);
}

//+------------------------------------------------------------------+
//| CheckMaxRisk                                                     |
//+------------------------------------------------------------------+
bool CheckMaxRisk(bool isBuy, double entry, double sl)
{
   if(InpMaxRiskPct <= 0) return true;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double lot     = CalculateLot(entry, sl);

   double profitSL;
   ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(orderType, _Symbol, lot, entry, sl, profitSL))
   {
      Print("⚠️ OrderCalcProfit failed, allowing trade");
      return true;
   }

   double riskPct = (balance > 0) ? MathAbs(profitSL) / balance * 100.0 : 0;
   if(riskPct > InpMaxRiskPct)
   {
      Print("🚫 MAX RISK EXCEEDED: ", DoubleToString(riskPct, 1), "% ($",
            DoubleToString(MathAbs(profitSL), 2), ") > MaxRisk=",
            DoubleToString(InpMaxRiskPct, 1), "% | Balance=$",
            DoubleToString(balance, 2));
      return false;
   }

   Print("✅ Risk OK: ", DoubleToString(riskPct, 2), "% ($",
         DoubleToString(MathAbs(profitSL), 2), ") ≤ MaxRisk=",
         DoubleToString(InpMaxRiskPct, 1), "% | Balance=$",
         DoubleToString(balance, 2));
   return true;
}

//+------------------------------------------------------------------+
//| CalculateLot                                                     |
//+------------------------------------------------------------------+
double CalculateLot(double entry, double sl)
{
   if(!InpUseDynamicLot) return InpLotSize;

   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt  = balance * InpRiskPct / 100.0;
   double slDist   = MathAbs(entry - sl);
   if(slDist <= 0) return InpLotSize;

   double profitForOneLot;
   if(!OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, entry,
                       entry - slDist, profitForOneLot))
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
                          ? curPrice - posEntry
                          : posEntry - curPrice;
      double rMultiple  = profitDist / riskDist;

      // Partial TP
      if(InpUsePartialTP && !g_partialDone && InpPartialTPAtR > 0 && rMultiple >= InpPartialTPAtR)
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
            req.comment   = "Scalper_PARTIAL";

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

            if(OrderSend(req, res) && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED))
            {
               Print("🎯 PARTIAL TP: Closed ", DoubleToString(closeLot, 2),
                     " lots at ", DoubleToString(rMultiple, 1), "R");
               g_partialDone = true;
            }
         }
      }

      // Breakeven
      if(InpBEAtR > 0 && rMultiple >= InpBEAtR)
      {
         bool needBE = false;
         if(posType == POSITION_TYPE_BUY && posSL < posEntry)  needBE = true;
         if(posType == POSITION_TYPE_SELL && posSL > posEntry)  needBE = true;

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
            {
               Print("✅ SL moved to breakeven=", DoubleToString(newSL, _Digits),
                     " at ", DoubleToString(rMultiple, 1), "R");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| HasPosition                                                      |
//+------------------------------------------------------------------+
bool HasPosition(bool checkBuy)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long pType = PositionGetInteger(POSITION_TYPE);
      if(checkBuy && pType == POSITION_TYPE_BUY) return true;
      if(!checkBuy && pType == POSITION_TYPE_SELL) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| ClosePositions — close by direction                              |
//+------------------------------------------------------------------+
void ClosePositions(bool closeBuy)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long pType = PositionGetInteger(POSITION_TYPE);
      bool shouldClose = (closeBuy && pType == POSITION_TYPE_BUY) ||
                         (!closeBuy && pType == POSITION_TYPE_SELL);
      if(!shouldClose) continue;

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
      req.comment   = "Scalper_FLIP";

      if(pType == POSITION_TYPE_BUY)
      {
         req.type  = ORDER_TYPE_SELL;
         req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      }
      else
      {
         req.type  = ORDER_TYPE_BUY;
         req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      }

      if(OrderSend(req, res) && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED))
         Print("🔄 Closed ", (closeBuy ? "BUY" : "SELL"), " position (flip signal)");
   }
}
//+------------------------------------------------------------------+
