//+------------------------------------------------------------------+
//| Indicator MST Medio 2.mq5                                       |
//| MST Medio 2 — Simplified 2-Step Breakout Confirmation           |
//| Indicator-only (no trading). Visual on chart.                   |
//|                                                                  |
//| Core logic same as MST Medio v2.0:                              |
//|   1. Swing High/Low → HH/LL detection                          |
//|   2. Impulse body filter                                        |
//|   3. W1 Peak scan → Confirm close beyond W1 → Signal           |
//|   Entry = old SH/SL, SL = swing opposite, TP = confirm candle  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MTS"
#property link      ""
#property version   "1.00"
#property strict

#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "SwingHigh"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrOrange
#property indicator_width1  1

#property indicator_label2  "SwingLow"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrCornflowerBlue
#property indicator_width2  1

#property indicator_label3  "SignalBuy"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLime
#property indicator_width3  2

#property indicator_label4  "SignalSell"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrRed
#property indicator_width4  2

//--- Inputs
input bool InpShowSwings = false;  // Show Swing Points

//--- Fixed strategy params
#define PIVOT_LEN     3
#define IMPULSE_MULT  1.0

//--- Buffers
double g_swHBuf[], g_swLBuf[], g_buyBuf[], g_sellBuf[];

//--- Object prefix
string g_pre = "M2_";

//--- Swing state
double   g_sh1, g_sh0, g_sl1, g_sl0;
datetime g_sh1_t, g_sh0_t, g_sl1_t, g_sl0_t;
double   g_slBeforeSH, g_shBeforeSL;
datetime g_slBeforeSH_t, g_shBeforeSL_t;

//--- Pending confirmation state
int      g_pState;        // 0=idle, 1=wait BUY confirm, -1=wait SELL confirm
double   g_pEntry;        // Entry level (old SH/SL)
double   g_pW1Peak;       // W1 peak (BUY) or W1 trough (SELL)
double   g_pW1Track;      // Tracking trough (BUY) or peak (SELL)
double   g_pSL;           // SL level
datetime g_pSL_t, g_pEntry_t;

//--- Signal counter
int g_cnt;

// ============================================================================
// HELPERS
// ============================================================================
bool IsPivotHigh(int bar, int len, int total)
{
   double val = iHigh(_Symbol, _Period, bar);
   for(int j = bar - len; j <= bar + len; j++)
   {
      if(j == bar || j < 0 || j >= total) continue;
      if(iHigh(_Symbol, _Period, j) >= val) return false;
   }
   return true;
}

bool IsPivotLow(int bar, int len, int total)
{
   double val = iLow(_Symbol, _Period, bar);
   for(int j = bar - len; j <= bar + len; j++)
   {
      if(j == bar || j < 0 || j >= total) continue;
      if(iLow(_Symbol, _Period, j) <= val) return false;
   }
   return true;
}

double CalcAvgBody(int from, int period, int total)
{
   double sum = 0; int cnt = 0;
   for(int i = from; i < from + period && i < total; i++)
   { sum += MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i)); cnt++; }
   return cnt > 0 ? sum / cnt : 0;
}

int TimeToShift(datetime t)
{ return t == 0 ? -1 : iBarShift(_Symbol, _Period, t, false); }

void DrawLine(string name, datetime t1, double p1, datetime t2, double p2,
              color clr, ENUM_LINE_STYLE style = STYLE_DASH)
{
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2))
   { ObjectMove(0, name, 0, t1, p1); ObjectMove(0, name, 1, t2, p2); }
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawLabel(string name, datetime t, double p, string txt, color clr, int sz = 8)
{
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, p))
      ObjectMove(0, name, 0, t, p);
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, sz);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DeleteAll()
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {  string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, g_pre) == 0) ObjectDelete(0, n); }
}

