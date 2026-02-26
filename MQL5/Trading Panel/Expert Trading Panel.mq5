//+------------------------------------------------------------------+
//| Expert Trading Panel.mq5                                         |
//| Tuan Quick Trade – One-Click Manual Trading Panel                 |
//|                                                                  |
//| Features:                                                        |
//|  • Risk $ input → auto-calculated lot size                       |
//|  • Auto SL: ATR / Last-N-bars / Fixed pips                       |
//|  • One-click BUY / SELL                                          |
//|  • Auto trailing SL: Candle-based or R-based                     |
//|  • Dark/Light chart themes                                      |
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
#property version   "1.35"
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
#define OBJ_BUY_PND    PREFIX "buy_pnd"
#define OBJ_SELL_PND   PREFIX "sell_pnd"

#define OBJ_SEP1       PREFIX "sep1"
#define OBJ_SEP2       PREFIX "sep2"
#define OBJ_SEP3       PREFIX "sep3"
#define OBJ_SEP4       PREFIX "sep4"
#define OBJ_SEP5       PREFIX "sep5"
#define OBJ_SEC_INFO   PREFIX "sec_info"
#define OBJ_SEC_TRADE  PREFIX "sec_trade"
#define OBJ_SEC_ORDER  PREFIX "sec_order"
#define OBJ_SEC_SIGNAL PREFIX "sec_signal"

// ORDER MANAGEMENT buttons
#define OBJ_TRAIL_BTN  PREFIX "trail_btn"
#define OBJ_GRID_BTN   PREFIX "grid_btn"
#define OBJ_AUTOTP_BTN PREFIX "autotp_btn"

// ENTRY SIGNALS buttons
#define OBJ_MEDIO_BTN  PREFIX "medio_btn"
#define OBJ_FVG_BTN    PREFIX "fvg_btn"

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
#define OBJ_GRID_INFO     PREFIX "grid_info"

#define OBJ_AUTO_BTN      PREFIX "auto_btn"



// Theme buttons
#define OBJ_THEME_DARK    PREFIX "theme_dark"
#define OBJ_THEME_LIGHT   PREFIX "theme_light"

// Collapse button
#define OBJ_COLLAPSE_BTN  PREFIX "collapse_btn"
#define OBJ_LINES_BTN     PREFIX "lines_btn"

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
double   g_tpDist     = 0;        // normal ATR dist for Auto TP (not grid-widened)
datetime g_lastBar    = 0;

// Auto Candle Counter mode
bool     g_autoMode   = false;
int      g_theme      = 0;       // 0=Dark, 1=Light

// Live ATR multiplier (changeable from panel)
double   g_atrMult    = 0;
int      g_pendingMode = 0;    // 0=none, 1=buy ready, 2=sell ready
bool     g_trailEnabled = false;
bool     g_panelCollapsed = false;
bool     g_linesHidden    = false;
int      g_panelFullHeight = 460;
ENUM_SL_MODE g_slMode = SL_ATR;

// MST Medio signal state
bool     g_medioEnabled  = false;
int      g_medioPivotLen = 5;     // Pivot lookback (bars left and right)
double   g_medioImpulseMult = 1.0; // Min body size = impulseMult × 20-bar avg body

// MST Medio persistent tracking
double   g_mSH1 = 0, g_mSH0 = 0;  // Most recent and previous Swing High
int      g_mSH1_idx = 0, g_mSH0_idx = 0;
double   g_mSL1 = 0, g_mSL0 = 0;  // Most recent and previous Swing Low
int      g_mSL1_idx = 0, g_mSL0_idx = 0;
double   g_mSLBeforeSH = 0;       // Last SL before most recent SH
int      g_mSLBeforeSH_idx = 0;
double   g_mSHBeforeSL = 0;       // Last SH before most recent SL
int      g_mSHBeforeSL_idx = 0;

// MST Medio pending confirmation state
// 0=idle, 1=waiting confirm BUY, -1=waiting confirm SELL
int      g_medioPending  = 0;
double   g_mBreakPoint   = 0;     // Entry level (SH or SL)
double   g_mW1Peak       = 0;     // W1 peak (BUY) or trough (SELL)
double   g_mPendSL       = 0;     // Stop loss level
datetime g_mLastPivotCalc = 0;    // Last bar that pivots were calculated

// FVG (Impulse Zone IN/OUT) signal state
bool     g_fvgEnabled     = false;
int      g_fvgATRLen       = 14;
double   g_fvgATRMult      = 1.2;   // Impulse range >= atrMult × ATR
double   g_fvgBodyRatio    = 0.55;  // Min body / range

// FVG persistent tracking
ENUM_TIMEFRAMES g_fvgImpulseTF = PERIOD_M15;  // Auto-mapped impulse TF
int      g_fvgImpulseATR   = INVALID_HANDLE;  // ATR handle for impulse TF
double   g_fvgZoneH        = 0;    // Impulse zone High
double   g_fvgZoneL        = 0;    // Impulse zone Low
datetime g_fvgZoneTime     = 0;    // Time of impulse bar
datetime g_fvgLastImpulse  = 0;    // Last checked impulse bar time
bool     g_fvgHasContext   = false; // Impulse detected, waiting for IN
bool     g_fvgWaitingIN    = false;
bool     g_fvgWaitingOUT   = false;
double   g_fvgInHigh       = 0;    // IN candle high
double   g_fvgInLow        = 0;    // IN candle low
double   g_fvgMinLow       = 0;    // Min low since IN
double   g_fvgMaxHigh      = 0;    // Max high since IN
datetime g_fvgInTime       = 0;    // IN candle time
datetime g_fvgLastCheck    = 0;    // Last bar checked

// Auto TP (Partial Take Profit) state
bool     g_autoTPEnabled  = false;
bool     g_tp1Hit         = false;    // TP1 (50% @1R) taken

