//+------------------------------------------------------------------+
//| SR Retest Strategy.mqh — SR Retest Bot v1.01                     |
//| Limit order at nearest swing S/R, SL = 0.1×ATR (wick scalp)     |
//| v1.01: Stronger pivot detection + prominence filter              |
//+------------------------------------------------------------------+
#ifndef SR_RETEST_STRATEGY_MQH
#define SR_RETEST_STRATEGY_MQH

// ════════════════════════════════════════════════════════════════════
// INPUTS
// ════════════════════════════════════════════════════════════════════
input group           "══ SR Retest Bot ══"
input int             InpSR_PivotBars   = 15;    // SR: Pivot strength (bars left + right)
input int             InpSR_Lookback    = 100;   // SR: Lookback bars for swing scan
input double          InpSR_Prominence  = 0.5;   // SR: Min prominence (× ATR, swing must stand out)
input double          InpSR_SLMult      = 0.1;   // SR: SL = x × ATR (tiny, wick scalp)
input int             InpSR_CancelBars  = 20;    // SR: Cancel pending after N bars

// ════════════════════════════════════════════════════════════════════
// OBJECT NAMES
// ════════════════════════════════════════════════════════════════════
#define SR_PREFIX     "SRBot_"
#define SR_OBJ_TITLE  SR_PREFIX "Title"
#define SR_OBJ_STATUS SR_PREFIX "Status"
#define SR_OBJ_POS    SR_PREFIX "PosInfo"
#define SR_OBJ_IL1    SR_PREFIX "IL1"
#define SR_OBJ_IL2    SR_PREFIX "IL2"
#define SR_OBJ_IL3    SR_PREFIX "IL3"
#define SR_OBJ_IL4    SR_PREFIX "IL4"
#define SR_OBJ_IL5    SR_PREFIX "IL5"
#define SR_OBJ_IL6    SR_PREFIX "IL6"
#define SR_OBJ_IL7    SR_PREFIX "IL7"
#define SR_OBJ_IL8    SR_PREFIX "IL8"

// Chart lines for swing levels
#define SR_OBJ_RES_LINE  SR_PREFIX "ResLine"
#define SR_OBJ_SUP_LINE  SR_PREFIX "SupLine"

// ════════════════════════════════════════════════════════════════════
// GLOBALS
// ════════════════════════════════════════════════════════════════════
bool     sr_enabled       = false;   // managed by Panel toggle
bool     sr_paused        = false;
datetime sr_lastScanBar   = 0;

// Swing levels
double   sr_nearestRes    = 0;       // nearest resistance (swing high above price)
double   sr_nearestSup    = 0;       // nearest support (swing low below price)
int      sr_resBarIdx     = -1;      // bar index of resistance swing
int      sr_supBarIdx     = -1;      // bar index of support swing

// Trend detection (HH/HL vs LH/LL)
int      sr_trend         = 0;       // 1=up, -1=down, 0=neutral

// Pending order tracking
ulong    sr_pendingTicket = 0;       // ticket of our pending order
datetime sr_pendingBar    = 0;       // bar time when pending was placed
double   sr_pendingLevel  = 0;       // entry price of pending
double   sr_lastFilledLvl = 0;       // last swing level that was filled (avoid re-entry)

// Panel
int      sr_panelX = 0;
int      sr_panelY = 0;
int      sr_panelW = 220;

// ════════════════════════════════════════════════════════════════════
// INIT / DEINIT
// ════════════════════════════════════════════════════════════════════
bool SR_Init()
{
   Print(StringFormat("[SR RETEST] Initialized | %s | Pivot=%d | Lookback=%d | Prominence=%.1f×ATR | SL=%.1f×ATR | Cancel=%d bars",
         _Symbol, InpSR_PivotBars, InpSR_Lookback, InpSR_Prominence, InpSR_SLMult, InpSR_CancelBars));
   return true;
}

void SR_Deinit()
{
   SR_DestroyPanel();
   SR_RemoveChartLines();
   SR_CancelPending();
   Print("[SR RETEST] Deinitialized");
}

