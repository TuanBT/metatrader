# Bot Strategies — Trading Panel v2.26

> Tài liệu giải thích logic vào lệnh của 2 bot + Auto-Regime system.
> Tất cả bot dùng chung lot/risk từ Panel, và Panel quản lý SL/TP/Trail/Grid.

---

## Tổng quan

| # | Bot | File | Version | Mô tả |
|---|-----|------|---------|-------|
| 1 | Candle Counter | `Candle Counter Strategy.mqh` | v1.03 | Đếm nến + ATR filter + breakout entry |
| 2 | News Straddle  | `News Straddle Strategy.mqh`  | v1.01 | Pending order trước tin tức quan trọng |

> Trend Signal bot đã bị xóa ở v2.26.

---

## 1. Candle Counter Bot (CC) — v1.03

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

### Inputs (Settings dialog)

| Input | Default | Mô tả |
|-------|---------|-------|
| `InpCC_ATRMinMult` | 0.3 | Min candle range / ATR (0 = tắt filter) |
| `InpCC_BreakMult` | 0.1 | Break buffer / ATR (0 = tắt buffer) |
| `InpCC_PauseBars` | 60 | Tự resume sau N bars (0 = manual) |

### Shadow Globals (thay đổi runtime bởi Auto-Regime)

| Variable | Mặc định | Mô tả |
|----------|----------|-------|
| `cc_atrMinMult` | = InpCC_ATRMinMult | Lọc nến nhỏ — regime có thể thay đổi |
| `cc_breakMult` | = InpCC_BreakMult | Break buffer — regime có thể thay đổi |

### Lưu ý quan trọng

- **Không filter theo multi-TF EMA**: EMA 20/50 chỉ hiển thị tham khảo, KHÔNG phải điều kiện vào lệnh
- **Entry trên timeframe hiện tại**: bot chỉ đếm nến trên TF mà chart đang mở
- **Breakout intrabar**: không đợi nến close, vào ngay khi giá chạm level
- **Auto-pause**: Panel tự pause bot khi Grid DCA max + Large SL. Auto-resume sau N bars (mặc định 60)

---

## 2. News Straddle Bot (NS) — v1.01

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

### Inputs (Settings dialog)

| Input | Default | Mô tả |
|-------|---------|-------|
| `InpNS_MinsBefore` | 3 | Đặt pending trước tin bao lâu (phút) |
| `InpNS_MinsExpire` | 10 | Hủy pending nếu không kích hoạt (phút) |
| `InpNS_OffsetPips` | 15.0 | Khoảng cách Buy Stop/Sell Stop (pips) |
| `InpNS_SLPips` | 30.0 | SL riêng (0 = dùng SL của Panel) |
| `InpNS_TPPips` | 45.0 | TP riêng (0 = dùng TP của Panel) |
| `InpNS_OnlyHigh` | true | Chỉ tin HIGH importance |
| `InpNS_PauseBars` | 60 | Tự resume sau N bars (0 = manual) |

### Lưu ý quan trọng

- **Cần MT5 Calendar**: chỉ hoạt động với broker có Calendar API
- **Straddle = không đoán hướng**: chỉ cần giá move mạnh
- **1 lần 1 event**: không đặt pending cho 2 tin cùng lúc
- **Pending orders tồn tại khi tắt EA**: bot KHÔNG hủy pending khi deinit

---

## 3. Auto-Regime System (Python → INI → MQL5)

### Kiến trúc

```
Python (regime_analyzer.py)
    ↓  phân tích ADX, ATR%, EMA spread (500 bars)
    ↓  phân loại regime: trending_strong / trending_weak / ranging / high_volatile
    ↓  ghi file INI: MQL5/Files/config_<SYM>_<TF>.ini
MQL5 (ReadConfigINI)
    ↓  đọc INI mỗi 60s khi Auto ON
    ↓  chỉ đọc lại nếu file modification time thay đổi
    ↓  apply params vào shadow globals (có bounds check)
```

### Trigger — Cách kích hoạt

