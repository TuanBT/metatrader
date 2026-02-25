//+------------------------------------------------------------------+
//| Expert Trading Panel.mq5                                         |
//| Tuan Quick Trade – One-Click Manual Trading Panel                 |
//|                                                                  |
//| Features:                                                        |
//|  • Risk $ input → auto-calculated lot size                       |
//|  • Auto SL: ATR / Last-N-bars / Fixed pips                       |
//|  • One-click BUY / SELL                                          |
//|  • Auto trailing SL: Candle-based or R-based                     |
//|  • Break-even + 50% partial close                                |
//|  • Dark chart theme (auto-apply on init)                         |
//|                                                                  |
//| Usage:                                                           |
//|  1. Attach EA to chart                                           |
//|  2. Set Risk $ in panel (max loss per trade)                     |
//|  3. Click BUY or SELL → order fires instantly                    |
//|  4. Trailing SL manages the trade automatically                  |
//|  5. Use "CLOSE ALL" to close all positions                      |
//|  6. Use "CLOSE ALL" to exit all positions                        |
//+------------------------------------------------------------------+
#property copyright "Tuan"
#property version   "1.00"
#property strict
#property description "One-click trading panel with auto risk & trail"

// ════════════════════════════════════════════════════════════════════
// ENUMS
// ════════════════════════════════════════════════════════════════════
enum ENUM_SL_MODE
{
   SL_ATR       = 0,  // ATR-based
   SL_LOOKBACK  = 1,  // Last N bars H/L
   SL_FIXED     = 2,  // Fixed pips
};

enum ENUM_TRAIL_MODE
{
   TRAIL_CANDLE = 0,  // Candle trail (bar low/high)
   TRAIL_R      = 1,  // R-based step trail
   TRAIL_NONE   = 2,  // No auto trail
};

// ════════════════════════════════════════════════════════════════════
// INPUTS
// ════════════════════════════════════════════════════════════════════
input group           "══ Risk Management ══"
input double          InpDefaultRisk    = 10.0;      // Risk $ (max loss per trade)
input double          InpMaxLotSize     = 1.0;       // Max lot size cap

input group           "══ Stop Loss ══"
input ENUM_SL_MODE    InpSLMode         = SL_ATR;    // SL Mode
input int             InpATRPeriod      = 14;        // ATR Period
input double          InpATRMult        = 1.5;       // ATR Multiplier
input int             InpSLLookback     = 5;         // Lookback bars (Last-N mode)
input double          InpFixedSLPips    = 50.0;      // Fixed SL pips (Fixed mode)
input double          InpSLBuffer       = 5.0;       // SL Buffer % (push SL further)

input group           "══ Trailing Stop ══"
input ENUM_TRAIL_MODE InpTrailMode      = TRAIL_CANDLE; // Trail Mode
input double          InpTrailStartR    = 0.5;       // [R] Start trailing after X×R
input double          InpTrailStepR     = 0.25;      // [R] Trail step X×R

input group           "══ General ══"
input ulong           InpMagic          = 99999;     // Magic Number
input int             InpDeviation      = 20;        // Max slippage (points)

// ════════════════════════════════════════════════════════════════════
// CONSTANTS
// ════════════════════════════════════════════════════════════════════
#define PREFIX       "Bot_"

// Layout
#define PX           15
#define PY           25
#define PW           320
#define MARGIN       12
#define IX           (PX + MARGIN)
#define IW           (PW - 2 * MARGIN)

// Fonts
#define FONT_MAIN    "Segoe UI"
#define FONT_BOLD    "Segoe UI Semibold"
#define FONT_MONO    "Consolas"

// Colors – Panel
#define COL_BG        C'25,25,35'
#define COL_TITLE_BG  C'35,40,60'
#define COL_TEXT      C'210,210,220'
#define COL_DIM       C'130,130,150'
#define COL_BORDER    C'50,50,65'

// Colors – Inputs
#define COL_EDIT_BG   C'35,35,50'
#define COL_EDIT_BD   C'60,60,80'

// Colors – Buttons
#define COL_BUY       C'0,137,82'
#define COL_BUY_HI    C'0,160,95'
#define COL_SELL      C'220,50,47'
#define COL_SELL_HI   C'245,65,60'
#define COL_BTN       C'55,55,72'
#define COL_BTN_TXT   C'200,200,220'
#define COL_CLOSE     C'160,40,40'
#define COL_WHITE     C'255,255,255'

// Colors – Status
#define COL_PROFIT    C'0,180,100'
#define COL_LOSS      C'230,60,60'

// Object names
#define OBJ_BG         PREFIX "bg"
#define OBJ_TITLE_BG   PREFIX "title_bg"
#define OBJ_TITLE      PREFIX "title"
#define OBJ_RISK_LBL   PREFIX "risk_lbl"
#define OBJ_RISK_EDT   PREFIX "risk_edt"
#define OBJ_SPRD_LBL   PREFIX "sprd_lbl"
#define OBJ_STATUS_LBL PREFIX "status_lbl"
#define OBJ_BUY_BTN    PREFIX "buy_btn"
#define OBJ_SELL_BTN   PREFIX "sell_btn"
#define OBJ_CLOSE_BTN  PREFIX "close_btn"
#define OBJ_SEP1       PREFIX "sep1"
#define OBJ_SEP2       PREFIX "sep2"

