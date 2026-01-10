//+------------------------------------------------------------------+
//| Indicator Test - SIÊU ĐƠN GIẢN để test EA                        |
//| Tín hiệu ra đều đặn mỗi N nến                                    |
//+------------------------------------------------------------------+
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
#property indicator_color4  clrLime
#property indicator_width4  3

#property indicator_label5  "OutSell"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrRed
#property indicator_width5  3

//+------------------------------------------------------------------+
//| INPUTS - Điều chỉnh để ra tín hiệu nhanh                         |
//+------------------------------------------------------------------+
input int    InpSignalEvery   = 5;    // Tín hiệu OUT mỗi N nến (8 = mỗi 8 phút trên M1)
input bool   InpAlternate     = true; // Xen kẽ Buy/Sell
input bool   InpShowBoxes     = true; // Vẽ Box
input bool   InpEnableAlerts  = true; // Bật Alert

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
double g_impBuffer[];
double g_zoneHBuffer[];
double g_zoneLBuffer[];
double g_outBuyBuffer[];
double g_outSellBuffer[];

string g_objPrefix = "TEST_";
datetime g_lastAlert = 0;
datetime g_lastSignalBar = 0;  // Track bar cuối cùng có signal
int g_signalCount = 0;         // Đếm số signal để xen kẽ Buy/Sell

// Lưu thông tin signal cuối để vẽ lại khi bar shift
datetime g_savedSignalTime = 0;
double g_savedZoneH = 0;
double g_savedZoneL = 0;
double g_savedOutBuy = EMPTY_VALUE;
double g_savedOutSell = EMPTY_VALUE;
int g_savedImpBarShift = 0;  // Số bar từ signal đến Impulse

//+------------------------------------------------------------------+
//| Delete objects by prefix                                         |
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
//| Draw Box with midline                                            |
//+------------------------------------------------------------------+
void DrawBox(const string base, datetime t1, datetime t2,
             double top, double bottom, color clr)
{
   if(top < bottom) { double tmp = top; top = bottom; bottom = tmp; }

   string box = base + "_BOX";
   if(!ObjectCreate(0, box, OBJ_RECTANGLE, 0, t1, top, t2, bottom))
   {
      ObjectMove(0, box, 0, t1, top);
      ObjectMove(0, box, 1, t2, bottom);
   }
   ObjectSetInteger(0, box, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, box, OBJPROP_BACK, true);
   ObjectSetInteger(0, box, OBJPROP_FILL, false);

   double mid = (top + bottom) / 2.0;
   string midName = base + "_MID";
   if(!ObjectCreate(0, midName, OBJ_TREND, 0, t1, mid, t2, mid))
   {
      ObjectMove(0, midName, 0, t1, mid);
      ObjectMove(0, midName, 1, t2, mid);
   }
   ObjectSetInteger(0, midName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, midName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, midName, OBJPROP_STYLE, STYLE_DOT);
}

//+------------------------------------------------------------------+
//| Draw Text label                                                  |
//+------------------------------------------------------------------+
void DrawText(const string name, datetime t, double price, 
              const string text, color clr)
{
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
      ObjectMove(0, name, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
}

//+------------------------------------------------------------------+
//| Indicator Init                                                   |
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

   g_objPrefix = "TEST_" + IntegerToString(GetTickCount64() % 10000) + "_";

   IndicatorSetString(INDICATOR_SHORTNAME, "TEST Signal (every " + 
                      IntegerToString(InpSignalEvery) + " bars)");
   Print("✅ Test Indicator: OUT signal mỗi ", InpSignalEvery, " nến");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Indicator Deinit                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteObjectsByPrefix(g_objPrefix);
}

