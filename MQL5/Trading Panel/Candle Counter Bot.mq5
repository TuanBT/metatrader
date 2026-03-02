//+------------------------------------------------------------------+
//| Candle Counter Bot.mq5                                           |
//| 3 same-direction candles with wick structure → entry              |
//| Filter: ATR candle size, wick rule (higher lows / lower highs)   |
//| v1.01: Breakout entry — 2 confirmed candles + live breakout     |
//| v1.02: Auto-resume after N bars pause (Large SL)               |
//+------------------------------------------------------------------+
#property copyright "Tuan v1.02"
#property version   "1.02"
#property strict

// ════════════════════════════════════════════════════════════════════
// INPUTS
// ════════════════════════════════════════════════════════════════════
input group           "══ Strategy ══"
input double          InpATRMinMult     = 0.3;        // Min candle range × ATR (0 = off)
input int             InpATRPeriod      = 14;         // ATR period
input int             InpPauseBars      = 10;         // Auto-resume after N bars (0 = manual only)

input group           "══ General ══"
input int             InpDeviation      = 20;         // Max slippage (points)
input ulong           InpMagic          = 99999;      // Magic Number

// ════════════════════════════════════════════════════════════════════
// CONSTANTS
// ════════════════════════════════════════════════════════════════════
#define BOT_PREFIX   "CCBot_"

// Object names — Panel
#define OBJ_BG       BOT_PREFIX "BG"
#define OBJ_TITLE    BOT_PREFIX "Title"
#define OBJ_STATUS   BOT_PREFIX "Status"
#define OBJ_START    BOT_PREFIX "Start"
#define OBJ_FORCE_BUY  BOT_PREFIX "ForceBuy"
#define OBJ_FORCE_SELL BOT_PREFIX "ForceSell"
#define OBJ_POS_INFO BOT_PREFIX "PosInfo"
#define OBJ_INFO_BTN BOT_PREFIX "InfoBtn"
#define OBJ_INFO_L1  BOT_PREFIX "InfoL1"
#define OBJ_INFO_L2  BOT_PREFIX "InfoL2"
#define OBJ_INFO_L3  BOT_PREFIX "InfoL3"
#define OBJ_INFO_L4  BOT_PREFIX "InfoL4"
#define OBJ_INFO_L5  BOT_PREFIX "InfoL5"

// Colors
#define COL_BG       C'25,27,35'
#define COL_BORDER   C'45,48,65'
#define COL_WHITE    C'220,225,240'
#define COL_DIM      C'120,125,145'
#define COL_GREEN    C'0,180,100'
#define COL_RED      C'220,80,80'
#define COL_BTN_BG   C'50,50,70'
#define COL_BTN_ON   C'0,100,60'
#define COL_BTN_OFF  C'60,60,85'

// Layout
#define BOT_PX      15
#define BOT_PY      25
#define BOT_W       220
#define BOT_H       195
#define BOT_H_INFO  320
#define BOT_ROW     24
#define BOT_PAD     8

// ════════════════════════════════════════════════════════════════════
// GLOBALS
// ════════════════════════════════════════════════════════════════════
int g_atrHandle;
datetime g_lastSignalBar = 0;
bool     g_botEnabled    = true;
bool     g_paused        = false;   // Auto-paused by Panel (large SL)
datetime g_pauseTime     = 0;       // Timestamp when pause was triggered
bool     g_hasPos        = false;
bool     g_infoExpanded  = false;
double   g_cachedATR     = 0;

// Candle count state (live)
int    g_countBull = 0;            // how many consecutive bull candles (bar[1], bar[2])
int    g_countBear = 0;            // how many consecutive bear candles
bool   g_wickOK[3];               // wick rule pass for bar[1..2] (index 1,2)
bool   g_atrOK[3];                // ATR filter pass for bar[1..2]
bool   g_colorOK[3];              // same color for bar[1..2]

// Breakout pending state
bool   g_pendingBuy   = false;     // waiting for breakout above bar[1].high
bool   g_pendingSell  = false;     // waiting for breakout below bar[1].low
double g_breakLevel   = 0;         // breakout price level
datetime g_pendingBar  = 0;        // bar when pending was set (to detect new bar reset)