// ============================================================================
// INIT / DEINIT
// ============================================================================
int OnInit()
{
   SetIndexBuffer(0, g_swHBuf, INDICATOR_DATA);
   SetIndexBuffer(1, g_swLBuf, INDICATOR_DATA);
   SetIndexBuffer(2, g_buyBuf, INDICATOR_DATA);
   SetIndexBuffer(3, g_sellBuf, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 234);
   PlotIndexSetInteger(1, PLOT_ARROW, 233);
   PlotIndexSetInteger(2, PLOT_ARROW, 233);
   PlotIndexSetInteger(3, PLOT_ARROW, 234);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   string num = StringFormat("%I64d", GetTickCount64());
   g_pre = StringSubstr(num, MathMax(0, StringLen(num) - 4)) + "_M2_";

   ResetState();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { DeleteAll(); }

void ResetState()
{
   g_sh1 = g_sh0 = g_sl1 = g_sl0 = EMPTY_VALUE;
   g_sh1_t = g_sh0_t = g_sl1_t = g_sl0_t = 0;
   g_slBeforeSH = g_shBeforeSL = EMPTY_VALUE;
   g_slBeforeSH_t = g_shBeforeSL_t = 0;
   g_pState = 0;
   g_pEntry = g_pW1Peak = g_pW1Track = g_pSL = EMPTY_VALUE;
   g_pSL_t = g_pEntry_t = 0;
   g_cnt = 0;
}

// ============================================================================
// MAIN
// ============================================================================
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   if(rates_total < PIVOT_LEN * 2 + 25) return 0;

   int startBar;
   if(prev_calculated == 0)
   {
      DeleteAll(); ResetState();
      startBar = rates_total - 1;
      ArrayInitialize(g_swHBuf, EMPTY_VALUE);
      ArrayInitialize(g_swLBuf, EMPTY_VALUE);
      ArrayInitialize(g_buyBuf, EMPTY_VALUE);
      ArrayInitialize(g_sellBuf, EMPTY_VALUE);
   }
   else
   {
      startBar = rates_total - prev_calculated;
      if(startBar < 1) startBar = 1;
   }

   ArraySetAsSeries(g_swHBuf, true);
   ArraySetAsSeries(g_swLBuf, true);
   ArraySetAsSeries(g_buyBuf, true);
   ArraySetAsSeries(g_sellBuf, true);

   for(int bar = startBar; bar >= 1; bar--)
      ProcessBar(bar, rates_total);

   return rates_total;
}

// ============================================================================
// PROCESS BAR
// ============================================================================
void ProcessBar(int bar, int total)
{
   int cb = bar + PIVOT_LEN;  // confirmed pivot bar
   if(cb >= total) return;

   bool swH = IsPivotHigh(cb, PIVOT_LEN, total);
   bool swL = IsPivotLow(cb, PIVOT_LEN, total);

   datetime cbTime = iTime(_Symbol, _Period, cb);
   double   cbHigh = iHigh(_Symbol, _Period, cb);
   double   cbLow  = iLow(_Symbol, _Period, cb);

   // Swing markers
   if(InpShowSwings)
   {
      double pad = (cbHigh - cbLow) * 0.3;
      if(pad < _Point * 5) pad = _Point * 5;
      if(swH) g_swHBuf[cb] = cbHigh + pad;
      if(swL) g_swLBuf[cb] = cbLow - pad;
   }

   // Update swing history (same order as Pine)
   if(swL) { g_sl0 = g_sl1; g_sl0_t = g_sl1_t; g_sl1 = cbLow; g_sl1_t = cbTime; }
   if(swH) { g_slBeforeSH = g_sl1; g_slBeforeSH_t = g_sl1_t;
             g_sh0 = g_sh1; g_sh0_t = g_sh1_t; g_sh1 = cbHigh; g_sh1_t = cbTime; }
   if(swL) { g_shBeforeSL = g_sh1; g_shBeforeSL_t = g_sh1_t; }

   // ── HH/LL detection ──
   bool hh = swH && g_sh0 != EMPTY_VALUE && g_sh1 > g_sh0;
   bool ll = swL && g_sl0 != EMPTY_VALUE && g_sl1 < g_sl0;

   // ── Impulse filter ──
   if(hh)
   {
      double avg = CalcAvgBody(bar, 20, total);
      int sh0s = TimeToShift(g_sh0_t);
      bool ok = false;
      if(sh0s >= 0)
         for(int i = sh0s; i >= cb; i--)
         {  if(i < 0) continue;
            if(iClose(_Symbol, _Period, i) > g_sh0)
            { ok = MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i)) >= IMPULSE_MULT * avg; break; } }
      if(!ok) hh = false;
   }
   if(ll)
   {
      double avg = CalcAvgBody(bar, 20, total);
      int sl0s = TimeToShift(g_sl0_t);
      bool ok = false;
      if(sl0s >= 0)
         for(int i = sl0s; i >= cb; i--)
         {  if(i < 0) continue;
            if(iClose(_Symbol, _Period, i) < g_sl0)
            { ok = MathAbs(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i)) >= IMPULSE_MULT * avg; break; } }
      if(!ok) ll = false;
   }

   // ── Raw break (breakMult=0 → always pass) ──
   bool breakUp  = hh && g_slBeforeSH != EMPTY_VALUE;
   bool breakDn  = ll && g_shBeforeSL != EMPTY_VALUE;

   // ── Pending state: wait for confirm ──
   double prevH = iHigh(_Symbol, _Period, bar);
   double prevL = iLow(_Symbol, _Period, bar);
   double prevC = iClose(_Symbol, _Period, bar);

   bool confBuy = false, confSell = false;
   double cEntry = 0, cSL = 0, cTP = 0;
   datetime cEntry_t = 0, cSL_t = 0, cWave_t = 0;

   if(g_pState == 1)
   {
      if(g_pW1Track == EMPTY_VALUE || prevL < g_pW1Track) g_pW1Track = prevL;
      if(g_pSL != EMPTY_VALUE && prevL <= g_pSL) g_pState = 0;
      else if(g_pEntry != EMPTY_VALUE && prevL <= g_pEntry) g_pState = 0;
      else if(g_pW1Peak != EMPTY_VALUE && prevC > g_pW1Peak)
      {  confBuy = true;
         cEntry = g_pEntry; cSL = g_pSL; cTP = prevH;
         cEntry_t = g_pEntry_t; cSL_t = g_pSL_t;
         cWave_t = iTime(_Symbol, _Period, bar);
         g_pState = 0; }
   }
   if(g_pState == -1)
   {
      if(g_pW1Track == EMPTY_VALUE || prevH > g_pW1Track) g_pW1Track = prevH;
      if(g_pSL != EMPTY_VALUE && prevH >= g_pSL) g_pState = 0;
      else if(g_pEntry != EMPTY_VALUE && prevH >= g_pEntry) g_pState = 0;
      else if(g_pW1Peak != EMPTY_VALUE && prevC < g_pW1Peak)
      {  confSell = true;
         cEntry = g_pEntry; cSL = g_pSL; cTP = prevL;
         cEntry_t = g_pEntry_t; cSL_t = g_pSL_t;
         cWave_t = iTime(_Symbol, _Period, bar);
         g_pState = 0; }
   }

   // ── New raw break → W1 scan + retro ──
   if(breakUp) ScanW1Buy(bar, total, confBuy, cEntry, cSL, cTP, cEntry_t, cSL_t, cWave_t);
   if(breakDn) ScanW1Sell(bar, total, confSell, cEntry, cSL, cTP, cEntry_t, cSL_t, cWave_t);

   // ── Draw confirmed signals ──
   if(confBuy)  DrawSignal(true,  cEntry, cSL, cTP, cEntry_t, cSL_t, cWave_t, bar);
   if(confSell) DrawSignal(false, cEntry, cSL, cTP, cEntry_t, cSL_t, cWave_t, bar);
}

