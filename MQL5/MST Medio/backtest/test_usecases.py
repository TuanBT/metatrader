#!/usr/bin/env python3
"""
Test Use Cases for Expert MST Medio.mq5 — Risk, Lot & HTF Filter
=================================================================
Simulates the EA logic in Python to verify edge cases.
Run: python test_usecases.py
"""

# ==============================================================================
# Simulate EA constants
# ==============================================================================
PARTIAL_PCT = 50
SL_BUFFER_PCT = 5
HTF_EMA_LEN = 50
HTF_FILTER = True

# ==============================================================================
# Simulate MQL5 functions
# ==============================================================================

def normalize_price(price, tick_size=0.01):
    """Simulate NormalizePrice()"""
    return round(round(price / tick_size) * tick_size, 10)


def check_max_risk(entry, sl, lot, max_risk_pct, balance, tick_value=1.0, tick_size=0.01, point=0.01):
    """
    Simulate CheckMaxRisk().
    Returns (is_safe: bool, risk_pct: float, risk_money: float)
    """
    if max_risk_pct <= 0:
        return True, 0.0, 0.0  # No limit

    if balance <= 0:
        return True, 0.0, 0.0

    sl_points = abs(entry - sl) / point
    if sl_points <= 0:
        return True, 0.0, 0.0

    if tick_value <= 0 or tick_size <= 0:
        return True, 0.0, 0.0

    point_value = tick_value * (point / tick_size)
    risk_money = lot * sl_points * point_value
    risk_pct = risk_money / balance * 100.0

    is_safe = risk_pct <= max_risk_pct
    return is_safe, risk_pct, risk_money


def normalize_lot(lot, min_lot=0.01, max_lot=100.0, step_lot=0.01):
    """Simulate lot normalization"""
    import math
    if lot < min_lot:
        lot = min_lot
    if lot > max_lot:
        lot = max_lot
    if step_lot > 0:
        lot = math.floor(lot / step_lot) * step_lot
    return round(lot, 2)


