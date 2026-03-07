//+------------------------------------------------------------------+
//| Expert Trading Panel.mq5                                         |
//| Tuan Quick Trade – Bot Management + Quick Buy/Sell               |
//|                                                                  |
//| Features:                                                        |
//|  • Risk $ input → auto-calculated lot size                       |
//|  • Auto SL: ATR / Last-N-bars / Fixed pips                       |
//|  • One-click BUY / SELL                                          |
//|  • Auto TP: 50% partial close at 0.5 or 1 ATR                    |
//|  • Grid DCA: auto DCA with ATR × mult spacing                    |
//|  • Dark/Light chart themes                                      |
//|  • Integrated bots: Candle Count Bot, News Straddle Bot (.mqh)             |
//|                                                                  |
//| Usage:                                                           |
//|  1. Attach EA to chart                                           |
//|  2. Set Risk $ in panel (max loss per trade)                     |
//|  3. Click BUY or SELL → order fires instantly                    |
//|  4. Trailing SL manages the trade automatically                  |
//+------------------------------------------------------------------+
#property copyright "Tuan v2.32"
#property version   "2.31"
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
   TRAIL_CLOSE     = 1,  // Close (bar[1] wick)
   TRAIL_SWING     = 2,  // Swing (swing low/high)
   TRAIL_BE_CLOSE  = 3,  // BE → then Close
   TRAIL_BE        = 4,  // BE only (step ATR)
   TRAIL_NONE      = 5,  // No trail
   TRAIL_BE_SWING  = 6,  // BE → then Swing
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
input ENUM_TRAIL_MODE InpTrailMode      = TRAIL_CLOSE; // Trail Mode (default)
input int             InpTrailLookback  = 5;          // Swing lookback bars (Swing mode)

input group           "══ Grid DCA ══"
input int             InpGridMaxLevel   = 3;          // Grid DCA max levels (2-5)

input group           "══ General ══"
input ulong           InpMagic          = 99999;     // Magic Number
input ulong           InpManageMagic    = 0;         // Manage Magic (0 = same as Magic)
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
#define COL_BUY       C'8,153,129'
#define COL_BUY_HI    C'0,180,150'
#define COL_SELL      C'220,50,47'
#define COL_SELL_HI   C'245,65,60'
#define COL_BTN       C'55,55,72'
#define COL_BTN_TXT   C'200,200,220'
#define COL_CLOSE     C'140,35,35'
#define COL_WHITE     C'255,255,255'

// Colors – Disabled/Placeholder
#define COL_DIS_BG    C'38,38,50'
#define COL_DIS_TXT   C'97,97,120'

// Colors – Status
#define COL_PROFIT    C'0,180,100'
#define COL_LOSS      C'230,60,60'
#define COL_LOCK_UP   C'0,130,75'
#define COL_LOCK_DN   C'170,55,55'

// Object names
#define OBJ_BG         PREFIX "bg"
#define OBJ_TITLE_BG   PREFIX "title_bg"
#define OBJ_TITLE      PREFIX "title"
#define OBJ_TITLE_INFO PREFIX "title_info"
#define OBJ_TITLE_LOCK PREFIX "title_lock"
#define OBJ_RISK_LBL   PREFIX "risk_lbl"
#define OBJ_RISK_EDT   PREFIX "risk_edt"
#define OBJ_SPRD_LBL   PREFIX "sprd_lbl"
#define OBJ_STATUS_LBL PREFIX "status_lbl"
#define OBJ_LOCK_LBL   PREFIX "lock_lbl"
#define OBJ_LOCK_VAL   PREFIX "lock_val"
#define OBJ_BUY_BTN    PREFIX "buy_btn"
#define OBJ_SELL_BTN   PREFIX "sell_btn"
#define OBJ_CLOSE_BTN  PREFIX "close_btn"


#define OBJ_SEP1       PREFIX "sep1"
#define OBJ_SEP2       PREFIX "sep2"
#define OBJ_SEP3       PREFIX "sep3"
#define OBJ_SEP5       PREFIX "sep5"
#define OBJ_SEC_INFO   PREFIX "sec_info"
#define OBJ_SEC_TRADE  PREFIX "sec_trade"
#define OBJ_SEC_ORDER  PREFIX "sec_order"
// ORDER MANAGEMENT buttons
#define OBJ_TM_CLOSE   PREFIX "tm_close"
#define OBJ_TM_SWING   PREFIX "tm_swing"
#define OBJ_TM_BE      PREFIX "tm_be"
#define OBJ_TRAIL_LBL  PREFIX "trail_lbl"   // Trail param label
#define OBJ_TRAIL_VAL  PREFIX "trail_val"   // Trail param value display
#define OBJ_TRAIL_PLUS PREFIX "trail_plus"  // Trail param +
#define OBJ_TRAIL_MINUS PREFIX "trail_minus" // Trail param -
#define OBJ_GRID_BTN   PREFIX "grid_btn"
#define OBJ_GRID_LVL   PREFIX "grid_lvl"
#define OBJ_GRID_DLY   PREFIX "grid_dly"
#define OBJ_AUTOTP_BTN PREFIX "autotp_btn"
#define OBJ_TP_05      PREFIX "tp_05"        // TP1 at 0.5 ATR
#define OBJ_TP_10      PREFIX "tp_10"        // TP1 at 1.0 ATR

// Chart lines (SL levels)
#define OBJ_SL_BUY_LINE   PREFIX "sl_buy_line"
#define OBJ_SL_SELL_LINE  PREFIX "sl_sell_line"
#define OBJ_SL_ACTIVE     PREFIX "sl_active"
#define OBJ_ENTRY_LINE    PREFIX "entry_line"


// Chart lines (Auto TP / Grid DCA / Trail Start)
#define OBJ_TP1_LINE      PREFIX "tp1_line"
#define OBJ_TRAIL_START   PREFIX "trail_start"
#define OBJ_AVG_ENTRY     PREFIX "avg_entry"
#define OBJ_DCA1_LINE     PREFIX "dca1_line"
#define OBJ_DCA2_LINE     PREFIX "dca2_line"
#define OBJ_DCA3_LINE     PREFIX "dca3_line"
#define OBJ_DCA4_LINE     PREFIX "dca4_line"
#define OBJ_DCA5_LINE     PREFIX "dca5_line"
#define OBJ_GRID_INFO     PREFIX "grid_info"


// Theme toggle button
#define OBJ_THEME_BTN     PREFIX "theme_btn"

// Collapse button
#define OBJ_COLLAPSE_BTN  PREFIX "collapse_btn"
#define OBJ_LINES_BTN     PREFIX "lines_btn"
#define OBJ_CLOSE50_BTN   PREFIX "close50_btn"
#define OBJ_CLOSE75_BTN   PREFIX "close75_btn"

// Settings panel
#define OBJ_SETTINGS_BTN  PREFIX "settings_btn"
#define OBJ_SET_SEP       PREFIX "set_sep"
#define OBJ_SET_SEC       PREFIX "set_sec"

// Bot toggle buttons (right side of panel)
#define OBJ_BOT_BG        PREFIX "bot_bg"
#define OBJ_BOT_CC_BTN    PREFIX "bot_cc"
#define OBJ_BOT_NS_BTN    PREFIX "bot_ns"
#define OBJ_BOT_SR_BTN    PREFIX "bot_sr"
#define OBJ_BOT_START_BTN PREFIX "bot_start"  // Start/Stop inside bot panel
#define OBJ_BOT_AUTO_BTN  PREFIX "bot_auto"   // Auto‐Regime toggle

// Bot panel layout constants
#define BOT_PANEL_X       (PX + PW + 5)
#define BOT_PANEL_Y       PY
#define BOT_BTN_W         80
#define BOT_BTN_H         24
#define BOT_CONTENT_W     400
#define BOT_CONTENT_Y     (PY + BOT_BTN_H + 4)
#define OBJ_SET_RISK_LBL  PREFIX "set_risk_lbl"
#define OBJ_SET_RISK_EDT  PREFIX "set_risk_edt"
#define OBJ_SET_RISK_PLUS PREFIX "set_rplus"
#define OBJ_SET_RISK_MINUS PREFIX "set_rminus"
#define OBJ_SET_MODE_DOLLAR PREFIX "set_mode_d"
#define OBJ_SET_PCT_EDT   PREFIX "set_pct_edt"
#define OBJ_SET_PCT_PLUS  PREFIX "set_pplus"
#define OBJ_SET_PCT_MINUS PREFIX "set_pminus"
#define OBJ_SET_MODE_PCT  PREFIX "set_mode_p"
#define OBJ_SET_ATR_LBL   PREFIX "set_atr_lbl"
#define OBJ_SET_ATR_EDT   PREFIX "set_atr_edt"
#define OBJ_SET_ATR_PLUS  PREFIX "set_aplus"
#define OBJ_SET_ATR_MINUS PREFIX "set_aminus"
#define OBJ_SET_A05       PREFIX "set_a05"
#define OBJ_SET_A10       PREFIX "set_a10"
#define OBJ_SET_A15       PREFIX "set_a15"
#define OBJ_SET_A20       PREFIX "set_a20"
#define OBJ_SET_A25       PREFIX "set_a25"
#define OBJ_SET_A30       PREFIX "set_a30"

// ════════════════════════════════════════════════════════════════════
// GLOBALS
// ════════════════════════════════════════════════════════════════════
int      g_atrHandle  = INVALID_HANDLE;
double   g_riskMoney  = 0;
double   g_riskPct    = 1.0;     // Risk % of balance
bool     g_riskPctMode = true;   // true=%Auto, false=$Fixed

// Position tracking
bool     g_hasPos     = false;
bool     g_isBuy      = false;
double   g_entryPx    = 0;
double   g_origSL     = 0;
double   g_currentSL  = 0;
double   g_riskDist   = 0;        // |entry − origSL| actual SL distance
double   g_tpDist     = 0;        // TP distance = factor × ATR (0.5 or 1.0)
datetime g_lastBar    = 0;

int      g_theme      = 0;       // 0=Dark, 1=Light

// Live ATR multiplier (changeable from panel)
double   g_atrMult    = 0;
double   g_cachedATR  = 0;        // ATR cached per bar (refreshed on new bar)
bool     g_trailEnabled = false;
ENUM_TRAIL_MODE g_trailRef = TRAIL_CLOSE;  // Runtime trail method (Close/Swing/None)
bool     g_beEnabled      = false;   // BE modifier toggle (combinable with Close/Swing)
double   g_beStartMult    = 1.0;   // BE mode: start breakeven when profit >= N × ATR input (0.1-3.0)
double   g_trailMinDist   = 0.5;   // Close/Swing mode: min SL distance as factor of ATR input (0.1-3.0)
bool     g_beReached    = false;   // BE trail: whether SL has been moved to breakeven
int      g_beStepLevel  = 0;       // BE trail Phase 2: step level (0=BE, 1=+1ATR, 2=+2ATR...)
bool     g_panelCollapsed = false;
bool     g_linesHidden    = false;
bool     g_settingsExpanded = true;
int      g_panelFullHeight = 460;
ENUM_SL_MODE g_slMode = SL_ATR;
ulong    g_manageMagic  = 0;        // Effective magic for position monitoring

// Auto TP (Partial Take Profit) state
bool     g_autoTPEnabled  = false;
bool     g_tp1Hit         = false;    // TP1 (50% @ g_tpATRFactor ATR) taken
double   g_tpATRFactor    = 1.0;     // TP1 distance factor: 0.5 or 1.0 ATR

// Grid DCA state
bool     g_gridEnabled    = false;
bool     g_gridUserEnabled = false;  // User's intended state (before trail override)
int      g_gridLevel      = 0;       // 0=initial only, 1-3=DCA additions
int      g_gridMaxLevel   = 3;       // max DCA positions — runtime changeable
double   g_gridBaseATR    = 0;       // ATR value when grid started (base for ATR × mult spacing)
int      g_gridDelay      = 5;       // Delay between DCA fills (minutes), 0=disabled
datetime g_lastDCATime    = 0;       // Timestamp of last DCA fill

// Bot integration state
double   g_panelLot       = 0;       // Calculated lot — shared with bots
int      g_activeBot      = 0;       // 0=none, 1=Candle Count Bot, 2=News Straddle, 3=SR Retest

// Regime Analyzer (Python → INI → MQL5)
bool     g_autoRegime     = false;   // Auto‐regime mode ON/OFF
string   g_regimeName     = "";      // e.g. "trending_strong"
double   g_regimeConf     = 0;       // confidence 0..1
datetime g_lastConfigRead = 0;       // last time config was read
long     g_lastConfigMod  = 0;       // file modification time

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

   switch(g_slMode)
   {
      case SL_ATR:
      {
         // Use locked grid ATR if available, fallback to live values
         double atrVal = (g_gridBaseATR > 0) ? g_gridBaseATR : g_cachedATR;
         double mult   = g_atrMult;
         if(atrVal > 0)
         {
            double dist = atrVal * mult;
            // When Grid DCA is ON, all intervals equal: spacing = ATR × mult
            // SL = spacing × (maxLevel + 1) = ATR × mult × (maxLevel + 1)
            if(g_gridEnabled)
               dist = atrVal * mult * (g_gridMaxLevel + 1);
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

// Calculate the minimum risk ($) needed to trade min lot at current ATR SL
double CalcMinRisk()
{
   if(g_cachedATR <= 0) return 1;
   double slDist  = g_cachedATR * g_atrMult;
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSz <= 0 || tickVal <= 0) return 1;
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   return MathCeil(minLot * (slDist / tickSz) * tickVal);  // round up to nearest $1
}

// Calculate the risk $ needed for a specific lot size at current ATR SL
double CalcRiskForLot(double targetLot)
{
   if(g_cachedATR <= 0 || targetLot <= 0) return 1;
   double slDist  = g_cachedATR * g_atrMult;
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSz <= 0 || tickVal <= 0) return 1;
   return MathCeil(targetLot * (slDist / tickSz) * tickVal);
}

// Calculate TRUE projected max risk for Grid DCA (accounts for min-lot clipping)
// Simulates initial entry + all DCA levels, sums actual risk per position
double CalcProjectedMaxRisk()
{
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSz <= 0 || tickVal <= 0)
      return g_riskMoney * (g_gridMaxLevel + 1);  // fallback

   if(g_cachedATR <= 0)
      return g_riskMoney * (g_gridMaxLevel + 1);  // fallback

   double atrVal = (g_gridBaseATR > 0) ? g_gridBaseATR : g_cachedATR;
   double spacing = atrVal * g_atrMult;  // Grid spacing = ATR × mult
   double fullSLDist = spacing * (g_gridMaxLevel + 1);
   if(InpSLBuffer > 0) fullSLDist *= (1.0 + InpSLBuffer / 100.0);

   double totalRisk = 0;

   // ── Part 1: REAL risk from already-open positions ──
   int nOpen = 0;
   if(g_hasPos)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(!PositionSelectByTicket(t)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != g_manageMagic) continue;
         double posLot = PositionGetDouble(POSITION_VOLUME);
         double posSL  = PositionGetDouble(POSITION_SL);
         double posEntry = PositionGetDouble(POSITION_PRICE_OPEN);
         if(posSL > 0)
            totalRisk += posLot * (MathAbs(posEntry - posSL) / tickSz) * tickVal;
         nOpen++;
      }
   }

   // ── Part 2: SIMULATED risk for remaining un-filled DCA levels ──
   int filledLevels = MathMax(0, nOpen - 1);  // entry doesn't count as DCA
   for(int i = filledLevels + 1; i <= g_gridMaxLevel; i++)
   {
      // Distance from DCA #i entry to SL (buffer already in fullSLDist)
      double distToSL = fullSLDist - i * spacing;
      if(distToSL <= 0) continue;

      double lot = CalcLot(distToSL);  // clips to min lot
      double risk = lot * (distToSL / tickSz) * tickVal;
      totalRisk += risk;
   }

   // ── Part 3: If no open positions, add simulated initial entry ──
   if(nOpen == 0)
   {
      double lot = CalcLot(fullSLDist);
      double risk = lot * (fullSLDist / tickSz) * tickVal;
      totalRisk += risk;
   }

   return totalRisk;
}

bool HasOwnPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)        == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)  == g_manageMagic)
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
      if((ulong)PositionGetInteger(POSITION_MAGIC)  != g_manageMagic) continue;
      pnl += PositionGetDouble(POSITION_PROFIT)
           + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

// Count positions matching our magic + symbol
int CountOwnPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_manageMagic) continue;
      count++;
   }
   return count;
}

// Volume-weighted average entry price
double GetAvgEntry()
{
   double sumLE = 0, sumL = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_manageMagic) continue;
      double lot = PositionGetDouble(POSITION_VOLUME);
      sumLE += lot * PositionGetDouble(POSITION_PRICE_OPEN);
      sumL  += lot;
   }
   return (sumL > 0) ? sumLE / sumL : 0;
}

// Locked profit at SL: what P&L would be if price reaches current SL
double GetLockedPnL()
{
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSz == 0 || tickVal == 0) return 0;

   double lockedPnL = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_manageMagic) continue;

      double lot   = PositionGetDouble(POSITION_VOLUME);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double swap  = PositionGetDouble(POSITION_SWAP);
      long   type  = PositionGetInteger(POSITION_TYPE);

      if(sl == 0) continue;  // no SL set → skip

      double dist = (type == POSITION_TYPE_BUY) ? (sl - entry) : (entry - sl);
      lockedPnL += lot * (dist / tickSz) * tickVal + swap;
   }
   return lockedPnL;
}

// Total lots across all positions
double GetTotalLots()
{
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_manageMagic) continue;
      total += PositionGetDouble(POSITION_VOLUME);
   }
   return total;
}

// Close X% of total position (most profitable position first)
bool PartialClosePercent(double pct)
{
   ulong   tickets[];
   double  lots[], profits[];
   int n = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_manageMagic) continue;

      ArrayResize(tickets, n + 1);
      ArrayResize(lots,    n + 1);
      ArrayResize(profits, n + 1);
      tickets[n] = t;
      lots[n]    = PositionGetDouble(POSITION_VOLUME);
      profits[n] = PositionGetDouble(POSITION_PROFIT)
                 + PositionGetDouble(POSITION_SWAP);
      n++;
   }
   if(n == 0) return false;

   double totalLots = 0;
   for(int i = 0; i < n; i++) totalLots += lots[i];

   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double closeLots = MathFloor(totalLots * pct / lotStep) * lotStep;
   if(closeLots < minLot) closeLots = minLot;
   if(closeLots >= totalLots) return false;  // can't close everything

   // Sort by profit descending (bubble sort)
   for(int i = 0; i < n - 1; i++)
      for(int j = 0; j < n - 1 - i; j++)
         if(profits[j] < profits[j + 1])
         {
            ulong  tt = tickets[j]; tickets[j] = tickets[j+1]; tickets[j+1] = tt;
            double tl = lots[j];    lots[j]    = lots[j+1];    lots[j+1]    = tl;
            double tp = profits[j]; profits[j] = profits[j+1]; profits[j+1] = tp;
         }

   double remaining = closeLots;
   bool anyClose = false;

   for(int i = 0; i < n && remaining >= minLot; i++)
   {
      if(!PositionSelectByTicket(tickets[i])) continue;
      double vol = MathMin(lots[i], remaining);
      vol = MathFloor(vol / lotStep) * lotStep;
      if(vol < minLot) continue;

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);

      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = _Symbol;
      req.position  = tickets[i];
      req.volume    = vol;
      req.type      = g_isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price     = g_isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                              : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      req.deviation = InpDeviation;
      req.magic     = InpMagic;

      if(OrderSend(req, res))
      {
         Print(StringFormat("[AUTO TP] Closed %.2f from #%d", vol, tickets[i]));
         remaining -= vol;
         anyClose = true;
      }
      else
         Print(StringFormat("[AUTO TP] Close FAIL rc=%d %s", res.retcode, res.comment));
   }
   return anyClose;
}