// Grid DCA state
bool     g_gridEnabled    = false;
int      g_gridLevel      = 0;       // 0=initial only, 1-3=DCA additions
int      g_gridMaxLevel   = 3;       // max DCA positions to add
double   g_gridBaseATR    = 0;       // ATR value when grid started
double   g_gridBaseMult   = 0;       // ATR multiplier locked at grid start

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
         double atr[1];
         if(g_atrHandle != INVALID_HANDLE &&
            CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1)
         {
            double dist = atr[0] * g_atrMult;
            // When Grid DCA is ON, widen SL to accommodate all grid levels
            // SL = (maxDCA + 1) × atrMult × ATR  (3 DCA + 1 buffer)
            if(g_gridEnabled)
               dist = atr[0] * (g_gridMaxLevel + 1) * g_atrMult;
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

// Return the NORMAL SL distance (without grid widening) – used for lot sizing
// Each position risks $RiskMoney based on normal ATR distance, NOT the wide grid SL
double CalcNormalSLDist()
{
   switch(g_slMode)
   {
      case SL_ATR:
      {
         double atr[1];
         if(g_atrHandle != INVALID_HANDLE &&
            CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1)
         {
            double dist = atr[0] * g_atrMult;
            if(InpSLBuffer > 0) dist *= (1.0 + InpSLBuffer / 100.0);
            return dist;
         }
         return 0;
      }
      case SL_LOOKBACK:
      {
         int lb = MathMax(InpSLLookback, 3);
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double mid = (ask + bid) / 2.0;
         double low = iLow(_Symbol, _Period, 1);
         for(int i = 2; i <= lb; i++)
            low = MathMin(low, iLow(_Symbol, _Period, i));
         double dist = MathAbs(mid - low);
         if(InpSLBuffer > 0) dist *= (1.0 + InpSLBuffer / 100.0);
         return dist;
      }
      case SL_FIXED:
      {
         double dist = InpFixedSLPips * PipSize();
         if(InpSLBuffer > 0) dist *= (1.0 + InpSLBuffer / 100.0);
         return dist;
      }
   }
   return 0;
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

   double atr[1];
   if(g_atrHandle == INVALID_HANDLE || CopyBuffer(g_atrHandle, 0, 1, 1, atr) != 1)
      return g_riskMoney * (g_gridMaxLevel + 1);  // fallback

   double atrVal = (g_gridBaseATR > 0) ? g_gridBaseATR : atr[0];
   double mult   = (g_gridBaseMult > 0) ? g_gridBaseMult : g_atrMult;
   double spacing = atrVal * mult;
   double fullSLDist = spacing * (g_gridMaxLevel + 1);

   double totalRisk = 0;
   for(int i = 0; i <= g_gridMaxLevel; i++)
   {
      // Distance from position #i entry to SL
      double distToSL = fullSLDist - i * spacing;
      if(distToSL <= 0) continue;

      // Apply SL buffer if configured
      if(InpSLBuffer > 0) distToSL *= (1.0 + InpSLBuffer / 100.0);

      double lot = CalcLot(distToSL);  // clips to min lot
      double risk = lot * (distToSL / tickSz) * tickVal;
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
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
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
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      double lot = PositionGetDouble(POSITION_VOLUME);
      sumLE += lot * PositionGetDouble(POSITION_PRICE_OPEN);
      sumL  += lot;
   }
   return (sumL > 0) ? sumLE / sumL : 0;
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
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
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
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

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
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

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
   // ── Auto TP: TP1 line at 1R from avgEntry ──
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
                     StringFormat("TP1 (1R) %." + IntegerToString(_Digits) + "f", tp1));
         else
            HideHLine(OBJ_TP1_LINE);  // already taken
      }
   }
   else
      HideHLine(OBJ_TP1_LINE);

   // ── Grid DCA: show pending DCA levels ──
   if(g_gridEnabled && g_hasPos && g_gridBaseATR > 0)
   {
      double spacing = g_gridBaseATR * g_gridBaseMult;
      string dcaNames[] = {OBJ_DCA1_LINE, OBJ_DCA2_LINE, OBJ_DCA3_LINE};

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
         name == OBJ_COLLAPSE_BTN || name == OBJ_LINES_BTN ||
         name == OBJ_THEME_DARK || name == OBJ_THEME_LIGHT)
         continue;
      
      // Skip chart lines – they have their own toggle
      ENUM_OBJECT otype = (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE);
      if(otype == OBJ_HLINE) continue;
      
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, showFlag);
   }
   
   // Resize background
   if(g_panelCollapsed)
      ObjectSetInteger(0, OBJ_BG, OBJPROP_YSIZE, 32);  // title bar height only
   else
      ObjectSetInteger(0, OBJ_BG, OBJPROP_YSIZE, g_panelFullHeight);
   
   ChartRedraw();
}

