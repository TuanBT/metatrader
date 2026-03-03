@echo off
:: ═══════════════════════════════════════════════════════════════
:: Clear MT5 Logs, Tester Cache & Reports
:: Double-click to run — safe to execute while MT5 is running
:: (MT5 will recreate today's log automatically)
:: ═══════════════════════════════════════════════════════════════

set "BASE=C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"

echo.
echo ═══════════════════════════════════════════
echo   Clear MT5 Logs ^& Cache
echo ═══════════════════════════════════════════
echo.
echo This will delete:
echo   - Terminal logs       (%BASE%\logs\*.log)
echo   - EA/Expert logs      (%BASE%\MQL5\Logs\*.log)
echo   - Tester logs         (%BASE%\Tester\logs\*)
echo   - Tester cache        (%BASE%\Tester\cache\*)
echo   - Backtest reports    (%BASE%\reports\*)
echo   - Temp files          (%BASE%\temp\*)
echo.

set /p CONFIRM="Are you sure? (Y/N): "
if /i not "%CONFIRM%"=="Y" (
    echo Cancelled.
    pause
    exit /b
)

echo.

:: ── Terminal logs ──
echo Clearing Terminal logs...
del /q "%BASE%\logs\*.log" 2>nul
echo   Done.

:: ── MQL5/Expert logs ──
echo Clearing Expert logs...
del /q "%BASE%\MQL5\Logs\*.log" 2>nul
echo   Done.

:: ── Tester logs ──
echo Clearing Tester logs...
del /q /s "%BASE%\Tester\logs\*.*" 2>nul
echo   Done.

:: ── Tester cache ──
echo Clearing Tester cache...
del /q /s "%BASE%\Tester\cache\*.*" 2>nul
echo   Done.

:: ── Reports ──
echo Clearing backtest reports...
del /q "%BASE%\reports\*.*" 2>nul
echo   Done.

:: ── Temp ──
echo Clearing temp files...
del /q /s "%BASE%\temp\*.*" 2>nul
echo   Done.

echo.
echo ═══════════════════════════════════════════
echo   All logs ^& cache cleared!
echo ═══════════════════════════════════════════
echo.
pause
