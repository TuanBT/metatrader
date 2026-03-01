//+------------------------------------------------------------------+
//| Trend Signal Bot.mq5                                              |
//| Multi-TF EMA Cross trend-following bot with UI panel              |
//| Entry: EMA 20/50 cross on M5                                      |
//| Filter: M15 + H1 EMA alignment                                    |
//+------------------------------------------------------------------+
#property copyright "Tuan"
#property version   "1.01"
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
// CONSTANTS
// ════════════════════════════════════════════════════════════════════
#define BOT_PREFIX   "TBot_"

// Object names
#define OBJ_BG       BOT_PREFIX "BG"
#define OBJ_TITLE    BOT_PREFIX "Title"
#define OBJ_STATUS   BOT_PREFIX "Status"
#define OBJ_START    BOT_PREFIX "Start"
#define OBJ_SIGNAL   BOT_PREFIX "Signal"
#define OBJ_FORCE_BUY  BOT_PREFIX "ForceBuy"
#define OBJ_FORCE_SELL BOT_PREFIX "ForceSell"
#define OBJ_POS_INFO BOT_PREFIX "PosInfo"

// Colors
#define COL_BG       C'25,27,35'
#define COL_BORDER   C'45,48,65'
#define COL_WHITE    C'220,225,240'
#define COL_DIM      C'120,125,145'
#define COL_GREEN    C'0,180,100'
#define COL_RED      C'220,80,80'
#define COL_BLUE     C'30,80,140'
#define COL_BTN_BG   C'50,50,70'
#define COL_BTN_ON   C'0,100,60'
#define COL_BTN_OFF  C'60,60,85'

// Layout
#define BOT_PX      15
#define BOT_PY      25
#define BOT_W       180
#define BOT_H       160
#define BOT_ROW     22
#define BOT_PAD     6

// ════════════════════════════════════════════════════════════════════
// GLOBALS
// ════════════════════════════════════════════════════════════════════
int g_emaFastEntry, g_emaSlowEntry;
int g_emaFastMid,   g_emaSlowMid;
int g_emaFastHigh,  g_emaSlowHigh;
int g_atrHandle;

datetime g_lastSignalBar = 0;
bool     g_botEnabled    = true;    // Start/Stop state
bool     g_hasPos        = false;

// Cached EMA states for UI
bool g_h1Up = false, g_h1Down = false;
bool g_m15Up = false, g_m15Down = false;
bool g_m5Up = false, g_m5Down = false;
bool g_crossUp = false, g_crossDown = false;
double g_cachedATR = 0;

// ════════════════════════════════════════════════════════════════════
// INIT / DEINIT
// ════════════════════════════════════════════════════════════════════
int OnInit()
{
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

   CreatePanel();
   UpdateSignalStates();
   UpdatePanel();

   EventSetMillisecondTimer(1000);

   Print(StringFormat("[TREND BOT] Started | %s | Magic=%d | EMA %d/%d | TF=%s/%s/%s | Risk=$%.0f",
         _Symbol, InpMagic, InpEMAFast, InpEMASlow,
         EnumToString(InpTFEntry), EnumToString(InpTFMid), EnumToString(InpTFHigh),
         InpRiskMoney));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DestroyPanel();
   EventKillTimer();
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
// UI PANEL
// ════════════════════════════════════════════════════════════════════
void MakeLabel(string name, int x, int y, string text, color clr, int fontSize=8, string font="Consolas")
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void MakeButton(string name, int x, int y, int w, int h, string text, color bgClr, color txtClr, int fontSize=8)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void CreatePanel()
{
   int x = BOT_PX, y = BOT_PY;

   // Background
   ObjectCreate(0, OBJ_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_XSIZE, BOT_W);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_YSIZE, BOT_H);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_BGCOLOR, COL_BG);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_BORDER_COLOR, COL_BORDER);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   int row = y + BOT_PAD;

   // Row 1: Title
   MakeLabel(OBJ_TITLE, x + BOT_PAD, row, "Trend Signal Bot", C'170,180,215', 9, "Segoe UI Semibold");
   row += BOT_ROW;

   // Row 2: Start/Stop button
   MakeButton(OBJ_START, x + BOT_PAD, row, BOT_W - 2*BOT_PAD, 22,
              "Bot: ON", COL_BTN_ON, COL_WHITE, 9);
   row += 26;

   // Row 3: Signal status (H1 up | M15 up | M5 up)
   MakeLabel(OBJ_SIGNAL, x + BOT_PAD, row, "H1 - | M15 - | M5 -", COL_DIM, 8, "Consolas");
   row += BOT_ROW;

   // Row 4: Position info
   MakeLabel(OBJ_POS_INFO, x + BOT_PAD, row, "No position", COL_DIM, 8, "Consolas");
   row += BOT_ROW + 2;

   // Row 5: Force BUY / Force SELL buttons
   int btnW = (BOT_W - 2*BOT_PAD - 4) / 2;
   MakeButton(OBJ_FORCE_BUY,  x + BOT_PAD,          row, btnW, 22, "Force BUY",  C'0,100,65', COL_WHITE, 8);
   MakeButton(OBJ_FORCE_SELL, x + BOT_PAD + btnW + 4, row, btnW, 22, "Force SELL", C'140,40,40', COL_WHITE, 8);

   ChartRedraw();
}

