# Expert Candle Counter v1.4

> **Ý tưởng cốt lõi:** Khi thị trường tạo ra 3 nến liên tục cùng màu → đà (momentum) đang rõ ràng → vào lệnh theo hướng đó ở nến thứ 4.

---

## 1. Logic tổng quan (từng bước)

```
Nến thứ 3    Nến thứ 2    Nến thứ 1      Nến hiện tại
 bar[3]        bar[2]        bar[1]           bar[0]
   ▲              ▲             ▲                ↑
[Xanh]         [Xanh]        [Xanh]    ← VÀO LỆNH MUA tại đây
   └── SL đặt ở đáy bar[3] ────────────────────┘
```

**Flow đầy đủ:**

1. **Chờ nến mới mở** (EA chỉ kiểm tra 1 lần mỗi nến)
2. **Kiểm tra signal:** 3 nến đã đóng (bar[1], bar[2], bar[3]) có cùng màu không?
3. **Check các bộ lọc** theo thứ tự:
   - Filter thời gian (nếu bật)
   - Filter EMA (nếu bật): giá đang ở phía nào của EMA?
   - Filter ADX (nếu bật): thị trường có đang trending không?
4. **Vào lệnh** ngay khi nến thứ 4 mở
   - BUY: `ask price`
   - SELL: `bid price`
   - SL: đặt tại đáy (buy) hoặc đỉnh (sell) của nến thứ nhất (bar[3])
   - TP: **không có** — chỉ thoát bằng trailing SL
5. **Mỗi nến tiếp theo:** kiểm tra trailing SL
   - Nếu nến mới đóng **cùng chiều** với lệnh → dời SL lên bar[1].low (buy) / bar[1].high (sell)
   - Trailing chỉ **tiến không lùi**

---

## 2. Tại sao 3 nến cùng màu?

Đây là pattern momentum đơn giản nhất:

- **1 nến xanh** → có thể ngẫu nhiên
- **2 nến xanh** → bắt đầu có hướng
- **3 nến xanh liên tiếp** → momentum đang rõ ràng, khả năng cao nến thứ 4 tiếp tục

Không cần phân tích phức tạp — thị trường đang "kéo" về một hướng, ta chỉ cần đi theo.

---

## 3. Stop Loss được đặt ở đâu và tại sao?

```
         bar[3]  bar[2]  bar[1]
          ─┬──    ─┬──    ─┬──     ← đỉnh các nến
           │       │       │
           │       │       │       ← thân nến
          ─┴──    ─┴──    ─┴──     ← đáy các nến
           ↑
    SL đặt ở đây (đáy bar[3])
```

**Lý do chọn bar[3]:**
- Đây là điểm **bắt đầu** của pattern 3 nến
- Nếu giá quay về phá đáy nến đầu tiên → pattern đã thất bại
- SL rộng hơn bar[1] (ít noise hơn) nhưng không quá rộng như bar[3] của toàn dãy

**Tại sao không dùng SL cố định (pips)?**
- SL theo cấu trúc giá phù hợp hơn với từng thị trường
- XAUUSD có biên độ khác USDJPY → SL tự động thích nghi

---

## 4. Trailing SL hoạt động thế nào?

```
Vào lệnh BUY        Nến tiếp 1     Nến tiếp 2     Nến tiếp 3
────────────────    ────────────    ────────────    ────────────
SL = bar[3].low     SL dời lên      SL dời lên      Nến đỏ xuất hiện
                    bar[1].low      bar[1].low      → KHÔNG dời SL
                    (tiến lên)      (tiến lên)      (chờ nến xanh tiếp)
```

**Điều kiện dời SL:**
- Nến vừa đóng (bar[1]) phải **cùng chiều** với lệnh
- SL mới phải **tốt hơn** SL cũ (chỉ tiến, không lùi)
- SL mới không được **vượt qua giá hiện tại** (an toàn)

**Ý nghĩa:** Khi trend chạy đẹp, SL sẽ dần "bám sát" theo từng nến — khoá lại lợi nhuận.

---

## 5. Thoát lệnh khi nào?

EA **không có TP cố định**. Lý do:

> Trend tốt có thể chạy xa hơn nhiều so với bất kỳ TP cố định nào. Việc đặt TP cắt ngắn lợi nhuận trong các trade win lớn.

Thoát lệnh chỉ bằng **SL bị chạm** (trailing hoặc initial). Kết quả:
- Lệnh thua → thoát nhanh (SL ở vùng pattern thất bại)
- Lệnh thắng → chạy theo trend đến khi đảo chiều

---

## 6. Giải thích từng tham số (Inputs)

> **v1.4:** Đã xóa các tham số không hiệu quả (body filter, ATR filter, time filter) để code gọn hơn.

### Nhóm 1: Quản lý lệnh cơ bản

| Tham số | Mặc định | Giải thích |
|---|---|---|
| `InpLotSize` | 0.01 | Số lot mỗi lệnh. Với $500 balance, lot 0.01 = rủi ro ~$1–5/lệnh tùy SL |
| `InpDeviation` | 20 | Slippage tối đa cho phép khi vào/sửa lệnh (tính bằng points). Nếu giá trượt quá 20 points khi vào lệnh, EA sẽ từ chối. |
| `InpMagic` | 20260225 | Số ID để nhận ra lệnh của EA này. Nếu chạy nhiều EA cùng lúc, mỗi EA cần magic number khác nhau |
| `InpOnePosition` | true | `true` = chỉ giữ 1 lệnh mở cùng lúc. Signal mới sẽ bị bỏ qua nếu đang có lệnh |

