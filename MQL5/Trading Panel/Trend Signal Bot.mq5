//+------------------------------------------------------------------+
//| Trend Signal Bot.mq5                                              |
//| Multi-TF EMA Cross trend-following bot                            |
//| Entry: EMA 20/50 cross on M5                                      |
//| Filter: M15 + H1 EMA alignment                                    |
//+------------------------------------------------------------------+
#property copyright "Tuan"
#property version   "1.00"
#property strict

// ════════════════════════════════════════════════════════════════════
// INPUTS
// ════════════════════════════════════════════════════════════════════
input group           "══ Strategy ══"
input int             InpEMAFast        = 20;         // EMA Fast period
input int             InpEMASlow        = 50;         // EMA Slow period
input ENUM_TIMEFRAMES InpTFEntry        = PERIOD_M5;  // Entry timeframe
input ENUM_TIMEFRAMES InpTFMid          = PERIOD_M15; // Mid filter timeframe
input ENUM_TIMEFRAMES InpTFHigh         = PERIOD_H1;  // High filter timeframe

input group           "══ Risk ══"
input double          InpRiskMoney      = 10.0;       // Risk per trade ($)
input double          InpATRMult        = 1.5;        // ATR multiplier for SL
input int             InpATRPeriod      = 14;         // ATR period
input double          InpRRRatio        = 2.0;        // Risk:Reward ratio for TP
input int             InpDeviation      = 20;         // Max slippage (points)

input group           "══ General ══"
input ulong           InpMagic          = 99999;      // Magic Number

// ════════════════════════════════════════════════════════════════════
// GLOBALS
// ════════════════════════════════════════════════════════════════════
int g_emaFastEntry, g_emaSlowEntry;   // M5 EMA handles
int g_emaFastMid,   g_emaSlowMid;     // M15 EMA handles
int g_emaFastHigh,  g_emaSlowHigh;    // H1 EMA handles
int g_atrHandle;                       // ATR handle (entry TF)

datetime g_lastSignalBar = 0;          // Prevent multiple entries on same bar

