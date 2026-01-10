//+------------------------------------------------------------------+
//| M15 Impulse FVG Entry                                            |
//| Simplified: calculate directly on chart timeframe                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Tuan"
#property link      "https://mql5.com"
#property version   "2.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5

#property indicator_label1  "Impulse"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrYellow
#property indicator_width1  2

#property indicator_label2  "ZoneHigh"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGray
#property indicator_width2  1
#property indicator_style2  STYLE_DOT

#property indicator_label3  "ZoneLow"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrGray
#property indicator_width3  1
#property indicator_style3  STYLE_DOT

#property indicator_label4  "OutBuy"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_width4  3

#property indicator_label5  "OutSell"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrRed
#property indicator_width5  3

//--- Inputs
input int    InpATRLen       = 14;    // ATR Length (M15)
input double InpATRMult      = 1.2;   // ATR Multiplier
input double InpBodyRatioMin = 0.55;  // Min Body/Range
input bool   InpShowBoxes    = true;  // Draw FVG Box
input bool   InpEnableAlerts = true;  // Alert on OUT signal
input color  InpBoxBuyColor  = clrDodgerBlue;
input color  InpBoxSellColor = clrCrimson;

//--- Buffers
double g_impBuffer[];
double g_zoneHBuffer[];
double g_zoneLBuffer[];
double g_outBuyBuffer[];
double g_outSellBuffer[];

//--- Global state (persistent like Pine Script var)
double g_zoneH = 0;
double g_zoneL = 0;
bool   g_waitingIN = false;
bool   g_waitingOUT = false;
int    g_inBarIndex = -1;
double g_inHigh = 0;
double g_inLow = 0;
double g_minLow = 0;
double g_maxHigh = 0;
datetime g_m15BarTime = 0;
datetime g_lastAlertTime = 0;
int    g_zoneStartBar = -1;  // Bar index where zone starts (last bar of M15 impulse)

string g_objPrefix = "FVG2_";