// Move SL to breakeven (avgEntry + spread buffer) for all positions
void MoveSLToBreakeven()
{
   double avgEntry = GetAvgEntry();
   if(avgEntry <= 0) return;

   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                 - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = spread + _Point;
   double beSL = g_isBuy ? NormPrice(avgEntry + buffer)
                         : NormPrice(avgEntry - buffer);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_manageMagic) continue;

      double curSL = PositionGetDouble(POSITION_SL);
      bool advance = g_isBuy ? (beSL > curSL) : (beSL < curSL);
      if(!advance) continue;

      // Safety: SL must stay behind current price
      if(g_isBuy  && beSL >= SymbolInfoDouble(_Symbol, SYMBOL_BID)) continue;
      if(!g_isBuy && beSL <= SymbolInfoDouble(_Symbol, SYMBOL_ASK)) continue;

      MqlTradeRequest rq;
      MqlTradeResult  rs;
      ZeroMemory(rq);
      ZeroMemory(rs);

      rq.action   = TRADE_ACTION_SLTP;
      rq.symbol   = _Symbol;
      rq.position = t;
      rq.sl       = beSL;
      rq.tp       = PositionGetDouble(POSITION_TP);

      if(OrderSend(rq, rs))
         Print(StringFormat("[AUTO TP] SL->BE %s for #%d",
               DoubleToString(beSL, _Digits), t));
      else
         Print(StringFormat("[AUTO TP] BE FAIL rc=%d", rs.retcode));
   }
   // Only update g_currentSL if BE is an advance (don't override Trail's higher SL)
   bool beAdvance = g_isBuy ? (beSL > g_currentSL) : (beSL < g_currentSL);
   if(beAdvance || g_currentSL == 0)
      g_currentSL = beSL;
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
   // Respect chart lines toggle
   if(g_linesHidden)
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
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
// CHART LINES – Auto TP & Grid DCA visualization
// ════════════════════════════════════════════════════════════════════
void UpdateTPGridLines()
{
   // ── Auto TP: TP1 line at factor × ATR from avgEntry ──
   if(g_autoTPEnabled && g_hasPos && g_tpDist > 0)
   {
      double avgEntry = GetAvgEntry();
      if(avgEntry > 0)
      {
         double tp1 = g_isBuy ? NormPrice(avgEntry + g_tpDist)
                              : NormPrice(avgEntry - g_tpDist);
         if(!g_tp1Hit)
            SetHLine(OBJ_TP1_LINE, tp1, C'0,200,83',
                     STYLE_DASH, 1,
                     StringFormat("TP1 (%.1fx%.1f) %." + IntegerToString(_Digits) + "f",
                                  g_tpATRFactor, g_atrMult, tp1));
         else
            HideHLine(OBJ_TP1_LINE);  // already taken
      }
   }
   else
      HideHLine(OBJ_TP1_LINE);

   // ── Trail Start: line showing where trail SL begins ──
   if(g_trailEnabled && g_hasPos && g_cachedATR > 0 && (g_trailRef != TRAIL_NONE || g_beEnabled))
   {
      double avgEntry = GetAvgEntry();
      if(avgEntry <= 0) avgEntry = g_entryPx;

      // Calculate trail start distance based on mode
      double trailStartDist = 0;
      string trailLbl = "";
      bool alreadyActive = false;

      if(g_beEnabled && !g_beReached)
      {
         // BE Phase 1: show BE trigger distance
         trailStartDist = g_beStartMult * g_cachedATR * g_atrMult;
         string methodLbl = (g_trailRef == TRAIL_CLOSE) ? "→Close" :
                            (g_trailRef == TRAIL_SWING) ? "→Swing" : "";
         trailLbl = StringFormat("Trail BE%s (%.1fx)", methodLbl, g_beStartMult);
         alreadyActive = false;
      }
      else if(g_trailRef == TRAIL_CLOSE || g_trailRef == TRAIL_SWING)
      {
         // Close/Swing: show profit gate distance (or already active if post-BE)
         if(g_beEnabled && g_beReached)
         {
            alreadyActive = true;  // post-BE: trail is live
         }
         else
         {
            trailStartDist = g_tpATRFactor * g_cachedATR * g_atrMult;
            string mName = (g_trailRef == TRAIL_CLOSE) ? "Close" : "Swing";
            trailLbl = StringFormat("Trail %s Start", mName);
            double cur = g_isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double move = g_isBuy ? (cur - avgEntry) : (avgEntry - cur);
            alreadyActive = (move >= trailStartDist);
         }
      }

      if(trailStartDist > 0 && !alreadyActive)
      {
         double trailPx = g_isBuy ? NormPrice(avgEntry + trailStartDist)
                                  : NormPrice(avgEntry - trailStartDist);
         SetHLine(OBJ_TRAIL_START, trailPx, C'255,165,0',
                  STYLE_DOT, 1,
                  StringFormat("%s %." + IntegerToString(_Digits) + "f",
                               trailLbl, trailPx));
      }
      else
         HideHLine(OBJ_TRAIL_START);
   }
   else
      HideHLine(OBJ_TRAIL_START);

   // ── Grid DCA: show pending DCA levels ──
   if(g_gridEnabled && g_hasPos && g_gridBaseATR > 0)
   {
      double spacing = g_gridBaseATR * g_atrMult;  // Grid spacing = ATR × mult
      string dcaNames[] = {OBJ_DCA1_LINE, OBJ_DCA2_LINE, OBJ_DCA3_LINE, OBJ_DCA4_LINE, OBJ_DCA5_LINE};

      for(int i = 0; i < g_gridMaxLevel; i++)
      {
         int level = i + 1;
         if(level <= g_gridLevel)
         {
            // Already filled — hide
            HideHLine(dcaNames[i]);
         }
         else
         {
            double dcaPx = g_isBuy
               ? NormPrice(g_entryPx - level * spacing)
               : NormPrice(g_entryPx + level * spacing);
            SetHLine(dcaNames[i], dcaPx, C'255,152,0',
                     STYLE_DOT, 1,
                     StringFormat("DCA #%d %." + IntegerToString(_Digits) + "f",
                                  level, dcaPx));
         }
      }

      // ── Average Entry line (when multiple positions) ──
      if(g_gridLevel > 0)
      {
         double avgEntry = GetAvgEntry();
         if(avgEntry > 0)
            SetHLine(OBJ_AVG_ENTRY, avgEntry, C'0,188,212',
                     STYLE_SOLID, 1,
                     StringFormat("Avg %." + IntegerToString(_Digits) + "f", avgEntry));
      }
      else
         HideHLine(OBJ_AVG_ENTRY);
   }
   else
   {
      HideHLine(OBJ_DCA1_LINE);
      HideHLine(OBJ_DCA2_LINE);
      HideHLine(OBJ_DCA3_LINE);
      HideHLine(OBJ_DCA4_LINE);
      HideHLine(OBJ_DCA5_LINE);
      HideHLine(OBJ_AVG_ENTRY);
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
   ObjectSetInteger(0, name, OBJPROP_ZORDER,        1);
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

//+------------------------------------------------------------------+
//| Toggle panel collapsed/expanded state                             |
//+------------------------------------------------------------------+
void TogglePanelCollapse()
{
   g_panelCollapsed = !g_panelCollapsed;
   
   // Update collapse button icon: ▲ when collapsed, ▼ when expanded
   ObjectSetString(0, OBJ_COLLAPSE_BTN, OBJPROP_TEXT,
                   g_panelCollapsed ? "\x25B2" : "\x25BC");
   
   long showFlag = g_panelCollapsed ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;
   
   // Hide/show panel UI objects only – chart lines (OBJ_HLINE) are NOT affected
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, PREFIX) != 0) continue;  // not our object
      
      // Keep title bar elements always visible
      if(name == OBJ_BG || name == OBJ_TITLE_BG || name == OBJ_TITLE ||
         name == OBJ_TITLE_INFO || name == OBJ_TITLE_LOCK ||
         name == OBJ_COLLAPSE_BTN || name == OBJ_LINES_BTN ||
         name == OBJ_SETTINGS_BTN ||
         name == OBJ_THEME_BTN)
         continue;
      
      // Skip chart lines – they have their own toggle
      ENUM_OBJECT otype = (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE);
      if(otype == OBJ_HLINE) continue;
      
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, showFlag);
   }
   
   // Resize background
   if(g_panelCollapsed)
      ObjectSetInteger(0, OBJ_BG, OBJPROP_YSIZE, 56);  // title bar + info row
   else
      ObjectSetInteger(0, OBJ_BG, OBJPROP_YSIZE, g_panelFullHeight);

   // Show/hide collapsed info row
   ObjectSetInteger(0, OBJ_TITLE_INFO, OBJPROP_TIMEFRAMES,
      g_panelCollapsed ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   ObjectSetInteger(0, OBJ_TITLE_LOCK, OBJPROP_TIMEFRAMES,
      g_panelCollapsed ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);

   // Hide/show bot buttons + bot panel when collapsing
   bool showBot = !g_panelCollapsed;
   ObjectSetInteger(0, OBJ_BOT_CC_BTN, OBJPROP_TIMEFRAMES, showBot ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   ObjectSetInteger(0, OBJ_BOT_NS_BTN, OBJPROP_TIMEFRAMES, showBot ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   ObjectSetInteger(0, OBJ_BOT_SR_BTN, OBJPROP_TIMEFRAMES, showBot ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   ObjectSetInteger(0, OBJ_BOT_BG, OBJPROP_TIMEFRAMES,
      (showBot && g_activeBot > 0) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   ObjectSetInteger(0, OBJ_BOT_START_BTN, OBJPROP_TIMEFRAMES,
      (showBot && g_activeBot > 0) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   if(g_activeBot == 1) CC_SetVisible(showBot);
   if(g_activeBot == 2) NS_SetVisible(showBot);
   if(g_activeBot == 3) SR_SetVisible(showBot);
   
   ChartRedraw();
}

void ToggleChartLines()
{
   g_linesHidden = !g_linesHidden;
   
   // Update button text: "Lines" when visible, strikethrough when hidden
   ObjectSetString(0, OBJ_LINES_BTN, OBJPROP_TEXT,
                   g_linesHidden ? "Lines" : "Lines");
   ObjectSetInteger(0, OBJ_LINES_BTN, OBJPROP_BGCOLOR,
                    g_linesHidden ? C'100,40,40' : C'40,40,55');
   ObjectSetInteger(0, OBJ_LINES_BTN, OBJPROP_BORDER_COLOR,
                    g_linesHidden ? C'100,40,40' : C'40,40,55');
   
   long showFlag = g_linesHidden ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;
   
   // Toggle only OBJ_HLINE objects that belong to our panel
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, PREFIX) != 0) continue;
      
      ENUM_OBJECT otype = (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE);
      if(otype == OBJ_HLINE)
         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, showFlag);
   }
   
   ChartRedraw();
}

void ToggleSettings()
{
   g_settingsExpanded = !g_settingsExpanded;
   // Rebuild panel (settings section changes layout)
   DestroyPanel();
   CreatePanel();
   UpdatePanel();
}

//+------------------------------------------------------------------+
//| Lightweight mode-button color update (no panel rebuild)          |
//+------------------------------------------------------------------+
void UpdateModeColors()
{
   // $ button: green if $Fixed mode, gray if %Auto
   color dBg  = g_riskPctMode ? C'50,50,70'    : C'0,100,60';
   color dTxt = g_riskPctMode ? C'140,140,160'  : C'255,255,255';
   ObjectSetInteger(0, OBJ_SET_MODE_DOLLAR, OBJPROP_BGCOLOR, dBg);
   ObjectSetInteger(0, OBJ_SET_MODE_DOLLAR, OBJPROP_COLOR,   dTxt);
   // % button: green if %Auto mode, gray if $Fixed
   color pBg  = g_riskPctMode ? C'0,100,60'    : C'50,50,70';
   color pTxt = g_riskPctMode ? C'255,255,255'  : C'140,140,160';
   ObjectSetInteger(0, OBJ_SET_MODE_PCT, OBJPROP_BGCOLOR, pBg);
   ObjectSetInteger(0, OBJ_SET_MODE_PCT, OBJPROP_COLOR,   pTxt);
}

// ════════════════════════════════════════════════════════════════════
// REGIME AUTO‐CONFIG (Python → INI → MQL5)
// ════════════════════════════════════════════════════════════════════
//  File: MQL5/Files/config_<SYMBOL>_<TF>.ini
//  Format: key=value (one per line), # comments
//  Keys: regime, confidence, atr_mult, atr_min_mult, break_mult, risk_pct
//
void ReadConfigINI()
{
   // Build filename:  config_XAUUSDm_M15.ini
   string tf = EnumToString(_Period);     // e.g. "PERIOD_M15"
   StringReplace(tf, "PERIOD_", "");      // → "M15"
   string fname = "config_" + _Symbol + "_" + tf + ".ini";

   // Check if file exists
   if(!FileIsExist(fname))
      return;

   // Check modification time to avoid re-reading unchanged file
   long modTime = (long)FileGetInteger(fname, FILE_MODIFY_DATE);
   if(modTime == g_lastConfigMod)
      return;   // file not changed since last read

   int handle = FileOpen(fname, FILE_READ | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      Print("[REGIME] Cannot open ", fname, " error=", GetLastError());
      return;
   }

   Print("[REGIME] Reading config: ", fname);
   int applied = 0;

   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringLen(line) == 0 || StringGetCharacter(line, 0) == '#')
         continue;

      int eq = StringFind(line, "=");
      if(eq <= 0) continue;

      string key = StringSubstr(line, 0, eq);
      string val = StringSubstr(line, eq + 1);
      StringTrimLeft(key);  StringTrimRight(key);
      StringTrimLeft(val);  StringTrimRight(val);

      if(key == "regime")
      {
         g_regimeName = val;
         applied++;
      }
      else if(key == "confidence")
      {
         g_regimeConf = StringToDouble(val);
         applied++;
      }
      else if(key == "atr_mult")
      {
         double v = StringToDouble(val);
         if(v >= 0.5 && v <= 5.0)
         {
            g_atrMult = v;
            applied++;
         }
      }
      else if(key == "atr_min_mult")
      {
         double v = StringToDouble(val);
         if(v >= 0 && v <= 2.0)
         {
            cc_atrMinMult = v;
            applied++;
         }
      }
      else if(key == "break_mult")
      {
         double v = StringToDouble(val);
         if(v >= 0 && v <= 1.0)
         {
            cc_breakMult = v;
            applied++;
         }
      }
      else if(key == "be_start_mult")
      {
         double v = StringToDouble(val);
         if(v >= 0.1 && v <= 3.0)
         {
            g_beStartMult = v;
            applied++;
         }
      }
      else if(key == "trail_min_dist")
      {
         double v = StringToDouble(val);
         if(v >= 0.1 && v <= 3.0)
         {
            g_trailMinDist = v;
            applied++;
         }
      }
      else if(key == "tp_atr_factor")
      {
         double v = StringToDouble(val);
         if(v >= 0.5 && v <= 3.0)
         {
            g_tpATRFactor = v;
            applied++;
         }
      }
   }

   FileClose(handle);
   g_lastConfigMod = modTime;
   g_lastConfigRead = TimeCurrent();

   Print(StringFormat("[REGIME] Applied %d params | regime=%s conf=%.2f | atrM=%.2f ccMin=%.2f ccBrk=%.2f beS=%.1f trD=%.1f tp=%.1f",
      applied, g_regimeName, g_regimeConf, g_atrMult, cc_atrMinMult, cc_breakMult,
      g_beStartMult, g_trailMinDist, g_tpATRFactor));

   // Refresh Settings panel UI with new values
   if(applied > 0)
   {
      ObjectSetString(0, OBJ_SET_ATR_EDT, OBJPROP_TEXT, StringFormat("%.1f", g_atrMult));
      ChartRedraw(0);
   }
}

// ════════════════════════════════════════════════════════════════════
// BOT STRATEGY INCLUDES
// ════════════════════════════════════════════════════════════════════
#include "Candle Counter Strategy.mqh"
#include "News Straddle Strategy.mqh"
#include "SR Retest Strategy.mqh"

// ════════════════════════════════════════════════════════════════════
// BOT PANEL MANAGEMENT
// ════════════════════════════════════════════════════════════════════
void CreateBotButtons()
{
   int x = BOT_PANEL_X;
   int y = BOT_PANEL_Y;

   // [Candle Count] [News Straddle] [SR Retest] buttons
   // Color: green=running, blue=viewing (not running), dark=inactive
   color ccBg, nsBg, srBg, ccTxt, nsTxt, srTxt;
   GetBotButtonColors(1, ccBg, ccTxt);
   GetBotButtonColors(2, nsBg, nsTxt);
   GetBotButtonColors(3, srBg, srTxt);

   MakeButton(OBJ_BOT_CC_BTN, x, y, BOT_BTN_W, BOT_BTN_H,
              "Candle Count", ccTxt, ccBg, 8);
   ObjectSetString(0, OBJ_BOT_CC_BTN, OBJPROP_TOOLTIP,
      "Candle Counter — đếm nến + ATR filter.\nXanh=đang chạy, Xanh dương=đang xem, Xám=tắt.");
   MakeButton(OBJ_BOT_NS_BTN, x + BOT_BTN_W + 2, y, BOT_BTN_W, BOT_BTN_H,
              "News Straddle", nsTxt, nsBg, 8);
   ObjectSetString(0, OBJ_BOT_NS_BTN, OBJPROP_TOOLTIP,
      "News Straddle — pending order trước tin.\nXanh=đang chạy, Xanh dương=đang xem, Xám=tắt.");
   MakeButton(OBJ_BOT_SR_BTN, x + 2*(BOT_BTN_W + 2), y, BOT_BTN_W, BOT_BTN_H,
              "SR Retest", srTxt, srBg, 8);
   ObjectSetString(0, OBJ_BOT_SR_BTN, OBJPROP_TOOLTIP,
      "SR Retest — limit tại swing S/R, SL nhỏ.\nXanh=đang chạy, Xanh dương=đang xem, Xám=tắt.");
}

// Get button colors: green=running, blue=viewing, dark=inactive
void GetBotButtonColors(int botId, color &bg, color &txt)
{
   bool running = false;
   if(botId == 1) running = cc_enabled;
   if(botId == 2) running = ns_enabled;
   if(botId == 3) running = sr_enabled;

   if(running)
   {
      bg  = C'0,100,60';       // Green = running
      txt = C'255,255,255';
   }
   else if(g_activeBot == botId)
   {
      bg  = C'30,60,120';      // Blue = viewing but not running
      txt = C'180,200,255';
   }
   else
   {
      bg  = C'50,50,70';       // Dark = inactive
      txt = C'140,140,160';
   }
}

