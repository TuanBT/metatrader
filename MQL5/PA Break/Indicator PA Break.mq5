//+------------------------------------------------------------------+
//| Indicator PA Break.mq5                                           |
//| PA Break — Swing HH/LL Breakout Detection                       |
//| Converted from TradingView Pine Script v0.2.0                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MTS"
#property link      ""
#property version   "1.00"
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
#property indicator_color2  clrDodgerBlue
#property indicator_width2  1

// Plot 3: Break Buy signal (hidden buffer for EA)
#property indicator_label3  "BreakBuy"
#property indicator_type3   DRAW_NONE

// Plot 4: Break Sell signal (hidden buffer for EA)
#property indicator_label4  "BreakSell"
#property indicator_type4   DRAW_NONE

//--- Inputs
input int    InpPivotLen      = 5;     // Pivot Lookback
input double InpBreakMult     = 1.0;   // Break Strength (x Swing Range)
input bool   InpShowSwings    = true;  // Show Swing Points
input bool   InpShowBreakLabel= true;  // Show Break Labels
input bool   InpShowBreakLine = true;  // Show Entry/SL Lines
input color  InpColBreakUp    = clrLime;       // Break UP Label Color
input color  InpColBreakDown  = clrRed;        // Break DOWN Label Color
input color  InpColEntryBuy   = clrDodgerBlue; // Entry Buy Line Color
input color  InpColEntrySell  = clrHotPink;    // Entry Sell Line Color
input color  InpColSL         = clrYellow;     // SL Line Color
input bool   InpEnableAlerts  = true;          // Enable Alerts

//--- Buffers
double g_swingHBuf[];
double g_swingLBuf[];
double g_breakBuyBuf[];
double g_breakSellBuf[];

//--- Object prefix
string g_objPrefix = "PAB_";

//--- Alert tracking
datetime g_lastAlertTime = 0;

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, g_swingHBuf, INDICATOR_DATA);
   SetIndexBuffer(1, g_swingLBuf, INDICATOR_DATA);
   SetIndexBuffer(2, g_breakBuyBuf, INDICATOR_DATA);
   SetIndexBuffer(3, g_breakSellBuf, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 234); // Down triangle for swing high
   PlotIndexSetInteger(1, PLOT_ARROW, 233); // Up triangle for swing low

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Unique prefix to avoid collisions
   string number = StringFormat("%I64d", GetTickCount64());
   g_objPrefix = StringSubstr(number, MathMax(0, StringLen(number) - 4)) + "_PAB_";

   IndicatorSetString(INDICATOR_SHORTNAME, "PA Break v0.2.0");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteObjectsByPrefix(g_objPrefix);
}

