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
#property indicator_type4   DRAW_NONE
#property indicator_color4  clrDeepSkyBlue
#property indicator_width4  1

#property indicator_label5  "OutSell"
#property indicator_type5   DRAW_NONE
#property indicator_color5  clrLightSalmon
#property indicator_width5  1

input int    InpATRLen       = 14;   // ATR Length (M15)
input double InpATRMult      = 1.2;  // ATR Multiplier
input double InpBodyRatioMin = 0.55; // Min Body/Range
input int    InpMaxM15Bars   = 500;  // Max M15 bars to scan
input int    InpMaxM5Bars    = 1500; // Max M5 bars to scan
input bool   InpShowImpulseText = true; // Show "M15" on impulse bars
input int    InpTextOffsetPoints = 25;  // Text offset in points
input bool   InpShowBoxes = true;       // Draw IN/OUT box
input bool   InpEnableAlerts = true;    // Alert on impulse/OUT
input bool   InpShowOutIcons = true;    // Show icon for OUT
input int    InpOutIconCode = 159;      // OUT icon code
input int    InpOutIconWidth = 3;       // OUT icon size
input int    InpOutTextSize = 10;       // OUT text size

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

void DrawTextLabelSized(const string name,
                        datetime t,
                        double price,
                        const string text,
                        color clr,
                        int fontSize)
{
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
      ObjectMove(0, name, 0, t, price);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawArrowIcon(const string name, datetime t, double price, int code, color clr, int width)
{
   if(!ObjectCreate(0, name, OBJ_ARROW, 0, t, price))
      ObjectMove(0, name, 0, t, price);

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
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

int MapM5ToChart(datetime t)
{
   bool exact = (_Period == PERIOD_M5);
   return iBarShift(_Symbol, _Period, t, exact);
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

   PlotIndexSetInteger(0, PLOT_ARROW, 242);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_NONE);
   PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE);
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

   int m15_count = m15_bars - 1;
   if(InpMaxM15Bars > 0)
      m15_count = MathMin(m15_count, InpMaxM15Bars);

   MqlRates m15Rates[];
   double atrBuf[];
   ArraySetAsSeries(m15Rates, true);
   ArraySetAsSeries(atrBuf, true);

   int copied_m15 = CopyRates(_Symbol, PERIOD_M15, 1, m15_count, m15Rates);
   int copied_atr = CopyBuffer(g_atrHandle, 0, 1, m15_count, atrBuf);
   if(copied_m15 <= 0 || copied_atr <= 0)
      return(rates_total);

   int m15_limit = MathMin(copied_m15, copied_atr);
   if(m15_limit <= 0)
      return(rates_total);

   datetime impulseEventTimes[];
   datetime impulseMarkTimes[];
   double impulseZoneH[];
   double impulseZoneL[];
   double impulseMarks[];
   int impulseCount = 0;

   for(int i = m15_limit - 1; i >= 0; --i)
   {
      double rng = m15Rates[i].high - m15Rates[i].low;
      if(rng <= 0.0)
         continue;

      double atr = atrBuf[i];
      if(atr <= 0.0)
         continue;

      double bodyRatio = MathAbs(m15Rates[i].close - m15Rates[i].open) / rng;
      bool impulse = (rng >= InpATRMult * atr) && (bodyRatio >= InpBodyRatioMin);
      if(!impulse)
         continue;

      int newSize = impulseCount + 1;
      ArrayResize(impulseEventTimes, newSize);
      ArrayResize(impulseMarkTimes, newSize);
      ArrayResize(impulseZoneH, newSize);
      ArrayResize(impulseZoneL, newSize);
      ArrayResize(impulseMarks, newSize);

      datetime eventTime = m15Rates[i].time + PeriodSeconds(PERIOD_M15);
      impulseEventTimes[impulseCount] = eventTime;
      impulseMarkTimes[impulseCount] = eventTime - PeriodSeconds(PERIOD_M5);
      impulseZoneH[impulseCount] = m15Rates[i].high;
      impulseZoneL[impulseCount] = m15Rates[i].low;

      double pad = MathMax(rng * 0.05, _Point * 5.0);
      impulseMarks[impulseCount] = m15Rates[i].high + pad;

      impulseCount++;
   }

   if(InpShowImpulseText)
   {
      for(int i = 0; i < impulseCount; i++)
      {
         double text_price = impulseZoneH[i] + InpTextOffsetPoints * _Point;
         string name = g_objPrefix + "IMP_" + IntegerToString((long)impulseMarkTimes[i]);
         DrawTextLabel(name, impulseMarkTimes[i], text_price, "M15", clrYellow);
      }
   }

   if(InpEnableAlerts && impulseCount > 0)
   {
      datetime latestMarkTime = impulseMarkTimes[impulseCount - 1];
      if(latestMarkTime > g_lastImpulseAlert && latestMarkTime <= time[0])
      {
         Alert("M15 Impulse: ", _Symbol, " at ", TimeToString(latestMarkTime));
         g_lastImpulseAlert = latestMarkTime;
      }
   }

   int m5_bars = Bars(_Symbol, PERIOD_M5);
   if(m5_bars < 2)
      return(rates_total);

   int m5_count = m5_bars - 1;
   if(InpMaxM5Bars > 0)
      m5_count = MathMin(m5_count, InpMaxM5Bars);

   MqlRates m5Rates[];
   ArraySetAsSeries(m5Rates, true);
   int copied_m5 = CopyRates(_Symbol, PERIOD_M5, 1, m5_count, m5Rates);
   if(copied_m5 <= 0)
      return(rates_total);

   int m5_limit = copied_m5;

   double m5ZoneH[];
   double m5ZoneL[];
   double m5OutBuy[];
   double m5OutSell[];
   ArrayResize(m5ZoneH, m5_limit);
   ArrayResize(m5ZoneL, m5_limit);
   ArrayResize(m5OutBuy, m5_limit);
   ArrayResize(m5OutSell, m5_limit);
   ArraySetAsSeries(m5ZoneH, true);
   ArraySetAsSeries(m5ZoneL, true);
   ArraySetAsSeries(m5OutBuy, true);
   ArraySetAsSeries(m5OutSell, true);
   ArrayFill(m5ZoneH, 0, m5_limit, EMPTY_VALUE);
   ArrayFill(m5ZoneL, 0, m5_limit, EMPTY_VALUE);
   ArrayFill(m5OutBuy, 0, m5_limit, EMPTY_VALUE);
   ArrayFill(m5OutSell, 0, m5_limit, EMPTY_VALUE);

   int impIdx = 0;
   double zoneH = EMPTY_VALUE;
   double zoneL = EMPTY_VALUE;
   bool waitingIn = false;
   bool waitingOut = false;
   int inIndex = -1;
   double inHigh = 0.0;
   double inLow = 0.0;
   double minLow = 0.0;
   double maxHigh = 0.0;
   datetime currentEventTime = 0;
   int directionLock = 0; // 1 = up, -1 = down, 0 = unset

   for(int i = m5_limit - 1; i >= 0; --i)
   {
      datetime t = m5Rates[i].time;
      while(impIdx < impulseCount && t >= impulseEventTimes[impIdx])
      {
         zoneH = impulseZoneH[impIdx];
         zoneL = impulseZoneL[impIdx];
         waitingIn = true;
         waitingOut = false;
         inIndex = -1;
         inHigh = 0.0;
         inLow = 0.0;
         minLow = 0.0;
         maxHigh = 0.0;
         currentEventTime = impulseEventTimes[impIdx];
         directionLock = 0;

         impIdx++;
      }

      if(zoneH == EMPTY_VALUE || zoneL == EMPTY_VALUE)
         continue;

      m5ZoneH[i] = zoneH;
      m5ZoneL[i] = zoneL;

      bool canIN = waitingIn && currentEventTime > 0 && t > currentEventTime;
      if(canIN && m5Rates[i].high < zoneH && m5Rates[i].low > zoneL)
      {
         inIndex = i;
         inHigh = m5Rates[i].high;
         inLow = m5Rates[i].low;
         minLow = inLow;
         maxHigh = inHigh;
         waitingIn = false;
         waitingOut = true;
         directionLock = 0;
      }

      if(waitingOut && inIndex >= 0)
      {
         minLow = MathMin(minLow, m5Rates[i].low);
         maxHigh = MathMax(maxHigh, m5Rates[i].high);

         // Lock direction on first breakout from zone
         if(directionLock == 0)
         {
            if(m5Rates[i].close > zoneH)
               directionLock = 1;  // Up break
            else if(m5Rates[i].close < zoneL)
               directionLock = -1; // Down break
         }

         bool prevUp = false;
         bool prevDown = false;
         if(i + 1 < m5_limit)
         {
            prevUp = (m5Rates[i + 1].close > zoneH);
            prevDown = (m5Rates[i + 1].close < zoneL);
         }

         bool outUp = (m5Rates[i].close > zoneH && m5Rates[i].low > zoneH && prevUp);
         bool outDown = (m5Rates[i].close < zoneL && m5Rates[i].high < zoneL && prevDown);

         bool noRevBuy = (minLow >= inLow);
         bool noRevSell = (maxHigh <= inHigh);

         // OUT Buy only valid if direction locked UP
         bool outBuy = outUp && (m5Rates[i].low > inHigh) && noRevBuy && directionLock != -1;
         // OUT Sell only valid if direction locked DOWN
         bool outSell = outDown && (m5Rates[i].high < inLow) && noRevSell && directionLock != 1;

            if(outBuy || outSell)
            {
               double rng = m5Rates[i].high - m5Rates[i].low;
               double pad = MathMax(rng * 0.05, _Point * 5.0);
               double iconOffset = _Point * (InpOutIconWidth * 2 + 4);
               if(outBuy)
               {
                  m5OutBuy[i] = m5Rates[i].low - pad;
                  string outName = g_objPrefix + "OUTB_" + IntegerToString((long)m5Rates[i].time);
                  // DrawTextLabelSized(outName, m5Rates[i].time, m5Rates[i].low - pad, "B",
                  //                    clrGreen, InpOutTextSize);
                  if(InpShowOutIcons)
                  {
                     string iconName = g_objPrefix + "OUTB_ICON_" + IntegerToString((long)m5Rates[i].time);
                     DrawArrowIcon(iconName, m5Rates[i].time, m5Rates[i].low - pad - iconOffset,
                                   InpOutIconCode, clrGreen, InpOutIconWidth);
                  }
               }
               if(outSell)
               {
                  m5OutSell[i] = m5Rates[i].high + pad;
                  string outName = g_objPrefix + "OUTS_" + IntegerToString((long)m5Rates[i].time);
                  // DrawTextLabelSized(outName, m5Rates[i].time, m5Rates[i].high + pad, "S",
                  //                    clrRed, InpOutTextSize);
                  if(InpShowOutIcons)
                  {
                     string iconName = g_objPrefix + "OUTS_ICON_" + IntegerToString((long)m5Rates[i].time);
                     DrawArrowIcon(iconName, m5Rates[i].time, m5Rates[i].high + pad + iconOffset,
                                   InpOutIconCode, clrRed, InpOutIconWidth);
                  }
               }

            if(inIndex >= 0)
            {
               double inPad = MathMax((inHigh - inLow) * 0.2, _Point * 10.0);
               string inName = g_objPrefix + "IN_" + IntegerToString((long)m5Rates[inIndex].time);
               // DrawTextLabel(inName, m5Rates[inIndex].time, inHigh + inPad, "IN", clrMagenta);
            }

            if(InpShowBoxes && inIndex >= 0)
            {
               double top = outBuy ? m5Rates[i].low : inLow;
               double bottom = outBuy ? inHigh : m5Rates[i].high;
               string base = g_objPrefix + IntegerToString((long)m5Rates[i].time);
               DrawBox(base, m5Rates[inIndex].time, m5Rates[i].time, top, bottom, clrMagenta);
            }

            if(InpEnableAlerts && i == 0 && m5Rates[i].time > g_lastOutAlert)
            {
               Alert("M15 OUT: ", _Symbol, " at ", TimeToString(m5Rates[i].time));
               g_lastOutAlert = m5Rates[i].time;
            }

            waitingOut = false;
            waitingIn = false;
            inIndex = -1;
         }
      }
   }

   for(int i = 0; i < m5_limit; i++)
   {
      if(m5ZoneH[i] == EMPTY_VALUE && m5ZoneL[i] == EMPTY_VALUE)
         continue;

      int chart_index = MapM5ToChart(m5Rates[i].time);
      if(chart_index < 0 || chart_index >= rates_total)
         continue;

      int chart_index_prev = rates_total - 1;
      if(i + 1 < m5_limit)
      {
         chart_index_prev = MapM5ToChart(m5Rates[i + 1].time);
         if(chart_index_prev < 0)
            chart_index_prev = rates_total - 1;
      }

      int from = MathMin(chart_index, chart_index_prev);
      int to = MathMax(chart_index, chart_index_prev);
      if(to >= rates_total)
         to = rates_total - 1;

      for(int j = from; j <= to; j++)
      {
         g_zoneHBuffer[j] = m5ZoneH[i];
         g_zoneLBuffer[j] = m5ZoneL[i];
      }
   }

   for(int i = 0; i < m5_limit; i++)
   {
      if(m5OutBuy[i] == EMPTY_VALUE && m5OutSell[i] == EMPTY_VALUE)
         continue;

      int chart_index = MapM5ToChart(m5Rates[i].time);
      if(chart_index < 0 || chart_index >= rates_total)
         continue;

      if(m5OutBuy[i] != EMPTY_VALUE)
         g_outBuyBuffer[chart_index] = m5OutBuy[i];
      if(m5OutSell[i] != EMPTY_VALUE)
         g_outSellBuffer[chart_index] = m5OutSell[i];
   }

   for(int i = 0; i < impulseCount; i++)
   {
      int chart_index = MapM5ToChart(impulseMarkTimes[i]);
      if(chart_index < 0 || chart_index >= rates_total)
         continue;

      if(g_impBuffer[chart_index] == EMPTY_VALUE)
         g_impBuffer[chart_index] = impulseMarks[i];
   }

   return(rates_total);
}
