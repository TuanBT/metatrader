//+------------------------------------------------------------------+
//| Random Bot Test.mq5                                               |
//| Simple bot that opens random BUY/SELL every N minutes             |
//| For testing Trading Panel's Manage Magic feature                  |
//+------------------------------------------------------------------+
#property copyright "Tuan"
#property version   "1.00"
#property strict

input ulong  InpBotMagic     = 88888;     // Bot Magic Number
input double InpLotSize      = 0.01;      // Lot Size
input int    InpIntervalMin  = 5;         // Open trade every N minutes
input double InpSLPoints     = 500;       // SL distance (points)
input double InpTPPoints     = 1000;      // TP distance (points)
input int    InpMaxPositions = 1;         // Max open positions

datetime g_lastTradeBar = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   EventSetMillisecondTimer(1000);
   Print(StringFormat("[RANDOM BOT] Started | Magic=%d | Lot=%.2f | Interval=%d min",
         InpBotMagic, InpLotSize, InpIntervalMin));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("[RANDOM BOT] Stopped");
}

//+------------------------------------------------------------------+
void OnTick()
{
   TryOpenRandom();
}

//+------------------------------------------------------------------+
void OnTimer()
{
   TryOpenRandom();
}

//+------------------------------------------------------------------+
void TryOpenRandom()
{
   // Check interval (use M1 bars as timer)
   datetime curBar = iTime(_Symbol, PERIOD_M1, 0);
   if(curBar == g_lastTradeBar) return;

   // Only trade every N minutes
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.min % InpIntervalMin != 0) return;

   // Check max positions
   int count = CountPositions();
   if(count >= InpMaxPositions) return;

   g_lastTradeBar = curBar;

   // Random direction
   MathSrand((uint)GetTickCount());
   bool isBuy = (MathRand() % 2 == 0);

   OpenTrade(isBuy);
}

//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpBotMagic) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
void OpenTrade(bool isBuy)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double price, sl, tp;
   ENUM_ORDER_TYPE orderType;

   if(isBuy)
   {
      orderType = ORDER_TYPE_BUY;
      price = ask;
      sl = price - InpSLPoints * point;
      tp = price + InpTPPoints * point;
   }
   else
   {
      orderType = ORDER_TYPE_SELL;
      price = bid;
      sl = price + InpSLPoints * point;
      tp = price - InpTPPoints * point;
   }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = InpLotSize;
   req.type      = orderType;
   req.price     = price;
   req.sl        = NormalizeDouble(sl, _Digits);
   req.tp        = NormalizeDouble(tp, _Digits);
   req.deviation = 20;
   req.magic     = InpBotMagic;
   req.comment   = "RandomBot";

   if(OrderSend(req, res))
   {
      Print(StringFormat("[RANDOM BOT] %s %.2f @ %s | SL=%s | TP=%s | Magic=%d",
            isBuy ? "BUY" : "SELL",
            InpLotSize,
            DoubleToString(price, _Digits),
            DoubleToString(req.sl, _Digits),
            DoubleToString(req.tp, _Digits),
            InpBotMagic));
   }
   else
   {
      Print(StringFormat("[RANDOM BOT] OrderSend FAILED: %d - %s",
            res.retcode, res.comment));
   }
}
//+------------------------------------------------------------------+
