//+------------------------------------------------------------------+
//| Trend Signal Bot Test.mq5                                         |
//| TEST VERSION: Ignores trend, auto-trades every 1 minute           |
//| Alternates BUY / SELL. Only 1 position at a time.                 |
//| Purpose: Verify bot mechanics (order, SL relay to Panel, etc.)    |
//+------------------------------------------------------------------+
#property copyright "Tuan TEST v1.00"
#property version   "1.00"
#property strict

// ════════════════════════════════════════════════════════════════════
// INPUTS
// ════════════════════════════════════════════════════════════════════
input group           "══ Test Settings ══"
input int             InpIntervalSec    = 60;         // Trade interval in seconds
input bool            InpAlternateDir   = true;       // Alternate BUY/SELL each trade

input group           "══ Risk ══"
input bool            InpUsePanelLot    = true;       // Use lot from Trading Panel
input double          InpRiskMoney      = 10.0;       // Fallback risk per trade ($)
input double          InpATRMult        = 1.5;        // ATR multiplier (fallback SL calc)
input int             InpATRPeriod      = 14;         // ATR period
input int             InpDeviation      = 20;         // Max slippage (points)

input group           "══ General ══"
input ulong           InpMagic          = 99999;      // Magic Number

// ════════════════════════════════════════════════════════════════════
// CONSTANTS
// ════════════════════════════════════════════════════════════════════
#define BOT_PREFIX   "TBot_"

// Object names
#define OBJ_BG       BOT_PREFIX "BG"
#define OBJ_TITLE    BOT_PREFIX "Title"
#define OBJ_STATUS   BOT_PREFIX "Status"
#define OBJ_START    BOT_PREFIX "Start"
#define OBJ_FORCE_BUY  BOT_PREFIX "ForceBuy"
#define OBJ_FORCE_SELL BOT_PREFIX "ForceSell"
#define OBJ_POS_INFO BOT_PREFIX "PosInfo"
#define OBJ_TIMER    BOT_PREFIX "Timer"

// Colors
#define COL_BG       C'25,27,35'
#define COL_BORDER   C'45,48,65'
#define COL_WHITE    C'220,225,240'
#define COL_DIM      C'120,125,145'
#define COL_GREEN    C'0,180,100'
#define COL_RED      C'220,80,80'
#define COL_BLUE     C'30,80,140'
#define COL_BTN_BG   C'50,50,70'
#define COL_BTN_ON   C'0,100,60'
#define COL_BTN_OFF  C'60,60,85'
#define COL_YELLOW   C'255,200,50'

// Layout
#define BOT_PX      15
#define BOT_PY      25
#define BOT_W       180
#define BOT_H       155
#define BOT_ROW     22
#define BOT_PAD     6

// ════════════════════════════════════════════════════════════════════
// GLOBALS
// ════════════════════════════════════════════════════════════════════
int g_atrHandle;
bool     g_botEnabled    = true;
bool     g_hasPos        = false;
bool     g_nextIsBuy     = true;     // Next trade direction
datetime g_lastTradeTime = 0;        // Last trade attempt time
double   g_cachedATR     = 0;
int      g_tradeCount    = 0;        // Total trades opened

// ════════════════════════════════════════════════════════════════════
// INIT / DEINIT
// ════════════════════════════════════════════════════════════════════
int OnInit()
{
   g_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("[TEST BOT] Failed to create ATR handle");
      return INIT_FAILED;
   }

   CreatePanel();
   UpdatePanel();
   EventSetMillisecondTimer(1000);

   Print(StringFormat("[TEST BOT] Started | %s | Magic=%d | Interval=%ds | Alternate=%s | PanelLot=%s",
         _Symbol, InpMagic, InpIntervalSec,
         InpAlternateDir ? "ON" : "OFF",
         InpUsePanelLot ? "ON" : "OFF"));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DestroyPanel();
   EventKillTimer();
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   Print(StringFormat("[TEST BOT] Stopped | Total trades: %d", g_tradeCount));
}

