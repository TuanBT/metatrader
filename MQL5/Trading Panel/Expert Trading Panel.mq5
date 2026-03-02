//+------------------------------------------------------------------+
//| Expert Trading Panel.mq5                                         |
//| Tuan Quick Trade – One-Click Manual Trading Panel                 |
//|                                                                  |
//| Features:                                                        |
//|  • Risk $ input → auto-calculated lot size                       |
//|  • Auto SL: ATR / Last-N-bars / Fixed pips                       |
//|  • One-click BUY / SELL                                          |
//|  • Auto trailing SL: Wick / Swing / Breakeven                    |
//|  • Auto TP: 50% partial close at 0.5 or 1 ATR                    |
//|  • Grid DCA: auto DCA with ATR × mult spacing                    |
//|  • Dark/Light chart themes                                      |
//|                                                                  |
//| Usage:                                                           |
//|  1. Attach EA to chart                                           |
//|  2. Set Risk $ in panel (max loss per trade)                     |
//|  3. Click BUY or SELL → order fires instantly                    |
//|  4. Trailing SL manages the trade automatically                  |
//|  5. Use "CLOSE ALL" to close all positions                      |
//+------------------------------------------------------------------+
#property copyright "Tuan v1.72"
#property version   "1.72"
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
   TRAIL_CLOSE  = 1,  // bar[1] wick (low/high), min 0.5 ATR
   TRAIL_SWING  = 2,  // nearest swing low/high (support/resistance)
   TRAIL_BE     = 4,  // Breakeven first, then step 1 ATR
   TRAIL_NONE   = 5,  // No auto trail
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
#define OBJ_BUY_PND    PREFIX "buy_pnd"
#define OBJ_SELL_PND   PREFIX "sell_pnd"

#define OBJ_SEP1       PREFIX "sep1"
#define OBJ_SEP2       PREFIX "sep2"
#define OBJ_SEP3       PREFIX "sep3"
#define OBJ_SEP5       PREFIX "sep5"
#define OBJ_SEC_INFO   PREFIX "sec_info"
#define OBJ_SEC_TRADE  PREFIX "sec_trade"
#define OBJ_SEC_ORDER  PREFIX "sec_order"
// ORDER MANAGEMENT buttons
#define OBJ_TRAIL_BTN  PREFIX "trail_btn"
#define OBJ_TM_CLOSE   PREFIX "tm_close"
#define OBJ_TM_SWING   PREFIX "tm_swing"
#define OBJ_TM_BE      PREFIX "tm_be"
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
#define OBJ_PENDING_LINE  PREFIX "pending_line"

// Chart lines (Auto TP / Grid DCA)
#define OBJ_TP1_LINE      PREFIX "tp1_line"
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
#define OBJ_SET_RISK_LBL  PREFIX "set_risk_lbl"
#define OBJ_SET_RISK_EDT  PREFIX "set_risk_edt"
#define OBJ_SET_RISK_PLUS PREFIX "set_rplus"
#define OBJ_SET_RISK_MINUS PREFIX "set_rminus"
#define OBJ_SET_R1        PREFIX "set_r1"
#define OBJ_SET_R2        PREFIX "set_r2"
#define OBJ_SET_R5        PREFIX "set_r5"
#define OBJ_SET_R10       PREFIX "set_r10"
#define OBJ_SET_R25       PREFIX "set_r25"
#define OBJ_SET_R50       PREFIX "set_r50"
#define OBJ_SET_R75       PREFIX "set_r75"
#define OBJ_SET_R100      PREFIX "set_r100"
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
int      g_pendingMode = 0;    // 0=none, 1=buy ready, 2=sell ready
bool     g_trailEnabled = false;
ENUM_TRAIL_MODE g_trailRef = TRAIL_CLOSE;  // Runtime trail mode (changeable from panel)
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
                     StringFormat("TP1 (%.1fATR) %." + IntegerToString(_Digits) + "f",
                                  g_tpATRFactor, tp1));
         else
            HideHLine(OBJ_TP1_LINE);  // already taken
      }
   }
   else
      HideHLine(OBJ_TP1_LINE);

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