// ── Multi-TF display (reference only, no filter) ──
#define MAX_DISP_TF 8
ENUM_TIMEFRAMES g_dispTF[MAX_DISP_TF];
string  g_dispName[MAX_DISP_TF];
int     g_dispFast[MAX_DISP_TF];  // iMA handle EMA 20
int     g_dispSlow[MAX_DISP_TF];  // iMA handle EMA 50
bool    g_dispUp[MAX_DISP_TF];
bool    g_dispDown[MAX_DISP_TF];
int     g_numDisp   = 0;
int     g_entryIdx  = -1;         // index of chart TF in display array

// ════════════════════════════════════════════════════════════════════
// TF HELPERS
// ════════════════════════════════════════════════════════════════════
string TFShortName(ENUM_TIMEFRAMES tf)
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

void BuildDispTFs()
{
   ENUM_TIMEFRAMES allTF[] = { PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1,
                                PERIOD_M30, PERIOD_M15, PERIOD_M5, PERIOD_M1 };
   g_numDisp = 0;
   g_entryIdx = -1;
   for(int i = 0; i < ArraySize(allTF) && g_numDisp < MAX_DISP_TF; i++)
   {
      g_dispTF[g_numDisp]   = allTF[i];
      g_dispName[g_numDisp] = TFShortName(allTF[i]);
      g_dispFast[g_numDisp] = INVALID_HANDLE;
      g_dispSlow[g_numDisp] = INVALID_HANDLE;
      g_dispUp[g_numDisp]   = false;
      g_dispDown[g_numDisp] = false;
      if(allTF[i] == _Period) g_entryIdx = g_numDisp;
      g_numDisp++;
   }
}

// ════════════════════════════════════════════════════════════════════
// INIT / DEINIT
// ════════════════════════════════════════════════════════════════════
int OnInit()
{
   BuildDispTFs();

   g_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("[CC BOT] Failed to create ATR handle");
      return INIT_FAILED;
   }

   // Create display EMA handles (reference only)
   for(int i = 0; i < g_numDisp; i++)
   {
      g_dispFast[i] = iMA(_Symbol, g_dispTF[i], 20, 0, MODE_EMA, PRICE_CLOSE);
      g_dispSlow[i] = iMA(_Symbol, g_dispTF[i], 50, 0, MODE_EMA, PRICE_CLOSE);
   }

   ArrayInitialize(g_wickOK, false);
   ArrayInitialize(g_atrOK, false);
   ArrayInitialize(g_colorOK, false);

   CreatePanel();
   UpdateCandleState();
   UpdateSignalStates();
   UpdatePanel();

   EventSetMillisecondTimer(1000);

   Print(StringFormat("[CC BOT] Started | %s | Magic=%d | ATR(%d) | MinMult=%.1f",
         _Symbol, InpMagic, InpATRPeriod, InpATRMinMult));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DestroyPanel();
   EventKillTimer();
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   for(int i = 0; i < g_numDisp; i++)
   {
      if(g_dispFast[i] != INVALID_HANDLE) IndicatorRelease(g_dispFast[i]);
      if(g_dispSlow[i] != INVALID_HANDLE) IndicatorRelease(g_dispSlow[i]);
   }
   Print("[CC BOT] Stopped");
}

// ════════════════════════════════════════════════════════════════════
// UI PANEL
// ════════════════════════════════════════════════════════════════════
void MakeLabel(string name, int x, int y, string text, color clr, int fontSize=9, string font="Consolas")
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

