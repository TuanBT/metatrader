# Trading Panel & Bots — Shared Conventions

> Tài liệu chuẩn hóa mọi rule chung giữa **Expert Trading Panel** (Panel) và tất cả Bot.
> Khi tạo Bot mới hoặc sửa Bot cũ, **phải tuân thủ** các quy ước bên dưới.
> Khi thay đổi quy ước chung → **cập nhật TẤT CẢ** Bot + Panel cho đồng nhất.

---

## 1. Danh sách thành phần hiện tại

| Thành phần | File | Version | Prefix |
|-----------|------|---------|--------|
| Expert Trading Panel | `Expert Trading Panel.mq5` | v1.65 | `Bot_` |
| Trend Signal Bot | `Trend Signal Bot.mq5` | v1.10 | `TBot_` |
| Candle Counter Bot | `Candle Counter Bot.mq5` | v1.01 | `CCBot_` |
| Trend Signal Bot Test | `Trend Signal Bot Test.mq5` | — | `TBotT_` |

**Quy tắc prefix:** Mỗi Bot/Panel phải có prefix riêng để object name trên chart không đụng nhau.
Đặt tên: `#define BOT_PREFIX "XXBot_"` (viết tắt 2-4 ký tự + `Bot_`).

---

## 2. IPC — Giao tiếp giữa Panel và Bot

Panel và Bot giao tiếp qua **GlobalVariable** (GV) của MT5.

### 2.1 Lot Size — `TP_Lot_<Symbol>`

| Item | Detail |
|------|--------|
| **GV Key** | `"TP_Lot_" + _Symbol` |
| **Writer** | Panel — mỗi tick tính avg lot từ SL distance của cả BUY lẫn SELL |
| **Reader** | Tất cả Bot — đọc trong `UpdatePanel()` và `OpenTrade()` |
| **Fallback** | Nếu GV không tồn tại → Bot dùng `SYMBOL_VOLUME_MIN` |

**Code mẫu (Bot đọc lot):**
```mql5
double GetLotFromPanel()
{
   string gvName = "TP_Lot_" + _Symbol;
   if(GlobalVariableCheck(gvName))
      return GlobalVariableGet(gvName);
   return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
}
```

### 2.2 Auto-Pause — `TP_BotPause_<Symbol>`

| Item | Detail |
|------|--------|
| **GV Key** | `"TP_BotPause_" + _Symbol` |
| **Writer** | Panel — set `1.0` khi phát hiện Large SL (Grid DCA maxed + đóng lỗ) |
| **Reader** | Tất cả Bot — check mỗi tick trong `OnTick()` |
| **Condition** | `wasGridMax && !wasTrailProfit` → `GlobalVariableSet(key, 1.0)` |
| **Clear** | Bot tự clear khi user click **Start** → `GlobalVariableDel(key)` |

**Flow:**
```
Panel phát hiện Large SL → set GV = 1.0
    ↓
Bot đọc GV ≥ 1.0 → g_paused = true, g_botEnabled = false
    ↓
Bot hiển thị "⚠ PAUSED (Large SL)" (màu cam)
    ↓
User click Start → clear g_paused, delete GV, resume
```

**Code mẫu (Bot check pause):**
```mql5
// In OnTick():
string pauseKey = "TP_BotPause_" + _Symbol;
if(GlobalVariableCheck(pauseKey) && GlobalVariableGet(pauseKey) >= 1.0)
{
   if(!g_paused)
   {
      g_paused      = true;
      g_botEnabled  = false;
      PrintFormat("[BOT] ⚠ Paused by Panel (Large SL) on %s", _Symbol);
   }
   return;
}
```

**Code mẫu (Bot clear pause on Start):**
```mql5
// In OnChartEvent(), khi click Start:
if(g_paused)
{
   g_paused = false;
   GlobalVariableDel("TP_BotPause_" + _Symbol);
}
g_botEnabled = true;
```

---

## 3. Magic Number & Position Management

### 3.1 Magic Number

| Rule | Detail |
|------|--------|
| **Default** | `99999` cho tất cả Bot + Panel |
| **Input** | `input int InpMagic = 99999;` |
| **Mục đích** | Dùng chung magic = cả Panel lẫn Bot quản lý cùng 1 position |

### 3.2 HasPosition()

Tất cả Bot + Panel **phải** có hàm `HasPosition()` (hoặc `HasOwnPosition()`) check:
- `_Symbol` match
- `PositionGetInteger(POSITION_MAGIC) == InpMagic`

```mql5
bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }
   return false;
}
```

