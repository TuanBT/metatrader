#property copyright "Copyright 2026, Tuan"
#property link      "https://mql5.com"
#property version   "1.00"
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
#property indicator_color2  clrDodgerBlue
#property indicator_width2  1

#property indicator_label3  "ZoneLow"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrOrange
#property indicator_width3  1

#property indicator_label4  "OutBuy"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrDeepSkyBlue
#property indicator_width4  2

#property indicator_label5  "OutSell"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrLightSalmon
#property indicator_width5  2

input int    InpATRLen       = 14;   // ATR Length (M15)
input double InpATRMult      = 1.2;  // ATR Multiplier
input double InpBodyRatioMin = 0.55; // Min Body/Range
input int    InpMaxM15Bars   = 500;  // Max M15 bars to scan
input bool   InpShowImpulseText = true; // Show "M15" on impulse bars
input int    InpTextOffsetPoints = 25;  // Text offset in points
input bool   InpShowBoxes = true;       // Draw IN/OUT box
input bool   InpEnableAlerts = true;    // Alert on impulse/OUT

double g_impBuffer[];
double g_zoneHBuffer[];
double g_zoneLBuffer[];
double g_outBuyBuffer[];
double g_outSellBuffer[];
int g_atrHandle = INVALID_HANDLE;
string g_objPrefix = "M15IMP_";
datetime g_lastImpulseAlert = 0;
datetime g_lastOutAlert = 0;

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

