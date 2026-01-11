
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

// =========================
// Inputs
// =========================
input string          InpSymbol              = "";              // "" = current chart symbol
input ENUM_TIMEFRAMES InpFvgTF               = PERIOD_M15;       // FVG timeframe (spec)
input int             InpLookbackBars        = 300;             // scan lookback on M15
input double          InpMinGapPoints        = 500;              // minimum FVG size (points)

input bool            InpUseATRFilter        = true;            // reduce low-quality FVGs
input int             InpATRLen              = 14;
input double          InpDisplacementATR     = 1.0;             // candle B range >= ATR*k

input double          InpRiskPercent         = 1.0;             // 0 = fixed lot
input double          InpFixedLot            = 0.01;

input double          InpRR_Min              = 2.0;             // min TP = 2R (spec)
input int             InpMagic               = 260111;

input int             InpMaxSpreadPoints     = 3000;             // safety for EUR/XAU is 120
input int             InpSlippagePoints      = 30;              // deviation in points
input int             InpEdgeBufferPoints    = 50;              // buffer beyond far edge (points) for SL & deep-cross check

input bool            InpDrawSimple          = true;            // draw rectangle + midpoint + state panel (light)
input bool            InpEnableFileLog       = true;           // Experts first; CSV optional
input string          InpLogFileName         = "FVG_M15_EA_Log.csv";
int                   g_lastSpreadState      = -1;


// =========================
// Logging
// =========================
enum LOG_LEVEL { LOG_OK, LOG_WARN, LOG_ERR, LOG_INFO };

string LogPrefix(LOG_LEVEL lv)
{
   switch(lv)
   {
      case LOG_OK:   return "🟢[OK] ";
      case LOG_WARN: return "🟡[WARN] ";
      case LOG_ERR:  return "🔴[ERR] ";
      default:       return "🔵[INFO] ";
   }
}

color LevelColor(LOG_LEVEL lv)
{
   switch(lv)
   {
      case LOG_OK:   return clrLime;
      case LOG_WARN: return clrGold;
      case LOG_ERR:  return clrTomato;
      default:       return clrDodgerBlue;
   }
}

string g_sym;
double g_point=0;
int    g_digits=0;

void Log(LOG_LEVEL lv, string event_type, string msg)
{
   string line = LogPrefix(lv) + event_type + " | " + msg;

   // 1) Experts (priority)
   Print(line);

   // 2) CSV optional
   if(!InpEnableFileLog) return;

   int fh = FileOpen(InpLogFileName,
                     FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_WRITE|FILE_ANSI);
   if(fh == INVALID_HANDLE) return;

   if(FileSize(fh) == 0)
      FileWrite(fh, "time", "symbol", "level", "event", "message");

   FileSeek(fh, 0, SEEK_END);
   FileWrite(fh,
             TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
             g_sym,
             (int)lv,
             event_type,
             msg);

   FileClose(fh);
}

// =========================
// FVG zone struct
// =========================
struct FvgZone
{
   bool     bullish;
   double   low;
   double   high;
   datetime outTime;     // time of candle C (OUT)
   int      barIndexC;   // debug
};

FvgZone  g_zone;
bool     g_hasZone=false;

bool     g_orderPlaced=false;   // trade 1 time per FVG (once pending placed, done)
bool     g_paused=false;        // pause until next FVG after deep cross
datetime g_lastFvgTime=0;

// =========================
// Drawing
// =========================
string OBJ_PREFIX;
string OBJ_PANEL;

string g_state="INIT";
string g_reason="";
string g_tpMode="";
double g_mid=0, g_sl=0, g_tp=0;

string Sym() { return (InpSymbol=="" ? _Symbol : InpSymbol); }
double NP(double p) { return NormalizeDouble(p, g_digits); }

int SpreadPoints()
{
   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   if(ask<=0 || bid<=0 || g_point<=0) return 999999;
   return (int)MathRound((ask - bid) / g_point);
}

