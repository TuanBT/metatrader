//+------------------------------------------------------------------+
//| Export Data.mq5                                                  |
//| Export M5 + H1 bars to CSV for backtest (multi-year)             |
//| v4.0 — Uses DownloadHistory to force MT5 server download         |
//+------------------------------------------------------------------+
#property copyright "MST"
#property link      ""
#property version   "4.00"
#property script_show_inputs

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input int InpYears = 5;  // Years of data to export (0 = all available)

//+------------------------------------------------------------------+
//| Symbols to export                                                 |
//+------------------------------------------------------------------+
string g_symbols[] = {
   "XAUUSD",    "XAUUSDm",
   "BTCUSD",    "BTCUSDm",
   "ETHUSD",    "ETHUSDm",
   "USOIL",     "USOILm",    "USOILUSD",
   "EURUSD",    "EURUSDm",
   "USDJPY",    "USDJPYm",
};

//+------------------------------------------------------------------+
//| Download history from server (like Strategy Tester does)          |
//| Keeps requesting data until no more new bars arrive               |
//+------------------------------------------------------------------+
bool DownloadHistory(const string symbol, ENUM_TIMEFRAMES tf, datetime dtStart)
{
   Print("  📥 Downloading ", symbol, " ", EnumToString(tf), " from ", TimeToString(dtStart, TIME_DATE));

   // Step 1: Request the oldest data point to trigger server sync
   long firstBar;
   MqlRates tempRates[];

   // Use SeriesInfoInteger to check server's first date
   if(SeriesInfoInteger(symbol, tf, SERIES_FIRSTDATE, firstBar))
   {
      Print("    Terminal first date: ", TimeToString((datetime)firstBar, TIME_DATE));
   }
   if(SeriesInfoInteger(symbol, tf, SERIES_SERVER_FIRSTDATE, firstBar))
   {
      Print("    Server first date:   ", TimeToString((datetime)firstBar, TIME_DATE));
   }

   // Step 2: Request data in yearly chunks from oldest to newest
   // This is similar to how the Strategy Tester forces download
   datetime current = dtStart;
   long sixMonths = 180L * 24 * 3600;
   int maxAttempts = 30;
   int attempt = 0;

   while(current < TimeCurrent() && attempt < maxAttempts)
   {
      // Request 10 bars starting from 'current' date
      int got = CopyRates(symbol, tf, current, 10, tempRates);
      if(got > 0)
      {
         // Jump forward by 6 months
         current = current + (datetime)sixMonths;
      }
      else
      {
         // No data at this point, try jumping forward
         current = current + (datetime)sixMonths;
      }
      attempt++;
      Sleep(500);
   }

   // Final wait for MT5 to finish syncing
   Sleep(3000);

   // Check how many bars we have now
   long totalBars;
   SeriesInfoInteger(symbol, tf, SERIES_BARS_COUNT, totalBars);
   Print("    Total bars after download: ", totalBars);

   return (totalBars > 0);
}