// Chart lines (SL levels)
#define OBJ_SL_BUY_LINE   PREFIX "sl_buy_line"
#define OBJ_SL_SELL_LINE  PREFIX "sl_sell_line"
#define OBJ_SL_ACTIVE     PREFIX "sl_active"
#define OBJ_ENTRY_LINE    PREFIX "entry_line"
#define OBJ_AUTO_BTN      PREFIX "auto_btn"



// Theme buttons
#define OBJ_THEME_DARK    PREFIX "theme_dark"
#define OBJ_THEME_LIGHT   PREFIX "theme_light"
#define OBJ_THEME_ZEN     PREFIX "theme_zen"

// ════════════════════════════════════════════════════════════════════
// GLOBALS
// ════════════════════════════════════════════════════════════════════
int      g_atrHandle  = INVALID_HANDLE;
double   g_riskMoney  = 0;

// Position tracking
bool     g_hasPos     = false;
bool     g_isBuy      = false;
double   g_entryPx    = 0;
double   g_origSL     = 0;
double   g_currentSL  = 0;
double   g_riskDist   = 0;        // |entry − origSL| for R calcs
datetime g_lastBar    = 0;

// Auto Candle Counter mode
bool     g_autoMode   = false;
int      g_theme      = 0;       // 0=Dark, 1=Light, 2=Zen

// Live ATR multiplier (changeable from panel)
double   g_atrMult    = 0;

// ════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════
double PipSize()
{
   return (_Digits == 3 || _Digits == 5) ? 10 * _Point : _Point;
}

double NormPrice(double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0) tick = _Point;
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
}

double NormLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathFloor(lot / step) * step;
   lot = MathMax(lot, minL);
   lot = MathMin(lot, MathMin(maxL, InpMaxLotSize));
   return NormalizeDouble(lot, 8);
}

// Return the calculated SL *price* for a given direction
double CalcSLPrice(bool isBuy)
{
   double entry = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0;

   switch(InpSLMode)
   {
      case SL_ATR:
      {
         double atr[1];
         if(g_atrHandle != INVALID_HANDLE &&
            CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1)
         {
            double dist = atr[0] * g_atrMult;
            if(InpSLBuffer > 0) dist *= (1.0 + InpSLBuffer / 100.0);
            sl = isBuy ? entry - dist : entry + dist;
         }
         break;
      }
      case SL_LOOKBACK:
      {
         int lb = MathMax(InpSLLookback, 3);
         if(isBuy)
         {
            sl = iLow(_Symbol, _Period, 1);
            for(int i = 2; i <= lb; i++)
               sl = MathMin(sl, iLow(_Symbol, _Period, i));
            if(InpSLBuffer > 0)
               sl -= MathAbs(entry - sl) * InpSLBuffer / 100.0;
         }
         else
         {
            sl = iHigh(_Symbol, _Period, 1);
            for(int i = 2; i <= lb; i++)
               sl = MathMax(sl, iHigh(_Symbol, _Period, i));
            if(InpSLBuffer > 0)
               sl += MathAbs(sl - entry) * InpSLBuffer / 100.0;
         }
         break;
      }
      case SL_FIXED:
      {
         double dist = InpFixedSLPips * PipSize();
         if(InpSLBuffer > 0) dist *= (1.0 + InpSLBuffer / 100.0);
         sl = isBuy ? entry - dist : entry + dist;
         break;
      }
   }

   return NormPrice(sl);
}

// Lot from risk $ and SL distance
double CalcLot(double slDist)
{
   if(slDist <= 0 || g_riskMoney <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSz <= 0 || tickVal <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double riskPerLot = (slDist / tickSz) * tickVal;
   double lot = g_riskMoney / riskPerLot;
   return NormLot(lot);
}

bool HasOwnPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)        == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)  == InpMagic)
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
      if(PositionGetString(POSITION_SYMBOL)        != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;
      pnl += PositionGetDouble(POSITION_PROFIT)
           + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

// ════════════════════════════════════════════════════════════════════
// CHART LINES – SL level visualization
// ════════════════════════════════════════════════════════════════════
void SetHLine(string name, double price, color clr,
             ENUM_LINE_STYLE style = STYLE_DASH, int width = 1,
             string label = "")
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   }
   ObjectSetDouble (0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   if(label != "")
      ObjectSetString(0, name, OBJPROP_TEXT, label);
}

void HideHLine(string name)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
}