void ClearDrawObjects()
{
   if(!InpDrawSimple) return;

   // Manual delete by prefix (MT5 ObjectsDeleteAll does not support prefix)
   int total = ObjectsTotal(0, 0, -1);
   for(int i=total-1; i>=0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, OBJ_PREFIX) == 0) // starts with prefix
         ObjectDelete(0, name);
   }
}

void DrawZone(const FvgZone &z)
{
   if(!InpDrawSimple) return;

   string rectName = OBJ_PREFIX + "_RECT";
   string midName  = OBJ_PREFIX + "_MID";

   datetime t1 = z.outTime;
   datetime t2 = TimeCurrent() + 60*60*6; // extend 6h

   double low  = z.low;
   double high = z.high;
   double mid  = (low + high) * 0.5;

   // Rectangle
   if(ObjectFind(0, rectName) < 0)
   {
      ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, t1, high, t2, low);
      ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
      ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 1);
   }
   else
   {
      // safer: move points instead of setting TIME1/PRICE1 props (compat)
      ObjectMove(0, rectName, 0, t1, high);
      ObjectMove(0, rectName, 1, t2, low);
   }

   // Midpoint line
   if(ObjectFind(0, midName) < 0)
   {
      ObjectCreate(0, midName, OBJ_TREND, 0, t1, mid, t2, mid);
      ObjectSetInteger(0, midName, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, midName, OBJPROP_WIDTH, 1);
   }
   else
   {
      ObjectMove(0, midName, 0, t1, mid);
      ObjectMove(0, midName, 1, t2, mid);
   }
}

void UpdatePanel(LOG_LEVEL lv)
{
   if(!InpDrawSimple) return;

   string text = "";
   text += "FVG M15 EA\n";
   text += "State: " + g_state + (g_reason=="" ? "" : " (" + g_reason + ")") + "\n";
   text += "SpreadPts: " + (string)SpreadPoints() + "\n";

   if(g_hasZone)
   {
      text += StringFormat("Side: %s | OUT: %s\n",
                           g_zone.bullish ? "BULL" : "BEAR",
                           TimeToString(g_zone.outTime, TIME_DATE|TIME_MINUTES));
      text += StringFormat("Zone: %.5f .. %.5f\n", g_zone.low, g_zone.high);
   }
   else
   {
      text += "Side: - | OUT: -\nZone: -\n";
   }

   if(g_mid!=0 && g_sl!=0 && g_tp!=0)
   {
      text += StringFormat("Mid: %.5f | SL: %.5f\nTP:  %.5f | TP_MODE: %s\n",
                           g_mid, g_sl, g_tp, g_tpMode);
   }

   if(ObjectFind(0, OBJ_PANEL) < 0)
   {
      ObjectCreate(0, OBJ_PANEL, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, OBJ_PANEL, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, OBJ_PANEL, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, OBJ_PANEL, OBJPROP_YDISTANCE, 20);
      ObjectSetInteger(0, OBJ_PANEL, OBJPROP_FONTSIZE, 10);
   }

   ObjectSetString(0, OBJ_PANEL, OBJPROP_TEXT, text);
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_COLOR, LevelColor(lv));
}

// =========================
// Market data helpers
// =========================
bool GetRates(ENUM_TIMEFRAMES tf, int count, MqlRates &rates[])
{
   ArraySetAsSeries(rates, true);
   return (CopyRates(g_sym, tf, 0, count, rates) == count);
}

double ATR(ENUM_TIMEFRAMES tf, int len, int shift=1)
{
   int h = iATR(g_sym, tf, len);
   if(h == INVALID_HANDLE) return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(h, 0, shift, 1, buf) != 1) return 0.0;
   return buf[0];
}

bool HasOurPosition()
{
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if((string)PositionGetString(POSITION_SYMBOL) != g_sym) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return true;
   }
   return false;
}

