//+------------------------------------------------------------------+
//| News Straddle Strategy.mqh — News Straddle Bot v1.01              |
//| Straddle pending orders around high-impact news events             |
//+------------------------------------------------------------------+
#ifndef NEWS_STRADDLE_STRATEGY_MQH
#define NEWS_STRADDLE_STRATEGY_MQH

// ════════════════════════════════════════════════════════════════════
// INPUTS (appear in Panel's settings dialog)
// ════════════════════════════════════════════════════════════════════
input group           "══ News Straddle Bot ══"
input int             InpNS_MinsBefore   = 3;     // News Straddle: Place pendings N mins before event
input int             InpNS_MinsExpire   = 10;    // News Straddle: Cancel pendings N mins after event
input double          InpNS_OffsetPips   = 15.0;  // News Straddle: Offset from price (pips)
input double          InpNS_SLPips       = 30.0;  // News Straddle: Stop Loss (pips, 0 = Panel manages)
input double          InpNS_TPPips       = 45.0;  // News Straddle: Take Profit (pips, 0 = Panel manages)
input bool            InpNS_OnlyHigh     = true;  // News Straddle: Only HIGH importance events
input int             InpNS_PauseBars    = 60;    // News Straddle: Auto-resume after N bars (0 = manual)

// ════════════════════════════════════════════════════════════════════
// OBJECT NAMES (unique prefix)
// ════════════════════════════════════════════════════════════════════
#define NS_PREFIX     "NSBot_"
#define NS_OBJ_BG     NS_PREFIX "BG"
#define NS_OBJ_TITLE  NS_PREFIX "Title"
#define NS_OBJ_STATUS NS_PREFIX "Status"

#define NS_OBJ_IL1    NS_PREFIX "IL1"
#define NS_OBJ_IL2    NS_PREFIX "IL2"
#define NS_OBJ_IL3    NS_PREFIX "IL3"
#define NS_OBJ_IL4    NS_PREFIX "IL4"
#define NS_OBJ_IL5    NS_PREFIX "IL5"

#define NS_OBJ_POS    NS_PREFIX "PosInfo"
#define NS_OBJ_NEXT   NS_PREFIX "NextEvent"
#define NS_OBJ_COUNT  NS_PREFIX "Countdown"
#define NS_OBJ_PEND   NS_PREFIX "PendStatus"

// ════════════════════════════════════════════════════════════════════
// GLOBALS (all ns_ prefixed)
// ════════════════════════════════════════════════════════════════════
bool     ns_enabled       = false;  // managed by Panel toggle
bool     ns_paused        = false;
datetime ns_pauseTime     = 0;

// Next event tracking
string   ns_nextEventName = "";
datetime ns_nextEventTime = 0;
string   ns_nextEventCcy  = "";

// Pending order management
ulong    ns_buyStopTicket  = 0;
ulong    ns_sellStopTicket = 0;
bool     ns_pendingPlaced  = false;
bool     ns_triggered      = false;   // one side triggered
datetime ns_placedTime     = 0;

// Panel position
int  ns_panelX = 0;
int  ns_panelY = 0;
int  ns_panelW = 224;

// Calendar scan cache
datetime ns_lastScan      = 0;

// ════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════

// Get symbol's base and quote currencies
string NS_GetBaseCurrency()  { return SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE); }
string NS_GetQuoteCurrency() { return SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT); }

// Pips to price distance
double NS_PipsToPrice(double pips)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   // For 5-digit (forex) or 3-digit (JPY), 1 pip = 10 points
   // For 2-digit, 1 pip = 1 point
   if(digits == 5 || digits == 3)
      return pips * point * 10.0;
   else
      return pips * point;
}