void CreateBotPanel()
{
   // Background for bot content area
   int bgH = 360;
   MakeRect(OBJ_BOT_BG, BOT_PANEL_X, BOT_CONTENT_Y, BOT_CONTENT_W, bgH,
            COL_BG, COL_BORDER);

   // Start/Stop button at top of bot content area
   bool running = false;
   if(g_activeBot == 1) running = cc_enabled;
   if(g_activeBot == 2) running = ns_enabled;
   if(g_activeBot == 3) running = sr_enabled;

   color startBg  = running ? C'180,40,40' : C'0,100,60';  // Red=stop, Green=start
   color startTxt = C'255,255,255';
   string startLabel = running ? "\x25A0 Stop" : "\x25B6 Start";
   MakeButton(OBJ_BOT_START_BTN, BOT_PANEL_X + 4, BOT_CONTENT_Y + 4, 60, 20,
              startLabel, startTxt, startBg, 8);
   ObjectSetString(0, OBJ_BOT_START_BTN, OBJPROP_TOOLTIP,
      "Start/Stop bot hiện tại.\nBot chạy nền ngay cả khi xem bot khác.");

   // Auto‐Regime toggle button (only for CC bot)
   if(g_activeBot == 1)
   {
      color autoBg  = g_autoRegime ? C'120,80,0' : C'50,50,70';
      color autoTxt = g_autoRegime ? C'255,255,255' : C'140,140,160';
      string autoLbl = g_autoRegime ? "\x2699 Auto ON" : "\x2699 Auto";
      MakeButton(OBJ_BOT_AUTO_BTN, BOT_PANEL_X + 68, BOT_CONTENT_Y + 4, 64, 20,
                 autoLbl, autoTxt, autoBg, 8);
      ObjectSetString(0, OBJ_BOT_AUTO_BTN, OBJPROP_TOOLTIP,
         "Auto Regime — Python tự điều chỉnh params.\nĐọc config INI mỗi 60s.");
   }

   int contentStartY = BOT_CONTENT_Y + 28;  // Below start button

   if(g_activeBot == 1)
      CC_CreatePanel(BOT_PANEL_X, contentStartY, BOT_CONTENT_W);
   else if(g_activeBot == 2)
      NS_CreatePanel(BOT_PANEL_X, contentStartY, BOT_CONTENT_W);
   else if(g_activeBot == 3)
      SR_CreatePanel(BOT_PANEL_X, contentStartY, BOT_CONTENT_W);
}

void DestroyBotPanel()
{
   CC_DestroyPanel();
   NS_DestroyPanel();
   SR_DestroyPanel();
   ObjectDelete(0, OBJ_BOT_START_BTN);
   ObjectDelete(0, OBJ_BOT_AUTO_BTN);
   ObjectDelete(0, OBJ_BOT_BG);
}

void ToggleBot(int botId)
{
   // botId: 1=CC, 2=NS
   // Only switches VIEW — does NOT start/stop the bot

   if(g_activeBot == botId)
   {
      // Hide current view
      DestroyBotPanel();
      g_activeBot = 0;
      Print(StringFormat("[PANEL] Bot %d panel hidden", botId));
   }
   else
   {
      // Switch to new bot view
      DestroyBotPanel();
      g_activeBot = botId;
      CreateBotPanel();
      Print(StringFormat("[PANEL] Bot %d panel shown", botId));
   }

   // Update button colors
   UpdateBotButtonColors();
   ChartRedraw();
}

void ToggleBotStart()
{
   // Start/Stop the currently viewed bot
   if(g_activeBot == 0) return;

   if(g_activeBot == 1)
   {
      cc_enabled = !cc_enabled;
      if(cc_enabled)
      {
         cc_paused = false;
         cc_pauseTime = 0;
      }
      Print(StringFormat("[PANEL] Candle Count Bot %s", cc_enabled ? "STARTED" : "STOPPED"));
   }
   else if(g_activeBot == 2)
   {
      ns_enabled = !ns_enabled;
      if(ns_enabled)
      {
         ns_paused = false;
         ns_pauseTime = 0;
      }
      Print(StringFormat("[PANEL] NS Bot %s", ns_enabled ? "STARTED" : "STOPPED"));
   }
   else if(g_activeBot == 3)
   {
      sr_enabled = !sr_enabled;
      Print(StringFormat("[PANEL] SR Retest Bot %s", sr_enabled ? "STARTED" : "STOPPED"));
   }

   // Update Start/Stop button appearance immediately (heavy init deferred to next Timer)
   UpdateBotStartButton();
   UpdateBotButtonColors();
   ChartRedraw();
}

void UpdateBotStartButton()
{
   if(g_activeBot == 0) return;

   bool running = false;
   if(g_activeBot == 1) running = cc_enabled;
   if(g_activeBot == 2) running = ns_enabled;
   if(g_activeBot == 3) running = sr_enabled;

   color bg  = running ? C'180,40,40' : C'0,100,60';
   string label = running ? "\x25A0 Stop" : "\x25B6 Start";
   ObjectSetString (0, OBJ_BOT_START_BTN, OBJPROP_TEXT, label);
   ObjectSetInteger(0, OBJ_BOT_START_BTN, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, OBJ_BOT_START_BTN, OBJPROP_BORDER_COLOR, bg);
}

void UpdateBotButtonColors()
{
   color bg, txt;
   GetBotButtonColors(1, bg, txt);
   ObjectSetInteger(0, OBJ_BOT_CC_BTN, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, OBJ_BOT_CC_BTN, OBJPROP_BORDER_COLOR, bg);
   ObjectSetInteger(0, OBJ_BOT_CC_BTN, OBJPROP_COLOR, txt);
   GetBotButtonColors(2, bg, txt);
   ObjectSetInteger(0, OBJ_BOT_NS_BTN, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, OBJ_BOT_NS_BTN, OBJPROP_BORDER_COLOR, bg);
   ObjectSetInteger(0, OBJ_BOT_NS_BTN, OBJPROP_COLOR, txt);
   GetBotButtonColors(3, bg, txt);
   ObjectSetInteger(0, OBJ_BOT_SR_BTN, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, OBJ_BOT_SR_BTN, OBJPROP_BORDER_COLOR, bg);
   ObjectSetInteger(0, OBJ_BOT_SR_BTN, OBJPROP_COLOR, txt);
}