//+------------------------------------------------------------------+
// Pivot High detection: high[i] is the highest in range [i-pivotLen, i+pivotLen]
bool IsPivotHigh(const double &high[], int i, int pivotLen, int total)
{
   if(i - pivotLen < 0 || i + pivotLen >= total)
      return false;

   double val = high[i];
   for(int j = i - pivotLen; j <= i + pivotLen; j++)
   {
      if(j == i) continue;
      if(high[j] >= val)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
// Pivot Low detection: low[i] is the lowest in range [i-pivotLen, i+pivotLen]
bool IsPivotLow(const double &low[], int i, int pivotLen, int total)
{
   if(i - pivotLen < 0 || i + pivotLen >= total)
      return false;

   double val = low[i];
   for(int j = i - pivotLen; j <= i + pivotLen; j++)
   {
      if(j == i) continue;
      if(low[j] <= val)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
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
   if(rates_total < InpPivotLen * 2 + 2)
      return(rates_total);

   // Clear buffers
   ArrayFill(g_swingHBuf,   0, rates_total, EMPTY_VALUE);
   ArrayFill(g_swingLBuf,   0, rates_total, EMPTY_VALUE);
   ArrayFill(g_breakBuyBuf, 0, rates_total, EMPTY_VALUE);
   ArrayFill(g_breakSellBuf,0, rates_total, EMPTY_VALUE);

   // Delete old objects and redraw
   DeleteObjectsByPrefix(g_objPrefix);

   // ── Swing History Variables ──
   double sh1 = EMPTY_VALUE, sh0 = EMPTY_VALUE;   // Swing High current / previous
   int    sh1_idx = -1,      sh0_idx = -1;
   double sl1 = EMPTY_VALUE, sl0 = EMPTY_VALUE;   // Swing Low current / previous
   int    sl1_idx = -1,      sl0_idx = -1;

   double slBeforeSH = EMPTY_VALUE;   // Swing Low before latest Swing High
   int    slBeforeSH_idx = -1;
   double shBeforeSL = EMPTY_VALUE;   // Swing High before latest Swing Low
   int    shBeforeSL_idx = -1;

   // ── Active line tracking ──
   string activeEntryName = "";
   string activeSLName    = "";
   string activeEntryLblName = "";
   string activeSLLblName    = "";
   double activeEntryPrice = EMPTY_VALUE;
   double activeSLPrice    = EMPTY_VALUE;
   datetime activeLineStart = 0;
   bool   activeIsBuy      = false;

   // ── Main loop (left to right, non-series) ──
   int startBar = InpPivotLen;
   int endBar   = rates_total - InpPivotLen - 1;

   for(int i = startBar; i <= endBar; i++)
   {
      // ── Detect Swing High at bar i (confirmed by pivotLen bars right) ──
      bool isSwH = IsPivotHigh(high, i, InpPivotLen, rates_total);
      bool isSwL = IsPivotLow(low, i, InpPivotLen, rates_total);

      // ── Update Swing Low first (same order as Pine Script) ──
      if(isSwL)
      {
         sl0 = sl1;
         sl0_idx = sl1_idx;
         sl1 = low[i];
         sl1_idx = i;
      }

      // ── Update Swing High ──
      if(isSwH)
      {
         // Record swing low before this swing high
         slBeforeSH = sl1;
         slBeforeSH_idx = sl1_idx;

         sh0 = sh1;
         sh0_idx = sh1_idx;
         sh1 = high[i];
         sh1_idx = i;
      }

      // ── Update shBeforeSL ──
      if(isSwL)
      {
         shBeforeSL = sh1;
         shBeforeSL_idx = sh1_idx;
      }

      // ── Show swing markers ──
      if(InpShowSwings)
      {
         if(isSwH)
         {
            double pad = (high[i] - low[i]) * 0.3;
            if(pad < _Point * 5) pad = _Point * 5;
            g_swingHBuf[i] = high[i] + pad;
         }
         if(isSwL)
         {
            double pad = (high[i] - low[i]) * 0.3;
            if(pad < _Point * 5) pad = _Point * 5;
            g_swingLBuf[i] = low[i] - pad;
         }
      }

      // ── Detect HH / LL ──
      bool isNewHH = isSwH && sh0 != EMPTY_VALUE && sh1 > sh0;
      bool isNewLL = isSwL && sl0 != EMPTY_VALUE && sl1 < sl0;

      // ── Break Strength Filter ──
      bool breakUp = false;
      bool breakDown = false;

      if(isNewHH && slBeforeSH != EMPTY_VALUE)
      {
         double swingRange = sh0 - slBeforeSH;
         double breakDist  = sh1 - sh0;
         if(swingRange > 0 && breakDist >= swingRange * InpBreakMult)
            breakUp = true;
      }

      if(isNewLL && shBeforeSL != EMPTY_VALUE)
      {
         double swingRange = shBeforeSL - sl0;
         double breakDist  = sl0 - sl1;
         if(swingRange > 0 && breakDist >= swingRange * InpBreakMult)
            breakDown = true;
      }

      // ── Process Breakout ──
      // The breakout is confirmed at bar (i + pivotLen) since pivot needs right bars.
      // But the swing itself is at bar i. We draw from the old swing level.
      int confirmBar = i + InpPivotLen;
      if(confirmBar >= rates_total) confirmBar = rates_total - 1;

      if(breakUp || breakDown)
      {
         // Terminate previous active lines at this break point
         if(activeEntryName != "" && activeLineStart > 0)
         {
            DrawHLine(activeEntryName, activeLineStart, activeEntryPrice,
                      time[i], activeIsBuy ? InpColEntryBuy : InpColEntrySell,
                      STYLE_DASH, 1);
            DrawHLine(activeSLName, activeLineStart, activeSLPrice,
                      time[i], InpColSL, STYLE_DASH, 1);
            // Move label to end
            DrawTextLabel(activeEntryLblName, time[i], activeEntryPrice,
                         activeIsBuy ? "Entry Buy" : "Entry Sell",
                         activeIsBuy ? InpColEntryBuy : InpColEntrySell, 7);
            DrawTextLabel(activeSLLblName, time[i], activeSLPrice,
                         "SL", InpColSL, 7);
         }
      }

      if(breakUp)
      {
         g_breakBuyBuf[confirmBar] = sh0; // Entry level = old swing high

         // Break label
         if(InpShowBreakLabel)
         {
            double pad = (sh1 - (sl1 != EMPTY_VALUE ? sl1 : sh1)) * 0.1;
            if(pad < _Point * 10) pad = _Point * 10;
            string lblName = g_objPrefix + "BRK_UP_" + IntegerToString(i);
            DrawTextLabel(lblName, time[sh1_idx], sh1 + pad, "▲ Break", InpColBreakUp, 9);
         }

         // Start new Entry/SL lines
         if(InpShowBreakLine && sh0_idx >= 0 && slBeforeSH_idx >= 0)
         {
            activeIsBuy = true;
            activeEntryPrice = sh0;
            activeSLPrice    = slBeforeSH;
            activeLineStart  = time[sh0_idx];

            string suffix = IntegerToString(i);
            activeEntryName    = g_objPrefix + "ENT_" + suffix;
            activeSLName       = g_objPrefix + "SL_" + suffix;
            activeEntryLblName = g_objPrefix + "ENTLBL_" + suffix;
            activeSLLblName    = g_objPrefix + "SLLBL_" + suffix;
         }

         // Alert
         if(InpEnableAlerts && confirmBar >= rates_total - 2 && time[confirmBar] > g_lastAlertTime)
         {
            Alert("PA Break BUY: ", _Symbol, " HH at ", DoubleToString(sh1, _Digits),
                  " Entry=", DoubleToString(sh0, _Digits),
                  " SL=", DoubleToString(slBeforeSH, _Digits));
            g_lastAlertTime = time[confirmBar];
         }
      }

      if(breakDown)
      {
         g_breakSellBuf[confirmBar] = sl0; // Entry level = old swing low

         // Break label
         if(InpShowBreakLabel)
         {
            double pad = ((sh1 != EMPTY_VALUE ? sh1 : sl1) - sl1) * 0.1;
            if(pad < _Point * 10) pad = _Point * 10;
            string lblName = g_objPrefix + "BRK_DN_" + IntegerToString(i);
            DrawTextLabel(lblName, time[sl1_idx], sl1 - pad, "▼ Break", InpColBreakDown, 9);
         }

         // Start new Entry/SL lines
         if(InpShowBreakLine && sl0_idx >= 0 && shBeforeSL_idx >= 0)
         {
            activeIsBuy = false;
            activeEntryPrice = sl0;
            activeSLPrice    = shBeforeSL;
            activeLineStart  = time[sl0_idx];

            string suffix = IntegerToString(i);
            activeEntryName    = g_objPrefix + "ENT_" + suffix;
            activeSLName       = g_objPrefix + "SL_" + suffix;
            activeEntryLblName = g_objPrefix + "ENTLBL_" + suffix;
            activeSLLblName    = g_objPrefix + "SLLBL_" + suffix;
         }

         // Alert
         if(InpEnableAlerts && confirmBar >= rates_total - 2 && time[confirmBar] > g_lastAlertTime)
         {
            Alert("PA Break SELL: ", _Symbol, " LL at ", DoubleToString(sl1, _Digits),
                  " Entry=", DoubleToString(sl0, _Digits),
                  " SL=", DoubleToString(shBeforeSL, _Digits));
            g_lastAlertTime = time[confirmBar];
         }
      }
   }

   // ── Draw the last active line set extending to current bar ──
   if(activeEntryName != "" && activeLineStart > 0)
   {
      datetime endTime = time[rates_total - 1];
      DrawHLine(activeEntryName, activeLineStart, activeEntryPrice,
                endTime, activeIsBuy ? InpColEntryBuy : InpColEntrySell,
                STYLE_DASH, 1);
      DrawHLine(activeSLName, activeLineStart, activeSLPrice,
                endTime, InpColSL, STYLE_DASH, 1);
      DrawTextLabel(activeEntryLblName, endTime, activeEntryPrice,
                   activeIsBuy ? "Entry Buy" : "Entry Sell",
                   activeIsBuy ? InpColEntryBuy : InpColEntrySell, 7);
      DrawTextLabel(activeSLLblName, endTime, activeSLPrice,
                   "SL", InpColSL, 7);
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