// ════════════════════════════════════════════════════════════════════
// UI PANEL
// ════════════════════════════════════════════════════════════════════
void MakeLabel(string name, int x, int y, string text, color clr, int fontSize=8, string font="Consolas")
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void MakeButton(string name, int x, int y, int w, int h, string text, color bgClr, color txtClr, int fontSize=8)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void CreatePanel()
{
   int x = BOT_PX, y = BOT_PY;

   // Background
   ObjectCreate(0, OBJ_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_XSIZE, BOT_W);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_YSIZE, BOT_H);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_BGCOLOR, COL_BG);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_BORDER_COLOR, COL_BORDER);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   int row = y + BOT_PAD;

   // Row 1: Title
   MakeLabel(OBJ_TITLE, x + BOT_PAD, row, "TEST Bot (auto-trade)", COL_YELLOW, 9, "Segoe UI Semibold");
   row += BOT_ROW;

   // Row 2: Start/Stop button
   MakeButton(OBJ_START, x + BOT_PAD, row, BOT_W - 2*BOT_PAD, 22,
              "Bot: ON", COL_BTN_ON, COL_WHITE, 9);
   row += 26;

   // Row 3: Timer / next direction
   MakeLabel(OBJ_TIMER, x + BOT_PAD, row, "Next: BUY in 60s", COL_DIM, 8, "Consolas");
   row += BOT_ROW;

   // Row 4: Position info
   MakeLabel(OBJ_POS_INFO, x + BOT_PAD, row, "No position", COL_DIM, 8, "Consolas");
   row += BOT_ROW + 2;

   // Row 5: Force BUY / Force SELL buttons
   int btnW = (BOT_W - 2*BOT_PAD - 4) / 2;
   MakeButton(OBJ_FORCE_BUY,  x + BOT_PAD,          row, btnW, 22, "Force BUY",  C'0,100,65', COL_WHITE, 8);
   MakeButton(OBJ_FORCE_SELL, x + BOT_PAD + btnW + 4, row, btnW, 22, "Force SELL", C'140,40,40', COL_WHITE, 8);

   ChartRedraw();
}

void DestroyPanel()
{
   ObjectsDeleteAll(0, BOT_PREFIX);
   ChartRedraw();
}

void UpdatePanel()
{
   // ── Start/Stop button ──
   if(g_botEnabled)
   {
      ObjectSetString (0, OBJ_START, OBJPROP_TEXT, "Bot: ON");
      ObjectSetInteger(0, OBJ_START, OBJPROP_BGCOLOR, COL_BTN_ON);
      ObjectSetInteger(0, OBJ_START, OBJPROP_BORDER_COLOR, COL_BTN_ON);
      ObjectSetInteger(0, OBJ_START, OBJPROP_COLOR, COL_WHITE);
   }
   else
   {
      ObjectSetString (0, OBJ_START, OBJPROP_TEXT, "Bot: OFF");
      ObjectSetInteger(0, OBJ_START, OBJPROP_BGCOLOR, COL_BTN_OFF);
      ObjectSetInteger(0, OBJ_START, OBJPROP_BORDER_COLOR, COL_BTN_OFF);
      ObjectSetInteger(0, OBJ_START, OBJPROP_COLOR, C'180,180,200');
   }

   // ── Timer / direction display ──
   g_hasPos = HasPosition();

   if(g_hasPos)
   {
      ObjectSetString(0, OBJ_TIMER, OBJPROP_TEXT,
         StringFormat("Trades: %d | Waiting...", g_tradeCount));
      ObjectSetInteger(0, OBJ_TIMER, OBJPROP_COLOR, COL_DIM);
   }
   else
   {
      int elapsed = (int)(TimeCurrent() - g_lastTradeTime);
      int remaining = InpIntervalSec - elapsed;
      if(remaining < 0) remaining = 0;
      string dir = g_nextIsBuy ? "BUY" : "SELL";
      ObjectSetString(0, OBJ_TIMER, OBJPROP_TEXT,
         StringFormat("#%d  Next: %s in %ds", g_tradeCount + 1, dir, remaining));
      ObjectSetInteger(0, OBJ_TIMER, OBJPROP_COLOR,
         g_nextIsBuy ? COL_GREEN : COL_RED);
   }

   // ── Position info ──
   if(g_hasPos)
   {
      double pnl = GetPositionPnL();
      double lots = GetPositionLots();
      bool isBuy = IsPositionBuy();
      string dir = isBuy ? "LONG" : "SHORT";
      ObjectSetString(0, OBJ_POS_INFO, OBJPROP_TEXT,
         StringFormat("%.2f %s  $%+.2f", lots, dir, pnl));
      ObjectSetInteger(0, OBJ_POS_INFO, OBJPROP_COLOR,
         pnl >= 0 ? COL_GREEN : COL_RED);
   }
   else
   {
      double lot = 0;
      string gvName = "TP_Lot_" + _Symbol;
      if(InpUsePanelLot && GlobalVariableCheck(gvName))
         lot = GlobalVariableGet(gvName);

      if(lot <= 0)
      {
         double atrBuf[1];
         if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) == 1 && atrBuf[0] > 0)
         {
            double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double slDist  = atrBuf[0] * InpATRMult;
            if(tickSz > 0 && tickVal > 0 && slDist > 0)
               lot = InpRiskMoney / ((slDist / tickSz) * tickVal);
         }
      }

      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(lotStep > 0 && lot > 0)
         lot = MathFloor(lot / lotStep) * lotStep;
      lot = MathMax(minLot, MathMin(maxLot, lot));

      double margin = 0;
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(lot > 0)
         if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, price, margin))
            margin = 0;

      ObjectSetString(0, OBJ_POS_INFO, OBJPROP_TEXT,
         StringFormat("Lot %.2f | Margin $%.0f", lot, margin));
      ObjectSetInteger(0, OBJ_POS_INFO, OBJPROP_COLOR, COL_DIM);
   }

   ChartRedraw();
}