void DestroyPanel()
{
   ObjectsDeleteAll(0, BOT_PREFIX);
   ChartRedraw();
}

void UpdatePanel()
{
   // ── Start/Stop button ──
   if(g_botEnabled)
   {
      ObjectSetString (0, OBJ_START, OBJPROP_TEXT, "Bot: ON");
      ObjectSetInteger(0, OBJ_START, OBJPROP_BGCOLOR, COL_BTN_ON);
      ObjectSetInteger(0, OBJ_START, OBJPROP_BORDER_COLOR, COL_BTN_ON);
      ObjectSetInteger(0, OBJ_START, OBJPROP_COLOR, COL_WHITE);
   }
   else
   {
      ObjectSetString (0, OBJ_START, OBJPROP_TEXT, "Bot: OFF");
      ObjectSetInteger(0, OBJ_START, OBJPROP_BGCOLOR, COL_BTN_OFF);
      ObjectSetInteger(0, OBJ_START, OBJPROP_BORDER_COLOR, COL_BTN_OFF);
      ObjectSetInteger(0, OBJ_START, OBJPROP_COLOR, C'180,180,200');
   }

   // ── Signal status with arrows ──
   string h1Arrow  = g_h1Up  ? "\x25B2" : (g_h1Down  ? "\x25BC" : "-");
   string m15Arrow = g_m15Up ? "\x25B2" : (g_m15Down ? "\x25BC" : "-");
   string m5Arrow  = g_m5Up  ? "\x25B2" : (g_m5Down  ? "\x25BC" : "-");

   string sigText = StringFormat("H1 %s | M15 %s | M5 %s", h1Arrow, m15Arrow, m5Arrow);
   ObjectSetString(0, OBJ_SIGNAL, OBJPROP_TEXT, sigText);

   // Color: all aligned = green/red, mixed = dim
   bool allUp   = g_h1Up && g_m15Up && g_m5Up;
   bool allDown = g_h1Down && g_m15Down && g_m5Down;
   if(allUp)
      ObjectSetInteger(0, OBJ_SIGNAL, OBJPROP_COLOR, COL_GREEN);
   else if(allDown)
      ObjectSetInteger(0, OBJ_SIGNAL, OBJPROP_COLOR, COL_RED);
   else
      ObjectSetInteger(0, OBJ_SIGNAL, OBJPROP_COLOR, COL_DIM);

   // ── Position info ──
   g_hasPos = HasPosition();
   if(g_hasPos)
   {
      double pnl = GetPositionPnL();
      double lots = GetPositionLots();
      bool isBuy = IsPositionBuy();
      string dir = isBuy ? "LONG" : "SHORT";
      ObjectSetString(0, OBJ_POS_INFO, OBJPROP_TEXT,
         StringFormat("%.2f %s  $%+.2f", lots, dir, pnl));
      ObjectSetInteger(0, OBJ_POS_INFO, OBJPROP_COLOR,
         pnl >= 0 ? COL_GREEN : COL_RED);
   }
   else
   {
      ObjectSetString(0, OBJ_POS_INFO, OBJPROP_TEXT, "No position");
      ObjectSetInteger(0, OBJ_POS_INFO, OBJPROP_COLOR, COL_DIM);
   }

   ChartRedraw();
}

// ════════════════════════════════════════════════════════════════════
// SIGNAL ANALYSIS
// ════════════════════════════════════════════════════════════════════
void UpdateSignalStates()
{
   double entryFast[2], entrySlow[2];
   double midFast[1], midSlow[1];
   double highFast[1], highSlow[1];
   double atr[1];

   // Reset
   g_h1Up = g_h1Down = g_m15Up = g_m15Down = g_m5Up = g_m5Down = false;
   g_crossUp = g_crossDown = false;

   if(CopyBuffer(g_emaFastEntry, 0, 1, 2, entryFast) != 2) return;
   if(CopyBuffer(g_emaSlowEntry, 0, 1, 2, entrySlow) != 2) return;
   if(CopyBuffer(g_emaFastMid,   0, 1, 1, midFast)   != 1) return;
   if(CopyBuffer(g_emaSlowMid,   0, 1, 1, midSlow)   != 1) return;
   if(CopyBuffer(g_emaFastHigh,  0, 1, 1, highFast)   != 1) return;
   if(CopyBuffer(g_emaSlowHigh,  0, 1, 1, highSlow)   != 1) return;
   if(CopyBuffer(g_atrHandle,    0, 1, 1, atr)        != 1) return;

   g_cachedATR = atr[0];

   // H1 trend
   g_h1Up   = (highFast[0] > highSlow[0]);
   g_h1Down = (highFast[0] < highSlow[0]);

   // M15 trend
   g_m15Up   = (midFast[0] > midSlow[0]);
   g_m15Down = (midFast[0] < midSlow[0]);

   // M5 trend + cross
   g_m5Up   = (entryFast[1] > entrySlow[1]);
   g_m5Down = (entryFast[1] < entrySlow[1]);
   g_crossUp   = (entryFast[0] <= entrySlow[0]) && (entryFast[1] > entrySlow[1]);
   g_crossDown = (entryFast[0] >= entrySlow[0]) && (entryFast[1] < entrySlow[1]);
}