void ToggleChartLines()
{
   g_linesHidden = !g_linesHidden;
   
   // Update button icon: ○ when hidden, ◉ when visible
   ObjectSetString(0, OBJ_LINES_BTN, OBJPROP_TEXT,
                   g_linesHidden ? "\x25CB" : "\x25C9");
   
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
      int tw = 48;
      int tx = PX + PW - 2 * tw - 10;
      // Collapse panel (left), Lines toggle, Theme buttons (right)
      MakeButton(OBJ_COLLAPSE_BTN, tx - 52, y + 3, 22, 20, "\x25BC", COL_BTN_TXT, C'40,40,55', 8, FONT_MAIN);
      MakeButton(OBJ_LINES_BTN,   tx - 26, y + 3, 22, 20, "\x25C9", COL_BTN_TXT, C'40,40,55', 8, FONT_MAIN);
      MakeButton(OBJ_THEME_DARK,  tx,            y + 3, tw, 20, "Dark",  COL_BTN_TXT, C'40,40,55', 7, FONT_MAIN);
      MakeButton(OBJ_THEME_LIGHT, tx + tw + 2,   y + 3, tw, 20, "Light", COL_BTN_TXT, C'40,40,55', 7, FONT_MAIN);
   }
   y += 32;

   // ═══════════════════════════════════════
   // SECTION: INFO
   // ═══════════════════════════════════════
   MakeRect(OBJ_SEP1, IX, y, IW, 1, COL_BORDER, COL_BORDER);
   MakeLabel(OBJ_SEC_INFO, IX + 2, y - 5, " INFO ", C'100,110,140', 7, FONT_MAIN);
   y += 8;

   // ── Max Risk + Position PnL (same row) ──
   MakeLabel(OBJ_RISK_LBL, IX, y + 3, "Risk $", COL_DIM, 9);
   MakeEdit(OBJ_RISK_EDT, IX + 48, y, 40, 22,
            IntegerToString((int)InpDefaultRisk),
            COL_WHITE, COL_EDIT_BG, COL_EDIT_BD);
   MakeLabel(OBJ_STATUS_LBL, IX + 96, y + 4, " ", COL_DIM, 11);
   y += 26;

   // ── SL + Spread info ──
   MakeLabel(OBJ_SPRD_LBL, IX, y, "", COL_DIM, 8, FONT_MONO);
   y += 20;

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

   // ── Trail SL toggle ──
   MakeButton(OBJ_TRAIL_BTN, PX + 5, y, IW - 2, 26,
              "Trail SL: OFF", C'180,180,200', C'60,60,85', 8);
   y += 30;

   // ── Grid DCA toggle ──
   MakeButton(OBJ_GRID_BTN, PX + 5, y, IW - 2, 26,
              "Grid DCA: OFF", C'180,180,200', C'60,60,85', 8);
   y += 28;

   // ── Auto TP toggle ──
   MakeButton(OBJ_AUTOTP_BTN, PX + 5, y, IW - 2, 26,
              "Auto TP: OFF", C'180,180,200', C'60,60,85', 8);
   y += 28;

   // ── Grid/TP info line (hidden initially, shown when grid/tp active with position) ──
   MakeLabel(OBJ_GRID_INFO, IX, y, " ", COL_DIM, 8, FONT_MONO);
   y += 16;

   // ═══════════════════════════════════════
   // SECTION: ENTRY SIGNALS
   // ═══════════════════════════════════════
   MakeRect(OBJ_SEP4, IX, y, IW, 1, COL_BORDER, COL_BORDER);
   MakeLabel(OBJ_SEC_SIGNAL, IX + 2, y - 5, " ENTRY SIGNALS ", C'100,110,140', 7, FONT_MAIN);
   y += 8;

   // ── Candle Counter toggle ──
   MakeButton(OBJ_AUTO_BTN, PX + 5, y, IW - 2, 26,
              "Candle Counter 3: OFF", C'180,180,200', C'60,60,85', 8);
   y += 30;

   // ── MST Medio toggle ──
   MakeButton(OBJ_MEDIO_BTN, PX + 5, y, IW - 2, 26,
              "MST Medio: OFF", C'180,180,200', C'60,60,85', 8);
   y += 28;

   // ── FVG Signal toggle ──
   MakeButton(OBJ_FVG_BTN, PX + 5, y, IW - 2, 26,
              "FVG Signal: OFF", C'180,180,200', C'60,60,85', 8);
   y += 30;

   // ═══════════════════════════════════════
   // CLOSE ALL (standalone at bottom)
   // ═══════════════════════════════════════
   MakeRect(OBJ_SEP5, IX, y, IW, 1, COL_BORDER, COL_BORDER);
   y += 6;
   MakeButton(OBJ_CLOSE_BTN, PX + 5, y, IW - 2, 30,
              "CLOSE ALL", C'255,200,200', COL_CLOSE, 9);
   y += 36;

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

   // ── Lot sizes (preview based on ACTUAL SL distance) ──
   double avgDist = (distBuy + distSell) / 2.0;
   double avgLot = CalcLot(avgDist);

   // ── ATR label ──
   string slMode = StringFormat("ATR %.1fx", g_atrMult);

   // ── BUY / SELL button text (clean, no lot) ──
   ObjectSetString(0, OBJ_BUY_BTN,  OBJPROP_TEXT, "BUY");
   ObjectSetString(0, OBJ_SELL_BTN, OBJPROP_TEXT, "SELL");

   // ── ATR + Spread info line (no Lot – lot shown in status) ──
   double spread = (ask - bid) / _Point;
   ObjectSetString(0, OBJ_SPRD_LBL, OBJPROP_TEXT,
      StringFormat("%s | Spr %.0f", slMode, spread));
   ObjectSetInteger(0, OBJ_SPRD_LBL, OBJPROP_COLOR, COL_DIM);

   // ── Position status (next to Risk) ──
   g_hasPos = HasOwnPosition();
   if(g_hasPos)
   {
      SyncIfNeeded();
      string dir = g_isBuy ? "LONG" : "SHORT";
      double pnl = GetPositionPnL();
      int nPos = CountOwnPositions();
      double totalLots = GetTotalLots();
      string statusTxt;
      if(nPos > 1)
         statusTxt = StringFormat("%.2f %s | x%d | $%+.2f", totalLots, dir, nPos, pnl);
      else
         statusTxt = StringFormat("%.2f %s | $%+.2f", totalLots, dir, pnl);
      ObjectSetString(0, OBJ_STATUS_LBL, OBJPROP_TEXT, statusTxt);
      ObjectSetInteger(0, OBJ_STATUS_LBL, OBJPROP_COLOR,
         pnl >= 0 ? COL_PROFIT : COL_LOSS);

      // ── Dynamic button text (info merged into buttons) ──
      if(g_gridEnabled)
      {
         double projRisk = CalcProjectedMaxRisk();
         ObjectSetString(0, OBJ_GRID_BTN, OBJPROP_TEXT,
            StringFormat("Grid DCA: ON | Hit %d/%d | Max $%.0f",
                         g_gridLevel, g_gridMaxLevel, projRisk));
      }
      if(g_autoTPEnabled)
         ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT,
            g_tp1Hit ? "Auto TP: ON | TP1 ✓ BE" : "Auto TP: ON | 50%@1R");
      // Clear separate info line (info now on buttons)
      ObjectSetString(0, OBJ_GRID_INFO, OBJPROP_TEXT, " ");
   }
   else
   {
      // Show expected lot when no position
      ObjectSetString(0, OBJ_STATUS_LBL, OBJPROP_TEXT,
         StringFormat("Lot %.2f", avgLot));
      ObjectSetInteger(0, OBJ_STATUS_LBL, OBJPROP_COLOR, COL_DIM);
      ObjectSetString(0, OBJ_GRID_INFO, OBJPROP_TEXT, " ");

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
      g_tpDist    = CalcNormalSLDist();  // normal ATR for TP calcs
      
      // Lock grid ATR/mult if grid enabled at trade entry
      if(g_gridEnabled && g_gridBaseATR <= 0)
      {
         double atr[1];
         if(g_atrHandle != INVALID_HANDLE &&
            CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1)
            g_gridBaseATR = atr[0];
         g_gridBaseMult = g_atrMult;
      }

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
         double atr[];
         if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1)
         {
            double dist = atr[0] * g_atrMult;
            // When Grid DCA is ON, widen SL beyond all grid levels
            if(g_gridEnabled)
               dist = atr[0] * (g_gridMaxLevel + 1) * g_atrMult;
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

   // Use average entry when Grid is active for correct R calculation
   double refEntry = (g_gridEnabled && g_gridLevel > 0) ? GetAvgEntry() : g_entryPx;
   if(refEntry <= 0) refEntry = g_entryPx;

   double moveFromEntry = g_isBuy ? (cur - refEntry)
                                  : (refEntry - cur);
   double moveR = moveFromEntry / g_riskDist;

   if(moveR < InpTrailStartR) return;   // not started yet

   int    fullSteps  = (int)MathFloor((moveR - InpTrailStartR) / InpTrailStepR);
   double trailAmt   = fullSteps * InpTrailStepR * g_riskDist;
   double newSL      = g_isBuy ? NormPrice(refEntry + trailAmt)
                                : NormPrice(refEntry - trailAmt);

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
   if(!g_trailEnabled) return;
   switch(InpTrailMode)
   {
      case TRAIL_CANDLE: TrailCandle(); break;
      case TRAIL_R:      TrailRBased(); break;
      case TRAIL_NONE:   break;
   }
}