// ════════════════════════════════════════════════════════════════════
// CALENDAR — Scan for next HIGH impact event
// ════════════════════════════════════════════════════════════════════
void NS_ScanNextEvent()
{
   ns_nextEventName = "";
   ns_nextEventTime = 0;
   ns_nextEventCcy  = "";

   string baseCcy  = NS_GetBaseCurrency();
   string quoteCcy = NS_GetQuoteCurrency();

   // Scan next 24 hours
   datetime from = TimeCurrent();
   datetime to   = from + 86400;  // 24h ahead

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, from, to);
   if(total <= 0) return;

   datetime earliest = to + 1;

   for(int i = 0; i < total; i++)
   {
      // Get event details
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event)) continue;

      // Get country for currency
      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country)) continue;

      // Filter by importance
      if(InpNS_OnlyHigh && event.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;

      // Also allow MEDIUM if not filtering
      if(!InpNS_OnlyHigh && event.importance == CALENDAR_IMPORTANCE_NONE)
         continue;

      // Filter by currency — must match symbol's base or quote
      string eventCcy = country.currency;
      if(eventCcy != baseCcy && eventCcy != quoteCcy)
         continue;

      // Find the earliest upcoming event
      if(values[i].time < earliest)
      {
         earliest = values[i].time;
         ns_nextEventName = event.name;
         ns_nextEventTime = values[i].time;
         ns_nextEventCcy  = eventCcy;
      }
   }
}

// ════════════════════════════════════════════════════════════════════
// PENDING ORDER MANAGEMENT
// ════════════════════════════════════════════════════════════════════
bool NS_PlacePendingOrders()
{
   if(ns_pendingPlaced) return true;
   if(HasOwnPosition()) return false;  // already in a trade

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double offset = NS_PipsToPrice(InpNS_OffsetPips);
   double slDist = (InpNS_SLPips > 0) ? NS_PipsToPrice(InpNS_SLPips) : 0;
   double tpDist = (InpNS_TPPips > 0) ? NS_PipsToPrice(InpNS_TPPips) : 0;

   double lot = (g_panelLot > 0) ? g_panelLot : SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   // Normalize lot
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < lotMin) lot = lotMin;
   if(lot > lotMax) lot = lotMax;

   // Buy Stop
   double buyPrice = ask + offset;
   double buySL = (slDist > 0) ? buyPrice - slDist : 0;
   double buyTP = (tpDist > 0) ? buyPrice + tpDist : 0;

   // Sell Stop
   double sellPrice = bid - offset;
   double sellSL = (slDist > 0) ? sellPrice + slDist : 0;
   double sellTP = (tpDist > 0) ? sellPrice - tpDist : 0;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   buyPrice  = NormalizeDouble(buyPrice, digits);
   buySL     = NormalizeDouble(buySL, digits);
   buyTP     = NormalizeDouble(buyTP, digits);
   sellPrice = NormalizeDouble(sellPrice, digits);
   sellSL    = NormalizeDouble(sellSL, digits);
   sellTP    = NormalizeDouble(sellTP, digits);

   MqlTradeRequest req;
   MqlTradeResult  res;

   // ── Buy Stop ──
   ZeroMemory(req);
   ZeroMemory(res);
   req.action    = TRADE_ACTION_PENDING;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = ORDER_TYPE_BUY_STOP;
   req.price     = buyPrice;
   req.sl        = buySL;
   req.tp        = buyTP;
   req.deviation = InpDeviation;
   req.magic     = InpMagic;
   req.comment   = "NS_BuyStop";

   if(!OrderSend(req, res) || res.retcode != TRADE_RETCODE_DONE)
   {
      Print(StringFormat("[NEWS STRADDLE] Buy Stop FAILED: %d - %s", res.retcode, res.comment));
      return false;
   }
   ns_buyStopTicket = res.order;
   Print(StringFormat("[NEWS STRADDLE] Buy Stop placed @ %.5f | Lot %.2f | SL %.5f | TP %.5f",
         buyPrice, lot, buySL, buyTP));

   // ── Sell Stop ──
   ZeroMemory(req);
   ZeroMemory(res);
   req.action    = TRADE_ACTION_PENDING;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = ORDER_TYPE_SELL_STOP;
   req.price     = sellPrice;
   req.sl        = sellSL;
   req.tp        = sellTP;
   req.deviation = InpDeviation;
   req.magic     = InpMagic;
   req.comment   = "NS_SellStop";

   if(!OrderSend(req, res) || res.retcode != TRADE_RETCODE_DONE)
   {
      Print(StringFormat("[NEWS STRADDLE] Sell Stop FAILED: %d - %s", res.retcode, res.comment));
      // Cancel the buy stop too
      NS_CancelOrder(ns_buyStopTicket);
      ns_buyStopTicket = 0;
      return false;
   }
   ns_sellStopTicket = res.order;
   Print(StringFormat("[NEWS STRADDLE] Sell Stop placed @ %.5f | Lot %.2f | SL %.5f | TP %.5f",
         sellPrice, lot, sellSL, sellTP));

   ns_pendingPlaced = true;
   ns_triggered = false;
   ns_placedTime = TimeCurrent();
   return true;
}

