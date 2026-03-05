@echo off
title Regime Analyzer - XAUUSDm M15
echo ============================================
echo  Regime Analyzer - Phan tich 1 lan
echo ============================================
echo.

:: Instance 2 = EXNESS Real (doi --instance 1 neu can Demo)
"C:\Program Files\Python312\python.exe" C:\Temp\regime_analyzer.py --instance 2 --symbols XAUUSDm --timeframes M15

echo.
echo ============================================
echo  Hoan tat! Bat Auto tren chart de EA doc config.
echo ============================================
pause
