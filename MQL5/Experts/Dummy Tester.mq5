//+------------------------------------------------------------------+
//| Dummy Tester.mq5                                                 |
//| Dummy EA for Strategy Tester — forces MT5 to download M5 data    |
//| Instructions:                                                    |
//|   1. Compile this EA                                             |
//|   2. Open Strategy Tester (Ctrl+R)                               |
//|   3. Select "Dummy Tester" EA                                    |
//|   4. Symbol: XAUUSDm (or each symbol you need)                   |
//|   5. Period: M5                                                  |
//|   6. Date: check "Use date" → from 2020.01.01 to today           |
//|   7. Modeling: "Every tick" or "1 minute OHLC"                   |
//|   8. Click "Start" — MT5 will download data first                |
//|   9. Repeat for each symbol: BTCUSDm, ETHUSDm, USOILm, etc.     |
//|   10. After all symbols done → run "Export Data" script           |
//+------------------------------------------------------------------+
#property copyright "MST"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Dummy Tester started — forcing data download for ", _Symbol, " ", EnumToString(_Period));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function — does nothing                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // Intentionally empty — we only need MT5 to download history
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Dummy Tester finished for ", _Symbol);
}
//+------------------------------------------------------------------+