// ════════════════════════════════════════════════════════════════════
// ONTICK / ONTIMER
// ════════════════════════════════════════════════════════════════════
void OnTick()
{
   // Cache ATR
   double atr[1];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1 && atr[0] > 0)
      g_cachedATR = atr[0];

   UpdatePanel();

   if(!g_botEnabled) return;

   // Skip if already have a position
   g_hasPos = HasPosition();
   if(g_hasPos) return;
   if(g_cachedATR <= 0) return;

   // Check if interval has elapsed
   datetime now = TimeCurrent();
   if(g_lastTradeTime > 0 && (now - g_lastTradeTime) < InpIntervalSec) return;

   // ── Time to trade! ──
   g_lastTradeTime = now;
   Print(StringFormat("[TEST BOT] Auto-trade #%d: %s (interval=%ds)",
         g_tradeCount + 1, g_nextIsBuy ? "BUY" : "SELL", InpIntervalSec));
   OpenTrade(g_nextIsBuy, g_cachedATR);

   // Alternate direction for next trade
   if(InpAlternateDir)
      g_nextIsBuy = !g_nextIsBuy;
}

void OnTimer()
{
   UpdatePanel();
}

// ════════════════════════════════════════════════════════════════════
// CHART EVENTS (UI clicks)
// ════════════════════════════════════════════════════════════════════
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == OBJ_START)
   {
      ObjectSetInteger(0, OBJ_START, OBJPROP_STATE, false);
      g_botEnabled = !g_botEnabled;
      Print(StringFormat("[TEST BOT] %s", g_botEnabled ? "ENABLED" : "DISABLED"));
      UpdatePanel();
   }
   else if(sparam == OBJ_FORCE_BUY)
   {
      ObjectSetInteger(0, OBJ_FORCE_BUY, OBJPROP_STATE, false);
      if(HasPosition())
      {
         Print("[TEST BOT] Already have a position, cannot force BUY");
         return;
      }
      double atr[1];
      if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1 && atr[0] > 0)
      {
         Print("[TEST BOT] Force BUY triggered by user");
         OpenTrade(true, atr[0]);
         g_lastTradeTime = TimeCurrent();
         UpdatePanel();
      }
   }
   else if(sparam == OBJ_FORCE_SELL)
   {
      ObjectSetInteger(0, OBJ_FORCE_SELL, OBJPROP_STATE, false);
      if(HasPosition())
      {
         Print("[TEST BOT] Already have a position, cannot force SELL");
         return;
      }
      double atr[1];
      if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1 && atr[0] > 0)
      {
         Print("[TEST BOT] Force SELL triggered by user");
         OpenTrade(false, atr[0]);
         g_lastTradeTime = TimeCurrent();
         UpdatePanel();
      }
   }
}

// ════════════════════════════════════════════════════════════════════
// TRADE FUNCTIONS
// ════════════════════════════════════════════════════════════════════
void OpenTrade(bool isBuy, double atrValue)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double lot = 0;
   string lotSource = "";

   if(InpUsePanelLot)
   {
      string gvName = "TP_Lot_" + _Symbol;
      if(GlobalVariableCheck(gvName))
      {
         lot = GlobalVariableGet(gvName);
         lotSource = "Panel";
      }
      else
         Print("[TEST BOT] WARNING: Panel GV not found, using fallback risk calc");
   }

   if(lot <= 0)
   {
      double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double slDist  = atrValue * InpATRMult;
      if(tickSz > 0 && tickVal > 0 && slDist > 0)
         lot = InpRiskMoney / ((slDist / tickSz) * tickVal);
      lotSource = StringFormat("Risk$%.0f", InpRiskMoney);
   }

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0)
      lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));

   double price;
   ENUM_ORDER_TYPE orderType;

   if(isBuy)
   {
      orderType = ORDER_TYPE_BUY;
      price = ask;
   }
   else
   {
      orderType = ORDER_TYPE_SELL;
      price = bid;
   }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = orderType;
   req.price     = price;
   req.sl        = 0;  // Panel manages SL
   req.tp        = 0;  // Panel manages TP
   req.deviation = InpDeviation;
   req.magic     = InpMagic;
   req.comment   = "TestBot";

   if(OrderSend(req, res))
   {
      g_tradeCount++;
      Print(StringFormat("[TEST BOT] %s %.2f @ %s | Trade #%d | Lot=%s | No SL/TP (Panel manages)",
            isBuy ? "BUY" : "SELL", lot,
            DoubleToString(price, _Digits),
            g_tradeCount, lotSource));
   }
   else
   {
      Print(StringFormat("[TEST BOT] OrderSend FAILED: %d - %s",
            res.retcode, res.comment));
   }
}

// ════════════════════════════════════════════════════════════════════
// UTILITY
// ════════════════════════════════════════════════════════════════════
bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
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

double GetPositionPnL()
{
   double pnl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
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

double GetPositionLots()
{
   double lots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      lots += PositionGetDouble(POSITION_VOLUME);
   }
   return lots;
}

bool IsPositionBuy()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
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
//+------------------------------------------------------------------+