// ════════════════════════════════════════════════════════════════════
// ONTICK / ONTIMER
// ════════════════════════════════════════════════════════════════════
void OnTick()
{
   UpdateSignalStates();
   UpdatePanel();

   if(!g_botEnabled) return;

   // Only check on new bar (entry TF)
   datetime curBar = iTime(_Symbol, InpTFEntry, 0);
   if(curBar == g_lastSignalBar) return;

   // Skip if already have a position
   if(g_hasPos) return;
   if(g_cachedATR <= 0) return;

   // ── BUY signal: M5 cross up + M15 up + H1 up ──
   if(g_crossUp && g_m15Up && g_h1Up)
   {
      g_lastSignalBar = curBar;
      OpenTrade(true, g_cachedATR);
      return;
   }

   // ── SELL signal: M5 cross down + M15 down + H1 down ──
   if(g_crossDown && g_m15Down && g_h1Down)
   {
      g_lastSignalBar = curBar;
      OpenTrade(false, g_cachedATR);
      return;
   }
}

void OnTimer()
{
   UpdateSignalStates();
   UpdatePanel();
}

// ════════════════════════════════════════════════════════════════════
// CHART EVENTS (UI clicks)
// ════════════════════════════════════════════════════════════════════
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   // ── Start/Stop toggle ──
   if(sparam == OBJ_START)
   {
      ObjectSetInteger(0, OBJ_START, OBJPROP_STATE, false);
      g_botEnabled = !g_botEnabled;
      Print(StringFormat("[TREND BOT] %s", g_botEnabled ? "ENABLED" : "DISABLED"));
      UpdatePanel();
   }
   // ── Force BUY ──
   else if(sparam == OBJ_FORCE_BUY)
   {
      ObjectSetInteger(0, OBJ_FORCE_BUY, OBJPROP_STATE, false);
      if(HasPosition())
      {
         Print("[TREND BOT] Already have a position, cannot force BUY");
         return;
      }
      double atr[1];
      if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1 && atr[0] > 0)
      {
         Print("[TREND BOT] Force BUY triggered by user");
         OpenTrade(true, atr[0]);
         UpdatePanel();
      }
   }
   // ── Force SELL ──
   else if(sparam == OBJ_FORCE_SELL)
   {
      ObjectSetInteger(0, OBJ_FORCE_SELL, OBJPROP_STATE, false);
      if(HasPosition())
      {
         Print("[TREND BOT] Already have a position, cannot force SELL");
         return;
      }
      double atr[1];
      if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1 && atr[0] > 0)
      {
         Print("[TREND BOT] Force SELL triggered by user");
         OpenTrade(false, atr[0]);
         UpdatePanel();
      }
   }
}

// ════════════════════════════════════════════════════════════════════
// TRADE FUNCTIONS
// ════════════════════════════════════════════════════════════════════
void OpenTrade(bool isBuy, double atrValue)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   double slDist = atrValue * InpATRMult;
   double tpDist = slDist * InpRRRatio;

   // Calculate lot from risk
   double lot = 0;
   if(tickSz > 0 && tickVal > 0 && slDist > 0)
      lot = InpRiskMoney / ((slDist / tickSz) * tickVal);

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
      Print(StringFormat("[TREND BOT] %s %.2f @ %s | SL=%s (%.1f ATR) | TP=%s (%.1f:1)",
            isBuy ? "BUY" : "SELL", lot,
            DoubleToString(price, _Digits),
            DoubleToString(sl, _Digits), InpATRMult,
            DoubleToString(tp, _Digits), InpRRRatio));
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

double GetPositionPnL()
{
   double pnl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

double GetPositionLots()
{
   double lots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      lots += PositionGetDouble(POSITION_VOLUME);
   }
   return lots;
}

bool IsPositionBuy()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   }
   return true;
}
//+------------------------------------------------------------------+