void UpdateChartLines()
{
   if(g_hasPos)
   {
      // In trade: show active SL + entry line, hide preview lines
      HideHLine(OBJ_SL_BUY_LINE);
      HideHLine(OBJ_SL_SELL_LINE);

      if(g_currentSL > 0)
         SetHLine(OBJ_SL_ACTIVE, g_currentSL, C'255,200,0',
                  STYLE_SOLID, 2, "SL");
      if(g_entryPx > 0)
         SetHLine(OBJ_ENTRY_LINE, g_entryPx, C'100,150,255',
                  STYLE_DOT, 1, "Entry");
   }
   else
   {
      // No trade: show preview SL levels for both directions
      HideHLine(OBJ_SL_ACTIVE);
      HideHLine(OBJ_ENTRY_LINE);

      double slBuy  = CalcSLPrice(true);
      double slSell = CalcSLPrice(false);

      if(slBuy > 0)
         SetHLine(OBJ_SL_BUY_LINE, slBuy, C'38,166,154',
                  STYLE_DASH, 1, StringFormat("BUY SL  %." + IntegerToString(_Digits) + "f", slBuy));
      if(slSell > 0)
         SetHLine(OBJ_SL_SELL_LINE, slSell, C'239,83,80',
                  STYLE_DASH, 1, StringFormat("SELL SL  %." + IntegerToString(_Digits) + "f", slSell));
   }
}

// ════════════════════════════════════════════════════════════════════
// PANEL – Object Builders
// ════════════════════════════════════════════════════════════════════
void MakeRect(string name, int x, int y, int w, int h,
              color bg, color bd)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, bd);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,       true);
}

void MakeLabel(string name, int x, int y, string text,
               color clr, int sz = 9, string font = FONT_MAIN)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT,       text);
   ObjectSetString (0, name, OBJPROP_FONT,       font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   sz);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

void MakeButton(string name, int x, int y, int w, int h,
                string text, color clr, color bg,
                int sz = 10, string font = FONT_BOLD)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        h);
   ObjectSetString (0, name, OBJPROP_TEXT,          text);
   ObjectSetString (0, name, OBJPROP_FONT,          font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,      sz);
   ObjectSetInteger(0, name, OBJPROP_COLOR,         clr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,       bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR,  bg);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,    false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,        true);
   ObjectSetInteger(0, name, OBJPROP_STATE,         false);
}

void MakeEdit(string name, int x, int y, int w, int h,
              string text, color clr, color bg, color bd)
{
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        h);
   ObjectSetString (0, name, OBJPROP_TEXT,          text);
   ObjectSetString (0, name, OBJPROP_FONT,          FONT_MONO);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,      10);
   ObjectSetInteger(0, name, OBJPROP_COLOR,         clr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,       bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR,  bd);
   ObjectSetInteger(0, name, OBJPROP_READONLY,      false);
   ObjectSetInteger(0, name, OBJPROP_ALIGN,         ALIGN_CENTER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,    false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,        true);
}

// ════════════════════════════════════════════════════════════════════
// PANEL – Create / Destroy / Update
// ════════════════════════════════════════════════════════════════════
void CreatePanel()
{
   int y  = PY;
   int bw = (IW - 8) / 2;   // half-width for paired buttons

   // ── Background ──
   MakeRect(OBJ_BG, PX, y, PW, 300, COL_BG, COL_BORDER);

   // ── Title bar ──
   MakeRect(OBJ_TITLE_BG, PX + 1, y + 1, PW - 2, 26, COL_TITLE_BG, COL_TITLE_BG);
   MakeLabel(OBJ_TITLE, IX, y + 6, "Trading Panel", C'170,180,215', 10, FONT_BOLD);

   // Theme buttons (right side of title bar)
   {
      int tw = 42;
      int tx = PX + PW - 3 * tw - 10;
      MakeButton(OBJ_THEME_DARK,  tx,            y + 3, tw, 20, "Dark",  COL_BTN_TXT, C'40,40,55', 7, FONT_MAIN);
      MakeButton(OBJ_THEME_LIGHT, tx + tw + 2,   y + 3, tw, 20, "Light", COL_BTN_TXT, C'40,40,55', 7, FONT_MAIN);
      MakeButton(OBJ_THEME_ZEN,   tx + 2*(tw+2), y + 3, tw, 20, "Zen",   COL_BTN_TXT, C'40,40,55', 7, FONT_MAIN);
   }
   y += 32;

   // ── Max Risk + Position PnL (same row) ──
   MakeLabel(OBJ_RISK_LBL, IX, y + 3, "Max Risk $", COL_DIM, 9);
   MakeEdit(OBJ_RISK_EDT, IX + 76, y, 40, 22,
            IntegerToString((int)InpDefaultRisk),
            COL_WHITE, COL_EDIT_BG, COL_EDIT_BD);
   MakeLabel(OBJ_STATUS_LBL, IX + 122, y + 4, " ", COL_DIM, 11);
   y += 26;

   // ── SL + Spread info ──
   MakeLabel(OBJ_SPRD_LBL, IX, y, "", COL_DIM, 8, FONT_MONO);
   y += 18;

   // ── Separator ──
   MakeRect(OBJ_SEP1, IX, y, IW, 1, COL_BORDER, COL_BORDER);
   y += 6;

   // ── BUY / SELL buttons ──
   MakeButton(OBJ_BUY_BTN,  PX + 5,          y, bw, 52,
              "BUY", COL_WHITE, COL_BUY, 14);
   MakeButton(OBJ_SELL_BTN, PX + 5 + bw + 8, y, bw, 52,
              "SELL", COL_WHITE, COL_SELL, 14);
   y += 58;

   // ── Separator ──
   MakeRect(OBJ_SEP2, IX, y, IW, 1, COL_BORDER, COL_BORDER);
   y += 6;

   // ── Candle Counter + CLOSE ALL (2 buttons, 1 row) ──
   {
      int bw2 = (PW - 18 - 4) / 2;  // 2 buttons, 1 gap of 4px
      MakeButton(OBJ_AUTO_BTN,  PX + 5,             y, bw2, 28,
                 "Candle Counter 3: OFF", C'180,180,200', C'60,60,85', 8);
      MakeButton(OBJ_CLOSE_BTN, PX + 5 + bw2 + 4,   y, bw2, 28,
                 "CLOSE ALL", C'255,200,200', C'120,30,30', 9);
   }
   y += 34;

   // Adjust panel background height
   ObjectSetInteger(0, OBJ_BG, OBJPROP_YSIZE, y - PY + 5);

   ChartRedraw();
}

