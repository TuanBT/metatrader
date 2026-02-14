//+------------------------------------------------------------------+
//| Indicator MST Medio.mq5                                         |
//| MST Medio — 2-Step Breakout Confirmation Visual Indicator       |
//| Converted from TradingView Pine Script MST Medio v2.0           |
//|                                                                  |
//| Indicator-only (no trading). Use on chart to compare with TV.    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MTS"
#property link      ""
#property version   "2.00"
#property strict

#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

// Plot 1: Swing High markers
#property indicator_label1  "SwingHigh"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrOrange
#property indicator_width1  1

// Plot 2: Swing Low markers
#property indicator_label2  "SwingLow"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrCornflowerBlue
#property indicator_width2  1

// Plot 3: Buy signal marker (triangle up at entry)
#property indicator_label3  "SignalBuy"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLime
#property indicator_width3  2

// Plot 4: Sell signal marker (triangle down at entry)
#property indicator_label4  "SignalSell"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrRed
#property indicator_width4  2

//--- Fixed Settings (not exposed as inputs)
#define PIVOT_LEN        5
#define BREAK_MULT       0.25
#define IMPULSE_MULT     1.5
#define SHOW_SWINGS      false
#define SHOW_BREAK_LABEL true
#define SHOW_BREAK_LINE  true
#define COL_BREAK_UP     clrLime
#define COL_BREAK_DOWN   clrRed
#define COL_ENTRY_BUY    clrDodgerBlue
#define COL_ENTRY_SELL   clrHotPink
#define COL_SL           clrYellow
#define COL_TP           clrLimeGreen

//--- Buffers
double g_swingHBuf[];
double g_swingLBuf[];
double g_sigBuyBuf[];
double g_sigSellBuf[];

//--- Object prefix
string g_objPrefix = "MSM_";

//--- Swing History (datetime-based state) ---
double   g_sh1, g_sh0;
datetime g_sh1_time, g_sh0_time;
double   g_sl1, g_sl0;
datetime g_sl1_time, g_sl0_time;

double   g_slBeforeSH;
datetime g_slBeforeSH_time;
double   g_shBeforeSL;
datetime g_shBeforeSL_time;

//--- 2-Step Confirmation State ---
int      g_pendingState;
double   g_pendBreakPoint;
double   g_pendW1Peak;
double   g_pendW1Trough;
double   g_pendSL;
datetime g_pendSL_time;
datetime g_pendBreak_time;

//--- Signal tracking ---
datetime g_lastBuySignal;
datetime g_lastSellSignal;

//--- Break count ---
int g_breakCount;

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================
void DeleteObjectsByPrefix(const string prefix)
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; --i)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

void DrawHLine(const string name, datetime t1, double price, datetime t2,
               color clr, ENUM_LINE_STYLE style, int width)
{
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price))
   {
      ObjectMove(0, name, 0, t1, price);
      ObjectMove(0, name, 1, t2, price);
   }
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawTextLabel(const string name, datetime t, double price,
                   const string text, color clr, int fontSize = 8)
{
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
      ObjectMove(0, name, 0, t, price);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

// ============================================================================
// PIVOT DETECTION
// ============================================================================
bool IsPivotHigh(int barIdx, int pivotLen, int totalBars)
{
   double val = iHigh(_Symbol, _Period, barIdx);
   for(int j = barIdx - pivotLen; j <= barIdx + pivotLen; j++)
   {
      if(j == barIdx || j < 0 || j >= totalBars) continue;
      if(iHigh(_Symbol, _Period, j) >= val)
         return false;
   }
   return true;
}

bool IsPivotLow(int barIdx, int pivotLen, int totalBars)
{
   double val = iLow(_Symbol, _Period, barIdx);
   for(int j = barIdx - pivotLen; j <= barIdx + pivotLen; j++)
   {
      if(j == barIdx || j < 0 || j >= totalBars) continue;
      if(iLow(_Symbol, _Period, j) <= val)
         return false;
   }
   return true;
}

// ============================================================================
// AVERAGE BODY (for Impulse Filter)
// ============================================================================
double CalcAvgBody(int atBar, int period, int totalBars)
{
   double sum = 0;
   int cnt = 0;
   for(int i = atBar; i < atBar + period && i < totalBars; i++)
   {
      sum += MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i));
      cnt++;
   }
   return (cnt > 0) ? sum / cnt : 0;
}

