//+------------------------------------------------------------------+
//| Trend Signal Strategy.mqh — Trend Signal Bot v1.00                |
//| Multi-TF EMA Cross trend-following                                 |
//+------------------------------------------------------------------+
#ifndef TREND_SIGNAL_STRATEGY_MQH
#define TREND_SIGNAL_STRATEGY_MQH

// ════════════════════════════════════════════════════════════════════
// INPUTS (appear in Panel's settings dialog)
// ════════════════════════════════════════════════════════════════════
input group           "══ Trend Signal Bot ══"
input int             InpTS_EMAFast     = 20;    // Trend Signal: EMA Fast period
input int             InpTS_EMASlow     = 50;    // Trend Signal: EMA Slow period

// ════════════════════════════════════════════════════════════════════
// OBJECT NAMES (unique prefix)
// ════════════════════════════════════════════════════════════════════
#define TS_PREFIX     "TBot_"
#define TS_OBJ_BG     TS_PREFIX "BG"
#define TS_OBJ_TITLE  TS_PREFIX "Title"
#define TS_OBJ_STATUS TS_PREFIX "Status"

#define TS_OBJ_IL1    TS_PREFIX "IL1"
#define TS_OBJ_IL2    TS_PREFIX "IL2"
#define TS_OBJ_IL3    TS_PREFIX "IL3"
#define TS_OBJ_IL4    TS_PREFIX "IL4"
#define TS_OBJ_IL5    TS_PREFIX "IL5"

#define TS_OBJ_POS    TS_PREFIX "PosInfo"

// ════════════════════════════════════════════════════════════════════
// GLOBALS (all ts_ prefixed)
// ════════════════════════════════════════════════════════════════════
ENUM_TIMEFRAMES ts_tfEntry, ts_tfMid, ts_tfHigh;
string ts_tfEntryName, ts_tfMidName, ts_tfHighName;

int ts_emaFastEntry, ts_emaSlowEntry;
int ts_emaFastMid,   ts_emaSlowMid;
int ts_emaFastHigh,  ts_emaSlowHigh;

datetime ts_lastSignalBar = 0;
bool     ts_enabled       = false;  // managed by Panel toggle
bool     ts_paused        = false;

// Trading signal states
bool ts_highUp = false, ts_highDown = false;
bool ts_midUp  = false, ts_midDown  = false;
bool ts_entryUp = false, ts_entryDown = false;
bool ts_crossUp = false, ts_crossDown = false;

// Lazy loading state
bool     ts_handlesCreated = false;
bool     ts_warmupDone     = false;

// Multi-TF display
#define TS_MAX_DISP 8
ENUM_TIMEFRAMES ts_dispTF[TS_MAX_DISP];
string  ts_dispName[TS_MAX_DISP];
int     ts_dispFast[TS_MAX_DISP];
int     ts_dispSlow[TS_MAX_DISP];
bool    ts_dispUp[TS_MAX_DISP];
bool    ts_dispDown[TS_MAX_DISP];
int     ts_numDisp  = 0;
int     ts_entryIdx = -1;

// Panel position
int  ts_panelX = 0;
int  ts_panelY = 0;
int  ts_panelW = 220;

// ════════════════════════════════════════════════════════════════════
// TF HELPERS
// ════════════════════════════════════════════════════════════════════
string TS_TFShortName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return EnumToString(tf);
   }
}

void TS_MapTimeframes()
{
   ts_tfEntry = _Period;

   switch(_Period)
   {
      case PERIOD_M1:  ts_tfMid = PERIOD_M5;  ts_tfHigh = PERIOD_M15; break;
      case PERIOD_M5:  ts_tfMid = PERIOD_M15; ts_tfHigh = PERIOD_H1;  break;
      case PERIOD_M15: ts_tfMid = PERIOD_H1;  ts_tfHigh = PERIOD_H4;  break;
      case PERIOD_M30: ts_tfMid = PERIOD_H4;  ts_tfHigh = PERIOD_D1;  break;
      case PERIOD_H1:  ts_tfMid = PERIOD_H4;  ts_tfHigh = PERIOD_D1;  break;
      case PERIOD_H4:  ts_tfMid = PERIOD_D1;  ts_tfHigh = PERIOD_W1;  break;
      case PERIOD_D1:  ts_tfMid = PERIOD_W1;  ts_tfHigh = PERIOD_MN1; break;
      default:         ts_tfMid = PERIOD_M15; ts_tfHigh = PERIOD_H1;  break;
   }

   ts_tfEntryName = TS_TFShortName(ts_tfEntry);
   ts_tfMidName   = TS_TFShortName(ts_tfMid);
   ts_tfHighName  = TS_TFShortName(ts_tfHigh);

   // Build display array: W1 down to M1
   ENUM_TIMEFRAMES allTF[] = { PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1,
                                PERIOD_M30, PERIOD_M15, PERIOD_M5, PERIOD_M1 };
   ts_numDisp = 0;
   ts_entryIdx = -1;
   for(int i = 0; i < ArraySize(allTF) && ts_numDisp < TS_MAX_DISP; i++)
   {
      ts_dispTF[ts_numDisp]   = allTF[i];
      ts_dispName[ts_numDisp] = TS_TFShortName(allTF[i]);
      ts_dispFast[ts_numDisp] = INVALID_HANDLE;
      ts_dispSlow[ts_numDisp] = INVALID_HANDLE;
      ts_dispUp[ts_numDisp]   = false;
      ts_dispDown[ts_numDisp] = false;
      if(allTF[i] == ts_tfEntry) ts_entryIdx = ts_numDisp;
      ts_numDisp++;
   }
}