void NS_CancelOrder(ulong ticket)
{
   if(ticket == 0) return;
   if(!OrderSelect(ticket)) return;  // order no longer exists

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_REMOVE;
   req.order  = ticket;

   if(OrderSend(req, res))
      Print(StringFormat("[NEWS STRADDLE] Cancelled order #%d", ticket));
   else
      Print(StringFormat("[NEWS STRADDLE] Cancel order #%d FAILED: %d", ticket, res.retcode));
}

void NS_CancelAllPendings()
{
   if(ns_buyStopTicket > 0)
   {
      NS_CancelOrder(ns_buyStopTicket);
      ns_buyStopTicket = 0;
   }
   if(ns_sellStopTicket > 0)
   {
      NS_CancelOrder(ns_sellStopTicket);
      ns_sellStopTicket = 0;
   }
   ns_pendingPlaced = false;
   ns_triggered = false;
}

// Check if one pending was triggered (now a position) → cancel the other
void NS_CheckTriggered()
{
   if(!ns_pendingPlaced || ns_triggered) return;

   bool buyExists  = (ns_buyStopTicket > 0 && OrderSelect(ns_buyStopTicket));
   bool sellExists = (ns_sellStopTicket > 0 && OrderSelect(ns_sellStopTicket));

   if(!buyExists && !sellExists)
   {
      // Both gone — maybe both triggered or cancelled externally
      ns_pendingPlaced = false;
      ns_triggered = true;
      return;
   }

   if(!buyExists && sellExists)
   {
      // Buy side triggered → cancel sell
      Print("[NEWS STRADDLE] Buy Stop triggered → cancelling Sell Stop");
      NS_CancelOrder(ns_sellStopTicket);
      ns_sellStopTicket = 0;
      ns_triggered = true;
   }
   else if(buyExists && !sellExists)
   {
      // Sell side triggered → cancel buy
      Print("[NEWS STRADDLE] Sell Stop triggered → cancelling Buy Stop");
      NS_CancelOrder(ns_buyStopTicket);
      ns_buyStopTicket = 0;
      ns_triggered = true;
   }
}

// ════════════════════════════════════════════════════════════════════
// INIT / DEINIT
// ════════════════════════════════════════════════════════════════════
bool NS_Init()
{
   ns_lastScan = 0;
   NS_ScanNextEvent();
   Print(StringFormat("[NEWS STRADDLE] Initialized | %s | Offset=%.1f pips | Before=%d min | Expire=%d min",
         _Symbol, InpNS_OffsetPips, InpNS_MinsBefore, InpNS_MinsExpire));
   return true;
}

void NS_Deinit()
{
   NS_DestroyPanel();
   // Note: We do NOT cancel pending orders on deinit — they stay
   Print("[NEWS STRADDLE] Deinitialized");
}

