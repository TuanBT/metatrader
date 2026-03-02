//+------------------------------------------------------------------+
//| Test Bot.mq5                                                      |
//| Simple test bot — auto-trades every 30s, alternates BUY/SELL      |
//| Purpose: Test Panel mechanics (SL, trailing, DCA, etc.)           |
//+------------------------------------------------------------------+
#property copyright "Tuan - Test Bot v1.00"
#property version   "1.00"
#property strict

// ════════════════════════════════════════════════════════════════════
// INPUTS
// ════════════════════════════════════════════════════════════════════
input int             InpInterval       = 30;         // Trade every N seconds
input bool            InpAlternate      = true;       // Alternate BUY ↔ SELL
input bool            InpUsePanelLot    = true;       // Use lot from Panel
input double          InpRiskMoney      = 10.0;       // Fallback risk ($)
input double          InpATRMult        = 1.5;        // ATR multiplier (SL)
input int             InpATRPeriod      = 14;         // ATR period
input int             InpDeviation      = 20;         // Max slippage
input ulong           InpMagic          = 99999;      // Magic Number

// ════════════════════════════════════════════════════════════════════
// PANEL
// ════════════════════════════════════════════════════════════════════
#define P       "Test_"
#define PBG     P "BG"
#define PTITLE  P "Title"
#define PBTN    P "Btn"
#define PINFO   P "Info"
#define PPOS    P "Pos"

#define BG_CLR   C'25,27,35'
#define BD_CLR   C'45,48,65'
#define TXT_CLR  C'220,225,240'
#define DIM_CLR  C'120,125,145'
#define GRN_CLR  C'0,180,100'
#define RED_CLR  C'220,80,80'
#define ON_CLR   C'0,100,60'
#define OFF_CLR  C'60,60,85'
#define YEL_CLR  C'255,200,50'

// ════════════════════════════════════════════════════════════════════
// GLOBALS
// ════════════════════════════════════════════════════════════════════
int      g_atr;
bool     g_on       = true;
bool     g_hasPos   = false;
bool     g_nextBuy  = true;
datetime g_lastTime = 0;
double   g_atrVal   = 0;
int      g_count    = 0;

// ════════════════════════════════════════════════════════════════════
// INIT / DEINIT
// ════════════════════════════════════════════════════════════════════
int OnInit()
{
   g_atr = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_atr == INVALID_HANDLE) return INIT_FAILED;

   // ── Panel ──
   int x = 15, y = 25, w = 180;

   ObjectCreate(0, PBG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PBG, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, PBG, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, PBG, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, PBG, OBJPROP_YSIZE, 115);
   ObjectSetInteger(0, PBG, OBJPROP_BGCOLOR, BG_CLR);
   ObjectSetInteger(0, PBG, OBJPROP_BORDER_COLOR, BD_CLR);
   ObjectSetInteger(0, PBG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, PBG, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   int r = y + 8;
   // Title
   MkLbl(PTITLE, x+8, r, "TEST BOT", YEL_CLR, 10, "Segoe UI Semibold");
   r += 24;

   // ON/OFF
   ObjectCreate(0, PBTN, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, PBTN, OBJPROP_XDISTANCE, x+8);
   ObjectSetInteger(0, PBTN, OBJPROP_YDISTANCE, r);
   ObjectSetInteger(0, PBTN, OBJPROP_XSIZE, w-16);
   ObjectSetInteger(0, PBTN, OBJPROP_YSIZE, 24);
   ObjectSetString (0, PBTN, OBJPROP_TEXT, "ON");
   ObjectSetString (0, PBTN, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, PBTN, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, PBTN, OBJPROP_COLOR, TXT_CLR);
   ObjectSetInteger(0, PBTN, OBJPROP_BGCOLOR, ON_CLR);
   ObjectSetInteger(0, PBTN, OBJPROP_BORDER_COLOR, ON_CLR);
   ObjectSetInteger(0, PBTN, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   r += 28;

   // Info line (countdown)
   MkLbl(PINFO, x+8, r, "", DIM_CLR, 10);
   r += 22;

   // Position line
   MkLbl(PPOS, x+8, r, "No position", DIM_CLR, 10);

   EventSetMillisecondTimer(500);
   PrintFormat("[TEST] Started | %s | every %ds", _Symbol, InpInterval);
   ChartRedraw();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, P);
   EventKillTimer();
   if(g_atr != INVALID_HANDLE) IndicatorRelease(g_atr);
   PrintFormat("[TEST] Stopped | trades: %d", g_count);
}

// ════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════
void MkLbl(string n, int x, int y, string t, color c, int sz=10, string f="Consolas")
{
   ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString (0, n, OBJPROP_TEXT, t);
   ObjectSetString (0, n, OBJPROP_FONT, f);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, sz);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
}

