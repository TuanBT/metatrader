//+------------------------------------------------------------------+
//| Random Sideway EA - XAUUSD M5                                    |
//| RR 1:3 | BE | Anti-Martingale (increase risk after win)          |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

// ===================== INPUT =====================
input double RiskBase      = 0.5;     // % risk ban đầu
input double RiskStep      = 0.25;    // tăng risk sau WIN
input double RiskMax       = 1.5;     // risk tối đa
input double RR            = 3.0;

input int    ADX_Period    = 14;
input double ADX_Max       = 18.0;

input int    ATR_Period    = 14;
input double ATR_Impulse   = 1.8;

input ENUM_TIMEFRAMES TF   = PERIOD_M1;

// ===================== GLOBAL =====================
double   CurrentRisk;
datetime LastBarTime = 0;

int hADX = INVALID_HANDLE;
int hATR = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, TF, 0);
   if(t != LastBarTime)
   {
      LastBarTime = t;
      return true;
   }
   return false;
}

bool GetADX(double &adx_val, int shift=0)
{
   if(hADX == INVALID_HANDLE) return false;

   double buf[];
   ArraySetAsSeries(buf, true);

   // buffer 0 of iADX is ADX line
   if(CopyBuffer(hADX, 0, shift, 1, buf) != 1) return false;
   adx_val = buf[0];
   return true;
}

bool GetATR(double &atr_val, int shift=0)
{
   if(hATR == INVALID_HANDLE) return false;

   double buf[];
   ArraySetAsSeries(buf, true);

   // buffer 0 of iATR is ATR line
   if(CopyBuffer(hATR, 0, shift, 1, buf) != 1) return false;
   atr_val = buf[0];
   return true;
}

double NormalizeVolume(double vol)
{
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(vol < vmin) vol = vmin;
   if(vol > vmax) vol = vmax;

   // snap to step
   vol = MathFloor(vol / vstep) * vstep;

   // normalize digits
   int digits = (int)MathRound(-MathLog10(vstep));
   if(digits < 0) digits = 0;
   return NormalizeDouble(vol, digits);
}

double CalcLot(double sl_dist_price)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * CurrentRisk / 100.0;

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tick_value <= 0 || tick_size <= 0) return NormalizeVolume(0.01);

   // loss per 1 lot if SL hit:
   // sl_dist_price is price distance; convert to ticks: sl_dist_price / tick_size
   double loss_per_lot = (sl_dist_price / tick_size) * tick_value;
   if(loss_per_lot <= 0) return NormalizeVolume(0.01);

   double lot = risk_money / loss_per_lot;
   return NormalizeVolume(lot);
}

bool IsSideway()
{
   double adx, atr;
   if(!GetADX(adx, 0)) return false;
   if(!GetATR(atr, 0)) return false;

   if(adx > ADX_Max) return false;

   // impulse filter: candle body of previous closed bar (shift=1)
   double o1 = iOpen(_Symbol, TF, 1);
   double c1 = iClose(_Symbol, TF, 1);
   double body = MathAbs(c1 - o1);

   if(body > atr * ATR_Impulse) return false;

   return true;
}

void ManagePositionBE()
{
   if(!PositionSelect(_Symbol)) return;

   long type = (long)PositionGetInteger(POSITION_TYPE);
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double tp   = PositionGetDouble(POSITION_TP);

   // Need SL to compute R
   if(sl <= 0) return;

   double risk = MathAbs(open - sl);
   if(risk <= 0) return;

   // Move to BE at +1R
   if(type == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid >= open + risk && sl < open)
         trade.PositionModify(_Symbol, open, tp);
   }
   else if(type == POSITION_TYPE_SELL)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(ask <= open - risk && sl > open)
         trade.PositionModify(_Symbol, open, tp);
   }
}

void OpenRandomTrade()
{
   double atr;
   if(!GetATR(atr, 0)) return;

   // SL = 1 * ATR (price distance)
   double sl_dist = atr * 1.0;
   double tp_dist = sl_dist * RR;

   double lot = CalcLot(sl_dist);
   if(lot <= 0) return;

   bool buy = (MathRand() % 2 == 0);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double price = buy ? ask : bid;
   double sl    = buy ? price - sl_dist : price + sl_dist;
   double tp    = buy ? price + tp_dist : price - tp_dist;

   trade.SetDeviationInPoints(30);

   if(buy) trade.Buy(lot, _Symbol, price, sl, tp);
   else    trade.Sell(lot, _Symbol, price, sl, tp);
}

//+------------------------------------------------------------------+
//| Init / Deinit                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(_Symbol != "XAUUSD")
      Print("Warning: EA is designed for XAUUSD, current = ", _Symbol);

   if(Period() != TF)
      Print("Warning: Attach EA on M5 chart to match logic.");

   CurrentRisk = RiskBase;
   MathSrand((uint)GetTickCount());

   hADX = iADX(_Symbol, TF, ADX_Period);
   if(hADX == INVALID_HANDLE)
   {
      Print("Failed to create ADX handle. Error=", GetLastError());
      return(INIT_FAILED);
   }

   hATR = iATR(_Symbol, TF, ATR_Period);
   if(hATR == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle. Error=", GetLastError());
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(hADX != INVALID_HANDLE) IndicatorRelease(hADX);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
}

//+------------------------------------------------------------------+
//| Tick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   // Manage BE every tick (để dời SL kịp)
   ManagePositionBE();

   // Entry only at new bar
   if(!IsNewBar()) return;

   // only 1 position at a time
   if(PositionSelect(_Symbol)) return;

   if(!IsSideway()) return;

   OpenRandomTrade();
}

//+------------------------------------------------------------------+
//| Trade result: Anti-Martingale after WIN                          |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req,
                        const MqlTradeResult &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal <= 0) return;

   // only react to closing deals
   long entry = (long)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   if(profit > 0)
   {
      CurrentRisk += RiskStep;
      if(CurrentRisk > RiskMax) CurrentRisk = RiskBase;
   }
   else if(profit < 0)
   {
      CurrentRisk = RiskBase;
   }
}