# Bot Strategies — Khi nào vào lệnh?

> Tài liệu giải thích logic vào lệnh của 3 bot tích hợp trong Trading Panel v2.02.
> Tất cả bot dùng chung lot/risk từ Panel, và Panel quản lý SL/TP/Trail/Grid.

---

## 1. Candle Counter Bot (CC Bot)

**Loại chiến lược:** Price Action — đếm nến liên tiếp + breakout

### Điều kiện vào lệnh BUY

1. **2 nến xanh liên tiếp** (bar[2] và bar[1] đều close > open)
2. **Higher lows**: low bar[1] > low bar[2] (nến sau có đáy cao hơn)
3. **ATR filter**: cả 2 nến đều có range (high - low) ≥ `ATRMinMult × ATR`
   - Mặc định `ATRMinMult = 0.3` → nến phải có biên độ ≥ 30% ATR
   - Nếu = 0 thì tắt filter
4. **Breakout**: Giá Ask **vượt qua** high của bar[1] (tick-by-tick, không đợi close)

```
Bar[2]    Bar[1]    Bar[0] (hiện tại)
 ┌─┐       ┌─┐
 │█│       │█│      Price > High[1] → BUY!
 │█│       │█│
 └─┘       └─┘
  ▲ low2 < low1 ▲
```

### Điều kiện vào lệnh SELL

1. **2 nến đỏ liên tiếp** (bar[2] và bar[1] đều close < open)
2. **Lower highs**: high bar[1] < high bar[2] (nến sau có đỉnh thấp hơn)
3. **ATR filter**: tương tự BUY
4. **Breakout**: Giá Bid **phá xuống dưới** low của bar[1]

```
Bar[2]    Bar[1]    Bar[0] (hiện tại)
 ┌─┐       ┌─┐
 │▓│       │▓│
 │▓│       │▓│      Price < Low[1] → SELL!
 └─┘       └─┘
  ▼ high2 > high1 ▼
```

### Tóm tắt luồng

```
Mỗi bar mới:
  → Đếm nến: 2 xanh liên tiếp? 2 đỏ liên tiếp?
  → Check higher lows / lower highs?
  → Check ATR filter?
  → Nếu tất cả OK → Chờ BREAKOUT (mỗi tick check giá)
  → Breakout xảy ra → Vào lệnh ngay

Pending state tự reset mỗi bar mới (nếu nến mới không thỏa mãn điều kiện).
```

### Display trên Panel

- **8 TF signal** (W1, D1, H4, H1, M30, M15, M5, M1): EMA 20/50 cross
  - ▲ = EMA20 > EMA50 (uptrend)
  - ▼ = EMA20 < EMA50 (downtrend)
  - TF hiện tại được đánh dấu `[▲]`
- **Count**: hiển thị 0/2, 1/2, 2/2 + hướng
- **Bar1, Bar2**: chi tiết từng nến (Color ✓/✗, Wick ✓/✗, ATR ✓/✗)
- **Break level**: mức giá cần vượt qua
- **ATR info**: giá trị ATR hiện tại và ngưỡng min

### Lưu ý quan trọng

- **Không filter theo multi-TF EMA**: EMA 20/50 chỉ hiển thị tham khảo, KHÔNG phải điều kiện vào lệnh
- **Entry trên timeframe hiện tại**: bot chỉ đếm nến trên TF mà chart đang mở
- **Breakout intrabar**: không đợi nến close, vào ngay khi giá chạm level
- **Auto-pause**: Panel tự pause bot khi Grid DCA max + Large SL. Auto-resume sau N bars (mặc định 60)

---

## 2. Trend Signal Bot (TS Bot)

**Loại chiến lược:** Multi-timeframe EMA trend-following

### Cấu trúc 3 timeframe

Tùy theo TF chart hiện tại, bot tự map 3 level:

| Chart TF | Entry TF | Mid TF | High TF |
|----------|----------|--------|---------|
| M1       | M1       | M5     | M15     |
| M5       | M5       | M15    | H1      |
| **M15**  | **M15**  | **H1** | **H4**  |
| M30      | M30      | H4     | D1      |
| H1       | H1       | H4     | D1      |
| H4       | H4       | D1     | W1      |
| D1       | D1       | W1     | MN      |

### Điều kiện vào lệnh BUY — Tất cả phải thỏa mãn đồng thời

