@echo off
title Regime Analyzer - XAUUSDm M15
echo ============================================
echo  Regime Analyzer - Phan tich 1 lan
echo ============================================
echo.

:: --all = ca 2 instances (Demo + EXNESS Real)
"C:\Program Files\Python312\python.exe" C:\Temp\regime_analyzer.py --all --symbols XAUUSDm --timeframes M15

echo.
echo ============================================
echo  Hoan tat! Bat Auto tren chart de EA doc config.
echo ============================================
pause