bool HasOurPendingOrder(ulong &ticket_out)
{
   int total = OrdersTotal();
   for(int i=0; i<total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;

      if((string)OrderGetString(ORDER_SYMBOL) != g_sym) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;

      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(t == ORDER_TYPE_BUY_LIMIT || t == ORDER_TYPE_SELL_LIMIT)
      {
         ticket_out = ticket;
         return true;
      }
   }
   ticket_out = 0;
   return false;
}

bool CancelOurPending()
{
   ulong ticket;
   if(!HasOurPendingOrder(ticket)) return true;

   trade.SetExpertMagicNumber(InpMagic);
   bool ok = trade.OrderDelete(ticket);

   Log(ok ? LOG_OK : LOG_WARN, "CANCEL_PENDING", "ticket=" + (string)ticket + ", ok=" + (string)ok);
   return ok;
}

// =========================
// Find latest valid FVG on M15 (A,B,C where C is OUT)
// =========================
bool FindLatestFVG(FvgZone &out)
{
   int need = MathMax(InpLookbackBars, 50);
   MqlRates r[];
   if(!GetRates(InpFvgTF, need, r)) return false;

   double atr = (InpUseATRFilter ? ATR(InpFvgTF, InpATRLen, 1) : 0.0);

   for(int i=1; i<need-2; i++)
   {
      MqlRates A = r[i+2];
      MqlRates B = r[i+1];
      MqlRates C = r[i];

      if(InpUseATRFilter && atr>0.0)
      {
         double rangeB = (B.high - B.low);
         if(rangeB < atr * InpDisplacementATR) continue;
      }

      bool bull=false;
      double zLow=0, zHigh=0;

      if(A.high < C.low)
      {
         bull = true;
         zLow = A.high;
         zHigh= C.low;
      }
      else if(A.low > C.high)
      {
         bull = false;
         zLow = C.high;
         zHigh= A.low;
      }
      else continue;

      double gapPts = (zHigh - zLow) / g_point;
      if(gapPts < InpMinGapPoints) continue;

      out.bullish  = bull;
      out.low      = zLow;
      out.high     = zHigh;
      out.outTime  = C.time;
      out.barIndexC= i;
      return true;
   }
   return false;
}

bool GetOutCandleHL(datetime outTime, double &outHigh, double &outLow)
{
   int shift = iBarShift(g_sym, InpFvgTF, outTime, true);
   if(shift < 0) return false;
   outHigh = iHigh(g_sym, InpFvgTF, shift);
   outLow  = iLow(g_sym, InpFvgTF, shift);
   return (outHigh>0 && outLow>0);
}

// =========================
// Lot sizing
// =========================
double CalcLotByRisk(double entry, double sl)
{
   if(InpRiskPercent <= 0.0) return InpFixedLot;

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);

   double tickSize  = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize<=0 || tickValue<=0) return InpFixedLot;

   double dist = MathAbs(entry - sl);
   if(dist <= 0) return InpFixedLot;

   double moneyPerLot = (dist / tickSize) * tickValue;
   if(moneyPerLot <= 0) return InpFixedLot;

   double lot = riskMoney / moneyPerLot;

   double minLot = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);

   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / step) * step;

   return lot;
}

