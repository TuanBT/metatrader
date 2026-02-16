# MST Medio — Strategy Tester Log Collection

## Mục tiêu
Thu thập log từ MT5 Strategy Tester cho tất cả 6 cặp tiền để so sánh với Python backtest.

## Thư mục lưu log
Lưu vào: `MST Medio/logs/`

## Tên file
Đặt tên CHÍNH XÁC theo symbol:
- `BTCUSDm.log`
- `XAUUSDm.log`
- `EURUSDm.log`
- `USDJPYm.log`
- `ETHUSDm.log`
- `USOILm.log`

## Cài đặt Strategy Tester (GIỐNG NHAU cho tất cả các cặp)

| Setting | Value |
|---------|-------|
| **Expert** | `Expert MST Medio.ex5` |
| **Symbol** | Chọn đúng pair (BTCUSDm, XAUUSDm, ...) |
| **Period** | **M5** |
| **Date From** | **2025.01.01** |
| **Date To** | **2026.02.15** (hoặc ngày hiện tại) |
| **Modeling** | **OHLC 1 minute** (mặc định) |
| **Deposit** | **10000** |
| **Profit in** | **pips** |
| **Leverage** | **1:100** |
| **Optimization** | **Disabled** (không optimize) |

### Inputs (Parameters):
| Input | Value |
|-------|-------|
| InpMaxRiskPct | **0** (tắt MaxRisk — để test không bị skip) |
| InpLotSize | **0.01** |
| InpPartialTP | **false** (tắt — để so sánh đơn giản) |
| InpShowVisual | **false** |
| InpMagic | **20260210** |

## Cách lấy log

1. Mở MT5 → View → **Strategy Tester**
2. Chọn Expert, Symbol, Period, Dates theo bảng trên
3. Nhập Inputs theo bảng trên
4. **Start** test
5. Khi test xong → click tab **Journal**
6. **Right-click** → **Open** (mở file log gốc)
7. **Copy file log** vào thư mục `MST Medio/logs/` và đổi tên theo symbol
8. Lặp lại cho tất cả 6 cặp

### ⚠️ LƯU Ý QUAN TRỌNG:
- **Deposit = 10000** (đủ lớn để không bị stop out)
- **InpMaxRiskPct = 0** (tắt MaxRisk filter)
- **InpPartialTP = false** (đơn giản hóa — 1 lệnh duy nhất)
- Đảm bảo **compile lại EA** trước khi test (nhấn F7 trong MetaEditor)
- Mỗi cặp test riêng, lưu log riêng

## Chạy phân tích

Sau khi có đủ log files:
```bash
cd /Users/tuan/GitProject/metatrader/MQL5/MST\ Medio/backtest
python analyze_all_logs.py
```

Hoặc chỉ 1 cặp:
```bash
python analyze_all_logs.py --pair BTCUSDm
```

## Kết quả mong đợi
Script sẽ so sánh:
1. Số lượng signals giữa MT5 và Python
2. Entry/SL/TP có khớp nhau không
3. Win rate và PnL
4. Những signals nào chỉ xuất hiện ở 1 bên