// ════════════════════════════════════════════════════════════════════
// INIT / DEINIT
// ════════════════════════════════════════════════════════════════════
bool TS_Init()
{
   TS_MapTimeframes();

   // NOTE: iMA handles are NOT created here (lazy loading).
   // They are created on-demand when the user presses Start → TS_CreateHandles().

   ts_handlesCreated = false;
   ts_warmupDone     = false;

   Print(StringFormat("[TREND SIGNAL] Initialized | %s | EMA %d/%d | TF=%s/%s/%s",
         _Symbol, InpTS_EMAFast, InpTS_EMASlow,
         ts_tfEntryName, ts_tfMidName, ts_tfHighName));
   return true;
}

// Create indicator handles on-demand (called from ToggleBotStart)
bool TS_CreateHandles()
{
   if(ts_handlesCreated) return true;

   ts_emaFastEntry = iMA(_Symbol, ts_tfEntry, InpTS_EMAFast, 0, MODE_EMA, PRICE_CLOSE);
   ts_emaSlowEntry = iMA(_Symbol, ts_tfEntry, InpTS_EMASlow, 0, MODE_EMA, PRICE_CLOSE);
   ts_emaFastMid   = iMA(_Symbol, ts_tfMid,   InpTS_EMAFast, 0, MODE_EMA, PRICE_CLOSE);
   ts_emaSlowMid   = iMA(_Symbol, ts_tfMid,   InpTS_EMASlow, 0, MODE_EMA, PRICE_CLOSE);
   ts_emaFastHigh  = iMA(_Symbol, ts_tfHigh,  InpTS_EMAFast, 0, MODE_EMA, PRICE_CLOSE);
   ts_emaSlowHigh  = iMA(_Symbol, ts_tfHigh,  InpTS_EMASlow, 0, MODE_EMA, PRICE_CLOSE);

   if(ts_emaFastEntry == INVALID_HANDLE || ts_emaSlowEntry == INVALID_HANDLE ||
      ts_emaFastMid   == INVALID_HANDLE || ts_emaSlowMid   == INVALID_HANDLE ||
      ts_emaFastHigh  == INVALID_HANDLE || ts_emaSlowHigh  == INVALID_HANDLE)
   {
      Print("[TREND SIGNAL] Failed to create indicator handles");
      return false;
   }

   for(int i = 0; i < ts_numDisp; i++)
   {
      ts_dispFast[i] = iMA(_Symbol, ts_dispTF[i], InpTS_EMAFast, 0, MODE_EMA, PRICE_CLOSE);
      ts_dispSlow[i] = iMA(_Symbol, ts_dispTF[i], InpTS_EMASlow, 0, MODE_EMA, PRICE_CLOSE);
   }

   ts_handlesCreated = true;
   ts_warmupDone     = false;
   Print("[TREND SIGNAL] Indicator handles created — warming up...");
   return true;
}

// Check if all TS indicator handles have cached data (non-blocking)
bool TS_CheckWarmup()
{
   if(ts_warmupDone) return true;
   if(!ts_handlesCreated) return false;
   // Core handles
   if(BarsCalculated(ts_emaFastEntry) <= 0) return false;
   if(BarsCalculated(ts_emaSlowEntry) <= 0) return false;
   if(BarsCalculated(ts_emaFastMid)   <= 0) return false;
   if(BarsCalculated(ts_emaSlowMid)   <= 0) return false;
   if(BarsCalculated(ts_emaFastHigh)  <= 0) return false;
   if(BarsCalculated(ts_emaSlowHigh)  <= 0) return false;
   // Display handles
   for(int i = 0; i < ts_numDisp; i++)
   {
      if(ts_dispFast[i] != INVALID_HANDLE && BarsCalculated(ts_dispFast[i]) <= 0) return false;
      if(ts_dispSlow[i] != INVALID_HANDLE && BarsCalculated(ts_dispSlow[i]) <= 0) return false;
   }
   ts_warmupDone = true;
   Print("[TREND SIGNAL] Warmup complete — ready to trade");
   return true;
}

