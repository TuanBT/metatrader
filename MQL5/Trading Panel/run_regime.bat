@echo off
title Regime Analyzer - XAUUSDm M15
echo ============================================
echo  Regime Analyzer - Phan tich 1 lan
echo ============================================
echo.

:: Them symbol: sua dong duoi, cach nhau bang dau phay (EXNESS dung 'm' suffix)
"C:\Program Files\Python312\python.exe" C:\Temp\regime_analyzer.py --all --symbols XAUUSDm,USDJPYm --timeframes M15

echo.
echo ============================================
echo  Hoan tat! Bat Auto tren chart de EA doc config.
echo ============================================
pause
