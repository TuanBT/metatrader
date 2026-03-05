@echo off
title Regime Analyzer - Loop Mode (5 phut)
echo ============================================
echo  Regime Analyzer - Chay lien tuc moi 5 phut
echo  Nhan Ctrl+C de dung
echo ============================================
echo.

:: Instance 2 = EXNESS Real (doi --instance 1 neu can Demo)
:: --loop 300 = chay lai moi 300 giay (5 phut)
"C:\Program Files\Python312\python.exe" C:\Temp\regime_analyzer.py --instance 2 --symbols XAUUSDm --timeframes M15 --loop 300

pause
