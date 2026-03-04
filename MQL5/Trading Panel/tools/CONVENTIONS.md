# Trading Panel — Conventions

> Chuẩn hóa mọi rule chung giữa **Expert Trading Panel** và các **Bot Strategy** (.mqh).
> Khi tạo Bot mới hoặc sửa Bot cũ, **phải tuân thủ** các quy ước bên dưới.
> Khi thay đổi quy ước chung → cập nhật **TẤT CẢ** Strategy + Panel cho đồng nhất.

---

## 1. Architecture — Integrated Bot Design

Tất cả Bot được tích hợp trực tiếp vào Panel qua **#include `.mqh`** files.
**Không dùng** standalone `.mq5` + GlobalVariable IPC nữa.

### 1.1 File Structure

```
Trading Panel/
  Expert Trading Panel.mq5         ← Main EA (Panel + bot dispatch)
  Candle Counter Strategy.mqh      ← Candle Counter Bot logic
  Trend Signal Strategy.mqh        ← Trend Signal Bot logic
  tools/
    deploy.command                 ← Deploy script (macOS)
    CONVENTIONS.md                 ← This file
```

### 1.2 Component Registry

| Component | File | Prefix (code) | Prefix (objects) | Input group |
|-----------|------|---------------|-------------------|-------------|
| Expert Trading Panel | `Expert Trading Panel.mq5` | `g_` | `Bot_` | (nhiều groups) |
| Candle Counter Bot | `Candle Counter Strategy.mqh` | `cc_` | `CCBot_` | `══ Candle Counter Bot ══` |
| Trend Signal Bot | `Trend Signal Strategy.mqh` | `ts_` | `TBot_` | `══ Trend Signal Bot ══` |

### 1.3 Integration Pattern

```mql5
// In Expert Trading Panel.mq5:
#include "Candle Counter Strategy.mqh"
#include "Trend Signal Strategy.mqh"
```

Mỗi `.mqh` file exports các function chuẩn:

| Function | Purpose |
|----------|---------|
| `XX_Init()` | Tạo indicator handles, map timeframes |
| `XX_Deinit()` | Release handles, destroy panel, cleanup chart |
| `XX_Tick()` | Entry logic, gọi mỗi tick khi bot active |
| `XX_Timer()` | Update signals + panel UI, gọi mỗi giây khi bot active |
| `XX_CreatePanel(x, y, w)` | Tạo bot info panel tại vị trí cho trước |
| `XX_DestroyPanel()` | Xóa tất cả objects của bot |
| `XX_UpdatePanel()` | Cập nhật bot panel UI |
| `XX_SetPaused(...)` | Panel yêu cầu bot pause (Large SL) |
| `XX_ClearPause()` | Xóa trạng thái pause |
| `XX_SetVisible(bool)` | Ẩn/hiện objects khi Panel collapse |
| `XX_UpdateSignalStates()` | Cập nhật trạng thái signal (gọi khi activate) |

---

## 2. Bot Toggle — UI

### 2.1 Bot Buttons

- Nút **[Candle Counter]** và **[Trend Signal]** nằm **ngang** bên phải Panel chính
- Mỗi nút rộng **110px**, cao **24px**
- **Chỉ 1 bot active** tại 1 thời điểm
- Click bot đang active → tắt bot (không có bot nào active)
- Click bot khác → tắt bot cũ, bật bot mới

### 2.2 Bot Panel

- Nằm bên **phải** Panel chính, dưới hàng nút bot
- Width: **224px**, background color giống Panel
- Hiển thị: status, TF signals, position info, strategy info

### 2.3 Collapse Behavior

- Panel collapse → **ẩn** cả bot buttons + bot panel
- Panel expand → **hiện** lại bot buttons + bot panel (nếu có bot active)

---

## 3. Shared Resources — Panel → Bot

Bot **KHÔNG** đọc GlobalVariable. Thay vào đó, dùng trực tiếp các globals/functions của Panel:

| Resource | Type | Description |
|----------|------|-------------|
| `g_panelLot` | `double` | Lot size tính từ Panel (avg lot BUY+SELL) |
| `g_cachedATR` | `double` | ATR value cached bởi Panel |
| `g_hasPos` | `bool` | Có position hay không |
| `g_isBuy` | `bool` | Position hiện tại là BUY |
| `InpMagic` | `int` | Magic number (shared, default 99999) |
| `InpDeviation` | `int` | Max slippage (shared, default 20) |
| `HasOwnPosition()` | function | Check position theo magic |
| `GetPositionPnL()` | function | Lấy PnL hiện tại |
| `GetTotalLots()` | function | Tổng lot của position |
| `MakeLabel()` | function | Tạo label object trên chart |

### 3.1 Lot Fallback

Nếu `g_panelLot == 0` (chưa có position) → Bot dùng `SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)`.

### 3.2 Auto-Pause (Large SL)

Panel phát hiện Large SL → gọi trực tiếp:
```mql5
CC_SetPaused(pauseTs);   // Candle Counter: pause với timestamp để auto-resume
TS_SetPaused(true);       // Trend Signal: pause boolean
```

**Không qua GlobalVariable.** Bot tự quản lý resume logic.

---

## 4. Naming Conventions

### 4.1 Code Prefix

| Bot | Global prefix | Function prefix | Object define prefix |
|-----|--------------|-----------------|---------------------|
| Candle Counter | `cc_` | `CC_` | `CC_OBJ_` |
| Trend Signal | `ts_` | `TS_` | `TS_OBJ_` |

### 4.2 Object Prefix (Chart)

```mql5
#define CC_PREFIX  "CCBot_"    // Candle Counter
#define TS_PREFIX  "TBot_"     // Trend Signal
```

Mỗi bot dùng prefix riêng → `ObjectsDeleteAll(0, XX_PREFIX)` xóa sạch.

### 4.3 Log Prefix

| Bot | Log prefix |
|-----|-----------|
| Candle Counter | `[CANDLE COUNTER]` |
| Trend Signal | `[TREND SIGNAL]` |
| Panel | `[PANEL]` hoặc `[GRID]` |

### 4.4 Display Names

Luôn dùng **tên đầy đủ** (không viết tắt) cho:
- Nút bot: "Candle Counter", "Trend Signal"
- Panel title: "Candle Counter Bot", "Trend Signal Bot"
- Input group: "══ Candle Counter Bot ══"
- Input labels: "Candle Counter: ...", "Trend Signal: ..."

Code variables/functions giữ viết tắt (`cc_`, `ts_`, `CC_`, `TS_`) cho gọn.

---

## 5. Input Parameters

### 5.1 Shared (Panel manages)

| Input | Type | Default | Nằm ở |
|-------|------|---------|--------|
| `InpDeviation` | `int` | `20` | Panel |
| `InpMagic` | `int` | `99999` | Panel |

### 5.2 Per-Bot

| Bot | Input | Default | Description |
|-----|-------|---------|-------------|
| Candle Counter | `InpCC_ATRMinMult` | `0.3` | Min candle range × ATR (0 = off) |
| Candle Counter | `InpCC_PauseBars` | `60` | Auto-resume after N bars (0 = manual) |
| Trend Signal | `InpTS_EMAFast` | `20` | EMA Fast period |
| Trend Signal | `InpTS_EMASlow` | `50` | EMA Slow period |

---

## 6. Chart Indicators — Bot Visibility

Bot **chỉ hiển thị** chart indicators (EMA lines, v.v.) khi **active**.
Khi bot tắt → xóa indicators khỏi chart để không gây nhiễu.

| Bot | Chart indicators | Show/Hide functions |
|-----|-----------------|-------------------|
| Candle Counter | (không có) | — |
| Trend Signal | EMA Fast + EMA Slow lines | `TS_ShowChartEMA()` / `TS_HideChartEMA()` |

Panel gọi Show/Hide trong `ToggleBot()`:
```mql5
// Turn off TS → hide EMA
TS_HideChartEMA();

// Turn on TS → show EMA
TS_ShowChartEMA();
```

---

## 7. UI Panel — Layout & Style

### 7.1 Bot Panel Position