void DestroyPanel()
{
   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw();
}

void UpdatePanel()
{
   // ── Read risk from edit ──
   string riskStr = ObjectGetString(0, OBJ_RISK_EDT, OBJPROP_TEXT);
   double parsed  = StringToDouble(riskStr);
   if(parsed > 0) g_riskMoney = parsed;
   else           g_riskMoney = InpDefaultRisk;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // ── SL prices for each direction ──
   double slBuy   = CalcSLPrice(true);
   double slSell  = CalcSLPrice(false);
   double distBuy  = MathAbs(ask - slBuy);
   double distSell = MathAbs(bid - slSell);

   // ── Lot sizes ──
   double lotBuy  = CalcLot(distBuy);
   double lotSell = CalcLot(distSell);

   // ── SL label ──
   string slMode = "";
   switch(InpSLMode)
   {
      case SL_ATR:      slMode = StringFormat("ATR %.1fx", g_atrMult); break;
      case SL_LOOKBACK: slMode = StringFormat("LB %d bars",  InpSLLookback); break;
      case SL_FIXED:    slMode = StringFormat("Fix %.0f pip", InpFixedSLPips); break;
   }
   double avgPts = ((distBuy + distSell) / 2.0) / _Point;

   // ── BUY / SELL button text ──
   ObjectSetString(0, OBJ_BUY_BTN,  OBJPROP_TEXT, StringFormat("BUY  %.2f", lotBuy));
   ObjectSetString(0, OBJ_SELL_BTN, OBJPROP_TEXT, StringFormat("SELL  %.2f", lotSell));

   // ── SL + Spread (own line) ──
   double spread = (ask - bid) / _Point;
   ObjectSetString(0, OBJ_SPRD_LBL, OBJPROP_TEXT,
      StringFormat("SL %.0f | Spread %.0f", avgPts, spread));
   ObjectSetInteger(0, OBJ_SPRD_LBL, OBJPROP_COLOR, COL_DIM);

   // ── Position status (next to Risk) ──
   g_hasPos = HasOwnPosition();
   if(g_hasPos)
   {
      SyncIfNeeded();
      string dir = g_isBuy ? "LONG" : "SHORT";
      double pnl = GetPositionPnL();
      ObjectSetString(0, OBJ_STATUS_LBL, OBJPROP_TEXT,
         StringFormat("%s $%+.2f", dir, pnl));
      ObjectSetInteger(0, OBJ_STATUS_LBL, OBJPROP_COLOR,
         pnl >= 0 ? COL_PROFIT : COL_LOSS);
   }
   else
   {
      ObjectSetString(0, OBJ_STATUS_LBL, OBJPROP_TEXT, " ");

      // Reset tracking
      g_entryPx  = 0;
      g_origSL   = 0;
      g_currentSL = 0;
      g_riskDist  = 0;
   }

   // ── Update chart SL lines ──
   UpdateChartLines();

   ChartRedraw();
}