// ════════════════════════════════════════════════════════════════════
// TICK LOGIC
// ════════════════════════════════════════════════════════════════════
void NS_Tick()
{
   if(!ns_enabled) return;

   // Auto-resume check
   if(ns_paused && InpNS_PauseBars > 0 && ns_pauseTime > 0)
   {
      int barsSincePause = iBarShift(_Symbol, _Period, ns_pauseTime);
      if(barsSincePause >= InpNS_PauseBars)
      {
         ns_paused = false;
         ns_pauseTime = 0;
         Print(StringFormat("[NEWS STRADDLE] Auto-resumed after %d bars pause", barsSincePause));
      }
   }

   if(ns_paused) return;

   // Check if pending was triggered
   if(ns_pendingPlaced)
   {
      NS_CheckTriggered();

      // Check expiry: if N mins after event and still pending → cancel
      if(ns_pendingPlaced && !ns_triggered && ns_nextEventTime > 0)
      {
         datetime expiry = ns_nextEventTime + InpNS_MinsExpire * 60;
         if(TimeCurrent() >= expiry)
         {
            Print("[NEWS STRADDLE] Pendings expired — cancelling all");
            NS_CancelAllPendings();
         }
      }
      return;  // don't place new orders while managing existing
   }

   // No pending orders — check if it's time to place
   if(ns_nextEventTime > 0 && !ns_triggered)
   {
      datetime placeTime = ns_nextEventTime - InpNS_MinsBefore * 60;
      datetime now = TimeCurrent();

      if(now >= placeTime && now < ns_nextEventTime + InpNS_MinsExpire * 60)
      {
         // Time to place straddle
         if(NS_PlacePendingOrders())
         {
            Print(StringFormat("[NEWS STRADDLE] Straddle placed for event: %s (%s) @ %s",
                  ns_nextEventName, ns_nextEventCcy,
                  TimeToString(ns_nextEventTime, TIME_DATE | TIME_MINUTES)));
         }
      }
   }
}

// ════════════════════════════════════════════════════════════════════
// TIMER — Update display + rescan calendar
// ════════════════════════════════════════════════════════════════════
void NS_Timer()
{
   if(!ns_enabled) return;

   // Rescan calendar every 60 seconds
   datetime now = TimeCurrent();
   if(now - ns_lastScan >= 60)
   {
      // If previous event has passed and there's no pending → scan next
      if(!ns_pendingPlaced && (ns_nextEventTime == 0 || now > ns_nextEventTime + InpNS_MinsExpire * 60))
      {
         ns_triggered = false;
         NS_ScanNextEvent();
      }
      ns_lastScan = now;
   }

   if(g_activeBot == 2) NS_UpdatePanel();  // Only update visible panel
}

// ════════════════════════════════════════════════════════════════════
// PAUSE
// ════════════════════════════════════════════════════════════════════
void NS_SetPaused(datetime pauseTimestamp)
{
   ns_paused = true;
   ns_pauseTime = pauseTimestamp;
   Print(StringFormat("[NEWS STRADDLE] Paused | Resume after %d bars", InpNS_PauseBars));
}

void NS_ClearPause()
{
   ns_paused = false;
   ns_pauseTime = 0;
   Print("[NEWS STRADDLE] Pause cleared");
}