**Rule:** Bot **KHÔNG được** mở lệnh nếu `HasPosition() == true` → tối đa 1 position/symbol.

### 3.3 Entry Guard Pattern

Mỗi Bot phải có chuỗi kiểm tra trong `OnTick()`:
```
if(!g_botEnabled) return;       // Bot đang tắt
if(g_paused) return;            // Bị pause bởi Panel
if(HasPosition()) return;       // Đã có lệnh
if(curBar == g_lastSignalBar) return;  // Đã xử lý bar này (nếu dùng per-bar)
```

---

## 4. Input Parameters — Chuẩn chung

Mọi Bot **phải** có các input sau với **cùng tên và default**:

| Input | Type | Default | Mô tả |
|-------|------|---------|-------|
| `InpDeviation` | `int` | `20` | Max slippage (points) |
| `InpMagic` | `int` | `99999` | Magic Number |

Bot có thể thêm input riêng (ví dụ `InpEMAFast`, `InpATRMinMult`, `InpATRPeriod`...), nhưng **nhóm chung phải giữ nguyên** default.

> **Note:** Bot KHÔNG có risk inputs (lot, risk $, ATR mult). Lot hoàn toàn do Panel quản lý qua GV. Fallback = `SYMBOL_VOLUME_MIN`.

---

## 5. UI Panel — Layout & Style

### 5.1 Position

| Constant | Value | Note |
|----------|-------|------|
| `BOT_PX` | `15` | X offset (px từ trái) |
| `BOT_PY` | `25` | Y offset (px từ trên) |
| `BOT_ROW` | `22` | Chiều cao mỗi row |
| `BOT_PAD` | `6` | Padding bên trong panel |

Panel luôn neo góc trên-bên-trái chart (`CORNER_LEFT_UPPER`).

### 5.2 Width

| Component | Width | Note |
|-----------|-------|------|
| Panel (control panel) | `320` | Rộng vì có nhiều control |
| Bot đơn giản | `180` – `200` | Chỉ hiển thị info + vài nút |

### 5.3 Height — Collapsible

Mỗi Bot có 2 trạng thái panel:

| State | Constant | Typical |
|-------|----------|---------|
| Collapsed (mặc định) | `BOT_H` | `175` – `180` |
| Expanded (info visible) | `BOT_H_INFO` | `285` – `290` |

Toggle bằng nút `[?]` → thay đổi `BOT_H` object height + ẩn/hiện info labels.

### 5.4 Color Scheme (Bots)

Tất cả Bot **phải** dùng chung bảng màu dark theme:

```mql5
#define COL_BG       C'25,27,35'     // Background
#define COL_BORDER   C'45,48,65'     // Border
#define COL_WHITE    C'220,225,240'  // Primary text
#define COL_DIM      C'120,125,145'  // Dimmed/secondary text
#define COL_GREEN    C'0,180,100'    // Buy / Up / Profit
#define COL_RED      C'220,80,80'    // Sell / Down / Loss
#define COL_BTN_BG   C'50,50,70'    // Button background
#define COL_BTN_ON   C'0,100,60'    // Button ON state
#define COL_BTN_OFF  C'60,60,85'    // Button OFF state
```

> Panel (`Expert Trading Panel.mq5`) dùng bảng màu mở rộng hơn (thêm `COL_BUY`, `COL_SELL`, `COL_EDIT_BG`...) vì có nhiều control hơn.

### 5.5 Font

| Use | Font | Size |
|-----|------|------|
| Title | `Segoe UI Semibold` | 9 |
| Button | `Segoe UI Semibold` | 8 |
| Data / TF signal | `Consolas` | 7-8 |
| Info panel lines | `Consolas` | 8 |

**Info panel line spacing:** `16px` (khoảng cách giữa các dòng info).

### 5.6 Object Naming

```
{BOT_PREFIX}BG        — Panel background rectangle
{BOT_PREFIX}Title     — Title label
{BOT_PREFIX}Status    — Status text
{BOT_PREFIX}Start     — Start/Stop button
{BOT_PREFIX}ForceBuy  — Force BUY button
{BOT_PREFIX}ForceSell — Force SELL button
{BOT_PREFIX}PosInfo   — Position info label
{BOT_PREFIX}InfoBtn   — [?] toggle button
{BOT_PREFIX}InfoL1-L5 — Info panel lines (5 lines)
{BOT_PREFIX}Sig0-Sig7 — TF signal labels (up to 8)
```

### 5.7 Info Panel [?] Pattern