// ════════════════════════════════════════════════════════════════════
// SWING DETECTION — Pure candle pivot
// ════════════════════════════════════════════════════════════════════
bool SR_IsPivotHigh(int barIdx, int strength)
{
   double hi = iHigh(_Symbol, _Period, barIdx);
   for(int i = 1; i <= strength; i++)
   {
      if(iHigh(_Symbol, _Period, barIdx - i) >= hi) return false;
      if(iHigh(_Symbol, _Period, barIdx + i) >= hi) return false;
   }
   // Prominence check: swing high must protrude above avg of surrounding highs by min ATR×mult
   double atr = g_cachedATR;
   if(atr > 0 && InpSR_Prominence > 0)
   {
      double sumH = 0;
      int cnt = 0;
      for(int i = 1; i <= strength; i++)
      {
         sumH += iHigh(_Symbol, _Period, barIdx - i);
         sumH += iHigh(_Symbol, _Period, barIdx + i);
         cnt += 2;
      }
      double avgH = sumH / cnt;
      if(hi - avgH < atr * InpSR_Prominence) return false;
   }
   return true;
}

bool SR_IsPivotLow(int barIdx, int strength)
{
   double lo = iLow(_Symbol, _Period, barIdx);
   for(int i = 1; i <= strength; i++)
   {
      if(iLow(_Symbol, _Period, barIdx - i) <= lo) return false;
      if(iLow(_Symbol, _Period, barIdx + i) <= lo) return false;
   }
   // Prominence check: swing low must dip below avg of surrounding lows by min ATR×mult
   double atr = g_cachedATR;
   if(atr > 0 && InpSR_Prominence > 0)
   {
      double sumL = 0;
      int cnt = 0;
      for(int i = 1; i <= strength; i++)
      {
         sumL += iLow(_Symbol, _Period, barIdx - i);
         sumL += iLow(_Symbol, _Period, barIdx + i);
         cnt += 2;
      }
      double avgL = sumL / cnt;
      if(avgL - lo < atr * InpSR_Prominence) return false;
   }
   return true;
}

void SR_ScanSwings()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int strength = InpSR_PivotBars;
   int lookback = InpSR_Lookback;

   // Reset
   sr_nearestRes = 0;
   sr_nearestSup = 0;
   sr_resBarIdx  = -1;
   sr_supBarIdx  = -1;

   // Collect swing highs and lows
   // Start from bar [strength] because we need bars to the right
   double swingHighs[];  int shBars[];
   double swingLows[];   int slBars[];
   ArrayResize(swingHighs, 0);  ArrayResize(shBars, 0);
   ArrayResize(swingLows, 0);   ArrayResize(slBars, 0);

   for(int i = strength; i <= lookback; i++)
   {
      if(SR_IsPivotHigh(i, strength))
      {
         int sz = ArraySize(swingHighs);
         ArrayResize(swingHighs, sz + 1);
         ArrayResize(shBars, sz + 1);
         swingHighs[sz] = iHigh(_Symbol, _Period, i);
         shBars[sz] = i;
      }
      if(SR_IsPivotLow(i, strength))
      {
         int sz = ArraySize(swingLows);
         ArrayResize(swingLows, sz + 1);
         ArrayResize(slBars, sz + 1);
         swingLows[sz] = iLow(_Symbol, _Period, i);
         slBars[sz] = i;
      }
   }

   // Nearest resistance = closest swing high ABOVE current price
   double minDist = DBL_MAX;
   for(int i = 0; i < ArraySize(swingHighs); i++)
   {
      if(swingHighs[i] > bid)
      {
         double d = swingHighs[i] - bid;
         if(d < minDist)
         {
            minDist = d;
            sr_nearestRes = swingHighs[i];
            sr_resBarIdx = shBars[i];
         }
      }
   }

   // Nearest support = closest swing low BELOW current price
   minDist = DBL_MAX;
   for(int i = 0; i < ArraySize(swingLows); i++)
   {
      if(swingLows[i] < bid)
      {
         double d = bid - swingLows[i];
         if(d < minDist)
         {
            minDist = d;
            sr_nearestSup = swingLows[i];
            sr_supBarIdx = slBars[i];
         }
      }
   }

   // ── Trend: compare 2 most recent swing highs + 2 most recent swing lows ──
   sr_trend = 0;
   bool hh = false, hl = false, lh = false, ll = false;

   if(ArraySize(swingHighs) >= 2)
   {
      // [0] = most recent, [1] = previous
      hh = (swingHighs[0] > swingHighs[1]);
      lh = (swingHighs[0] < swingHighs[1]);
   }
   if(ArraySize(swingLows) >= 2)
   {
      hl = (swingLows[0] > swingLows[1]);
      ll = (swingLows[0] < swingLows[1]);
   }

   if(hh && hl) sr_trend = 1;        // Uptrend: HH + HL
   else if(lh && ll) sr_trend = -1;   // Downtrend: LH + LL

   // ── Draw chart lines ──
   SR_DrawChartLines();
}