void CreatePanel()
{
   int y  = PY;
   int bw = (IW - 8) / 2;   // half-width for paired buttons

   // ── Background ──
   MakeRect(OBJ_BG, PX, y, PW, 300, COL_BG, COL_BORDER);

   // ── Title bar ──
   MakeRect(OBJ_TITLE_BG, PX + 1, y + 1, PW - 2, 26, COL_TITLE_BG, COL_TITLE_BG);
   MakeLabel(OBJ_TITLE, IX, y + 6, "Trading Panel v1.72", C'170,180,215', 10, FONT_BOLD);

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

      // ── Risk row: label + edit + [−] [+] ──
      MakeLabel(OBJ_SET_RISK_LBL, IX, y + 3, "Risk $", COL_DIM, 9);
      MakeEdit(OBJ_SET_RISK_EDT, IX + 48, y, 60, 22,
               IntegerToString((int)g_riskMoney),
               COL_WHITE, COL_EDIT_BG, COL_EDIT_BD);
      MakeButton(OBJ_SET_RISK_MINUS, IX + 112, y, 28, 22, "-", COL_BTN_TXT, C'80,40,40', 10, FONT_BOLD);
      MakeButton(OBJ_SET_RISK_PLUS,  IX + 143, y, 28, 22, "+", COL_BTN_TXT, C'40,80,40', 10, FONT_BOLD);
      y += 26;

      // ── Risk $ quick-select buttons ──
      {
         int rbw = (IW - 2 - 7 * 2) / 8;  // ~35px each, 8 buttons
         int rx = PX + 5;
         int rg = 2;
         MakeButton(OBJ_SET_R1,   rx + 0 * (rbw + rg), y, rbw, 22, "1%",   COL_BTN_TXT, C'50,50,70', 7, FONT_MAIN);
         MakeButton(OBJ_SET_R2,   rx + 1 * (rbw + rg), y, rbw, 22, "2%",   COL_BTN_TXT, C'50,50,70', 7, FONT_MAIN);
         MakeButton(OBJ_SET_R5,   rx + 2 * (rbw + rg), y, rbw, 22, "5%",   COL_BTN_TXT, C'50,50,70', 7, FONT_MAIN);
         MakeButton(OBJ_SET_R10,  rx + 3 * (rbw + rg), y, rbw, 22, "10%",  COL_BTN_TXT, C'50,50,70', 7, FONT_MAIN);
         MakeButton(OBJ_SET_R25,  rx + 4 * (rbw + rg), y, rbw, 22, "25%",  COL_BTN_TXT, C'50,50,70', 7, FONT_MAIN);
         MakeButton(OBJ_SET_R50,  rx + 5 * (rbw + rg), y, rbw, 22, "50%",  COL_BTN_TXT, C'50,50,70', 7, FONT_MAIN);
         MakeButton(OBJ_SET_R75,  rx + 6 * (rbw + rg), y, rbw, 22, "75%",  COL_BTN_TXT, C'50,50,70', 7, FONT_MAIN);
         MakeButton(OBJ_SET_R100, rx + 7 * (rbw + rg), y, rbw, 22, "100%", COL_BTN_TXT, C'50,50,70', 7, FONT_MAIN);
      }
      y += 28;

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

   // ── Pending Order buttons (2 buttons, no Show Line) ──
   {
      int pw2 = (IW - 8) / 2;
      MakeButton(OBJ_BUY_PND,  PX + 5,             y, pw2, 26,
                 "BUY PENDING", COL_WHITE, C'0,100,65', 8);
      MakeButton(OBJ_SELL_PND, PX + 5 + pw2 + 4,   y, pw2, 26,
                 "SELL PENDING", COL_WHITE, C'170,40,40', 8);
   }
   y += 32;

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

   // ── Trail SL toggle + mode buttons (1 row) ──
   //   Modes: Close | Swing | BE
   {
      int bx = PX + 5;
      int tw = 78;   // trail toggle width
      int gp = 2;    // gap between buttons
      int mw = (IW - 2 - tw - 4 * gp) / 3;  // mode button width (3 modes)
      MakeButton(OBJ_TRAIL_BTN, bx, y, tw, 26,
                 "Trail: OFF", C'180,180,200', C'60,60,85', 8);
      bx += tw + gp;
      MakeButton(OBJ_TM_CLOSE, bx, y, mw, 26,
                 "Close", C'140,140,160', C'50,50,70', 7);
      bx += mw + gp;
      MakeButton(OBJ_TM_SWING, bx, y, mw, 26,
                 "Swing", C'140,140,160', C'50,50,70', 7);
      bx += mw + gp;
      MakeButton(OBJ_TM_BE, bx, y, mw, 26,
                 "BE", C'140,140,160', C'50,50,70', 7);
   }
   y += 28;

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
      "Cài đặt Risk (rủi ro) và ATR (Average True Range).");
   ObjectSetString(0, OBJ_SET_RISK_LBL, OBJPROP_TOOLTIP,
      "Risk: Số tiền tối đa bạn chấp nhận mất nếu lệnh dính SL.\nLot size sẽ tự tính dựa trên Risk $ và khoảng cách SL.");
   ObjectSetString(0, OBJ_SET_ATR_LBL, OBJPROP_TOOLTIP,
      "ATR (Average True Range): Chỉ báo đo biên độ dao động trung bình.\nHệ số ATR càng lớn → SL càng xa → lot càng nhỏ.\nVD: ATR 1.5x = SL cách giá 1.5 lần biên độ ATR.");
   ObjectSetString(0, OBJ_SEC_INFO, OBJPROP_TOOLTIP,
      "Thông tin: Risk, lot, hướng lệnh, lãi/lỗ hiện tại.");
   ObjectSetString(0, OBJ_RISK_LBL, OBJPROP_TOOLTIP,
      "Lãi/Lỗ hiện tại (P&L) của tất cả lệnh đang mở.");
   ObjectSetString(0, OBJ_LOCK_LBL, OBJPROP_TOOLTIP,
      "Lợi nhuận Lock (SL Lock): Lãi/Lỗ tính tại mức SL hiện tại.\nCho biết lợi nhuận tối thiểu (hoặc lỗ tối đa) nếu SL bị chạm.\nKhi kéo SL bằng tay, con số này tự cập nhật.");
   ObjectSetString(0, OBJ_LOCK_VAL, OBJPROP_TOOLTIP,
      "Lợi nhuận Lock (SL Lock): Lãi/Lỗ tính tại mức SL hiện tại.\nCho biết lợi nhuận tối thiểu (hoặc lỗ tối đa) nếu SL bị chạm.\nKhi kéo SL bằng tay, con số này tự cập nhật.");
   ObjectSetString(0, OBJ_STATUS_LBL, OBJPROP_TOOLTIP,
      "Lot size và hướng lệnh (LONG/SHORT).\nKhi chưa có lệnh: lot dự kiến theo Risk hiện tại.");
   ObjectSetString(0, OBJ_SPRD_LBL, OBJPROP_TOOLTIP,
      "Risk: Tiền rủi ro mỗi lệnh ($).\nATR (Average True Range): Hệ số biên độ dao động.\nSpread: Chênh lệch giá mua-bán (point).");
   ObjectSetString(0, OBJ_SEC_TRADE, OBJPROP_TOOLTIP,
      "Khu vực vào lệnh: BUY/SELL market hoặc lệnh chờ Pending.");
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

   // Settings: Risk
   ObjectSetString(0, OBJ_SET_RISK_MINUS, OBJPROP_TOOLTIP, "Giảm Risk $1");
   ObjectSetString(0, OBJ_SET_RISK_PLUS,  OBJPROP_TOOLTIP, "Tăng Risk $1");
   ObjectSetString(0, OBJ_SET_R1,   OBJPROP_TOOLTIP, "Risk = 1% số dư tài khoản");
   ObjectSetString(0, OBJ_SET_R2,   OBJPROP_TOOLTIP, "Risk = 2% số dư tài khoản");
   ObjectSetString(0, OBJ_SET_R5,   OBJPROP_TOOLTIP, "Risk = 5% số dư tài khoản");
   ObjectSetString(0, OBJ_SET_R10,  OBJPROP_TOOLTIP, "Risk = 10% số dư tài khoản");
   ObjectSetString(0, OBJ_SET_R25,  OBJPROP_TOOLTIP, "Risk = 25% số dư tài khoản");
   ObjectSetString(0, OBJ_SET_R50,  OBJPROP_TOOLTIP, "Risk = 50% số dư tài khoản");
   ObjectSetString(0, OBJ_SET_R75,  OBJPROP_TOOLTIP, "Risk = 75% số dư tài khoản");
   ObjectSetString(0, OBJ_SET_R100, OBJPROP_TOOLTIP, "Risk = 100% số dư tài khoản");

   // Settings: ATR
   ObjectSetString(0, OBJ_SET_ATR_MINUS, OBJPROP_TOOLTIP, "Giảm ATR ×0.5 (snap đến bước 0.5 gần nhất)");
   ObjectSetString(0, OBJ_SET_ATR_PLUS,  OBJPROP_TOOLTIP, "Tăng ATR ×0.5 (snap đến bước 0.5 gần nhất)");

   // Trade buttons
   ObjectSetString(0, OBJ_BUY_BTN,  OBJPROP_TOOLTIP,
      "Mua ngay theo giá thị trường.\nSL tự động theo ATR. Lot tính theo Risk $.");
   ObjectSetString(0, OBJ_SELL_BTN, OBJPROP_TOOLTIP,
      "Bán ngay theo giá thị trường.\nSL tự động theo ATR. Lot tính theo Risk $.");
   ObjectSetString(0, OBJ_BUY_PND,  OBJPROP_TOOLTIP,
      "Lệnh chờ MUA: Click 1 lần tạo đường giá → kéo đến vị trí → click lần 2 xác nhận.");
   ObjectSetString(0, OBJ_SELL_PND, OBJPROP_TOOLTIP,
      "Lệnh chờ BÁN: Click 1 lần tạo đường giá → kéo đến vị trí → click lần 2 xác nhận.");

   // Trail SL
   ObjectSetString(0, OBJ_TRAIL_BTN, OBJPROP_TOOLTIP,
      "Trailing Stop Loss — Bật/Tắt\n"
      "Chỉ dời SL mà không đóng lệnh.\n"
      "Chuyển mode bất cứ lúc nào, kể cả đang có lệnh.");

   ObjectSetString(0, OBJ_TM_CLOSE, OBJPROP_TOOLTIP,
      "CLOSE — Theo râu nến (mỗi nến mới)\n"
      "BUY: SL = Low[1] | SELL: SL = High[1]\n"
      "Nến quá ngắn (< 0.5 ATR) → bỏ qua.\n"
      "Kích hoạt sau khi giá đi >= TP ATR factor.");

   ObjectSetString(0, OBJ_TM_SWING, OBJPROP_TOOLTIP,
      "SWING — Theo chân sóng gần nhất (mỗi nến mới)\n"
      "BUY: SL = Swing Low | SELL: SL = Swing High\n"
      "Nếu không có swing → lấy nến đỏ/xanh gần nhất.\n"
      "Min 0.5 ATR, kích hoạt sau >= TP ATR factor.");

   ObjectSetString(0, OBJ_TM_BE, OBJPROP_TOOLTIP,
      "BE — Dời SL về BE và ATR\n"
      "B1: Giá +1.0 ATR → SL về entry\n"
      "B2: Mỗi +1 ATR tiếp → SL nhảy lên 1 ATR\n");

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

   ChartRedraw();
}