1. Nút `[?]` nằm cạnh Force BUY / Force SELL (24px width)
2. Default: collapsed (`g_infoExpanded = false`)
3. Click `[?]` → toggle `g_infoExpanded`
4. Expanded: resize BG height → `BOT_H_INFO`, show info labels via `ObjectSetInteger(OBJ_PERIOD, OBJ_ALL_PERIODS)`
5. Collapsed: resize BG height → `BOT_H`, hide info labels via `ObjectSetInteger(OBJ_PERIOD, OBJ_NO_PERIODS)`
6. Info labels update mỗi giây trong `OnTimer()`

### 5.8 TF Display — Multi-Timeframe Reference

Tất cả Bot hiển thị 8 TF tham khảo (W1 → M1) với EMA 20/50 direction:

| Symbol | Meaning |
|--------|---------|
| `▲` | EMA Fast > EMA Slow (bullish) |
| `▼` | EMA Fast < EMA Slow (bearish) |
| `[-]` hoặc `[▲]` | Entry TF (trong ngoặc vuông) |
| `▲` / `▼` (không ngoặc) | TF tham khảo |

TF display chỉ là **tham khảo** — không ảnh hưởng logic entry (trừ khi Bot dùng multi-TF entry như Trend Bot).

---

## 6. Behavior Rules

### 6.1 OnInit()

```mql5
int OnInit()
{
   // 1. Create indicator handles (ATR, EMA...)
   // 2. Set timer: EventSetTimer(1);
   // 3. Create panel: CreatePanel();
   // 4. (Optional) Add indicators to chart: ChartIndicatorAdd()
   return INIT_SUCCEEDED;
}
```

### 6.2 OnDeinit()

```mql5
void OnDeinit(const int reason)
{
   // 1. Delete all chart objects with prefix: ObjectsDeleteAll(0, BOT_PREFIX);
   // 2. Delete entry arrows: ObjectsDeleteAll(0, "EntryArrow_");
   // 3. Remove indicators from chart: iterate ChartIndicatorName, ChartIndicatorDelete
   // 4. Release handles: IndicatorRelease()
   // 5. Destroy timer: EventKillTimer();
}
```

### 6.3 OnTimer() — Mỗi 1 giây

```
1. Update multi-TF signal display (EMA direction arrows)
2. Update candle state (nếu Bot dùng candle counting)
3. Update panel info (position, lot, status)
4. Update info panel lines (nếu expanded)
```

### 6.4 OnTick() — Per-tick

```
1. Check g_botEnabled → return nếu false
2. Check TP_BotPause_ GV → pause nếu cần
3. HasPosition() → cập nhật g_hasPos
4. Nếu g_hasPos → return (ko mở thêm)
5. Signal logic (per-bar hoặc per-tick tùy Bot)
6. OpenTrade() nếu có signal
```

### 6.5 OnChartEvent()

```
1. Click Start/Stop → toggle g_botEnabled + handle unpause
2. Click Force BUY → OpenTrade(BUY) (bỏ qua signal check)
3. Click Force SELL → OpenTrade(SELL) (bỏ qua signal check)
4. Click [?] → toggle g_infoExpanded, resize panel
```

### 6.6 OpenTrade()

```mql5
void OpenTrade(bool isBuy)
{
   // 1. HasPosition() check → return nếu đã có
   // 2. Lấy lot: Panel GV → fallback SYMBOL_VOLUME_MIN
   // 3. Normalize lot (step, min, max)
   // 4. entry = isBuy ? SymbolInfoDouble(ASK) : SymbolInfoDouble(BID)
   // 5. sl = 0, tp = 0 (Panel manages)
   // 6. OrderSend(req, res)
   // 7. DrawEntryArrow() (nếu Bot hỗ trợ)
   // 8. Log: PrintFormat("[BOT] Opened %s ...", isBuy?"BUY":"SELL", ...)
}
```

### 6.7 Entry Arrow Pattern (Optional)

Bot có thể vẽ arrow lên chart khi vào lệnh:
```mql5
void DrawEntryArrow(bool isBuy, double price)
{
   string name = "EntryArrow_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? COL_GREEN : COL_RED);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}
```
Arrow code: `233` = arrow up, `234` = arrow down.

---

## 7. Log Format

Tất cả Bot dùng format thống nhất:

```
[BOT_NAME] Action detail on SYMBOL
```

| Bot | Log prefix |
|-----|-----------|
| Trend Signal Bot | `[TREND BOT]` |
| Candle Counter Bot | `[CC BOT]` |
| Panel | `[Panel]` hoặc `[GRID]` |