void CreatePanel()
{
   int y  = PY;
   int bw = (IW - 8) / 2;   // half-width for paired buttons

   // ── Background ──
   MakeRect(OBJ_BG, PX, y, PW, 300, COL_BG, COL_BORDER);

   // ── Title bar ──
   MakeRect(OBJ_TITLE_BG, PX + 1, y + 1, PW - 2, 26, COL_TITLE_BG, COL_TITLE_BG);
   string titleTxt = "Trading Panel v2.32";
   MakeLabel(OBJ_TITLE, IX, y + 6, titleTxt, C'170,180,215', 10, FONT_BOLD);

   // ── Collapsed info row (below title bar, visible only when collapsed) ──
   MakeLabel(OBJ_TITLE_INFO, IX, y + 30, " ", COL_DIM, 9, FONT_BOLD);
   MakeLabel(OBJ_TITLE_LOCK, IX + IW + MARGIN - 5, y + 30, " ", COL_DIM, 8, FONT_MONO);
   ObjectSetInteger(0, OBJ_TITLE_LOCK, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, OBJ_TITLE_INFO, OBJPROP_TIMEFRAMES,
      g_panelCollapsed ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   ObjectSetInteger(0, OBJ_TITLE_LOCK, OBJPROP_TIMEFRAMES,
      g_panelCollapsed ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);

   // Theme + utility buttons (right side of title bar)
   // Layout: [Set][Dark][Lines][▼]
   {
      int bw2 = 38;   // width for each header button
      int gap = 2;
      int rx = PX + PW - 4 * (bw2 + gap) - 4;  // start X for 4 buttons
      MakeButton(OBJ_SETTINGS_BTN, rx,                          y + 3, bw2, 20, "Set",    COL_BTN_TXT, C'40,40,55', 7, FONT_MAIN);
      MakeButton(OBJ_THEME_BTN,    rx + (bw2 + gap),            y + 3, bw2, 20, "Dark",   COL_BTN_TXT, C'40,40,55', 7, FONT_MAIN);
      MakeButton(OBJ_LINES_BTN,    rx + 2 * (bw2 + gap),        y + 3, bw2, 20, "Lines",  COL_BTN_TXT, C'40,40,55', 7, FONT_MAIN);
      MakeButton(OBJ_COLLAPSE_BTN, rx + 3 * (bw2 + gap),        y + 3, bw2, 20, "\x25BC", COL_BTN_TXT, C'40,40,55', 8, FONT_MAIN);
   }
   y += 32;

   // ═══════════════════════════════════════
   // SECTION: SETTINGS (collapsible)
   // ═══════════════════════════════════════
   if(g_settingsExpanded)
   {
      // Highlight [Set] button when expanded
      ObjectSetInteger(0, OBJ_SETTINGS_BTN, OBJPROP_BGCOLOR, C'0,100,60');
      ObjectSetInteger(0, OBJ_SETTINGS_BTN, OBJPROP_BORDER_COLOR, C'0,100,60');
      ObjectSetInteger(0, OBJ_SETTINGS_BTN, OBJPROP_COLOR, COL_WHITE);

      MakeRect(OBJ_SET_SEP, IX, y, IW, 1, COL_BORDER, COL_BORDER);
      MakeLabel(OBJ_SET_SEC, IX + 2, y - 5, " SETTINGS ", C'100,110,140', 7, FONT_MAIN);
      y += 8;

      // ── Risk row: [$] [__$__] [-][+]   [%] [__%__] [-][+] ──
      {
         int rx = IX;
         // [$] mode button
         color dBg  = g_riskPctMode ? C'50,50,70' : C'0,100,60';
         color dTxt = g_riskPctMode ? C'140,140,160' : C'255,255,255';
         MakeButton(OBJ_SET_MODE_DOLLAR, rx, y, 24, 22, "$", dTxt, dBg, 9, FONT_BOLD);
         rx += 26;
         // $ edit
         MakeEdit(OBJ_SET_RISK_EDT, rx, y, 52, 22,
                  IntegerToString((int)g_riskMoney),
                  COL_WHITE, COL_EDIT_BG, COL_EDIT_BD);
         rx += 54;
         // [-] [+] for $
         MakeButton(OBJ_SET_RISK_MINUS, rx, y, 24, 22, "-", COL_BTN_TXT, C'80,40,40', 10, FONT_BOLD);
         rx += 26;
         MakeButton(OBJ_SET_RISK_PLUS,  rx, y, 24, 22, "+", COL_BTN_TXT, C'40,80,40', 10, FONT_BOLD);
         rx += 32;
         // [%] mode button
         color pBg  = g_riskPctMode ? C'0,100,60' : C'50,50,70';
         color pTxt = g_riskPctMode ? C'255,255,255' : C'140,140,160';
         MakeButton(OBJ_SET_MODE_PCT, rx, y, 24, 22, "%", pTxt, pBg, 9, FONT_BOLD);
         rx += 26;
         // % edit
         MakeEdit(OBJ_SET_PCT_EDT, rx, y, 52, 22,
                  StringFormat("%.1f", g_riskPct),
                  COL_WHITE, COL_EDIT_BG, COL_EDIT_BD);
         rx += 54;
         // [-] [+] for %
         MakeButton(OBJ_SET_PCT_MINUS, rx, y, 24, 22, "-", COL_BTN_TXT, C'80,40,40', 10, FONT_BOLD);
         rx += 26;
         MakeButton(OBJ_SET_PCT_PLUS,  rx, y, 24, 22, "+", COL_BTN_TXT, C'40,80,40', 10, FONT_BOLD);
      }
      y += 26;

      // ── ATR row: label + edit + [−] [+] ──
      MakeLabel(OBJ_SET_ATR_LBL, IX, y + 3, "ATR", COL_DIM, 9);
      MakeEdit(OBJ_SET_ATR_EDT, IX + 48, y, 60, 22,
               StringFormat("%.1f", g_atrMult),
               COL_WHITE, COL_EDIT_BG, COL_EDIT_BD);
      MakeButton(OBJ_SET_ATR_MINUS, IX + 112, y, 28, 22, "-", COL_BTN_TXT, C'80,40,40', 10, FONT_BOLD);
      MakeButton(OBJ_SET_ATR_PLUS,  IX + 143, y, 28, 22, "+", COL_BTN_TXT, C'40,80,40', 10, FONT_BOLD);
      y += 28;
   }

   // ═══════════════════════════════════════
   // SECTION: INFO
   // ═══════════════════════════════════════
   MakeRect(OBJ_SEP1, IX, y, IW, 1, COL_BORDER, COL_BORDER);
   MakeLabel(OBJ_SEC_INFO, IX + 2, y - 5, " INFO ", C'100,110,140', 7, FONT_MAIN);
   y += 8;

   // ── Row 1: Status (left) + P&L (right) ──
   MakeLabel(OBJ_STATUS_LBL, IX, y + 1, " ", COL_DIM, 11, FONT_BOLD);
   MakeLabel(OBJ_RISK_LBL, IX + IW - 5, y + 1, " ", COL_DIM, 11, FONT_BOLD);
   ObjectSetInteger(0, OBJ_RISK_LBL, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   y += 22;

   // ── Row 1b: Locked Profit at SL (left label + right value) ──
   MakeLabel(OBJ_LOCK_LBL, IX, y, "SL Lock", COL_DIM, 8, FONT_MONO);
   MakeLabel(OBJ_LOCK_VAL, IX + IW - 5, y, " ", COL_DIM, 8, FONT_MONO);
   ObjectSetInteger(0, OBJ_LOCK_VAL, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   y += 16;

   // ── Row 2: Risk | ATR | Spread info ──
   MakeLabel(OBJ_SPRD_LBL, IX, y, "", COL_DIM, 8, FONT_MONO);
   y += 16;

   // ═══════════════════════════════════════
   // SECTION: TRADE
   // ═══════════════════════════════════════
   MakeRect(OBJ_SEP2, IX, y, IW, 1, COL_BORDER, COL_BORDER);
   MakeLabel(OBJ_SEC_TRADE, IX + 2, y - 5, " TRADE ", C'100,110,140', 7, FONT_MAIN);
   y += 8;

   // ── BUY / SELL buttons (40px height) ──
   MakeButton(OBJ_BUY_BTN,  PX + 5,          y, bw, 40,
              "BUY", COL_WHITE, COL_BUY, 11);
   MakeButton(OBJ_SELL_BTN, PX + 5 + bw + 8, y, bw, 40,
              "SELL", COL_WHITE, COL_SELL, 11);
   y += 44;

   // ═══════════════════════════════════════
   // SECTION: ORDER MANAGEMENT
   // ═══════════════════════════════════════
   MakeRect(OBJ_SEP3, IX, y, IW, 1, COL_BORDER, COL_BORDER);
   MakeLabel(OBJ_SEC_ORDER, IX + 2, y - 5, " ORDER MANAGEMENT ", C'100,110,140', 7, FONT_MAIN);
   y += 8;

   // ── Auto TP toggle + ATR factor selector (0.5 / 1) ──
   {
      int tpFcW = 30;  // width of each factor button
      int tpGp  = 2;
      int tpBtnW = IW - 2 - tpFcW * 2 - tpGp * 2;  // main button width
      MakeButton(OBJ_AUTOTP_BTN, PX + 5, y, tpBtnW, 26,
                 "Auto TP: OFF", C'180,180,200', C'60,60,85', 8);
      // Factor buttons: highlight active one
      color bg05  = (g_tpATRFactor <= 0.5) ? C'0,100,60' : C'50,50,70';
      color bg10  = (g_tpATRFactor >= 1.0) ? C'0,100,60' : C'50,50,70';
      color txt05 = (g_tpATRFactor <= 0.5) ? COL_WHITE   : C'140,140,160';
      color txt10 = (g_tpATRFactor >= 1.0) ? COL_WHITE   : C'140,140,160';
      MakeButton(OBJ_TP_05, PX + 5 + tpBtnW + tpGp, y, tpFcW, 26,
                 "0.5", txt05, bg05, 8);
      MakeButton(OBJ_TP_10, PX + 5 + tpBtnW + tpGp + tpFcW + tpGp, y, tpFcW, 26,
                 "1", txt10, bg10, 8);
   }
   y += 28;

   // ── Grid DCA toggle + level selector + delay selector ──
   int gridDlyW = 32;  // width of delay cycle button
   int gridLvlW = 32;  // width of level cycle button
   int gridBtnW = IW - 2 - gridLvlW - 2 - gridDlyW - 2;  // main grid button width
   MakeButton(OBJ_GRID_BTN, PX + 5, y, gridBtnW, 26,
              "Grid DCA: OFF", C'180,180,200', C'60,60,85', 8);
   MakeButton(OBJ_GRID_LVL, PX + 5 + gridBtnW + 2, y, gridLvlW, 26,
              StringFormat("x%d", g_gridMaxLevel), C'180,200,255', C'40,50,80', 8);
   MakeButton(OBJ_GRID_DLY, PX + 5 + gridBtnW + 2 + gridLvlW + 2, y, gridDlyW, 26,
              StringFormat("%dm", g_gridDelay), C'200,180,255', C'50,40,80', 8);
   y += 30;

   // ── Trail method buttons (1 row): Trail Close | Trail Swing | BE ──
   //   Close/Swing: toggle (click again to deselect)
   //   BE: toggle modifier (combinable with Close/Swing)
   {
      int bx = PX + 5;
      int gp = 2;    // gap between buttons
      int mw = (IW - 2 - 2 * gp) / 3;  // 3 equal-width buttons
      MakeButton(OBJ_TM_CLOSE, bx, y, mw, 26,
                 "Trail Close", C'140,140,160', C'50,50,70', 7);
      bx += mw + gp;
      MakeButton(OBJ_TM_SWING, bx, y, mw, 26,
                 "Trail Swing", C'140,140,160', C'50,50,70', 7);
      bx += mw + gp;
      MakeButton(OBJ_TM_BE, bx, y, mw, 26,
                 "BE", C'140,140,160', C'50,50,70', 7);
   }
   y += 28;

   // ── Trail parameter line (contextual: BE Start / Min Dist / hidden) ──
   {
      string tpLbl = g_beEnabled ? "BE Start:" : "Min Dist:";
      double tpVal = g_beEnabled ? g_beStartMult : g_trailMinDist;
      MakeLabel(OBJ_TRAIL_LBL, PX + 8, y + 4, tpLbl, C'140,140,160', 8, "Segoe UI");
      MakeLabel(OBJ_TRAIL_VAL, PX + 70, y + 4,
                StringFormat("%.1fx", tpVal), C'220,225,240', 8, "Consolas");
      MakeButton(OBJ_TRAIL_MINUS, PX + 5 + IW - 56, y, 26, 22,
                 "-", C'180,180,200', C'55,55,75', 9);
      MakeButton(OBJ_TRAIL_PLUS, PX + 5 + IW - 28, y, 26, 22,
                 "+", C'180,180,200', C'55,55,75', 9);
   }
   y += 24;

   // ── Grid/TP info line (hidden initially, shown when grid/tp active with position) ──
   MakeLabel(OBJ_GRID_INFO, IX, y, " ", COL_DIM, 8, FONT_MONO);
   y += 16;

   // ═══════════════════════════════════════
   // CLOSE SECTION (single row: 50% | 75% | ALL)
   // ═══════════════════════════════════════
   MakeRect(OBJ_SEP5, IX, y, IW, 1, COL_BORDER, COL_BORDER);
   y += 6;
   {
      int cw3 = (IW - 2 - 8) / 3;  // 3 buttons with 4px gaps
      MakeButton(OBJ_CLOSE50_BTN, PX + 5, y, cw3, 28,
                 "Close 50%", C'220,180,180', C'120,50,50', 8);
      MakeButton(OBJ_CLOSE75_BTN, PX + 5 + cw3 + 4, y, cw3, 28,
                 "Close 75%", C'220,180,180', C'120,50,50', 8);
      MakeButton(OBJ_CLOSE_BTN, PX + 5 + 2*(cw3 + 4), y, cw3, 28,
                 "Close 100%", C'255,200,200', COL_CLOSE, 8);
   }
   y += 34;

   // ═══════════════════════════════════════
   // TOOLTIPS (tiếng Việt)
   // ═══════════════════════════════════════

   // ── Labels ──
   ObjectSetString(0, OBJ_TITLE, OBJPROP_TOOLTIP,
      "Bảng giao dịch nhanh — vào lệnh thủ công, bot quản lý SL/TP.");
   ObjectSetString(0, OBJ_SET_SEC, OBJPROP_TOOLTIP,
      "Cài đặt Risk (rủi ro) và ATR (Average True Range).\n[$] = Fixed dollar risk | [%] = Auto % of balance.");
   ObjectSetString(0, OBJ_SET_ATR_LBL, OBJPROP_TOOLTIP,
      "ATR (Average True Range): Chỉ báo đo biên độ dao động trung bình.\nHệ số ATR càng lớn → SL càng xa → lot càng nhỏ.\nVD: ATR 1.5x = SL cách giá 1.5 lần biên độ ATR.");
   ObjectSetString(0, OBJ_SEC_INFO, OBJPROP_TOOLTIP,
      "Thông tin: Risk, lot, hướng lệnh, lãi/lỗ hiện tại.");
   ObjectSetString(0, OBJ_RISK_LBL, OBJPROP_TOOLTIP,
      "Khi có lệnh: P&L hiện tại.\nKhi chưa có lệnh: Số tiền mất nếu SL hit (cập nhật khi kéo SL).");
   ObjectSetString(0, OBJ_LOCK_LBL, OBJPROP_TOOLTIP,
      "Khi có lệnh: SL Lock = Lãi/Lỗ tại mức SL.\nKhi chưa có lệnh: RR ratio hoặc SL x ATR.");
   ObjectSetString(0, OBJ_LOCK_VAL, OBJPROP_TOOLTIP,
      "Khi có lệnh: SL Lock value.\nKhi chưa có lệnh: TP $ dự kiến (chỉ hiện khi Auto TP ON).");
   ObjectSetString(0, OBJ_STATUS_LBL, OBJPROP_TOOLTIP,
      "Lot size và hướng lệnh (LONG/SHORT).\nKhi chưa có lệnh: lot dự kiến theo Risk hiện tại.");
   ObjectSetString(0, OBJ_SPRD_LBL, OBJPROP_TOOLTIP,
      "Risk: Tiền rủi ro mỗi lệnh ($).\nATR (Average True Range): Hệ số biên độ dao động.\nSpread: Chênh lệch giá mua-bán (point).");
   ObjectSetString(0, OBJ_SEC_TRADE, OBJPROP_TOOLTIP,
      "Khu vực vào lệnh: BUY/SELL market nhanh.");
   ObjectSetString(0, OBJ_SEC_ORDER, OBJPROP_TOOLTIP,
      "Quản lý lệnh tự động: Trailing SL, Grid DCA, Auto Take Profit.");
   ObjectSetString(0, OBJ_GRID_INFO, OBJPROP_TOOLTIP,
      "Thông tin chi tiết Grid DCA và Auto TP khi đang có lệnh.");

   // ── Header buttons ──
   ObjectSetString(0, OBJ_SETTINGS_BTN, OBJPROP_TOOLTIP,
      "Mở/đóng bảng cài đặt");
   ObjectSetString(0, OBJ_THEME_BTN, OBJPROP_TOOLTIP,
      "Chuyển đổi giao diện Tối/Sáng");
   ObjectSetString(0, OBJ_LINES_BTN, OBJPROP_TOOLTIP,
      "Ẩn/hiện các đường của công cụ trên chart");
   ObjectSetString(0, OBJ_COLLAPSE_BTN, OBJPROP_TOOLTIP,
      "Thu gọn/mở rộng bảng điều khiển");

   // ── Settings: Edit fields ──
   ObjectSetString(0, OBJ_SET_RISK_EDT, OBJPROP_TOOLTIP,
      "Nhập số tiền Risk ($) cho mỗi lệnh.\nVD: 10 = mất tối đa $10 nếu dính SL.");
   ObjectSetString(0, OBJ_SET_ATR_EDT, OBJPROP_TOOLTIP,
      "Nhập hệ số ATR (Average True Range).\nVD: 1.5 = SL cách giá vào 1.5 lần biên độ dao động.");

   // Settings: Risk (step = $ per 0.01 lot at current ATR SL)
   ObjectSetString(0, OBJ_SET_RISK_MINUS, OBJPROP_TOOLTIP, "Giảm Risk (theo 0.01 lot step)\nChuyển sang $Fixed. Min = risk tối thiểu cho min lot");
   ObjectSetString(0, OBJ_SET_RISK_PLUS,  OBJPROP_TOOLTIP, "Tăng Risk (theo 0.01 lot step)\nChuyển sang $Fixed");
   ObjectSetString(0, OBJ_SET_PCT_MINUS,  OBJPROP_TOOLTIP, "Giảm Risk % (theo 0.01 lot step)\nChuyển sang %Auto");
   ObjectSetString(0, OBJ_SET_PCT_PLUS,   OBJPROP_TOOLTIP, "Tăng Risk % (theo 0.01 lot step)\nChuyển sang %Auto");
   ObjectSetString(0, OBJ_SET_MODE_DOLLAR, OBJPROP_TOOLTIP,
      "$Fixed: Risk cố định theo số tiền.\nKhông tự thay đổi khi balance thay đổi.");
   ObjectSetString(0, OBJ_SET_MODE_PCT,   OBJPROP_TOOLTIP,
      "%Auto: Risk = % balance.\nTự tính lại trước mỗi lệnh theo số dư hiện tại.");

   // Settings: ATR
   ObjectSetString(0, OBJ_SET_ATR_MINUS, OBJPROP_TOOLTIP, "Giảm ATR ×0.5 (snap đến bước 0.5 gần nhất)");
   ObjectSetString(0, OBJ_SET_ATR_PLUS,  OBJPROP_TOOLTIP, "Tăng ATR ×0.5 (snap đến bước 0.5 gần nhất)");

   // Trade buttons
   ObjectSetString(0, OBJ_BUY_BTN,  OBJPROP_TOOLTIP,
      "Mua ngay theo giá thị trường.\nSL tự động theo ATR. Lot tính theo Risk $.");
   ObjectSetString(0, OBJ_SELL_BTN, OBJPROP_TOOLTIP,
      "Bán ngay theo giá thị trường.\nSL tự động theo ATR. Lot tính theo Risk $.");

   // Trail SL
   ObjectSetString(0, OBJ_TM_CLOSE, OBJPROP_TOOLTIP,
      "CLOSE — Theo r\xE2u nến bar[1]\n"
      "BUY: SL = Low[1] | SELL: SL = High[1]\n"
      "Click lần nữa để tắt.\n"
      "Kết hợp +BE: BE trước → rồi Close (bỏ profit gate).");

   ObjectSetString(0, OBJ_TM_SWING, OBJPROP_TOOLTIP,
      "SWING — Theo ch\xE2n sóng gần nhất\n"
      "BUY: SL = Swing Low | SELL: SL = Swing High\n"
      "Click lần nữa để tắt.\n"
      "Kết hợp +BE: BE trước → rồi Swing (bỏ profit gate).");

   ObjectSetString(0, OBJ_TM_BE, OBJPROP_TOOLTIP,
      "BE — Toggle bật/tắt (kết hợp với Close/Swing)\n"
      "B1: Giá >= BE Start × ATR → SL về entry\n"
      "B2: Nếu có Close/Swing → chạy theo nến (không cần profit gate)\n"
      "    Nếu chỉ BE → bước nhảy +1 ATR mỗi level\n"
      "Cam = bật chờ | Xanh = đã về BE | Xám = tắt");

   // Grid DCA
   ObjectSetString(0, OBJ_GRID_BTN, OBJPROP_TOOLTIP,
      "Grid DCA — Bật/Tắt\n"
      "Tự động thêm lệnh khi giá đi ngược.\n"
      "SL mở rộng tự động theo số level.\n"
      "Bảo vệ: delay + nến > 2×ATR → skip DCA.");
   ObjectSetString(0, OBJ_GRID_LVL, OBJPROP_TOOLTIP,
      "Số level DCA tối đa (2-5).\n"
      "Click để đổi: 2→3→4→5→2...\n"
      "Không đổi được khi đang có lệnh + grid bật.");

   ObjectSetString(0, OBJ_GRID_DLY, OBJPROP_TOOLTIP,
      "Delay giữa các DCA (phút).\n"
      "Gợi ý: 5m cho M1, 10-15m cho M5-M15.\n"
      "Kèm filter: nến > 2×ATR → skip DCA.");

   // Auto TP
   ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TOOLTIP,
      "Auto TP — Chỉ đóng lệnh (không dời SL)\n"
      "Đóng 50% khối lượng khi lãi đạt mục tiêu ATR.\n"
      "Chọn 0.5 hoặc 1 ATR bằng nút bên cạnh.\n"
      "Nếu lot = min → bỏ qua (không đóng được).\n"
      "Phối hợp Trail BE để dời SL phần còn lại.");
   ObjectSetString(0, OBJ_TP_05, OBJPROP_TOOLTIP,
      "TP1 tại 0.5 ATR (đóng 50% volume)");
   ObjectSetString(0, OBJ_TP_10, OBJPROP_TOOLTIP,
      "TP1 tại 1.0 ATR (đóng 50% volume)");

   // Trail params
   ObjectSetString(0, OBJ_TRAIL_LBL, OBJPROP_TOOLTIP,
      "BE Start: khi nào trail bắt đầu (BE mode)\n"
      "Min Dist: khoảng cách SL tối thiểu (Close/Swing)");
   ObjectSetString(0, OBJ_TRAIL_VAL, OBJPROP_TOOLTIP,
      "Giá trị hiện tại × ATR input.\n"
      "Nhấn [-][+] để chỉnh (bước 0.1, phạm vi 0.1-3.0).");
   ObjectSetString(0, OBJ_TRAIL_MINUS, OBJPROP_TOOLTIP, "Giảm 0.1 (min 0.1)");
   ObjectSetString(0, OBJ_TRAIL_PLUS,  OBJPROP_TOOLTIP, "Tăng 0.1 (max 3.0)");

   // Close buttons
   ObjectSetString(0, OBJ_CLOSE50_BTN, OBJPROP_TOOLTIP,
      "Đóng 50% khối lượng tất cả lệnh đang mở.\nPhần còn lại tiếp tục chạy.");
   ObjectSetString(0, OBJ_CLOSE75_BTN, OBJPROP_TOOLTIP,
      "Đóng 75% khối lượng tất cả lệnh đang mở.\nPhần còn lại tiếp tục chạy.");
   ObjectSetString(0, OBJ_CLOSE_BTN, OBJPROP_TOOLTIP,
      "Đóng TẤT CẢ các lệnh đang mở.\nBao gồm lệnh DCA. Không thể hoàn tác!");

   // Adjust panel background height
   g_panelFullHeight = y - PY + 5;
   ObjectSetInteger(0, OBJ_BG, OBJPROP_YSIZE, g_panelFullHeight);

   // ── Bot toggle buttons (right of panel) ──
   CreateBotButtons();
   if(g_activeBot > 0)
      CreateBotPanel();

   ChartRedraw();
}

void DestroyPanel()
{
   DestroyBotPanel();
   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update trail parameter display (label + value) based on mode     |
//+------------------------------------------------------------------+
void UpdateTrailParamDisplay()
{
   string lbl = g_beEnabled ? "BE Start:" : "Min Dist:";
   double val = g_beEnabled ? g_beStartMult : g_trailMinDist;
   ObjectSetString(0, OBJ_TRAIL_LBL, OBJPROP_TEXT, lbl);
   ObjectSetString(0, OBJ_TRAIL_VAL, OBJPROP_TEXT, StringFormat("%.1fx", val));
   // Note: ChartRedraw + UpdateTPGridLines handled by caller (UpdatePanel or button handler)
}

//+------------------------------------------------------------------+
//| Sync button appearance with actual enabled state                  |
//+------------------------------------------------------------------+
void SyncButtonAppearance()
{
   // ── Derive g_trailEnabled from button states ──
   g_trailEnabled = (g_trailRef != TRAIL_NONE || g_beEnabled);

   // ── Trail mode buttons: Close/Swing (toggle) + BE (toggle) ──
   // Close/Swing: Blue = selected, Green = active, Gray = not selected
   // BE: Orange = ON, Green = active (beReached), Gray = OFF

   // Determine if trail is actively tracking
   bool closeSwingActive = false;
   bool beActive = false;
   if(g_hasPos && g_trailEnabled)
   {
      double refEntry = (g_gridEnabled && g_gridLevel > 0) ? GetAvgEntry() : g_entryPx;
      if(refEntry <= 0) refEntry = g_entryPx;
      double cur2 = g_isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                            : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double move = g_isBuy ? (cur2 - refEntry) : (refEntry - cur2);

      // Close/Swing active: profit gate met (or BE reached → no gate)
      if(g_trailRef == TRAIL_CLOSE || g_trailRef == TRAIL_SWING)
      {
         if(g_beEnabled && g_beReached)
            closeSwingActive = true;  // post-BE: always active
         else if(!g_beEnabled)
            closeSwingActive = (move >= g_cachedATR * g_tpATRFactor * g_atrMult);
      }

      // BE active: reached or about to trigger
      if(g_beEnabled)
         beActive = g_beReached || (g_cachedATR > 0 && move >= g_beStartMult * g_cachedATR * g_atrMult);
   }

   // Close button
   if(g_trailRef == TRAIL_CLOSE)
   {
      if(closeSwingActive)
      { ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_BGCOLOR, C'0,100,60');
        ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_BORDER_COLOR, C'0,140,80');
        ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_COLOR, COL_WHITE); }
      else
      { ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_BGCOLOR, C'30,80,140');
        ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_BORDER_COLOR, C'50,120,200');
        ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_COLOR, COL_WHITE); }
   }
   else
   { ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_BGCOLOR, C'50,50,70');
     ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_BORDER_COLOR, C'50,50,70');
     ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_COLOR, C'140,140,160'); }

   // Swing button
   if(g_trailRef == TRAIL_SWING)
   {
      if(closeSwingActive)
      { ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_BGCOLOR, C'0,100,60');
        ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_BORDER_COLOR, C'0,140,80');
        ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_COLOR, COL_WHITE); }
      else
      { ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_BGCOLOR, C'30,80,140');
        ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_BORDER_COLOR, C'50,120,200');
        ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_COLOR, COL_WHITE); }
   }
   else
   { ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_BGCOLOR, C'50,50,70');
     ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_BORDER_COLOR, C'50,50,70');
     ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_COLOR, C'140,140,160'); }

   // BE button (toggle: orange=ON, green=active, gray=OFF)
   if(g_beEnabled)
   {
      if(beActive)
      { ObjectSetInteger(0, OBJ_TM_BE, OBJPROP_BGCOLOR, C'0,100,60');
        ObjectSetInteger(0, OBJ_TM_BE, OBJPROP_BORDER_COLOR, C'0,140,80');
        ObjectSetInteger(0, OBJ_TM_BE, OBJPROP_COLOR, COL_WHITE); }
      else
      { ObjectSetInteger(0, OBJ_TM_BE, OBJPROP_BGCOLOR, C'160,100,20');
        ObjectSetInteger(0, OBJ_TM_BE, OBJPROP_BORDER_COLOR, C'200,130,30');
        ObjectSetInteger(0, OBJ_TM_BE, OBJPROP_COLOR, COL_WHITE); }
   }
   else
   { ObjectSetInteger(0, OBJ_TM_BE, OBJPROP_BGCOLOR, C'50,50,70');
     ObjectSetInteger(0, OBJ_TM_BE, OBJPROP_BORDER_COLOR, C'50,50,70');
     ObjectSetInteger(0, OBJ_TM_BE, OBJPROP_COLOR, C'140,140,160'); }

   // ── Trail parameter display refresh (label text only, no ChartRedraw) ──
   {
      string tLbl = g_beEnabled ? "BE Start:" : "Min Dist:";
      double tVal = g_beEnabled ? g_beStartMult : g_trailMinDist;
      ObjectSetString(0, OBJ_TRAIL_LBL, OBJPROP_TEXT, tLbl);
      ObjectSetString(0, OBJ_TRAIL_VAL, OBJPROP_TEXT, StringFormat("%.1fx", tVal));
   }

   // ── Grid DCA button ──
   if(g_gridEnabled)
   {
      // Ensure text shows ON state (text content managed by UpdatePanel)
      if(StringFind(ObjectGetString(0, OBJ_GRID_BTN, OBJPROP_TEXT), "OFF") >= 0)
      {
         double maxRisk = CalcProjectedMaxRisk();
         ObjectSetString(0, OBJ_GRID_BTN, OBJPROP_TEXT,
            StringFormat("Grid DCA: ON | DCA %d/%d | Max $%.0f",
                         g_gridLevel, g_gridMaxLevel, maxRisk));
      }
      ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_BGCOLOR, C'0,100,60');
      ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_BORDER_COLOR, C'0,100,60');
      ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_COLOR, COL_WHITE);
   }
   else
   {
      ObjectSetString (0, OBJ_GRID_BTN, OBJPROP_TEXT, "Grid DCA: OFF");
      ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_BGCOLOR, C'60,60,85');
      ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_BORDER_COLOR, C'60,60,85');
      ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_COLOR, C'180,180,200');
   }
   // Grid level button always shows current level
   ObjectSetString(0, OBJ_GRID_LVL, OBJPROP_TEXT,
      StringFormat("x%d", g_gridMaxLevel));

   // ── Auto TP button ──
   if(g_autoTPEnabled)
   {
      // Always refresh text (ATR mult may have changed via ± buttons)
      ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT,
         g_tp1Hit ? "Auto TP: ON | TP1 \x2713"
                  : StringFormat("Auto TP: ON | 50%%@%.1fx%.1f", g_tpATRFactor, g_atrMult));
      ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_BGCOLOR, C'0,100,60');
      ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_BORDER_COLOR, C'0,100,60');
      ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_COLOR, COL_WHITE);
   }
   else
   {
      ObjectSetString (0, OBJ_AUTOTP_BTN, OBJPROP_TEXT, "Auto TP: OFF");
      ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_BGCOLOR, C'60,60,85');
      ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_BORDER_COLOR, C'60,60,85');
      ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_COLOR, C'180,180,200');
   }

   // ── TP ATR factor buttons ──
   ObjectSetInteger(0, OBJ_TP_05, OBJPROP_BGCOLOR,
      (g_tpATRFactor <= 0.5) ? C'0,100,60' : C'50,50,70');
   ObjectSetInteger(0, OBJ_TP_05, OBJPROP_COLOR,
      (g_tpATRFactor <= 0.5) ? COL_WHITE   : C'140,140,160');
   ObjectSetInteger(0, OBJ_TP_10, OBJPROP_BGCOLOR,
      (g_tpATRFactor >= 1.0) ? C'0,100,60' : C'50,50,70');
   ObjectSetInteger(0, OBJ_TP_10, OBJPROP_COLOR,
      (g_tpATRFactor >= 1.0) ? COL_WHITE   : C'140,140,160');
}

