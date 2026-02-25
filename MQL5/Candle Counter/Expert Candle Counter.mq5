//+------------------------------------------------------------------+
//| Candle Counter EA — v1.5                                         |
//|                                                                  |
//| Signal:  3 consecutive same-color candles                        |
//| Entry:   Market order at open of 4th candle                      |
//| SL:      Lowest low / highest high of last N bars (lookback)     |
//| Trail:   Advance SL to low/high of each new same-color candle    |
//| TP:      None (exit only via SL)                                 |
//+------------------------------------------------------------------+
#property strict

// ── Inputs ────────────────────────────────────────────────────────
input double InpLotSize       = 0.01;    // Lot size
input int    InpDeviation     = 20;      // Max deviation (points)
input ulong  InpMagic         = 20260225;// Magic number
input bool   InpOnePosition   = true;    // Block new entry if already in trade
input bool   InpUseEMAFilter  = true;    // Only trade in EMA trend direction
input int    InpEMAPeriod     = 50;      // EMA period for trend filter
input ENUM_TIMEFRAMES InpEMATF = PERIOD_CURRENT; // EMA timeframe (PERIOD_CURRENT = same TF)
input bool   InpUseADXFilter  = true;    // Only trade when ADX > threshold (trending market)
input int    InpADXPeriod     = 14;      // ADX period
input double InpADXMinValue   = 25.0;    // Min ADX value to allow entry
input int    InpSLLookback    = 5;       // SL lookback bars (min low/max high of last N bars)

// ── State ─────────────────────────────────────────────────────────
static datetime g_lastBarTime = 0;
static int      g_emaHandle   = INVALID_HANDLE;
static int      g_adxHandle   = INVALID_HANDLE;
static bool     g_inTrade     = false;
static bool     g_isBuy       = false;
static double   g_currentSL   = 0.0;

// ────────────────────────────────────────────────────────────────
double NormalizePrice(const double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) tick = _Point;
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
}

bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)       == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }
   return false;
}

void CheckResetState()
{
   if(!g_inTrade) return;
   if(!HasPosition())
   {
      g_inTrade   = false;
      g_currentSL = 0.0;
   }
}

// ── Signal: 3 same-color candles at bar[1], bar[2], bar[3] ────────
// Returns +1 (3 green) or -1 (3 red) or 0 (no signal)
// Additional filter: trend structure validation
//   BUY:  each bar's low > previous bar's low  (strictly higher lows → clean uptrend)
//   SELL: each bar's high < previous bar's high (strictly lower highs → clean downtrend)
int DetectThreeCandles()
{
   bool allGreen = true;
   bool allRed   = true;

   for(int i = 1; i <= 3; i++)
   {
      double o = iOpen(_Symbol, _Period, i);
      double c = iClose(_Symbol, _Period, i);
      if(c <= o) allGreen = false;
      if(c >= o) allRed   = false;
   }

   if(!allGreen && !allRed) return 0;

   // Validate trend structure
   if(allGreen)
   {
      // Strictly higher lows: bar[1].low > bar[2].low > bar[3].low
      for(int i = 1; i <= 2; i++)
      {
         if(iLow(_Symbol, _Period, i) <= iLow(_Symbol, _Period, i + 1))
            return 0;   // wick not strictly higher → not clean trend
      }
      return 1;
   }
   else // allRed
   {
      // Strictly lower highs: bar[1].high < bar[2].high < bar[3].high
      for(int i = 1; i <= 2; i++)
      {
         if(iHigh(_Symbol, _Period, i) >= iHigh(_Symbol, _Period, i + 1))
            return 0;   // wick not strictly lower → not clean trend
      }
      return -1;
   }
}

// ── Trailing SL: advance on same-color candle ─────────────────────
// SL trails bar[1] (1 candle back) for tight but responsive trailing.
void CheckTrail()
{
   if(!g_inTrade) return;

   // Check: was bar[1] (last closed) same color as trade?
   double o1 = iOpen(_Symbol, _Period, 1);
   double c1 = iClose(_Symbol, _Period, 1);

   bool barBullish = (c1 > o1);
   bool barBearish = (c1 < o1);

   if(g_isBuy  && !barBullish) return;   // not same direction → no trail
   if(!g_isBuy && !barBearish) return;

   // New SL = bar[1] (most recently closed candle)
   double newSL = g_isBuy
                  ? NormalizePrice(iLow(_Symbol, _Period, 1))
                  : NormalizePrice(iHigh(_Symbol, _Period, 1));

   // Only advance SL (never retreat)
   bool advance = g_isBuy  ? (newSL > g_currentSL)
                            : (newSL < g_currentSL);
   if(!advance) return;

   // Safety: don't set SL past current price
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(g_isBuy  && newSL >= bid) return;
   if(!g_isBuy && newSL <= ask) return;

   // Modify position SL
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)       != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action   = TRADE_ACTION_SLTP;
      req.symbol   = _Symbol;
      req.position = t;
      req.sl       = newSL;
      req.tp       = PositionGetDouble(POSITION_TP);

      if(OrderSend(req, res))
      {
         g_currentSL = newSL;
         Print("[TRAIL] SL→", DoubleToString(newSL, _Digits),
            " (bar1 low/high=", DoubleToString(newSL, _Digits), ")");
      }
      else
         Print("[TRAIL] Warning: modify failed. Retcode=", res.retcode);
   }
}

