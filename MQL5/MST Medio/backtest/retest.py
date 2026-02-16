#!/usr/bin/env python3
"""Retest with user's exact settings — compare MaxRisk 2%, 5%, 10%"""
import math

# User's settings
InpLotSize = 0.02
InpPartialTP = True
balance = 500.0
SL_BUFFER_PCT = 5
PARTIAL_PCT = 50

# (name, entry, sl_raw, min_lot, max_lot, step_lot, tick_value, tick_size, point)
pairs = [
    ('XAUUSDm',  2650.00, 2640.00,  0.01, 100, 0.01, 1.0,  0.01,    0.01),
    ('BTCUSDm',  100000,  98000,    0.01, 100, 0.01, 1.0,  0.01,    0.01),
    ('ETHUSDm',  3500,    3400,     0.10, 100, 0.10, 1.0,  0.01,    0.01),
    ('USOILm',   72.00,   70.50,    0.01, 100, 0.01, 1.0,  0.01,    0.01),
    ('EURUSDm',  1.0850,  1.0800,   0.01, 100, 0.01, 1.0,  0.00001, 0.00001),
    ('USDJPYm',  155.500, 154.800,  0.01, 100, 0.01, 0.65, 0.001,   0.001),
]

for max_risk in [2, 5, 10]:
    max_money = balance * max_risk / 100
    print("=" * 65)
    hdr = "MaxRisk=%d%% (max $%.0f) | Lot=%.2f | PartialTP=%s | Bal=$%.0f" % (
        max_risk, max_money, InpLotSize, InpPartialTP, balance)
    print(hdr)
    print("-" * 65)

    for name, entry, sl_raw, min_lot, max_lot, step_lot, tick_val, tick_size, point in pairs:
        is_buy = entry > sl_raw

        # SL buffer
        risk_dist = abs(entry - sl_raw)
        buffer_amt = risk_dist * SL_BUFFER_PCT / 100.0
        sl_buf = sl_raw - buffer_amt if is_buy else sl_raw + buffer_amt

        # Normalize lot
        lot = InpLotSize
        if lot < min_lot:
            lot = min_lot
        if lot > max_lot:
            lot = max_lot
        if step_lot > 0:
            lot = math.floor(lot / step_lot) * step_lot
        lot = round(lot, 2)

        # Partial TP: 2x minLot
        tag = ""
        if InpPartialTP and lot < min_lot * 2:
            lot = min_lot * 2
            if lot > max_lot:
                lot = max_lot
            tag = "*"

        # Risk calc
        sl_pts = abs(entry - sl_buf) / point
        point_value = tick_val * (point / tick_size)
        risk_money = lot * sl_pts * point_value
        risk_pct = risk_money / balance * 100.0

        is_safe = risk_pct <= max_risk
        icon = "OK" if is_safe else "SKIP"
        line = "  %-10s lot=%-5s%-2s risk=$%-8.2f (%6.1f%%) -> %s" % (
            name, lot, tag, risk_money, risk_pct, icon)
        print(line)

    print()