void DrawTextLabel(const string name, datetime t, double price, const string text, color clr)
{
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
      ObjectMove(0, name, 0, t, price);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawBox(const string base,
             datetime inTime,
             datetime outTime,
             double top,
             double bottom,
             color clr)
{
   if(top < bottom)
   {
      double tmp = top;
      top = bottom;
      bottom = tmp;
   }

   string box = base + "_BOX";
   if(!ObjectCreate(0, box, OBJ_RECTANGLE, 0, inTime, top, outTime, bottom))
   {
      ObjectMove(0, box, 0, inTime, top);
      ObjectMove(0, box, 1, outTime, bottom);
   }
   ObjectSetInteger(0, box, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, box, OBJPROP_BACK, true);
   ObjectSetInteger(0, box, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, box, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, box, OBJPROP_FILL, false);

   double mid = (top + bottom) / 2.0;
   string midName = base + "_MID";
   if(!ObjectCreate(0, midName, OBJ_TREND, 0, inTime, mid, outTime, mid))
   {
      ObjectMove(0, midName, 0, inTime, mid);
      ObjectMove(0, midName, 1, outTime, mid);
   }
   ObjectSetInteger(0, midName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, midName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, midName, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, midName, OBJPROP_WIDTH, 1);
}

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

   PlotIndexSetInteger(0, PLOT_ARROW, 241);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(3, PLOT_ARROW, 159);
   PlotIndexSetInteger(4, PLOT_ARROW, 159);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   g_atrHandle = iATR(_Symbol, PERIOD_M15, InpATRLen);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create M15 ATR handle.");
      return(INIT_FAILED);
   }

   string number = StringFormat("%I64d", GetTickCount64());
   g_objPrefix = StringSubstr(number, MathMax(0, StringLen(number) - 4)) + "_M15IMP_";

   IndicatorSetString(INDICATOR_SHORTNAME, "M15 Impulse FAG Entry");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   g_atrHandle = INVALID_HANDLE;

   DeleteObjectsByPrefix(g_objPrefix);
}

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
   if(rates_total < 2)
      return(rates_total);

   ArrayFill(g_impBuffer, 0, rates_total, EMPTY_VALUE);
   ArrayFill(g_zoneHBuffer, 0, rates_total, EMPTY_VALUE);
   ArrayFill(g_zoneLBuffer, 0, rates_total, EMPTY_VALUE);
   ArrayFill(g_outBuyBuffer, 0, rates_total, EMPTY_VALUE);
   ArrayFill(g_outSellBuffer, 0, rates_total, EMPTY_VALUE);

   int m15_bars = Bars(_Symbol, PERIOD_M15);
   if(m15_bars < InpATRLen + 2)
      return(rates_total);

   int count = m15_bars - 1;
   if(InpMaxM15Bars > 0)
      count = MathMin(count, InpMaxM15Bars);

   MqlRates m15Rates[];
   double atrBuf[];
   ArraySetAsSeries(m15Rates, true);
   ArraySetAsSeries(atrBuf, true);

   int copied_rates = CopyRates(_Symbol, PERIOD_M15, 1, count, m15Rates);
   int copied_atr = CopyBuffer(g_atrHandle, 0, 1, count, atrBuf);
   if(copied_rates <= 0 || copied_atr <= 0)
      return(rates_total);

   int limit = MathMin(copied_rates, copied_atr);
   if(limit <= 0)
      return(rates_total);

   double m15Imp[];
   double m15ZoneH[];
   double m15ZoneL[];
   double m15OutBuy[];
   double m15OutSell[];
   ArrayResize(m15Imp, limit);
   ArrayResize(m15ZoneH, limit);
   ArrayResize(m15ZoneL, limit);
   ArrayResize(m15OutBuy, limit);
   ArrayResize(m15OutSell, limit);
   ArraySetAsSeries(m15Imp, true);
   ArraySetAsSeries(m15ZoneH, true);
   ArraySetAsSeries(m15ZoneL, true);
   ArraySetAsSeries(m15OutBuy, true);
   ArraySetAsSeries(m15OutSell, true);
   ArrayFill(m15Imp, 0, limit, EMPTY_VALUE);
   ArrayFill(m15ZoneH, 0, limit, EMPTY_VALUE);
   ArrayFill(m15ZoneL, 0, limit, EMPTY_VALUE);
   ArrayFill(m15OutBuy, 0, limit, EMPTY_VALUE);
   ArrayFill(m15OutSell, 0, limit, EMPTY_VALUE);

   double zoneH = EMPTY_VALUE;
   double zoneL = EMPTY_VALUE;
   bool waitingIn = false;
   bool waitingOut = false;
   int inIndex = -1;
   double inHigh = 0.0;
   double inLow = 0.0;
   double minLow = 0.0;
   double maxHigh = 0.0;

   for(int i = limit - 1; i >= 0; --i)
   {
      double rng = m15Rates[i].high - m15Rates[i].low;
      if(rng <= 0.0)
         continue;

      double atr = atrBuf[i];
      if(atr <= 0.0)
         continue;

      double bodyRatio = MathAbs(m15Rates[i].close - m15Rates[i].open) / rng;
      bool impulse = (rng >= InpATRMult * atr) && (bodyRatio >= InpBodyRatioMin);
      if(impulse)
      {
         zoneH = m15Rates[i].high;
         zoneL = m15Rates[i].low;
         waitingIn = true;
         waitingOut = false;
         inIndex = -1;
         inHigh = 0.0;
         inLow = 0.0;
         minLow = 0.0;
         maxHigh = 0.0;
      }

      if(zoneH != EMPTY_VALUE && zoneL != EMPTY_VALUE)
      {
         m15ZoneH[i] = zoneH;
         m15ZoneL[i] = zoneL;
      }

      if(impulse)
      {
         double pad = MathMax(rng * 0.05, _Point * 5.0);
         m15Imp[i] = m15Rates[i].high + pad;

         if(InpShowImpulseText)
         {
            double text_price = m15Rates[i].high + InpTextOffsetPoints * _Point;
            string name = g_objPrefix + "IMP_" + IntegerToString((long)m15Rates[i].time);
            DrawTextLabel(name, m15Rates[i].time, text_price, "M15", clrYellow);
         }

         if(InpEnableAlerts && i == 0 && m15Rates[i].time > g_lastImpulseAlert)
         {
            Alert("M15 Impulse: ", _Symbol, " at ", TimeToString(m15Rates[i].time));
            g_lastImpulseAlert = m15Rates[i].time;
         }
         continue;
      }

      if(waitingIn && zoneH != EMPTY_VALUE && zoneL != EMPTY_VALUE)
      {
         if(m15Rates[i].high < zoneH && m15Rates[i].low > zoneL)
         {
            inIndex = i;
            inHigh = m15Rates[i].high;
            inLow = m15Rates[i].low;
            minLow = inLow;
            maxHigh = inHigh;
            waitingIn = false;
            waitingOut = true;
         }
      }

      if(waitingOut && zoneH != EMPTY_VALUE && zoneL != EMPTY_VALUE && inIndex >= 0)
      {
         minLow = MathMin(minLow, m15Rates[i].low);
         maxHigh = MathMax(maxHigh, m15Rates[i].high);

         bool prevUp = false;
         bool prevDown = false;
         if(i + 1 < limit)
         {
            prevUp = (m15Rates[i + 1].close > zoneH && m15Rates[i + 1].low > zoneH);
            prevDown = (m15Rates[i + 1].close < zoneL && m15Rates[i + 1].high < zoneL);
         }

         bool outUp = (m15Rates[i].close > zoneH && m15Rates[i].low > zoneH && prevUp);
         bool outDown = (m15Rates[i].close < zoneL && m15Rates[i].high < zoneL && prevDown);

         bool noRevBuy = (minLow >= inLow);
         bool noRevSell = (maxHigh <= inHigh);

         bool outBuy = outUp && (m15Rates[i].low > inHigh) && noRevBuy;
         bool outSell = outDown && (m15Rates[i].high < inLow) && noRevSell;

         if(outBuy || outSell)
         {
            double pad = MathMax(rng * 0.05, _Point * 5.0);
            if(outBuy)
               m15OutBuy[i] = m15Rates[i].low - pad;
            if(outSell)
               m15OutSell[i] = m15Rates[i].high + pad;

            if(inIndex >= 0)
            {
               double inPad = MathMax((inHigh - inLow) * 0.2, _Point * 10.0);
               string inName = g_objPrefix + "IN_" + IntegerToString((long)m15Rates[inIndex].time);
               DrawTextLabel(inName, m15Rates[inIndex].time, inHigh + inPad, "IN",
                             outBuy ? clrDeepSkyBlue : clrLightSalmon);
            }

            if(InpShowBoxes && inIndex >= 0)
            {
               double top = outBuy ? m15Rates[i].low : inLow;
               double bottom = outBuy ? inHigh : m15Rates[i].high;
               string base = g_objPrefix + IntegerToString((long)m15Rates[i].time);
               DrawBox(base, m15Rates[inIndex].time, m15Rates[i].time, top, bottom,
                       outBuy ? clrDeepSkyBlue : clrLightSalmon);
            }

            if(InpEnableAlerts && i == 0 && m15Rates[i].time > g_lastOutAlert)
            {
               Alert("M15 OUT: ", _Symbol, " at ", TimeToString(m15Rates[i].time));
               g_lastOutAlert = m15Rates[i].time;
            }

            waitingOut = false;
            waitingIn = false;
            zoneH = EMPTY_VALUE;
            zoneL = EMPTY_VALUE;
            inIndex = -1;
         }
      }
   }

   for(int i = 0; i < limit; i++)
   {
      if(m15ZoneH[i] == EMPTY_VALUE && m15ZoneL[i] == EMPTY_VALUE)
         continue;

      int chart_index = iBarShift(_Symbol, _Period, m15Rates[i].time, false);
      if(chart_index < 0 || chart_index >= rates_total)
         continue;

      int chart_index_prev = rates_total - 1;
      if(i + 1 < limit)
      {
         chart_index_prev = iBarShift(_Symbol, _Period, m15Rates[i + 1].time, false);
         if(chart_index_prev < 0)
            chart_index_prev = rates_total - 1;
      }

      int from = MathMin(chart_index, chart_index_prev);
      int to = MathMax(chart_index, chart_index_prev);
      if(to >= rates_total)
         to = rates_total - 1;

      for(int j = from; j <= to; j++)
      {
         g_zoneHBuffer[j] = m15ZoneH[i];
         g_zoneLBuffer[j] = m15ZoneL[i];
      }
   }

   for(int i = 0; i < limit; i++)
   {
      if(m15Imp[i] == EMPTY_VALUE &&
         m15OutBuy[i] == EMPTY_VALUE && m15OutSell[i] == EMPTY_VALUE)
         continue;

      int chart_index = (_Period == PERIOD_M15)
                        ? iBarShift(_Symbol, _Period, m15Rates[i].time, true)
                        : iBarShift(_Symbol, _Period, m15Rates[i].time, false);
      if(chart_index < 0 || chart_index >= rates_total)
         continue;

      if(m15Imp[i] != EMPTY_VALUE && g_impBuffer[chart_index] == EMPTY_VALUE)
         g_impBuffer[chart_index] = m15Imp[i];
      if(m15OutBuy[i] != EMPTY_VALUE)
         g_outBuyBuffer[chart_index] = m15OutBuy[i];
      if(m15OutSell[i] != EMPTY_VALUE)
         g_outSellBuffer[chart_index] = m15OutSell[i];
   }

   return(rates_total);
}
