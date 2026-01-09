//+------------------------------------------------------------------+
//| M15 Impulse FVG Entry EA                                         |
//| Sử dụng Indicator mql.mq5 để lấy tín hiệu                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Tuan"
#property link      "https://mql5.com"
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
// Indicator parameters (phải khớp với mql.mq5)
input int    InpATRLen        = 14;    // ATR Length (M15)
input double InpATRMult       = 1.2;   // ATR Multiplier
input double InpBodyRatioMin  = 0.55;  // Min Body/Range
input int    InpMaxM15Bars    = 500;   // Max M15 bars to scan
input int    InpMaxM5Bars     = 1500;  // Max M5 bars to scan

// Trade parameters
input double InpLotSize       = 0.01;  // Lot size
input int    InpDeviation     = 20;    // Max deviation (points)
input ulong  InpMagic         = 20260109; // Magic number
input bool   InpOnePosition   = true;  // Only one position at a time
input int    InpExpiryMinutes = 0;     // Pending expiry minutes (0 = no expiry)
input double InpSLBuffer      = 0.0;   // SL buffer in points (0 = no buffer)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
int g_indicatorHandle = INVALID_HANDLE;
datetime g_lastSignalTime = 0;
datetime g_lastBarTime = 0;

// Buffer indices từ indicator (phải khớp với mql.mq5)
#define BUFFER_IMPULSE   0
#define BUFFER_ZONE_HIGH 1
#define BUFFER_ZONE_LOW  2
#define BUFFER_OUT_BUY   3
#define BUFFER_OUT_SELL  4

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Tạo handle cho indicator mql.mq5
   // Đường dẫn: nếu indicator nằm cùng thư mục với EA, chỉ cần tên file (không có .mq5)
   g_indicatorHandle = iCustom(
      _Symbol,
      _Period,
      "Indicator M15 Impulse FAG Entry",                // Tên indicator (không có extension)
      InpATRLen,            // ATR Length
      InpATRMult,           // ATR Multiplier
      InpBodyRatioMin,      // Body Ratio Min
      InpMaxM15Bars,        // Max M15 bars
      InpMaxM5Bars          // Max M5 bars
   );

   if(g_indicatorHandle == INVALID_HANDLE)
   {
      Print("❌ Failed to create indicator handle. Error: ", GetLastError());
      Print("   Đảm bảo file mql.ex5 nằm trong thư mục MQL5/Indicators/");
      return(INIT_FAILED);
   }

   Print("✅ EA initialized. Indicator handle: ", g_indicatorHandle);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_indicatorHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_indicatorHandle);
      g_indicatorHandle = INVALID_HANDLE;
   }
   Print("EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Check if there are active orders/positions                       |
//+------------------------------------------------------------------+
bool HasActiveOrders()
{
   // Check positions
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }

   // Check pending orders
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Normalize price to tick size                                     |
//+------------------------------------------------------------------+
double NormalizePrice(const double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0)
      tick = _Point;
   double normalized = MathRound(price / tick) * tick;
   return NormalizeDouble(normalized, _Digits);
}

//+------------------------------------------------------------------+
//| Place pending order                                              |
//+------------------------------------------------------------------+
bool PlaceFvgOrder(const bool isBuy, 
                   const double entry, 
                   const double sl, 
                   const double tp,
                   const datetime signalTime)
{
   double entryNorm = NormalizePrice(entry);
   double slNorm    = NormalizePrice(sl);
   double tpNorm    = NormalizePrice(tp);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Xác định loại lệnh
   ENUM_ORDER_TYPE type;

   if(isBuy)
   {
      // Buy Limit: entry < ask
      if(entryNorm >= ask)
      {
         Print("⚠️ Skip buy limit: entry (", entryNorm, ") >= ask (", ask, ")");
         return false;
      }
      type = ORDER_TYPE_BUY_LIMIT;
   }
   else
   {
      // Sell Limit: entry > bid
      if(entryNorm <= bid)
      {
         Print("⚠️ Skip sell limit: entry (", entryNorm, ") <= bid (", bid, ")");
         return false;
      }
      type = ORDER_TYPE_SELL_LIMIT;
   }

   // Validate SL/TP placement
   if(isBuy && !(slNorm < entryNorm && entryNorm < tpNorm))
   {
      Print("❌ Invalid buy SL/TP: SL=", slNorm, " Entry=", entryNorm, " TP=", tpNorm);
      return false;
   }
   if(!isBuy && !(tpNorm < entryNorm && entryNorm < slNorm))
   {
      Print("❌ Invalid sell SL/TP: TP=", tpNorm, " Entry=", entryNorm, " SL=", slNorm);
      return false;
   }

   // Prepare order request
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action    = TRADE_ACTION_PENDING;
   req.symbol    = _Symbol;
   req.volume    = InpLotSize;
   req.type      = type;
   req.price     = entryNorm;
   req.sl        = slNorm;
   req.tp        = tpNorm;
   req.magic     = InpMagic;
   req.deviation = InpDeviation;
   req.comment   = isBuy ? "FVG_BUY" : "FVG_SELL";

   // Set expiration if configured
   if(InpExpiryMinutes > 0)
   {
      req.type_time  = ORDER_TIME_SPECIFIED;
      req.expiration = signalTime + InpExpiryMinutes * 60;
   }

   // Send order
   if(!OrderSend(req, res))
   {
      Print("❌ OrderSend failed. Retcode=", res.retcode, " Error=", GetLastError());
      return false;
   }

   Print("✅ ", (isBuy ? "BUY" : "SELL"), " LIMIT placed. Ticket=", res.order,
         " Entry=", entryNorm, " SL=", slNorm, " TP=", tpNorm);
   return true;
}