// ════════════════════════════════════════════════════════════════════
// TRADING
// ════════════════════════════════════════════════════════════════════
bool ExecuteTrade(bool isBuy)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double entry = isBuy ? ask : bid;
   double sl    = CalcSLPrice(isBuy);
   double dist  = MathAbs(entry - sl);
   double lot   = CalcLot(dist);

   // Validate SL
   if(isBuy  && sl >= bid) { Print("[PANEL] Skip: buy SL >= bid");  return false; }
   if(!isBuy && sl <= ask) { Print("[PANEL] Skip: sell SL <= ask"); return false; }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price     = entry;
   req.sl        = sl;
   req.tp        = 0;
   req.magic     = InpMagic;
   req.deviation = InpDeviation;
   req.comment   = "Bot";

   if(OrderSend(req, res))
   {
      g_hasPos    = true;
      g_isBuy     = isBuy;
      g_entryPx   = entry;
      g_origSL    = sl;
      g_currentSL = sl;
      g_riskDist  = dist;

      Print(StringFormat("[PANEL] %s %.2f lot @ %s  SL=%s  Risk=$%.2f",
         isBuy ? "BUY" : "SELL", lot,
         DoubleToString(entry, _Digits),
         DoubleToString(sl, _Digits),
         g_riskMoney));
      return true;
   }
   else
   {
      Print(StringFormat("[PANEL] OrderSend FAILED  rc=%d  %s",
         res.retcode, res.comment));
      return false;
   }
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)        != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);

      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = _Symbol;
      req.position  = t;
      req.volume    = PositionGetDouble(POSITION_VOLUME);
      req.type      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                        ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price     = (req.type == ORDER_TYPE_BUY)
                        ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      req.deviation = InpDeviation;
      req.magic     = InpMagic;

      if(OrderSend(req, res))
         Print("[PANEL] Closed #", t);
      else
         Print("[PANEL] Close FAILED #", t, " rc=", res.retcode);
   }

   g_hasPos    = false;
   g_entryPx   = 0;
   g_origSL    = 0;
   g_currentSL = 0;
   g_riskDist  = 0;
}

// ════════════════════════════════════════════════════════════════════
// TRAILING STOP
// ════════════════════════════════════════════════════════════════════
void ModifySL(double newSL)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)        != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;

      MqlTradeRequest rq;
      MqlTradeResult  rs;
      ZeroMemory(rq);
      ZeroMemory(rs);

      rq.action   = TRADE_ACTION_SLTP;
      rq.symbol   = _Symbol;
      rq.position = t;
      rq.sl       = newSL;
      rq.tp       = PositionGetDouble(POSITION_TP);

      if(OrderSend(rq, rs))
      {
         g_currentSL = newSL;
         Print("[TRAIL] SL -> ", DoubleToString(newSL, _Digits));
      }
      else
         Print("[TRAIL] Modify FAILED rc=", rs.retcode);
   }
}

// Candle-based trail: advance SL to low/high of last same-color bar
void TrailCandle()
{
   if(!g_hasPos) return;

   // Only on new bar (checked before g_lastBar is updated in OnTick)
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == g_lastBar) return;

   double o1 = iOpen (_Symbol, _Period, 1);
   double c1 = iClose(_Symbol, _Period, 1);

   bool bullish = (c1 > o1);
   bool bearish = (c1 < o1);

   // Only trail when bar[1] is same direction as trade
   if(g_isBuy  && !bullish) return;
   if(!g_isBuy && !bearish) return;

   double newSL = g_isBuy ? NormPrice(iLow (_Symbol, _Period, 1))
                          : NormPrice(iHigh(_Symbol, _Period, 1));

   // Only advance, never retreat
   bool advance = g_isBuy ? (newSL > g_currentSL)
                           : (newSL < g_currentSL);
   if(!advance) return;

   // Safety: SL must stay off-side of current price
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(g_isBuy  && newSL >= bid) return;
   if(!g_isBuy && newSL <= ask) return;

   ModifySL(newSL);
}