void MakeButton(string name, int x, int y, int w, int h, string text, color bgClr, color txtClr, int fontSize=9)
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
   MakeLabel(OBJ_TITLE, x + BOT_PAD, row, "CC Bot v1.01", C'170,180,215', 10, "Segoe UI Semibold");
   row += BOT_ROW;

   // Row 2: Start/Stop button
   MakeButton(OBJ_START, x + BOT_PAD, row, BOT_W - 2*BOT_PAD, 24,
              "Bot: ON", COL_BTN_ON, COL_WHITE, 10);
   row += 26;

   // Row 3: TF name labels (8 columns) — fixed width
   int colW = (BOT_W - 2*BOT_PAD) / 8;
   for(int i = 0; i < g_numDisp && i < 8; i++)
   {
      string objName = BOT_PREFIX + "TF" + IntegerToString(i);
      MakeLabel(objName, x + BOT_PAD + i * colW, row, g_dispName[i], COL_DIM, 9, "Consolas");
   }
   row += 15;

   // Row 4: Arrow labels (8 columns) — same fixed width
   for(int i = 0; i < g_numDisp && i < 8; i++)
   {
      string objName = BOT_PREFIX + "Sig" + IntegerToString(i);
      string initText = (i == g_entryIdx) ? "[-]" : "-";
      MakeLabel(objName, x + BOT_PAD + i * colW, row, initText, COL_DIM, 9, "Consolas");
   }
   row += 18;

   // Row 5: Position info
   MakeLabel(OBJ_POS_INFO, x + BOT_PAD, row, "No position", COL_DIM, 9, "Consolas");
   row += BOT_ROW + 2;

   // Row 6: Force BUY / Force SELL + Info button
   int infoBtnW = 26;
   int btnW = (BOT_W - 2*BOT_PAD - 4 - infoBtnW - 2) / 2;
   MakeButton(OBJ_FORCE_BUY,  x + BOT_PAD,          row, btnW, 24, "Force BUY",  C'0,100,65', COL_WHITE, 9);
   MakeButton(OBJ_FORCE_SELL, x + BOT_PAD + btnW + 4, row, btnW, 24, "Force SELL", C'140,40,40', COL_WHITE, 9);
   MakeButton(OBJ_INFO_BTN, x + BOT_PAD + 2*btnW + 4 + 2, row, infoBtnW, 24, "?", C'60,60,85', C'180,180,200', 10);
   row += 28;

   // Info section (hidden by default, 5 lines)
   int infoY = row;
   MakeLabel(OBJ_INFO_L1, x + BOT_PAD, infoY, "", COL_DIM, 9, "Consolas"); infoY += 19;
   MakeLabel(OBJ_INFO_L2, x + BOT_PAD, infoY, "", COL_DIM, 9, "Consolas"); infoY += 19;
   MakeLabel(OBJ_INFO_L3, x + BOT_PAD, infoY, "", COL_DIM, 9, "Consolas"); infoY += 19;
   MakeLabel(OBJ_INFO_L4, x + BOT_PAD, infoY, "", COL_DIM, 9, "Consolas"); infoY += 19;
   MakeLabel(OBJ_INFO_L5, x + BOT_PAD, infoY, "", COL_DIM, 9, "Consolas");
   // Hide info labels initially
   ObjectSetInteger(0, OBJ_INFO_L1, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, OBJ_INFO_L2, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, OBJ_INFO_L3, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, OBJ_INFO_L4, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, OBJ_INFO_L5, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);

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
   if(g_paused)
   {
      // Show countdown if auto-resume is enabled
      if(InpPauseBars > 0 && g_pauseTime > 0)
      {
         int barsSincePause = iBarShift(_Symbol, _Period, g_pauseTime);
         int barsLeft = InpPauseBars - barsSincePause;
         if(barsLeft < 0) barsLeft = 0;
         ObjectSetString(0, OBJ_START, OBJPROP_TEXT,
            StringFormat("⚠ PAUSED | %d bars left", barsLeft));
      }
      else
         ObjectSetString(0, OBJ_START, OBJPROP_TEXT, "⚠ PAUSED (Large SL)");
      ObjectSetInteger(0, OBJ_START, OBJPROP_BGCOLOR, C'140,60,20');
      ObjectSetInteger(0, OBJ_START, OBJPROP_BORDER_COLOR, C'180,80,30');
   }
   else if(g_botEnabled)
   {
      ObjectSetString (0, OBJ_START, OBJPROP_TEXT, "Bot: ON");
      ObjectSetInteger(0, OBJ_START, OBJPROP_BGCOLOR, COL_BTN_ON);
      ObjectSetInteger(0, OBJ_START, OBJPROP_BORDER_COLOR, COL_BTN_ON);
   }
   else
   {
      ObjectSetString (0, OBJ_START, OBJPROP_TEXT, "Bot: OFF");
      ObjectSetInteger(0, OBJ_START, OBJPROP_BGCOLOR, COL_BTN_OFF);
      ObjectSetInteger(0, OBJ_START, OBJPROP_BORDER_COLOR, COL_BTN_OFF);
   }

   // ── TF signal arrows (reference, no filter) ──
   for(int i = 0; i < g_numDisp && i < 8; i++)
   {
      string objSig = BOT_PREFIX + "Sig" + IntegerToString(i);
      string arrow;
      color  clr;

      if(g_dispUp[i])       { arrow = "▲"; clr = COL_GREEN; }
      else if(g_dispDown[i]){ arrow = "▼"; clr = COL_RED; }
      else                  { arrow = "-"; clr = COL_DIM; }

      // Entry TF with brackets
      if(i == g_entryIdx)
         ObjectSetString(0, objSig, OBJPROP_TEXT, "[" + arrow + "]");
      else
         ObjectSetString(0, objSig, OBJPROP_TEXT, " " + arrow);
      ObjectSetInteger(0, objSig, OBJPROP_COLOR, clr);
   }

   // ── Position info ──
   g_hasPos = HasPosition();
   if(g_hasPos)
   {
      double pnl  = GetPositionPnL();
      double lots = GetPositionLots();
      bool isBuy  = IsPositionBuy();
      color pnlClr = (pnl >= 0) ? COL_GREEN : COL_RED;
      ObjectSetString(0, OBJ_POS_INFO, OBJPROP_TEXT,
         StringFormat("%s %.2f | %s$%.1f", isBuy ? "BUY" : "SELL", lots,
                      pnl >= 0 ? "+" : "", pnl));
      ObjectSetInteger(0, OBJ_POS_INFO, OBJPROP_COLOR, pnlClr);
   }
   else
   {
      // Show lot from Panel GV
      string gvLot = "TP_Lot_" + _Symbol;
      double lot = 0;
      if(GlobalVariableCheck(gvLot))
         lot = GlobalVariableGet(gvLot);

      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(lotStep > 0 && lot > 0)
         lot = MathFloor(lot / lotStep) * lotStep;
      lot = MathMax(minLot, MathMin(maxLot, lot));

      double margin = 0;
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(lot > 0)
         if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, price, margin))
            margin = 0;

      ObjectSetString(0, OBJ_POS_INFO, OBJPROP_TEXT,
         StringFormat("Lot %.2f | Margin $%.0f", lot, margin));
      ObjectSetInteger(0, OBJ_POS_INFO, OBJPROP_COLOR, COL_DIM);
   }

   // ── Info panel (expand / collapse) — LIVE candle counting ──
   int bgH = BOT_H;
   if(g_infoExpanded)
   {
      bgH = BOT_H_INFO;
      ObjectSetString(0, OBJ_INFO_BTN, OBJPROP_TEXT, "×");

      // Line 1: Count summary
      int count = 0;
      string dir = "—";
      if(g_countBull > 0)      { count = g_countBull; dir = "BUY"; }
      else if(g_countBear > 0) { count = g_countBear; dir = "SELL"; }

      string dots = "";
      for(int i = 0; i < count; i++)
         dots += (g_countBull > 0) ? "▲" : "▼";
      for(int i = count; i < 2; i++)
         dots += "_";

      bool isPending = (g_pendingBuy || g_pendingSell);
      if(isPending)
         ObjectSetString(0, OBJ_INFO_L1, OBJPROP_TEXT,
            StringFormat("WAIT %s > %s  %s",
               g_pendingBuy ? "BUY" : "SELL",
               DoubleToString(g_breakLevel, _Digits), dots));
      else
         ObjectSetString(0, OBJ_INFO_L1, OBJPROP_TEXT,
            StringFormat("Count: %d/2 %s  %s", count, dir, dots));
      ObjectSetInteger(0, OBJ_INFO_L1, OBJPROP_COLOR,
         isPending ? (g_pendingBuy ? COL_GREEN : COL_RED) : COL_WHITE);

      // Lines 2-3: Bar details (only bar[1] and bar[2])
      for(int b = 1; b <= 2; b++)
      {
         string objL = (b == 1) ? OBJ_INFO_L2 : OBJ_INFO_L3;
         string col  = g_colorOK[b] ? (g_countBull > 0 ? "Green" : "Red") : "✗";
         string wck  = g_wickOK[b] ? "Wick✓" : "Wick✗";
         string atr  = g_atrOK[b]  ? "ATR✓"  : "ATR✗";

         if(g_colorOK[b])
            ObjectSetString(0, objL, OBJPROP_TEXT,
               StringFormat("Bar%d: %s %s %s", b, col, wck, atr));
         else
            ObjectSetString(0, objL, OBJPROP_TEXT,
               StringFormat("Bar%d: %s", b, col));
         ObjectSetInteger(0, objL, OBJPROP_COLOR,
            (g_colorOK[b] && g_wickOK[b] && g_atrOK[b]) ? COL_GREEN : COL_DIM);
      }

      // Line 4: Breakout level
      if(isPending)
      {
         ObjectSetString(0, OBJ_INFO_L4, OBJPROP_TEXT,
            StringFormat("Break: %s %s",
               g_pendingBuy ? "Ask >" : "Bid <",
               DoubleToString(g_breakLevel, _Digits)));
         ObjectSetInteger(0, OBJ_INFO_L4, OBJPROP_COLOR, C'200,180,80');
      }
      else
      {
         ObjectSetString(0, OBJ_INFO_L4, OBJPROP_TEXT, "Break: — (no setup)");
         ObjectSetInteger(0, OBJ_INFO_L4, OBJPROP_COLOR, COL_DIM);
      }

      // Line 5: ATR info
      double minRange = g_cachedATR * InpATRMinMult;
      ObjectSetString(0, OBJ_INFO_L5, OBJPROP_TEXT,
         StringFormat("ATR: %.1f | Min: %.1f (%.1fx)", g_cachedATR, minRange, InpATRMinMult));
      ObjectSetInteger(0, OBJ_INFO_L5, OBJPROP_COLOR, COL_DIM);

      // Show all info labels
      ObjectSetInteger(0, OBJ_INFO_L1, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      ObjectSetInteger(0, OBJ_INFO_L2, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      ObjectSetInteger(0, OBJ_INFO_L3, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      ObjectSetInteger(0, OBJ_INFO_L4, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      ObjectSetInteger(0, OBJ_INFO_L5, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   }
   else
   {
      ObjectSetString(0, OBJ_INFO_BTN, OBJPROP_TEXT, "?");
      // Hide all info labels
      ObjectSetInteger(0, OBJ_INFO_L1, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, OBJ_INFO_L2, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, OBJ_INFO_L3, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, OBJ_INFO_L4, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, OBJ_INFO_L5, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   }
   ObjectSetInteger(0, OBJ_BG, OBJPROP_YSIZE, bgH);

   ChartRedraw();
}

// ════════════════════════════════════════════════════════════════════
// SIGNAL ANALYSIS
// ════════════════════════════════════════════════════════════════════
void UpdateSignalStates()
{
   // Multi-TF EMA direction (reference only)
   for(int i = 0; i < g_numDisp; i++)
   {
      double fast[1], slow[1];
      g_dispUp[i] = g_dispDown[i] = false;
      if(g_dispFast[i] == INVALID_HANDLE || g_dispSlow[i] == INVALID_HANDLE) continue;
      if(CopyBuffer(g_dispFast[i], 0, 1, 1, fast) != 1) continue;
      if(CopyBuffer(g_dispSlow[i], 0, 1, 1, slow) != 1) continue;
      g_dispUp[i]   = (fast[0] > slow[0]);
      g_dispDown[i] = (fast[0] < slow[0]);
   }

   // Cache ATR
   double atr[1];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1 && atr[0] > 0)
      g_cachedATR = atr[0];
}

void UpdateCandleState()
{
   // Reset display state
   g_countBull = g_countBear = 0;
   ArrayInitialize(g_wickOK, false);
   ArrayInitialize(g_atrOK, false);
   ArrayInitialize(g_colorOK, false);

   // Check bar[1] and bar[2] (2 confirmed closed candles)
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

   // ATR filter
   if(InpATRMinMult > 0 && g_cachedATR > 0)
   {
      g_atrOK[1] = ((h1 - l1) >= InpATRMinMult * g_cachedATR);
      g_atrOK[2] = ((h2 - l2) >= InpATRMinMult * g_cachedATR);
   }
   else
   {
      g_atrOK[1] = g_atrOK[2] = true;
   }

   // Check for 2 consecutive green
   if(bar1Bull && bar2Bull)
   {
      g_countBull = 2;
      g_colorOK[1] = g_colorOK[2] = true;

      // Wick rule: bar[1].low > bar[2].low (strictly higher lows)
      g_wickOK[2] = true;  // first candle always OK
      g_wickOK[1] = (l1 > l2);

      // If all conditions pass → set pending breakout
      if(g_wickOK[1] && g_atrOK[1] && g_atrOK[2])
      {
         g_pendingBuy  = true;
         g_pendingSell = false;
         g_breakLevel  = h1;  // breakout above bar[1].high
         g_pendingBar  = iTime(_Symbol, _Period, 0);
      }
      else
      {
         g_pendingBuy = g_pendingSell = false;
      }
   }
   // Check for 2 consecutive red
   else if(bar1Bear && bar2Bear)
   {
      g_countBear = 2;
      g_colorOK[1] = g_colorOK[2] = true;

      // Wick rule: bar[1].high < bar[2].high (strictly lower highs)
      g_wickOK[2] = true;
      g_wickOK[1] = (h1 < h2);

      if(g_wickOK[1] && g_atrOK[1] && g_atrOK[2])
      {
         g_pendingSell = true;
         g_pendingBuy  = false;
         g_breakLevel  = l1;  // breakout below bar[1].low
         g_pendingBar  = iTime(_Symbol, _Period, 0);
      }
      else
      {
         g_pendingBuy = g_pendingSell = false;
      }
   }
   else
   {
      // No 2-candle pattern → clear pending
      g_pendingBuy = g_pendingSell = false;

      // Partial count for display
      if(bar1Bull) { g_countBull = 1; g_colorOK[1] = true; }
      else if(bar1Bear) { g_countBear = 1; g_colorOK[1] = true; }
   }
}

// ════════════════════════════════════════════════════════════════════
// ON TICK — Entry logic
// ════════════════════════════════════════════════════════════════════
void OnTick()
{
   // Check pause from Panel (GV value = timestamp of pause event)
   string gvPause = "TP_BotPause_" + _Symbol;
   if(!g_paused && GlobalVariableCheck(gvPause))
   {
      double gvVal = GlobalVariableGet(gvPause);
      if(gvVal >= 1.0)
      {
         g_paused = true;
         g_botEnabled = false;
         g_pauseTime = (datetime)(int)gvVal;
         Print(StringFormat("[CC BOT] Auto-paused by Panel (Large SL) | Pause time=%s | Resume after %d bars",
               TimeToString(g_pauseTime, TIME_DATE|TIME_MINUTES), InpPauseBars));
         UpdatePanel();
      }
   }

   // Auto-resume: check if enough bars have passed since pause
   if(g_paused && InpPauseBars > 0 && g_pauseTime > 0)
   {
      int barsSincePause = iBarShift(_Symbol, _Period, g_pauseTime);
      if(barsSincePause >= InpPauseBars)
      {
         g_paused = false;
         g_botEnabled = true;
         g_pauseTime = 0;
         if(GlobalVariableCheck(gvPause))
            GlobalVariableDel(gvPause);
         Print(StringFormat("[CC BOT] Auto-resumed after %d bars pause", barsSincePause));
         UpdatePanel();
      }
   }

   // On new bar: update candle state
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar != g_lastSignalBar)
   {
      g_lastSignalBar = curBar;
      UpdateCandleState();
   }

   // Skip if disabled or paused or already has position
   if(!g_botEnabled || g_paused) return;
   if(HasPosition()) return;

   // ── Per-tick breakout check ──
   if(g_pendingBuy && g_breakLevel > 0)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(ask > g_breakLevel)
      {
         Print(StringFormat("[CC BOT] Breakout BUY! Price %.5f > %.5f",
               ask, g_breakLevel));
         g_pendingBuy = false;
         OpenTrade(true);
      }
   }
   else if(g_pendingSell && g_breakLevel > 0)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid < g_breakLevel)
      {
         Print(StringFormat("[CC BOT] Breakout SELL! Price %.5f < %.5f",
               bid, g_breakLevel));
         g_pendingSell = false;
         OpenTrade(false);
      }
   }
}

