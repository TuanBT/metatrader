//+------------------------------------------------------------------+
//| Candle Counter Strategy.mqh — Candle Counter Bot v1.01            |
//| 2-candle pattern + breakout entry logic                           |
//+------------------------------------------------------------------+
#ifndef CANDLE_COUNTER_STRATEGY_MQH
#define CANDLE_COUNTER_STRATEGY_MQH

// ════════════════════════════════════════════════════════════════════
// INPUTS (appear in Panel's settings dialog)
// ════════════════════════════════════════════════════════════════════
input group           "══ Candle Counter Bot ══"
input double          InpCC_ATRMinMult  = 0.3;   // Candle Counter: Min candle range × ATR (0 = off)
input int             InpCC_PauseBars   = 60;    // Candle Counter: Auto-resume after N bars (0 = manual)

// ════════════════════════════════════════════════════════════════════
// OBJECT NAMES (unique prefix avoids Panel/TS conflicts)
// ════════════════════════════════════════════════════════════════════
#define CC_PREFIX     "CCBot_"
#define CC_OBJ_BG     CC_PREFIX "BG"
#define CC_OBJ_TITLE  CC_PREFIX "Title"
#define CC_OBJ_STATUS CC_PREFIX "Status"

// Info lines (always visible)
#define CC_OBJ_IL1    CC_PREFIX "IL1"
#define CC_OBJ_IL2    CC_PREFIX "IL2"
#define CC_OBJ_IL3    CC_PREFIX "IL3"
#define CC_OBJ_IL4    CC_PREFIX "IL4"
#define CC_OBJ_IL5    CC_PREFIX "IL5"

#define CC_OBJ_POS    CC_PREFIX "PosInfo"

// ════════════════════════════════════════════════════════════════════
// GLOBALS (all cc_ prefixed)
// ════════════════════════════════════════════════════════════════════
datetime cc_lastSignalBar = 0;
bool     cc_enabled       = false;  // managed by Panel toggle
bool     cc_paused        = false;
datetime cc_pauseTime     = 0;

// Candle state
int    cc_countBull = 0;
int    cc_countBear = 0;
bool   cc_wickOK[3];
bool   cc_atrOK[3];
bool   cc_colorOK[3];

// Breakout pending
bool     cc_pendingBuy   = false;
bool     cc_pendingSell  = false;
double   cc_breakLevel   = 0;
datetime cc_pendingBar   = 0;

// Panel position (set by Panel when creating bot UI)
int  cc_panelX = 0;
int  cc_panelY = 0;
int  cc_panelW = 220;

// ════════════════════════════════════════════════════════════════════
// INIT / DEINIT
// ════════════════════════════════════════════════════════════════════
bool CC_Init()
{
   ArrayInitialize(cc_wickOK, false);
   ArrayInitialize(cc_atrOK, false);
   ArrayInitialize(cc_colorOK, false);

   Print(StringFormat("[CANDLE COUNTER] Initialized | %s | ATR MinMult=%.1f | PauseBars=%d",
         _Symbol, InpCC_ATRMinMult, InpCC_PauseBars));
   return true;
}

void CC_Deinit()
{
   CC_DestroyPanel();
   Print("[CANDLE COUNTER] Deinitialized");
}