// =========================
// Place limit order by spec
// =========================
bool PlaceLimitFromZone(const FvgZone &z)
{
   int sp = SpreadPoints();
   if(sp > InpMaxSpreadPoints)
   {
      g_state  = "WAIT";
      g_reason = "SPREAD";
      UpdatePanel(LOG_WARN);

      // chỉ log khi vừa chuyển sang trạng thái SPREAD_TOO_WIDE
      if(g_lastSpreadState != 1)
      {
         Log(LOG_WARN, "SKIP_SPREAD", "spreadPts=" + (string)sp);
         g_lastSpreadState = 1;
      }
      return false;
   }
   else
   {
      // spread vừa OK trở lại
      if(g_lastSpreadState == 1)
      {
         Log(LOG_INFO, "SPREAD_OK", "spreadPts=" + (string)sp);
         g_lastSpreadState = 0;
      }
   }

   if(HasOurPosition())
   {
      g_state = "IN_POSITION";
      g_reason= "";
      UpdatePanel(LOG_INFO);
      Log(LOG_INFO, "SKIP_HAS_POS", "already has position");
      return false;
   }

   ulong ticket;
   if(HasOurPendingOrder(ticket))
   {
      g_state = "PENDING";
      g_reason= "";
      UpdatePanel(LOG_INFO);
      Log(LOG_INFO, "SKIP_HAS_PENDING", "ticket=" + (string)ticket);
      return false;
   }

   double mid = NP((z.low + z.high) * 0.5);
   double buffer = InpEdgeBufferPoints * g_point;

   double outH, outL;
   if(!GetOutCandleHL(z.outTime, outH, outL))
   {
      g_state = "WAIT";
      g_reason= "OUT_HL_ERR";
      UpdatePanel(LOG_ERR);
      Log(LOG_ERR, "ERR_OUT_HL", "cannot read OUT candle H/L");
      return false;
   }

   double sl=0, tp=0;

   if(z.bullish)
   {
      sl = NP(z.low - buffer);
      double risk = mid - sl;
      if(risk <= 0) { Log(LOG_ERR, "ERR_RISK", "risk<=0 BUY"); return false; }

      double tp_2r  = NP(mid + InpRR_Min * risk);
      double tp_out = NP(outH);
      tp = (tp_out > tp_2r ? tp_out : tp_2r);
      if(tp <= mid) tp = tp_2r;

      g_tpMode = (tp == tp_out ? "OUT" : "2R");
   }
   else
   {
      sl = NP(z.high + buffer);
      double risk = sl - mid;
      if(risk <= 0) { Log(LOG_ERR, "ERR_RISK", "risk<=0 SELL"); return false; }

      double tp_2r  = NP(mid - InpRR_Min * risk);
      double tp_out = NP(outL);
      tp = (tp_out < tp_2r ? tp_out : tp_2r);
      if(tp >= mid) tp = tp_2r;

      g_tpMode = (tp == tp_out ? "OUT" : "2R");
   }

   double lot = CalcLotByRisk(mid, sl);
   if(lot <= 0) { Log(LOG_ERR, "ERR_LOT", "lot<=0"); return false; }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   bool ok=false;
   if(z.bullish)
      ok = trade.BuyLimit(lot, mid, g_sym, sl, tp, ORDER_TIME_GTC, 0, "FVG_M15_BUY");
   else
      ok = trade.SellLimit(lot, mid, g_sym, sl, tp, ORDER_TIME_GTC, 0, "FVG_M15_SELL");

   g_mid = mid; g_sl = sl; g_tp = tp;
   g_state = ok ? "PENDING" : "WAIT";
   g_reason= ok ? "" : "PLACE_FAIL";
   UpdatePanel(ok ? LOG_OK : LOG_ERR);

   string msg = StringFormat("%s | OUT=%s | zone=[%.5f..%.5f] | mid=%.5f | sl=%.5f | tp=%.5f | TP_MODE=%s | spreadPts=%d | lot=%.2f",
                             (z.bullish ? "BUY" : "SELL"),
                             TimeToString(z.outTime, TIME_DATE|TIME_MINUTES),
                             z.low, z.high,
                             mid, sl, tp, g_tpMode, sp, lot);

   Log(ok ? LOG_OK : LOG_ERR, "PLACE_LIMIT", msg);

   return ok;
}