// Convert datetime to bar shift. Returns -1 if not found.
int TimeToShift(datetime t)
{
   if(t == 0) return -1;
   return iBarShift(_Symbol, _Period, t, false);
}

// ============================================================================
// INIT
// ============================================================================
int OnInit()
{
   // Buffers
   SetIndexBuffer(0, g_swingHBuf, INDICATOR_DATA);
   SetIndexBuffer(1, g_swingLBuf, INDICATOR_DATA);
   SetIndexBuffer(2, g_sigBuyBuf, INDICATOR_DATA);
   SetIndexBuffer(3, g_sigSellBuf, INDICATOR_DATA);

   // Arrow codes
   PlotIndexSetInteger(0, PLOT_ARROW, 234);    // Down arrow for SH
   PlotIndexSetInteger(1, PLOT_ARROW, 233);    // Up arrow for SL
   PlotIndexSetInteger(2, PLOT_ARROW, 233);    // Up arrow for buy signal
   PlotIndexSetInteger(3, PLOT_ARROW, 234);    // Down arrow for sell signal

   // Empty values
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Object prefix
   string number = StringFormat("%I64d", GetTickCount64());
   g_objPrefix = StringSubstr(number, MathMax(0, StringLen(number) - 4)) + "_MSM_";

   // Reset state
   ResetState();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteObjectsByPrefix(g_objPrefix);
}

void ResetState()
{
   g_sh1 = EMPTY_VALUE; g_sh0 = EMPTY_VALUE;
   g_sh1_time = 0; g_sh0_time = 0;
   g_sl1 = EMPTY_VALUE; g_sl0 = EMPTY_VALUE;
   g_sl1_time = 0; g_sl0_time = 0;
   g_slBeforeSH = EMPTY_VALUE; g_slBeforeSH_time = 0;
   g_shBeforeSL = EMPTY_VALUE; g_shBeforeSL_time = 0;
   g_pendingState = 0;
   g_pendBreakPoint = EMPTY_VALUE;
   g_pendW1Peak = EMPTY_VALUE;
   g_pendW1Trough = EMPTY_VALUE;
   g_pendSL = EMPTY_VALUE;
   g_pendSL_time = 0;
   g_pendBreak_time = 0;
   g_lastBuySignal = 0;
   g_lastSellSignal = 0;
   g_breakCount = 0;
}

// ============================================================================
// MAIN CALCULATION
// ============================================================================
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < PIVOT_LEN * 2 + 25) return(0);

   // Delete old objects and reset state on full recalculation
   int startBar;
   if(prev_calculated == 0)
   {
      DeleteObjectsByPrefix(g_objPrefix);
      ResetState();
      startBar = rates_total - 1;  // Start from oldest bar (highest index = oldest in as-series)

      // Initialize all buffers to EMPTY
      ArrayInitialize(g_swingHBuf, EMPTY_VALUE);
      ArrayInitialize(g_swingLBuf, EMPTY_VALUE);
      ArrayInitialize(g_sigBuyBuf, EMPTY_VALUE);
      ArrayInitialize(g_sigSellBuf, EMPTY_VALUE);
   }
   else
   {
      // Only process new/updated bars
      startBar = rates_total - prev_calculated;
      if(startBar < 1) startBar = 1;
   }

   // Set buffers as series (index 0 = current bar)
   ArraySetAsSeries(g_swingHBuf, true);
   ArraySetAsSeries(g_swingLBuf, true);
   ArraySetAsSeries(g_sigBuyBuf, true);
   ArraySetAsSeries(g_sigSellBuf, true);

   // Process bars from oldest to newest
   // In as-series mode: highest index = oldest, 0 = current
   // We iterate from startBar down to 1 (don't process bar 0 = forming bar)
   for(int barShift = startBar; barShift >= 1; barShift--)
   {
      ProcessBar(barShift, rates_total);
   }

   return(rates_total);
}