void TS_ShowChartEMA()
{
   ChartIndicatorAdd(0, 0, ts_emaFastEntry);
   ChartIndicatorAdd(0, 0, ts_emaSlowEntry);
}

void TS_HideChartEMA()
{
   for(int i = ChartIndicatorsTotal(0, 0) - 1; i >= 0; i--)
   {
      string indName = ChartIndicatorName(0, 0, i);
      int indHandle = ChartIndicatorGet(0, 0, indName);
      if(indHandle == ts_emaFastEntry || indHandle == ts_emaSlowEntry)
         ChartIndicatorDelete(0, 0, indName);
   }
}

void TS_Deinit()
{
   TS_DestroyPanel();
   TS_HideChartEMA();

   if(ts_handlesCreated)
   {
      if(ts_emaFastEntry != INVALID_HANDLE) IndicatorRelease(ts_emaFastEntry);
      if(ts_emaSlowEntry != INVALID_HANDLE) IndicatorRelease(ts_emaSlowEntry);
      if(ts_emaFastMid   != INVALID_HANDLE) IndicatorRelease(ts_emaFastMid);
      if(ts_emaSlowMid   != INVALID_HANDLE) IndicatorRelease(ts_emaSlowMid);
      if(ts_emaFastHigh  != INVALID_HANDLE) IndicatorRelease(ts_emaFastHigh);
      if(ts_emaSlowHigh  != INVALID_HANDLE) IndicatorRelease(ts_emaSlowHigh);
      for(int i = 0; i < ts_numDisp; i++)
      {
         if(ts_dispFast[i] != INVALID_HANDLE) IndicatorRelease(ts_dispFast[i]);
         if(ts_dispSlow[i] != INVALID_HANDLE) IndicatorRelease(ts_dispSlow[i]);
      }
   }
   ts_handlesCreated = false;
   ts_warmupDone     = false;
   Print("[TREND SIGNAL] Deinitialized");
}

// ════════════════════════════════════════════════════════════════════
// SIGNAL ANALYSIS
// ════════════════════════════════════════════════════════════════════
void TS_UpdateSignalStates()
{
   double entryFast[2], entrySlow[2];
   double midFast[1], midSlow[1];
   double highFast[1], highSlow[1];

   ts_highUp = ts_highDown = ts_midUp = ts_midDown = false;
   ts_entryUp = ts_entryDown = ts_crossUp = ts_crossDown = false;

   if(CopyBuffer(ts_emaFastEntry, 0, 1, 2, entryFast) != 2) return;
   if(CopyBuffer(ts_emaSlowEntry, 0, 1, 2, entrySlow) != 2) return;
   if(CopyBuffer(ts_emaFastMid,   0, 1, 1, midFast)   != 1) return;
   if(CopyBuffer(ts_emaSlowMid,   0, 1, 1, midSlow)   != 1) return;
   if(CopyBuffer(ts_emaFastHigh,  0, 1, 1, highFast)   != 1) return;
   if(CopyBuffer(ts_emaSlowHigh,  0, 1, 1, highSlow)   != 1) return;

   ts_highUp   = (highFast[0] > highSlow[0]);
   ts_highDown = (highFast[0] < highSlow[0]);
   ts_midUp    = (midFast[0] > midSlow[0]);
   ts_midDown  = (midFast[0] < midSlow[0]);
   ts_entryUp  = (entryFast[1] > entrySlow[1]);
   ts_entryDown = (entryFast[1] < entrySlow[1]);
   ts_crossUp   = (entryFast[0] <= entrySlow[0]) && (entryFast[1] > entrySlow[1]);
   ts_crossDown = (entryFast[0] >= entrySlow[0]) && (entryFast[1] < entrySlow[1]);

   // Update display TF states
   for(int i = 0; i < ts_numDisp; i++)
   {
      ts_dispUp[i]   = false;
      ts_dispDown[i] = false;
      if(ts_dispFast[i] == INVALID_HANDLE || ts_dispSlow[i] == INVALID_HANDLE) continue;
      double f[1], s[1];
      if(CopyBuffer(ts_dispFast[i], 0, 1, 1, f) != 1) continue;
      if(CopyBuffer(ts_dispSlow[i], 0, 1, 1, s) != 1) continue;
      ts_dispUp[i]   = (f[0] > s[0]);
      ts_dispDown[i] = (f[0] < s[0]);
   }
}