// ── MAIN TICK ─────────────────────────────────────────────────────
void OnTick()
{
   // Fire only on new bar
   datetime curBarTime = iTime(_Symbol, _Period, 0);
   if(curBarTime == g_lastBarTime) return;
   g_lastBarTime = curBarTime;

   // Update trade state
   CheckResetState();

   // Try to advance trailing SL
   CheckTrail();

   // Entry conditions
   if(InpOnePosition && HasPosition()) return;

   // Detect 3-candle signal
   int sig = DetectThreeCandles();
   if(sig == 0) return;

   bool isBuy = (sig == 1);

   // EMA trend filter: long only above EMA, short only below EMA
   if(InpUseEMAFilter && g_emaHandle != INVALID_HANDLE)
   {
      double emaBuf[1];
      if(CopyBuffer(g_emaHandle, 0, 1, 1, emaBuf) == 1)
      {
         double ema   = emaBuf[0];
         double close = iClose(_Symbol, _Period, 1);
         if(isBuy  && close < ema) return;   // price below EMA → skip buy
         if(!isBuy && close > ema) return;   // price above EMA → skip sell
      }
   }

   // ADX regime filter: only enter when market is trending
   if(InpUseADXFilter && g_adxHandle != INVALID_HANDLE)
   {
      double adxBuf[1];
      if(CopyBuffer(g_adxHandle, 0, 1, 1, adxBuf) == 1)
      {
         if(adxBuf[0] < InpADXMinValue) return;  // market ranging → skip
      }
   }

   // SL = lowest low / highest high of last N bars (lookback)
   int lookback = MathMax(InpSLLookback, 3);  // at least 3 bars
   double sl;
   if(isBuy)
   {
      double minLow = iLow(_Symbol, _Period, 1);
      for(int i = 2; i <= lookback; i++)
         minLow = MathMin(minLow, iLow(_Symbol, _Period, i));
      sl = NormalizePrice(minLow);
   }
   else
   {
      double maxHigh = iHigh(_Symbol, _Period, 1);
      for(int i = 2; i <= lookback; i++)
         maxHigh = MathMax(maxHigh, iHigh(_Symbol, _Period, i));
      sl = NormalizePrice(maxHigh);
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Basic SL validity
   if(isBuy  && sl >= ask) { Print("[ENTRY] Skip: buy SL≥ask");  return; }
   if(!isBuy && sl <= bid) { Print("[ENTRY] Skip: sell SL≤bid"); return; }

   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = InpLotSize;
   req.type      = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price     = isBuy ? ask : bid;
   req.sl        = sl;
   req.tp        = 0;         // no fixed TP
   req.magic     = InpMagic;
   req.deviation = InpDeviation;
   req.comment   = "CC_v1";

   if(OrderSend(req, res))
   {
      g_inTrade   = true;
      g_isBuy     = isBuy;
      g_currentSL = sl;
      Print("[ENTRY] ", (isBuy ? "BUY" : "SELL"),
            " @", DoubleToString(isBuy ? ask : bid, _Digits),
            " SL=", DoubleToString(sl, _Digits),
            " | 3 candles: ",
            DoubleToString(iOpen(_Symbol, _Period, 3), _Digits), "→",
            DoubleToString(iClose(_Symbol, _Period, 1), _Digits));
   }
   else
      Print("[ENTRY] OrderSend failed. Retcode=", res.retcode,
            " | ", isBuy ? "BUY" : "SELL",
            " Ask=", DoubleToString(ask, _Digits),
            " SL=",  DoubleToString(sl, _Digits));
}

int OnInit()
{
   if(InpUseEMAFilter)
   {
      ENUM_TIMEFRAMES emaTF = (InpEMATF == PERIOD_CURRENT) ? _Period : InpEMATF;
      g_emaHandle = iMA(_Symbol, emaTF, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_emaHandle == INVALID_HANDLE)
      {
         Print("Warning: failed to create EMA handle.");
         return INIT_FAILED;
      }
   }
   if(InpUseADXFilter)
   {
      g_adxHandle = iADX(_Symbol, _Period, InpADXPeriod);
      if(g_adxHandle == INVALID_HANDLE)
      {
         Print("Warning: failed to create ADX handle.");
         return INIT_FAILED;
      }
   }
   Print("Candle Counter v1.5 | Lot=", InpLotSize,
         " | EMA=", (InpUseEMAFilter ? StringFormat("EMA%d", InpEMAPeriod) : "off"),
         " | ADX=", (InpUseADXFilter ? StringFormat("ADX%d>%.0f", InpADXPeriod, InpADXMinValue) : "off"),
         " | SL_LB=", InpSLLookback);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_emaHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_emaHandle);
      g_emaHandle = INVALID_HANDLE;
   }
   if(g_adxHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_adxHandle);
      g_adxHandle = INVALID_HANDLE;
   }
}
//+------------------------------------------------------------------+
