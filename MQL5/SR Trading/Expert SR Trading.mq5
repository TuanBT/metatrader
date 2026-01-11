//+------------------------------------------------------------------+
//| S/R Trading EA - Focus on Support/Resistance                      |
//| Risk:Reward minimum 1:2                                          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Tuan"
#property link      "https://mql5.com"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== S/R Detection Settings ==="
input ENUM_TIMEFRAMES InpSRTimeframe = PERIOD_M5;   // S/R Timeframe
input int    InpSRLookback     = 100;     // S/R Lookback Bars
input int    InpSRMinTouches   = 2;       // Min touches for valid S/R
input int    InpSRZoneWidth    = 50;      // S/R Zone Width (points)
input int    InpMaxSRLevels    = 5;       // Max S/R levels to track

input group "=== Entry Confirmation ==="
input ENUM_TIMEFRAMES InpEntryTimeframe = PERIOD_M1; // Entry Timeframe
input int    InpConfirmBars    = 2;       // Confirmation bars in zone
input bool   InpNeedRejection  = true;    // Need rejection wick
input double InpMinWickRatio   = 0.5;     // Min wick/body ratio for rejection

input group "=== Trading Settings ==="
input double InpRiskPercent    = 1.0;     // Risk per trade (%)
input double InpMinRR          = 2.0;     // Minimum Risk:Reward
input int    InpSLBuffer       = 20;      // SL Buffer (points)
input int    InpMaxSpread      = 30;      // Max Spread (points)
input int    InpMagicNumber    = 123457;  // Magic Number
input int    InpSlippage       = 10;      // Slippage (points)
input int    InpMaxTradesPerDay = 3;      // Max trades per day

input group "=== Visual Settings ==="
input bool   InpShowSR         = true;    // Show S/R Zones
input bool   InpShowEntry      = true;    // Show Entry Lines
input color  InpResistColor    = clrCrimson;    // Resistance Color
input color  InpSupportColor   = clrDodgerBlue; // Support Color
input color  InpEntryColor     = clrWhite;      // Entry Line Color
input color  InpSLColor        = clrRed;        // SL Line Color
input color  InpTPColor        = clrLime;       // TP Line Color

//--- Global Variables
CTrade g_trade;
string g_objPrefix;

// S/R Levels structure
struct SRLevel
{
   double price;
   bool   isResistance;
   int    touches;
   datetime firstTouch;
   datetime lastTouch;
   bool   isActive;
};

SRLevel g_srLevels[];

// Trade tracking
int g_tradesToday = 0;
datetime g_lastTradeDate = 0;

// Zone reaction tracking
struct ZoneReaction
{
   int    srIndex;        // Index of S/R level
   int    barsInZone;     // Number of bars touching zone
   double entryPrice;     // Potential entry price
   double slPrice;        // Stop loss price
   bool   hasRejection;   // Has rejection candle
   datetime startTime;    // When reaction started
};

ZoneReaction g_currentReaction;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   g_objPrefix = "SREA_" + IntegerToString(InpMagicNumber) + "_";

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   ArrayResize(g_srLevels, 0);
   ResetReaction();

   // Initial S/R detection
   FindSRLevels();
   DrawAllSRZones();

   Print("S/R Trading EA initialized. Magic: ", InpMagicNumber);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteAllObjects();
   Print("S/R Trading EA removed");
}

//+------------------------------------------------------------------+
//| Delete all EA objects                                              |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; --i)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, g_objPrefix) == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| Reset zone reaction tracking                                       |
//+------------------------------------------------------------------+
void ResetReaction()
{
   g_currentReaction.srIndex = -1;
   g_currentReaction.barsInZone = 0;
   g_currentReaction.entryPrice = 0;
   g_currentReaction.slPrice = 0;
   g_currentReaction.hasRejection = false;
   g_currentReaction.startTime = 0;
}

//+------------------------------------------------------------------+
//| Find Support/Resistance Levels                                     |
//+------------------------------------------------------------------+
void FindSRLevels()
{
   ArrayResize(g_srLevels, 0);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpSRTimeframe, 0, InpSRLookback, rates);
   if(copied < 20) return;

   double zoneWidth = _Point * InpSRZoneWidth;

   // Find swing highs and lows
   for(int i = 3; i < copied - 3; i++)
   {
      // Swing High (Resistance)
      if(IsSwingHigh(rates, i, 3))
      {
         double level = rates[i].high;
         int touches = CountTouches(rates, copied, level, zoneWidth, true);

         if(touches >= InpSRMinTouches)
         {
            AddSRLevel(level, true, touches, rates[i].time);
         }
      }

      // Swing Low (Support)
      if(IsSwingLow(rates, i, 3))
      {
         double level = rates[i].low;
         int touches = CountTouches(rates, copied, level, zoneWidth, false);

         if(touches >= InpSRMinTouches)
         {
            AddSRLevel(level, false, touches, rates[i].time);
         }
      }
   }

   // Sort by touches (strongest first) and limit
   SortSRLevelsByStrength();

   Print("Found ", ArraySize(g_srLevels), " S/R levels");
}