// ════════════════════════════════════════════════════════════════════
// TICK — Entry logic
// ════════════════════════════════════════════════════════════════════
void TS_Tick()
{
   if(!ts_enabled) return;
   if(!ts_warmupDone) return;  // Skip trading until indicators warmed up

   // Signal states updated by TS_Timer() — no need to repeat here

   if(ts_paused) return;
   if(HasOwnPosition()) return;

   // Only on new bar
   datetime curBar = iTime(_Symbol, ts_tfEntry, 0);
   if(curBar == ts_lastSignalBar) return;

   // BUY: cross up + Mid up + High up
   if(ts_crossUp && ts_midUp && ts_highUp)
   {
      ts_lastSignalBar = curBar;
      TS_OpenTrade(true);
      return;
   }
   // SELL: cross down + Mid down + High down
   if(ts_crossDown && ts_midDown && ts_highDown)
   {
      ts_lastSignalBar = curBar;
      TS_OpenTrade(false);
      return;
   }
}

// ════════════════════════════════════════════════════════════════════
// TIMER
// ════════════════════════════════════════════════════════════════════
void TS_Timer()
{
   if(!ts_enabled) return;

   // Warmup check: poll indicator data until all handles have cached data
   if(!ts_warmupDone)
   {
      TS_CheckWarmup();
      if(g_activeBot == 2) TS_UpdatePanel();
      return;  // Skip trading logic during warmup
   }

   // Throttle heavy CopyBuffer to every 5s (signals only change on bar close)
   static uint s_lastSignalMs = 0;
   uint now = GetTickCount();
   if(now - s_lastSignalMs >= 5000)
   {
      TS_UpdateSignalStates();
      s_lastSignalMs = now;
   }
   if(g_activeBot == 2) TS_UpdatePanel();  // Only update visible panel
}

// ════════════════════════════════════════════════════════════════════
// TRADE
// ════════════════════════════════════════════════════════════════════
void TS_OpenTrade(bool isBuy)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

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
   req.sl        = 0;
   req.tp        = 0;
   req.deviation = InpDeviation;
   req.magic     = InpMagic;
   req.comment   = "TrendBot";

   if(OrderSend(req, res))
   {
      Print(StringFormat("[TREND SIGNAL] %s %.2f @ %s",
            isBuy ? "BUY" : "SELL", lot,
            DoubleToString(req.price, _Digits)));
      TS_DrawEntryArrow(isBuy, req.price, lot);
   }
   else
      Print(StringFormat("[TREND SIGNAL] OrderSend FAILED: %d - %s", res.retcode, res.comment));
}