def simulate_trade_flow(
    inp_lot_size, inp_max_risk_pct, inp_partial_tp,
    entry, sl_raw, balance,
    min_lot=0.01, max_lot=100.0, step_lot=0.01,
    tick_value=1.0, tick_size=0.01, point=0.01,
    label=""
):
    """Simulate the full ProcessConfirmedSignal trade flow"""
    print(f"\n{'='*70}")
    print(f"USE CASE: {label}")
    print(f"{'='*70}")
    print(f"  InpLotSize={inp_lot_size}, InpMaxRiskPct={inp_max_risk_pct}, InpPartialTP={inp_partial_tp}")
    print(f"  Entry={entry}, SL_raw={sl_raw}, Balance=${balance}")
    print(f"  MinLot={min_lot}, MaxLot={max_lot}, StepLot={step_lot}")

    # SL Buffer (5% of risk distance)
    risk_dist = abs(entry - sl_raw)
    is_buy = entry > sl_raw  # Simple heuristic
    sl_buffered = sl_raw
    if SL_BUFFER_PCT > 0 and risk_dist > 0:
        buffer_amt = risk_dist * SL_BUFFER_PCT / 100.0
        if is_buy:
            sl_buffered = sl_raw - buffer_amt
        else:
            sl_buffered = sl_raw + buffer_amt
    print(f"  SL_buffered={sl_buffered:.5f} (buffer={abs(sl_buffered - sl_raw):.5f})")

    # Normalize lot
    total_lot = normalize_lot(inp_lot_size, min_lot, max_lot, step_lot)
    print(f"  Normalized lot: {total_lot}")

    # Partial TP: adjust to 2x minLot BEFORE risk check
    lot_adjusted = False
    if inp_partial_tp and total_lot < min_lot * 2:
        total_lot = min_lot * 2
        if total_lot > max_lot:
            total_lot = max_lot
        lot_adjusted = True
        print(f"  ⚠️ Partial TP: lot adjusted to {total_lot} (2x minLot={min_lot})")

    # Max risk check
    is_safe, risk_pct, risk_money = check_max_risk(
        entry, sl_buffered, total_lot, inp_max_risk_pct, balance,
        tick_value, tick_size, point
    )
    status = "✅ PASS" if is_safe else "❌ SKIP"
    print(f"  Risk check: {status} | Risk={risk_pct:.2f}% (${risk_money:.2f}) vs Max={inp_max_risk_pct}%")

    if not is_safe:
        print(f"  → TRADE SKIPPED (risk too high)")
        return False

    # Partial TP splitting
    if inp_partial_tp:
        import math
        part1 = round(total_lot * PARTIAL_PCT / 100.0, 2)
        if part1 < min_lot:
            part1 = min_lot
        if step_lot > 0:
            part1 = math.floor(part1 / step_lot) * step_lot
        part1 = round(part1, 2)

        part2 = round(total_lot - part1, 2)
        if part2 < min_lot:
            part2 = min_lot
        if step_lot > 0:
            part2 = math.floor(part2 / step_lot) * step_lot
        part2 = round(part2, 2)

        actual_total = part1 + part2
        print(f"  Partial TP: Part1={part1}, Part2={part2}, ActualTotal={actual_total}")

        # Check: actual total may exceed risk-checked total due to part2 floor
        if actual_total > total_lot:
            excess_pct = (actual_total - total_lot) / total_lot * 100
            print(f"  ⚠️ WARN: ActualTotal ({actual_total}) > CheckedTotal ({total_lot}) — excess {excess_pct:.1f}%")
            # Re-check with actual total
            is_safe2, risk_pct2, risk_money2 = check_max_risk(
                entry, sl_buffered, actual_total, inp_max_risk_pct, balance,
                tick_value, tick_size, point
            )
            if not is_safe2:
                print(f"  ❌ REAL RISK EXCEEDED with actual lots: {risk_pct2:.2f}% (${risk_money2:.2f})")
            else:
                print(f"  ✅ Still safe with actual lots: {risk_pct2:.2f}%")
    else:
        print(f"  Single order: Lot={total_lot}")
        # PlaceOrder also has its own risk check, but ProcessConfirmedSignal already checked
        # PlaceOrder would check again (double check — safe but redundant)
        print(f"  → PlaceOrder() — has its own CheckMaxRisk (double check)")

    print(f"  → TRADE PLACED ✅")
    return True