// ============================================================================
// PROCESS SINGLE BAR (mirror of EA's OnTick new-bar logic)
// ============================================================================
void ProcessBar(int bar, int totalBars)
{
   // bar = the "current" bar shift being processed
   // Pivot detection: look at bar + PIVOT_LEN (the confirmed pivot)
   int checkBar = bar + PIVOT_LEN;
   if(checkBar >= totalBars) return;

   bool isSwH = IsPivotHigh(checkBar, PIVOT_LEN, totalBars);
   bool isSwL = IsPivotLow(checkBar, PIVOT_LEN, totalBars);

   datetime checkTime = iTime(_Symbol, _Period, checkBar);
   double   checkHigh = iHigh(_Symbol, _Period, checkBar);
   double   checkLow  = iLow(_Symbol, _Period, checkBar);

   // ── Swing markers (on the pivot bar itself) ──
   if(SHOW_SWINGS)
   {
      if(isSwH)
      {
         double pad = (checkHigh - checkLow) * 0.3;
         if(pad < _Point * 5) pad = _Point * 5;
         g_swingHBuf[checkBar] = checkHigh + pad;
      }
      if(isSwL)
      {
         double pad = (checkHigh - checkLow) * 0.3;
         if(pad < _Point * 5) pad = _Point * 5;
         g_swingLBuf[checkBar] = checkLow - pad;
      }
   }

   // ── Update Swing Low first (same order as Pine Script) ──
   if(isSwL)
   {
      g_sl0 = g_sl1;       g_sl0_time = g_sl1_time;
      g_sl1 = checkLow;    g_sl1_time = checkTime;
   }

   // ── Update Swing High ──
   if(isSwH)
   {
      g_slBeforeSH = g_sl1;       g_slBeforeSH_time = g_sl1_time;
      g_sh0 = g_sh1;       g_sh0_time = g_sh1_time;
      g_sh1 = checkHigh;   g_sh1_time = checkTime;
   }

   // ── Update shBeforeSL ──
   if(isSwL)
   {
      g_shBeforeSL = g_sh1;       g_shBeforeSL_time = g_sh1_time;
   }

   // ================================================================
   // STEP 2: HH/LL DETECTION + IMPULSE FILTER
   // ================================================================
   bool isNewHH = isSwH && g_sh0 != EMPTY_VALUE && g_sh1 > g_sh0;
   bool isNewLL = isSwL && g_sl0 != EMPTY_VALUE && g_sl1 < g_sl0;

   // Impulse Body Filter (BUY)
   if(isNewHH && IMPULSE_MULT > 0)
   {
      double avgBody = CalcAvgBody(bar, 20, totalBars);
      int sh0Shift = TimeToShift(g_sh0_time);
      int toBar    = checkBar;   // sh1 position = checkBar
      bool found   = false;
      if(sh0Shift >= 0)
      {
         for(int i = sh0Shift; i >= toBar; i--)
         {
            if(i < 0) continue;
            if(iClose(_Symbol, _Period, i) > g_sh0)
            {
               double body = MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i));
               found = (body >= IMPULSE_MULT * avgBody);
               break;
            }
         }
      }
      if(!found) isNewHH = false;
   }

   // Impulse Body Filter (SELL)
   if(isNewLL && IMPULSE_MULT > 0)
   {
      double avgBody = CalcAvgBody(bar, 20, totalBars);
      int sl0Shift = TimeToShift(g_sl0_time);
      int toBar    = checkBar;
      bool found   = false;
      if(sl0Shift >= 0)
      {
         for(int i = sl0Shift; i >= toBar; i--)
         {
            if(i < 0) continue;
            if(iClose(_Symbol, _Period, i) < g_sl0)
            {
               double body = MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i));
               found = (body >= IMPULSE_MULT * avgBody);
               break;
            }
         }
      }
      if(!found) isNewLL = false;
   }

   // ── Break Strength Filter ──
   bool rawBreakUp   = false;
   bool rawBreakDown = false;

   if(isNewHH && g_slBeforeSH != EMPTY_VALUE)
   {
      if(BREAK_MULT <= 0)
         rawBreakUp = true;
      else
      {
         double swR = g_sh0 - g_slBeforeSH;
         double brD = g_sh1 - g_sh0;
         if(swR > 0 && brD >= swR * BREAK_MULT)
            rawBreakUp = true;
      }
   }

   if(isNewLL && g_shBeforeSL != EMPTY_VALUE)
   {
      if(BREAK_MULT <= 0)
         rawBreakDown = true;
      else
      {
         double swR = g_shBeforeSL - g_sl0;
         double brD = g_sl0 - g_sl1;
         if(swR > 0 && brD >= swR * BREAK_MULT)
            rawBreakDown = true;
      }
   }

   // ================================================================
   // STEP 3: CONFIRMATION STATE MACHINE
   // ================================================================
   bool confirmedBuy  = false;
   bool confirmedSell = false;
   double confEntry = 0, confSL = 0, confW1Peak = 0;
   datetime confEntryTime = 0, confSLTime = 0;
   datetime confWaveTime = 0;
   double confWaveHigh = 0, confWaveLow = 0;

   // Read bar+1 from current = the "previous completed bar" relative to this processing bar
   // But in indicator context, 'bar' is bar being processed.
   // The EA checks bar 1 (previous completed). Here, 'bar' is the newly completed bar,
   // so we use 'bar' itself for the state checks (just like EA uses bar 1 = last completed).
   double prevHigh  = iHigh(_Symbol, _Period, bar);
   double prevLow   = iLow(_Symbol, _Period, bar);
   double prevClose = iClose(_Symbol, _Period, bar);
   double prevOpen  = iOpen(_Symbol, _Period, bar);

   // -- Wait for Confirm: Close beyond W1 Peak (BUY) --
   if(g_pendingState == 1)
   {
      if(g_pendW1Trough == EMPTY_VALUE || prevLow < g_pendW1Trough)
         g_pendW1Trough = prevLow;
      if(g_pendSL != EMPTY_VALUE && prevLow <= g_pendSL)
         g_pendingState = 0;
      else if(g_pendBreakPoint != EMPTY_VALUE && prevLow <= g_pendBreakPoint)
         g_pendingState = 0;
      else if(g_pendW1Peak != EMPTY_VALUE && prevClose > g_pendW1Peak)
      {
         // Confirmed BUY!
         confirmedBuy  = true;
         confEntry     = g_pendBreakPoint;
         confSL        = g_pendSL;
         confW1Peak    = g_pendW1Peak;
         confEntryTime = g_pendBreak_time;
         confSLTime    = g_pendSL_time;
         confWaveTime  = iTime(_Symbol, _Period, bar);
         confWaveHigh  = prevHigh;
         confWaveLow   = prevLow;
         g_pendingState = 0;
      }
   }

   // -- Wait for Confirm: Close beyond W1 Peak (SELL) --
   if(g_pendingState == -1)
   {
      if(g_pendW1Trough == EMPTY_VALUE || prevHigh > g_pendW1Trough)
         g_pendW1Trough = prevHigh;
      if(g_pendSL != EMPTY_VALUE && prevHigh >= g_pendSL)
         g_pendingState = 0;
      else if(g_pendBreakPoint != EMPTY_VALUE && prevHigh >= g_pendBreakPoint)
         g_pendingState = 0;
      else if(g_pendW1Peak != EMPTY_VALUE && prevClose < g_pendW1Peak)
      {
         // Confirmed SELL!
         confirmedSell = true;
         confEntry     = g_pendBreakPoint;
         confSL        = g_pendSL;
         confW1Peak    = g_pendW1Peak;
         confEntryTime = g_pendBreak_time;
         confSLTime    = g_pendSL_time;
         confWaveTime  = iTime(_Symbol, _Period, bar);
         confWaveHigh  = prevHigh;
         confWaveLow   = prevLow;
         g_pendingState = 0;
      }
   }

   // ================================================================
   // STEP 4: NEW RAW BREAK → Start tracking W1 Peak + Phase 1
   // ================================================================
   if(rawBreakUp)
   {
      // --- Find W1 Peak ---
      double w1Peak       = EMPTY_VALUE;
      int    w1BarShift   = -1;
      double w1TroughInit = EMPTY_VALUE;
      bool   foundBreak   = false;

      int sh0Shift = TimeToShift(g_sh0_time);
      if(sh0Shift >= 0)
      {
         for(int i = sh0Shift; i >= bar; i--)
         {
            double cl = iClose(_Symbol, _Period, i);
            double op = iOpen(_Symbol, _Period, i);
            double hi = iHigh(_Symbol, _Period, i);
            double lo = iLow(_Symbol, _Period, i);

            if(!foundBreak)
            {
               if(cl > g_sh0)
               {
                  foundBreak   = true;
                  w1Peak       = hi;
                  w1BarShift   = i;
                  w1TroughInit = lo;
               }
            }
            else
            {
               if(hi > w1Peak) { w1Peak = hi; w1BarShift = i; }
               if(w1TroughInit == EMPTY_VALUE || lo < w1TroughInit) w1TroughInit = lo;
               if(cl < op) break;  // First bearish → end of W1
            }
         }
      }

      if(w1Peak != EMPTY_VALUE)
      {
         g_pendingState   = 1;
         g_pendBreakPoint = g_sh0;
         g_pendW1Peak     = w1Peak;
         g_pendW1Trough   = w1TroughInit;
         g_pendSL         = g_slBeforeSH;
         g_pendSL_time    = g_slBeforeSH_time;
         g_pendBreak_time = g_sh0_time;

         // Retro scan
         int retroFrom = w1BarShift - 1;
         if(retroFrom < bar) retroFrom = bar;
         for(int i = retroFrom; i >= bar; i--)
         {
            double rH = iHigh(_Symbol, _Period, i);
            double rL = iLow(_Symbol, _Period, i);
            double rC = iClose(_Symbol, _Period, i);

            if(g_pendingState == 1)
            {
               if(g_pendW1Trough == EMPTY_VALUE || rL < g_pendW1Trough)
                  g_pendW1Trough = rL;
               if(g_pendSL != EMPTY_VALUE && rL <= g_pendSL)
               { g_pendingState = 0; break; }
               if(rL <= g_pendBreakPoint)
               { g_pendingState = 0; break; }
               if(rC > g_pendW1Peak)
               {
                  // Confirmed BUY (retro scan)
                  confirmedBuy  = true;
                  confEntry     = g_pendBreakPoint;
                  confSL        = g_pendSL;
                  confW1Peak    = g_pendW1Peak;
                  confEntryTime = g_pendBreak_time;
                  confSLTime    = g_pendSL_time;
                  confWaveTime  = iTime(_Symbol, _Period, i);
                  confWaveHigh  = rH;
                  confWaveLow   = rL;
                  g_pendingState = 0;
                  break;
               }
            }
            if(g_pendingState == 0) break;
         }
      }
   }

   // ── rawBreakDown ──
   if(rawBreakDown)
   {
      double w1Trough    = EMPTY_VALUE;
      int    w1BarShift  = -1;
      double w1PeakInit  = EMPTY_VALUE;
      bool   foundBreak  = false;

      int sl0Shift = TimeToShift(g_sl0_time);
      if(sl0Shift >= 0)
      {
         for(int i = sl0Shift; i >= bar; i--)
         {
            double cl = iClose(_Symbol, _Period, i);
            double op = iOpen(_Symbol, _Period, i);
            double lo = iLow(_Symbol, _Period, i);
            double hi = iHigh(_Symbol, _Period, i);

            if(!foundBreak)
            {
               if(cl < g_sl0)
               {
                  foundBreak  = true;
                  w1Trough    = lo;
                  w1BarShift  = i;
                  w1PeakInit  = hi;
               }
            }
            else
            {
               if(lo < w1Trough) { w1Trough = lo; w1BarShift = i; }
               if(w1PeakInit == EMPTY_VALUE || hi > w1PeakInit) w1PeakInit = hi;
               if(cl > op) break;  // First bullish → end of W1
            }
         }
      }

      if(w1Trough != EMPTY_VALUE)
      {
         g_pendingState   = -1;
         g_pendBreakPoint = g_sl0;
         g_pendW1Peak     = w1Trough;
         g_pendW1Trough   = w1PeakInit;
         g_pendSL         = g_shBeforeSL;
         g_pendSL_time    = g_shBeforeSL_time;
         g_pendBreak_time = g_sl0_time;

         int retroFrom = w1BarShift - 1;
         if(retroFrom < bar) retroFrom = bar;
         for(int i = retroFrom; i >= bar; i--)
         {
            double rH = iHigh(_Symbol, _Period, i);
            double rL = iLow(_Symbol, _Period, i);
            double rC = iClose(_Symbol, _Period, i);

            if(g_pendingState == -1)
            {
               if(g_pendW1Trough == EMPTY_VALUE || rH > g_pendW1Trough)
                  g_pendW1Trough = rH;
               if(g_pendSL != EMPTY_VALUE && rH >= g_pendSL)
               { g_pendingState = 0; break; }
               if(rH >= g_pendBreakPoint)
               { g_pendingState = 0; break; }
               if(rC < g_pendW1Peak)
               {
                  // Confirmed SELL (retro scan)
                  confirmedSell = true;
                  confEntry     = g_pendBreakPoint;
                  confSL        = g_pendSL;
                  confW1Peak    = g_pendW1Peak;
                  confEntryTime = g_pendBreak_time;
                  confSLTime    = g_pendSL_time;
                  confWaveTime  = iTime(_Symbol, _Period, i);
                  confWaveHigh  = rH;
                  confWaveLow   = rL;
                  g_pendingState = 0;
                  break;
               }
            }
            if(g_pendingState == 0) break;
         }
      }
   }

   // ================================================================
   // STEP 5: PROCESS CONFIRMED SIGNALS
   // ================================================================
   if(confirmedBuy)
      DrawSignal(true, bar, confEntry, confSL, confW1Peak,
                 confEntryTime, confSLTime, confWaveTime,
                 confWaveHigh, confWaveLow);

   if(confirmedSell)
      DrawSignal(false, bar, confEntry, confSL, confW1Peak,
                 confEntryTime, confSLTime, confWaveTime,
                 confWaveHigh, confWaveLow);
}