// ════════════════════════════════════════════════════════════════════
// CHART LINES
// ════════════════════════════════════════════════════════════════════
void SR_DrawChartLines()
{
   // Resistance line
   if(sr_nearestRes > 0)
   {
      if(ObjectFind(0, SR_OBJ_RES_LINE) < 0)
         ObjectCreate(0, SR_OBJ_RES_LINE, OBJ_HLINE, 0, 0, sr_nearestRes);
      ObjectSetDouble (0, SR_OBJ_RES_LINE, OBJPROP_PRICE, sr_nearestRes);
      ObjectSetInteger(0, SR_OBJ_RES_LINE, OBJPROP_COLOR, C'220,80,80');
      ObjectSetInteger(0, SR_OBJ_RES_LINE, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, SR_OBJ_RES_LINE, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, SR_OBJ_RES_LINE, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, SR_OBJ_RES_LINE, OBJPROP_BACK, true);
      ObjectSetString (0, SR_OBJ_RES_LINE, OBJPROP_TOOLTIP,
         StringFormat("Resistance %.5f (bar %d)", sr_nearestRes, sr_resBarIdx));
   }
   else
      ObjectDelete(0, SR_OBJ_RES_LINE);

   // Support line
   if(sr_nearestSup > 0)
   {
      if(ObjectFind(0, SR_OBJ_SUP_LINE) < 0)
         ObjectCreate(0, SR_OBJ_SUP_LINE, OBJ_HLINE, 0, 0, sr_nearestSup);
      ObjectSetDouble (0, SR_OBJ_SUP_LINE, OBJPROP_PRICE, sr_nearestSup);
      ObjectSetInteger(0, SR_OBJ_SUP_LINE, OBJPROP_COLOR, C'0,140,80');
      ObjectSetInteger(0, SR_OBJ_SUP_LINE, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, SR_OBJ_SUP_LINE, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, SR_OBJ_SUP_LINE, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, SR_OBJ_SUP_LINE, OBJPROP_BACK, true);
      ObjectSetString (0, SR_OBJ_SUP_LINE, OBJPROP_TOOLTIP,
         StringFormat("Support %.5f (bar %d)", sr_nearestSup, sr_supBarIdx));
   }
   else
      ObjectDelete(0, SR_OBJ_SUP_LINE);
}

void SR_RemoveChartLines()
{
   ObjectDelete(0, SR_OBJ_RES_LINE);
   ObjectDelete(0, SR_OBJ_SUP_LINE);
}

// ════════════════════════════════════════════════════════════════════
// PENDING ORDER MANAGEMENT
// ════════════════════════════════════════════════════════════════════
bool SR_HasOwnPending()
{
   if(sr_pendingTicket == 0) return false;
   if(OrderSelect(sr_pendingTicket))
      return true;
   // Order gone (filled or cancelled)
   sr_pendingTicket = 0;
   return false;
}

void SR_CancelPending()
{
   if(sr_pendingTicket == 0) return;
   if(!OrderSelect(sr_pendingTicket))
   {
      sr_pendingTicket = 0;
      return;
   }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action = TRADE_ACTION_REMOVE;
   req.order  = sr_pendingTicket;

   if(OrderSend(req, res))
      Print(StringFormat("[SR RETEST] Pending #%d cancelled", sr_pendingTicket));
   else
      Print(StringFormat("[SR RETEST] Cancel FAILED: %d - %s", res.retcode, res.comment));

   sr_pendingTicket = 0;
   sr_pendingLevel  = 0;
   sr_pendingBar    = 0;
}