// ============================================================================
// W1 SCAN — BUY
// ============================================================================
void ScanW1Buy(int bar, int total,
               bool &confBuy, double &cEntry, double &cSL, double &cTP,
               datetime &cEntry_t, datetime &cSL_t, datetime &cWave_t)
{
   double w1 = EMPTY_VALUE;
   int w1s = -1;
   double w1Init = EMPTY_VALUE;
   bool found = false;

   int sh0s = TimeToShift(g_sh0_t);
   if(sh0s < 0) return;

   for(int i = sh0s; i >= bar; i--)
   {
      double cl = iClose(_Symbol, _Period, i);
      double op = iOpen(_Symbol, _Period, i);
      double hi = iHigh(_Symbol, _Period, i);
      double lo = iLow(_Symbol, _Period, i);
      if(!found)
      {  if(cl > g_sh0) { found = true; w1 = hi; w1s = i; w1Init = lo; } }
      else
      {  if(hi > w1) { w1 = hi; w1s = i; }
         if(w1Init == EMPTY_VALUE || lo < w1Init) w1Init = lo;
         if(cl < op) break; }
   }
   if(w1 == EMPTY_VALUE) return;

   g_pState   = 1;
   g_pEntry   = g_sh0;
   g_pW1Peak  = w1;
   g_pW1Track = w1Init;
   g_pSL      = g_slBeforeSH;
   g_pSL_t    = g_slBeforeSH_t;
   g_pEntry_t = g_sh0_t;

   // Retro scan
   int rf = w1s - 1;
   if(rf < bar) rf = bar;
   for(int i = rf; i >= bar; i--)
   {
      if(g_pState != 1) break;
      double rH = iHigh(_Symbol, _Period, i);
      double rL = iLow(_Symbol, _Period, i);
      double rC = iClose(_Symbol, _Period, i);
      if(g_pW1Track == EMPTY_VALUE || rL < g_pW1Track) g_pW1Track = rL;
      if(g_pSL != EMPTY_VALUE && rL <= g_pSL) { g_pState = 0; break; }
      if(rL <= g_pEntry) { g_pState = 0; break; }
      if(rC > g_pW1Peak)
      {  confBuy = true;
         cEntry = g_pEntry; cSL = g_pSL; cTP = rH;
         cEntry_t = g_pEntry_t; cSL_t = g_pSL_t;
         cWave_t = iTime(_Symbol, _Period, i);
         g_pState = 0; break; }
   }
}