1. **High TF uptrend**: EMA Fast > EMA Slow trên High TF
2. **Mid TF uptrend**: EMA Fast > EMA Slow trên Mid TF
3. **Entry TF cross up**: EMA Fast _vừa cắt lên_ EMA Slow trên Entry TF
   - Cụ thể: `bar[2]: Fast ≤ Slow` → `bar[1]: Fast > Slow`

```
High TF:   EMA20 ────────── trên EMA50  ✓ Uptrend
Mid TF:    EMA20 ────────── trên EMA50  ✓ Uptrend
Entry TF:  EMA20 ╲ cắt lên ╱ EMA50     ✓ Cross Up
                              ↓
                         VÀO LỆNH BUY
```

### Điều kiện vào lệnh SELL — Tất cả phải thỏa mãn đồng thời

1. **High TF downtrend**: EMA Fast < EMA Slow trên High TF
2. **Mid TF downtrend**: EMA Fast < EMA Slow trên Mid TF
3. **Entry TF cross down**: EMA Fast _vừa cắt xuống_ EMA Slow trên Entry TF
   - Cụ thể: `bar[2]: Fast ≥ Slow` → `bar[1]: Fast < Slow`

```
High TF:   EMA20 ────────── dưới EMA50  ✓ Downtrend
Mid TF:    EMA20 ────────── dưới EMA50  ✓ Downtrend
Entry TF:  EMA20 ╱ cắt xuống ╲ EMA50   ✓ Cross Down
                              ↓
                         VÀO LỆNH SELL
```

### Tóm tắt luồng

```
Mỗi bar mới (Entry TF):
  → Update EMA trên 3 TF
  → High TF: EMA20 vs EMA50 → up/down?
  → Mid TF: EMA20 vs EMA50 → up/down?
  → Entry TF: EMA20 có vừa cross EMA50 không?
  → 3 điều kiện cùng hướng → VÀO LỆNH
  → Chỉ vào 1 lần mỗi bar (không entry 2 lần cùng bar)
```

### Display trên Panel

- **8 TF signal** (W1, D1, H4, H1, M30, M15, M5, M1):
  - `H4▲` = EMA20 > EMA50 trên H4
  - `M15▼` = EMA20 < EMA50 trên M15
  - `[M15▲]` = TF entry hiện tại
- **Info lines**:
  - Entry: EMA 20/50 cross [M15]
  - Filter: H1 + H4 aligned
  - BUY : Cross up + Mid▲ + High▲
  - SELL: Cross dn + Mid▼ + High▼

### Lưu ý quan trọng

- **Chỉ vào khi cross + cả 3 TF cùng hướng**: rất selective, có thể nhiều ngày không có signal
- **Cross = điều kiện chặt**: phải có sự thay đổi từ bar[2] → bar[1], không chỉ đơn giản Fast > Slow
- **Không có ATR filter**: entry dựa 100% vào EMA
- **EMA period mặc định**: Fast = 20, Slow = 50 (có thể thay đổi trong input)
- **Khi bật bot**: EMA 20/50 được hiển thị trên chart. Khi tắt → ẩn
- **VD trên M15**: cần H4 + H1 uptrend, rồi EMA20 vừa cross lên EMA50 trên M15 → BUY

### Khi nào Trend Signal KHÔNG vào lệnh

- High TF và Mid TF ngược hướng nhau (ví dụ H4 up, H1 down)
- EMA trên Entry TF chưa cross (chỉ đang trending nhưng chưa có cross point)
- Đã có position (chỉ vào 1 lệnh cùng lúc)
- Bot đang paused (sau Large SL)

---

## 3. News Straddle Bot (NS Bot)

**Loại chiến lược:** News trading — đặt pending straddle trước tin

### Logic vào lệnh

NS Bot **không tự vào lệnh trực tiếp**, mà đặt 2 lệnh pending (Buy Stop + Sell Stop) rồi để thị trường quyết định:

```
         Sell Stop ─────── Bid - Offset (15 pips mặc định)
              │
         Price hiện tại
              │
         Buy Stop  ─────── Ask + Offset (15 pips mặc định)
```

### Quy trình chi tiết

