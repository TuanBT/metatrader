#property copyright "Copyright 2026, Tuan"
#property link      "https://mql5.com"
#property version   "1.00"
#property strict

#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

#property indicator_label1  "ImpulseUp"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2

#property indicator_label2  "ImpulseDown"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

#property indicator_label3  "ZoneHigh"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_width3  1

#property indicator_label4  "ZoneLow"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrOrange
#property indicator_width4  1

#property indicator_label5  "OutBuy"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrDeepSkyBlue
#property indicator_width5  2

#property indicator_label6  "OutSell"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrLightSalmon
#property indicator_width6  2

input int    InpATRLen       = 14;   // ATR Length (M15)
input double InpATRMult      = 1.2;  // ATR Multiplier
input double InpBodyRatioMin = 0.55; // Min Body/Range
input int    InpMaxM15Bars   = 500;  // Max M15 bars to scan
input bool   InpShowImpulseText = true; // Show "M15" text on impulse
input int    InpTextOffsetPoints = 25;  // Text offset in points

double g_impUpBuffer[];
double g_impDownBuffer[];
double g_zoneHBuffer[];
double g_zoneLBuffer[];
double g_outBuyBuffer[];
double g_outSellBuffer[];
int g_atrHandle = INVALID_HANDLE;
string g_textPrefix = "M15IMP_TXT_";

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