bool SR_PlacePending(bool isBuy, double entryPx, double slPx)
{
   // Lot from Panel
   double lot = g_panelLot;
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0 && lot > 0)
      lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));

   // Normalize
   entryPx = NormalizeDouble(entryPx, _Digits);
   slPx    = NormalizeDouble(slPx, _Digits);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Determine order type
   ENUM_ORDER_TYPE orderType;
   if(isBuy)
      orderType = (entryPx < ask) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP;
   else
      orderType = (entryPx > bid) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_PENDING;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = orderType;
   req.price     = entryPx;
   req.sl        = slPx;
   req.tp        = 0;      // No TP — Panel manages SL dynamically
   req.deviation = InpDeviation;
   req.magic     = InpMagic;
   req.comment   = "SRBot";

   if(OrderSend(req, res))
   {
      sr_pendingTicket = res.order;
      sr_pendingBar    = iTime(_Symbol, _Period, 0);
      sr_pendingLevel  = entryPx;
      Print(StringFormat("[SR RETEST] %s %s %.2f @ %s SL=%s",
            isBuy ? "BUY" : "SELL",
            EnumToString(orderType), lot,
            DoubleToString(entryPx, _Digits),
            DoubleToString(slPx, _Digits)));
      return true;
   }
   else
   {
      Print(StringFormat("[SR RETEST] OrderSend FAILED: %d - %s", res.retcode, res.comment));
      return false;
   }
}

// ════════════════════════════════════════════════════════════════════
// TICK LOGIC
// ════════════════════════════════════════════════════════════════════
void SR_Tick()
{
   if(!sr_enabled) return;

   // New bar → rescan swings
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar != sr_lastScanBar)
   {
      sr_lastScanBar = curBar;
      SR_ScanSwings();
   }

   // Already have position → let Panel manage
   if(HasOwnPosition())
   {
      // If pending still exists, cancel it
      if(SR_HasOwnPending()) SR_CancelPending();
      return;
   }

   // ── Cancel stale pending ──
   if(SR_HasOwnPending())
   {
      // Cancel if price moved too far (2×ATR from entry)
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(g_cachedATR > 0 && MathAbs(bid - sr_pendingLevel) > 2.0 * g_cachedATR)
      {
         Print("[SR RETEST] Cancel: price too far from entry");
         SR_CancelPending();
      }
      // Cancel after N bars
      else if(InpSR_CancelBars > 0 && sr_pendingBar > 0)
      {
         int barsSince = iBarShift(_Symbol, _Period, sr_pendingBar);
         if(barsSince >= InpSR_CancelBars)
         {
            Print(StringFormat("[SR RETEST] Cancel: %d bars elapsed", barsSince));
            SR_CancelPending();
         }
      }
      return;  // Already have a pending, wait
   }

   // ── Place new pending based on trend + swing ──
   double slDist = InpSR_SLMult * g_cachedATR;
   if(slDist <= 0) return;  // ATR not ready

   // Uptrend → price going UP → SELL LIMIT at nearest resistance
   if(sr_trend == 1 && sr_nearestRes > 0)
   {
      // Don't re-entry same level
      if(MathAbs(sr_nearestRes - sr_lastFilledLvl) < slDist) return;

      double entryPx = sr_nearestRes;
      double slPx    = NormalizeDouble(entryPx + slDist, _Digits);

      if(SR_PlacePending(false, entryPx, slPx))
         Print(StringFormat("[SR RETEST] SELL LIMIT @ Resistance %.5f", entryPx));
   }
   // Downtrend → price going DOWN → BUY LIMIT at nearest support
   else if(sr_trend == -1 && sr_nearestSup > 0)
   {
      if(MathAbs(sr_nearestSup - sr_lastFilledLvl) < slDist) return;

      double entryPx = sr_nearestSup;
      double slPx    = NormalizeDouble(entryPx - slDist, _Digits);

      if(SR_PlacePending(true, entryPx, slPx))
         Print(StringFormat("[SR RETEST] BUY LIMIT @ Support %.5f", entryPx));
   }
}