// ════════════════════════════════════════════════════════════════════
// AUTO TP – Partial Take Profit: 50% @1R → BE → trail remainder
// ════════════════════════════════════════════════════════════════════
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
   double moveR = moveFromEntry / g_tpDist;  // R based on normal ATR

   // TP1: 50% at 1R
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
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
         totalLot += PositionGetDouble(POSITION_VOLUME);
      }
      if(totalLot <= minLot)
      {
         // Can't halve min lot — just move SL to BE without partial close
         g_tp1Hit = true;
         Print(StringFormat("[AUTO TP] TP1 hit but lot=%.2f is min. Skip partial, SL→BE only.", totalLot));
         MoveSLToBreakeven();
         return;
      }

      Print(StringFormat("[AUTO TP] TP1 hit at %.1fR | Price=%s AvgEntry=%s",
            moveR, DoubleToString(cur, _Digits), DoubleToString(avgEntry, _Digits)));

      if(PartialClosePercent(0.50))
      {
         g_tp1Hit = true;
         Print("[AUTO TP] 50% closed at TP1 (1R) → moving SL to breakeven");
         MoveSLToBreakeven();
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

   // Need base ATR to calculate spacing
   if(g_gridBaseATR <= 0)
   {
      double atr[1];
      if(g_atrHandle != INVALID_HANDLE &&
         CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1)
         g_gridBaseATR = atr[0];
      else
         return;
   }

   double cur = g_isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Calculate expected DCA level price
   double spacing = g_gridBaseATR * g_gridBaseMult;
   int nextLevel = g_gridLevel + 1;
   double dcaPrice = g_isBuy
      ? g_entryPx - nextLevel * spacing
      : g_entryPx + nextLevel * spacing;

   // Check if price reached DCA level
   bool triggered = g_isBuy ? (cur <= dcaPrice) : (cur >= dcaPrice);
   if(!triggered) return;

   // Calculate lot for DCA position – based on ACTUAL distance from DCA entry to SL
   // Each DCA position risks exactly $RiskMoney
   double sl = CalcSLPrice(g_isBuy);
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
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
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

   // Only on new bar
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == g_lastBar) return;

   int sig = DetectThreeCandles();
   if(sig == 0) return;

   // Signal-only: draw arrow on chart (no auto execution)
   bool isBuy = (sig == 1);
   datetime t1 = iTime(_Symbol, _Period, 1);
   double   p1 = isBuy ? iLow(_Symbol, _Period, 1) : iHigh(_Symbol, _Period, 1);
   double   offset = 10 * _Point;

   string arrowName = PREFIX "sig_" + IntegerToString((long)t1);

   if(ObjectFind(0, arrowName) < 0)
   {
      ObjectCreate(0, arrowName, OBJ_ARROW, 0, t1,
                   isBuy ? p1 - offset : p1 + offset);
      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE,
                       isBuy ? 233 : 234);  // ▲ up / ▼ down
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR,
                       isBuy ? C'38,166,154' : C'239,83,80');
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, arrowName, OBJPROP_BACK, false);

      Print(StringFormat("[SIGNAL] CC3 %s arrow @ bar[1]",
            isBuy ? "BUY" : "SELL"));
   }
}

// ════════════════════════════════════════════════════════════════════
// MST MEDIO – 2-Step Breakout Confirmation Signal
// ════════════════════════════════════════════════════════════════════
// Logic (from TradingView MST Medio v1.4):
//   1. Detect HH/LL via swing pivots
//   2. Find W1 Peak = highest high (BUY) / lowest low (SELL) from
//      break candle until first opposite-color candle
//   3. Wait for CLOSE beyond W1 Peak → Confirmed signal
//
// In MQL5 we draw arrows only (signal-only, no auto-trade).

// Detect pivot high at bar[shift] (confirmed pivot: pivotLen bars on each side)
double MedioPivotHigh(int shift)
{
   int pl = g_medioPivotLen;
   double mid = iHigh(_Symbol, _Period, shift);
   for(int i = 1; i <= pl; i++)
   {
      if(iHigh(_Symbol, _Period, shift - i) > mid) return 0;
      if(iHigh(_Symbol, _Period, shift + i) > mid) return 0;
   }
   return mid;
}

double MedioPivotLow(int shift)
{
   int pl = g_medioPivotLen;
   double mid = iLow(_Symbol, _Period, shift);
   for(int i = 1; i <= pl; i++)
   {
      if(iLow(_Symbol, _Period, shift - i) < mid) return 0;
      if(iLow(_Symbol, _Period, shift + i) < mid) return 0;
   }
   return mid;
}

// Average body of last N bars at position shift
double MedioAvgBody(int shift, int period = 20)
{
   double sum = 0;
   for(int i = 0; i < period; i++)
      sum += MathAbs(iClose(_Symbol, _Period, shift + i) - iOpen(_Symbol, _Period, shift + i));
   return sum / period;
}