void UpdatePanel()
{
   // ── Read risk: settings edit if open, otherwise use current g_riskMoney ──
   if(g_settingsExpanded)
   {
      if(!g_riskPctMode)
      {
         // $Fixed mode: read $ edit
         string riskStr = ObjectGetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT);
         double parsed  = StringToDouble(riskStr);
         if(parsed > 0) g_riskMoney = parsed;
      }
      else
      {
         // %Auto mode: read % edit, recalc $
         string pctStr = ObjectGetString(0, OBJ_SET_PCT_EDT, OBJPROP_TEXT);
         double parsedPct = StringToDouble(pctStr);
         if(parsedPct > 0) g_riskPct = parsedPct;
      }
   }
   // %Auto mode: always recalc $ from current balance
   if(g_riskPctMode)
   {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      if(bal > 0) g_riskMoney = MathMax(1, MathFloor(bal * g_riskPct / 100.0));
      // Update $ edit display to reflect recalculated value
      if(g_settingsExpanded)
         ObjectSetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT, IntegerToString((int)g_riskMoney));
   }
   else if(g_settingsExpanded)
   {
      // $Fixed mode: sync % display from current $
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      if(bal > 0) g_riskPct = NormalizeDouble(g_riskMoney / bal * 100.0, 1);
      ObjectSetString(0, OBJ_SET_PCT_EDT, OBJPROP_TEXT, StringFormat("%.1f", g_riskPct));
   }
   if(g_riskMoney <= 0) g_riskMoney = InpDefaultRisk;

   // Update INFO section risk label
   // (Risk now shown in SPRD line, OBJ_RISK_LBL repurposed for P&L)

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // ── SL prices for each direction ──
   double slBuy, slSell, distBuy, distSell;
   slBuy    = CalcSLPrice(true);
   slSell   = CalcSLPrice(false);
   distBuy  = MathAbs(ask - slBuy);
   distSell = MathAbs(bid - slSell);

   // ── Lot sizes (preview based on ACTUAL SL distance) ──
   double avgDist = (distBuy + distSell) / 2.0;
   double avgLot = CalcLot(avgDist);

   // ── Share lot with integrated bots (direct access) ──
   g_panelLot = avgLot;

   // ── BUY / SELL button text (clean, no lot) ──
   ObjectSetString(0, OBJ_BUY_BTN,  OBJPROP_TEXT, "BUY");
   ObjectSetString(0, OBJ_SELL_BTN, OBJPROP_TEXT, "SELL");

   // ── Row 2: Risk | ATR | Spread ──
   double spread = (ask - bid) / _Point;
   ObjectSetString(0, OBJ_SPRD_LBL, OBJPROP_TEXT,
      StringFormat("Risk $%d (%.1f%%) | ATR %.1fx | Spread %.0f", (int)g_riskMoney, g_riskPct, g_atrMult, spread));
   ObjectSetInteger(0, OBJ_SPRD_LBL, OBJPROP_COLOR, COL_DIM);

   // ── Row 1: Position status ──
   g_hasPos = HasOwnPosition();
   if(g_hasPos)
   {
      SyncIfNeeded();
      string dir = g_isBuy ? "LONG" : "SHORT";
      double pnl = GetPositionPnL();
      int nPos = CountOwnPositions();
      double totalLots = GetTotalLots();

      // Left: Lot + Direction (+ DCA count)
      string statusTxt;
      if(nPos > 1)
         statusTxt = StringFormat("%.2f %s | x%d", totalLots, dir, nPos);
      else
         statusTxt = StringFormat("%.2f %s", totalLots, dir);
      ObjectSetString(0, OBJ_STATUS_LBL, OBJPROP_TEXT, statusTxt);
      ObjectSetInteger(0, OBJ_STATUS_LBL, OBJPROP_COLOR,
         g_isBuy ? C'0,180,100' : C'220,80,80');

      // Right: P&L (big, colored)
      ObjectSetString(0, OBJ_RISK_LBL, OBJPROP_TEXT,
         StringFormat("$%+.2f", pnl));
      ObjectSetInteger(0, OBJ_RISK_LBL, OBJPROP_COLOR,
         pnl >= 0 ? COL_PROFIT : COL_LOSS);

      // ── Locked Profit at SL ──
      double lockedPnL = GetLockedPnL();
      ObjectSetString(0, OBJ_LOCK_LBL, OBJPROP_TEXT, "SL Lock");
      ObjectSetInteger(0, OBJ_LOCK_LBL, OBJPROP_COLOR, COL_DIM);
      ObjectSetString(0, OBJ_LOCK_VAL, OBJPROP_TEXT,
         StringFormat("$%+.2f", lockedPnL));
      ObjectSetInteger(0, OBJ_LOCK_VAL, OBJPROP_COLOR,
         lockedPnL >= 0 ? COL_LOCK_UP : COL_LOCK_DN);

      // ── Dynamic button text (info merged into buttons) ──
      if(g_gridEnabled)
      {
         double projRisk = CalcProjectedMaxRisk();
         ObjectSetString(0, OBJ_GRID_BTN, OBJPROP_TEXT,
            StringFormat("Grid DCA: ON | DCA %d/%d | Max $%.0f",
                         g_gridLevel, g_gridMaxLevel, projRisk));
      }
      if(g_autoTPEnabled)
      {
         if(g_tp1Hit)
            ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT, "Auto TP: ON | TP1 \x2713");
         else
         {
            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double totalLot = GetTotalLots();
            if(totalLot <= minLot)
               ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT,
                  StringFormat("Auto TP: ON | Lot min (%.2f)", minLot));
            else
               ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT,
                  StringFormat("Auto TP: ON | 50%%@%.1fx%.1f", g_tpATRFactor, g_atrMult));
         }
      }
      // Clear separate info line (info now on buttons)
      ObjectSetString(0, OBJ_GRID_INFO, OBJPROP_TEXT, " ");
   }
   else
   {
      // No position: show expected lot (left) + SL money (right, prominent)
      double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double slMoney = 0;
      if(tickSz > 0 && tickVal > 0 && avgDist > 0)
         slMoney = avgLot * (avgDist / tickSz) * tickVal;

      // Row 1 Left: Lot size (+ min risk warning)
      double minR = CalcMinRisk();
      if(g_riskMoney < minR && minR > 1)
      {
         ObjectSetString(0, OBJ_STATUS_LBL, OBJPROP_TEXT,
            StringFormat("Lot %.2f (min $%.0f)", avgLot, minR));
         ObjectSetInteger(0, OBJ_STATUS_LBL, OBJPROP_COLOR, C'220,160,0');
      }
      else
      {
         ObjectSetString(0, OBJ_STATUS_LBL, OBJPROP_TEXT,
            StringFormat("Lot %.2f", avgLot));
         ObjectSetInteger(0, OBJ_STATUS_LBL, OBJPROP_COLOR, COL_DIM);
      }

      // Row 1 Right: SL money — prominent red (Exness-style)
      ObjectSetString(0, OBJ_RISK_LBL, OBJPROP_TEXT,
         StringFormat("SL -$%.2f", slMoney));
      ObjectSetInteger(0, OBJ_RISK_LBL, OBJPROP_COLOR, C'230,70,70');

      // Row 1b: RR ratio (left) + TP money (right)
      double tpMoney = 0;
      double tpDist  = g_cachedATR * g_tpATRFactor * g_atrMult;
      if(g_autoTPEnabled && tickSz > 0 && tickVal > 0 && tpDist > 0)
         tpMoney = avgLot * (tpDist / tickSz) * tickVal;

      if(g_autoTPEnabled && tpMoney > 0 && slMoney > 0)
      {
         double rr = tpMoney / slMoney;
         ObjectSetString(0, OBJ_LOCK_LBL, OBJPROP_TEXT,
            StringFormat("RR 1:%.1f", rr));
         ObjectSetInteger(0, OBJ_LOCK_LBL, OBJPROP_COLOR,
            rr >= 1.0 ? C'100,200,120' : C'220,160,0');

         ObjectSetString(0, OBJ_LOCK_VAL, OBJPROP_TEXT,
            StringFormat("TP +$%.2f", tpMoney));
         ObjectSetInteger(0, OBJ_LOCK_VAL, OBJPROP_COLOR, C'100,200,120');
      }
      else if(g_autoTPEnabled)
      {
         ObjectSetString(0, OBJ_LOCK_LBL, OBJPROP_TEXT, "RR --");
         ObjectSetInteger(0, OBJ_LOCK_LBL, OBJPROP_COLOR, COL_DIM);
         ObjectSetString(0, OBJ_LOCK_VAL, OBJPROP_TEXT, "TP --");
         ObjectSetInteger(0, OBJ_LOCK_VAL, OBJPROP_COLOR, COL_DIM);
      }
      else
      {
         ObjectSetString(0, OBJ_LOCK_LBL, OBJPROP_TEXT,
            StringFormat("SL %.1fx ATR", avgDist / MathMax(g_cachedATR, _Point)));
         ObjectSetInteger(0, OBJ_LOCK_LBL, OBJPROP_COLOR, C'220,120,120');
         ObjectSetString(0, OBJ_LOCK_VAL, OBJPROP_TEXT, " ");
         ObjectSetInteger(0, OBJ_LOCK_VAL, OBJPROP_COLOR, COL_DIM);
      }

      // Row 2: Risk info + Grid max risk
      ObjectSetString(0, OBJ_GRID_INFO, OBJPROP_TEXT, " ");
      if(g_gridEnabled)
      {
         double maxRisk = CalcProjectedMaxRisk();
         ObjectSetString(0, OBJ_GRID_BTN, OBJPROP_TEXT,
            StringFormat("Grid DCA: ON | DCA 0/%d | Max $%.0f",
                         g_gridMaxLevel, maxRisk));
         // Show grid max risk in SPRD line for clarity
         ObjectSetString(0, OBJ_SPRD_LBL, OBJPROP_TEXT,
            StringFormat("Risk $%d (%.1f%%) | ATR %.1fx | Grid Max -$%.0f",
                         (int)g_riskMoney, g_riskPct, g_atrMult, maxRisk));
         ObjectSetInteger(0, OBJ_SPRD_LBL, OBJPROP_COLOR, C'200,140,80');
      }

      // Reset tracking
      g_entryPx  = 0;
      g_origSL   = 0;
      g_currentSL = 0;
      g_riskDist  = 0;
      g_tpDist    = 0;
   }

   // ── Update chart SL lines ──
   UpdateChartLines();

   // ── Update TP/Grid chart lines ──
   UpdateTPGridLines();

   // ── Sync button visual state with actual enabled flags ──
   SyncButtonAppearance();

   // ── Title bar: show position info when collapsed ──
   string panelTitle = "Trading Panel v2.32";
   if(g_panelCollapsed)
   {
      if(g_hasPos)
      {
         double pnl2 = GetPositionPnL();
         double lock2 = GetLockedPnL();
         double lots2 = GetTotalLots();
         string dir2 = g_isBuy ? "LONG" : "SHORT";
         ObjectSetString(0, OBJ_TITLE, OBJPROP_TEXT, panelTitle);
         ObjectSetInteger(0, OBJ_TITLE, OBJPROP_COLOR, C'170,180,215');
         // Info row left: lot + direction + P&L
         ObjectSetString(0, OBJ_TITLE_INFO, OBJPROP_TEXT,
            StringFormat("%.2f %s  $%+.2f", lots2, dir2, pnl2));
         ObjectSetInteger(0, OBJ_TITLE_INFO, OBJPROP_COLOR,
            pnl2 >= 0 ? COL_PROFIT : COL_LOSS);
         // Info row right: Lock (muted color)
         ObjectSetString(0, OBJ_TITLE_LOCK, OBJPROP_TEXT,
            StringFormat("Lock $%+.2f", lock2));
         ObjectSetInteger(0, OBJ_TITLE_LOCK, OBJPROP_COLOR,
            lock2 >= 0 ? COL_LOCK_UP : COL_LOCK_DN);
      }
      else
      {
         ObjectSetString(0, OBJ_TITLE, OBJPROP_TEXT, panelTitle);
         ObjectSetInteger(0, OBJ_TITLE, OBJPROP_COLOR, C'170,180,215');
         ObjectSetString(0, OBJ_TITLE_INFO, OBJPROP_TEXT,
            StringFormat("Lot %.2f", avgLot));
         ObjectSetInteger(0, OBJ_TITLE_INFO, OBJPROP_COLOR, COL_DIM);
         ObjectSetString(0, OBJ_TITLE_LOCK, OBJPROP_TEXT, " ");
      }
   }
   else
   {
      ObjectSetString(0, OBJ_TITLE, OBJPROP_TEXT, panelTitle);
      ObjectSetInteger(0, OBJ_TITLE, OBJPROP_COLOR, C'170,180,215');
      ObjectSetString(0, OBJ_TITLE_INFO, OBJPROP_TEXT, " ");
      ObjectSetString(0, OBJ_TITLE_LOCK, OBJPROP_TEXT, " ");
   }

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
   // Lot based on ACTUAL SL distance (entry → SL), so risk is exactly $RiskMoney
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
      g_tpDist    = g_cachedATR * g_tpATRFactor * g_atrMult;  // TP at factor × mult × ATR
      
      // Lock grid ATR if grid enabled at trade entry
      if(g_gridEnabled && g_gridBaseATR <= 0)
      {
         if(g_cachedATR > 0)
            g_gridBaseATR = g_cachedATR;
      }
      // Start DCA delay timer from initial entry
      g_lastDCATime = TimeCurrent();

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
      if((ulong)PositionGetInteger(POSITION_MAGIC)  != g_manageMagic) continue;

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
   g_tpDist    = 0;
}

// ════════════════════════════════════════════════════════════════════
// SL PRICE FROM ENTRY (used by Grid DCA, SyncPosition)
// ════════════════════════════════════════════════════════════════════




double CalcSLPriceFrom(bool isBuy, double entryPrice)
{
   double sl = 0;
   switch(g_slMode)
   {
      case SL_ATR:
      {
         // Use locked grid ATR if available, fallback to live values
         double atrVal = (g_gridBaseATR > 0) ? g_gridBaseATR : g_cachedATR;
         double mult   = g_atrMult;
         if(atrVal > 0)
         {
            double dist = atrVal * mult;
            // When Grid DCA is ON, all intervals equal: spacing = ATR × mult
            // SL = spacing × (maxLevel + 1)
            if(g_gridEnabled)
               dist = atrVal * mult * (g_gridMaxLevel + 1);
            double buffer = dist * InpSLBuffer / 100.0;
            sl = isBuy ? NormPrice(entryPrice - dist - buffer)
                       : NormPrice(entryPrice + dist + buffer);
         }
         break;
      }
      case SL_LOOKBACK:
      {
         int bars = MathMax(InpSLLookback, 3);
         if(isBuy)
         {
            double low = iLow(_Symbol, _Period, 1);
            for(int i = 2; i <= bars; i++)
               low = MathMin(low, iLow(_Symbol, _Period, i));
            double buffer = MathAbs(entryPrice - low) * InpSLBuffer / 100.0;
            sl = NormPrice(low - buffer);
         }
         else
         {
            double high = iHigh(_Symbol, _Period, 1);
            for(int i = 2; i <= bars; i++)
               high = MathMax(high, iHigh(_Symbol, _Period, i));
            double buffer = MathAbs(high - entryPrice) * InpSLBuffer / 100.0;
            sl = NormPrice(high + buffer);
         }
         break;
      }
      case SL_FIXED:
      {
         double dist = InpFixedSLPips * PipSize();
         if(InpSLBuffer > 0) dist *= (1.0 + InpSLBuffer / 100.0);
         sl = isBuy ? NormPrice(entryPrice - dist) : NormPrice(entryPrice + dist);
         break;
      }
   }
   return sl;
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
      if((ulong)PositionGetInteger(POSITION_MAGIC)  != g_manageMagic) continue;

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

   // Check if trail SL has overridden remaining Grid DCA levels
   CheckTrailOverridesGrid();
}

// Check if trailing SL has moved past all remaining Grid DCA levels.
// If so, auto-disable Grid DCA since those levels are unreachable.
void CheckTrailOverridesGrid()
{
   if(!g_gridEnabled) return;
   if(!g_hasPos) return;
   if(g_gridLevel >= g_gridMaxLevel) return;  // all DCA already executed
   if(g_gridBaseATR <= 0) return;

   double spacing = g_gridBaseATR * g_atrMult;  // Grid spacing = ATR × mult
   // Next unexecuted DCA level
   int nextLevel = g_gridLevel + 1;
   double nextDCA = g_isBuy
      ? g_entryPx - nextLevel * spacing
      : g_entryPx + nextLevel * spacing;

   // Has trail SL passed the next DCA level?
   bool overridden = g_isBuy ? (g_currentSL > nextDCA)
                             : (g_currentSL < nextDCA);
   if(!overridden) return;

   // Trail SL has passed DCA level(s) — auto-disable Grid
   // (preserve user intent for next trade)
   g_gridEnabled  = false;
   g_gridLevel    = 0;
   g_gridBaseATR  = 0;

   ObjectSetString (0, OBJ_GRID_BTN, OBJPROP_TEXT, "Grid DCA: OFF (Trail)");
   ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_BGCOLOR, C'60,60,85');
   ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_BORDER_COLOR, C'60,60,85');
   ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_COLOR, C'180,180,200');

   Print(StringFormat("[GRID] Auto-disabled — Trail SL (%s) đã vượt DCA #%d (%s)",
         DoubleToString(g_currentSL, _Digits),
         nextLevel,
         DoubleToString(nextDCA, _Digits)));
}