void TS_DrawEntryArrow(bool isBuy, double price, double lot)
{
   static int arrowId = 0;
   arrowId++;
   string name = StringFormat("TBot_Entry_%d", arrowId);

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
// PAUSE
// ════════════════════════════════════════════════════════════════════
void TS_SetPaused(bool paused)
{
   ts_paused = paused;
   if(paused)
      Print("[TREND SIGNAL] Paused (Large SL)");
   else
      Print("[TREND SIGNAL] Pause cleared");
}

// ════════════════════════════════════════════════════════════════════
// UI PANEL
// ════════════════════════════════════════════════════════════════════
void TS_CreatePanel(int x, int y, int w)
{
   ts_panelX = x;
   ts_panelY = y;
   ts_panelW = w;
   int pad = 8;
   int row = y;

   // Title
   MakeLabel(TS_OBJ_TITLE, x + pad, row + 4, "Trend Signal Bot v1.00",
             C'170,180,215', 10, "Segoe UI Semibold");
   row += 22;

   // Status
   MakeLabel(TS_OBJ_STATUS, x + pad, row, "Running", C'0,180,100', 8);
   row += 16;

   // TF signals: 2 rows × 4 (W1-H1, M30-M1)
   int colW = (w - 2 * pad) / 4;
   for(int i = 0; i < ts_numDisp; i++)
   {
      if(i == 4) row += 16;  // second row
      int col = i % 4;
      string objName = TS_PREFIX + "Sig" + IntegerToString(i);
      string initText;
      if(i == ts_entryIdx)
         initText = "[" + ts_dispName[i] + "-]";
      else
         initText = ts_dispName[i] + " -";
      MakeLabel(objName, x + pad + col * colW, row, initText, C'120,125,145', 8, "Consolas");
   }
   row += 20;

   // Position info
   MakeLabel(TS_OBJ_POS, x + pad, row, "No position", C'120,125,145', 8, "Consolas");
   row += 18;

   // Info lines (always visible)
   MakeLabel(TS_OBJ_IL1, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 14;
   MakeLabel(TS_OBJ_IL2, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 14;
   MakeLabel(TS_OBJ_IL3, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 14;
   MakeLabel(TS_OBJ_IL4, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 14;
   MakeLabel(TS_OBJ_IL5, x + pad, row, "", C'120,125,145', 7, "Consolas");

   TS_UpdatePanel();
}

void TS_DestroyPanel()
{
   ObjectsDeleteAll(0, TS_PREFIX);
}

void TS_UpdatePanel()
{
   if(g_activeBot != 2) return;   // skip if not viewing

   // ── Status ──
   if(!ts_enabled)
   {
      ObjectSetString(0, TS_OBJ_STATUS, OBJPROP_TEXT, "Stopped");
      ObjectSetInteger(0, TS_OBJ_STATUS, OBJPROP_COLOR, C'120,125,145');
   }
   else if(!ts_warmupDone)
   {
      ObjectSetString(0, TS_OBJ_STATUS, OBJPROP_TEXT, "\x23F3 Loading indicators...");
      ObjectSetInteger(0, TS_OBJ_STATUS, OBJPROP_COLOR, C'255,180,50');
   }
   else if(ts_paused)
   {
      ObjectSetString(0, TS_OBJ_STATUS, OBJPROP_TEXT, "PAUSED (Large SL)");
      ObjectSetInteger(0, TS_OBJ_STATUS, OBJPROP_COLOR, C'220,80,80');
   }
   else
   {
      ObjectSetString(0, TS_OBJ_STATUS, OBJPROP_TEXT, "Running");
      ObjectSetInteger(0, TS_OBJ_STATUS, OBJPROP_COLOR, C'0,180,100');
   }

   // ── TF signals ──
   for(int i = 0; i < ts_numDisp; i++)
   {
      string objName = TS_PREFIX + "Sig" + IntegerToString(i);
      string arrow = ts_dispUp[i] ? "\x25B2" : (ts_dispDown[i] ? "\x25BC" : "-");
      string text;
      if(i == ts_entryIdx)
         text = "[" + ts_dispName[i] + arrow + "]";
      else
         text = ts_dispName[i] + arrow;
      ObjectSetString(0, objName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, objName, OBJPROP_COLOR,
         ts_dispUp[i] ? C'0,180,100' : (ts_dispDown[i] ? C'220,80,80' : C'120,125,145'));
   }

   // ── Position info ──
   if(g_hasPos)
   {
      double pnl = GetPositionPnL();
      double lots = GetTotalLots();
      color pnlClr = (pnl >= 0) ? C'0,180,100' : C'220,80,80';
      ObjectSetString(0, TS_OBJ_POS, OBJPROP_TEXT,
         StringFormat("%s %.2f | %s$%.1f", g_isBuy ? "BUY" : "SELL", lots,
                      pnl >= 0 ? "+" : "", pnl));
      ObjectSetInteger(0, TS_OBJ_POS, OBJPROP_COLOR, pnlClr);
   }
   else
   {
      ObjectSetString(0, TS_OBJ_POS, OBJPROP_TEXT,
         StringFormat("Lot %.2f", g_panelLot));
      ObjectSetInteger(0, TS_OBJ_POS, OBJPROP_COLOR, C'120,125,145');
   }

   // ── Info (always visible) ──
   ObjectSetString(0, TS_OBJ_IL1, OBJPROP_TEXT,
      StringFormat("Entry: EMA %d/%d cross [%s]", InpTS_EMAFast, InpTS_EMASlow, ts_tfEntryName));
   ObjectSetString(0, TS_OBJ_IL2, OBJPROP_TEXT,
      StringFormat("Filter: %s + %s aligned", ts_tfMidName, ts_tfHighName));
   ObjectSetString(0, TS_OBJ_IL3, OBJPROP_TEXT,
      "BUY : Cross up + Mid\x25B2 + High\x25B2");
   ObjectSetString(0, TS_OBJ_IL4, OBJPROP_TEXT,
      "SELL: Cross dn + Mid\x25BC + High\x25BC");
   ObjectSetString(0, TS_OBJ_IL5, OBJPROP_TEXT,
      "Panel manages SL / TP / Trail");
}

// ════════════════════════════════════════════════════════════════════
// VISIBILITY
// ════════════════════════════════════════════════════════════════════
void TS_SetVisible(bool visible)
{
   long flag = visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, TS_PREFIX) == 0)
         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, flag);
   }
}

#endif // TREND_SIGNAL_STRATEGY_MQH