**Tại sao `InpOnePosition=true`?**
Tránh "chồng lệnh" — khi có lệnh đang mở mà signal mới xuất hiện (có thể là cùng chiều), sẽ không vào thêm. Giúp kiểm soát rủi ro tốt hơn.

---

### Nhóm 2: EMA Trend Filter *(mặc định BẬT)*

| Tham số | Mặc định | Giải thích |
|---|---|---|
| `InpUseEMAFilter` | **true** | Bật/tắt filter |
| `InpEMAPeriod` | 50 | Số chu kỳ EMA |
| `InpEMATF` | PERIOD_CURRENT | Timeframe tính EMA (0 = dùng TF của chart) |

**Logic:**
```
EMA50 line
──────────────────── ← EMA50

    Giá đang trên EMA50 → Chỉ vào lệnh BUY (3 nến xanh)
                           Bỏ qua SELL (3 nến đỏ)

──────────────────── ← EMA50

    Giá đang dưới EMA50 → Chỉ vào lệnh SELL (3 nến đỏ)
                           Bỏ qua BUY (3 nến xanh)
```

**Tại sao EMA50?**
- EMA50 là trend filter phổ biến nhất, đủ "nhanh" cho H4 nhưng không quá nhiễu
- **Bằng chứng từ backtest:** khi thêm EMA50, kết quả USDJPYm H4 tăng từ 3/6 lên **5/6 năm dương**, XAUUSD từ 2/6 lên **4/6 năm dương**

---

### Nhóm 3: ADX Regime Filter *(mặc định BẬT)*

| Tham số | Mặc định | Giải thích |
|---|---|---|
| `InpUseADXFilter` | **true** | Bật/tắt filter |
| `InpADXPeriod` | 14 | Chu kỳ ADX |
| `InpADXMinValue` | 25.0 | Chỉ vào lệnh khi ADX ≥ giá trị này |

**ADX là gì?**
ADX (Average Directional Index) đo **độ mạnh của trend**, không đo hướng:
- ADX < 20: thị trường đang **sideway/ranging** → pattern 3 nến kém tin cậy
- ADX 20–25: trend **yếu**
- ADX > 25: trend **đang có sức mạnh** → đây là lúc vào lệnh an toàn hơn
- ADX > 40: trend **rất mạnh**

**Logic:**
```
ADX = 18  (ranging market)
→ 3 nến xanh xuất hiện nhưng thị trường đang đi ngang
→ EA BỎ QUA signal → tránh false breakout

ADX = 30  (trending market)
→ 3 nến xanh xuất hiện và thị trường đang có đà
→ EA VÀO LỆNH
```

**Tại sao ADX > 25 thay vì 20 hay 30?**
Backtest cho thấy 25 là điểm cân bằng tốt nhất giữa "lọc đủ" và "không bỏ lỡ quá nhiều lệnh".

---

## 7. Ví dụ trade thực tế

**Setup:** USDJPYm H4, EMA50=141.00, ADX=28

```
Bar[3]: Open=140.50, Close=140.80 → Xanh ✓
Bar[2]: Open=140.80, Close=141.20 → Xanh ✓
Bar[1]: Open=141.20, Close=141.60 → Xanh ✓

Kiểm tra:
- Close[1]=141.60 > EMA50=141.00 → OK (buy phía trên EMA) ✓
- ADX=28 > 25 → OK (đang trending) ✓

→ VÀO LỆNH BUY tại open bar[0]

Entry: Ask = 141.62
SL:    bar[3].low = 140.45
Risk:  141.62 - 140.45 = 117 points = 117 pips USDJPY

Trailing:
- Bar tiếp theo đóng xanh tại 142.00 → dời SL lên bar[1].low = 141.59
- Bar tiếp theo đóng xanh tại 142.50 → dời SL lên bar[1].low = 141.98
- Bar tiếp theo đóng đỏ → giữ nguyên SL = 141.98
- Bar tiếp theo đóng xanh tại 143.00 → dời SL lên bar[1].low = 142.47
...
- Một lúc sau, giá quay về chạm SL cuối → thoát lệnh
```

---

## 8. Tại sao không có TP?

Hệ thống này dựa trên **asymmetric payoff:**

- **Lệnh thua:** bị stop nhanh ở SL cố định ban đầu (1 pattern 3 nến)
- **Lệnh thắng:** chạy theo trend, SL trailing theo từng nến → có thể lãi 3R, 5R, 10R

Nếu đặt TP = 2R:
- Win Rate 50% × 2R - 50% × 1R = **0.5R/trade** (profit nhỏ)

Nếu không có TP, để trend chạy:
- Win Rate 50%, nhưng các lệnh thắng có thể đạt 4–8R
- Kỳ vọng cao hơn nhiều

---

## 9. Kết quả backtest (H4, 2020–2025)

| Cặp | 2020 | 2021 | 2022 | 2023 | 2024 | 2025 | +/6 |
|---|---|---|---|---|---|---|---|
| **USDJPYm** | +7.4% | -1.5% | +11.1% | +1.6% | +28.2% | +5.5% | **5/6** ⭐ |
| **XAUUSDm** | -6.5% | +3.5% | -9.1% | +15.1% | +25.3% | +153.9% | 4/6 |

*Config: Lot=0.01, EMA50, ADX(14)>25, Body=0%, Balance=\$500*

---

## 10. Config đang chạy live

| Tham số | Giá trị |
|---|---|
| Lot size | 0.01 |
| EMA filter | ✅ ON — EMA(50) |
| ADX filter | ✅ ON — ADX(14) > 25 |
| Timeframe | H4 |
| Pairs | USDJPYm, XAUUSDm |

Preset: `CC_H4_EMA50_ADX25.set`