// R-based trail: step SL up in increments of R
void TrailRBased()
{
   if(!g_hasPos || g_riskDist <= 0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double cur = g_isBuy ? bid : ask;

   double moveFromEntry = g_isBuy ? (cur - g_entryPx)
                                  : (g_entryPx - cur);
   double moveR = moveFromEntry / g_riskDist;

   if(moveR < InpTrailStartR) return;   // not started yet

   int    fullSteps  = (int)MathFloor((moveR - InpTrailStartR) / InpTrailStepR);
   double trailAmt   = fullSteps * InpTrailStepR * g_riskDist;
   double newSL      = g_isBuy ? NormPrice(g_entryPx + trailAmt)
                                : NormPrice(g_entryPx - trailAmt);

   bool advance = g_isBuy ? (newSL > g_currentSL)
                           : (newSL < g_currentSL);
   if(!advance) return;

   if(g_isBuy  && newSL >= bid) return;
   if(!g_isBuy && newSL <= ask) return;

   ModifySL(newSL);
}

void ManageTrail()
{
   if(!g_hasPos) return;
   switch(InpTrailMode)
   {
      case TRAIL_CANDLE: TrailCandle(); break;
      case TRAIL_R:      TrailRBased(); break;
      case TRAIL_NONE:   break;
   }
}

// ════════════════════════════════════════════════════════════════════
// AUTO CANDLE COUNTER – 3 same-color candles → auto entry
// ════════════════════════════════════════════════════════════════════
// Returns +1 (3 green = BUY signal), -1 (3 red = SELL signal), 0 (none)
// Conditions:
//   BUY:  3 consecutive bullish bars, each bar's low > previous bar's low (strictly higher lows)
//   SELL: 3 consecutive bearish bars, each bar's high < previous bar's high (strictly lower highs)
int DetectThreeCandles()
{
   bool allGreen = true;
   bool allRed   = true;

   for(int i = 1; i <= 3; i++)
   {
      double o = iOpen (_Symbol, _Period, i);
      double c = iClose(_Symbol, _Period, i);
      if(c <= o) allGreen = false;
      if(c >= o) allRed   = false;
   }

   if(!allGreen && !allRed) return 0;

   // Validate trend structure: higher lows (buy) or lower highs (sell)
   if(allGreen)
   {
      // For bullish: each bar's low must be strictly > the previous bar's low
      // Bars: 1 (newest), 2, 3 (oldest) => check bar 2 low > bar 3 low, bar 1 low > bar 2 low
      for(int i = 1; i <= 2; i++)
      {
         double curLow  = iLow(_Symbol, _Period, i);
         double prevLow = iLow(_Symbol, _Period, i + 1);
         if(curLow <= prevLow)
            return 0;   // wick not strictly higher -> not clean trend
      }
      return 1;
   }
   else // allRed
   {
      // For bearish: each bar's high must be strictly < the previous bar's high
      for(int i = 1; i <= 2; i++)
      {
         double curHigh  = iHigh(_Symbol, _Period, i);
         double prevHigh = iHigh(_Symbol, _Period, i + 1);
         if(curHigh >= prevHigh)
            return 0;   // wick not strictly lower -> not clean trend
      }
      return -1;
   }
}

void CheckAutoEntry()
{
   if(!g_autoMode) return;
   if(g_hasPos) return;     // already in position

   // Only on new bar
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == g_lastBar) return;

   int sig = DetectThreeCandles();
   if(sig == 0) return;

   bool isBuy = (sig == 1);
   Print(StringFormat("[AUTO] 3-candle signal: %s", isBuy ? "BUY" : "SELL"));
   ExecuteTrade(isBuy);
}

// ════════════════════════════════════════════════════════════════════
// SYNC – Recover state if EA restarted with open position
// ════════════════════════════════════════════════════════════════════
void SyncPositionState()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)        != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;

      g_hasPos    = true;
      g_isBuy     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      g_entryPx   = PositionGetDouble(POSITION_PRICE_OPEN);
      g_currentSL = PositionGetDouble(POSITION_SL);
      g_origSL    = g_currentSL;                    // best approximation
      g_riskDist  = MathAbs(g_entryPx - g_currentSL);

      Print(StringFormat("[PANEL] Synced position: %s @ %s  SL=%s",
         g_isBuy ? "BUY" : "SELL",
         DoubleToString(g_entryPx, _Digits),
         DoubleToString(g_currentSL, _Digits)));
      break;
   }
}

// Lightweight re-sync if we detect position but lost tracking vars
void SyncIfNeeded()
{
   if(g_entryPx > 0) return;   // already synced
   SyncPositionState();
}

// ════════════════════════════════════════════════════════════════════
// DARK CHART THEME
// ════════════════════════════════════════════════════════════════════
void ApplyThemeCommon()
{
   long id = ChartID();
   ChartSetInteger(id, CHART_MODE,           CHART_CANDLES);
   ChartSetInteger(id, CHART_SHOW_VOLUMES,   false);
   ChartSetInteger(id, CHART_SHOW_BID_LINE,  true);
   ChartSetInteger(id, CHART_SHOW_ASK_LINE,  true);
   ChartSetInteger(id, CHART_SHIFT,          true);
   ChartSetDouble (id, CHART_SHIFT_SIZE,     15.0);
}

void HighlightActiveTheme()
{
   string names[] = {OBJ_THEME_DARK, OBJ_THEME_LIGHT, OBJ_THEME_ZEN};
   for(int i = 0; i < 3; i++)
   {
      bool sel = (i == g_theme);
      ObjectSetInteger(0, names[i], OBJPROP_STATE,        false);
      ObjectSetInteger(0, names[i], OBJPROP_BGCOLOR,      sel ? C'0,100,60' : C'40,40,55');
      ObjectSetInteger(0, names[i], OBJPROP_BORDER_COLOR, sel ? C'0,100,60' : C'40,40,55');
      ObjectSetInteger(0, names[i], OBJPROP_COLOR,        sel ? COL_WHITE : COL_BTN_TXT);
   }
}