//+------------------------------------------------------------------+
//| Read indicator buffers                                           |
//+------------------------------------------------------------------+
bool ReadIndicatorBuffers(double &outBuy, 
                          double &outSell, 
                          double &zoneH, 
                          double &zoneL)
{
   double bufOutBuy[1], bufOutSell[1], bufZoneH[1], bufZoneL[1];

   // Copy từ bar [1] (bar vừa đóng)
   if(CopyBuffer(g_indicatorHandle, BUFFER_OUT_BUY, 1, 1, bufOutBuy) != 1)
      return false;
   if(CopyBuffer(g_indicatorHandle, BUFFER_OUT_SELL, 1, 1, bufOutSell) != 1)
      return false;
   if(CopyBuffer(g_indicatorHandle, BUFFER_ZONE_HIGH, 1, 1, bufZoneH) != 1)
      return false;
   if(CopyBuffer(g_indicatorHandle, BUFFER_ZONE_LOW, 1, 1, bufZoneL) != 1)
      return false;

   outBuy  = bufOutBuy[0];
   outSell = bufOutSell[0];
   zoneH   = bufZoneH[0];
   zoneL   = bufZoneL[0];

   return true;
}

//+------------------------------------------------------------------+
//| Get IN candle data from recent bars                              |
//| Tìm nến IN gần nhất trước nến OUT                                |
//+------------------------------------------------------------------+
bool FindINCandle(const double zoneH, 
                  const double zoneL,
                  double &inHigh, 
                  double &inLow)
{
   // Scan ngược từ bar [2] về quá khứ để tìm nến IN
   // Bar [1] là nến OUT, bar [2] trở đi có thể là IN
   for(int i = 2; i < 50; i++)
   {
      double h = iHigh(_Symbol, _Period, i);
      double l = iLow(_Symbol, _Period, i);

      // Nến IN: nằm hoàn toàn trong zone
      if(h < zoneH && l > zoneL)
      {
         inHigh = h;
         inLow  = l;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Chỉ xử lý khi có bar mới
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == g_lastBarTime)
      return;
   g_lastBarTime = currentBarTime;

   // Check indicator handle
   if(g_indicatorHandle == INVALID_HANDLE)
      return;

   // Read indicator buffers
   double outBuy, outSell, zoneH, zoneL;
   if(!ReadIndicatorBuffers(outBuy, outSell, zoneH, zoneL))
   {
      Print("⚠️ Failed to read indicator buffers");
      return;
   }

   // Check for OUT signal
   // Indicator trả về giá (price) khi có signal, EMPTY_VALUE khi không có
   bool hasOutBuy  = (outBuy != EMPTY_VALUE && outBuy != 0.0);
   bool hasOutSell = (outSell != EMPTY_VALUE && outSell != 0.0);

   if(!hasOutBuy && !hasOutSell)
      return;

   // Prevent duplicate signals
   datetime barTime = iTime(_Symbol, _Period, 1);
   if(barTime == g_lastSignalTime)
      return;
   g_lastSignalTime = barTime;

   // Check if already has position/order
   if(InpOnePosition && HasActiveOrders())
   {
      Print("ℹ️ Signal detected but already has active order/position");
      return;
   }

   // Get bar [1] data (nến OUT)
   double high1 = iHigh(_Symbol, _Period, 1);
   double low1  = iLow(_Symbol, _Period, 1);

   // Find IN candle
   double inHigh = 0.0, inLow = 0.0;
   if(!FindINCandle(zoneH, zoneL, inHigh, inLow))
   {
      Print("⚠️ Cannot find IN candle");
      return;
   }

   // Calculate Entry, SL, TP
   double entry = 0.0;
   double sl    = 0.0;
   double tp    = 0.0;
   bool isBuy   = hasOutBuy;

   if(hasOutBuy)
   {
      // OUT Buy:
      // Box: từ inHigh đến low1 (nến OUT)
      // Entry: trung điểm Box
      entry = (inHigh + low1) / 2.0;
      // SL: đáy Zone + buffer
      sl = zoneL - InpSLBuffer * _Point;
      // TP: high của nến OUT
      tp = high1;

      Print("📈 OUT BUY detected. inHigh=", inHigh, " low1=", low1, 
            " Entry=", entry, " SL=", sl, " TP=", tp);
   }
   else if(hasOutSell)
   {
      // OUT Sell:
      // Box: từ high1 (nến OUT) đến inLow
      // Entry: trung điểm Box
      entry = (high1 + inLow) / 2.0;
      // SL: đỉnh Zone + buffer
      sl = zoneH + InpSLBuffer * _Point;
      // TP: low của nến OUT
      tp = low1;

      Print("📉 OUT SELL detected. high1=", high1, " inLow=", inLow,
            " Entry=", entry, " SL=", sl, " TP=", tp);
   }

   // Place order
   PlaceFvgOrder(isBuy, entry, sl, tp, TimeCurrent());
}
//+------------------------------------------------------------------+