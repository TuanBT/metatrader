# MetaTrader 5 — Trading Bots

## Tổng quan

Project quản lý Expert Advisors (EAs) cho MetaTrader 5. Bao gồm:
- **EA source code** (MQL5)
- **Remote backtest tools** (SSH to VPS)
- **Trade monitor** (giám sát + phân tích giao dịch)

## Cấu trúc

```
metatrader/
├── MQL5/                           ← Expert Advisors source code
│   ├── MST Medio/                  ← 2-Step Breakout Confirmation
│   ├── Reversal/                   ← Bollinger Band + RSI Mean Reversion
│   ├── M15 Impulse FAG Entry/      ← M15 Impulse strategy
│   └── Test/                       ← Test EA
├── backtest/                       ← SSH remote backtest tools
├── monitor/                        ← Trade monitor & analyzer
├── profiles/                       ← MT5 chart profiles (.chr)
└── README.md
```

## Server

| Item | Giá trị |
|------|---------|
| VPS | `103.122.221.141` (Windows Server 2019) |
| MT5 | MetaTrader 5 EXNESS, build 5592 |
| Account | Demo Exness-MT5Trial7 (433013546) |
| Timezone | GMT+7 |

## Chiến lược đang chạy

| EA | Symbol | TF | Lot | Backtest |
|----|--------|----|-----|----------|
| **Expert Reversal** | XAUUSDm | H1 | 0.02 | +13.6%/năm |
| **Expert MST Medio** | USDJPYm | H1 | 0.02 | +3.9%/năm |

---

## Cách dùng

### 1. Trade Monitor (giám sát giao dịch)

```bash
cd monitor

# Kiểm tra MT5 + EA có chạy không
python3 monitor.py status

# Thu thập dữ liệu trade từ server
python3 monitor.py collect

# Tạo báo cáo phân tích
python3 monitor.py report

# Chạy tất cả (status → collect → report)
python3 monitor.py full

# Xem log EA gần nhất
python3 monitor.py logs
```

Dữ liệu lưu tại `monitor/data/`:
- `trades.json` — Tất cả trade events
- `analysis_report.md` — Báo cáo phân tích mới nhất
- `analysis_state.json` — State để so sánh giữa các lần chạy

### 2. Backtest (chạy test chiến lược)

```bash
cd backtest

# Quick test — EURUSD × 4 EA × H1/M15
python3 mt5_quick_backtest.py

# Optimize tham số MST Medio + Reversal
python3 mt5_optimize_medio.py

# Full matrix test — nhiều cặp × timeframe × EA
python3 mt5_full_backtest.py
```

Kết quả backtest lưu trong `backtest/*.md`.

### 3. Upload + Compile EA

```bash
cd backtest

# Auto upload .mq5 → compile → backtest verify
python3 mt5_auto_backtest.py
```

### 4. Deploy EA lên chart (thủ công)

Files chart profile đã cấu hình sẵn:
- `profiles/chart01.chr` — XAUUSDm H1 + Expert Reversal
- `profiles/chart02.chr` — USDJPYm H1 + Expert MST Medio

Upload lên server:
```bash
sshpass -p "$MT5_SSH_PASS" scp profiles/*.chr profiles/order.wnd \
  "administrator@103.122.221.141:C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/53785E099C927DB68A545C249CDBCE06/MQL5/Profiles/Charts/Default/"
```

---

## Quản lý vốn (Money Management)

### Đã có trong EA code:

| Chiến lược | MST Medio | Reversal |
|------------|-----------|----------|
| Fixed lot (0.02) | ✅ | ✅ |
| Dynamic lot (% risk) | ✅ Tiered (0.75-2.0%) | ✅ Flat (2.0%) |
| Max risk per trade | ✅ (2.0%) | ✅ (5.0%) |
| Max SL risk guard | ✅ (30%) | ❌ |
| Max daily loss | ✅ (3%) | ✅ (5.0%) |
| Anti-martingale | ❌ | ❌ |
| Loss streak protect | ❌ | ❌ |
| Equity curve trading | ⚠️ Partial | ❌ |

### Cần bổ sung:
1. **Loss streak protection** — Giảm lot 50% sau 3 lệnh thua liên tiếp
2. **Equity curve trading** — Dừng/giảm khi equity < MA(20 trades)
3. **Anti-martingale** — Tăng lot sau chuỗi thắng

---

## Lưu ý kỹ thuật

- **EA logs UTF-16 LE** — Phải dùng PowerShell `Select-String` hoặc `Get-Content -Encoding Unicode`, KHÔNG dùng `type`/`findstr`
- **Chart profiles** — Cần CRLF line endings + `path=` field + `flags=343`
- **common.ini** — `Chart=1` trong `[Experts]` để cho phép EA trên chart
- **Task Scheduler** — MT5 khởi động qua task "MT5_Live" (cần thiết cho SSH non-interactive)