@echo off
title Regime Analyzer - Loop Mode (5 phut)
echo ============================================
echo  Regime Analyzer - Chay lien tuc moi 5 phut
echo  Nhan Ctrl+C de dung
echo ============================================
echo.

:: Them symbol: sua dong duoi, cach nhau bang dau phay (EXNESS dung 'm' suffix)
:: --loop 300 = chay lai moi 300 giay (5 phut)
"C:\Program Files\Python312\python.exe" C:\Temp\regime_analyzer.py --all --symbols XAUUSDm,USDJPYm,BTCUSDm,EURUSDm,GBPUSDm,AUDUSDm --timeframes M1 --loop 300

pause
