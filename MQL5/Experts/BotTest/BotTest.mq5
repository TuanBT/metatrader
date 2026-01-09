//+------------------------------------------------------------------+
//| Simple Test EA - For DEMO testing only                           |
//+------------------------------------------------------------------+
#property strict

input double LotSize   = 0.01;
input int    StopLoss  = 200;   // points
input int    TakeProfit= 200;   // points
input ulong  Magic     = 20260108;

datetime lastBarTime = 0;

//+------------------------------------------------------------------+
void OnTick()
{
   // Chỉ chạy khi có nến mới
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;

   // Không vào thêm nếu đang có lệnh
   if(PositionsTotal() > 0)
      return;

   // Dữ liệu nến trước
   double open1  = iOpen(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);

   bool isBuy = close1 > open1;
   bool isSell= close1 < open1;

   if(isBuy)
      OpenOrder(ORDER_TYPE_BUY);
   else if(isSell)
      OpenOrder(ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
void OpenOrder(ENUM_ORDER_TYPE type)
{
   MqlTradeRequest  req;
   MqlTradeResult   res;

   ZeroMemory(req);
   ZeroMemory(res);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (type == ORDER_TYPE_BUY) ? ask : bid;

   // Range của nến trước (bar 1)
   double h1 = iHigh(_Symbol, _Period, 1);
   double l1 = iLow(_Symbol, _Period, 1);
   double range = h1 - l1;

   // Nếu dữ liệu nến lỗi thì thoát
   if(range <= 0)
   {
      Print("⚠️ Invalid previous candle range.");
      return;
   }

   // SL/TP = 1x range (bạn có thể đổi multiplier)
   double slDist = range * 1.0;
   double tpDist = range * 1.0;

   double sl = (type == ORDER_TYPE_BUY) ? (price - slDist) : (price + slDist);
   double tp = (type == ORDER_TYPE_BUY) ? (price + tpDist) : (price - tpDist);

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = LotSize;
   req.type      = type;
   req.price     = price;
   req.sl        = NormalizeDouble(sl, _Digits);
   req.tp        = NormalizeDouble(tp, _Digits);
   req.magic     = Magic;
   req.deviation = 20;
   req.comment   = "TEST_EA_RANGE";

   if(!OrderSend(req, res))
      Print("❌ OrderSend failed. Retcode=", res.retcode);
   else
      Print("✅ Order placed. Ticket=", res.order, " SL=", req.sl, " TP=", req.tp);
}