// ════════════════════════════════════════════════════════════════════
// TIMER
// ════════════════════════════════════════════════════════════════════
void SR_Timer()
{
   if(!sr_enabled) return;
   SR_ScanSwings();

   // Track if pending was filled → mark last filled level
   if(sr_pendingTicket > 0 && !SR_HasOwnPending() && HasOwnPosition())
   {
      sr_lastFilledLvl = sr_pendingLevel;
      sr_pendingTicket = 0;
      sr_pendingLevel  = 0;
      sr_pendingBar    = 0;
      Print(StringFormat("[SR RETEST] Pending filled → position opened at %.5f", sr_lastFilledLvl));
   }

   if(g_activeBot == 3) SR_UpdatePanel();
}

// ════════════════════════════════════════════════════════════════════
// UI PANEL
// ════════════════════════════════════════════════════════════════════
void SR_CreatePanel(int x, int y, int w)
{
   sr_panelX = x;
   sr_panelY = y;
   sr_panelW = w;
   int pad = 8;
   int row = y;

   MakeLabel(SR_OBJ_TITLE, x + pad, row + 4, "SR Retest Bot v1.00",
             C'170,180,215', 10, "Segoe UI Semibold");
   row += 22;

   MakeLabel(SR_OBJ_STATUS, x + pad, row, "Running", C'0,180,100', 8);
   row += 16;

   MakeLabel(SR_OBJ_POS, x + pad, row, "No position", C'120,125,145', 8, "Consolas");
   row += 18;

   MakeLabel(SR_OBJ_IL1, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 16;
   MakeLabel(SR_OBJ_IL2, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 16;
   MakeLabel(SR_OBJ_IL3, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 16;
   MakeLabel(SR_OBJ_IL4, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 16;
   MakeLabel(SR_OBJ_IL5, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 16;
   MakeLabel(SR_OBJ_IL6, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 16;
   MakeLabel(SR_OBJ_IL7, x + pad, row, "", C'80,80,100', 8, "Consolas"); row += 16;
   MakeLabel(SR_OBJ_IL8, x + pad, row, "", C'80,80,100', 8, "Consolas");

   SR_UpdatePanel();
}

void SR_DestroyPanel()
{
   ObjectsDeleteAll(0, SR_PREFIX);
}

void SR_UpdatePanel()
{
   if(g_activeBot != 3) return;

   // Status
   if(!sr_enabled)
   {
      ObjectSetString(0, SR_OBJ_STATUS, OBJPROP_TEXT, "Stopped");
      ObjectSetInteger(0, SR_OBJ_STATUS, OBJPROP_COLOR, C'120,125,145');
   }
   else
   {
      ObjectSetString(0, SR_OBJ_STATUS, OBJPROP_TEXT, "Running");
      ObjectSetInteger(0, SR_OBJ_STATUS, OBJPROP_COLOR, C'0,180,100');
   }

   // Position info
   if(g_hasPos)
   {
      double pnl  = GetPositionPnL();
      double lots = GetTotalLots();
      color pnlClr = (pnl >= 0) ? C'0,180,100' : C'220,80,80';
      ObjectSetString(0, SR_OBJ_POS, OBJPROP_TEXT,
         StringFormat("%s %.2f | %s$%.1f", g_isBuy ? "BUY" : "SELL", lots,
                      pnl >= 0 ? "+" : "", pnl));
      ObjectSetInteger(0, SR_OBJ_POS, OBJPROP_COLOR, pnlClr);
   }
   else
   {
      ObjectSetString(0, SR_OBJ_POS, OBJPROP_TEXT,
         StringFormat("Lot %.2f", g_panelLot));
      ObjectSetInteger(0, SR_OBJ_POS, OBJPROP_COLOR, C'120,125,145');
   }

   // Trend
   string trendStr = "Neutral";
   color trendClr = C'120,125,145';
   if(sr_trend == 1)  { trendStr = "Uptrend (HH+HL)"; trendClr = C'0,180,100'; }
   if(sr_trend == -1) { trendStr = "Downtrend (LH+LL)"; trendClr = C'220,80,80'; }
   ObjectSetString(0, SR_OBJ_IL1, OBJPROP_TEXT, "Trend: " + trendStr);
   ObjectSetInteger(0, SR_OBJ_IL1, OBJPROP_COLOR, trendClr);

   // Resistance
   if(sr_nearestRes > 0)
      ObjectSetString(0, SR_OBJ_IL2, OBJPROP_TEXT,
         StringFormat("Res: %s (bar %d)", DoubleToString(sr_nearestRes, _Digits), sr_resBarIdx));
   else
      ObjectSetString(0, SR_OBJ_IL2, OBJPROP_TEXT, "Res: —");
   ObjectSetInteger(0, SR_OBJ_IL2, OBJPROP_COLOR, C'220,80,80');

   // Support
   if(sr_nearestSup > 0)
      ObjectSetString(0, SR_OBJ_IL3, OBJPROP_TEXT,
         StringFormat("Sup: %s (bar %d)", DoubleToString(sr_nearestSup, _Digits), sr_supBarIdx));
   else
      ObjectSetString(0, SR_OBJ_IL3, OBJPROP_TEXT, "Sup: —");
   ObjectSetInteger(0, SR_OBJ_IL3, OBJPROP_COLOR, C'0,140,80');

   // Pending info
   if(SR_HasOwnPending())
   {
      int barsSince = (sr_pendingBar > 0) ? iBarShift(_Symbol, _Period, sr_pendingBar) : 0;
      ObjectSetString(0, SR_OBJ_IL4, OBJPROP_TEXT,
         StringFormat("Pending #%d @ %s (%d bars)",
            sr_pendingTicket,
            DoubleToString(sr_pendingLevel, _Digits),
            barsSince));
      ObjectSetInteger(0, SR_OBJ_IL4, OBJPROP_COLOR, C'180,180,0');
   }
   else
   {
      ObjectSetString(0, SR_OBJ_IL4, OBJPROP_TEXT, "No pending");
      ObjectSetInteger(0, SR_OBJ_IL4, OBJPROP_COLOR, C'80,80,100');
   }

   // SL dist
   double slDist = InpSR_SLMult * g_cachedATR;
   double slPips = (slDist > 0) ? slDist / _Point : 0;
   ObjectSetString(0, SR_OBJ_IL5, OBJPROP_TEXT,
      StringFormat("SL: %.1f pts (%.1f×ATR)", slPips, InpSR_SLMult));
   ObjectSetInteger(0, SR_OBJ_IL5, OBJPROP_COLOR, C'120,125,145');

   // ATR
   ObjectSetString(0, SR_OBJ_IL6, OBJPROP_TEXT,
      StringFormat("ATR(14): %s", DoubleToString(g_cachedATR, _Digits)));
   ObjectSetInteger(0, SR_OBJ_IL6, OBJPROP_COLOR, C'80,80,100');

   // Last filled level
   if(sr_lastFilledLvl > 0)
      ObjectSetString(0, SR_OBJ_IL7, OBJPROP_TEXT,
         StringFormat("Last fill: %s", DoubleToString(sr_lastFilledLvl, _Digits)));
   else
      ObjectSetString(0, SR_OBJ_IL7, OBJPROP_TEXT, "Last fill: —");

   // Config summary
   ObjectSetString(0, SR_OBJ_IL8, OBJPROP_TEXT,
      StringFormat("Pivot=%d Look=%d Cancel=%d", InpSR_PivotBars, InpSR_Lookback, InpSR_CancelBars));
   ObjectSetInteger(0, SR_OBJ_IL8, OBJPROP_COLOR, C'80,80,100');
}

// ════════════════════════════════════════════════════════════════════
// VISIBILITY
// ════════════════════════════════════════════════════════════════════
void SR_SetVisible(bool visible)
{
   long flag = visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, SR_PREFIX) == 0)
         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, flag);
   }

   // Show/hide chart lines
   if(visible && sr_enabled)
      SR_DrawChartLines();
   else
      SR_RemoveChartLines();
}

#endif // SR_RETEST_STRATEGY_MQH