// ════════════════════════════════════════════════════════════════════
// SIGNAL ANALYSIS
// ════════════════════════════════════════════════════════════════════
void CC_UpdateCandleState()
{
   cc_countBull = cc_countBear = 0;
   ArrayInitialize(cc_wickOK, false);
   ArrayInitialize(cc_atrOK, false);
   ArrayInitialize(cc_colorOK, false);

   double o1 = iOpen(_Symbol, _Period, 1);
   double c1 = iClose(_Symbol, _Period, 1);
   double h1 = iHigh(_Symbol, _Period, 1);
   double l1 = iLow(_Symbol, _Period, 1);
   double o2 = iOpen(_Symbol, _Period, 2);
   double c2 = iClose(_Symbol, _Period, 2);
   double h2 = iHigh(_Symbol, _Period, 2);
   double l2 = iLow(_Symbol, _Period, 2);

   bool bar1Bull = (c1 > o1);
   bool bar1Bear = (c1 < o1);
   bool bar2Bull = (c2 > o2);
   bool bar2Bear = (c2 < o2);

   // ATR filter — uses Panel's g_cachedATR
   if(InpCC_ATRMinMult > 0 && g_cachedATR > 0)
   {
      cc_atrOK[1] = ((h1 - l1) >= InpCC_ATRMinMult * g_cachedATR);
      cc_atrOK[2] = ((h2 - l2) >= InpCC_ATRMinMult * g_cachedATR);
   }
   else
   {
      cc_atrOK[1] = cc_atrOK[2] = true;
   }

   // 2 consecutive green
   if(bar1Bull && bar2Bull)
   {
      cc_countBull = 2;
      cc_colorOK[1] = cc_colorOK[2] = true;
      cc_wickOK[2] = true;
      cc_wickOK[1] = (l1 > l2);  // higher lows

      if(cc_wickOK[1] && cc_atrOK[1] && cc_atrOK[2])
      {
         cc_pendingBuy  = true;
         cc_pendingSell = false;
         cc_breakLevel  = h1;
         cc_pendingBar  = iTime(_Symbol, _Period, 0);
      }
      else
         cc_pendingBuy = cc_pendingSell = false;
   }
   // 2 consecutive red
   else if(bar1Bear && bar2Bear)
   {
      cc_countBear = 2;
      cc_colorOK[1] = cc_colorOK[2] = true;
      cc_wickOK[2] = true;
      cc_wickOK[1] = (h1 < h2);  // lower highs

      if(cc_wickOK[1] && cc_atrOK[1] && cc_atrOK[2])
      {
         cc_pendingSell = true;
         cc_pendingBuy  = false;
         cc_breakLevel  = l1;
         cc_pendingBar  = iTime(_Symbol, _Period, 0);
      }
      else
         cc_pendingBuy = cc_pendingSell = false;
   }
   else
   {
      cc_pendingBuy = cc_pendingSell = false;
      if(bar1Bull) { cc_countBull = 1; cc_colorOK[1] = true; }
      else if(bar1Bear) { cc_countBear = 1; cc_colorOK[1] = true; }
   }
}

// ════════════════════════════════════════════════════════════════════
// TICK — Entry logic (called from Panel's OnTick when CC is active)
// ════════════════════════════════════════════════════════════════════
void CC_Tick()
{
   if(!cc_enabled) return;

   // Auto-resume check
   if(cc_paused && InpCC_PauseBars > 0 && cc_pauseTime > 0)
   {
      int barsSincePause = iBarShift(_Symbol, _Period, cc_pauseTime);
      if(barsSincePause >= InpCC_PauseBars)
      {
         cc_paused = false;
         cc_pauseTime = 0;
         Print(StringFormat("[CANDLE COUNTER] Auto-resumed after %d bars pause", barsSincePause));
      }
   }

   // New bar → update candle state
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar != cc_lastSignalBar)
   {
      cc_lastSignalBar = curBar;
      CC_UpdateCandleState();
   }

   if(cc_paused) return;
   if(HasOwnPosition()) return;

   // Per-tick breakout check
   if(cc_pendingBuy && cc_breakLevel > 0)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(ask > cc_breakLevel)
      {
         Print(StringFormat("[CANDLE COUNTER] Breakout BUY! Price %.5f > %.5f", ask, cc_breakLevel));
         cc_pendingBuy = false;
         CC_OpenTrade(true);
      }
   }
   else if(cc_pendingSell && cc_breakLevel > 0)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid < cc_breakLevel)
      {
         Print(StringFormat("[CANDLE COUNTER] Breakout SELL! Price %.5f < %.5f", bid, cc_breakLevel));
         cc_pendingSell = false;
         CC_OpenTrade(false);
      }
   }
}

// ════════════════════════════════════════════════════════════════════
// TIMER — Update signals + display
// ════════════════════════════════════════════════════════════════════
void CC_Timer()
{
   if(!cc_enabled) return;
   CC_UpdateCandleState();
   if(g_activeBot == 1) CC_UpdatePanel();  // Only update visible panel
}

// ════════════════════════════════════════════════════════════════════
// TRADE
// ════════════════════════════════════════════════════════════════════
void CC_OpenTrade(bool isBuy)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Lot from Panel (direct access, no GV)
   double lot = g_panelLot;
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0 && lot > 0)
      lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price     = isBuy ? ask : bid;
   req.sl        = 0;  // Panel manages SL
   req.tp        = 0;  // Panel manages TP
   req.deviation = InpDeviation;
   req.magic     = InpMagic;
   req.comment   = "CCBot";

   if(OrderSend(req, res))
   {
      Print(StringFormat("[CANDLE COUNTER] %s %.2f @ %s",
            isBuy ? "BUY" : "SELL", lot,
            DoubleToString(req.price, _Digits)));
      CC_DrawEntryArrow(isBuy, req.price, lot);
   }
   else
      Print(StringFormat("[CANDLE COUNTER] OrderSend FAILED: %d - %s", res.retcode, res.comment));
}