1. Bấm **⚙ Auto** button trong Bot panel → `g_autoRegime = true`
2. OnTimer tự check file INI mỗi **60 giây**
3. File phải ở: `MQL5/Files/config_<SYMBOL>_<TF>.ini` (ví dụ: `config_XAUUSDm_M1.ini`)
4. Chỉ đọc lại khi **modification time thay đổi** (tránh đọc lặp vô ích)

### Tham số Auto-Regime thay đổi

| INI Key | MQL5 Variable | Bounds | Ảnh hưởng lên EA |
|---------|---------------|--------|-------------------|
| `atr_mult` | `g_atrMult` | 0.5 – 5.0 | SL distance = ATR × mult (core) |
| `atr_min_mult` | `cc_atrMinMult` | 0.0 – 2.0 | CC bot: min candle range filter |
| `break_mult` | `cc_breakMult` | 0.0 – 1.0 | CC bot: breakout buffer |
| `be_start_mult` | `g_beStartMult` | 0.1 – 3.0 | Breakeven trigger: profit ≥ N × ATR × atrMult |
| `trail_min_dist` | `g_trailMinDist` | 0.1 – 3.0 | Close/Swing trail: min SL distance (× ATR) |
| `tp_atr_factor` | `g_tpATRFactor` | 0.5 – 3.0 | Auto TP: partial close at N × ATR |

> **Risk ($) KHÔNG bị thay đổi** — user luôn set thủ công.

### Regime Classification (Python)

| Regime | Điều kiện | atr_mult | trail | tp |
|--------|-----------|----------|-------|----|
| **trending_strong** | ADX > 30 & EMA spread > 1% | 1.5 | tight (0.3) | 1.0× ATR |
| **trending_weak** | ADX > 20 & EMA ordered | 1.5 | medium (0.5) | 1.0× ATR |
| **ranging** | ADX < 20 | 2.0 | wide (0.8) | 0.5× ATR (quick exit) |
| **high_volatile** | ATR percentile > 80% | 2.5 | medium (0.5) | 1.0× ATR |

### Khi tắt Auto (Auto OFF)

Reset tất cả shadow globals về input defaults:

| Variable | Reset về |
|----------|----------|
| `cc_atrMinMult` | InpCC_ATRMinMult |
| `cc_breakMult` | InpCC_BreakMult |
| `g_atrMult` | InpATRMult |
| `g_beStartMult` | 1.0 |
| `g_trailMinDist` | 0.5 |
| `g_tpATRFactor` | 1.0 |

### Chạy Python trên VPS

- File: `regime_analyzer.py` (cùng folder `MQL5/Trading Panel/`)
- Bat files: `run_regime.bat` (1 lần), `run_regime_loop.bat` (loop mỗi 60s)
- Symbols: XAUUSDm, USDJPYm, BTCUSDm, EURUSDm, GBPUSDm, AUDUSDm
- Timeframe: M1
- Flag `--all`: ghi config cho cả 2 instances

---

## Bot Panel UI

```
[Candle Count] [News Straddle]    ← 2 nút toggle view
┌──────────────────────────────┐
│ [▶ Start] [⚙ Auto]          │  ← Start/Stop + Auto-Regime
│                              │
│ (Bot-specific info lines)    │
│ ...                          │
│ Regime: ranging (93%)        │  ← CC line 6 (khi auto ON)
└──────────────────────────────┘
```

- **Xanh lá** = bot đang chạy
- **Xanh dương** = đang xem nhưng chưa chạy
- **Xám** = không active
- Bot chạy **nền** — chuyển view sang bot khác không tắt bot đang chạy

---

## Panel quản lý chung cho cả 2 bot

Khi bot vào lệnh, Panel tự động:

1. **SL**: Đặt theo ATR × multiplier (hoặc NS dùng SL riêng nếu > 0)
2. **Trail SL**: Di chuyển SL khi giá đi đúng hướng (Swing / Close / BE mode)
3. **Auto TP**: Đóng 50% tại TP1 (g_tpATRFactor × ATR), trail phần còn lại
4. **Grid DCA**: Nếu bật, thêm position khi giá đi ngược (max 2 levels, delay 5m)
5. **Lot size**: Tính từ Risk $ ÷ SL distance

---

*Last updated: Panel v2.26*