// ============================================================================
// W1 SCAN — SELL
// ============================================================================
void ScanW1Sell(int bar, int total,
                bool &confSell, double &cEntry, double &cSL, double &cTP,
                datetime &cEntry_t, datetime &cSL_t, datetime &cWave_t)
{
   double w1 = EMPTY_VALUE;
   int w1s = -1;
   double w1Init = EMPTY_VALUE;
   bool found = false;

   int sl0s = TimeToShift(g_sl0_t);
   if(sl0s < 0) return;

   for(int i = sl0s; i >= bar; i--)
   {
      double cl = iClose(_Symbol, _Period, i);
      double op = iOpen(_Symbol, _Period, i);
      double lo = iLow(_Symbol, _Period, i);
      double hi = iHigh(_Symbol, _Period, i);
      if(!found)
      {  if(cl < g_sl0) { found = true; w1 = lo; w1s = i; w1Init = hi; } }
      else
      {  if(lo < w1) { w1 = lo; w1s = i; }
         if(w1Init == EMPTY_VALUE || hi > w1Init) w1Init = hi;
         if(cl > op) break; }
   }
   if(w1 == EMPTY_VALUE) return;

   g_pState   = -1;
   g_pEntry   = g_sl0;
   g_pW1Peak  = w1;
   g_pW1Track = w1Init;
   g_pSL      = g_shBeforeSL;
   g_pSL_t    = g_shBeforeSL_t;
   g_pEntry_t = g_sl0_t;

   // Retro scan
   int rf = w1s - 1;
   if(rf < bar) rf = bar;
   for(int i = rf; i >= bar; i--)
   {
      if(g_pState != -1) break;
      double rH = iHigh(_Symbol, _Period, i);
      double rL = iLow(_Symbol, _Period, i);
      double rC = iClose(_Symbol, _Period, i);
      if(g_pW1Track == EMPTY_VALUE || rH > g_pW1Track) g_pW1Track = rH;
      if(g_pSL != EMPTY_VALUE && rH >= g_pSL) { g_pState = 0; break; }
      if(rH >= g_pEntry) { g_pState = 0; break; }
      if(rC < g_pW1Peak)
      {  confSell = true;
         cEntry = g_pEntry; cSL = g_pSL; cTP = rL;
         cEntry_t = g_pEntry_t; cSL_t = g_pSL_t;
         cWave_t = iTime(_Symbol, _Period, i);
         g_pState = 0; break; }
   }
}

// ============================================================================
// DRAW SIGNAL
// ============================================================================
void DrawSignal(bool isBuy, double entry, double sl, double tp,
                datetime entry_t, datetime sl_t, datetime wave_t, int bar)
{
   g_cnt++;
   string s = IntegerToString(g_cnt);
   datetime now = iTime(_Symbol, _Period, bar);

   double risk = MathAbs(entry - sl);
   double reward = MathAbs(tp - entry);
   double rr = risk > 0 ? reward / risk : 0;

   // Signal arrow on buffer
   if(isBuy) g_buyBuf[bar] = entry;
   else      g_sellBuf[bar] = entry;

   // Entry / SL / TP lines
   DrawLine(g_pre + "E_" + s, entry_t, entry, now, entry,
            isBuy ? clrDodgerBlue : clrHotPink);
   DrawLine(g_pre + "S_" + s, sl_t, sl, now, sl, clrYellow);
   DrawLine(g_pre + "T_" + s, entry_t, tp, now, tp, clrLimeGreen);

   // Labels
   DrawLabel(g_pre + "EL_" + s, now, entry,
             isBuy ? "Entry Buy" : "Entry Sell",
             isBuy ? clrDodgerBlue : clrHotPink, 7);
   DrawLabel(g_pre + "SL_" + s, now, sl, "SL", clrYellow, 7);
   DrawLabel(g_pre + "TL_" + s, now, tp,
             StringFormat("TP (%.1fR)", rr), clrLimeGreen, 7);

   // Confirm break label
   if(isBuy)
      DrawLabel(g_pre + "CB_" + s, wave_t, iHigh(_Symbol, _Period, bar),
                "▲ Confirm", clrLime, 9);
   else
      DrawLabel(g_pre + "CB_" + s, wave_t, iLow(_Symbol, _Period, bar),
                "▼ Confirm", clrRed, 9);
}
//+------------------------------------------------------------------+