// Trail SL: dispatches based on g_trailRef (Close/Swing) + g_beEnabled (BE modifier)
// BE Phase 1 (per-tick throttled): Move SL to breakeven
// BE Phase 2 (per-tick): Step ATR (when BE only, no Close/Swing)
// Close/Swing (per-bar): trail based on candle structure
// After BE reached, Close/Swing skip profit gate (already safe at breakeven)
void ManageTrail()
{
   if(!g_hasPos) return;
   if(!g_trailEnabled) return;
   if(g_trailRef == TRAIL_NONE && !g_beEnabled) return;

   if(g_cachedATR <= 0) return;

   // Is this a new bar?
   datetime curBar = iTime(_Symbol, _Period, 0);
   bool isNewBar = (curBar != g_lastBar);

   // Per-tick throttle: limit OrderModify to once per ~3 seconds
   static uint s_lastTrailMs = 0;
   uint nowMs = GetTickCount();
   bool tickAllowed = (nowMs - s_lastTrailMs >= 3000);

   double bid2 = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask2 = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double cur  = g_isBuy ? bid2 : ask2;
   double refEntry = (g_gridEnabled && g_gridLevel > 0) ? GetAvgEntry() : g_entryPx;
   if(refEntry <= 0) refEntry = g_entryPx;
   double moveFromEntry = g_isBuy ? (cur - refEntry) : (refEntry - cur);

   // ═══════════════════════════════════════
   // BE PHASE 1: Move SL to breakeven (when g_beEnabled, not yet reached)
   // ═══════════════════════════════════════
   if(g_beEnabled && !g_beReached)
   {
      if(!tickAllowed) return;

      double fullATR = g_cachedATR * g_atrMult;
      if(fullATR <= 0) return;

      if(moveFromEntry >= g_beStartMult * fullATR)
      {
         double beSL = NormPrice(refEntry);
         bool advance = g_isBuy ? (beSL > g_currentSL) : (beSL < g_currentSL);
         if(advance)
         {
            if(g_isBuy  && beSL >= bid2) return;
            if(!g_isBuy && beSL <= ask2) return;
            g_beReached = true;
            g_beStepLevel = 0;
            s_lastTrailMs = nowMs;
            string phase2Lbl = (g_trailRef == TRAIL_CLOSE) ? "→ Close" :
                               (g_trailRef == TRAIL_SWING) ? "→ Swing" : "→ Step ATR";
            Print(StringFormat("[TRAIL-BE] Phase 1: SL → breakeven %s (profit >= %.1f × ATR) | Next: %s",
                  DoubleToString(beSL, _Digits), g_beStartMult, phase2Lbl));
            ModifySL(beSL);
         }
         else
         {
            g_beReached = true;
            g_beStepLevel = 0;
            Print("[TRAIL-BE] SL already past breakeven — entering Phase 2");
         }
      }
      return;  // Wait for BE before proceeding to Close/Swing
   }

   // ═══════════════════════════════════════
   // BE PHASE 2 (BE only, no Close/Swing): Step SL in ATR increments
   // ═══════════════════════════════════════
   if(g_beEnabled && g_beReached && g_trailRef != TRAIL_CLOSE && g_trailRef != TRAIL_SWING)
   {
      if(!tickAllowed) return;

      double fullATR = g_cachedATR * g_atrMult;
      if(fullATR <= 0) return;

      int reachedLevel = (int)MathFloor((moveFromEntry - fullATR) / fullATR);
      if(reachedLevel <= 0) reachedLevel = 0;
      if(reachedLevel <= g_beStepLevel) return;

      g_beStepLevel = reachedLevel;
      double newSL = g_isBuy
         ? NormPrice(refEntry + g_beStepLevel * fullATR)
         : NormPrice(refEntry - g_beStepLevel * fullATR);

      bool advance = g_isBuy ? (newSL > g_currentSL) : (newSL < g_currentSL);
      if(!advance) return;
      if(g_isBuy  && newSL >= bid2) return;
      if(!g_isBuy && newSL <= ask2) return;

      s_lastTrailMs = nowMs;
      Print(StringFormat("[TRAIL-BE] Phase 2: Step %d → SL=%s (+%d ATR from entry)",
            g_beStepLevel, DoubleToString(newSL, _Digits), g_beStepLevel));
      ModifySL(newSL);
      return;
   }

   // ═══════════════════════════════════════
   // TRAIL_CLOSE / TRAIL_SWING (per-bar)
   // If BE reached → skip profit gate (already safe at breakeven)
   // If no BE → require profit gate (TP factor × ATR)
   // ═══════════════════════════════════════
   if(g_trailRef != TRAIL_CLOSE && g_trailRef != TRAIL_SWING) return;
   if(!isNewBar) return;

   // Profit gate: skip if BE already reached (SL at breakeven = safe zone)
   if(!(g_beEnabled && g_beReached))
   {
      if(moveFromEntry < g_cachedATR * g_tpATRFactor * g_atrMult)
         return;
   }

   double minDist = g_cachedATR * g_atrMult * g_trailMinDist;
   if(minDist <= 0) return;

   double newSL = 0;

   switch(g_trailRef)
   {
      case TRAIL_CLOSE:
      {
         if(g_isBuy)
         {
            newSL = NormPrice(iLow(_Symbol, _Period, 1));
            if((bid2 - newSL) < minDist) return;
         }
         else
         {
            newSL = NormPrice(iHigh(_Symbol, _Period, 1));
            if((newSL - ask2) < minDist) return;
         }
         break;
      }
      case TRAIL_SWING:
      {
         int N = InpTrailLookback;
         if(N < 3) N = 5;
         double swingPrice = 0;

         if(g_isBuy)
         {
            for(int i = 2; i <= N; i++)
            {
               double lo  = iLow(_Symbol, _Period, i);
               double loL = iLow(_Symbol, _Period, i - 1);
               double loR = iLow(_Symbol, _Period, i + 1);
               if(lo < loL && lo < loR)
               {
                  swingPrice = lo;
                  break;
               }
            }
            if(swingPrice <= 0)
            {
               for(int i = 1; i <= N; i++)
               {
                  if(iClose(_Symbol, _Period, i) < iOpen(_Symbol, _Period, i))
                  {
                     swingPrice = iLow(_Symbol, _Period, i);
                     break;
                  }
               }
            }
            if(swingPrice <= 0) return;
            newSL = NormPrice(swingPrice);
            if((bid2 - newSL) < minDist) return;
         }
         else
         {
            for(int i = 2; i <= N; i++)
            {
               double hi  = iHigh(_Symbol, _Period, i);
               double hiL = iHigh(_Symbol, _Period, i - 1);
               double hiR = iHigh(_Symbol, _Period, i + 1);
               if(hi > hiL && hi > hiR)
               {
                  swingPrice = hi;
                  break;
               }
            }
            if(swingPrice <= 0)
            {
               for(int i = 1; i <= N; i++)
               {
                  if(iClose(_Symbol, _Period, i) > iOpen(_Symbol, _Period, i))
                  {
                     swingPrice = iHigh(_Symbol, _Period, i);
                     break;
                  }
               }
            }
            if(swingPrice <= 0) return;
            newSL = NormPrice(swingPrice);
            if((newSL - ask2) < minDist) return;
         }
         break;
      }
      default: return;
   }

   if(newSL <= 0) return;

   bool advance = g_isBuy ? (newSL > g_currentSL)
                           : (newSL < g_currentSL);
   if(!advance) return;

   if(g_isBuy  && newSL >= bid2) return;
   if(!g_isBuy && newSL <= ask2) return;

   ModifySL(newSL);
}

// ════════════════════════════════════════════════════════════════════
// AUTO TP – Partial Take Profit: close 50% at g_tpATRFactor × g_atrMult × ATR
// ════════════════════════════════════════════════════════════════════
// Auto-disable Grid DCA after TP1 — called from both minLot and partial close paths
void DisableGridAfterTP1()
{
   if(!g_gridEnabled) return;
   g_gridEnabled = false;
   g_gridLevel   = 0;
   g_gridBaseATR  = 0;
   ObjectSetString (0, OBJ_GRID_BTN, OBJPROP_TEXT, "Grid DCA: OFF (TP1)");
   ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_BGCOLOR, C'60,60,85');
   ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_BORDER_COLOR, C'60,60,85');
   ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_COLOR, C'180,180,200');
   Print("[GRID] Auto-disabled after TP1 — no more DCA for this trade.");
}

void ManageAutoTP()
{
   if(!g_autoTPEnabled) return;
   if(!g_hasPos) return;
   if(g_tpDist <= 0) return;  // use normal ATR dist, not grid-widened

   // Use average entry for multi-position (grid) scenarios
   double avgEntry = GetAvgEntry();
   if(avgEntry <= 0) return;

   double cur = g_isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double moveFromEntry = g_isBuy ? (cur - avgEntry) : (avgEntry - cur);
   double moveR = moveFromEntry / g_tpDist;  // ratio based on TP distance

   // TP1: 50% at factor × mult × ATR
   if(!g_tp1Hit && moveR >= 1.0)
   {
      // Check if partial close is possible (total lot must be > min lot)
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double totalLot = 0;
      for(int pi = PositionsTotal() - 1; pi >= 0; pi--)
      {
         ulong pt = PositionGetTicket(pi);
         if(pt == 0) continue;
         if(!PositionSelectByTicket(pt)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != g_manageMagic) continue;
         totalLot += PositionGetDouble(POSITION_VOLUME);
      }
      if(totalLot <= minLot)
      {
         // Can't halve min lot — wait for Grid DCA to add more positions
         // Don't mark g_tp1Hit — Auto TP will retry after lot increases
         return;
      }

      Print(StringFormat("[AUTO TP] TP1 hit at %.1fR | Price=%s AvgEntry=%s",
            moveR, DoubleToString(cur, _Digits), DoubleToString(avgEntry, _Digits)));

      if(PartialClosePercent(0.50))
      {
         g_tp1Hit = true;
         Print(StringFormat("[AUTO TP] 50%% closed at TP1 (%.1f×%.1f ATR).", g_tpATRFactor, g_atrMult));
         DisableGridAfterTP1();
      }
   }
}

// ════════════════════════════════════════════════════════════════════
// GRID DCA – Add positions when price moves against us
// ════════════════════════════════════════════════════════════════════
void ManageGrid()
{
   if(!g_gridEnabled) return;
   if(!g_hasPos) return;
   if(g_gridLevel >= g_gridMaxLevel) return;  // max DCA reached

   // Need base ATR to calculate spacing (ATR × mult per DCA level)
   if(g_gridBaseATR <= 0)
   {
      if(g_cachedATR > 0)
         g_gridBaseATR = g_cachedATR;
      else
         return;
   }

   double cur = g_isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Calculate expected DCA level price (ATR × mult spacing)
   double spacing = g_gridBaseATR * g_atrMult;
   int nextLevel = g_gridLevel + 1;
   double dcaPrice = g_isBuy
      ? g_entryPx - nextLevel * spacing
      : g_entryPx + nextLevel * spacing;

   // Check if price reached DCA level
   bool triggered = g_isBuy ? (cur <= dcaPrice) : (cur >= dcaPrice);
   if(!triggered) return;

   // ── Delay filter: skip DCA if too soon after last DCA ──
   if(g_gridDelay > 0 && g_lastDCATime > 0)
   {
      int elapsedSec = (int)(TimeCurrent() - g_lastDCATime);
      int delaySec = g_gridDelay * 60;
      if(elapsedSec < delaySec)
      {
         // Throttle log: only print once per 30 seconds
         static uint s_lastDelayLogMs = 0;
         uint nowMs2 = GetTickCount();
         if(nowMs2 - s_lastDelayLogMs >= 30000)
         {
            s_lastDelayLogMs = nowMs2;
            int remain = delaySec - elapsedSec;
            Print(StringFormat("[GRID] DCA #%d waiting — delay %d/%d sec remaining",
                  nextLevel, remain, delaySec));
         }
         return;
      }
   }

   // ── Candle size filter: skip DCA if current candle is abnormally large (> 2×ATR) ──
   {
      double candleHigh = iHigh(_Symbol, _Period, 0);
      double candleLow  = iLow(_Symbol, _Period, 0);
      double candleSize = candleHigh - candleLow;
      double maxCandle  = g_cachedATR * 2.0;
      if(candleSize > maxCandle && g_cachedATR > 0)
      {
         static uint s_lastCandleLogMs = 0;
         uint nowMs3 = GetTickCount();
         if(nowMs3 - s_lastCandleLogMs >= 30000)
         {
            s_lastCandleLogMs = nowMs3;
            Print(StringFormat("[GRID] DCA #%d skipped — candle %.1f > 2×ATR %.1f (flash move)",
                  nextLevel, candleSize / _Point, maxCandle / _Point));
         }
         return;
      }
   }

   // Calculate lot for DCA position – based on ACTUAL distance from DCA entry to SL
   // SL anchored to ORIGINAL entry, not current price – prevents SL from drifting further
   double sl = CalcSLPriceFrom(g_isBuy, g_entryPx);
   double dist = MathAbs(cur - sl);
   double lot = CalcLot(dist);

   // Safety: check margin
   double margin = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(margin > 0 && margin < 200)
   {
      Print(StringFormat("[GRID] Margin level %.0f%% < 200%% - skip DCA #%d",
            margin, nextLevel));
      return;
   }

   // Execute DCA order
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = g_isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price     = cur;
   req.sl        = sl;
   req.tp        = 0;
   req.magic     = InpMagic;
   req.deviation = InpDeviation;
   req.comment   = StringFormat("DCA #%d", nextLevel);

   if(OrderSend(req, res))
   {
      g_gridLevel = nextLevel;
      g_lastDCATime = TimeCurrent();  // Record DCA fill time for delay filter
      g_beReached = false;  // Reset BE trail — new DCA changes reference entry
      g_beStepLevel = 0;
      double avgEntry = GetAvgEntry();
      Print(StringFormat("[GRID] DCA #%d %s %.2f @ %s | SL=%s | AvgEntry=%s | Total=%.2f",
            nextLevel,
            g_isBuy ? "BUY" : "SELL",
            lot,
            DoubleToString(cur, _Digits),
            DoubleToString(sl, _Digits),
            DoubleToString(avgEntry, _Digits),
            GetTotalLots()));

      // Update riskDist (actual SL distance) – tpDist stays at normal ATR
      g_riskDist = MathAbs(avgEntry - sl);
      
      // Sync all existing positions' SL to the same level
      for(int j = PositionsTotal() - 1; j >= 0; j--)
      {
         ulong t2 = PositionGetTicket(j);
         if(t2 == 0) continue;
         if(!PositionSelectByTicket(t2)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != g_manageMagic) continue;
         if(t2 == res.order) continue;  // skip the one we just opened
         
         double curSL = PositionGetDouble(POSITION_SL);
         if(MathAbs(curSL - sl) < _Point) continue;  // already correct
         
         MqlTradeRequest rq2;
         MqlTradeResult  rs2;
         ZeroMemory(rq2);
         ZeroMemory(rs2);
         rq2.action   = TRADE_ACTION_SLTP;
         rq2.symbol   = _Symbol;
         rq2.position = t2;
         rq2.sl       = sl;
         rq2.tp       = PositionGetDouble(POSITION_TP);
         if(!OrderSend(rq2, rs2))
            Print(StringFormat("[GRID] SL sync FAIL #%d rc=%d", t2, rs2.retcode));
      }
      g_currentSL = sl;
   }
   else
      Print(StringFormat("[GRID] DCA FAIL rc=%d %s", res.retcode, res.comment));
}