void DestroyPanel()
{
   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Sync button appearance with actual enabled state                  |
//+------------------------------------------------------------------+
void SyncButtonAppearance()
{
   // ── Trail SL button ──
   if(g_trailEnabled)
   {
      ObjectSetString (0, OBJ_TRAIL_BTN, OBJPROP_TEXT, "Trail SL: ON");
      ObjectSetInteger(0, OBJ_TRAIL_BTN, OBJPROP_BGCOLOR, C'0,100,60');
      ObjectSetInteger(0, OBJ_TRAIL_BTN, OBJPROP_BORDER_COLOR, C'0,100,60');
      ObjectSetInteger(0, OBJ_TRAIL_BTN, OBJPROP_COLOR, COL_WHITE);
   }
   else
   {
      ObjectSetString (0, OBJ_TRAIL_BTN, OBJPROP_TEXT, "Trail SL: OFF");
      ObjectSetInteger(0, OBJ_TRAIL_BTN, OBJPROP_BGCOLOR, C'60,60,85');
      ObjectSetInteger(0, OBJ_TRAIL_BTN, OBJPROP_BORDER_COLOR, C'60,60,85');
      ObjectSetInteger(0, OBJ_TRAIL_BTN, OBJPROP_COLOR, C'180,180,200');
   }

   // ── Trail mode buttons (radio-style highlight) ──
   // Blue = selected but waiting for activation
   // Green = selected AND actively trailing
   // Gray = not selected
   string modeObjs[] = {OBJ_TM_CLOSE, OBJ_TM_SWING, OBJ_TM_BE};
   ENUM_TRAIL_MODE modes[] = {TRAIL_CLOSE, TRAIL_SWING, TRAIL_BE};

   // Determine if trail is actively tracking (conditions met)
   bool trailActive = false;
   if(g_hasPos && g_trailEnabled && g_trailRef != TRAIL_NONE)
   {
      double refEntry = (g_gridEnabled && g_gridLevel > 0) ? GetAvgEntry() : g_entryPx;
      if(refEntry <= 0) refEntry = g_entryPx;
      double cur2 = g_isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                            : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double move = g_isBuy ? (cur2 - refEntry) : (refEntry - cur2);

      switch(g_trailRef)
      {
         case TRAIL_CLOSE:
         case TRAIL_SWING:
            trailActive = (move >= g_cachedATR * g_tpATRFactor);  // profit gate = TP factor
            break;
         case TRAIL_BE:
         {
            trailActive = g_beReached || (g_cachedATR > 0 && move >= g_cachedATR * 1.0);
            break;
         }
      }
   }

   for(int i = 0; i < 3; i++)
   {
      if(g_trailRef == modes[i])
      {
         if(trailActive)
         {
            // Active: green — trail is live
            ObjectSetInteger(0, modeObjs[i], OBJPROP_BGCOLOR, C'0,100,60');
            ObjectSetInteger(0, modeObjs[i], OBJPROP_BORDER_COLOR, C'0,140,80');
            ObjectSetInteger(0, modeObjs[i], OBJPROP_COLOR, COL_WHITE);
         }
         else
         {
            // Selected but not yet active: blue
            ObjectSetInteger(0, modeObjs[i], OBJPROP_BGCOLOR, C'30,80,140');
            ObjectSetInteger(0, modeObjs[i], OBJPROP_BORDER_COLOR, C'50,120,200');
            ObjectSetInteger(0, modeObjs[i], OBJPROP_COLOR, COL_WHITE);
         }
      }
      else
      {
         // Inactive mode: dim
         ObjectSetInteger(0, modeObjs[i], OBJPROP_BGCOLOR, C'50,50,70');
         ObjectSetInteger(0, modeObjs[i], OBJPROP_BORDER_COLOR, C'50,50,70');
         ObjectSetInteger(0, modeObjs[i], OBJPROP_COLOR, C'140,140,160');
      }
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
      if(StringFind(ObjectGetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT), "OFF") >= 0)
         ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT,
            g_tp1Hit ? "Auto TP: ON | TP1 \x2713"
                     : StringFormat("Auto TP: ON | 50%%@%.1fATR", g_tpATRFactor));
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
      string riskStr = ObjectGetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT);
      double parsed  = StringToDouble(riskStr);
      if(parsed > 0) g_riskMoney = parsed;
   }
   if(g_riskMoney <= 0) g_riskMoney = InpDefaultRisk;

   // Update INFO section risk label
   // (Risk now shown in SPRD line, OBJ_RISK_LBL repurposed for P&L)

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // ── SL prices for each direction ──
   double slBuy   = CalcSLPrice(true);
   double slSell  = CalcSLPrice(false);
   double distBuy  = MathAbs(ask - slBuy);
   double distSell = MathAbs(bid - slSell);

   // ── Lot sizes (preview based on ACTUAL SL distance) ──
   double avgDist = (distBuy + distSell) / 2.0;
   double avgLot = CalcLot(avgDist);

   // ── Publish lot to GlobalVariable for external bots ──
   GlobalVariableSet("TP_Lot_" + _Symbol, avgLot);

   // ── BUY / SELL button text (clean, no lot) ──
   ObjectSetString(0, OBJ_BUY_BTN,  OBJPROP_TEXT, "BUY");
   ObjectSetString(0, OBJ_SELL_BTN, OBJPROP_TEXT, "SELL");

   // ── Row 2: Risk | ATR | Spread ──
   double spread = (ask - bid) / _Point;
   ObjectSetString(0, OBJ_SPRD_LBL, OBJPROP_TEXT,
      StringFormat("Risk $%d | ATR %.1fx | Spread %.0f", (int)g_riskMoney, g_atrMult, spread));
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
                  StringFormat("Auto TP: ON | 50%%@%.1fATR", g_tpATRFactor));
         }
      }
      // Clear separate info line (info now on buttons)
      ObjectSetString(0, OBJ_GRID_INFO, OBJPROP_TEXT, " ");
   }
   else
   {
      // No position: show expected lot (left), clear P&L (right)
      ObjectSetString(0, OBJ_STATUS_LBL, OBJPROP_TEXT,
         StringFormat("Lot %.2f", avgLot));
      ObjectSetInteger(0, OBJ_STATUS_LBL, OBJPROP_COLOR, COL_DIM);
      ObjectSetString(0, OBJ_RISK_LBL, OBJPROP_TEXT, " ");
      ObjectSetString(0, OBJ_LOCK_LBL, OBJPROP_TEXT, " ");
      ObjectSetString(0, OBJ_LOCK_VAL, OBJPROP_TEXT, " ");
      ObjectSetString(0, OBJ_GRID_INFO, OBJPROP_TEXT, " ");

      // Refresh Grid DCA projected risk (risk$ may have changed)
      if(g_gridEnabled)
      {
         double maxRisk = CalcProjectedMaxRisk();
         ObjectSetString(0, OBJ_GRID_BTN, OBJPROP_TEXT,
            StringFormat("Grid DCA: ON | DCA 0/%d | Max $%.0f",
                         g_gridMaxLevel, maxRisk));
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
   if(g_panelCollapsed)
   {
      if(g_hasPos)
      {
         double pnl2 = GetPositionPnL();
         double lock2 = GetLockedPnL();
         double lots2 = GetTotalLots();
         string dir2 = g_isBuy ? "LONG" : "SHORT";
         ObjectSetString(0, OBJ_TITLE, OBJPROP_TEXT, "Trading Panel");
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
         ObjectSetString(0, OBJ_TITLE, OBJPROP_TEXT, "Trading Panel");
         ObjectSetInteger(0, OBJ_TITLE, OBJPROP_COLOR, C'170,180,215');
         ObjectSetString(0, OBJ_TITLE_INFO, OBJPROP_TEXT,
            StringFormat("Lot %.2f", avgLot));
         ObjectSetInteger(0, OBJ_TITLE_INFO, OBJPROP_COLOR, COL_DIM);
         ObjectSetString(0, OBJ_TITLE_LOCK, OBJPROP_TEXT, " ");
      }
   }
   else
   {
      ObjectSetString(0, OBJ_TITLE, OBJPROP_TEXT, "Trading Panel");
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
      g_tpDist    = g_cachedATR * g_tpATRFactor;  // TP at factor × ATR
      
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
// PENDING ORDERS
// ════════════════════════════════════════════════════════════════════
void CreatePendingLine()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double offset = 100 * _Point;
   double linePrice = bid + offset;
   if(ObjectFind(0, OBJ_PENDING_LINE) < 0)
      ObjectCreate(0, OBJ_PENDING_LINE, OBJ_HLINE, 0, 0, linePrice);
   ObjectSetDouble (0, OBJ_PENDING_LINE, OBJPROP_PRICE, linePrice);
   ObjectSetInteger(0, OBJ_PENDING_LINE, OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, OBJ_PENDING_LINE, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, OBJ_PENDING_LINE, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, OBJ_PENDING_LINE, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, OBJ_PENDING_LINE, OBJPROP_SELECTED,   true);
   ObjectSetInteger(0, OBJ_PENDING_LINE, OBJPROP_HIDDEN,     false);
   ObjectSetInteger(0, OBJ_PENDING_LINE, OBJPROP_BACK,       false);
   ObjectSetString (0, OBJ_PENDING_LINE, OBJPROP_TEXT, "Pending Entry");
   ObjectSetString (0, OBJ_PENDING_LINE, OBJPROP_TOOLTIP, "Drag to desired entry price");
   ChartRedraw();
}

bool ExecutePendingTrade(bool isBuy)
{
   double pendingPrice = ObjectGetDouble(0, OBJ_PENDING_LINE, OBJPROP_PRICE);
   if(pendingPrice <= 0)
   {
      Print("[PENDING] No pending line price found");
      return false;
   }
   pendingPrice = NormPrice(pendingPrice);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   ENUM_ORDER_TYPE orderType;
   if(isBuy)
      orderType = (pendingPrice < ask) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP;
   else
      orderType = (pendingPrice > bid) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP;

   double sl   = CalcSLPriceFrom(isBuy, pendingPrice);
   // Lot based on ACTUAL SL distance (entry to SL)
   double dist = MathAbs(pendingPrice - sl);
   double lot  = CalcLot(dist);

   if(dist <= 0)                     { Print("[PENDING] Invalid SL distance"); return false; }
   if(isBuy  && sl >= pendingPrice)  { Print("[PENDING] Buy SL >= entry");     return false; }
   if(!isBuy && sl <= pendingPrice)  { Print("[PENDING] Sell SL <= entry");    return false; }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = _Symbol;
   req.volume       = lot;
   req.type         = orderType;
   req.price        = pendingPrice;
   req.sl           = sl;
   req.tp           = 0;
   req.magic        = InpMagic;
   req.type_filling = ORDER_FILLING_IOC;
   req.comment      = "Bot Pending";

   string typeStr;
   switch(orderType)
   {
      case ORDER_TYPE_BUY_LIMIT:  typeStr = "BUY LIMIT";  break;
      case ORDER_TYPE_BUY_STOP:   typeStr = "BUY STOP";   break;
      case ORDER_TYPE_SELL_LIMIT: typeStr = "SELL LIMIT";  break;
      case ORDER_TYPE_SELL_STOP:  typeStr = "SELL STOP";   break;
      default:                   typeStr = "UNKNOWN";      break;
   }

   if(OrderSend(req, res))
   {
      Print(StringFormat("[PENDING] %s %.2f lot @ %s  SL=%s  Risk=$%.2f",
         typeStr, lot,
         DoubleToString(pendingPrice, _Digits),
         DoubleToString(sl, _Digits),
         g_riskMoney));
      return true;
   }
   else
   {
      Print(StringFormat("[PENDING] OrderSend FAILED  rc=%d  %s",
         res.retcode, res.comment));
      return false;
   }
}

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

// Trail SL: dispatches based on g_trailRef (runtime-selectable)
// Price/Step/BE-Phase1: per-tick (throttled ~3s) — react to live price
// Close/Swing/BE-Phase2: per-bar — reference only changes on new candle
void ManageTrail()
{
   if(!g_hasPos) return;
   if(!g_trailEnabled) return;
   if(g_trailRef == TRAIL_NONE) return;

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
   // TRAIL_BE: Breakeven first, then step 1 ATR
   // Phase 1 (per-tick): Move SL to breakeven when profit >= 1.0 ATR
   // Phase 2 (per-tick): Step SL in 1 ATR increments
   // ═══════════════════════════════════════
   if(g_trailRef == TRAIL_BE)
   {
      if(!tickAllowed) return;  // throttle per-tick for both phases

      double fullATR = g_cachedATR;
      if(fullATR <= 0) return;

      // Phase 1: Move to breakeven when profit >= 1.0 ATR
      if(!g_beReached)
      {
         if(moveFromEntry >= fullATR)
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
               Print(StringFormat("[TRAIL-BE] Phase 1: SL → breakeven %s (profit >= 1.0 ATR)",
                     DoubleToString(beSL, _Digits)));
               ModifySL(beSL);
            }
            else
            {
               g_beReached = true;
               g_beStepLevel = 0;
               Print("[TRAIL-BE] SL already past breakeven — entering Phase 2");
            }
         }
         return;
      }

      // Phase 2: Step SL in 1 ATR increments
      // Level 1 reached (price +2.0 ATR from entry) → SL = entry + 1 ATR
      // Level 2 reached (price +3.0 ATR)            → SL = entry + 2 ATR
      // Level N reached (price +(N+1) ATR)           → SL = entry + N ATR
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
   // TRAIL_CLOSE (per-bar): SL = bar[1] wick (low for BUY, high for SELL)
   // TRAIL_SWING (per-bar): SL = nearest swing low/high (support/resistance)
   // Both: min 0.5 ATR distance from current price, profit gate = TP ATR factor
   // ═══════════════════════════════════════

   // Both CLOSE and SWING: per-bar only
   if(!isNewBar) return;

   // Minimum profit gate: don't trail until price moved >= TP ATR factor from entry
   // Matches Auto TP distance so trail activates right after TP1 fires
   if(moveFromEntry < g_cachedATR * g_tpATRFactor)
      return;

   double minDist = g_cachedATR * 0.5;  // minimum trail distance from price
   if(minDist <= 0) return;

   double newSL = 0;

   switch(g_trailRef)
   {
      case TRAIL_CLOSE:
      {
         // SL at bar[1] wick: low for BUY, high for SELL
         // Skip if distance from current price < 0.5 ATR (candle too short)
         if(g_isBuy)
         {
            newSL = NormPrice(iLow(_Symbol, _Period, 1));
            if((bid2 - newSL) < minDist) return;  // too close, skip
         }
         else
         {
            newSL = NormPrice(iHigh(_Symbol, _Period, 1));
            if((newSL - ask2) < minDist) return;   // too close, skip
         }
         break;
      }
      case TRAIL_SWING:
      {
         // Find nearest swing low/high (wave trough/crest)
         // Swing low = bar where low < both neighbors (confirmed from bar[2])
         // Fallback: nearest bearish candle's low (BUY) / bullish candle's high (SELL)
         int N = InpTrailLookback;
         if(N < 3) N = 5;
         double swingPrice = 0;

         if(g_isBuy)
         {
            // Search for swing low from bar[2] backwards (bar[2] has bar[1] as right neighbor)
            for(int i = 2; i <= N; i++)
            {
               double lo  = iLow(_Symbol, _Period, i);
               double loL = iLow(_Symbol, _Period, i - 1);  // right neighbor (newer)
               double loR = iLow(_Symbol, _Period, i + 1);  // left neighbor (older)
               if(lo < loL && lo < loR)
               {
                  swingPrice = lo;
                  break;
               }
            }
            // Fallback: nearest bearish candle's low
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
            if((bid2 - newSL) < minDist) return;  // too close, skip
         }
         else
         {
            // Search for swing high from bar[2] backwards
            for(int i = 2; i <= N; i++)
            {
               double hi  = iHigh(_Symbol, _Period, i);
               double hiL = iHigh(_Symbol, _Period, i - 1);  // right neighbor
               double hiR = iHigh(_Symbol, _Period, i + 1);  // left neighbor
               if(hi > hiL && hi > hiR)
               {
                  swingPrice = hi;
                  break;
               }
            }
            // Fallback: nearest bullish candle's high
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
            if((newSL - ask2) < minDist) return;  // too close, skip
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
// AUTO TP – Partial Take Profit: close 50% at g_tpATRFactor × ATR
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
   double moveR = moveFromEntry / g_tpDist;  // ratio based on 1 ATR

   // TP1: 50% at 1 ATR
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
         Print(StringFormat("[AUTO TP] 50%% closed at TP1 (%.1fATR).", g_tpATRFactor));
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
      g_tpDist = g_cachedATR * g_tpATRFactor;  // TP at factor × ATR

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

   g_riskMoney = InpDefaultRisk;
   g_atrMult   = InpATRMult;
   g_slMode    = SL_ATR;  // Always ATR mode
   g_manageMagic = (InpManageMagic > 0) ? InpManageMagic : InpMagic;
   g_trailRef  = InpTrailMode;  // Initialize trail mode from input
   g_gridMaxLevel = MathMax(2, MathMin(5, InpGridMaxLevel));  // Clamp 2-5

   // Recover if EA restarted with open position
   SyncPositionState();

   // Theme
   ApplyDarkTheme();

   // Build panel
   CreatePanel();
   UpdatePanel();

   // Timer for updates when market is slow
   EventSetMillisecondTimer(1000);

   Print(StringFormat("[PANEL] Tuan Quick Trade v1.72 | %s | Risk=$%.2f | SL=ATR | Trail=%s",
      _Symbol,
      InpDefaultRisk,
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
   // ── Cache ATR once per tick (avoid multiple CopyBuffer calls) ──
   {
      double atr[1];
      if(g_atrHandle != INVALID_HANDLE && CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1)
         g_cachedATR = atr[0];
   }

   // Detect position closed externally (SL hit, etc.)
   if(g_hasPos && !HasOwnPosition())
   {
      // ── Detect "Large SL" = Grid DCA fully exhausted + closed at loss ──
      // Check BEFORE resetting state
      bool wasGridMax = (g_gridEnabled && g_gridLevel >= g_gridMaxLevel);
      bool wasTrailProfit = g_beReached || (g_isBuy ? (g_currentSL > g_entryPx) : (g_currentSL < g_entryPx && g_currentSL > 0));

      // If Grid DCA was maxed out AND trailing hadn't locked profit → "Large SL"
      // Publish GV to pause Bot(s) using this symbol
      if(wasGridMax && !wasTrailProfit)
      {
         string gvPause = "TP_BotPause_" + _Symbol;
         GlobalVariableSet(gvPause, 1.0);
         Print(StringFormat("[PANEL] ⚠ LARGE SL detected — Grid DCA %d/%d maxed | Publishing %s=1",
               g_gridLevel, g_gridMaxLevel, gvPause));
      }
      else
      {
         Print(StringFormat("[PANEL] Position closed — Grid=%d/%d, TrailProfit=%s",
               g_gridLevel, g_gridMaxLevel, wasTrailProfit ? "Yes" : "No"));
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
   // Only update panel if no ticks in last 2s (weekend/closed market fallback)
   static uint s_lastTickMs = 0;
   uint now = GetTickCount();
   if(now - s_lastTickMs >= 2000)
      UpdatePanel();
   s_lastTickMs = now;
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
      // ── Settings panel toggle ──
      if(sparam == OBJ_SETTINGS_BTN)
      {
         ObjectSetInteger(0, OBJ_SETTINGS_BTN, OBJPROP_STATE, false);
         ToggleSettings();
         return;
      }
      // ── Settings: Risk ±$1 ──
      if(sparam == OBJ_SET_RISK_PLUS)
      {
         ObjectSetInteger(0, OBJ_SET_RISK_PLUS, OBJPROP_STATE, false);
         g_riskMoney = MathMax(1, g_riskMoney + 1);
         ObjectSetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT, IntegerToString((int)g_riskMoney));
         UpdatePanel();
         return;
      }
      if(sparam == OBJ_SET_RISK_MINUS)
      {
         ObjectSetInteger(0, OBJ_SET_RISK_MINUS, OBJPROP_STATE, false);
         g_riskMoney = MathMax(1, g_riskMoney - 1);
         ObjectSetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT, IntegerToString((int)g_riskMoney));
         UpdatePanel();
         return;
      }
      // ── Settings: Risk % of balance ──
      if(sparam == OBJ_SET_R1 || sparam == OBJ_SET_R2 ||
         sparam == OBJ_SET_R5 || sparam == OBJ_SET_R10 ||
         sparam == OBJ_SET_R25 || sparam == OBJ_SET_R50 ||
         sparam == OBJ_SET_R75 || sparam == OBJ_SET_R100)
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         double pct = 0;
         if(sparam == OBJ_SET_R1)   pct = 1;
         if(sparam == OBJ_SET_R2)   pct = 2;
         if(sparam == OBJ_SET_R5)   pct = 5;
         if(sparam == OBJ_SET_R10)  pct = 10;
         if(sparam == OBJ_SET_R25)  pct = 25;
         if(sparam == OBJ_SET_R50)  pct = 50;
         if(sparam == OBJ_SET_R75)  pct = 75;
         if(sparam == OBJ_SET_R100) pct = 100;
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         g_riskMoney = MathMax(1, MathFloor(bal * pct / 100.0));
         ObjectSetString(0, OBJ_SET_RISK_EDT, OBJPROP_TEXT, IntegerToString((int)g_riskMoney));
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
         UpdatePanel();
         return;
      }
      if(sparam == OBJ_SET_ATR_MINUS)
      {
         ObjectSetInteger(0, OBJ_SET_ATR_MINUS, OBJPROP_STATE, false);
         // Snap down: 1.0→0.5, 1.1→1.0, 1.5→1.0
         g_atrMult = MathMax(0.5, MathFloor(g_atrMult * 2.0 - 0.001) / 2.0);
         ObjectSetString(0, OBJ_SET_ATR_EDT, OBJPROP_TEXT, StringFormat("%.1f", g_atrMult));
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
               StringFormat("Auto TP: ON | 50%%@%.1fATR", g_tpATRFactor));

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
         HideHLine(OBJ_DCA1_LINE);
         HideHLine(OBJ_DCA2_LINE);
         HideHLine(OBJ_DCA3_LINE);
         HideHLine(OBJ_DCA4_LINE);
         HideHLine(OBJ_DCA5_LINE);
         HideHLine(OBJ_AVG_ENTRY);
         ObjectSetString(0, OBJ_GRID_INFO, OBJPROP_TEXT, " ");
      }
      // ── BUY PENDING (2-click: create line → confirm) ──
      else if(sparam == OBJ_BUY_PND)
      {
         ObjectSetInteger(0, OBJ_BUY_PND, OBJPROP_STATE, false);
         if(g_pendingMode == 1)
         {
            // Click 2: confirm buy pending
            ExecutePendingTrade(true);
            ObjectDelete(0, OBJ_PENDING_LINE);
            g_pendingMode = 0;
            ObjectSetString(0, OBJ_BUY_PND, OBJPROP_TEXT, "BUY PENDING");
            ObjectSetInteger(0, OBJ_BUY_PND, OBJPROP_BGCOLOR, C'0,100,65');
            Print("[PENDING] Buy pending confirmed");
         }
         else
         {
            // Click 1: create line, enter buy-ready mode
            g_pendingMode = 1;
            CreatePendingLine();
            ObjectSetString(0, OBJ_BUY_PND, OBJPROP_TEXT, "✓ CONFIRM BUY");
            ObjectSetInteger(0, OBJ_BUY_PND, OBJPROP_BGCOLOR, C'55,90,160');
            // Reset sell button if it was in confirm mode
            ObjectSetString(0, OBJ_SELL_PND, OBJPROP_TEXT, "SELL PENDING");
            ObjectSetInteger(0, OBJ_SELL_PND, OBJPROP_BGCOLOR, C'170,40,40');
            Print("[PENDING] Line created – drag to price, click BUY PENDING again to confirm");
         }
      }
      // ── SELL PENDING (2-click: create line → confirm) ──
      else if(sparam == OBJ_SELL_PND)
      {
         ObjectSetInteger(0, OBJ_SELL_PND, OBJPROP_STATE, false);
         if(g_pendingMode == 2)
         {
            // Click 2: confirm sell pending
            ExecutePendingTrade(false);
            ObjectDelete(0, OBJ_PENDING_LINE);
            g_pendingMode = 0;
            ObjectSetString(0, OBJ_SELL_PND, OBJPROP_TEXT, "SELL PENDING");
            ObjectSetInteger(0, OBJ_SELL_PND, OBJPROP_BGCOLOR, C'170,40,40');
            Print("[PENDING] Sell pending confirmed");
         }
         else
         {
            // Click 1: create line, enter sell-ready mode
            g_pendingMode = 2;
            CreatePendingLine();
            ObjectSetString(0, OBJ_SELL_PND, OBJPROP_TEXT, "✓ CONFIRM SELL");
            ObjectSetInteger(0, OBJ_SELL_PND, OBJPROP_BGCOLOR, C'55,90,160');
            // Reset buy button if it was in confirm mode
            ObjectSetString(0, OBJ_BUY_PND, OBJPROP_TEXT, "BUY PENDING");
            ObjectSetInteger(0, OBJ_BUY_PND, OBJPROP_BGCOLOR, C'0,100,65');
            Print("[PENDING] Line created – drag to price, click SELL PENDING again to confirm");
         }
      }
      // ── Trail SL toggle ──
      else if(sparam == OBJ_TRAIL_BTN)
      {
         g_trailEnabled = !g_trailEnabled;
         ObjectSetInteger(0, OBJ_TRAIL_BTN, OBJPROP_STATE, false);
         Print(StringFormat("[PANEL] Trail SL %s (mode: %s)",
               g_trailEnabled ? "ENABLED" : "DISABLED",
               EnumToString(g_trailRef)));
         SyncButtonAppearance();
      }
      // ── Trail mode: Close ──
      else if(sparam == OBJ_TM_CLOSE)
      {
         ObjectSetInteger(0, OBJ_TM_CLOSE, OBJPROP_STATE, false);
         g_trailRef = TRAIL_CLOSE;
         Print("[TRAIL] Mode → Close (bar[1] wick, min 0.5 ATR)");
         SyncButtonAppearance();
      }
      // ── Trail mode: Swing ──
      else if(sparam == OBJ_TM_SWING)
      {
         ObjectSetInteger(0, OBJ_TM_SWING, OBJPROP_STATE, false);
         g_trailRef = TRAIL_SWING;
         Print("[TRAIL] Mode → Swing (nearest swing low/high, min 0.5 ATR)");
         SyncButtonAppearance();
      }
      // ── Trail mode: BE ──
      else if(sparam == OBJ_TM_BE)
      {
         ObjectSetInteger(0, OBJ_TM_BE, OBJPROP_STATE, false);
         g_trailRef = TRAIL_BE;
         g_beReached = false;  // Reset BE state on mode change
         g_beStepLevel = 0;
         Print("[TRAIL] Mode → BE (breakeven first, then step 1 ATR)");
         SyncButtonAppearance();
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
                  g_tpDist = g_cachedATR * g_tpATRFactor;
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
               StringFormat("Auto TP: ON | 50%%@%.1fATR", g_tpATRFactor));
            ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_BGCOLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_BORDER_COLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_COLOR, COL_WHITE);
            Print(StringFormat("[AUTO TP] ENABLED | 50%% @%.1fATR (SL managed by Trail SL separately)",
                  g_tpATRFactor));
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
            g_tpDist = g_cachedATR * g_tpATRFactor;
         // Update button text
         if(g_autoTPEnabled && !g_tp1Hit)
            ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT,
               StringFormat("Auto TP: ON | 50%%@%.1fATR", g_tpATRFactor));
         Print(StringFormat("[AUTO TP] Factor → %.1f ATR", g_tpATRFactor));
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
            g_tpDist = g_cachedATR * g_tpATRFactor;
         // Update button text
         if(g_autoTPEnabled && !g_tp1Hit)
            ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT,
               StringFormat("Auto TP: ON | 50%%@%.1fATR", g_tpATRFactor));
         Print(StringFormat("[AUTO TP] Factor → %.1f ATR", g_tpATRFactor));
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