void OnTimer()
{
   UpdateSignalStates();
   UpdateCandleState();
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

      if(g_botEnabled && g_paused)
      {
         g_paused = false;
         g_pauseTime = 0;
         string gvPause = "TP_BotPause_" + _Symbol;
         if(GlobalVariableCheck(gvPause))
            GlobalVariableDel(gvPause);
         Print("[CC BOT] Pause cleared — resumed by user");
      }

      Print(StringFormat("[CC BOT] %s", g_botEnabled ? "ENABLED" : "DISABLED"));
      UpdatePanel();
   }
   // ── Force BUY ──
   else if(sparam == OBJ_FORCE_BUY)
   {
      ObjectSetInteger(0, OBJ_FORCE_BUY, OBJPROP_STATE, false);
      if(HasPosition())
      {
         Print("[CC BOT] Already have a position, cannot force BUY");
         return;
      }
      Print("[CC BOT] Force BUY triggered by user");
      OpenTrade(true);
      UpdatePanel();
   }
   // ── Info toggle ──
   else if(sparam == OBJ_INFO_BTN)
   {
      ObjectSetInteger(0, OBJ_INFO_BTN, OBJPROP_STATE, false);
      g_infoExpanded = !g_infoExpanded;
      UpdatePanel();
   }
   // ── Force SELL ──
   else if(sparam == OBJ_FORCE_SELL)
   {
      ObjectSetInteger(0, OBJ_FORCE_SELL, OBJPROP_STATE, false);
      if(HasPosition())
      {
         Print("[CC BOT] Already have a position, cannot force SELL");
         return;
      }
      Print("[CC BOT] Force SELL triggered by user");
      OpenTrade(false);
      UpdatePanel();
   }
}