// ════════════════════════════════════════════════════════════════════
// PANEL UI
// ════════════════════════════════════════════════════════════════════
void NS_CreatePanel(int x, int y, int w)
{
   ns_panelX = x;
   ns_panelY = y;
   ns_panelW = w;

   int pad = 6;
   int row = y + 4;  // inside bot_bg

   // Title
   MakeLabel(NS_OBJ_TITLE, x + pad, row + 4, "News Straddle Bot v1.01",
             C'170,180,215', 9, "Segoe UI Semibold");
   row += 22;

   // Status
   MakeLabel(NS_OBJ_STATUS, x + pad, row, "Idle", C'120,125,145', 8, "Consolas");
   row += 18;

   // Next event
   MakeLabel(NS_OBJ_NEXT, x + pad, row, "No upcoming events", C'120,125,145', 8, "Consolas");
   row += 16;

   // Countdown
   MakeLabel(NS_OBJ_COUNT, x + pad, row, "", C'120,125,145', 8, "Consolas");
   row += 16;

   // Pending status
   MakeLabel(NS_OBJ_PEND, x + pad, row, "", C'120,125,145', 8, "Consolas");
   row += 18;

   // Position info
   MakeLabel(NS_OBJ_POS, x + pad, row, "No position", C'120,125,145', 8, "Consolas");
   row += 18;

   // Info lines (always visible)
   MakeLabel(NS_OBJ_IL1, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 14;
   MakeLabel(NS_OBJ_IL2, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 14;
   MakeLabel(NS_OBJ_IL3, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 14;
   MakeLabel(NS_OBJ_IL4, x + pad, row, "", C'120,125,145', 8, "Consolas"); row += 14;
   MakeLabel(NS_OBJ_IL5, x + pad, row, "", C'120,125,145', 7, "Consolas");

   NS_UpdatePanel();
}

void NS_DestroyPanel()
{
   ObjectsDeleteAll(0, NS_PREFIX);
}

void NS_UpdatePanel()
{
   if(g_activeBot != 2) return;   // skip if not viewing

   datetime now = TimeCurrent();

   // ── Status ──
   if(!ns_enabled)
   {
      ObjectSetString(0, NS_OBJ_STATUS, OBJPROP_TEXT, "Stopped");
      ObjectSetInteger(0, NS_OBJ_STATUS, OBJPROP_COLOR, C'120,125,145');
   }
   else if(ns_paused)
   {
      if(InpNS_PauseBars > 0 && ns_pauseTime > 0)
      {
         int barsSincePause = iBarShift(_Symbol, _Period, ns_pauseTime);
         int barsLeft = MathMax(0, InpNS_PauseBars - barsSincePause);
         int secPerBar = PeriodSeconds(_Period);
         int minsLeft = (barsLeft * secPerBar) / 60;
         if(minsLeft >= 60)
            ObjectSetString(0, NS_OBJ_STATUS, OBJPROP_TEXT,
               StringFormat("PAUSED | ~%dh%dm", minsLeft / 60, minsLeft % 60));
         else
            ObjectSetString(0, NS_OBJ_STATUS, OBJPROP_TEXT,
               StringFormat("PAUSED | ~%dm", minsLeft));
      }
      else
         ObjectSetString(0, NS_OBJ_STATUS, OBJPROP_TEXT, "PAUSED (Large SL)");
      ObjectSetInteger(0, NS_OBJ_STATUS, OBJPROP_COLOR, C'220,80,80');
   }
   else if(ns_triggered)
   {
      ObjectSetString(0, NS_OBJ_STATUS, OBJPROP_TEXT, "Triggered");
      ObjectSetInteger(0, NS_OBJ_STATUS, OBJPROP_COLOR, C'0,180,100');
   }
   else if(ns_pendingPlaced)
   {
      ObjectSetString(0, NS_OBJ_STATUS, OBJPROP_TEXT, "Pendings Active");
      ObjectSetInteger(0, NS_OBJ_STATUS, OBJPROP_COLOR, C'255,180,50');
   }
   else
   {
      ObjectSetString(0, NS_OBJ_STATUS, OBJPROP_TEXT, "Watching");
      ObjectSetInteger(0, NS_OBJ_STATUS, OBJPROP_COLOR, C'0,180,100');
   }

   // ── Next event ──
   if(ns_nextEventTime > 0)
   {
      string eventStr = StringFormat("%s [%s]", ns_nextEventName, ns_nextEventCcy);
      // Truncate if too long
      if(StringLen(eventStr) > 30)
         eventStr = StringSubstr(eventStr, 0, 27) + "...";
      ObjectSetString(0, NS_OBJ_NEXT, OBJPROP_TEXT, eventStr);
      ObjectSetInteger(0, NS_OBJ_NEXT, OBJPROP_COLOR, C'220,225,240');

      // ── Countdown ──
      long secsLeft = (long)(ns_nextEventTime - now);
      if(secsLeft > 0)
      {
         int hrs = (int)(secsLeft / 3600);
         int mins = (int)((secsLeft % 3600) / 60);
         int secs = (int)(secsLeft % 60);
         string countStr;
         if(hrs > 0)
            countStr = StringFormat("In %dh %02dm %02ds @ %s", hrs, mins, secs,
                       TimeToString(ns_nextEventTime, TIME_MINUTES));
         else
            countStr = StringFormat("In %dm %02ds @ %s", mins, secs,
                       TimeToString(ns_nextEventTime, TIME_MINUTES));

         ObjectSetString(0, NS_OBJ_COUNT, OBJPROP_TEXT, countStr);

         // Color: red if within MinsBefore
         if(secsLeft <= InpNS_MinsBefore * 60)
            ObjectSetInteger(0, NS_OBJ_COUNT, OBJPROP_COLOR, C'255,180,50');
         else
            ObjectSetInteger(0, NS_OBJ_COUNT, OBJPROP_COLOR, C'120,125,145');
      }
      else
      {
         long secsPast = -secsLeft;
         int mins = (int)(secsPast / 60);
         ObjectSetString(0, NS_OBJ_COUNT, OBJPROP_TEXT,
            StringFormat("Event was %dm ago", mins));
         ObjectSetInteger(0, NS_OBJ_COUNT, OBJPROP_COLOR, C'120,125,145');
      }
   }
   else
   {
      ObjectSetString(0, NS_OBJ_NEXT, OBJPROP_TEXT, "No upcoming events");
      ObjectSetInteger(0, NS_OBJ_NEXT, OBJPROP_COLOR, C'120,125,145');
      ObjectSetString(0, NS_OBJ_COUNT, OBJPROP_TEXT, "");
   }

   // ── Pending orders status ──
   if(ns_pendingPlaced && !ns_triggered)
   {
      ObjectSetString(0, NS_OBJ_PEND, OBJPROP_TEXT,
         StringFormat("Buy Stop #%d | Sell Stop #%d", ns_buyStopTicket, ns_sellStopTicket));
      ObjectSetInteger(0, NS_OBJ_PEND, OBJPROP_COLOR, C'255,180,50');
   }
   else if(ns_triggered)
   {
      ObjectSetString(0, NS_OBJ_PEND, OBJPROP_TEXT, "One side triggered");
      ObjectSetInteger(0, NS_OBJ_PEND, OBJPROP_COLOR, C'0,180,100');
   }
   else
   {
      ObjectSetString(0, NS_OBJ_PEND, OBJPROP_TEXT, "No pending orders");
      ObjectSetInteger(0, NS_OBJ_PEND, OBJPROP_COLOR, C'120,125,145');
   }

   // ── Position info ──
   if(g_hasPos)
   {
      double pnl = GetPositionPnL();
      double lots = GetTotalLots();
      color pnlClr = (pnl >= 0) ? C'0,180,100' : C'220,80,80';
      ObjectSetString(0, NS_OBJ_POS, OBJPROP_TEXT,
         StringFormat("%s %.2f | %s$%.1f", g_isBuy ? "BUY" : "SELL", lots,
                      pnl >= 0 ? "+" : "", pnl));
      ObjectSetInteger(0, NS_OBJ_POS, OBJPROP_COLOR, pnlClr);
   }
   else
   {
      ObjectSetString(0, NS_OBJ_POS, OBJPROP_TEXT,
         StringFormat("Lot %.2f", g_panelLot));
      ObjectSetInteger(0, NS_OBJ_POS, OBJPROP_COLOR, C'120,125,145');
   }

   // ── Info lines ──
   ObjectSetString(0, NS_OBJ_IL1, OBJPROP_TEXT,
      StringFormat("Offset: %.1f pips from price", InpNS_OffsetPips));
   ObjectSetString(0, NS_OBJ_IL2, OBJPROP_TEXT,
      StringFormat("Place %d min before event", InpNS_MinsBefore));
   ObjectSetString(0, NS_OBJ_IL3, OBJPROP_TEXT,
      StringFormat("Expire %d min after event", InpNS_MinsExpire));
   ObjectSetString(0, NS_OBJ_IL4, OBJPROP_TEXT,
      StringFormat("SL: %s | TP: %s",
                   InpNS_SLPips > 0 ? StringFormat("%.0f pips", InpNS_SLPips) : "Panel",
                   InpNS_TPPips > 0 ? StringFormat("%.0f pips", InpNS_TPPips) : "Panel"));
   ObjectSetString(0, NS_OBJ_IL5, OBJPROP_TEXT,
      StringFormat("Filter: %s only", InpNS_OnlyHigh ? "HIGH" : "HIGH+MED"));
}

// ════════════════════════════════════════════════════════════════════
// VISIBILITY
// ════════════════════════════════════════════════════════════════════
void NS_SetVisible(bool visible)
{
   long flag = visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, NS_PREFIX) == 0)
         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, flag);
   }
}

#endif // NEWS_STRADDLE_STRATEGY_MQH
