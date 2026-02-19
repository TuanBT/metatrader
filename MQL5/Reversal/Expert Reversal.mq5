//+------------------------------------------------------------------+
//| Expert Reversal.mq5                                             |
//| Reversal — Bollinger Band + RSI Mean Reversion                  |
//|                                                                  |
//| Logic:                                                           |
//|   1. Price closes beyond Bollinger Band (outer band touch)       |
//|   2. RSI confirms oversold (<30) for BUY, overbought (>70) SELL |
//|   3. Optional: require reversal candle on next bar              |
//|   4. SL = Beyond the extreme (band + ATR buffer)                |
//|   5. TP = Middle Bollinger Band (mean reversion target)          |
//|   6. Dynamic TP update to track middle BB movement              |
//|   7. Partial TP + Breakeven management                          |
//|                                                                  |
//| Target: 5-10 trades/month per pair on H1, high win rate          |
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
input double InpMaxRiskPct      = 5.0;       // Max Risk % per trade
input double InpMaxDailyLossPct = 5.0;       // Max Daily Loss %

// ============================================================================
// INPUTS — BOLLINGER BANDS
// ============================================================================
input int    InpBBPeriod        = 20;        // BB Period
input double InpBBDeviation     = 2.0;       // BB Deviation
input ENUM_APPLIED_PRICE InpBBPrice = PRICE_CLOSE; // BB Applied Price

// ============================================================================
// INPUTS — RSI
// ============================================================================
input int    InpRSIPeriod       = 14;        // RSI Period
input double InpRSIOverbought   = 70.0;      // RSI Overbought (trigger SELL)
input double InpRSIOversold     = 30.0;      // RSI Oversold (trigger BUY)

// ============================================================================
// INPUTS — CANDLE CONFIRMATION
// ============================================================================
input bool   InpRequireReversal = true;      // Require reversal candle

// ============================================================================
// INPUTS — SL/TP
// ============================================================================
input double InpSLBufferATR     = 0.7;       // SL buffer beyond band (ATR mult) [optimized: 0.5→0.7 for XAUUSD H1 wider wicks]
input int    InpATRPeriod       = 14;        // ATR Period
input bool   InpTPUseMidBB      = true;      // TP = Middle BB (mean reversion)
input double InpTPFixedRR       = 0;         // TP as RR (0=use Middle BB)
input int    InpMinSLPts        = 100;       // Minimum SL distance in points [optimized: 50→100 for XAUUSD H1]

// ============================================================================
// INPUTS — TRADE MANAGEMENT
// ============================================================================
input double InpBEAtR           = 0.5;       // Move SL to BE at X×R (0=disabled)
input bool   InpUsePartialTP    = true;      // Use Partial TP
input double InpPartialTPAtR    = 0.5;       // Close partial at X×R
input double InpPartialTPPct    = 50.0;      // % to close at partial TP

// ============================================================================
// INPUTS — GENERAL
// ============================================================================
input ulong  InpMagic           = 20260302;  // Magic Number

// ============================================================================
// CONSTANTS
// ============================================================================
#define DEVIATION 20

// ============================================================================
// GLOBAL STATE
// ============================================================================
int g_hBB, g_hRSI, g_hATR;
static datetime g_lastBarTime  = 0;
static bool     g_partialDone  = false;
static double   g_entryPrice   = 0;
static double   g_entrySL      = 0;
static double   g_dailyLoss    = 0;
static int      g_dailyDate    = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_hBB  = iBands(_Symbol, _Period, InpBBPeriod, 0, InpBBDeviation, InpBBPrice);
   g_hRSI = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   g_hATR = iATR(_Symbol, _Period, InpATRPeriod);

   if(g_hBB == INVALID_HANDLE || g_hRSI == INVALID_HANDLE || g_hATR == INVALID_HANDLE)
   {
      Print("❌ Failed to create indicator handles");
      return INIT_FAILED;
   }

   Print("ℹ️ Reversal: BB(", InpBBPeriod, ",", DoubleToString(InpBBDeviation, 1), ")",
         " | RSI(", InpRSIPeriod, ") OB=", DoubleToString(InpRSIOverbought, 0),
         " OS=", DoubleToString(InpRSIOversold, 0),
         " | Reversal=", InpRequireReversal ? "ON" : "OFF",
         " | TP=", InpTPUseMidBB ? "MidBB" : DoubleToString(InpTPFixedRR, 1) + "R",
         " | SLBuf=ATR×", DoubleToString(InpSLBufferATR, 1));
   Print("💰 Risk: Lot=", DoubleToString(InpLotSize, 2),
         " | MaxRisk=", DoubleToString(InpMaxRiskPct, 1), "%");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_hBB  != INVALID_HANDLE) IndicatorRelease(g_hBB);
   if(g_hRSI != INVALID_HANDLE) IndicatorRelease(g_hRSI);
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;

   if(!CheckDailyLoss()) return;

   ManagePositions();
   CheckSignals();
}