//+------------------------------------------------------------------+
//| Export one symbol + timeframe                                      |
//+------------------------------------------------------------------+
bool ExportBars(const string symbol, ENUM_TIMEFRAMES tf, int years)
{
   string tfName;
   switch(tf)
   {
      case PERIOD_M5:  tfName = "M5";  break;
      case PERIOD_H1:  tfName = "H1";  break;
      default:         tfName = EnumToString(tf); break;
   }

   if(!SymbolSelect(symbol, true))
      return false;

   Sleep(300);

   datetime dtEnd   = TimeCurrent();
   datetime dtStart;
   if(years <= 0)
   {
      // Get the earliest available date from server
      long serverFirst = 0;
      SeriesInfoInteger(symbol, tf, SERIES_SERVER_FIRSTDATE, serverFirst);
      if(serverFirst > 0)
         dtStart = (datetime)serverFirst;
      else
         dtStart = dtEnd - (datetime)(10L * 365 * 24 * 3600);  // fallback 10 years
   }
   else
   {
      dtStart = dtEnd - (datetime)((long)years * 365 * 24 * 3600);
   }

   // Force download history
   DownloadHistory(symbol, tf, dtStart);

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   // ── Export using index-based CopyRates ──
   // This approach copies from bar[N] to bar[0] (newest)
   // Not limited by the 100K single-call restriction
   string filename = symbol + "_" + tfName + ".csv";
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("❌ Cannot create file: ", filename, " error=", GetLastError());
      return false;
   }
   FileWrite(handle, "datetime", "Open", "High", "Low", "Close", "Volume", "symbol");

   // Find out how many bars exist from dtStart
   int totalAvailable = Bars(symbol, tf, dtStart, dtEnd);
   Print("  📊 ", symbol, " ", tfName, ": ", totalAvailable, " bars available (", TimeToString(dtStart, TIME_DATE), " → now)");

   if(totalAvailable <= 0)
   {
      FileClose(handle);
      return false;
   }

   // Copy in batches of 50,000 using start_pos + count
   // start_pos = index from current bar (0 = newest)
   int BATCH = 50000;
   int totalWritten = 0;
   datetime firstTime = 0;
   datetime lastTime = 0;

   // We need to find the starting index
   // Bars(symbol, tf) = total bars, bars are indexed 0=newest
   int totalBarsAll = Bars(symbol, tf);
   int startIndex = totalBarsAll - totalAvailable;  // oldest bar in our range
   if(startIndex < 0) startIndex = 0;

   // Copy from oldest to newest in batches
   int remaining = totalAvailable;
   int currentPos = totalAvailable - 1;  // Start from oldest (highest index from 0)

   // Actually easier: copy using time-based approach but in smaller chunks
   // 6 months per chunk = ~37K M5 bars, well under any limit
   long chunkDays = 90L;  // 3 months = ~25K M5 bars
   long chunkSec  = chunkDays * 24 * 3600;
   datetime batchStart = dtStart;

   while(batchStart < dtEnd)
   {
      datetime batchEnd = batchStart + (datetime)chunkSec;
      if(batchEnd > dtEnd) batchEnd = dtEnd;

      MqlRates rates[];
      ArraySetAsSeries(rates, false);
      int copied = CopyRates(symbol, tf, batchStart, batchEnd, rates);

      if(copied > 0)
      {
         int skip = 0;
         if(totalWritten > 0 && rates[0].time <= lastTime)
            skip = 1;

         for(int i = skip; i < copied; i++)
         {
            string dt = TimeToString(rates[i].time, TIME_DATE | TIME_MINUTES);
            StringReplace(dt, ".", "-");
            FileWrite(handle, dt,
               DoubleToString(rates[i].open, digits),
               DoubleToString(rates[i].high, digits),
               DoubleToString(rates[i].low, digits),
               DoubleToString(rates[i].close, digits),
               IntegerToString(rates[i].tick_volume),
               symbol);
            totalWritten++;
         }
         if(firstTime == 0) firstTime = rates[0].time;
         lastTime = rates[copied - 1].time;
      }

      batchStart = batchEnd;
   }

   FileClose(handle);

   if(totalWritten > 0)
   {
      string s1 = TimeToString(firstTime, TIME_DATE);
      string s2 = TimeToString(lastTime, TIME_DATE);
      Print("✅ ", symbol, " ", tfName, ": ", totalWritten, " bars (", s1, " → ", s2, ") → ", filename);
      return true;
   }

   Print("⚠️ ", symbol, " ", tfName, ": No data written");
   return false;
}

//+------------------------------------------------------------------+
//| Script program start function                                      |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("═══════════════════════════════════════════════════════════");
   if(InpYears <= 0)
      Print("  Export Data v4.0 — ALL available data");
   else
      Print("  Export Data v4.0 — ", InpYears, " year(s)");
   Print("  3-month batch export + auto history download");
   Print("═══════════════════════════════════════════════════════════");
   Print("  ⚠️ BEFORE running: Tools → Options → Charts");
   Print("     → Max bars in chart: Unlimited");
   Print("═══════════════════════════════════════════════════════════");

   ENUM_TIMEFRAMES timeframes[] = {PERIOD_M5, PERIOD_H1};
   int totalExported = 0, totalFailed = 0;

   for(int s = 0; s < ArraySize(g_symbols); s++)
   {
      for(int t = 0; t < ArraySize(timeframes); t++)
      {
         if(ExportBars(g_symbols[s], timeframes[t], InpYears))
            totalExported++;
         else
            totalFailed++;
      }
   }

   Print("═══════════════════════════════════════════════════════════");
   Print("  Done! Exported: ", totalExported, " | Skipped: ", totalFailed);
   Print("  Files in: MQL5/Files/");
   Print("═══════════════════════════════════════════════════════════");
   Print("  Copy CSV files to your candle data folder");
}
//+------------------------------------------------------------------+
