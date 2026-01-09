//+------------------------------------------------------------------+
//|                               Indicator M15 Impulse FAG Entry.mq5|
//|                         Converted from TradingView indicator      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Tuan"
#property link      "https://mql5.com"
#property version   "1.10"
#property strict

#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5

input int    InpATRLen        = 14;    // ATR Length (M15)
input double InpATRMult       = 1.2;   // ATR Multiplier
input double InpBodyRatioMin  = 0.55;  // Min Body/Range

input color  InpZoneColor     = clrGray;
input color  InpM15Color      = clrGray;
input color  InpSigColor      = clrMagenta;
input color  InpBuyColor      = clrGreen;
input color  InpSellColor     = clrRed;

double g_zoneHBuffer[];
double g_zoneLBuffer[];
double g_m15Buffer[];
double g_outBuyBuffer[];
double g_outSellBuffer[];

static int g_atrHandleM15 = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, g_zoneHBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, g_zoneLBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, g_m15Buffer, INDICATOR_DATA);
   SetIndexBuffer(3, g_outBuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, g_outSellBuffer, INDICATOR_DATA);

   ArraySetAsSeries(g_zoneHBuffer, true);
   ArraySetAsSeries(g_zoneLBuffer, true);
   ArraySetAsSeries(g_m15Buffer, true);
   ArraySetAsSeries(g_outBuyBuffer, true);
   ArraySetAsSeries(g_outSellBuffer, true);

   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_ARROW);

   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpZoneColor);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpZoneColor);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpM15Color);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpBuyColor);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, InpSellColor);

   PlotIndexSetInteger(2, PLOT_ARROW, 217); // triangle down
   PlotIndexSetInteger(3, PLOT_ARROW, 241); // arrow up
   PlotIndexSetInteger(4, PLOT_ARROW, 242); // arrow down

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   g_atrHandleM15 = iATR(_Symbol, PERIOD_M15, InpATRLen);
   if(g_atrHandleM15 == INVALID_HANDLE)
   {
      Print("Failed to create M15 ATR handle.");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandleM15 != INVALID_HANDLE)
      IndicatorRelease(g_atrHandleM15);
   g_atrHandleM15 = INVALID_HANDLE;
}

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
void DrawOutObjects(const string base,
                    const datetime inTime,
                    const double inHigh,
                    const double inLow,
                    const datetime outTime,
                    const double top,
                    const double bottom)
{
   string inLabel = base + "_IN";
   if(ObjectFind(0, inLabel) < 0)
   {
      double pad = MathMax((top - bottom) * 0.1, _Point * 10.0);
      ObjectCreate(0, inLabel, OBJ_TEXT, 0, inTime, inHigh + pad);
      ObjectSetString(0, inLabel, OBJPROP_TEXT, "IN");
      ObjectSetInteger(0, inLabel, OBJPROP_COLOR, InpSigColor);
   }

   string topLine = base + "_TOP";
   if(ObjectFind(0, topLine) < 0)
   {
      ObjectCreate(0, topLine, OBJ_TREND, 0, inTime, top, outTime, top);
      ObjectSetInteger(0, topLine, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, topLine, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, topLine, OBJPROP_COLOR, InpSigColor);
   }

   string botLine = base + "_BOT";
   if(ObjectFind(0, botLine) < 0)
   {
      ObjectCreate(0, botLine, OBJ_TREND, 0, inTime, bottom, outTime, bottom);
      ObjectSetInteger(0, botLine, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, botLine, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, botLine, OBJPROP_COLOR, InpSigColor);
   }

   string midLine = base + "_MID";
   if(ObjectFind(0, midLine) < 0)
   {
      double mid = (top + bottom) / 2.0;
      ObjectCreate(0, midLine, OBJ_TREND, 0, inTime, mid, outTime, mid);
      ObjectSetInteger(0, midLine, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, midLine, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, midLine, OBJPROP_COLOR, InpSigColor);
   }
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
   if(rates_total < 3)
      return(rates_total);

   if(prev_calculated == 0)
      DeleteObjectsByPrefix("M15FVG_");

   double zoneH = EMPTY_VALUE;
   double zoneL = EMPTY_VALUE;
   bool waitingIN = false;
   bool waitingOUT = false;
   int inIndex = -1;
   double inHigh = 0.0;
   double inLow = 0.0;
   double minLow = 0.0;
   double maxHigh = 0.0;
   datetime m15ImpulseTime = 0;
   datetime lastM15Time = 0;

   for(int i = rates_total - 1; i >= 0; --i)
   {
      g_zoneHBuffer[i] = EMPTY_VALUE;
      g_zoneLBuffer[i] = EMPTY_VALUE;
      g_m15Buffer[i] = EMPTY_VALUE;
      g_outBuyBuffer[i] = EMPTY_VALUE;
      g_outSellBuffer[i] = EMPTY_VALUE;
   }

   for(int i = rates_total - 2; i >= 0; --i)
   {
      int m15_index = iBarShift(_Symbol, PERIOD_M15, time[i], true);
      if(m15_index >= 0)
      {
         int m15_closed_index = m15_index;
         datetime m15Time = iTime(_Symbol, PERIOD_M15, m15_index);
         datetime currentM15Time = iTime(_Symbol, PERIOD_M15, 0);
         if(time[i] >= currentM15Time)
         {
            m15_closed_index = 1;
            m15Time = iTime(_Symbol, PERIOD_M15, 1);
         }

         if(m15Time != 0 && m15Time != lastM15Time && m15_closed_index >= 1)
         {
            double mh = iHigh(_Symbol, PERIOD_M15, m15_closed_index);
            double ml = iLow(_Symbol, PERIOD_M15, m15_closed_index);
            double mo = iOpen(_Symbol, PERIOD_M15, m15_closed_index);
            double mc = iClose(_Symbol, PERIOD_M15, m15_closed_index);
            double rng = mh - ml;

            double atrBuf[1];
            if(g_atrHandleM15 != INVALID_HANDLE &&
               CopyBuffer(g_atrHandleM15, 0, m15_closed_index, 1, atrBuf) == 1)
            {
               double atr = atrBuf[0];
               double bodyRatio = (rng > 0.0) ? MathAbs(mc - mo) / rng : 0.0;
               bool imp = (rng >= InpATRMult * atr) && (bodyRatio >= InpBodyRatioMin);
               if(imp)
               {
                  zoneH = mh;
                  zoneL = ml;
                  m15ImpulseTime = m15Time;
                  waitingIN = true;
                  waitingOUT = false;
                  inIndex = -1;
                  inHigh = 0.0;
                  inLow = 0.0;
                  minLow = 0.0;
                  maxHigh = 0.0;

                  g_m15Buffer[i] = high[i] + MathMax((high[i] - low[i]) * 0.2, _Point * 10.0);
               }
            }
            lastM15Time = m15Time;
         }
      }

      if(zoneH != EMPTY_VALUE && zoneL != EMPTY_VALUE)
      {
         g_zoneHBuffer[i] = zoneH;
         g_zoneLBuffer[i] = zoneL;
      }

      bool inZone = (zoneH != EMPTY_VALUE && zoneL != EMPTY_VALUE && high[i] < zoneH && low[i] > zoneL);
      bool canIN = waitingIN && m15ImpulseTime > 0 && time[i] > m15ImpulseTime;
      if(canIN && inZone)
      {
         inIndex = i;
         inHigh = high[i];
         inLow = low[i];
         minLow = low[i];
         maxHigh = high[i];
         waitingIN = false;
         waitingOUT = true;
      }

      if(waitingOUT && inIndex >= 0)
      {
         minLow = MathMin(minLow, low[i]);
         maxHigh = MathMax(maxHigh, high[i]);
      }

      if(i + 1 >= rates_total)
         continue;

      bool prevUp = (zoneH != EMPTY_VALUE && close[i + 1] > zoneH);
      bool prevDown = (zoneL != EMPTY_VALUE && close[i + 1] < zoneL);

      bool outUp = (zoneH != EMPTY_VALUE && close[i] > zoneH && low[i] > zoneH && prevUp);
      bool outDown = (zoneL != EMPTY_VALUE && close[i] < zoneL && high[i] < zoneL && prevDown);

      bool noRevBuy = waitingOUT && (minLow >= inLow);
      bool noRevSell = waitingOUT && (maxHigh <= inHigh);

      bool outBuy = waitingOUT && outUp && (low[i] > inHigh) && noRevBuy;
      bool outSell = waitingOUT && outDown && (high[i] < inLow) && noRevSell;

      if(outBuy || outSell)
      {
         if(outBuy)
            g_outBuyBuffer[i] = low[i] - MathMax((high[i] - low[i]) * 0.2, _Point * 10.0);
         if(outSell)
            g_outSellBuffer[i] = high[i] + MathMax((high[i] - low[i]) * 0.2, _Point * 10.0);

         double top = 0.0;
         double bottom = 0.0;
         if(outBuy)
         {
            top = low[i];
            bottom = inHigh;
         }
         else
         {
            top = inLow;
            bottom = high[i];
         }

         string base = "M15FVG_" + IntegerToString((int)time[i]);
         if(inIndex >= 0)
            DrawOutObjects(base, time[inIndex], inHigh, inLow, time[i], top, bottom);

         waitingOUT = false;
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