//+------------------------------------------------------------------+
//| Get BB, RSI, ATR values                                          |
//+------------------------------------------------------------------+
bool GetIndicators(int shift, double &bbUpper, double &bbMiddle, double &bbLower,
                   double &rsi, double &atr)
{
   double bufU[1], bufM[1], bufL[1], bufR[1], bufA[1];

   if(CopyBuffer(g_hBB, 1, shift, 1, bufU) != 1) return false;
   if(CopyBuffer(g_hBB, 0, shift, 1, bufM) != 1) return false;
   if(CopyBuffer(g_hBB, 2, shift, 1, bufL) != 1) return false;
   if(CopyBuffer(g_hRSI, 0, shift, 1, bufR) != 1) return false;
   if(CopyBuffer(g_hATR, 0, shift, 1, bufA) != 1) return false;

   bbUpper  = bufU[0];
   bbMiddle = bufM[0];
   bbLower  = bufL[0];
   rsi      = bufR[0];
   atr      = bufA[0];
   return true;
}

//+------------------------------------------------------------------+
//| CheckSignals                                                     |
//+------------------------------------------------------------------+
void CheckSignals()
{
   if(CountPositions() > 0) return;

   double bbU1, bbM1, bbL1, rsi1, atr1;
   double bbU2, bbM2, bbL2, rsi2, atr2;
   if(!GetIndicators(1, bbU1, bbM1, bbL1, rsi1, atr1)) return;
   if(!GetIndicators(2, bbU2, bbM2, bbL2, rsi2, atr2)) return;

   double close1 = iClose(_Symbol, _Period, 1);
   double open1  = iOpen(_Symbol, _Period, 1);
   double close2 = iClose(_Symbol, _Period, 2);
   double low1   = iLow(_Symbol, _Period, 1);
   double high1  = iHigh(_Symbol, _Period, 1);
   double low2   = iLow(_Symbol, _Period, 2);
   double high2  = iHigh(_Symbol, _Period, 2);

   bool signalBuy  = false;
   bool signalSell = false;

   if(InpRequireReversal)
   {
      bool zone_os = (close2 <= bbL2 || low2 <= bbL2) && (rsi2 <= InpRSIOversold);
      bool zone_ob = (close2 >= bbU2 || high2 >= bbU2) && (rsi2 >= InpRSIOverbought);
      bool bullish_reversal = (close1 > open1);
      bool bearish_reversal = (close1 < open1);

      if(zone_os && bullish_reversal && rsi1 > InpRSIOversold)
         signalBuy = true;
      if(zone_ob && bearish_reversal && rsi1 < InpRSIOverbought)
         signalSell = true;
   }
   else
   {
      if(close1 <= bbL1 && rsi1 <= InpRSIOversold)
         signalBuy = true;
      if(close1 >= bbU1 && rsi1 >= InpRSIOverbought)
         signalSell = true;
   }

   if(!signalBuy && !signalSell) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slBuffer = atr1 * InpSLBufferATR;
   double entry, sl, tp;
   bool isBuy = signalBuy;

   if(signalBuy)
   {
      entry = ask;
      sl    = NormalizeDouble(bbL1 - slBuffer, _Digits);
      double slDist = entry - sl;
      if(slDist < InpMinSLPts * _Point)
      {
         sl = NormalizeDouble(entry - InpMinSLPts * _Point, _Digits);
         slDist = entry - sl;
      }
      if(InpTPUseMidBB && InpTPFixedRR <= 0)
         tp = NormalizeDouble(bbM1, _Digits);
      else
         tp = NormalizeDouble(entry + slDist * InpTPFixedRR, _Digits);

      Print("📊 REVERSAL BUY: Close=", DoubleToString(close1, _Digits),
            " < BB_Lower=", DoubleToString(bbL1, _Digits),
            " | RSI=", DoubleToString(rsi1, 1),
            " | BB_Mid=", DoubleToString(bbM1, _Digits));
   }
   else
   {
      entry = bid;
      sl    = NormalizeDouble(bbU1 + slBuffer, _Digits);
      double slDist = sl - entry;
      if(slDist < InpMinSLPts * _Point)
      {
         sl = NormalizeDouble(entry + InpMinSLPts * _Point, _Digits);
         slDist = sl - entry;
      }
      if(InpTPUseMidBB && InpTPFixedRR <= 0)
         tp = NormalizeDouble(bbM1, _Digits);
      else
         tp = NormalizeDouble(entry - slDist * InpTPFixedRR, _Digits);

      Print("📊 REVERSAL SELL: Close=", DoubleToString(close1, _Digits),
            " > BB_Upper=", DoubleToString(bbU1, _Digits),
            " | RSI=", DoubleToString(rsi1, 1),
            " | BB_Mid=", DoubleToString(bbM1, _Digits));
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
   req.comment   = isBuy ? "Reversal_BUY" : "Reversal_SELL";

   if(OrderSend(req, res))
   {
      if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED)
      {
         g_partialDone = false;
         g_entryPrice  = entry;
         g_entrySL     = sl;
         Print("✅ Order placed: Lot=", DoubleToString(lot, 2));
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
            DoubleToString(InpMaxRiskPct, 1), "% | Balance=$",
            DoubleToString(balance, 2));
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
//| ManagePositions — BE + Partial TP + Dynamic BB TP                |
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
            req.comment   = "Reversal_PARTIAL";
            if(posType == POSITION_TYPE_BUY)
            { req.type = ORDER_TYPE_SELL; req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); }
            else
            { req.type = ORDER_TYPE_BUY;  req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); }

            if(OrderSend(req, res) && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED))
            {
               Print("🎯 PARTIAL TP: ", DoubleToString(closeLot, 2),
                     " lots at ", DoubleToString(rMult, 1), "R");
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
               Print("✅ SL moved to breakeven=", DoubleToString(newSL, _Digits));
         }
      }

      // Dynamic TP update: move TP to current middle BB
      if(InpTPUseMidBB && InpTPFixedRR <= 0)
      {
         double bbU, bbM, bbL, rsi, atr;
         if(GetIndicators(1, bbU, bbM, bbL, rsi, atr))
         {
            double newTP = NormalizeDouble(bbM, _Digits);
            if(MathAbs(newTP - posTP) > _Point * 5)
            {
               bool valid = (posType == POSITION_TYPE_BUY && newTP > curPrice) ||
                            (posType == POSITION_TYPE_SELL && newTP < curPrice);
               if(valid)
               {
                  MqlTradeRequest req;
                  MqlTradeResult  res;
                  ZeroMemory(req);
                  ZeroMemory(res);
                  req.action   = TRADE_ACTION_SLTP;
                  req.symbol   = _Symbol;
                  req.position = ticket;
                  req.sl       = posSL;
                  req.tp       = newTP;
                  OrderSend(req, res);
               }
            }
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
//| CheckDailyLoss                                                   |
//+------------------------------------------------------------------+
bool CheckDailyLoss()
{
   if(InpMaxDailyLossPct <= 0) return true;
   MqlDateTime dt;
   TimeCurrent(dt);
   int today = dt.day_of_year;
   if(today != g_dailyDate) { g_dailyDate = today; g_dailyLoss = 0; }

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
      Print("🚫 MAX DAILY LOSS: ", DoubleToString(todayLoss, 2));
      return false;
   }
   return true;
}
//+------------------------------------------------------------------+