void CheckMSTMedio()
{
   if(!g_medioEnabled) return;

   // Only on new bar
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == g_mLastPivotCalc) return;
   g_mLastPivotCalc = curBar;

   int pl = g_medioPivotLen;

   // Check for confirmed pivot at bar[pivotLen] (needs pivotLen bars to the right)
   double pivHigh = MedioPivotHigh(pl);
   double pivLow  = MedioPivotLow(pl);

   // Update swing tracking
   if(pivLow > 0)
   {
      g_mSL0     = g_mSL1;
      g_mSL0_idx = g_mSL1_idx;
      g_mSL1     = pivLow;
      g_mSL1_idx = pl;  // lookback from current bar

      // Track SH before SL
      g_mSHBeforeSL     = g_mSH1;
      g_mSHBeforeSL_idx = g_mSH1_idx;
   }
   if(pivHigh > 0)
   {
      // Track SL before SH
      g_mSLBeforeSH     = g_mSL1;
      g_mSLBeforeSH_idx = g_mSL1_idx;

      g_mSH0     = g_mSH1;
      g_mSH0_idx = g_mSH1_idx;
      g_mSH1     = pivHigh;
      g_mSH1_idx = pl;
   }

   // Detect HH / LL
   bool isNewHH = (pivHigh > 0 && g_mSH0 > 0 && g_mSH1 > g_mSH0);
   bool isNewLL = (pivLow > 0  && g_mSL0 > 0 && g_mSL1 < g_mSL0);

   // Impulse body filter
   if(isNewHH && g_medioImpulseMult > 0)
   {
      int scanFrom = g_mSH0_idx;
      bool found = false;
      for(int i = scanFrom; i >= pl; i--)
      {
         if(iClose(_Symbol, _Period, i) > g_mSH0)
         {
            double body = MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i));
            found = (body >= g_medioImpulseMult * MedioAvgBody(i));
            break;
         }
      }
      if(!found) isNewHH = false;
   }
   if(isNewLL && g_medioImpulseMult > 0)
   {
      int scanFrom = g_mSL0_idx;
      bool found = false;
      for(int i = scanFrom; i >= pl; i--)
      {
         if(iClose(_Symbol, _Period, i) < g_mSL0)
         {
            double body = MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i));
            found = (body >= g_medioImpulseMult * MedioAvgBody(i));
            break;
         }
      }
      if(!found) isNewLL = false;
   }

   // ── New HH → start tracking BUY confirmation ──
   if(isNewHH && g_mSLBeforeSH > 0)
   {
      // Find W1 peak: highest high from break candle until first bearish bar
      double w1Peak = 0;
      bool foundBreak = false;
      int scanStart = g_mSH0_idx;  // lookback to old SH
      for(int i = scanStart; i >= 0; i--)
      {
         double cl = iClose(_Symbol, _Period, i);
         double op = iOpen(_Symbol, _Period, i);
         double hi = iHigh(_Symbol, _Period, i);
         if(!foundBreak)
         {
            if(cl > g_mSH0)
            {
               foundBreak = true;
               w1Peak = hi;
            }
         }
         else
         {
            if(hi > w1Peak) w1Peak = hi;
            if(cl < op) break;  // first bearish bar → end W1
         }
      }
      if(w1Peak > 0)
      {
         g_medioPending = 1;
         g_mBreakPoint  = g_mSH0;        // Entry = old SH
         g_mW1Peak      = w1Peak;
         g_mPendSL      = g_mSLBeforeSH;  // SL = swing low before SH
      }
   }

   // ── New LL → start tracking SELL confirmation ──
   if(isNewLL && g_mSHBeforeSL > 0)
   {
      double w1Trough = 0;
      bool foundBreak = false;
      int scanStart = g_mSL0_idx;
      for(int i = scanStart; i >= 0; i--)
      {
         double cl = iClose(_Symbol, _Period, i);
         double op = iOpen(_Symbol, _Period, i);
         double lo = iLow(_Symbol, _Period, i);
         if(!foundBreak)
         {
            if(cl < g_mSL0)
            {
               foundBreak = true;
               w1Trough = lo;
            }
         }
         else
         {
            if(lo < w1Trough) w1Trough = lo;
            if(cl > op) break;  // first bullish bar → end W1
         }
      }
      if(w1Trough > 0)
      {
         g_medioPending = -1;
         g_mBreakPoint  = g_mSL0;
         g_mW1Peak      = w1Trough;
         g_mPendSL      = g_mSHBeforeSL;
      }
   }

   // ── Check pending confirmation on bar[1] ──
   if(g_medioPending == 1)
   {
      double lo1 = iLow(_Symbol, _Period, 1);
      double cl1 = iClose(_Symbol, _Period, 1);

      // Cancel if SL hit or structure broken
      if(lo1 <= g_mPendSL || lo1 <= g_mBreakPoint)
      {
         g_medioPending = 0;
      }
      else if(cl1 > g_mW1Peak)
      {
         // Confirmed BUY signal!
         datetime t1 = iTime(_Symbol, _Period, 1);
         double arrow_y = iLow(_Symbol, _Period, 1) - 20 * _Point;
         string arrowName = PREFIX "msig_" + IntegerToString((long)t1);

         if(ObjectFind(0, arrowName) < 0)
         {
            ObjectCreate(0, arrowName, OBJ_ARROW, 0, t1, arrow_y);
            ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, 233);  // ▲
            ObjectSetInteger(0, arrowName, OBJPROP_COLOR, C'33,150,243');  // blue
            ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
            ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, true);

            // Draw entry/SL/TP reference lines
            string entryLine = PREFIX "mentry_" + IntegerToString((long)t1);
            string slLine    = PREFIX "msl_" + IntegerToString((long)t1);
            SetHLine(entryLine, g_mBreakPoint, C'33,150,243', STYLE_DOT, 1, "M.Entry");
            SetHLine(slLine,    g_mPendSL,     C'255,152,0',  STYLE_DOT, 1, "M.SL");

            Print(StringFormat("[SIGNAL] MST Medio BUY | Entry=%.5f SL=%.5f",
                  g_mBreakPoint, g_mPendSL));
         }
         g_medioPending = 0;
      }
   }
   else if(g_medioPending == -1)
   {
      double hi1 = iHigh(_Symbol, _Period, 1);
      double cl1 = iClose(_Symbol, _Period, 1);

      if(hi1 >= g_mPendSL || hi1 >= g_mBreakPoint)
      {
         g_medioPending = 0;
      }
      else if(cl1 < g_mW1Peak)
      {
         // Confirmed SELL signal!
         datetime t1 = iTime(_Symbol, _Period, 1);
         double arrow_y = iHigh(_Symbol, _Period, 1) + 20 * _Point;
         string arrowName = PREFIX "msig_" + IntegerToString((long)t1);

         if(ObjectFind(0, arrowName) < 0)
         {
            ObjectCreate(0, arrowName, OBJ_ARROW, 0, t1, arrow_y);
            ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, 234);  // ▼
            ObjectSetInteger(0, arrowName, OBJPROP_COLOR, C'255,105,180');  // pink
            ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
            ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, true);

            string entryLine = PREFIX "mentry_" + IntegerToString((long)t1);
            string slLine    = PREFIX "msl_" + IntegerToString((long)t1);
            SetHLine(entryLine, g_mBreakPoint, C'255,105,180', STYLE_DOT, 1, "M.Entry");
            SetHLine(slLine,    g_mPendSL,     C'255,152,0',   STYLE_DOT, 1, "M.SL");

            Print(StringFormat("[SIGNAL] MST Medio SELL | Entry=%.5f SL=%.5f",
                  g_mBreakPoint, g_mPendSL));
         }
         g_medioPending = 0;
      }
   }
}

// ════════════════════════════════════════════════════════════════════
// FVG SIGNAL – Impulse Zone IN/OUT Pattern
// ════════════════════════════════════════════════════════════════════
// Logic (from TradingView M15 Impulse FVG Entry):
//   1. Detect impulse candle on higher TF (range >= atrMult × ATR, body >= 55%)
//   2. On chart TF, wait for IN candle (fully inside impulse zone)
//   3. Wait for OUT candle (close outside zone + clean break)
//   4. Draw signal arrow

// Auto-map current chart TF to impulse (higher) TF
ENUM_TIMEFRAMES FVG_GetImpulseTF()
{
   ENUM_TIMEFRAMES curTF = _Period;
   switch(curTF)
   {
      case PERIOD_M1:   return PERIOD_M5;
      case PERIOD_M2:   return PERIOD_M15;
      case PERIOD_M3:   return PERIOD_M15;
      case PERIOD_M4:   return PERIOD_M15;
      case PERIOD_M5:   return PERIOD_M15;
      case PERIOD_M6:   return PERIOD_M30;
      case PERIOD_M10:  return PERIOD_M30;
      case PERIOD_M12:  return PERIOD_H1;
      case PERIOD_M15:  return PERIOD_H1;
      case PERIOD_M20:  return PERIOD_H1;
      case PERIOD_M30:  return PERIOD_H2;
      case PERIOD_H1:   return PERIOD_H4;
      case PERIOD_H2:   return PERIOD_H4;
      case PERIOD_H3:   return PERIOD_H8;
      case PERIOD_H4:   return PERIOD_D1;
      case PERIOD_H6:   return PERIOD_D1;
      case PERIOD_H8:   return PERIOD_D1;
      case PERIOD_H12:  return PERIOD_D1;
      case PERIOD_D1:   return PERIOD_W1;
      case PERIOD_W1:   return PERIOD_MN1;
      default:          return PERIOD_H1;
   }
}