// ════════════════════════════════════════════════════════════════════
// INIT / DEINIT
// ════════════════════════════════════════════════════════════════════
int OnInit()
{
   // Create EMA handles for each timeframe
   g_emaFastEntry = iMA(_Symbol, InpTFEntry, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowEntry = iMA(_Symbol, InpTFEntry, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   g_emaFastMid   = iMA(_Symbol, InpTFMid,   InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowMid   = iMA(_Symbol, InpTFMid,   InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   g_emaFastHigh  = iMA(_Symbol, InpTFHigh,  InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowHigh  = iMA(_Symbol, InpTFHigh,  InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   g_atrHandle    = iATR(_Symbol, InpTFEntry, InpATRPeriod);

   if(g_emaFastEntry == INVALID_HANDLE || g_emaSlowEntry == INVALID_HANDLE ||
      g_emaFastMid   == INVALID_HANDLE || g_emaSlowMid   == INVALID_HANDLE ||
      g_emaFastHigh  == INVALID_HANDLE || g_emaSlowHigh  == INVALID_HANDLE ||
      g_atrHandle    == INVALID_HANDLE)
   {
      Print("[TREND BOT] Failed to create indicator handles");
      return INIT_FAILED;
   }

   Print(StringFormat("[TREND BOT] Started | %s | Magic=%d | EMA %d/%d | TF=%s/%s/%s | Risk=$%.0f",
         _Symbol, InpMagic, InpEMAFast, InpEMASlow,
         EnumToString(InpTFEntry), EnumToString(InpTFMid), EnumToString(InpTFHigh),
         InpRiskMoney));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_emaFastEntry != INVALID_HANDLE) IndicatorRelease(g_emaFastEntry);
   if(g_emaSlowEntry != INVALID_HANDLE) IndicatorRelease(g_emaSlowEntry);
   if(g_emaFastMid   != INVALID_HANDLE) IndicatorRelease(g_emaFastMid);
   if(g_emaSlowMid   != INVALID_HANDLE) IndicatorRelease(g_emaSlowMid);
   if(g_emaFastHigh  != INVALID_HANDLE) IndicatorRelease(g_emaFastHigh);
   if(g_emaSlowHigh  != INVALID_HANDLE) IndicatorRelease(g_emaSlowHigh);
   if(g_atrHandle    != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   Print("[TREND BOT] Stopped");
}

// ════════════════════════════════════════════════════════════════════
// ONTICK
// ════════════════════════════════════════════════════════════════════
void OnTick()
{
   // Only check on new bar (entry TF)
   datetime curBar = iTime(_Symbol, InpTFEntry, 0);
   if(curBar == g_lastSignalBar) return;

   // Skip if already have a position
   if(HasPosition()) return;

   // ── Get EMA values ──
   double entryFast[2], entrySlow[2];  // [0]=current bar, [1]=prev bar
   double midFast[1], midSlow[1];
   double highFast[1], highSlow[1];
   double atr[1];

   if(CopyBuffer(g_emaFastEntry, 0, 1, 2, entryFast) != 2) return;
   if(CopyBuffer(g_emaSlowEntry, 0, 1, 2, entrySlow) != 2) return;
   if(CopyBuffer(g_emaFastMid,   0, 1, 1, midFast)   != 1) return;
   if(CopyBuffer(g_emaSlowMid,   0, 1, 1, midSlow)   != 1) return;
   if(CopyBuffer(g_emaFastHigh,  0, 1, 1, highFast)   != 1) return;
   if(CopyBuffer(g_emaSlowHigh,  0, 1, 1, highSlow)   != 1) return;
   if(CopyBuffer(g_atrHandle,    0, 1, 1, atr)        != 1) return;

   if(atr[0] <= 0) return;

   // ── Check H1 filter (EMA alignment) ──
   bool h1Up   = (highFast[0] > highSlow[0]);
   bool h1Down = (highFast[0] < highSlow[0]);

   // ── Check M15 filter (EMA alignment) ──
   bool m15Up   = (midFast[0] > midSlow[0]);
   bool m15Down = (midFast[0] < midSlow[0]);

   // ── Check M5 entry signal (EMA cross) ──
   // Cross up: prev bar fast <= slow, current bar fast > slow
   bool crossUp   = (entryFast[0] <= entrySlow[0]) && (entryFast[1] > entrySlow[1]);
   bool crossDown = (entryFast[0] >= entrySlow[0]) && (entryFast[1] < entrySlow[1]);

   // ── BUY signal: M5 cross up + M15 up + H1 up ──
   if(crossUp && m15Up && h1Up)
   {
      g_lastSignalBar = curBar;
      OpenTrade(true, atr[0]);
      return;
   }

   // ── SELL signal: M5 cross down + M15 down + H1 down ──
   if(crossDown && m15Down && h1Down)
   {
      g_lastSignalBar = curBar;
      OpenTrade(false, atr[0]);
      return;
   }
}

// ════════════════════════════════════════════════════════════════════
// TRADE FUNCTIONS
// ════════════════════════════════════════════════════════════════════
void OpenTrade(bool isBuy, double atrValue)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   // SL distance = ATR × mult
   double slDist = atrValue * InpATRMult;
   double tpDist = slDist * InpRRRatio;

   // Calculate lot from risk
   double lot = 0;
   if(tickSz > 0 && tickVal > 0 && slDist > 0)
      lot = InpRiskMoney / ((slDist / tickSz) * tickVal);

   // Clip to broker limits
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0)
      lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));

   double price, sl, tp;
   ENUM_ORDER_TYPE orderType;

   if(isBuy)
   {
      orderType = ORDER_TYPE_BUY;
      price = ask;
      sl = NormalizeDouble(price - slDist, _Digits);
      tp = NormalizeDouble(price + tpDist, _Digits);
   }
   else
   {
      orderType = ORDER_TYPE_SELL;
      price = bid;
      sl = NormalizeDouble(price + slDist, _Digits);
      tp = NormalizeDouble(price - tpDist, _Digits);
   }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = orderType;
   req.price     = price;
   req.sl        = sl;
   req.tp        = tp;
   req.deviation = InpDeviation;
   req.magic     = InpMagic;
   req.comment   = "TrendBot";

   if(OrderSend(req, res))
   {
      Print(StringFormat("[TREND BOT] %s %.2f @ %s | SL=%s (%.1f ATR) | TP=%s (%.1f:1) | Magic=%d",
            isBuy ? "BUY" : "SELL",
            lot,
            DoubleToString(price, _Digits),
            DoubleToString(sl, _Digits), InpATRMult,
            DoubleToString(tp, _Digits), InpRRRatio,
            InpMagic));
   }
   else
   {
      Print(StringFormat("[TREND BOT] OrderSend FAILED: %d - %s",
            res.retcode, res.comment));
   }
}

// ════════════════════════════════════════════════════════════════════
// UTILITY
// ════════════════════════════════════════════════════════════════════
bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return true;
   }
   return false;
}
//+------------------------------------------------------------------+