// =========================
// Deep-cross pause
// =========================
void CheckDeepCrossPause()
{
   if(!g_hasZone || !g_orderPlaced) return;

   if(HasOurPosition())
   {
      g_state="IN_POSITION";
      g_reason="";
      UpdatePanel(LOG_INFO);
      return;
   }

   ulong ticket;
   if(!HasOurPendingOrder(ticket)) return;

   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double buffer = InpEdgeBufferPoints * g_point;

   if(g_zone.bullish)
   {
      double thr = g_zone.low - buffer;
      if(bid <= thr)
      {
         g_state="PAUSED";
         g_reason="DEEP_CROSS";
         UpdatePanel(LOG_WARN);

         Log(LOG_WARN, "PAUSE",
             StringFormat("DEEP_CROSS | bullish | bid=%.5f <= thr=%.5f | cancel pending, wait next FVG", bid, thr));

         CancelOurPending();
         g_paused = true;
      }
   }
   else
   {
      double thr = g_zone.high + buffer;
      if(ask >= thr)
      {
         g_state="PAUSED";
         g_reason="DEEP_CROSS";
         UpdatePanel(LOG_WARN);

         Log(LOG_WARN, "PAUSE",
             StringFormat("DEEP_CROSS | bearish | ask=%.5f >= thr=%.5f | cancel pending, wait next FVG", ask, thr));

         CancelOurPending();
         g_paused = true;
      }
   }
}

// =========================
// Zone lifecycle
// =========================
void UpdateZoneIfNew()
{
   FvgZone z;
   if(!FindLatestFVG(z)) return;
   if(z.outTime == 0) return;

   if(z.outTime != g_lastFvgTime)
   {
      Log(LOG_OK, "NEW_FVG",
          StringFormat("OUT=%s | side=%s | zone=[%.5f..%.5f] | barC=%d",
                       TimeToString(z.outTime, TIME_DATE|TIME_MINUTES),
                       (z.bullish ? "BULL" : "BEAR"),
                       z.low, z.high, z.barIndexC));

      CancelOurPending(); // limit lives until next FVG

      g_zone = z;
      g_hasZone = true;
      g_lastFvgTime = z.outTime;

      g_orderPlaced = false;
      g_paused      = false;

      g_mid=0; g_sl=0; g_tp=0; g_tpMode="";
      g_state="NEW_FVG";
      g_reason="";
      UpdatePanel(LOG_OK);

      if(InpDrawSimple)
      {
         ClearDrawObjects();
         DrawZone(g_zone);
      }
   }
}

// =========================
// Trade transaction logging
// =========================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.symbol != "" && trans.symbol != g_sym) return;

   // NOTE: some MT5 builds don't expose trans.reason; keep log portable
   string msg = StringFormat("type=%d | deal=%I64d | order=%I64d | price=%.5f | vol=%.2f | ret=%d",
                             (int)trans.type,
                             trans.deal,
                             trans.order,
                             trans.price,
                             trans.volume,
                             (int)result.retcode);

   Log(LOG_INFO, "TX", msg);

   if(HasOurPosition())
   {
      g_state="IN_POSITION";
      g_reason="";
      UpdatePanel(LOG_INFO);
   }
}

// =========================
// MT5 lifecycle
// =========================
int OnInit()
{
   g_sym = Sym();
   g_point  = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);

   OBJ_PREFIX = "FVG_M15_" + g_sym + "_" + (string)InpMagic;
   OBJ_PANEL  = OBJ_PREFIX + "_PANEL";

   trade.SetExpertMagicNumber(InpMagic);

   g_state="INIT";
   g_reason="";
   UpdatePanel(LOG_INFO);
   Log(LOG_INFO, "INIT", "EA started. symbol=" + g_sym);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Log(LOG_INFO, "DEINIT", "EA stopped. reason=" + (string)reason);
   if(InpDrawSimple) ClearDrawObjects();
}

void OnTick()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;

   UpdateZoneIfNew();

   if(!g_hasZone)
   {
      g_state="WAIT";
      g_reason="NO_FVG";
      UpdatePanel(LOG_INFO);
      return;
   }

   if(g_paused)
   {
      UpdatePanel(LOG_WARN);
      return;
   }

   if(!g_orderPlaced && !HasOurPosition())
   {
      bool ok = PlaceLimitFromZone(g_zone);
      if(ok) g_orderPlaced = true;
      if(InpDrawSimple) DrawZone(g_zone);
   }

   CheckDeepCrossPause();

   if(InpDrawSimple) DrawZone(g_zone);
}