void CC_DrawEntryArrow(bool isBuy, double price, double lot)
{
   static int arrowId = 0;
   arrowId++;
   string name = StringFormat("CCBot_Entry_%d", arrowId);

   ObjectCreate(0, name, isBuy ? OBJ_ARROW_BUY : OBJ_ARROW_SELL, 0,
                TimeCurrent(), price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? C'0,180,100' : C'220,80,80');
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString (0, name, OBJPROP_TEXT,
      StringFormat("%s %.2f @ %s", isBuy ? "BUY" : "SELL",
                   lot, DoubleToString(price, _Digits)));
}

// ════════════════════════════════════════════════════════════════════
// PAUSE (called by Panel when Large SL detected)
// ════════════════════════════════════════════════════════════════════
void CC_SetPaused(datetime pauseTimestamp)
{
   cc_paused = true;
   cc_pauseTime = pauseTimestamp;
   Print(StringFormat("[CANDLE COUNTER] Paused | Resume after %d bars", InpCC_PauseBars));
}

void CC_ClearPause()
{
   cc_paused = false;
   cc_pauseTime = 0;
   Print("[CANDLE COUNTER] Pause cleared");
}

// ════════════════════════════════════════════════════════════════════
// UI PANEL — Created/destroyed by Panel
// ════════════════════════════════════════════════════════════════════
void CC_CreatePanel(int x, int y, int w)
{
   cc_panelX = x;
   cc_panelY = y;
   cc_panelW = w;
   int pad = 8;
   int row = y;

   // Title
   MakeLabel(CC_OBJ_TITLE, x + pad, row + 4, "Candle Counter Bot v1.01",
             C'170,180,215', 10, "Segoe UI Semibold");
   row += 22;

   // Status line (running / paused countdown)
   MakeLabel(CC_OBJ_STATUS, x + pad, row, "Running", C'0,180,100', 8);
   row += 16;

   // Position info
   MakeLabel(CC_OBJ_POS, x + pad, row, "No position", C'120,125,145', 8, "Consolas");
   row += 18;

   // Info lines (always visible)
   MakeLabel(CC_OBJ_IL1, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 16;
   MakeLabel(CC_OBJ_IL2, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 16;
   MakeLabel(CC_OBJ_IL3, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 16;
   MakeLabel(CC_OBJ_IL4, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 16;
   MakeLabel(CC_OBJ_IL5, x + pad, row, "", C'120,125,145', 8, "Consolas");

   CC_UpdatePanel();
}

void CC_DestroyPanel()
{
   ObjectsDeleteAll(0, CC_PREFIX);
}

void CC_UpdatePanel()
{
   if(g_activeBot != 1) return;   // skip if not viewing

   // ── Status line ──
   if(!cc_enabled)
   {
      ObjectSetString(0, CC_OBJ_STATUS, OBJPROP_TEXT, "Stopped");
      ObjectSetInteger(0, CC_OBJ_STATUS, OBJPROP_COLOR, C'120,125,145');
   }
   else if(cc_paused)
   {
      if(InpCC_PauseBars > 0 && cc_pauseTime > 0)
      {
         int barsSincePause = iBarShift(_Symbol, _Period, cc_pauseTime);
         int barsLeft = MathMax(0, InpCC_PauseBars - barsSincePause);
         int secPerBar = PeriodSeconds(_Period);
         int minsLeft = (barsLeft * secPerBar) / 60;
         if(minsLeft >= 60)
            ObjectSetString(0, CC_OBJ_STATUS, OBJPROP_TEXT,
               StringFormat("PAUSED | ~%dh%dm", minsLeft / 60, minsLeft % 60));
         else
            ObjectSetString(0, CC_OBJ_STATUS, OBJPROP_TEXT,
               StringFormat("PAUSED | ~%dm", minsLeft));
      }
      else
         ObjectSetString(0, CC_OBJ_STATUS, OBJPROP_TEXT, "PAUSED (Large SL)");
      ObjectSetInteger(0, CC_OBJ_STATUS, OBJPROP_COLOR, C'220,80,80');
   }
   else
   {
      ObjectSetString(0, CC_OBJ_STATUS, OBJPROP_TEXT, "Running");
      ObjectSetInteger(0, CC_OBJ_STATUS, OBJPROP_COLOR, C'0,180,100');
   }

   // ── Position info ──
   if(g_hasPos)
   {
      double pnl  = GetPositionPnL();
      double lots = GetTotalLots();
      color pnlClr = (pnl >= 0) ? C'0,180,100' : C'220,80,80';
      ObjectSetString(0, CC_OBJ_POS, OBJPROP_TEXT,
         StringFormat("%s %.2f | %s$%.1f", g_isBuy ? "BUY" : "SELL", lots,
                      pnl >= 0 ? "+" : "", pnl));
      ObjectSetInteger(0, CC_OBJ_POS, OBJPROP_COLOR, pnlClr);
   }
   else
   {
      ObjectSetString(0, CC_OBJ_POS, OBJPROP_TEXT,
         StringFormat("Lot %.2f", g_panelLot));
      ObjectSetInteger(0, CC_OBJ_POS, OBJPROP_COLOR, C'120,125,145');
   }

   // ── Info lines (always visible) ──
   // Line 1: Count summary
   int count = 0;
   string dir = "—";
   if(cc_countBull > 0)      { count = cc_countBull; dir = "BUY"; }
   else if(cc_countBear > 0) { count = cc_countBear; dir = "SELL"; }

   string dots = "";
   for(int i = 0; i < count; i++)
      dots += (cc_countBull > 0) ? "\x25B2" : "\x25BC";
   for(int i = count; i < 2; i++)
      dots += "_";

   bool isPending = (cc_pendingBuy || cc_pendingSell);
   if(isPending)
      ObjectSetString(0, CC_OBJ_IL1, OBJPROP_TEXT,
         StringFormat("WAIT %s > %s  %s",
            cc_pendingBuy ? "BUY" : "SELL",
            DoubleToString(cc_breakLevel, _Digits), dots));
   else
      ObjectSetString(0, CC_OBJ_IL1, OBJPROP_TEXT,
         StringFormat("Count: %d/2 %s  %s", count, dir, dots));
   ObjectSetInteger(0, CC_OBJ_IL1, OBJPROP_COLOR,
      isPending ? (cc_pendingBuy ? C'0,180,100' : C'220,80,80') : C'220,225,240');

   // Lines 2-3: Bar details
   for(int b = 1; b <= 2; b++)
   {
      string objL = (b == 1) ? CC_OBJ_IL2 : CC_OBJ_IL3;
      string col  = cc_colorOK[b] ? (cc_countBull > 0 ? "Green" : "Red") : "✗";
      string wck  = cc_wickOK[b] ? "Wick\x2713" : "Wick✗";
      string atr  = cc_atrOK[b]  ? "ATR\x2713"  : "ATR✗";

      if(cc_colorOK[b])
         ObjectSetString(0, objL, OBJPROP_TEXT,
            StringFormat("Bar%d: %s %s %s", b, col, wck, atr));
      else
         ObjectSetString(0, objL, OBJPROP_TEXT,
            StringFormat("Bar%d: %s", b, col));
      ObjectSetInteger(0, objL, OBJPROP_COLOR,
         (cc_colorOK[b] && cc_wickOK[b] && cc_atrOK[b]) ? C'0,180,100' : C'120,125,145');
   }

   // Line 4: Breakout level
   if(isPending)
   {
      ObjectSetString(0, CC_OBJ_IL4, OBJPROP_TEXT,
         StringFormat("Break: %s %s",
            cc_pendingBuy ? "Ask >" : "Bid <",
            DoubleToString(cc_breakLevel, _Digits)));
      ObjectSetInteger(0, CC_OBJ_IL4, OBJPROP_COLOR, C'200,180,80');
   }
   else
   {
      ObjectSetString(0, CC_OBJ_IL4, OBJPROP_TEXT, "Break: — (no setup)");
      ObjectSetInteger(0, CC_OBJ_IL4, OBJPROP_COLOR, C'120,125,145');
   }

   // Line 5: ATR info
   double minRange = g_cachedATR * InpCC_ATRMinMult;
   ObjectSetString(0, CC_OBJ_IL5, OBJPROP_TEXT,
      StringFormat("ATR: %.1f | Min: %.1f (%.1fx)",
         g_cachedATR / _Point, minRange / _Point, InpCC_ATRMinMult));
   ObjectSetInteger(0, CC_OBJ_IL5, OBJPROP_COLOR, C'120,125,145');
}

// ════════════════════════════════════════════════════════════════════
// VISIBILITY (for Panel collapse)
// ════════════════════════════════════════════════════════════════════
void CC_SetVisible(bool visible)
{
   long flag = visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, CC_PREFIX) == 0)
         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, flag);
   }
}

#endif // CANDLE_COUNTER_STRATEGY_MQH