string FVG_TFLabel(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H4:  return "H4";
      case PERIOD_H8:  return "H8";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return "??";
   }
}

void FVG_Init()
{
   g_fvgImpulseTF = FVG_GetImpulseTF();
   if(g_fvgImpulseATR != INVALID_HANDLE)
   {
      IndicatorRelease(g_fvgImpulseATR);
      g_fvgImpulseATR = INVALID_HANDLE;
   }
   g_fvgImpulseATR = iATR(_Symbol, g_fvgImpulseTF, g_fvgATRLen);
   if(g_fvgImpulseATR == INVALID_HANDLE)
      Print("[FVG] Warning: ATR handle failed for ", FVG_TFLabel(g_fvgImpulseTF));
   else
      Print("[FVG] Impulse TF = ", FVG_TFLabel(g_fvgImpulseTF),
            " (chart = ", FVG_TFLabel(_Period), ")");

   // Reset state
   g_fvgHasContext  = false;
   g_fvgWaitingIN   = false;
   g_fvgWaitingOUT  = false;
   g_fvgZoneH       = 0;
   g_fvgZoneL       = 0;
}

void FVG_Deinit()
{
   if(g_fvgImpulseATR != INVALID_HANDLE)
   {
      IndicatorRelease(g_fvgImpulseATR);
      g_fvgImpulseATR = INVALID_HANDLE;
   }
}