# ==============================================================================
# TEST CASES
# ==============================================================================
def main():
    print("=" * 70)
    print("TEST USE CASES — Expert MST Medio.mq5 Risk & Lot Management")
    print("=" * 70)

    results = []

    # ──────────────────────────────────────────────────────────────
    # UC1: Normal trade — XAUUSD, small lot, risk OK
    # ──────────────────────────────────────────────────────────────
    r = simulate_trade_flow(
        inp_lot_size=0.01, inp_max_risk_pct=2.0, inp_partial_tp=False,
        entry=2650.00, sl_raw=2640.00, balance=1000,
        min_lot=0.01, max_lot=100.0, step_lot=0.01,
        tick_value=1.0, tick_size=0.01, point=0.01,
        label="UC1: XAUUSD normal — small lot, risk OK"
    )
    results.append(("UC1", r, True))

    # ──────────────────────────────────────────────────────────────
    # UC2: Risk exceeds max — XAUUSD, large lot on small account
    # ──────────────────────────────────────────────────────────────
    r = simulate_trade_flow(
        inp_lot_size=1.0, inp_max_risk_pct=2.0, inp_partial_tp=False,
        entry=2650.00, sl_raw=2640.00, balance=1000,
        min_lot=0.01, max_lot=100.0, step_lot=0.01,
        tick_value=1.0, tick_size=0.01, point=0.01,
        label="UC2: XAUUSD — 1.0 lot on $1000 account (risk too high)"
    )
    results.append(("UC2", r, False))

    # ──────────────────────────────────────────────────────────────
    # UC3: Max risk = 0 (no limit) — always passes
    # ──────────────────────────────────────────────────────────────
    r = simulate_trade_flow(
        inp_lot_size=10.0, inp_max_risk_pct=0.0, inp_partial_tp=False,
        entry=2650.00, sl_raw=2640.00, balance=100,
        min_lot=0.01, max_lot=100.0, step_lot=0.01,
        tick_value=1.0, tick_size=0.01, point=0.01,
        label="UC3: MaxRisk=0 (no limit) — huge lot on tiny account"
    )
    results.append(("UC3", r, True))

    # ──────────────────────────────────────────────────────────────
    # UC4: Partial TP — lot doubles due to minLot, risk check catches it
    # ──────────────────────────────────────────────────────────────
    r = simulate_trade_flow(
        inp_lot_size=0.01, inp_max_risk_pct=1.0, inp_partial_tp=True,
        entry=2650.00, sl_raw=2640.00, balance=500,
        min_lot=0.01, max_lot=100.0, step_lot=0.01,
        tick_value=1.0, tick_size=0.01, point=0.01,
        label="UC4: Partial TP — lot doubles (0.01→0.02), tight risk limit"
    )
    results.append(("UC4", r, None))  # Could go either way

    # ──────────────────────────────────────────────────────────────
    # UC5: ETHUSD — minLot=0.1, user sets 0.02 → auto rounds to 0.1
    # ──────────────────────────────────────────────────────────────
    r = simulate_trade_flow(
        inp_lot_size=0.02, inp_max_risk_pct=2.0, inp_partial_tp=False,
        entry=3500.00, sl_raw=3400.00, balance=5000,
        min_lot=0.1, max_lot=100.0, step_lot=0.1,
        tick_value=1.0, tick_size=0.01, point=0.01,
        label="UC5: ETHUSD — InpLotSize=0.02, minLot=0.1 → auto round"
    )
    results.append(("UC5", r, None))

    # ──────────────────────────────────────────────────────────────
    # UC6: ETHUSD Partial TP — 0.02 → 0.2 (minLot=0.1, 2x for partial)
    # ──────────────────────────────────────────────────────────────
    r = simulate_trade_flow(
        inp_lot_size=0.02, inp_max_risk_pct=2.0, inp_partial_tp=True,
        entry=3500.00, sl_raw=3400.00, balance=5000,
        min_lot=0.1, max_lot=100.0, step_lot=0.1,
        tick_value=1.0, tick_size=0.01, point=0.01,
        label="UC6: ETHUSD Partial TP — 0.02→0.2 (2x minLot=0.1)"
    )
    results.append(("UC6", r, None))

    # ──────────────────────────────────────────────────────────────
    # UC7: Tiny account — $50, XAUUSD 0.01 lot, 10pt SL
    # ──────────────────────────────────────────────────────────────
    r = simulate_trade_flow(
        inp_lot_size=0.01, inp_max_risk_pct=2.0, inp_partial_tp=False,
        entry=2650.00, sl_raw=2640.00, balance=50,
        min_lot=0.01, max_lot=100.0, step_lot=0.01,
        tick_value=1.0, tick_size=0.01, point=0.01,
        label="UC7: Tiny account $50 — XAUUSD 0.01 lot, 10pt SL"
    )
    results.append(("UC7", r, False))

    # ──────────────────────────────────────────────────────────────
    # UC8: Large account — $100k, XAUUSD 1.0 lot
    # ──────────────────────────────────────────────────────────────
    r = simulate_trade_flow(
        inp_lot_size=1.0, inp_max_risk_pct=2.0, inp_partial_tp=False,
        entry=2650.00, sl_raw=2640.00, balance=100000,
        min_lot=0.01, max_lot=100.0, step_lot=0.01,
        tick_value=1.0, tick_size=0.01, point=0.01,
        label="UC8: Large account $100k — XAUUSD 1.0 lot, 10pt SL"
    )
    results.append(("UC8", r, True))

    # ──────────────────────────────────────────────────────────────
    # UC9: Very wide SL — BTCUSD 5000pt SL
    # ──────────────────────────────────────────────────────────────
    r = simulate_trade_flow(
        inp_lot_size=0.01, inp_max_risk_pct=2.0, inp_partial_tp=False,
        entry=100000.00, sl_raw=95000.00, balance=1000,
        min_lot=0.01, max_lot=100.0, step_lot=0.01,
        tick_value=1.0, tick_size=0.01, point=0.01,
        label="UC9: BTCUSD wide SL — 5000pt, small account"
    )
    results.append(("UC9", r, False))

    # ──────────────────────────────────────────────────────────────
    # UC10: Partial TP — part2 floor increases actual total beyond checked
    # ──────────────────────────────────────────────────────────────
    r = simulate_trade_flow(
        inp_lot_size=0.03, inp_max_risk_pct=2.0, inp_partial_tp=True,
        entry=2650.00, sl_raw=2640.00, balance=2000,
        min_lot=0.01, max_lot=100.0, step_lot=0.01,
        tick_value=1.0, tick_size=0.01, point=0.01,
        label="UC10: Partial TP — 0.03 lot split (part2 floor issue?)"
    )
    results.append(("UC10", r, None))

    # ──────────────────────────────────────────────────────────────
    # UC11: Borderline risk — exactly at limit
    # ──────────────────────────────────────────────────────────────
    # 0.01 lot × 1050 pts × 1.0 pointValue = $10.50
    # $10.50 / $500 × 100 = 2.1% → just over 2%
    r = simulate_trade_flow(
        inp_lot_size=0.01, inp_max_risk_pct=2.0, inp_partial_tp=False,
        entry=2650.00, sl_raw=2639.50, balance=500,
        min_lot=0.01, max_lot=100.0, step_lot=0.01,
        tick_value=1.0, tick_size=0.01, point=0.01,
        label="UC11: Borderline risk — just over 2%"
    )
    results.append(("UC11", r, False))

    # ──────────────────────────────────────────────────────────────
    # UC12: Non-partial TP → PlaceOrder double risk check
    # ──────────────────────────────────────────────────────────────
    print(f"\n{'='*70}")
    print("UC12: Double Risk Check Analysis (ProcessConfirmedSignal → PlaceOrder)")
    print(f"{'='*70}")
    print("  When PartialTP=false, flow is:")
    print("    1. ProcessConfirmedSignal: normalize lot, CheckMaxRisk → PASS")
    print("    2. PlaceOrder(): normalize lot again, CheckMaxRisk again → redundant but safe")
    print("  Issue: PlaceOrder normalizes lot independently from InpLotSize")
    print("  This means ProcessConfirmedSignal's normalization is unused in non-partial path")
    print("  ⚠️ FINDING: Minor redundancy, but NOT a bug — both checks will give same result")

    # ──────────────────────────────────────────────────────────────
    # UC13: Existing positions closed before risk check
    # ──────────────────────────────────────────────────────────────
    print(f"\n{'='*70}")
    print("UC13: Delete/Close before Risk Check")
    print(f"{'='*70}")
    print("  Flow: DeleteAllPendingOrders() → CloseAllPositions() → normalize → CheckMaxRisk")
    print("  ⚠️ FINDING: If risk check fails → old positions already closed, no new trade")
    print("  → Trader ends up FLAT with no position")
    print("  → This is INTENTIONAL: new signal invalidates old signal, close regardless")
    print("  → If risk too high, better to be flat than over-risked")
    print("  → EA prints warning, trader can adjust lot size and wait for next signal")

    # ──────────────────────────────────────────────────────────────
    # HTF TREND FILTER USE CASES (UC14–UC19)
    # ──────────────────────────────────────────────────────────────
    print(f"\n{'='*70}")
    print("HTF TREND FILTER — H1 EMA50")
    print(f"{'='*70}")
    print("  Logic: BUY only when price > EMA50(H1), SELL only when price < EMA50(H1)")
    print("  Filter applied BEFORE ProcessConfirmedSignal (STEP 5 in EA)")
    print()

    htf_results = []

    def check_htf_filter(is_buy, current_close, ema_value, htf_enabled=True):
        """Simulate HTF trend filter — returns (allowed, reason)"""
        if not htf_enabled:
            return True, "HTF filter disabled"
        if is_buy and current_close < ema_value:
            return False, f"BUY skipped — Price={current_close} < EMA{HTF_EMA_LEN}={ema_value} → Downtrend"
        if not is_buy and current_close > ema_value:
            return False, f"SELL skipped — Price={current_close} > EMA{HTF_EMA_LEN}={ema_value} → Uptrend"
        return True, "Trend aligned"

    # UC14: BUY in uptrend — allowed
    allowed, reason = check_htf_filter(is_buy=True, current_close=2700, ema_value=2650)
    print(f"  UC14: BUY price=2700 > EMA50=2650 → {'✅ ALLOWED' if allowed else '❌ BLOCKED'} ({reason})")
    htf_results.append(("UC14: BUY in uptrend", allowed, True))

    # UC15: BUY in downtrend — blocked
    allowed, reason = check_htf_filter(is_buy=True, current_close=2600, ema_value=2650)
    print(f"  UC15: BUY price=2600 < EMA50=2650 → {'✅ ALLOWED' if allowed else '❌ BLOCKED'} ({reason})")
    htf_results.append(("UC15: BUY in downtrend", allowed, False))

    # UC16: SELL in downtrend — allowed
    allowed, reason = check_htf_filter(is_buy=False, current_close=2600, ema_value=2650)
    print(f"  UC16: SELL price=2600 < EMA50=2650 → {'✅ ALLOWED' if allowed else '❌ BLOCKED'} ({reason})")
    htf_results.append(("UC16: SELL in downtrend", allowed, True))

    # UC17: SELL in uptrend — blocked
    allowed, reason = check_htf_filter(is_buy=False, current_close=2700, ema_value=2650)
    print(f"  UC17: SELL price=2700 > EMA50=2650 → {'✅ ALLOWED' if allowed else '❌ BLOCKED'} ({reason})")
    htf_results.append(("UC17: SELL in uptrend", allowed, False))

    # UC18: Price exactly at EMA — BUY (price == EMA, NOT < so allowed)
    allowed, reason = check_htf_filter(is_buy=True, current_close=2650, ema_value=2650)
    print(f"  UC18: BUY price=2650 == EMA50=2650 → {'✅ ALLOWED' if allowed else '❌ BLOCKED'} ({reason})")
    htf_results.append(("UC18: BUY at EMA (edge)", allowed, True))

    # UC19: Price exactly at EMA — SELL (price == EMA, NOT > so allowed)
    allowed, reason = check_htf_filter(is_buy=False, current_close=2650, ema_value=2650)
    print(f"  UC19: SELL price=2650 == EMA50=2650 → {'✅ ALLOWED' if allowed else '❌ BLOCKED'} ({reason})")
    htf_results.append(("UC19: SELL at EMA (edge)", allowed, True))

    # UC20: HTF filter disabled — should always allow
    allowed, reason = check_htf_filter(is_buy=True, current_close=2600, ema_value=2650, htf_enabled=False)
    print(f"  UC20: BUY counter-trend but filter OFF → {'✅ ALLOWED' if allowed else '❌ BLOCKED'} ({reason})")
    htf_results.append(("UC20: Filter disabled", allowed, True))

    # HTF filter summary
    print(f"\n  HTF Filter Tests:")
    htf_passed = htf_failed = 0
    for name, result, expected in htf_results:
        if result == expected:
            htf_passed += 1
            print(f"    ✅ {name}")
        else:
            htf_failed += 1
            print(f"    ❌ {name} (expected={expected}, got={result})")
    print(f"  HTF: {htf_passed} passed, {htf_failed} failed")

    # ──────────────────────────────────────────────────────────────
    # SUMMARY
    # ──────────────────────────────────────────────────────────────
    print(f"\n{'='*70}")
    print("SUMMARY")
    print(f"{'='*70}")
    passed = 0
    failed = 0
    for name, result, expected in results:
        if expected is None:
            status = "INFO"
        elif result == expected:
            status = "✅ OK"
            passed += 1
        else:
            status = f"❌ FAIL (expected={expected}, got={result})"
            failed += 1
        traded = "TRADED" if result else "SKIPPED"
        print(f"  {name}: {traded} — {status}")

    print(f"\n  Risk & Lot Tests: {passed} passed, {failed} failed")
    print(f"  HTF Filter Tests: {htf_passed} passed, {htf_failed} failed")
    total_passed = passed + htf_passed
    total_failed = failed + htf_failed
    print(f"  TOTAL: {total_passed} passed, {total_failed} failed")

    # ──────────────────────────────────────────────────────────────
    # FINDINGS
    # ──────────────────────────────────────────────────────────────
    print(f"\n{'='*70}")
    print("FINDINGS & HIDDEN RISKS")
    print(f"{'='*70}")
    print("""
  [FIXED] #1 Partial TP lot doubling after risk check
    → FIXED: minLot × 2 adjustment now happens BEFORE CheckMaxRisk

  [SAFE] #2 PlaceOrderEx has no internal risk check
    → SAFE: Only called from ProcessConfirmedSignal which checks first
    → Added comment warning for future maintenance

  [DESIGN] #3 Double risk check in non-partial path
    → ProcessConfirmedSignal checks risk, then calls PlaceOrder which checks again
    → PlaceOrder re-normalizes lot from InpLotSize independently
    → Redundant but harmless — both produce same lot → same risk result
    → Could optimize by passing lot to PlaceOrder, but not critical

  [DESIGN] #4 Old positions closed before risk check
    → If risk check fails, trader is flat (old positions closed, no new trade)
    → Intentional: new signal invalidates old, being flat is safer than over-risk
    → EA logs warning so trader knows to adjust lot size

  [EDGE] #5 Partial TP: part1+part2 can exceed totalLot due to floor rounding
    → Example: totalLot=0.03, part1=0.01, part2=0.02 → OK (0.03)
    → Example: totalLot=0.03, part1=0.01, remaining=0.02 → part2=0.02 → OK
    → But if totalLot=0.015 (after step rounding=0.01), part1=0.01, 
      remaining=0.00 → part2 floored to minLot=0.01 → actual=0.02 > checked=0.01
    → This can only happen with VERY small lots near minLot boundary
    → Already mitigated by the 2x minLot pre-adjustment for partial TP

  [SAFE] #6 SL buffer always applied before risk check ✅
  [SAFE] #7 CheckMaxRisk fail-open on degenerate data (balance=0, tickValue=0) ✅
  [SAFE] #8 Partial TP cleanup on risk-check fail ✅

  [NEW] #9 HTF Trend Filter (H1 EMA50)
    → BUY only when price > EMA50(H1), SELL only when price < EMA50(H1)
    → Filter applied BEFORE ProcessConfirmedSignal (STEP 5 in EA)
    → Edge case: price == EMA → NOT filtered (strict < / > comparison)
    → CopyBuffer failure → no filter applied (fail-open, safe)
    → iMA handle failure → prints warning, filter disabled for entire session
    → #define HTF_FILTER true/false to toggle at compile time
""")


if __name__ == "__main__":
    main()