// ════════════════════════════════════════════════════════════════════
// TRADE FUNCTIONS
// ════════════════════════════════════════════════════════════════════
void OpenTrade(bool isBuy)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // ── Lot from Panel GV, fallback = min lot ──
   double lot = 0;
   string gvName = "TP_Lot_" + _Symbol;
   if(GlobalVariableCheck(gvName))
      lot = GlobalVariableGet(gvName);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0 && lot > 0)
      lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));

   double price;
   ENUM_ORDER_TYPE orderType;

   if(isBuy)
   {
      orderType = ORDER_TYPE_BUY;
      price = ask;
   }
   else
   {
      orderType = ORDER_TYPE_SELL;
      price = bid;
   }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = orderType;
   req.price     = price;
   req.sl        = 0;  // Panel manages SL
   req.tp        = 0;  // Panel manages TP
   req.deviation = InpDeviation;
   req.magic     = InpMagic;
   req.comment   = "CCBot";

   if(OrderSend(req, res))
   {
      Print(StringFormat("[CC BOT] %s %.2f @ %s | No SL/TP (Panel manages)",
            isBuy ? "BUY" : "SELL", lot,
            DoubleToString(price, _Digits)));

      // Draw entry arrow on chart
      DrawEntryArrow(isBuy, price, lot);
   }
   else
   {
      Print(StringFormat("[CC BOT] OrderSend FAILED: %d - %s",
            res.retcode, res.comment));
   }
}

// ════════════════════════════════════════════════════════════════════
// CHART MARKERS
// ════════════════════════════════════════════════════════════════════
void DrawEntryArrow(bool isBuy, double price, double lot)
{
   static int arrowId = 0;
   arrowId++;
   string name = StringFormat("CCBot_Entry_%d", arrowId);

   ObjectCreate(0, name, isBuy ? OBJ_ARROW_BUY : OBJ_ARROW_SELL, 0,
                TimeCurrent(), price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? COL_GREEN : COL_RED);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString (0, name, OBJPROP_TEXT,
      StringFormat("%s %.2f @ %s", isBuy ? "BUY" : "SELL",
                   lot, DoubleToString(price, _Digits)));
   ChartRedraw();
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