bool HasPos()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return true;
   }
   return false;
}

double GetPnL()
{
   double pnl = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

double GetLots()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return PositionGetDouble(POSITION_VOLUME);
   }
   return 0;
}

bool IsBuy()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   }
   return true;
}

double CalcLot()
{
   // Try Panel lot first
   if(InpUsePanelLot)
   {
      string gv = "TP_Lot_" + _Symbol;
      if(GlobalVariableCheck(gv))
      {
         double lot = GlobalVariableGet(gv);
         if(lot > 0) return lot;
      }
   }
   // Fallback: ATR-based risk
   if(g_atrVal <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double slDist  = g_atrVal * InpATRMult;
   if(tickSz <= 0 || tickVal <= 0 || slDist <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lot = InpRiskMoney / ((slDist / tickSz) * tickVal);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step > 0) lot = MathFloor(lot / step) * step;
   lot = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                 MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), lot));
   return lot;
}

// ════════════════════════════════════════════════════════════════════
// TICK + TIMER
// ════════════════════════════════════════════════════════════════════
void OnTick()
{
   double a[1];
   if(CopyBuffer(g_atr, 0, 1, 1, a) == 1 && a[0] > 0) g_atrVal = a[0];

   if(!g_on) return;
   g_hasPos = HasPos();
   if(g_hasPos) return;
   if(g_atrVal <= 0) return;

   datetime now = TimeCurrent();
   if(g_lastTime > 0 && (now - g_lastTime) < InpInterval) return;

   // ── Trade ──
   g_lastTime = now;
   double lot = CalcLot();
   double price = g_nextBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = g_nextBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price     = price;
   req.sl        = 0;
   req.tp        = 0;
   req.deviation = InpDeviation;
   req.magic     = InpMagic;
   req.comment   = "Test";

   if(OrderSend(req, res))
   {
      g_count++;
      PrintFormat("[TEST] #%d %s %.2f @ %s",
                  g_count, g_nextBuy ? "BUY" : "SELL", lot,
                  DoubleToString(price, _Digits));
   }
   else
      PrintFormat("[TEST] FAIL: %d %s", res.retcode, res.comment);

   if(InpAlternate) g_nextBuy = !g_nextBuy;
}

void OnTimer()
{
   // ── Button state ──
   if(g_on)
   {
      ObjectSetString (0, PBTN, OBJPROP_TEXT, "ON");
      ObjectSetInteger(0, PBTN, OBJPROP_BGCOLOR, ON_CLR);
      ObjectSetInteger(0, PBTN, OBJPROP_BORDER_COLOR, ON_CLR);
   }
   else
   {
      ObjectSetString (0, PBTN, OBJPROP_TEXT, "OFF");
      ObjectSetInteger(0, PBTN, OBJPROP_BGCOLOR, OFF_CLR);
      ObjectSetInteger(0, PBTN, OBJPROP_BORDER_COLOR, OFF_CLR);
   }

   // ── Info line ──
   g_hasPos = HasPos();
   if(g_hasPos)
   {
      ObjectSetString(0, PINFO, OBJPROP_TEXT,
         StringFormat("#%d  waiting...", g_count));
      ObjectSetInteger(0, PINFO, OBJPROP_COLOR, DIM_CLR);
   }
   else
   {
      int sec = InpInterval - (int)(TimeCurrent() - g_lastTime);
      if(sec < 0) sec = 0;
      string dir = g_nextBuy ? "BUY" : "SELL";
      ObjectSetString(0, PINFO, OBJPROP_TEXT,
         StringFormat("#%d  %s in %ds", g_count+1, dir, sec));
      ObjectSetInteger(0, PINFO, OBJPROP_COLOR, g_nextBuy ? GRN_CLR : RED_CLR);
   }

   // ── Position line ──
   if(g_hasPos)
   {
      double pnl = GetPnL();
      ObjectSetString(0, PPOS, OBJPROP_TEXT,
         StringFormat("%.2f %s  $%+.2f", GetLots(),
                      IsBuy() ? "LONG" : "SHORT", pnl));
      ObjectSetInteger(0, PPOS, OBJPROP_COLOR, pnl >= 0 ? GRN_CLR : RED_CLR);
   }
   else
   {
      ObjectSetString(0, PPOS, OBJPROP_TEXT, "No position");
      ObjectSetInteger(0, PPOS, OBJPROP_COLOR, DIM_CLR);
   }

   ChartRedraw();
}

// ════════════════════════════════════════════════════════════════════
// CLICK
// ════════════════════════════════════════════════════════════════════
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   if(sparam == PBTN)
   {
      ObjectSetInteger(0, PBTN, OBJPROP_STATE, false);
      g_on = !g_on;
      PrintFormat("[TEST] %s", g_on ? "ON" : "OFF");
   }
}
//+------------------------------------------------------------------+