// ============================================================================
// DRAW SIGNAL (visual only — no trading)
// ============================================================================
void DrawSignal(bool isBuy, int signalBar, double entry, double sl, double w1Peak,
                datetime entryTime, datetime slTime, datetime waveTime,
                double waveHigh, double waveLow)
{
   g_breakCount++;
   string suffix = IntegerToString(g_breakCount);

   datetime signalTime = iTime(_Symbol, _Period, signalBar);

   // ── Signal marker in buffer ──
   if(isBuy)
      g_sigBuyBuf[signalBar] = entry;
   else
      g_sigSellBuf[signalBar] = entry;

   // ── Lines ──
   if(SHOW_BREAK_LINE)
   {
      // Entry line
      string entName = g_objPrefix + "ENT_" + suffix;
      DrawHLine(entName, entryTime, entry, signalTime,
                isBuy ? COL_ENTRY_BUY : COL_ENTRY_SELL, STYLE_DASH, 1);

      // SL line
      string slName = g_objPrefix + "SL_" + suffix;
      DrawHLine(slName, slTime, sl, signalTime, COL_SL, STYLE_DASH, 1);

      // Entry label
      string entLbl = g_objPrefix + "ENTLBL_" + suffix;
      DrawTextLabel(entLbl, signalTime, entry,
                    isBuy ? "Entry Buy" : "Entry Sell",
                    isBuy ? COL_ENTRY_BUY : COL_ENTRY_SELL, 7);

      // SL label
      string slLbl = g_objPrefix + "SLLBL_" + suffix;
      DrawTextLabel(slLbl, signalTime, sl, "SL", COL_SL, 7);

      // TP line (Confirm Break high/low)
      double tp = isBuy ? waveHigh : waveLow;
      if(tp > 0)
      {
         string tpName = g_objPrefix + "TP_" + suffix;
         string tpLbl  = g_objPrefix + "TPLBL_" + suffix;
         DrawHLine(tpName, entryTime, tp, signalTime, COL_TP, STYLE_DASH, 1);
         DrawTextLabel(tpLbl, signalTime, tp, "TP (Conf)", COL_TP, 7);
      }
   }

   // ── Confirm Break label ──
   if(SHOW_BREAK_LABEL && waveTime > 0)
   {
      string lblName = g_objPrefix + (isBuy ? "CONF_UP_" : "CONF_DN_") + suffix;
      if(isBuy)
         DrawTextLabel(lblName, waveTime, waveHigh,
                       "▲ Confirm Break", COL_BREAK_UP, 9);
      else
         DrawTextLabel(lblName, waveTime, waveLow,
                       "▼ Confirm Break", COL_BREAK_DOWN, 9);
   }

   // ── Alert ──
   datetime lastSig = isBuy ? g_lastBuySignal : g_lastSellSignal;
   if(signalTime > lastSig)
   {
      if(isBuy) g_lastBuySignal = signalTime;
      else      g_lastSellSignal = signalTime;

      // Only alert if this is a recent bar (not historical recalculation)
      datetime currentTime = TimeCurrent();
      if(currentTime - signalTime < PeriodSeconds(_Period) * 3)
      {
         double tp = isBuy ? waveHigh : waveLow;
         string msg = StringFormat("MST Medio: %s | Entry=%.2f SL=%.2f TP=%.2f | %s",
                                    isBuy ? "BUY" : "SELL",
                                    entry, sl, tp, _Symbol);
         Alert(msg);
         Print("🔔 ", msg);
      }
   }
}
//+------------------------------------------------------------------+