//+------------------------------------------------------------------+
//| LOGIC: Tín hiệu OUT ở bar [1] mỗi N nến                          |
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
   if(rates_total < 20)
      return(rates_total);

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   // CHỈ clear khi lần đầu tính hoặc có thay đổi lớn
   if(prev_calculated == 0)
   {
      ArrayFill(g_impBuffer, 0, rates_total, EMPTY_VALUE);
      ArrayFill(g_zoneHBuffer, 0, rates_total, EMPTY_VALUE);
      ArrayFill(g_zoneLBuffer, 0, rates_total, EMPTY_VALUE);
      ArrayFill(g_outBuyBuffer, 0, rates_total, EMPTY_VALUE);
      ArrayFill(g_outSellBuffer, 0, rates_total, EMPTY_VALUE);

      // Reset saved signal khi chart refresh
      g_savedSignalTime = 0;
   }
   else
   {
      // Clear chỉ các bar mới
      for(int i = 0; i < rates_total - prev_calculated + 1 && i < rates_total; i++)
      {
         g_impBuffer[i] = EMPTY_VALUE;
         g_zoneHBuffer[i] = EMPTY_VALUE;
         g_zoneLBuffer[i] = EMPTY_VALUE;
         g_outBuyBuffer[i] = EMPTY_VALUE;
         g_outSellBuffer[i] = EMPTY_VALUE;
      }
   }

   // === VẼ LẠI signal đã lưu (nếu có) ===
   if(g_savedSignalTime > 0)
   {
      int signalBarIndex = iBarShift(_Symbol, _Period, g_savedSignalTime, false);
      if(signalBarIndex >= 0 && signalBarIndex < rates_total)
      {
         // Vẽ lại OUT signal - mũi tên gần nến
         if(g_savedOutBuy != EMPTY_VALUE)
         {
            double outLow = iLow(_Symbol, _Period, signalBarIndex);
            g_outBuyBuffer[signalBarIndex] = outLow - 20 * _Point;
         }
         if(g_savedOutSell != EMPTY_VALUE)
         {
            double outHigh = iHigh(_Symbol, _Period, signalBarIndex);
            g_outSellBuffer[signalBarIndex] = outHigh + 20 * _Point;
         }

         // Vẽ lại Zone từ Impulse đến OUT
         int impBar = signalBarIndex + g_savedImpBarShift;
         for(int j = impBar; j >= signalBarIndex && j >= 0 && j < rates_total; j--)
         {
            g_zoneHBuffer[j] = g_savedZoneH;
            g_zoneLBuffer[j] = g_savedZoneL;
         }

         // Vẽ lại Impulse mark
         if(impBar >= 0 && impBar < rates_total)
         {
            double zoneRange = g_savedZoneH - g_savedZoneL;
            g_impBuffer[impBar] = g_savedZoneH + zoneRange * 0.1;
         }
      }
   }

   // Chỉ tạo signal mới khi có bar mới VÀ đủ N nến từ signal trước
   datetime bar1Time = time[1];  // Thời gian của bar vừa đóng

   // Kiểm tra xem đã đủ N nến chưa
   bool shouldSignal = false;
   if(g_lastSignalBar == 0)
   {
      // Lần đầu tiên
      shouldSignal = true;
   }
   else
   {
      // Đếm số bar từ signal trước
      int barsSinceLastSignal = iBarShift(_Symbol, _Period, g_lastSignalBar, false);
      if(barsSinceLastSignal >= InpSignalEvery)
         shouldSignal = true;
   }

   // Nếu chưa đủ điều kiện, vẫn vẽ các signal cũ trên chart để nhìn
   // Nhưng QUAN TRỌNG: Signal mới chỉ xuất hiện ở bar [1]

   if(shouldSignal && bar1Time != g_lastSignalBar)
   {
      // Tạo signal mới ở bar [1]
      int outBar = 1;
      int impBar = 5;  // Impulse ở 4 nến trước OUT

      if(impBar >= rates_total)
         return(rates_total);

      // Xen kẽ Buy/Sell
      bool isBuy = InpAlternate ? (g_signalCount % 2 == 0) : (close[impBar] > open[impBar]);

      // === QUAN TRỌNG: Tạo zone dựa trên giá THẬT của các nến ===
      // Tìm range thật từ impBar đến outBar để đảm bảo có IN candle thật
      double realHigh = high[impBar];
      double realLow = low[impBar];

      // Mở rộng zone để bao trùm tất cả các nến từ impBar đến bar[2]
      // Như vậy chắc chắn có nến nằm trong zone (là IN candle)
      for(int k = impBar - 1; k >= 2; k--)
      {
         if(high[k] > realHigh) realHigh = high[k];
         if(low[k] < realLow) realLow = low[k];
      }

      // Mở rộng zone thêm chút để đảm bảo có nến nằm hoàn toàn bên trong
      double buffer = (realHigh - realLow) * 0.2;
      double zoneH = realHigh + buffer;
      double zoneL = realLow - buffer;
      double zoneRange = zoneH - zoneL;

      if(zoneRange <= 0)
         zoneRange = 100 * _Point;  // Fallback

      // Đánh dấu Impulse
      g_impBuffer[impBar] = zoneH + zoneRange * 0.1;
      DrawText(g_objPrefix + "IMP_" + IntegerToString((long)time[impBar]), 
               time[impBar], g_impBuffer[impBar], "IMP", clrYellow);

      // Zone lines từ Impulse đến OUT
      for(int j = impBar; j >= outBar && j >= 0; j--)
      {
         g_zoneHBuffer[j] = zoneH;
         g_zoneLBuffer[j] = zoneL;
      }

      // Tìm IN candle thật (nến nằm trong zone) - để vẽ label
      int inBar = 3;  // Mặc định, EA sẽ tự tìm
      for(int m = 2; m <= impBar - 1; m++)
      {
         if(high[m] < zoneH && low[m] > zoneL)
         {
            inBar = m;
            break;
         }
      }

      // Vẽ label IN cho candle được chọn
      DrawText(g_objPrefix + "IN_" + IntegerToString((long)time[inBar]),
               time[inBar], high[inBar] + zoneRange * 0.05, "IN", clrMagenta);

      // OUT signal ở bar [1]
      double outHigh = high[outBar];
      double outLow  = low[outBar];

      // Lấy IN candle high/low thật để tính Box
      double inHigh = high[inBar];
      double inLow  = low[inBar];

      if(isBuy)
      {
         // OUT Buy - QUAN TRỌNG: Đặt ở bar [1]
         // Mũi tên lên màu xanh ngay dưới nến OUT
         g_outBuyBuffer[outBar] = outLow - 20 * _Point;

         // LƯU signal để vẽ lại
         g_savedSignalTime = time[outBar];
         g_savedZoneH = zoneH;
         g_savedZoneL = zoneL;
         g_savedOutBuy = g_outBuyBuffer[outBar];
         g_savedOutSell = EMPTY_VALUE;
         g_savedImpBarShift = impBar - outBar;

         double boxTop = outLow;
         double boxBottom = inHigh;
         double entry = (boxTop + boxBottom) / 2.0;

         if(InpShowBoxes)
            DrawBox(g_objPrefix + "OUTB_" + IntegerToString((long)time[outBar]),
                    time[inBar], time[outBar], boxTop, boxBottom, clrLime);

         if(InpEnableAlerts && time[outBar] > g_lastAlert)
         {
            Alert("🔼 OUT BUY: ", _Symbol,
                  " | Entry=", DoubleToString(entry, _Digits),
                  " | SL=", DoubleToString(zoneL, _Digits),
                  " | TP=", DoubleToString(outHigh, _Digits));
            g_lastAlert = time[outBar];
         }

         Print("✅ OUT BUY signal tạo ở bar[1], time=", TimeToString(time[outBar]));
      }
      else
      {
         // OUT Sell - QUAN TRỌNG: Đặt ở bar [1]
         // Mũi tên xuống màu đỏ ngay trên nến OUT
         g_outSellBuffer[outBar] = outHigh + 20 * _Point;

         // LƯU signal để vẽ lại
         g_savedSignalTime = time[outBar];
         g_savedZoneH = zoneH;
         g_savedZoneL = zoneL;
         g_savedOutBuy = EMPTY_VALUE;
         g_savedOutSell = g_outSellBuffer[outBar];
         g_savedImpBarShift = impBar - outBar;

         double boxTop = inLow;
         double boxBottom = outHigh;
         double entry = (boxTop + boxBottom) / 2.0;

         if(InpShowBoxes)
            DrawBox(g_objPrefix + "OUTS_" + IntegerToString((long)time[outBar]),
                    time[inBar], time[outBar], boxTop, boxBottom, clrRed);

         if(InpEnableAlerts && time[outBar] > g_lastAlert)
         {
            Alert("🔽 OUT SELL: ", _Symbol,
                  " | Entry=", DoubleToString(entry, _Digits),
                  " | SL=", DoubleToString(zoneH, _Digits),
                  " | TP=", DoubleToString(outLow, _Digits));
            g_lastAlert = time[outBar];
         }

         Print("✅ OUT SELL signal tạo ở bar[1], time=", TimeToString(time[outBar]));
      }

      // Cập nhật tracking
      g_lastSignalBar = bar1Time;
      g_signalCount++;
   }

   return(rates_total);
}
//+------------------------------------------------------------------+