void CheckFVG()
{
   if(!g_fvgEnabled) return;

   // Only on new bar
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == g_fvgLastCheck) return;
   g_fvgLastCheck = curBar;

   // ── Step 1: Check impulse on higher TF ──
   datetime impTime = iTime(_Symbol, g_fvgImpulseTF, 0);
   if(impTime != g_fvgLastImpulse)
   {
      g_fvgLastImpulse = impTime;
      // Check bar[1] on impulse TF (confirmed bar)
      double hi  = iHigh (_Symbol, g_fvgImpulseTF, 1);
      double lo  = iLow  (_Symbol, g_fvgImpulseTF, 1);
      double cl  = iClose(_Symbol, g_fvgImpulseTF, 1);
      double op  = iOpen (_Symbol, g_fvgImpulseTF, 1);
      double rng = hi - lo;

      double atr[1];
      bool atrOK = (g_fvgImpulseATR != INVALID_HANDLE &&
                    CopyBuffer(g_fvgImpulseATR, 0, 1, 1, atr) == 1);

      if(atrOK && rng > 0)
      {
         double bodyRatio = MathAbs(cl - op) / rng;
         bool isImpulse = (rng >= g_fvgATRMult * atr[0]) &&
                          (bodyRatio >= g_fvgBodyRatio);

         if(isImpulse)
         {
            g_fvgZoneH      = hi;
            g_fvgZoneL      = lo;
            g_fvgZoneTime   = iTime(_Symbol, g_fvgImpulseTF, 1);
            g_fvgHasContext = true;
            g_fvgWaitingIN  = true;
            g_fvgWaitingOUT = false;
            g_fvgInHigh     = 0;
            g_fvgInLow      = 0;
            g_fvgMinLow     = 0;
            g_fvgMaxHigh    = 0;

            Print(StringFormat("[FVG] Impulse detected on %s | Zone %.5f – %.5f",
                  FVG_TFLabel(g_fvgImpulseTF), g_fvgZoneL, g_fvgZoneH));

            // Draw zone lines
            string zhLine = PREFIX "fvgs_zh";
            string zlLine = PREFIX "fvgs_zl";
            SetHLine(zhLine, g_fvgZoneH, C'128,0,255', STYLE_SOLID, 1, "FVG Zone H");
            SetHLine(zlLine, g_fvgZoneL, C'128,0,255', STYLE_SOLID, 1, "FVG Zone L");
         }
      }
   }

   if(!g_fvgHasContext) return;

   // ── Step 2: Check for IN candle on chart TF (bar[1]) ──
   if(g_fvgWaitingIN && g_fvgZoneH > 0 && g_fvgZoneL > 0)
   {
      double hi1 = iHigh(_Symbol, _Period, 1);
      double lo1 = iLow(_Symbol, _Period, 1);

      // Candle fully inside zone
      if(hi1 < g_fvgZoneH && lo1 > g_fvgZoneL)
      {
         g_fvgInHigh    = hi1;
         g_fvgInLow     = lo1;
         g_fvgInTime    = iTime(_Symbol, _Period, 1);
         g_fvgMinLow    = lo1;
         g_fvgMaxHigh   = hi1;
         g_fvgWaitingIN  = false;
         g_fvgWaitingOUT = true;
         Print("[FVG] IN candle detected");
      }
   }

   // ── Step 3: Check for OUT candle (bar[1]) ──
   if(g_fvgWaitingOUT)
   {
      double hi1 = iHigh (_Symbol, _Period, 1);
      double lo1 = iLow  (_Symbol, _Period, 1);
      double cl1 = iClose(_Symbol, _Period, 1);
      double cl2 = iClose(_Symbol, _Period, 2);

      // Track extremes since IN
      if(lo1 < g_fvgMinLow)  g_fvgMinLow  = lo1;
      if(hi1 > g_fvgMaxHigh) g_fvgMaxHigh = hi1;

      // OUT BUY: close > zoneH, low > zoneH, prev close > zoneH, no reversal below inLow
      bool prevUp  = (cl2 > g_fvgZoneH);
      bool outBuy  = (cl1 > g_fvgZoneH) && (lo1 > g_fvgZoneH) &&
                     prevUp && (lo1 > g_fvgInHigh) &&
                     (g_fvgMinLow >= g_fvgInLow);

      // OUT SELL: close < zoneL, high < zoneL, prev close < zoneL, no reversal above inHigh
      bool prevDown = (cl2 < g_fvgZoneL);
      bool outSell  = (cl1 < g_fvgZoneL) && (hi1 < g_fvgZoneL) &&
                      prevDown && (hi1 < g_fvgInLow) &&
                      (g_fvgMaxHigh <= g_fvgInHigh);

      if(outBuy || outSell)
      {
         datetime t1 = iTime(_Symbol, _Period, 1);
         string arrowName = PREFIX "fvgs_" + IntegerToString((long)t1);

         if(ObjectFind(0, arrowName) < 0)
         {
            double arrowY = outBuy ? lo1 - 20 * _Point : hi1 + 20 * _Point;
            ObjectCreate(0, arrowName, OBJ_ARROW, 0, t1, arrowY);
            ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, outBuy ? 233 : 234);
            ObjectSetInteger(0, arrowName, OBJPROP_COLOR,
                             outBuy ? C'76,175,80' : C'244,67,54');  // green / red
            ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
            ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, true);

            Print(StringFormat("[FVG] %s signal | %s impulse",
                  outBuy ? "BUY" : "SELL", FVG_TFLabel(g_fvgImpulseTF)));
         }

         // Reset state
         g_fvgWaitingOUT = false;
         g_fvgHasContext = false;
      }
   }
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
      if((ulong)PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;
      
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
   g_riskDist  = MathAbs(g_entryPx - g_currentSL);
   if(g_tpDist <= 0)
      g_tpDist = CalcNormalSLDist();

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
   string names[] = {OBJ_THEME_DARK, OBJ_THEME_LIGHT};
   for(int i = 0; i < 2; i++)
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

   // Recover if EA restarted with open position
   SyncPositionState();

   // Theme
   ApplyDarkTheme();

   // Build panel
   CreatePanel();
   UpdatePanel();

   // Timer for updates when market is slow
   EventSetMillisecondTimer(1000);

   Print(StringFormat("[PANEL] Tuan Quick Trade v1.32 | %s | Risk=$%.2f | SL=ATR | Trail=%s",
      _Symbol,
      InpDefaultRisk,
      EnumToString(InpTrailMode)));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DestroyPanel();
   EventKillTimer();
   FVG_Deinit();

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
      g_tpDist    = 0;
      g_tp1Hit    = false;
      g_gridLevel = 0;
      g_gridBaseATR = 0;
      g_gridBaseMult = 0;
   }

   // Auto trailing
   ManageTrail();

   // Auto TP (partial close at 1R)
   ManageAutoTP();

   // Grid DCA (add positions on adverse move)
   ManageGrid();

   // Auto Candle Counter (before bar tracking update)
   CheckAutoEntry();

   // MST Medio signal detection
   CheckMSTMedio();

   // FVG Impulse Zone signal detection
   CheckFVG();

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
      // ── Collapse/Expand Panel ──
      if(sparam == OBJ_COLLAPSE_BTN)
      {
         ObjectSetInteger(0, OBJ_COLLAPSE_BTN, OBJPROP_STATE, false);
         TogglePanelCollapse();
         return;
      }
      if(sparam == OBJ_LINES_BTN)
      {
         ObjectSetInteger(0, OBJ_LINES_BTN, OBJPROP_STATE, false);
         ToggleChartLines();
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
      // ── CLOSE ALL ──
      else if(sparam == OBJ_CLOSE_BTN)
      {
         ObjectSetInteger(0, OBJ_CLOSE_BTN, OBJPROP_STATE, false);
         CloseAllPositions();

         // Reset Auto TP state
         g_tp1Hit = false;
         if(g_autoTPEnabled)
            ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT, "Auto TP: ON | 50%@1R");

         // Reset Grid DCA state
         g_gridLevel   = 0;
         g_gridBaseATR = 0;
         g_gridBaseMult = 0;
         if(g_gridEnabled)
         {
            double maxRisk = CalcProjectedMaxRisk();
            ObjectSetString(0, OBJ_GRID_BTN, OBJPROP_TEXT,
               StringFormat("Grid: ON | DCA 0/%d | Max $%.0f",
                            g_gridMaxLevel, maxRisk));
         }

         // Clear chart lines
         HideHLine(OBJ_TP1_LINE);
         HideHLine(OBJ_DCA1_LINE);
         HideHLine(OBJ_DCA2_LINE);
         HideHLine(OBJ_DCA3_LINE);
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
         if(g_trailEnabled)
         {
            ObjectSetString (0, OBJ_TRAIL_BTN, OBJPROP_TEXT, "Trail SL: ON");
            ObjectSetInteger(0, OBJ_TRAIL_BTN, OBJPROP_BGCOLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_TRAIL_BTN, OBJPROP_BORDER_COLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_TRAIL_BTN, OBJPROP_COLOR, COL_WHITE);
            Print("[PANEL] Trail SL ENABLED");
         }
         else
         {
            ObjectSetString (0, OBJ_TRAIL_BTN, OBJPROP_TEXT, "Trail SL: OFF");
            ObjectSetInteger(0, OBJ_TRAIL_BTN, OBJPROP_BGCOLOR, C'60,60,85');
            ObjectSetInteger(0, OBJ_TRAIL_BTN, OBJPROP_BORDER_COLOR, C'60,60,85');
            ObjectSetInteger(0, OBJ_TRAIL_BTN, OBJPROP_COLOR, C'180,180,200');
            Print("[PANEL] Trail SL DISABLED");
         }
      }
      // ── Candle Counter toggle (signal arrows only) ──
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
            Print("[SIGNAL] Candle Counter signal arrows ENABLED");
         }
         else
         {
            ObjectSetString (0, OBJ_AUTO_BTN, OBJPROP_TEXT, "Candle Counter 3: OFF");
            ObjectSetInteger(0, OBJ_AUTO_BTN, OBJPROP_BGCOLOR, C'60,60,85');
            ObjectSetInteger(0, OBJ_AUTO_BTN, OBJPROP_BORDER_COLOR, C'60,60,85');
            ObjectSetInteger(0, OBJ_AUTO_BTN, OBJPROP_COLOR, C'180,180,200');
            // Clean up signal arrows
            ObjectsDeleteAll(0, PREFIX + "sig_");
            Print("[SIGNAL] Candle Counter signal arrows DISABLED");
         }
      }
      // ── MST Medio toggle ──
      else if(sparam == OBJ_MEDIO_BTN)
      {
         g_medioEnabled = !g_medioEnabled;
         ObjectSetInteger(0, OBJ_MEDIO_BTN, OBJPROP_STATE, false);
         if(g_medioEnabled)
         {
            ObjectSetString (0, OBJ_MEDIO_BTN, OBJPROP_TEXT, "MST Medio: ON");
            ObjectSetInteger(0, OBJ_MEDIO_BTN, OBJPROP_BGCOLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_MEDIO_BTN, OBJPROP_BORDER_COLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_MEDIO_BTN, OBJPROP_COLOR, COL_WHITE);
            Print("[SIGNAL] MST Medio signal arrows ENABLED");
         }
         else
         {
            ObjectSetString (0, OBJ_MEDIO_BTN, OBJPROP_TEXT, "MST Medio: OFF");
            ObjectSetInteger(0, OBJ_MEDIO_BTN, OBJPROP_BGCOLOR, C'60,60,85');
            ObjectSetInteger(0, OBJ_MEDIO_BTN, OBJPROP_BORDER_COLOR, C'60,60,85');
            ObjectSetInteger(0, OBJ_MEDIO_BTN, OBJPROP_COLOR, C'180,180,200');
            // Clean up signal arrows and reference lines
            ObjectsDeleteAll(0, PREFIX + "msig_");
            ObjectsDeleteAll(0, PREFIX + "mentry_");
            ObjectsDeleteAll(0, PREFIX + "msl_");
            g_medioPending = 0;
            Print("[SIGNAL] MST Medio signal arrows DISABLED");
         }
      }
      // ── FVG Signal toggle ──
      else if(sparam == OBJ_FVG_BTN)
      {
         g_fvgEnabled = !g_fvgEnabled;
         ObjectSetInteger(0, OBJ_FVG_BTN, OBJPROP_STATE, false);
         if(g_fvgEnabled)
         {
            FVG_Init();
            ObjectSetString (0, OBJ_FVG_BTN, OBJPROP_TEXT, "FVG Signal: ON");
            ObjectSetInteger(0, OBJ_FVG_BTN, OBJPROP_BGCOLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_FVG_BTN, OBJPROP_BORDER_COLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_FVG_BTN, OBJPROP_COLOR, COL_WHITE);
            Print("[SIGNAL] FVG Signal ENABLED");
         }
         else
         {
            FVG_Deinit();
            ObjectSetString (0, OBJ_FVG_BTN, OBJPROP_TEXT, "FVG Signal: OFF");
            ObjectSetInteger(0, OBJ_FVG_BTN, OBJPROP_BGCOLOR, C'60,60,85');
            ObjectSetInteger(0, OBJ_FVG_BTN, OBJPROP_BORDER_COLOR, C'60,60,85');
            ObjectSetInteger(0, OBJ_FVG_BTN, OBJPROP_COLOR, C'180,180,200');
            // Cleanup signal objects (not the button)
            ObjectsDeleteAll(0, PREFIX + "fvgs_");
            g_fvgHasContext  = false;
            g_fvgWaitingIN   = false;
            g_fvgWaitingOUT  = false;
            Print("[SIGNAL] FVG Signal DISABLED");
         }
      }
      // ── Grid DCA toggle ──
      else if(sparam == OBJ_GRID_BTN)
      {
         g_gridEnabled = !g_gridEnabled;
         ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_STATE, false);
         if(g_gridEnabled)
         {
            // Capture current ATR for consistent grid spacing
            double atr[1];
            if(g_atrHandle != INVALID_HANDLE &&
               CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1)
               g_gridBaseATR = atr[0];
            g_gridBaseMult = g_atrMult;  // Lock ATR multiplier for grid
            
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
               StringFormat("Grid: ON | DCA 0/%d | Max $%.0f",
                            g_gridMaxLevel, maxRisk));
            ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_BGCOLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_BORDER_COLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_GRID_BTN, OBJPROP_COLOR, COL_WHITE);

            // Warning about total risk
            Print(StringFormat("[GRID] WARNING: Max total risk = $%.0f (projected with min-lot clipping)",
                  maxRisk));
            Print(StringFormat("[GRID] ENABLED | Max=%d Spacing=%.1fxATR | SL widened to %.1fxATR",
                  g_gridMaxLevel, g_atrMult,
                  (g_gridMaxLevel + 1) * g_atrMult));

            // Widen SL on existing positions to accommodate grid levels
            if(g_hasPos)
            {
               double newSL = CalcSLPrice(g_isBuy);
               for(int i = PositionsTotal() - 1; i >= 0; i--)
               {
                  ulong ticket = PositionGetTicket(i);
                  if(ticket == 0) continue;
                  if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
                  if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
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
               // Set tpDist to normal ATR for Auto TP calcs (if not already set)
               if(g_tpDist <= 0)
                  g_tpDist = CalcNormalSLDist();
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
            g_gridBaseMult = 0;
            // Narrow SL back to normal on existing positions
            if(g_hasPos)
            {
               double newSL = CalcSLPrice(g_isBuy);  // now uses non-grid formula
               for(int i = PositionsTotal() - 1; i >= 0; i--)
               {
                  ulong ticket = PositionGetTicket(i);
                  if(ticket == 0) continue;
                  if(!PositionSelectByTicket(ticket)) continue;
                  if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
                  if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
                  
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
            HideHLine(OBJ_AVG_ENTRY);
            ObjectSetString(0, OBJ_GRID_INFO, OBJPROP_TEXT, " ");
            Print("[GRID] DISABLED");
         }
      }
      // ── Auto TP toggle ──
      else if(sparam == OBJ_AUTOTP_BTN)
      {
         ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_STATE, false);
         
         // Validate min lot: can't do 50% partial if total lot is at minimum
         if(!g_autoTPEnabled && g_hasPos)
         {
            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double totalLot = 0;
            for(int pi = PositionsTotal() - 1; pi >= 0; pi--)
            {
               ulong pt = PositionGetTicket(pi);
               if(pt == 0) continue;
               if(!PositionSelectByTicket(pt)) continue;
               if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
               if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
               totalLot += PositionGetDouble(POSITION_VOLUME);
            }
            if(totalLot <= minLot)
            {
               Print(StringFormat("[AUTO TP] BLOCKED: Total lot %.2f = min lot. Cannot halve for partial close.", totalLot));
               ObjectSetString(0, OBJ_AUTOTP_BTN, OBJPROP_TEXT,
                  StringFormat("Auto TP: LOT MIN (%.2f)", minLot));
               return;
            }
         }
         
         g_autoTPEnabled = !g_autoTPEnabled;
         if(g_autoTPEnabled)
         {
            // Check if TP1 was already taken (SL is at/above breakeven)
            if(g_hasPos && g_entryPx > 0 && g_currentSL > 0)
            {
               double avgEntry = GetAvgEntry();
               bool slAboveBE = g_isBuy ? (g_currentSL >= avgEntry)
                                        : (g_currentSL <= avgEntry);
               if(slAboveBE)
               {
                  g_tp1Hit = true;
                  Print("[AUTO TP] SL already at BE → TP1 marked as taken");
               }
               else
                  g_tp1Hit = false;
            }
            else
               g_tp1Hit = false;
            
            ObjectSetString (0, OBJ_AUTOTP_BTN, OBJPROP_TEXT,
               g_tp1Hit ? "Auto TP: ON | TP1 \x2713 BE" : "Auto TP: ON | 50%@1R");
            ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_BGCOLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_BORDER_COLOR, C'0,100,60');
            ObjectSetInteger(0, OBJ_AUTOTP_BTN, OBJPROP_COLOR, COL_WHITE);
            Print("[AUTO TP] ENABLED | 50% @1R → BE");
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
      // ── Theme buttons ──
      else if(sparam == OBJ_THEME_DARK || sparam == OBJ_THEME_LIGHT)
      {
         if(sparam == OBJ_THEME_DARK)  ApplyDarkTheme();
         if(sparam == OBJ_THEME_LIGHT) ApplyLightTheme();
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