//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; --i)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, g_objPrefix) == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
void DrawBox(datetime t1, datetime t2, double top, double bottom, color clr)
{
   if(top < bottom) { double tmp = top; top = bottom; bottom = tmp; }

   string name = g_objPrefix + "BOX_" + IntegerToString((long)t2);
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bottom);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, false);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   // Midline
   double mid = (top + bottom) / 2.0;
   string midName = g_objPrefix + "MID_" + IntegerToString((long)t2);
   ObjectDelete(0, midName);
   ObjectCreate(0, midName, OBJ_TREND, 0, t1, mid, t2, mid);
   ObjectSetInteger(0, midName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, midName, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, midName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, midName, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
void DrawINLabel(datetime t, double price)
{
   string name = g_objPrefix + "IN_" + IntegerToString((long)t);
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, "IN");
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrMagenta);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
// Calculate ATR manually for M15 data
double CalcATR(MqlRates &rates[], int pos, int period)
{
   if(pos < period) return 0;

   double sum = 0;
   for(int i = 0; i < period; i++)
   {
      int idx = pos - i;
      double tr = rates[idx].high - rates[idx].low;
      if(idx > 0)
      {
         tr = MathMax(tr, MathAbs(rates[idx].high - rates[idx-1].close));
         tr = MathMax(tr, MathAbs(rates[idx].low - rates[idx-1].close));
      }
      sum += tr;
   }
   return sum / period;
}

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, g_impBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, g_zoneHBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, g_zoneLBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, g_outBuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, g_outSellBuffer, INDICATOR_DATA);

   ArraySetAsSeries(g_impBuffer, true);
   ArraySetAsSeries(g_zoneHBuffer, true);
   ArraySetAsSeries(g_zoneLBuffer, true);
   ArraySetAsSeries(g_outBuyBuffer, true);
   ArraySetAsSeries(g_outSellBuffer, true);

   PlotIndexSetInteger(0, PLOT_ARROW, 242);
   PlotIndexSetInteger(3, PLOT_ARROW, 233);
   PlotIndexSetInteger(4, PLOT_ARROW, 234);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   g_objPrefix = IntegerToString(GetTickCount64() % 10000) + "_FVG_";

   IndicatorSetString(INDICATOR_SHORTNAME, "M15 Impulse FVG v2");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteAllObjects();
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
   if(rates_total < 50) return(rates_total);

   // Set arrays as series
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   //--- Get M15 data
   MqlRates m15[];
   ArraySetAsSeries(m15, false);  // oldest first for ATR calc
   int m15Count = CopyRates(_Symbol, PERIOD_M15, 0, 3000, m15);

   if(m15Count < InpATRLen + 10)
   {
      Print("Not enough M15 data: ", m15Count);
      return(prev_calculated);
   }

   //--- Calculate limit for first run or full recalc
   int limit = (prev_calculated == 0) ? rates_total - 1 : rates_total - prev_calculated + 1;
   if(limit > rates_total - 1) limit = rates_total - 1;
   if(limit < 0) limit = 0;

   // Reset state if full recalc
   if(prev_calculated == 0)
   {
      ArrayInitialize(g_impBuffer, EMPTY_VALUE);
      ArrayInitialize(g_zoneHBuffer, EMPTY_VALUE);
      ArrayInitialize(g_zoneLBuffer, EMPTY_VALUE);
      ArrayInitialize(g_outBuyBuffer, EMPTY_VALUE);
      ArrayInitialize(g_outSellBuffer, EMPTY_VALUE);

      g_zoneH = 0;
      g_zoneL = 0;
      g_waitingIN = false;
      g_waitingOUT = false;
      g_inBarIndex = -1;
      g_m15BarTime = 0;
      g_zoneStartBar = -1;

      DeleteAllObjects();
   }

   //--- Loop from oldest to newest bar (like Pine Script)
   for(int i = limit; i >= 0; i--)
   {
      datetime barTime = time[i];

      //--- Find the M15 bar that is CLOSED at this point in time
      //--- M15 bar closes when barTime >= m15.time + 15 minutes
      int m15Idx = -1;
      for(int j = m15Count - 1; j >= 0; j--)
      {
         datetime m15CloseTime = m15[j].time + PeriodSeconds(PERIOD_M15);
         if(barTime >= m15CloseTime)
         {
            m15Idx = j;
            break;
         }
      }

      //--- Check for new M15 impulse
      //--- Only detect when M15 bar just closed (barTime is first bar after M15 close)
      if(m15Idx >= InpATRLen && m15[m15Idx].time != g_m15BarTime)
      {
         double rng = m15[m15Idx].high - m15[m15Idx].low;
         double atr = CalcATR(m15, m15Idx, InpATRLen);
         double bodyRatio = rng > 0 ? MathAbs(m15[m15Idx].close - m15[m15Idx].open) / rng : 0;

         bool isImpulse = (rng >= InpATRMult * atr) && (bodyRatio >= InpBodyRatioMin) && (atr > 0);

         if(isImpulse)
         {
            // Update zone
            g_zoneH = m15[m15Idx].high;
            g_zoneL = m15[m15Idx].low;
            g_m15BarTime = m15[m15Idx].time;

            // Reset state for new pattern
            g_waitingIN = true;
            g_waitingOUT = false;
            g_inBarIndex = -1;
            g_inHigh = 0;
            g_inLow = 0;
            g_minLow = 0;
            g_maxHigh = 0;

            // Draw M15 impulse marker on PREVIOUS bar (last bar of M15 candle)
            // Current bar (i) is the FIRST bar after M15 close
            // So previous bar (i+1) is the LAST bar of M15 impulse candle
            int markerBar = i + 1;
            g_zoneStartBar = markerBar;  // Zone also starts from this bar
            if(markerBar < rates_total)
            {
               double pad = MathMax(rng * 0.05, _Point * 10);
               g_impBuffer[markerBar] = high[markerBar] + pad;
            }
         }
      }

      //--- Draw zone lines (only from zoneStartBar onwards)
      if(g_zoneH > 0 && g_zoneL > 0 && g_zoneStartBar >= 0 && i <= g_zoneStartBar)
      {
         g_zoneHBuffer[i] = g_zoneH;
         g_zoneLBuffer[i] = g_zoneL;
      }

      //--- IN/OUT logic (only after zone is established)
      if(g_zoneH <= 0 || g_zoneL <= 0) continue;

      // Candle fully inside zone = IN
      bool inZone = (high[i] < g_zoneH) && (low[i] > g_zoneL);

      // Previous bar already closed outside zone
      bool prevUp = false;
      bool prevDown = false;
      if(i + 1 < rates_total)
      {
         prevUp = (close[i+1] > g_zoneH);
         prevDown = (close[i+1] < g_zoneL);
      }

      // Current bar breakout
      bool outUp = (close[i] > g_zoneH) && (low[i] > g_zoneH) && prevUp;
      bool outDown = (close[i] < g_zoneL) && (high[i] < g_zoneL) && prevDown;

      //--- Capture IN candle
      if(g_waitingIN && inZone)
      {
         g_inBarIndex = i;
         g_inHigh = high[i];
         g_inLow = low[i];
         g_minLow = low[i];
         g_maxHigh = high[i];
         g_waitingIN = false;
         g_waitingOUT = true;
      }

      //--- Waiting for OUT
      if(g_waitingOUT && g_inBarIndex >= 0)
      {
         // Track extremes
         g_minLow = MathMin(g_minLow, low[i]);
         g_maxHigh = MathMax(g_maxHigh, high[i]);

         // No reversal conditions
         bool noRevBuy = (g_minLow >= g_inLow);
         bool noRevSell = (g_maxHigh <= g_inHigh);

         // OUT conditions (with FVG gap check)
         bool outBuy = outUp && (low[i] > g_inHigh) && noRevBuy;
         bool outSell = outDown && (high[i] < g_inLow) && noRevSell;

         // Calculate padding based on candle range (like impulse marker)
         double candleRange = high[i] - low[i];
         double pad = MathMax(candleRange * 0.3, _Point * 50);

         if(outBuy)
         {
            g_outBuyBuffer[i] = low[i] - pad;

            // Draw box and IN label
            if(InpShowBoxes && g_inBarIndex < rates_total)
            {
               double inPad = MathMax((g_inHigh - g_inLow) * 0.3, _Point * 50);
               DrawBox(time[g_inBarIndex], time[i], low[i], g_inHigh, InpBoxBuyColor);
               DrawINLabel(time[g_inBarIndex], g_inHigh + inPad);
            }

            // Alert
            if(InpEnableAlerts && i == 0 && time[i] > g_lastAlertTime)
            {
               Alert("FVG BUY: ", _Symbol, " at ", TimeToString(time[i]));
               g_lastAlertTime = time[i];
            }

            // Reset
            g_waitingOUT = false;
            g_inBarIndex = -1;
         }

         if(outSell)
         {
            g_outSellBuffer[i] = high[i] + pad;

            if(InpShowBoxes && g_inBarIndex < rates_total)
            {
               double inPad = MathMax((g_inHigh - g_inLow) * 0.3, _Point * 50);
               DrawBox(time[g_inBarIndex], time[i], g_inLow, high[i], InpBoxSellColor);
               DrawINLabel(time[g_inBarIndex], g_inLow - inPad);
            }

            if(InpEnableAlerts && i == 0 && time[i] > g_lastAlertTime)
            {
               Alert("FVG SELL: ", _Symbol, " at ", TimeToString(time[i]));
               g_lastAlertTime = time[i];
            }

            g_waitingOUT = false;
            g_inBarIndex = -1;
         }
      }
   }

   return(rates_total);
}