//+------------------------------------------------------------------+
//| Check if bar is swing high                                         |
//+------------------------------------------------------------------+
bool IsSwingHigh(MqlRates &rates[], int index, int lookback)
{
   for(int i = 1; i <= lookback; i++)
   {
      if(rates[index].high <= rates[index - i].high) return false;
      if(rates[index].high <= rates[index + i].high) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is swing low                                          |
//+------------------------------------------------------------------+
bool IsSwingLow(MqlRates &rates[], int index, int lookback)
{
   for(int i = 1; i <= lookback; i++)
   {
      if(rates[index].low >= rates[index - i].low) return false;
      if(rates[index].low >= rates[index + i].low) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Count touches at a level                                           |
//+------------------------------------------------------------------+
int CountTouches(MqlRates &rates[], int count, double level, double tolerance, bool isResistance)
{
   int touches = 0;
   for(int i = 0; i < count; i++)
   {
      if(isResistance)
      {
         // Price came close to level from below
         if(rates[i].high >= level - tolerance && rates[i].high <= level + tolerance)
            touches++;
      }
      else
      {
         // Price came close to level from above
         if(rates[i].low >= level - tolerance && rates[i].low <= level + tolerance)
            touches++;
      }
   }
   return touches;
}

//+------------------------------------------------------------------+
//| Add S/R level if not duplicate                                     |
//+------------------------------------------------------------------+
void AddSRLevel(double price, bool isResistance, int touches, datetime touchTime)
{
   double zoneWidth = _Point * InpSRZoneWidth;

   // Check if level already exists
   for(int i = 0; i < ArraySize(g_srLevels); i++)
   {
      if(MathAbs(g_srLevels[i].price - price) <= zoneWidth)
      {
         // Update existing level if stronger
         if(touches > g_srLevels[i].touches)
         {
            g_srLevels[i].touches = touches;
            g_srLevels[i].lastTouch = touchTime;
         }
         return;
      }
   }

   // Add new level
   int size = ArraySize(g_srLevels);
   ArrayResize(g_srLevels, size + 1);
   g_srLevels[size].price = price;
   g_srLevels[size].isResistance = isResistance;
   g_srLevels[size].touches = touches;
   g_srLevels[size].firstTouch = touchTime;
   g_srLevels[size].lastTouch = touchTime;
   g_srLevels[size].isActive = true;
}

//+------------------------------------------------------------------+
//| Sort S/R levels by strength (touches) and limit count             |
//+------------------------------------------------------------------+
void SortSRLevelsByStrength()
{
   int size = ArraySize(g_srLevels);

   // Bubble sort by touches (descending)
   for(int i = 0; i < size - 1; i++)
   {
      for(int j = 0; j < size - i - 1; j++)
      {
         if(g_srLevels[j].touches < g_srLevels[j + 1].touches)
         {
            SRLevel temp = g_srLevels[j];
            g_srLevels[j] = g_srLevels[j + 1];
            g_srLevels[j + 1] = temp;
         }
      }
   }

   // Limit to max levels
   if(size > InpMaxSRLevels * 2)
      ArrayResize(g_srLevels, InpMaxSRLevels * 2);
}

//+------------------------------------------------------------------+
//| Draw all S/R zones                                                 |
//+------------------------------------------------------------------+
void DrawAllSRZones()
{
   if(!InpShowSR) return;

   // Delete old zones first
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, g_objPrefix + "SR_") == 0)
         ObjectDelete(0, name);
   }

   double zoneWidth = _Point * InpSRZoneWidth;
   datetime t1 = iTime(_Symbol, InpSRTimeframe, InpSRLookback);
   datetime t2 = TimeCurrent() + PeriodSeconds(PERIOD_D1);

   for(int i = 0; i < ArraySize(g_srLevels); i++)
   {
      if(!g_srLevels[i].isActive) continue;

      DrawSRZone(g_srLevels[i].price, zoneWidth, g_srLevels[i].isResistance, 
                 g_srLevels[i].touches, t1, t2, IntegerToString(i));
   }
}

//+------------------------------------------------------------------+
//| Draw single S/R zone                                               |
//+------------------------------------------------------------------+
void DrawSRZone(double level, double width, bool isResistance, int touches,
                datetime t1, datetime t2, string suffix)
{
   color clr = isResistance ? InpResistColor : InpSupportColor;

   // Draw zone rectangle
   string zoneName = g_objPrefix + "SR_ZONE_" + suffix;
   ObjectDelete(0, zoneName);
   ObjectCreate(0, zoneName, OBJ_RECTANGLE, 0, t1, level + width/2, t2, level - width/2);
   ObjectSetInteger(0, zoneName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, zoneName, OBJPROP_FILL, true);
   ObjectSetInteger(0, zoneName, OBJPROP_BACK, true);
   ObjectSetInteger(0, zoneName, OBJPROP_SELECTABLE, false);

   // Draw center line
   string lineName = g_objPrefix + "SR_LINE_" + suffix;
   ObjectDelete(0, lineName);
   ObjectCreate(0, lineName, OBJ_TREND, 0, t1, level, t2, level);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);

   // Add label with touches count
   string labelName = g_objPrefix + "SR_LBL_" + suffix;
   ObjectDelete(0, labelName);
   ObjectCreate(0, labelName, OBJ_TEXT, 0, t2, level);
   string typeStr = isResistance ? "R" : "S";
   ObjectSetString(0, labelName, OBJPROP_TEXT, typeStr + "(" + IntegerToString(touches) + "): " + 
                   DoubleToString(level, _Digits));
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
}