// ════════════════════════════════════════════════════════════════════
// SYNC – Recover state if EA restarted with open position
// ════════════════════════════════════════════════════════════════════
void SyncPositionState()
{
   // Find earliest position (original entry) by open time
   datetime earliest = D'3000.01.01';
   ulong earliestTicket = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)        != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)  != g_manageMagic) continue;
      
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(openTime < earliest)
      {
         earliest = openTime;
         earliestTicket = t;
      }
   }
   
   if(earliestTicket == 0) return;  // no position found
   
   if(!PositionSelectByTicket(earliestTicket)) return;

   g_hasPos    = true;
   g_isBuy     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   g_entryPx   = PositionGetDouble(POSITION_PRICE_OPEN);
   g_currentSL = PositionGetDouble(POSITION_SL);
   g_origSL    = g_currentSL;

   // ── Auto-set SL if position has no SL (e.g. opened by Bot) ──
   if(g_currentSL == 0 && g_cachedATR > 0)
   {
      double autoSL = CalcSLPriceFrom(g_isBuy, g_entryPx);
      if(autoSL > 0)
      {
         MqlTradeRequest slReq = {};
         MqlTradeResult  slRes = {};
         slReq.action   = TRADE_ACTION_SLTP;
         slReq.position = earliestTicket;
         slReq.symbol   = _Symbol;
         slReq.sl       = autoSL;
         slReq.tp       = 0;
         if(OrderSend(slReq, slRes) && slRes.retcode == TRADE_RETCODE_DONE)
         {
            g_currentSL = autoSL;
            g_origSL    = autoSL;
            Print(StringFormat("[PANEL] Auto-SL set: %s @ %s  SL=%s",
               g_isBuy ? "BUY" : "SELL",
               DoubleToString(g_entryPx, _Digits),
               DoubleToString(autoSL, _Digits)));
         }
         else
         {
            Print(StringFormat("[PANEL] Auto-SL FAILED: retcode=%d  comment=%s  autoSL=%s  ATR=%.5f",
               slRes.retcode, slRes.comment,
               DoubleToString(autoSL, _Digits), g_cachedATR));
         }
      }
   }

   g_riskDist  = MathAbs(g_entryPx - g_currentSL);
   if(g_tpDist <= 0)
      g_tpDist = g_cachedATR * g_tpATRFactor * g_atrMult;  // TP at factor × mult × ATR

   // Lock grid ATR/mult if grid enabled but not yet locked
   // Lock grid ATR if grid enabled but not yet locked
   // (covers pending order fill scenario where ExecuteTrade was never called)
   if(g_gridEnabled && g_gridBaseATR <= 0)
   {
      if(g_cachedATR > 0)
         g_gridBaseATR = g_cachedATR;
   }
   // Start DCA delay timer from position sync
   if(g_lastDCATime == 0)
      g_lastDCATime = TimeCurrent();

   Print(StringFormat("[PANEL] Synced position: %s @ %s  SL=%s  (earliest of %d)",
      g_isBuy ? "BUY" : "SELL",
      DoubleToString(g_entryPx, _Digits),
      DoubleToString(g_currentSL, _Digits),
      CountOwnPositions()));
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
   ObjectSetInteger(0, OBJ_THEME_BTN, OBJPROP_STATE, false);
   if(g_theme == 0) // Dark
   {
      ObjectSetString (0, OBJ_THEME_BTN, OBJPROP_TEXT, "Dark");
      ObjectSetInteger(0, OBJ_THEME_BTN, OBJPROP_BGCOLOR, C'40,40,55');
      ObjectSetInteger(0, OBJ_THEME_BTN, OBJPROP_BORDER_COLOR, C'40,40,55');
      ObjectSetInteger(0, OBJ_THEME_BTN, OBJPROP_COLOR, COL_BTN_TXT);
   }
   else // Light
   {
      ObjectSetString (0, OBJ_THEME_BTN, OBJPROP_TEXT, "Light");
      ObjectSetInteger(0, OBJ_THEME_BTN, OBJPROP_BGCOLOR, C'200,200,210');
      ObjectSetInteger(0, OBJ_THEME_BTN, OBJPROP_BORDER_COLOR, C'200,200,210');
      ObjectSetInteger(0, OBJ_THEME_BTN, OBJPROP_COLOR, C'30,30,40');
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

// ════════════════════════════════════════════════════════════════════
// EVENT HANDLERS
// ════════════════════════════════════════════════════════════════════
int OnInit()
{
   // ATR handle
   g_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
      Print("[PANEL] Warning: iATR handle failed");

   g_riskPct     = 1.0;              // Default 1%
   g_riskPctMode = true;             // Default %Auto mode
   double initBal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_riskMoney = (initBal > 0) ? MathMax(1, MathFloor(initBal * g_riskPct / 100.0)) : InpDefaultRisk;
   g_atrMult   = InpATRMult;
   g_slMode    = SL_ATR;  // Always ATR mode
   g_manageMagic = (InpManageMagic > 0) ? InpManageMagic : InpMagic;
   g_gridMaxLevel = MathMax(2, MathMin(5, InpGridMaxLevel));  // Clamp 2-5

   // ── Defaults: AutoTP 1, Grid DCA x2 5m, Trail SL Swing, Bot CC ──
   g_autoTPEnabled  = true;
   g_tpATRFactor    = 1.0;
   g_gridEnabled    = true;
   g_gridUserEnabled = true;
   g_gridMaxLevel   = 2;
   g_gridDelay      = 5;
   // Map input trail mode to internal state (method + BE toggle)
   // g_trailEnabled is derived in SyncButtonAppearance()
   switch(InpTrailMode)
   {
      case TRAIL_CLOSE:    g_trailRef = TRAIL_CLOSE; g_beEnabled = false; break;
      case TRAIL_SWING:    g_trailRef = TRAIL_SWING; g_beEnabled = false; break;
      case TRAIL_BE_CLOSE: g_trailRef = TRAIL_CLOSE; g_beEnabled = true;  break;
      case TRAIL_BE_SWING: g_trailRef = TRAIL_SWING; g_beEnabled = true;  break;
      case TRAIL_BE:       g_trailRef = TRAIL_NONE;  g_beEnabled = true;  break;
      case TRAIL_NONE:     g_trailRef = TRAIL_NONE;  g_beEnabled = false; break;
      default:             g_trailRef = TRAIL_SWING; g_beEnabled = false; break;
   }
   g_trailEnabled = (g_trailRef != TRAIL_NONE || g_beEnabled);
   g_activeBot      = 1;   // Show CC panel by default
   // Bots start stopped — user presses Start
   cc_enabled       = false;
   ns_enabled       = false;

   // Recover if EA restarted with open position
   SyncPositionState();

   // Theme
   ApplyDarkTheme();

   // Build panel
   CreatePanel();
   UpdatePanel();

   // ── Initialize integrated bots ──
   CC_Init();
   NS_Init();
   SR_Init();

   // Timer for updates when market is slow
   EventSetMillisecondTimer(1000);

   Print(StringFormat("[PANEL] Tuan Quick Trade v2.32 | %s | Risk=$%.2f | SL=ATR | Trail=%s%s",
      _Symbol,
      InpDefaultRisk,
      EnumToString(g_trailRef),
      g_beEnabled ? "+BE" : ""));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   CC_Deinit();
   NS_Deinit();
   SR_Deinit();
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
   // ── Fast-path: detect Start/Stop button click during OnTick ──
   // OBJPROP_STATE is set immediately on click (before OnChartEvent queues)
   // This makes Start/Stop respond within the current tick, not next event cycle
   if(ObjectGetInteger(0, OBJ_BOT_START_BTN, OBJPROP_STATE) != 0)
   {
      ObjectSetInteger(0, OBJ_BOT_START_BTN, OBJPROP_STATE, false);
      ToggleBotStart();
   }

   // ── Cache ATR once per tick (avoid multiple CopyBuffer calls) ──
   {
      double atr[1];
      if(g_atrHandle != INVALID_HANDLE && CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1)
         g_cachedATR = atr[0];
   }

   // Detect position closed externally (SL hit, etc.)
   if(g_hasPos && !HasOwnPosition())
   {
      // ── Detect loss scenarios that should pause bots ──
      // Check BEFORE resetting state
      bool wasGridMax = (g_gridEnabled && g_gridLevel >= g_gridMaxLevel);
      bool wasTrailProfit = g_beReached || (g_isBuy ? (g_currentSL > g_entryPx) : (g_currentSL < g_entryPx && g_currentSL > 0));
      bool noGridEffect = (!g_gridEnabled || g_gridLevel == 0);
      bool slUnmoved = (g_origSL > 0 && MathAbs(g_currentSL - g_origSL) < _Point);

      // Case 1: Grid DCA maxed out + loss → "Large SL"
      if(wasGridMax && !wasTrailProfit)
      {
         datetime pauseTs = (datetime)TimeCurrent();
         if(cc_enabled) CC_SetPaused(pauseTs);
         if(ns_enabled) NS_SetPaused(pauseTs);
         Print(StringFormat("[PANEL] ⚠ LARGE SL detected — Grid DCA %d/%d maxed | Bots paused",
               g_gridLevel, g_gridMaxLevel));
      }
      // Case 2: No Grid + SL never moved + no trailing profit → "Plain SL hit"
      else if(noGridEffect && slUnmoved && !wasTrailProfit)
      {
         datetime pauseTs = (datetime)TimeCurrent();
         if(cc_enabled) CC_SetPaused(pauseTs);
         if(ns_enabled) NS_SetPaused(pauseTs);
         Print("[PANEL] ⚠ SL hit (no Grid, SL unmoved) — Bots paused");
      }
      else
      {
         Print(StringFormat("[PANEL] Position closed — Grid=%d/%d, TrailProfit=%s, SLMoved=%s",
               g_gridLevel, g_gridMaxLevel, wasTrailProfit ? "Yes" : "No",
               slUnmoved ? "No" : "Yes"));
      }

      g_hasPos    = false;
      g_entryPx   = 0;
      g_origSL    = 0;
      g_currentSL = 0;
      g_riskDist  = 0;
      g_tpDist    = 0;
      g_tp1Hit    = false;
      g_gridLevel = 0;
      g_gridBaseATR = 0;
      g_lastDCATime = 0;
      // Restore grid to user's intended state
      g_gridEnabled = g_gridUserEnabled;
      g_beReached = false;
      g_beStepLevel = 0;
   }

   // Detect new position opened externally (Bot, manual, etc.)
   if(!g_hasPos && HasOwnPosition())
   {
      SyncPositionState();
   }

   // Persistent SL fix: retry auto-SL if position still has SL=0
   if(g_hasPos && g_currentSL == 0 && g_cachedATR > 0)
   {
      // Find the actual position ticket to modify
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(!PositionSelectByTicket(t)) continue;
         if(PositionGetString(POSITION_SYMBOL)       != _Symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != g_manageMagic) continue;

         double posSL = PositionGetDouble(POSITION_SL);
         if(posSL == 0)
         {
            double autoSL = CalcSLPriceFrom(g_isBuy, g_entryPx);
            if(autoSL > 0)
            {
               MqlTradeRequest slReq = {};
               MqlTradeResult  slRes = {};
               slReq.action   = TRADE_ACTION_SLTP;
               slReq.position = t;
               slReq.symbol   = _Symbol;
               slReq.sl       = autoSL;
               slReq.tp       = 0;
               if(OrderSend(slReq, slRes) && slRes.retcode == TRADE_RETCODE_DONE)
               {
                  g_currentSL = autoSL;
                  g_origSL    = autoSL;
                  g_riskDist  = MathAbs(g_entryPx - autoSL);
                  Print(StringFormat("[PANEL] Auto-SL retry OK: %s SL=%s",
                     g_isBuy ? "BUY" : "SELL",
                     DoubleToString(autoSL, _Digits)));
               }
            }
         }
         break;  // Only fix the earliest/first position
      }
   }

   // Auto trailing
   ManageTrail();

   // Auto TP (partial close at TP ATR factor)
   ManageAutoTP();

   // Grid DCA (add positions on adverse move)
   ManageGrid();

   // Track bar changes (AFTER trail + auto, so candle logic works on 1st tick)
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar != g_lastBar)
      g_lastBar = curBar;

   // Throttled panel update (every 1000 ms — avoid starving OnChartEvent)
   static uint lastMs = 0;
   uint now = GetTickCount();
   if(now - lastMs >= 1000)
   {
      UpdatePanel();
      lastMs = now;
   }

   // ── Dispatch to ALL running bots (independent of view) ──
   if(cc_enabled) CC_Tick();
   if(ns_enabled) NS_Tick();
   if(sr_enabled) SR_Tick();
}

void OnTimer()
{
   // Only update panel if no ticks in last 2s (weekend/closed market fallback)
   static uint s_lastTickMs = 0;
   uint now2 = GetTickCount();
   if(now2 - s_lastTickMs >= 2000)
      UpdatePanel();
   s_lastTickMs = now2;

   // ── Dispatch to ALL running bots + update viewed bot panel ──
   if(cc_enabled) CC_Timer();
   if(ns_enabled) NS_Timer();
   if(sr_enabled) SR_Timer();
   // If viewing a non-running bot, still update its panel display
   if(g_activeBot == 1 && !cc_enabled) CC_UpdatePanel();
   if(g_activeBot == 2 && !ns_enabled) NS_UpdatePanel();
   if(g_activeBot == 3 && !sr_enabled) SR_UpdatePanel();

   // ── Auto‐Regime: check config file every 60s ──
   if(g_autoRegime)
   {
      static uint s_lastRegimeMs = 0;
      uint nowMs = GetTickCount();
      if(nowMs - s_lastRegimeMs >= 60000 || s_lastRegimeMs == 0)
      {
         ReadConfigINI();
         s_lastRegimeMs = nowMs;
      }
   }
}