---

## 8. Deployment & Compile

### 8.1 VPS Info

| Item | Value |
|------|-------|
| Host | `103.122.221.141` |
| User | `administrator` |
| Password | `PNS1G3e7oc3h6PWJD4dsA` |
| MT5 Data Path | `C:\Users\administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06\MQL5\Experts\Trading Panel\` |
| MetaEditor | `C:\Program Files\MetaTrader 5 EXNESS\MetaEditor64.exe` |

### 8.2 Compile Scripts (at `C:\Temp\`)

| Script | Compiles |
|--------|----------|
| `compile_tp.ps1` | `Expert Trading Panel.mq5` |
| `compile_bot.ps1` | `Trend Signal Bot.mq5` |
| `compile_cc.ps1` | `Candle Counter Bot.mq5` |

### 8.3 Deploy Commands (macOS Terminal)

**Step 1: Upload file**
```bash
sshpass -p 'PNS1G3e7oc3h6PWJD4dsA' scp "path/to/File.mq5" \
  administrator@103.122.221.141:"C:\Users\administrator\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06\MQL5\Experts\Trading Panel\File.mq5"
```

**Step 2: Compile (sau khi upload xong)**
```bash
sleep 10 && sshpass -p 'PNS1G3e7oc3h6PWJD4dsA' ssh administrator@103.122.221.141 \
  'powershell -ExecutionPolicy Bypass -File C:\Temp\compile_xx.ps1'
```

> ⚠ **QUAN TRỌNG:** SCP và SSH **phải là 2 lệnh riêng**, chaining `&&` giữa scp và ssh sẽ fail permission denied.

### 8.4 Git

| Item | Value |
|------|-------|
| Repo | `https://github.com/TuanBT/metatrader.git` |
| Branch | `main` |
| Working dir | `/Users/tuan/GitProject/metatrader` |

**Commit message format:**
```
ComponentName vX.XX: Short description
```
Ví dụ: `Bot v1.10: Add entry arrows on chart`

---

## 9. Adding a New Bot — Checklist

Khi tạo Bot mới, copy từ Bot hiện tại và đảm bảo:

- [ ] **Prefix:** Đặt `BOT_PREFIX` mới, **không trùng** với Bot khác
- [ ] **Inputs:** Có đủ 6 input chuẩn (Section 4)
- [ ] **Magic:** Default `99999`
- [ ] **IPC:** Đọc `TP_Lot_` và `TP_BotPause_` GV (Section 2)
- [ ] **HasPosition():** Copy nguyên hàm
- [ ] **Entry Guard:** Đủ 4 check (Section 3.3)
- [ ] **Panel UI:** Theo chuẩn layout (Section 5)
- [ ] **Color scheme:** Copy nguyên bảng màu Bot (Section 5.4)
- [ ] **Info panel [?]:** 5 lines, toggle ẩn/hiện, cập nhật trong OnTimer()
- [ ] **TF Display:** 8 TF reference với EMA direction
- [ ] **OnDeinit cleanup:** Xóa tất cả objects + release handles
- [ ] **Log prefix:** Đặt `[XX BOT]` riêng
- [ ] **Compile script:** Tạo `C:\Temp\compile_xx.ps1` trên VPS
- [ ] **Cập nhật file này** (thêm vào Section 1)

---

## 10. Modifying Shared Behavior — Checklist

Khi thay đổi một rule chung (ví dụ: thêm GV mới, đổi color, đổi panel layout...):

- [ ] Cập nhật **TẤT CẢ** Bot + Panel
- [ ] Cập nhật file `CONVENTIONS.md` này
- [ ] Test trên từng Bot riêng
- [ ] Commit tất cả file đã sửa trong **cùng 1 commit**
- [ ] Deploy tất cả file đã sửa lên VPS

---

## 11. Panel-specific Features (Không áp dụng cho Bot)

Các tính năng chỉ có ở Panel, Bot **không** cần implement:

| Feature | Mô tả |
|---------|-------|
| Trailing SL | CLOSE / SWING / BE mode — Panel tự quản lý |
| Grid DCA | Delay cycle + candle filter — Panel tự quản lý |
| Auto TP | 50% close at 1 ATR — Panel tự quản lý |
| SL Mode | ATR / Lookback / Fixed — Panel tự quản lý |
| Risk calculator | Tính lot theo risk $ — Panel publish qua GV |

Bot chỉ cần: **Mở lệnh** (entry + SL). Panel sẽ tự quản lý trailing, DCA, partial TP.

---

*Last updated: 2025-01*