```
┌─────────────────────────────────────────────────────┐
│  1. Bot quét MT5 Calendar API mỗi 60 giây           │
│     → Tìm tin HIGH importance trong 24h tới          │
│     → Chỉ lấy tin liên quan đến symbol (base/quote) │
│     Ví dụ: XAUUSD → lọc tin USD                     │
│            EURUSD → lọc tin EUR + USD                │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│  2. N phút trước tin (mặc định 3 phút)              │
│     → Đặt Buy Stop = Ask + 15 pips                  │
│     → Đặt Sell Stop = Bid - 15 pips                 │
│     → SL/TP từ input (30/45 pips) hoặc Panel quản lý│
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│  3. Tin ra → giá spike                               │
│     → Nếu giá spike lên → Buy Stop kích hoạt        │
│       → Bot tự hủy Sell Stop                         │
│     → Nếu giá spike xuống → Sell Stop kích hoạt     │
│       → Bot tự hủy Buy Stop                          │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│  4. Nếu sau N phút (mặc định 10) không kích hoạt    │
│     → Hủy cả 2 pending                              │
│     → Quét tin tiếp theo                              │
└─────────────────────────────────────────────────────┘
```

### Parameters

| Parameter     | Default | Mô tả                                           |
|---------------|---------|--------------------------------------------------|
| MinsBefore    | 3       | Đặt pending trước tin bao lâu (phút)             |
| MinsExpire    | 10      | Hủy pending nếu không kích hoạt sau bao lâu (phút) |
| OffsetPips    | 15.0    | Khoảng cách từ giá hiện tại                       |
| SLPips        | 30.0    | Stop Loss (0 = để Panel quản lý)                  |
| TPPips        | 45.0    | Take Profit (0 = để Panel quản lý)                |
| OnlyHigh      | true    | Chỉ lọc tin HIGH importance                       |

### Display trên Panel

- **Status**: Watching / Pendings Active / Triggered / PAUSED
- **Next event**: tên tin + currency + countdown
- **Pending status**: ticket numbers của Buy Stop / Sell Stop
- **Position info**: nếu đã trigger → hiện P&L
- **Parameters**: offset, timing, SL/TP

### Lưu ý quan trọng

- **Cần MT5 Calendar**: chỉ hoạt động với broker có Calendar API (hầu hết broker đều có)
- **Giá offset**: nếu offset quá nhỏ → dễ bị trigger bởi noise. Quá lớn → khó trigger
- **Straddle = không đoán hướng**: bot không cần biết tin tốt/xấu, chỉ cần giá move mạnh
- **1 lần 1 event**: khi đã đặt pending cho 1 tin, không đặt thêm cho tin khác
- **Pending orders tồn tại khi tắt EA**: nếu deinit, bot KHÔNG hủy pending → order vẫn sống trên server

---

## So sánh 3 Bot

| Tiêu chí         | Candle Counter       | Trend Signal          | News Straddle          |
|-------------------|----------------------|-----------------------|------------------------|
| **Loại**          | Price Action         | Trend Following       | News/Event             |
| **Entry**         | Breakout (intrabar)  | EMA Cross (new bar)   | Pending order          |
| **Timeframe**     | Single TF            | Multi-TF (3 levels)   | Không phụ thuộc TF     |
| **Frequency**     | Trung bình           | Thấp (rất selective)  | Theo lịch tin          |
| **Indicator**     | None (price action)  | EMA 20/50             | MT5 Calendar API       |
| **Filter**        | ATR min size         | Higher TF aligned     | News importance        |
| **Best for**      | Ranging + trending   | Strong trends         | High-impact news       |
| **Risk**          | False breakout       | Whipsaw khi sideway   | Slippage, spread widen |

---

## Panel quản lý chung cho cả 3 bot

Khi bot vào lệnh, Panel tự động:

1. **SL**: Đặt theo ATR × multiplier (hoặc NS dùng SL riêng nếu > 0)
2. **Trail SL**: Di chuyển SL khi giá đi đúng hướng (Swing / Close / BE mode)
3. **Auto TP**: Đóng 50% tại TP1 (1.0 ATR mặc định), trail phần còn lại
4. **Grid DCA**: Nếu bật, thêm position khi giá đi ngược (max 2 levels, delay 5m)
5. **Lot size**: Tính từ Risk % (mặc định 1% balance) ÷ SL distance

---

*Last updated: Panel v2.02*