int OnInit()
{
   SetIndexBuffer(0, g_impUpBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, g_impDownBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, g_zoneHBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, g_zoneLBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, g_outBuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(5, g_outSellBuffer, INDICATOR_DATA);

   ArraySetAsSeries(g_impUpBuffer, true);
   ArraySetAsSeries(g_impDownBuffer, true);
   ArraySetAsSeries(g_zoneHBuffer, true);
   ArraySetAsSeries(g_zoneLBuffer, true);
   ArraySetAsSeries(g_outBuyBuffer, true);
   ArraySetAsSeries(g_outSellBuffer, true);

   PlotIndexSetInteger(0, PLOT_ARROW, 241);
   PlotIndexSetInteger(1, PLOT_ARROW, 242);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(4, PLOT_ARROW, 159);
   PlotIndexSetInteger(5, PLOT_ARROW, 159);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   g_atrHandle = iATR(_Symbol, PERIOD_M15, InpATRLen);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create M15 ATR handle.");
      return(INIT_FAILED);
   }

   string number = StringFormat("%I64d", GetTickCount64());
   g_textPrefix = StringSubstr(number, MathMax(0, StringLen(number) - 4)) + "_M15IMP_";

   IndicatorSetString(INDICATOR_SHORTNAME, "M15 Impulse FAG Entry");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   g_atrHandle = INVALID_HANDLE;

   DeleteObjectsByPrefix(g_textPrefix);
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

   ArrayFill(g_impUpBuffer, 0, rates_total, EMPTY_VALUE);
   ArrayFill(g_impDownBuffer, 0, rates_total, EMPTY_VALUE);
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

   double m15ImpUp[];
   double m15ImpDown[];
   double m15ZoneH[];
   double m15ZoneL[];
   double m15OutBuy[];
   double m15OutSell[];
   ArrayResize(m15ImpUp, limit);
   ArrayResize(m15ImpDown, limit);
   ArrayResize(m15ZoneH, limit);
   ArrayResize(m15ZoneL, limit);
   ArrayResize(m15OutBuy, limit);
   ArrayResize(m15OutSell, limit);
   ArraySetAsSeries(m15ImpUp, true);
   ArraySetAsSeries(m15ImpDown, true);
   ArraySetAsSeries(m15ZoneH, true);
   ArraySetAsSeries(m15ZoneL, true);
   ArraySetAsSeries(m15OutBuy, true);
   ArraySetAsSeries(m15OutSell, true);
   ArrayFill(m15ImpUp, 0, limit, EMPTY_VALUE);
   ArrayFill(m15ImpDown, 0, limit, EMPTY_VALUE);
   ArrayFill(m15ZoneH, 0, limit, EMPTY_VALUE);
   ArrayFill(m15ZoneL, 0, limit, EMPTY_VALUE);
   ArrayFill(m15OutBuy, 0, limit, EMPTY_VALUE);
   ArrayFill(m15OutSell, 0, limit, EMPTY_VALUE);

   double zoneH = EMPTY_VALUE;
   double zoneL = EMPTY_VALUE;
   bool waitingIn = false;
   bool waitingOut = false;

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
      }

      if(zoneH != EMPTY_VALUE && zoneL != EMPTY_VALUE)
      {
         m15ZoneH[i] = zoneH;
         m15ZoneL[i] = zoneL;
      }

      if(impulse)
      {
         double pad = MathMax(rng * 0.05, _Point * 5.0);
         if(m15Rates[i].close >= m15Rates[i].open)
            m15ImpUp[i] = m15Rates[i].low - pad;
         else
            m15ImpDown[i] = m15Rates[i].high + pad;
         continue;
      }

      if(waitingIn && zoneH != EMPTY_VALUE && zoneL != EMPTY_VALUE)
      {
         if(m15Rates[i].high < zoneH && m15Rates[i].low > zoneL)
         {
            waitingIn = false;
            waitingOut = true;
         }
      }

      if(waitingOut && zoneH != EMPTY_VALUE && zoneL != EMPTY_VALUE)
      {
         if(m15Rates[i].close > zoneH)
         {
            double pad = MathMax(rng * 0.05, _Point * 5.0);
            m15OutBuy[i] = m15Rates[i].low - pad;
            waitingOut = false;
            zoneH = EMPTY_VALUE;
            zoneL = EMPTY_VALUE;
         }
         else if(m15Rates[i].close < zoneL)
         {
            double pad = MathMax(rng * 0.05, _Point * 5.0);
            m15OutSell[i] = m15Rates[i].high + pad;
            waitingOut = false;
            zoneH = EMPTY_VALUE;
            zoneL = EMPTY_VALUE;
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
      if(m15ImpUp[i] == EMPTY_VALUE && m15ImpDown[i] == EMPTY_VALUE &&
         m15OutBuy[i] == EMPTY_VALUE && m15OutSell[i] == EMPTY_VALUE)
         continue;

      int chart_index = (_Period == PERIOD_M15)
                        ? iBarShift(_Symbol, _Period, m15Rates[i].time, true)
                        : iBarShift(_Symbol, _Period, m15Rates[i].time, false);
      if(chart_index < 0 || chart_index >= rates_total)
         continue;

      if(g_impUpBuffer[chart_index] != EMPTY_VALUE || g_impDownBuffer[chart_index] != EMPTY_VALUE)
         continue;

      if(m15ImpUp[i] != EMPTY_VALUE)
         g_impUpBuffer[chart_index] = m15ImpUp[i];
      if(m15ImpDown[i] != EMPTY_VALUE)
         g_impDownBuffer[chart_index] = m15ImpDown[i];
      if(m15OutBuy[i] != EMPTY_VALUE)
         g_outBuyBuffer[chart_index] = m15OutBuy[i];
      if(m15OutSell[i] != EMPTY_VALUE)
         g_outSellBuffer[chart_index] = m15OutSell[i];

      if(InpShowImpulseText && (m15ImpUp[i] != EMPTY_VALUE || m15ImpDown[i] != EMPTY_VALUE))
      {
         double text_price = (m15ImpUp[i] != EMPTY_VALUE)
                             ? m15Rates[i].low - InpTextOffsetPoints * _Point
                             : m15Rates[i].high + InpTextOffsetPoints * _Point;
         string name = g_textPrefix + IntegerToString((long)m15Rates[i].time);
         if(!ObjectCreate(0, name, OBJ_TEXT, 0, m15Rates[i].time, text_price))
            ObjectMove(0, name, 0, m15Rates[i].time, text_price);
         ObjectSetString(0, name, OBJPROP_TEXT, "M15");
         ObjectSetInteger(0, name, OBJPROP_COLOR,
                          (m15ImpUp[i] != EMPTY_VALUE) ? clrLime : clrRed);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
   }

   return(rates_total);
}