//+------------------------------------------------------------------+
//| Check if price is in S/R zone                                      |
//+------------------------------------------------------------------+
int FindSRZoneAtPrice(double price, bool &isResistance)
{
   double zoneWidth = _Point * InpSRZoneWidth;

   for(int i = 0; i < ArraySize(g_srLevels); i++)
   {
      if(!g_srLevels[i].isActive) continue;

      double zoneTop = g_srLevels[i].price + zoneWidth / 2;
      double zoneBottom = g_srLevels[i].price - zoneWidth / 2;

      if(price >= zoneBottom && price <= zoneTop)
      {
         isResistance = g_srLevels[i].isResistance;
         return i;
      }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Check for rejection candle pattern                                 |
//+------------------------------------------------------------------+
bool IsRejectionCandle(double open, double high, double low, double close, bool expectBullish)
{
   double body = MathAbs(close - open);
   double range = high - low;

   if(range <= 0) return false;

   if(expectBullish)
   {
      // Bullish rejection: long lower wick, small body at top
      double lowerWick = MathMin(open, close) - low;
      double upperWick = high - MathMax(open, close);

      if(body > 0 && lowerWick / body >= InpMinWickRatio && lowerWick > upperWick * 2)
         return true;
   }
   else
   {
      // Bearish rejection: long upper wick, small body at bottom
      double upperWick = high - MathMax(open, close);
      double lowerWick = MathMin(open, close) - low;

      if(body > 0 && upperWick / body >= InpMinWickRatio && upperWick > lowerWick * 2)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Draw Entry Lines                                                   |
//+------------------------------------------------------------------+
void DrawEntryLines(double entry, double sl, double tp, bool isBuy)
{
   if(!InpShowEntry) return;

   datetime t1 = TimeCurrent();
   datetime t2 = t1 + PeriodSeconds(PERIOD_H4);
   string suffix = IntegerToString((long)t1);

   // Entry line
   string entryName = g_objPrefix + "ENTRY_" + suffix;
   ObjectDelete(0, entryName);
   ObjectCreate(0, entryName, OBJ_TREND, 0, t1, entry, t2, entry);
   ObjectSetInteger(0, entryName, OBJPROP_COLOR, InpEntryColor);
   ObjectSetInteger(0, entryName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, entryName, OBJPROP_WIDTH, 2);

   // SL line
   string slName = g_objPrefix + "SL_" + suffix;
   ObjectDelete(0, slName);
   ObjectCreate(0, slName, OBJ_TREND, 0, t1, sl, t2, sl);
   ObjectSetInteger(0, slName, OBJPROP_COLOR, InpSLColor);
   ObjectSetInteger(0, slName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, slName, OBJPROP_WIDTH, 1);

   // TP line
   string tpName = g_objPrefix + "TP_" + suffix;
   ObjectDelete(0, tpName);
   ObjectCreate(0, tpName, OBJ_TREND, 0, t1, tp, t2, tp);
   ObjectSetInteger(0, tpName, OBJPROP_COLOR, InpTPColor);
   ObjectSetInteger(0, tpName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, tpName, OBJPROP_WIDTH, 1);

   // Labels
   ObjectCreate(0, g_objPrefix + "ENTRYLBL_" + suffix, OBJ_TEXT, 0, t2, entry);
   ObjectSetString(0, g_objPrefix + "ENTRYLBL_" + suffix, OBJPROP_TEXT, 
                   "Entry: " + DoubleToString(entry, _Digits));
   ObjectSetInteger(0, g_objPrefix + "ENTRYLBL_" + suffix, OBJPROP_COLOR, InpEntryColor);

   ObjectCreate(0, g_objPrefix + "SLLBL_" + suffix, OBJ_TEXT, 0, t2, sl);
   ObjectSetString(0, g_objPrefix + "SLLBL_" + suffix, OBJPROP_TEXT, 
                   "SL: " + DoubleToString(sl, _Digits));
   ObjectSetInteger(0, g_objPrefix + "SLLBL_" + suffix, OBJPROP_COLOR, InpSLColor);

   ObjectCreate(0, g_objPrefix + "TPLBL_" + suffix, OBJ_TEXT, 0, t2, tp);
   ObjectSetString(0, g_objPrefix + "TPLBL_" + suffix, OBJPROP_TEXT, 
                   "TP: " + DoubleToString(tp, _Digits));
   ObjectSetInteger(0, g_objPrefix + "TPLBL_" + suffix, OBJPROP_COLOR, InpTPColor);
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                   |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * InpRiskPercent / 100.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(tickSize == 0 || point == 0 || slPoints == 0) return 0.01;

   double valuePerPoint = tickValue / tickSize * point;
   double lotSize = riskAmount / (slPoints * valuePerPoint);

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

   return lotSize;
}

//+------------------------------------------------------------------+
//| Check if we have open positions                                    |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Find nearest opposite S/R for TP                                   |
//+------------------------------------------------------------------+
double FindTPTarget(double entryPrice, bool isBuy)
{
   double bestTP = 0;
   double minDist = DBL_MAX;

   for(int i = 0; i < ArraySize(g_srLevels); i++)
   {
      if(!g_srLevels[i].isActive) continue;

      double level = g_srLevels[i].price;

      if(isBuy)
      {
         // For buy, look for resistance above entry
         if(g_srLevels[i].isResistance && level > entryPrice)
         {
            double dist = level - entryPrice;
            if(dist < minDist)
            {
               minDist = dist;
               bestTP = level;
            }
         }
      }
      else
      {
         // For sell, look for support below entry
         if(!g_srLevels[i].isResistance && level < entryPrice)
         {
            double dist = entryPrice - level;
            if(dist < minDist)
            {
               minDist = dist;
               bestTP = level;
            }
         }
      }
   }

   return bestTP;
}

//+------------------------------------------------------------------+
//| Execute Buy Trade                                                  |
//+------------------------------------------------------------------+
bool ExecuteBuy(double entry, double sl, double tp, int srIndex)
{
   if(HasOpenPosition()) return false;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
   {
      Print("Spread too high: ", spread);
      return false;
   }

   double risk = entry - sl;
   double reward = tp - entry;

   if(risk <= 0)
   {
      Print("Invalid risk calculation");
      return false;
   }

   double rr = reward / risk;

   if(rr < InpMinRR)
   {
      Print("RR too low: ", DoubleToString(rr, 2), " < ", DoubleToString(InpMinRR, 2));
      return false;
   }

   double lotSize = CalculateLotSize(risk / _Point);

   DrawEntryLines(entry, sl, tp, true);

   if(g_trade.Buy(lotSize, _Symbol, entry, sl, tp, "SR Buy - RR:" + DoubleToString(rr, 2)))
   {
      Print("BUY at Support[", srIndex, "]: Lot=", lotSize, " Entry=", entry, 
            " SL=", sl, " TP=", tp, " RR=", DoubleToString(rr, 2));
      g_tradesToday++;
      return true;
   }
   else
   {
      Print("BUY failed: ", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Execute Sell Trade                                                 |
//+------------------------------------------------------------------+
bool ExecuteSell(double entry, double sl, double tp, int srIndex)
{
   if(HasOpenPosition()) return false;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
   {
      Print("Spread too high: ", spread);
      return false;
   }

   double risk = sl - entry;
   double reward = entry - tp;

   if(risk <= 0)
   {
      Print("Invalid risk calculation");
      return false;
   }

   double rr = reward / risk;

   if(rr < InpMinRR)
   {
      Print("RR too low: ", DoubleToString(rr, 2), " < ", DoubleToString(InpMinRR, 2));
      return false;
   }

   double lotSize = CalculateLotSize(risk / _Point);

   DrawEntryLines(entry, sl, tp, false);

   if(g_trade.Sell(lotSize, _Symbol, entry, sl, tp, "SR Sell - RR:" + DoubleToString(rr, 2)))
   {
      Print("SELL at Resistance[", srIndex, "]: Lot=", lotSize, " Entry=", entry, 
            " SL=", sl, " TP=", tp, " RR=", DoubleToString(rr, 2));
      g_tradesToday++;
      return true;
   }
   else
   {
      Print("SELL failed: ", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // Reset daily trade count
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today = StringToTime(IntegerToString(dt.year) + "." + 
                                  IntegerToString(dt.mon) + "." + 
                                  IntegerToString(dt.day));
   if(today != g_lastTradeDate)
   {
      g_tradesToday = 0;
      g_lastTradeDate = today;
   }

   // Check max trades
   if(g_tradesToday >= InpMaxTradesPerDay) return;
   if(HasOpenPosition()) return;

   // Update S/R levels periodically (every 4 hours)
   static datetime lastSRUpdate = 0;
   if(TimeCurrent() - lastSRUpdate > PeriodSeconds(PERIOD_H4))
   {
      FindSRLevels();
      DrawAllSRZones();
      lastSRUpdate = TimeCurrent();
   }

   // Get entry timeframe data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpEntryTimeframe, 0, 10, rates);
   if(copied < 5) return;

   // Current price
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double zoneWidth = _Point * InpSRZoneWidth;

   // Check if price is at any S/R zone
   bool isResistance = false;
   int srIndex = FindSRZoneAtPrice(currentPrice, isResistance);

   if(srIndex < 0)
   {
      // Price not in any zone, reset reaction
      if(g_currentReaction.srIndex >= 0)
      {
         ResetReaction();
      }
      return;
   }

   // Price is in a zone
   double srLevel = g_srLevels[srIndex].price;

   // New zone reaction?
   if(g_currentReaction.srIndex != srIndex)
   {
      ResetReaction();
      g_currentReaction.srIndex = srIndex;
      g_currentReaction.startTime = TimeCurrent();
   }

   // Count bars in zone
   g_currentReaction.barsInZone++;

   // Check for rejection candle
   bool expectBullish = !isResistance;  // At support, expect bullish rejection

   if(InpNeedRejection)
   {
      if(IsRejectionCandle(rates[1].open, rates[1].high, rates[1].low, rates[1].close, expectBullish))
      {
         g_currentReaction.hasRejection = true;
         Print("Rejection candle detected at ", (isResistance ? "Resistance" : "Support"), 
               " level: ", DoubleToString(srLevel, _Digits));
      }
   }
   else
   {
      g_currentReaction.hasRejection = true;  // Skip rejection requirement
   }

   // Entry conditions
   bool canEnter = (g_currentReaction.barsInZone >= InpConfirmBars) && 
                   g_currentReaction.hasRejection;

   if(!canEnter) return;

   // Prepare trade
   double entry, sl, tp;
   double buffer = _Point * InpSLBuffer;

   if(isResistance)
   {
      // SELL at resistance
      entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = srLevel + zoneWidth / 2 + buffer;  // SL above resistance zone

      // Find TP at next support
      tp = FindTPTarget(entry, false);
      if(tp <= 0)
      {
         // No support found, use RR-based TP
         double risk = sl - entry;
         tp = entry - (risk * InpMinRR);
      }

      ExecuteSell(entry, sl, tp, srIndex);
   }
   else
   {
      // BUY at support
      entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = srLevel - zoneWidth / 2 - buffer;  // SL below support zone

      // Find TP at next resistance
      tp = FindTPTarget(entry, true);
      if(tp <= 0)
      {
         // No resistance found, use RR-based TP
         double risk = entry - sl;
         tp = entry + (risk * InpMinRR);
      }

      ExecuteBuy(entry, sl, tp, srIndex);
   }

   // Reset reaction after trade attempt
   ResetReaction();
}

//+------------------------------------------------------------------+
//| ChartEvent function                                                |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // Manual refresh S/R on keyboard 'R'
   if(id == CHARTEVENT_KEYDOWN && lparam == 'R')
   {
      FindSRLevels();
      DrawAllSRZones();
      Print("S/R levels refreshed manually");
   }
}
//+------------------------------------------------------------------+
 