| Constant | Value | Note |
|----------|-------|------|
| `BOT_PANEL_X` | `PX + PW + 5` | Ngay bên phải Panel chính |
| `BOT_PANEL_Y` | `PY` | Cùng top với Panel |
| `BOT_BTN_W` | `110` | Width nút bot |
| `BOT_BTN_H` | `24` | Height nút bot |
| `BOT_CONTENT_W` | `224` | Width content area |
| `BOT_CONTENT_Y` | `PY + BOT_BTN_H + 4` | Dưới hàng nút |

### 7.2 Color Scheme

```mql5
C'25,27,35'      // Background (COL_BG)
C'45,48,65'      // Border (COL_BORDER)
C'220,225,240'   // Primary text (COL_WHITE)
C'120,125,145'   // Dimmed text
C'0,180,100'     // Buy / Up / Profit (green)
C'220,80,80'     // Sell / Down / Loss (red)
C'50,50,70'      // Button inactive
C'0,100,60'      // Button active
```

### 7.3 Font

| Use | Font | Size |
|-----|------|------|
| Title | `Segoe UI Semibold` | 9 |
| Button | `Segoe UI Semibold` | 8 |
| Data / Signal | `Consolas` | 7-8 |

### 7.4 TF Display

8 TF tham khảo (W1 → M1):
- `▲` = EMA Fast > Slow (bullish)
- `▼` = EMA Fast < Slow (bearish)
- `[M15▲]` = Entry TF (trong ngoặc vuông)

---

## 8. Entry Logic — Per Bot

### 8.1 Entry Guard (all bots)

```mql5
if(!xx_enabled) return;
if(xx_paused) return;
if(HasOwnPosition()) return;
if(curBar == xx_lastSignalBar) return;
```

### 8.2 OpenTrade Pattern

```mql5
void XX_OpenTrade(bool isBuy)
{
   if(HasOwnPosition()) return;
   double lot = (g_panelLot > 0) ? g_panelLot : SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   // Normalize lot → OrderSend → DrawEntryArrow
}
```

SL = 0, TP = 0 → Panel manages trailing, DCA, auto TP.

---

## 9. Deployment

### 9.1 VPS

**Powernet VPS** (`103.122.221.141`) — 2 MT5 instances:

| Instance | Path |
|----------|------|
| Demo/Test | `C:\Users\administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06\MQL5\Experts\Trading Panel\` |
| EXNESS Real | `C:\MetaTrader 5 EXNESS Real\MQL5\Experts\Trading Panel\` |

| Item | Value |
|------|-------|
| Host | `103.122.221.141` |
| User | `administrator` |
| SSH password | (see conversation context) |
| SSH flags | `-o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o KbdInteractiveAuthentication=no` |
| Compile | `powershell -ExecutionPolicy Bypass -File C:\Temp\compile_tp.ps1` |

**Vietnix VPS** (`14.225.217.152`) — hiện tại không dùng, tạm ngưng deploy.

### 9.2 Deploy Flow

1. SCP upload 4 files: Panel `.mq5` + 3 `.mqh` → **cả 2 MT5 paths** trên Powernet
2. Compile via `C:\Temp\compile_tp.ps1` (compile 1 lần, cả 2 instance dùng chung binary? Hoặc compile riêng)
3. Git add -A → commit → push

### 9.3 Git

| Item | Value |
|------|-------|
| Repo | `github.com/TuanBT/metatrader` |
| Branch | `main` |

---

## 10. Adding a New Bot — Checklist

- [ ] Tạo `NewBot Strategy.mqh` trong `Trading Panel/`
- [ ] Prefix: code `nb_` / functions `NB_` / objects `NBBot_`
- [ ] Export đủ functions chuẩn (Init/Deinit/Tick/Timer/CreatePanel/...)
- [ ] Dùng Panel's shared resources (g_panelLot, g_cachedATR, HasOwnPosition, ...)
- [ ] **KHÔNG** đọc/ghi GlobalVariable
- [ ] `#include "NewBot Strategy.mqh"` trong Panel
- [ ] Thêm nút toggle + dispatch logic trong Panel
- [ ] Chart indicators: chỉ hiện khi bot active
- [ ] Display names đầy đủ (không viết tắt)
- [ ] Update `deploy.command` để upload file mới
- [ ] Update file này (thêm vào Section 1.2)

---

*Last updated: 2025-03*