void ApplyDarkTheme()
{
   long id = ChartID();
   g_theme = 0;
   ChartSetInteger(id, CHART_COLOR_BACKGROUND,  C'19,23,34');    // #131722 TradingView bg
   ChartSetInteger(id, CHART_COLOR_FOREGROUND,  C'200,200,210');
   ChartSetInteger(id, CHART_COLOR_CHART_UP,    C'38,166,154');   // #26a69a
   ChartSetInteger(id, CHART_COLOR_CHART_DOWN,  C'239,83,80');    // #ef5350
   ChartSetInteger(id, CHART_COLOR_CANDLE_BULL, C'38,166,154');
   ChartSetInteger(id, CHART_COLOR_CANDLE_BEAR, C'239,83,80');
   ChartSetInteger(id, CHART_COLOR_CHART_LINE,  C'200,200,210');
   ChartSetInteger(id, CHART_COLOR_GRID,        C'30,34,45');
   ChartSetInteger(id, CHART_COLOR_VOLUME,      C'60,63,80');
   ChartSetInteger(id, CHART_COLOR_BID,         C'33,150,243');
   ChartSetInteger(id, CHART_COLOR_ASK,         C'255,152,0');
   ChartSetInteger(id, CHART_COLOR_LAST,        C'200,200,210');
   ChartSetInteger(id, CHART_COLOR_STOP_LEVEL,  C'255,50,50');
   ChartSetInteger(id, CHART_SHOW_GRID,         false);
   ApplyThemeCommon();
   HighlightActiveTheme();
   ChartRedraw(id);
   Print("[PANEL] Dark theme applied");
}

void ApplyLightTheme()
{
   long id = ChartID();
   g_theme = 1;
   ChartSetInteger(id, CHART_COLOR_BACKGROUND,  C'255,255,255'); // white
   ChartSetInteger(id, CHART_COLOR_FOREGROUND,  C'60,60,60');
   ChartSetInteger(id, CHART_COLOR_CHART_UP,    C'8,153,129');    // #089981
   ChartSetInteger(id, CHART_COLOR_CHART_DOWN,  C'242,54,69');    // #F23645
   ChartSetInteger(id, CHART_COLOR_CANDLE_BULL, C'8,153,129');
   ChartSetInteger(id, CHART_COLOR_CANDLE_BEAR, C'242,54,69');
   ChartSetInteger(id, CHART_COLOR_CHART_LINE,  C'60,60,60');
   ChartSetInteger(id, CHART_COLOR_GRID,        C'230,230,230');
   ChartSetInteger(id, CHART_COLOR_VOLUME,      C'180,180,180');
   ChartSetInteger(id, CHART_COLOR_BID,         C'33,150,243');
   ChartSetInteger(id, CHART_COLOR_ASK,         C'255,152,0');
   ChartSetInteger(id, CHART_COLOR_LAST,        C'60,60,60');
   ChartSetInteger(id, CHART_COLOR_STOP_LEVEL,  C'255,50,50');
   ChartSetInteger(id, CHART_SHOW_GRID,         true);
   ApplyThemeCommon();
   HighlightActiveTheme();
   ChartRedraw(id);
   Print("[PANEL] Light theme applied");
}

void ApplyZenTheme()
{
   long id = ChartID();
   g_theme = 2;
   // Monochrome: removes red/green emotional bias, easy on eyes for long sessions
   ChartSetInteger(id, CHART_COLOR_BACKGROUND,  C'0,0,0');        // pure black
   ChartSetInteger(id, CHART_COLOR_FOREGROUND,  C'200,200,200');
   ChartSetInteger(id, CHART_COLOR_CHART_UP,    C'255,255,255');   // white border up
   ChartSetInteger(id, CHART_COLOR_CHART_DOWN,  C'93,96,107');     // #5d606b grey border down
   ChartSetInteger(id, CHART_COLOR_CANDLE_BULL, C'255,255,255');   // white fill up
   ChartSetInteger(id, CHART_COLOR_CANDLE_BEAR, C'93,96,107');     // grey fill down
   ChartSetInteger(id, CHART_COLOR_CHART_LINE,  C'200,200,200');
   ChartSetInteger(id, CHART_COLOR_GRID,        C'18,18,22');
   ChartSetInteger(id, CHART_COLOR_VOLUME,      C'50,50,55');
   ChartSetInteger(id, CHART_COLOR_BID,         C'93,127,160');    // muted steel blue
   ChartSetInteger(id, CHART_COLOR_ASK,         C'160,135,96');    // muted amber
   ChartSetInteger(id, CHART_COLOR_LAST,        C'200,200,200');
   ChartSetInteger(id, CHART_COLOR_STOP_LEVEL,  C'180,60,60');
   ChartSetInteger(id, CHART_SHOW_GRID,         false);
   ApplyThemeCommon();
   HighlightActiveTheme();
   ChartRedraw(id);
   Print("[PANEL] Zen theme applied");
}

