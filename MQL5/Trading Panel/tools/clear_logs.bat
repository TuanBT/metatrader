@echo off
:: ═══════════════════════════════════════════════════════════════
:: Clear MT5 Logs, Tester Cache & Reports
:: Covers BOTH MT5 installations on this VPS:
::   1. AppData (standard install)
::   2. C:\MetaTrader 5 EXNESS Real (portable copy)
:: Double-click to run — safe while MT5 is running
:: ═══════════════════════════════════════════════════════════════

set "BASE1=C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06"
set "BASE2=C:\MetaTrader 5 EXNESS Real"

echo.
echo ═══════════════════════════════════════════
echo   Clear MT5 Logs ^& Cache (both installs)
echo ═══════════════════════════════════════════
echo.
echo [1] AppData install:  %BASE1%
echo [2] Portable install: %BASE2%
echo.
echo Will delete: logs, EA logs, tester logs/cache, reports, temp
echo.

set /p CONFIRM="Are you sure? (Y/N): "
if /i not "%CONFIRM%"=="Y" (
    echo Cancelled.
    pause
    exit /b
)

echo.

:: ════════════════════════════════════════════
:: INSTALL 1: AppData
:: ════════════════════════════════════════════
echo [1/2] Clearing AppData install...

echo   Terminal logs...
del /q "%BASE1%\logs\*.log" 2>nul

echo   Expert logs...
del /q "%BASE1%\MQL5\Logs\*.log" 2>nul

echo   Tester logs...
del /q /s "%BASE1%\Tester\logs\*.*" 2>nul

echo   Tester cache...
del /q /s "%BASE1%\Tester\cache\*.*" 2>nul

echo   Reports...
del /q "%BASE1%\reports\*.*" 2>nul

echo   Temp...
del /q /s "%BASE1%\temp\*.*" 2>nul

echo   Done.
echo.

:: ════════════════════════════════════════════
:: INSTALL 2: Portable (C:\MetaTrader 5 EXNESS Real)
:: ════════════════════════════════════════════
echo [2/2] Clearing Portable install...

echo   Terminal logs...
del /q "%BASE2%\logs\*.log" 2>nul

echo   Expert logs...
del /q "%BASE2%\MQL5\Logs\*.log" 2>nul

echo   Tester logs...
del /q /s "%BASE2%\Tester\logs\*.*" 2>nul

echo   Tester cache...
del /q /s "%BASE2%\Tester\cache\*.*" 2>nul

echo   Done.
echo.

echo ═══════════════════════════════════════════
echo   All logs ^& cache cleared!
echo ═══════════════════════════════════════════
echo.
pause