void OnChartEvent(const int id,
                  const long   &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // ── Collapse/Expand Panel ──
      if(sparam == OBJ_COLLAPSE_BTN)
      {
         ObjectSetInteger(0, OBJ_COLLAPSE_BTN, OBJPROP_STATE, false);
         TogglePanelCollapse();
         UpdatePanel();  // Immediately refresh title bar text
         return;
      }
      if(sparam == OBJ_LINES_BTN)
      {
         ObjectSetInteger(0, OBJ_LINES_BTN, OBJPROP_STATE, false);
         ToggleChartLines();
         return;
      }

      // ── Bot toggle buttons ──
      if(sparam == OBJ_BOT_CC_BTN)
      {
         ObjectSetInteger(0, OBJ_BOT_CC_BTN, OBJPROP_STATE, false);
         ToggleBot(1);
         return;
      }
      if(sparam == OBJ_BOT_NS_BTN)
      {
         ObjectSetInteger(0, OBJ_BOT_NS_BTN, OBJPROP_STATE, false);
         ToggleBot(2);
         return;
      }
      if(sparam == OBJ_BOT_SR_BTN)
      {
         ObjectSetInteger(0, OBJ_BOT_SR_BTN, OBJPROP_STATE, false);
         ToggleBot(3);
         return;
      }
      // ── Bot Start/Stop button ──
      if(sparam == OBJ_BOT_START_BTN)
      {
         ObjectSetInteger(0, OBJ_BOT_START_BTN, OBJPROP_STATE, false);
         ToggleBotStart();
         return;
      }
      // ── Auto‐Regime toggle ──
      if(sparam == OBJ_BOT_AUTO_BTN)
      {
         ObjectSetInteger(0, OBJ_BOT_AUTO_BTN, OBJPROP_STATE, false);
         g_autoRegime = !g_autoRegime;
         if(g_autoRegime)
         {
            g_lastConfigMod = 0;   // force re-read
            ReadConfigINI();
            Print("[REGIME] Auto‐regime ON");
         }
         else
         {
            // Reset shadows to input defaults
            cc_atrMinMult  = InpCC_ATRMinMult;
            cc_breakMult   = InpCC_BreakMult;
            g_atrMult      = InpATRMult;
            g_beStartMult  = 1.0;
            g_trailMinDist = 0.5;
            g_tpATRFactor  = 1.0;
            g_regimeName   = "";
            g_regimeConf   = 0;
            ObjectSetString(0, OBJ_SET_ATR_EDT, OBJPROP_TEXT, StringFormat("%.1f", g_atrMult));
            Print("[REGIME] Auto‐regime OFF — params reset to inputs");
         }
         // Refresh auto button appearance
         color autoBg  = g_autoRegime ? C'120,80,0' : C'50,50,70';
         color autoTxt = g_autoRegime ? C'255,255,255' : C'140,140,160';
         string autoLbl = g_autoRegime ? "\x2699 Auto ON" : "\x2699 Auto";
         ObjectSetString(0, OBJ_BOT_AUTO_BTN, OBJPROP_TEXT, autoLbl);
         ObjectSetInteger(0, OBJ_BOT_AUTO_BTN, OBJPROP_BGCOLOR, autoBg);
         ObjectSetInteger(0, OBJ_BOT_AUTO_BTN, OBJPROP_COLOR, autoTxt);
         ChartRedraw(0);
         return;
      }

      // ── Settings panel toggle ──
      if(sparam == OBJ_SETTINGS_BTN)
      {
         ObjectSetInteger(0, OBJ_SETTINGS_BTN, OBJPROP_STATE, false);
         ToggleSettings();
         return;
      }
      // ── Settings: Risk $ ± (jump to next/prev 0.01 lot level) → switch to $Fixed mode ──
      if(sparam == OBJ_SET_RISK_PLUS)
      {
         ObjectSetInteger(0, OBJ_SET_RISK_PLUS, OBJPROP_STATE, false);
         g_riskPctMode = false;
         double slDist   = g_cachedATR * g_atrMult;
         double curLot   = CalcLot(slDist);
         double volStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         double nextLot  = curLot + volStep;
         g_riskMoney = CalcRiskForLot(nextLot);
         // Sync % from $
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         if(bal > 0) g_riskPct = NormalizeDouble(g_riskMoney / bal * 100.0, 1);
         ObjectSetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT, IntegerToString((int)g_riskMoney));
         ObjectSetString(0, OBJ_SET_PCT_EDT, OBJPROP_TEXT, StringFormat("%.1f", g_riskPct));
         UpdateModeColors();
         UpdatePanel();
         return;
      }
      if(sparam == OBJ_SET_RISK_MINUS)
      {
         ObjectSetInteger(0, OBJ_SET_RISK_MINUS, OBJPROP_STATE, false);
         g_riskPctMode = false;
         double slDist   = g_cachedATR * g_atrMult;
         double curLot   = CalcLot(slDist);
         double volStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double prevLot  = MathMax(minLot, curLot - volStep);
         // Use MathFloor (not MathCeil) so risk actually decreases for the smaller lot
         double tickSz   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         if(tickSz > 0 && tickVal > 0 && slDist > 0)
            g_riskMoney = MathMax(1, MathFloor(prevLot * (slDist / tickSz) * tickVal));
         else
            g_riskMoney = MathMax(1, g_riskMoney - 1);
         // Sync % from $
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         if(bal > 0) g_riskPct = NormalizeDouble(g_riskMoney / bal * 100.0, 1);
         ObjectSetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT, IntegerToString((int)g_riskMoney));
         ObjectSetString(0, OBJ_SET_PCT_EDT, OBJPROP_TEXT, StringFormat("%.1f", g_riskPct));
         UpdateModeColors();
         UpdatePanel();
         return;
      }
      // ── Settings: Risk % ± (jump to next/prev 0.01 lot level) → switch to %Auto mode ──
      if(sparam == OBJ_SET_PCT_PLUS)
      {
         ObjectSetInteger(0, OBJ_SET_PCT_PLUS, OBJPROP_STATE, false);
         g_riskPctMode = true;
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         double slDist   = g_cachedATR * g_atrMult;
         double curLot   = CalcLot(slDist);
         double volStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         double nextLot  = curLot + volStep;
         double targetRisk = CalcRiskForLot(nextLot);
         g_riskMoney = targetRisk;
         // Sync % from $
         if(bal > 0) g_riskPct = MathMin(100.0, NormalizeDouble(g_riskMoney / bal * 100.0, 1));
         ObjectSetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT, IntegerToString((int)g_riskMoney));
         ObjectSetString(0, OBJ_SET_PCT_EDT, OBJPROP_TEXT, StringFormat("%.1f", g_riskPct));
         UpdateModeColors();
         UpdatePanel();
         return;
      }
      if(sparam == OBJ_SET_PCT_MINUS)
      {
         ObjectSetInteger(0, OBJ_SET_PCT_MINUS, OBJPROP_STATE, false);
         g_riskPctMode = true;
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         double slDist   = g_cachedATR * g_atrMult;
         double curLot   = CalcLot(slDist);
         double volStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double prevLot  = MathMax(minLot, curLot - volStep);
         // Use MathFloor so risk actually decreases
         double tickSz   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         if(tickSz > 0 && tickVal > 0 && slDist > 0)
            g_riskMoney = MathMax(1, MathFloor(prevLot * (slDist / tickSz) * tickVal));
         else
            g_riskMoney = MathMax(1, g_riskMoney - 1);
         // Sync % from $
         if(bal > 0) g_riskPct = MathMax(0.1, NormalizeDouble(g_riskMoney / bal * 100.0, 1));
         ObjectSetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT, IntegerToString((int)g_riskMoney));
         ObjectSetString(0, OBJ_SET_PCT_EDT, OBJPROP_TEXT, StringFormat("%.1f", g_riskPct));
         UpdateModeColors();
         UpdatePanel();
         return;
      }
      // ── Settings: Mode toggle buttons ──
      if(sparam == OBJ_SET_MODE_DOLLAR)
      {
         ObjectSetInteger(0, OBJ_SET_MODE_DOLLAR, OBJPROP_STATE, false);
         g_riskPctMode = false;
         UpdateModeColors();
         UpdatePanel();
         return;
      }
      if(sparam == OBJ_SET_MODE_PCT)
      {
         ObjectSetInteger(0, OBJ_SET_MODE_PCT, OBJPROP_STATE, false);
         g_riskPctMode = true;
         // Recalc $ from current %
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         if(bal > 0) g_riskMoney = MathMax(1, MathFloor(bal * g_riskPct / 100.0));
         ObjectSetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT, IntegerToString((int)g_riskMoney));
         UpdateModeColors();
         UpdatePanel();
         return;
      }
      // ── Settings: ATR ±0.5 (snap to nearest 0.5 step) ──
      if(sparam == OBJ_SET_ATR_PLUS)
      {
         ObjectSetInteger(0, OBJ_SET_ATR_PLUS, OBJPROP_STATE, false);
         // Snap up: 1.0→1.5, 1.1→1.5, 1.5→2.0
         g_atrMult = MathMin(5.0, MathCeil(g_atrMult * 2.0 + 0.001) / 2.0);
         ObjectSetString(0, OBJ_SET_ATR_EDT, OBJPROP_TEXT, StringFormat("%.1f", g_atrMult));
         // Recalc TP distance with new mult
         if(g_hasPos && g_cachedATR > 0 && !g_tp1Hit)
            g_tpDist = g_cachedATR * g_tpATRFactor * g_atrMult;
         UpdatePanel();
         return;
      }
      if(sparam == OBJ_SET_ATR_MINUS)
      {
         ObjectSetInteger(0, OBJ_SET_ATR_MINUS, OBJPROP_STATE, false);
         // Snap down: 1.0→0.5, 1.1→1.0, 1.5→1.0
         g_atrMult = MathMax(0.5, MathFloor(g_atrMult * 2.0 - 0.001) / 2.0);
         ObjectSetString(0, OBJ_SET_ATR_EDT, OBJPROP_TEXT, StringFormat("%.1f", g_atrMult));
         // Recalc TP distance with new mult
         if(g_hasPos && g_cachedATR > 0 && !g_tp1Hit)
            g_tpDist = g_cachedATR * g_tpATRFactor * g_atrMult;
         UpdatePanel();
         return;
      }
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
      // ── CLOSE 50% ──
      else if(sparam == OBJ_CLOSE50_BTN)
      {
         ObjectSetInteger(0, OBJ_CLOSE50_BTN, OBJPROP_STATE, false);
         if(g_hasPos)
         {
            if(PartialClosePercent(0.50))
               Print("[PANEL] Closed 50% of positions");
            else
               Print("[PANEL] Close 50% failed (lot too small?)");
         }
      }
      // ── CLOSE 75% ──
      else if(sparam == OBJ_CLOSE75_BTN)
      {
         ObjectSetInteger(0, OBJ_CLOSE75_BTN, OBJPROP_STATE, false);
         if(g_hasPos)
         {
            if(PartialClosePercent(0.75))
               Print("[PANEL] Closed 75% of positions");
            else
               Print("[PANEL] Close 75% failed (lot too small?)");
         }
      }
      // ── CLOSE ALL ──
      else if(sparam == OBJ_CLOSE_BTN)
      {
         ObjectSetInteger(0, OBJ_CLOSE_BTN, OBJPROP_STATE, false);
         CloseAllPositions();

         // Reset Auto TP state
         g_tp1Hit = false;
         if(g_autoTPEnabled)
            ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT,
               StringFormat("Auto TP: ON | 50%%@%.1fx%.1f", g_tpATRFactor, g_atrMult));

         // Reset Grid DCA state
         g_gridLevel   = 0;
         g_gridBaseATR = 0;
         g_lastDCATime = 0;

         // Reset Trail state
         g_beReached = false;
         g_beStepLevel = 0;
         if(g_gridEnabled)
         {
            double maxRisk = CalcProjectedMaxRisk();
            ObjectSetString(0, OBJ_GRID_BTN, OBJPROP_TEXT,
               StringFormat("Grid DCA: ON | DCA 0/%d | Max $%.0f",
                            g_gridMaxLevel, maxRisk));
         }

         // Clear chart lines
         HideHLine(OBJ_TP1_LINE);
         HideHLine(OBJ_TRAIL_START);
         HideHLine(OBJ_DCA1_LINE);
         HideHLine(OBJ_DCA2_LINE);
         HideHLine(OBJ_DCA3_LINE);
         HideHLine(OBJ_DCA4_LINE);
         HideHLine(OBJ_DCA5_LINE);
         HideHLine(OBJ_AVG_ENTRY);
         ObjectSetString(0, OBJ_GRID_INFO, OBJPROP_TEXT, " ");
      }
      // ── Trail method: Close (toggle — click again to deselect) ──
      else if(sparam == OBJ_TM_CLOSE)
      {
         ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_STATE, false);
         if(g_trailRef == TRAIL_CLOSE)
            g_trailRef = TRAIL_NONE;   // deselect
         else
            g_trailRef = TRAIL_CLOSE;  // select (deselects Swing)
         Print(StringFormat("[TRAIL] Method → %s%s",
               (g_trailRef == TRAIL_CLOSE) ? "Close" : "None",
               g_beEnabled ? " (+BE)" : ""));
         UpdateTrailParamDisplay();
      }
      // ── Trail method: Swing (toggle — click again to deselect) ──
      else if(sparam == OBJ_TM_SWING)
      {
         ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_STATE, false);
         if(g_trailRef == TRAIL_SWING)
            g_trailRef = TRAIL_NONE;   // deselect
         else
            g_trailRef = TRAIL_SWING;  // select (deselects Close)
         Print(StringFormat("[TRAIL] Method → %s%s",
               (g_trailRef == TRAIL_SWING) ? "Swing" : "None",
               g_beEnabled ? " (+BE)" : ""));
         UpdateTrailParamDisplay();
      }
      // ── Trail modifier: BE (toggle on/off, combinable with Close/Swing) ──
      else if(sparam == OBJ_TM_BE)
      {
         ObjectSetInteger(0, OBJ_TM_BE, OBJPROP_STATE, false);
         g_beEnabled = !g_beEnabled;
         g_beReached = false;
         g_beStepLevel = 0;
         string methodLbl = (g_trailRef == TRAIL_CLOSE) ? "+Close" :
                            (g_trailRef == TRAIL_SWING) ? "+Swing" : " only";
         Print(StringFormat("[TRAIL] BE %s%s (start %.1fx ATR)",
               g_beEnabled ? "ON" : "OFF", g_beEnabled ? methodLbl : "", g_beStartMult));
         UpdateTrailParamDisplay();
      }
      // ── Trail param: minus ──
      else if(sparam == OBJ_TRAIL_MINUS)
      {
         ObjectSetInteger(0, OBJ_TRAIL_MINUS, OBJPROP_STATE, false);
         if(g_beEnabled)
         { g_beStartMult = MathMax(0.1, g_beStartMult - 0.1); }
         else
         { g_trailMinDist = MathMax(0.1, g_trailMinDist - 0.1); }
         UpdateTrailParamDisplay();
      }
      // ── Trail param: plus ──
      else if(sparam == OBJ_TRAIL_PLUS)
      {
         ObjectSetInteger(0, OBJ_TRAIL_PLUS, OBJPROP_STATE, false);
         if(g_beEnabled)
         { g_beStartMult = MathMin(3.0, g_beStartMult + 0.1); }
         else
         { g_trailMinDist = MathMin(3.0, g_trailMinDist + 0.1); }
         UpdateTrailParamDisplay();
      }
      // ── Grid DCA toggle ──
      else if(sparam == OBJ_GRID_BTN)
      {
         g_gridEnabled = !g_gridEnabled;
         g_gridUserEnabled = g_gridEnabled;  // Track user's manual intent
         ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_STATE, false);
         if(g_gridEnabled)
         {
            // Lock grid ATR only if we have an open position
            // (no position = values locked later in ExecuteTrade)
            if(g_hasPos)
            {
               if(g_cachedATR > 0)
                  g_gridBaseATR = g_cachedATR;
            }
            
            // If already in position, count existing DCA positions
            if(g_hasPos)
            {
               int nPos = CountOwnPositions();
               g_gridLevel = MathMax(0, nPos - 1);  // entry doesn't count as DCA
               Print(StringFormat("[GRID] Detected %d existing positions → gridLevel=%d",
                     nPos, g_gridLevel));
            }
            else
               g_gridLevel = 0;

            double maxRisk = CalcProjectedMaxRisk();
            ObjectSetString (0, OBJ_GRID_BTN, OBJPROP_TEXT,
               StringFormat("Grid DCA: ON | DCA 0/%d | Max $%.0f",
                            g_gridMaxLevel, maxRisk));
            ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_BGCOLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_BORDER_COLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_COLOR, COL_WHITE);

            // Warning about total risk
            Print(StringFormat("[GRID] WARNING: Max total risk = $%.0f (projected with min-lot clipping)",
                  maxRisk));
            Print(StringFormat("[GRID] ENABLED | Max=%d Spacing=%.1fxATR | SL = %dx spacing",
                  g_gridMaxLevel, g_atrMult, g_gridMaxLevel + 1));

            // Widen SL on existing positions to accommodate grid levels
            if(g_hasPos)
            {
               double newSL = CalcSLPriceFrom(g_isBuy, g_entryPx);
               for(int i = PositionsTotal() - 1; i >= 0; i--)
               {
                  ulong ticket = PositionGetTicket(i);
                  if(ticket == 0) continue;
                  if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
                  if(PositionGetInteger(POSITION_MAGIC) != g_manageMagic) continue;
                  double curSL = PositionGetDouble(POSITION_SL);
                  // Only widen, never tighten
                  bool shouldUpdate = g_isBuy ? (newSL < curSL || curSL == 0)
                                              : (newSL > curSL || curSL == 0);
                  if(shouldUpdate)
                  {
                     MqlTradeRequest mreq;
                     MqlTradeResult  mres;
                     ZeroMemory(mreq);
                     ZeroMemory(mres);
                     mreq.action   = TRADE_ACTION_SLTP;
                     mreq.position = ticket;
                     mreq.symbol   = _Symbol;
                     mreq.sl       = newSL;
                     mreq.tp       = PositionGetDouble(POSITION_TP);
                     if(OrderSend(mreq, mres))
                        Print(StringFormat("[GRID] SL widened ticket #%d → %s",
                              ticket, DoubleToString(newSL, _Digits)));
                     else
                        Print(StringFormat("[GRID] SL modify FAIL ticket #%d rc=%d",
                              ticket, mres.retcode));
                  }
               }
               g_origSL    = newSL;
               g_currentSL = newSL;
               g_riskDist  = MathAbs(g_entryPx - newSL);
               // Set tpDist to raw ATR for Auto TP calcs (if not already set)
               if(g_tpDist <= 0)
                  g_tpDist = g_cachedATR * g_tpATRFactor * g_atrMult;
            }
         }
         else
         {
            ObjectSetString (0, OBJ_GRID_BTN, OBJPROP_TEXT, "Grid DCA: OFF");
            ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_BGCOLOR, C'60,60,85');
            ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_BORDER_COLOR, C'60,60,85');
            ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_COLOR, C'180,180,200');
            g_gridLevel   = 0;
            g_gridBaseATR = 0;
            // Narrow SL back to normal on existing positions
            if(g_hasPos)
            {
               double newSL = CalcSLPriceFrom(g_isBuy, g_entryPx);  // normal dist from original entry
               for(int i = PositionsTotal() - 1; i >= 0; i--)
               {
                  ulong ticket = PositionGetTicket(i);
                  if(ticket == 0) continue;
                  if(!PositionSelectByTicket(ticket)) continue;
                  if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
                  if((ulong)PositionGetInteger(POSITION_MAGIC) != g_manageMagic) continue;
                  
                  MqlTradeRequest mreq;
                  MqlTradeResult  mres;
                  ZeroMemory(mreq);
                  ZeroMemory(mres);
                  mreq.action   = TRADE_ACTION_SLTP;
                  mreq.position = ticket;
                  mreq.symbol   = _Symbol;
                  mreq.sl       = newSL;
                  mreq.tp       = PositionGetDouble(POSITION_TP);
                  if(!OrderSend(mreq, mres))
                     Print(StringFormat("[GRID] SL narrow FAIL #%d rc=%d", ticket, mres.retcode));
               }
               g_currentSL = newSL;
               g_origSL    = newSL;
               g_riskDist  = MathAbs(g_entryPx - newSL);
               Print(StringFormat("[GRID] SL narrowed to normal: %s",
                     DoubleToString(newSL, _Digits)));
            }
            // Clean up DCA lines
            HideHLine(OBJ_DCA1_LINE);
            HideHLine(OBJ_DCA2_LINE);
            HideHLine(OBJ_DCA3_LINE);
            HideHLine(OBJ_DCA4_LINE);
            HideHLine(OBJ_DCA5_LINE);
            HideHLine(OBJ_AVG_ENTRY);
            ObjectSetString(0, OBJ_GRID_INFO, OBJPROP_TEXT, " ");
            Print("[GRID] DISABLED");
         }
      }
      // ── Grid DCA level cycle: 2→3→4→5→2 ──
      else if(sparam == OBJ_GRID_LVL)
      {
         ObjectSetInteger(0, OBJ_GRID_LVL, OBJPROP_STATE, false);
         // Only allow change when no position (grid spacing locked during trade)
         if(g_hasPos && g_gridEnabled)
         {
            Print("[GRID] Cannot change max level while grid is active with positions.");
         }
         else
         {
            g_gridMaxLevel = (g_gridMaxLevel >= 5) ? 2 : g_gridMaxLevel + 1;
            ObjectSetString(0, OBJ_GRID_LVL, OBJPROP_TEXT,
               StringFormat("x%d", g_gridMaxLevel));
            Print(StringFormat("[GRID] Max level → %d", g_gridMaxLevel));
            // Refresh grid button text if grid is enabled
            if(g_gridEnabled)
            {
               double maxRisk = CalcProjectedMaxRisk();
               ObjectSetString(0, OBJ_GRID_BTN, OBJPROP_TEXT,
                  StringFormat("Grid DCA: ON | DCA %d/%d | Max $%.0f",
                               g_gridLevel, g_gridMaxLevel, maxRisk));
            }
         }
      }
      // ── Grid DCA delay cycle: 0→3→5→10→15→0 ──
      else if(sparam == OBJ_GRID_DLY)
      {
         ObjectSetInteger(0, OBJ_GRID_DLY, OBJPROP_STATE, false);
         int delays[] = {0, 3, 5, 10, 15};
         int numDelays = ArraySize(delays);
         int nextIdx = 0;
         for(int i = 0; i < numDelays; i++)
         {
            if(g_gridDelay == delays[i])
            {
               nextIdx = (i + 1) % numDelays;
               break;
            }
         }
         g_gridDelay = delays[nextIdx];
         ObjectSetString(0, OBJ_GRID_DLY, OBJPROP_TEXT,
            StringFormat("%dm", g_gridDelay));
         Print(StringFormat("[GRID] Delay → %d minutes", g_gridDelay));
      }
      // ── Auto TP toggle ──
      else if(sparam == OBJ_AUTOTP_BTN)
      {
         ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_STATE, false);
         
         g_autoTPEnabled = !g_autoTPEnabled;
         if(g_autoTPEnabled)
         {
            g_tp1Hit = false;  // Reset — let ManageAutoTP detect fresh
            
            ObjectSetString (0, OBJ_AUTOTP_BTN, OBJPROP_TEXT,
               StringFormat("Auto TP: ON | 50%%@%.1fx%.1f", g_tpATRFactor, g_atrMult));
            ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_BGCOLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_BORDER_COLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_COLOR, COL_WHITE);
            Print(StringFormat("[AUTO TP] ENABLED | 50%% @%.1f×%.1f ATR (SL managed by Trail SL separately)",
                  g_tpATRFactor, g_atrMult));
         }
         else
         {
            ObjectSetString (0, OBJ_AUTOTP_BTN, OBJPROP_TEXT, "Auto TP: OFF");
            ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_BGCOLOR, C'60,60,85');
            ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_BORDER_COLOR, C'60,60,85');
            ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_COLOR, C'180,180,200');
            g_tp1Hit = false;
            Print("[AUTO TP] DISABLED");
         }
      }
      // ── TP ATR factor: 0.5 ──
      else if(sparam == OBJ_TP_05)
      {
         ObjectSetInteger(0, OBJ_TP_05, OBJPROP_STATE, false);
         g_tpATRFactor = 0.5;
         // Highlight 0.5, dim 1
         ObjectSetInteger(0, OBJ_TP_05, OBJPROP_BGCOLOR, C'0,100,60');
         ObjectSetInteger(0, OBJ_TP_05, OBJPROP_COLOR, COL_WHITE);
         ObjectSetInteger(0, OBJ_TP_10, OBJPROP_BGCOLOR, C'50,50,70');
         ObjectSetInteger(0, OBJ_TP_10, OBJPROP_COLOR, C'140,140,160');
         // Recalc tpDist if we have a position
         if(g_hasPos && g_cachedATR > 0)
            g_tpDist = g_cachedATR * g_tpATRFactor * g_atrMult;
         // Update button text
         if(g_autoTPEnabled && !g_tp1Hit)
            ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT,
               StringFormat("Auto TP: ON | 50%%@%.1fx%.1f", g_tpATRFactor, g_atrMult));
         Print(StringFormat("[AUTO TP] Factor → %.1f × %.1f ATR", g_tpATRFactor, g_atrMult));
      }
      // ── TP ATR factor: 1.0 ──
      else if(sparam == OBJ_TP_10)
      {
         ObjectSetInteger(0, OBJ_TP_10, OBJPROP_STATE, false);
         g_tpATRFactor = 1.0;
         // Highlight 1, dim 0.5
         ObjectSetInteger(0, OBJ_TP_10, OBJPROP_BGCOLOR, C'0,100,60');
         ObjectSetInteger(0, OBJ_TP_10, OBJPROP_COLOR, COL_WHITE);
         ObjectSetInteger(0, OBJ_TP_05, OBJPROP_BGCOLOR, C'50,50,70');
         ObjectSetInteger(0, OBJ_TP_05, OBJPROP_COLOR, C'140,140,160');
         // Recalc tpDist if we have a position
         if(g_hasPos && g_cachedATR > 0)
            g_tpDist = g_cachedATR * g_tpATRFactor * g_atrMult;
         // Update button text
         if(g_autoTPEnabled && !g_tp1Hit)
            ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT,
               StringFormat("Auto TP: ON | 50%%@%.1fx%.1f", g_tpATRFactor, g_atrMult));
         Print(StringFormat("[AUTO TP] Factor → %.1f × %.1f ATR", g_tpATRFactor, g_atrMult));
      }
      // ── Theme toggle ──
      else if(sparam == OBJ_THEME_BTN)
      {
         ObjectSetInteger(0, OBJ_THEME_BTN, OBJPROP_STATE, false);
         if(g_theme == 0)
            ApplyLightTheme();
         else
            ApplyDarkTheme();
      }

      ChartRedraw();
      UpdatePanel();
   }
   // ── Edit field changed ──
   else if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == OBJ_SET_RISK_EDT)
      {
         string val = ObjectGetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT);
         g_riskMoney = StringToDouble(val);
         if(g_riskMoney <= 0)
         {
            g_riskMoney = InpDefaultRisk;
            ObjectSetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT,
               IntegerToString((int)InpDefaultRisk));
         }
         else
         {
            ObjectSetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT,
               IntegerToString((int)g_riskMoney));
         }
         // Typing in $ → switch to $Fixed, sync %
         g_riskPctMode = false;
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         if(bal > 0) g_riskPct = NormalizeDouble(g_riskMoney / bal * 100.0, 1);
         ObjectSetString(0, OBJ_SET_PCT_EDT, OBJPROP_TEXT, StringFormat("%.1f", g_riskPct));
         UpdateModeColors();
         UpdatePanel();
      }
      else if(sparam == OBJ_SET_PCT_EDT)
      {
         // Typing in % → switch to %Auto, sync $
         string val = ObjectGetString(0, OBJ_SET_PCT_EDT, OBJPROP_TEXT);
         double pct = StringToDouble(val);
         if(pct > 0 && pct <= 100)
         {
            g_riskPct = NormalizeDouble(pct, 1);
            g_riskPctMode = true;
            double bal = AccountInfoDouble(ACCOUNT_BALANCE);
            if(bal > 0) g_riskMoney = MathMax(1, MathFloor(bal * g_riskPct / 100.0));
            ObjectSetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT, IntegerToString((int)g_riskMoney));
         }
         ObjectSetString(0, OBJ_SET_PCT_EDT, OBJPROP_TEXT, StringFormat("%.1f", g_riskPct));
         UpdateModeColors();
         UpdatePanel();
      }
      else if(sparam == OBJ_SET_ATR_EDT)
      {
         string val = ObjectGetString(0, OBJ_SET_ATR_EDT, OBJPROP_TEXT);
         double atr = StringToDouble(val);
         if(atr >= 0.1 && atr <= 5.0)
            g_atrMult = NormalizeDouble(atr, 1);
         ObjectSetString(0, OBJ_SET_ATR_EDT, OBJPROP_TEXT,
            StringFormat("%.1f", g_atrMult));
         UpdatePanel();
      }
   }
}
//+------------------------------------------------------------------+