// ════════════════════════════════════════════════════════════════════
// EVENT HANDLERS
// ════════════════════════════════════════════════════════════════════
int OnInit()
{
   // ATR handle
   g_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
      Print("[PANEL] Warning: iATR handle failed");

   g_riskMoney = InpDefaultRisk;
   g_atrMult   = InpATRMult;

   // Recover if EA restarted with open position
   SyncPositionState();

   // Theme
   ApplyDarkTheme();

   // Build panel
   CreatePanel();
   UpdatePanel();

   // Timer for updates when market is slow
   EventSetMillisecondTimer(1000);

   Print(StringFormat("[PANEL] Tuan Quick Trade v1.00 | %s | Risk=$%.2f | SL=%s | Trail=%s",
      _Symbol,
      InpDefaultRisk,
      EnumToString(InpSLMode),
      EnumToString(InpTrailMode)));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DestroyPanel();
   EventKillTimer();

   if(g_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
   }
}

void OnTick()
{
   // Detect position closed externally (SL hit, etc.)
   if(g_hasPos && !HasOwnPosition())
   {
      g_hasPos    = false;
      g_entryPx   = 0;
      g_origSL    = 0;
      g_currentSL = 0;
      g_riskDist  = 0;
   }

   // Auto trailing
   ManageTrail();

   // Auto Candle Counter (before bar tracking update)
   CheckAutoEntry();

   // Track bar changes (AFTER trail + auto, so candle logic works on 1st tick)
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar != g_lastBar)
      g_lastBar = curBar;

   // Throttled panel update (every 500 ms)
   static uint lastMs = 0;
   uint now = GetTickCount();
   if(now - lastMs >= 500)
   {
      UpdatePanel();
      lastMs = now;
   }
}

void OnTimer()
{
   UpdatePanel();
}

void OnChartEvent(const int id,
                  const long   &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // ── BUY ──
      if(sparam == OBJ_BUY_BTN)
      {
         ObjectSetInteger(0, OBJ_BUY_BTN, OBJPROP_STATE, false);
         if(!g_hasPos)
            ExecuteTrade(true);
         else
            Print("[PANEL] Already in position – close first");
      }
      // ── SELL ──
      else if(sparam == OBJ_SELL_BTN)
      {
         ObjectSetInteger(0, OBJ_SELL_BTN, OBJPROP_STATE, false);
         if(!g_hasPos)
            ExecuteTrade(false);
         else
            Print("[PANEL] Already in position – close first");
      }
      // ── CLOSE ALL ──
      else if(sparam == OBJ_CLOSE_BTN)
      {
         ObjectSetInteger(0, OBJ_CLOSE_BTN, OBJPROP_STATE, false);
         CloseAllPositions();
      }
      // ── AUTO toggle ──
      else if(sparam == OBJ_AUTO_BTN)
      {
         g_autoMode = !g_autoMode;
         ObjectSetInteger(0, OBJ_AUTO_BTN, OBJPROP_STATE, false);
         if(g_autoMode)
         {
            ObjectSetString (0, OBJ_AUTO_BTN, OBJPROP_TEXT, "Candle Counter 3: ON");
            ObjectSetInteger(0, OBJ_AUTO_BTN, OBJPROP_BGCOLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_AUTO_BTN, OBJPROP_BORDER_COLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_AUTO_BTN, OBJPROP_COLOR, COL_WHITE);
            Print("[AUTO] Candle Counter auto-trade ENABLED");
         }
         else
         {
            ObjectSetString (0, OBJ_AUTO_BTN, OBJPROP_TEXT, "Candle Counter 3: OFF");
            ObjectSetInteger(0, OBJ_AUTO_BTN, OBJPROP_BGCOLOR, COL_BTN);
            ObjectSetInteger(0, OBJ_AUTO_BTN, OBJPROP_BORDER_COLOR, COL_BTN);
            ObjectSetInteger(0, OBJ_AUTO_BTN, OBJPROP_COLOR, COL_BTN_TXT);
            Print("[AUTO] Candle Counter auto-trade DISABLED");
         }
      }
      // ── Theme buttons ──
      else if(sparam == OBJ_THEME_DARK || sparam == OBJ_THEME_LIGHT ||
              sparam == OBJ_THEME_ZEN)
      {
         if(sparam == OBJ_THEME_DARK)  ApplyDarkTheme();
         if(sparam == OBJ_THEME_LIGHT) ApplyLightTheme();
         if(sparam == OBJ_THEME_ZEN)   ApplyZenTheme();
      }

      ChartRedraw();
      UpdatePanel();
   }
   // ── Risk edit changed ──
   else if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == OBJ_RISK_EDT)
      {
         string val = ObjectGetString(0, OBJ_RISK_EDT, OBJPROP_TEXT);
         g_riskMoney = StringToDouble(val);
         if(g_riskMoney <= 0)
         {
            g_riskMoney = InpDefaultRisk;
            ObjectSetString(0, OBJ_RISK_EDT, OBJPROP_TEXT,
               IntegerToString((int)InpDefaultRisk));
         }
         else
         {
            ObjectSetString(0, OBJ_RISK_EDT, OBJPROP_TEXT,
               IntegerToString((int)g_riskMoney));
         }
         UpdatePanel();
      }
   }
}
//+------------------------------------------------------------------+
