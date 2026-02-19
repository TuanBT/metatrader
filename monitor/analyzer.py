"""
Trade Analyzer — Analyzes collected trade data and produces insights.

Reads from local trades.json, computes statistics, identifies patterns,
and recommends money management adjustments.
"""
import json
import os
from datetime import datetime
from typing import Optional
from collections import Counter

from config import DATA_DIR, STRATEGIES, MONEY_MANAGEMENT


TRADES_FILE = os.path.join(DATA_DIR, "trades.json")
REPORT_FILE = os.path.join(DATA_DIR, "analysis_report.md")
ANALYSIS_FILE = os.path.join(DATA_DIR, "analysis_state.json")


def load_trades() -> list[dict]:
    if os.path.exists(TRADES_FILE):
        with open(TRADES_FILE, "r") as f:
            return json.load(f)
    return []


def load_previous_analysis() -> Optional[dict]:
    """Load the last analysis for comparison."""
    if os.path.exists(ANALYSIS_FILE):
        with open(ANALYSIS_FILE, "r") as f:
            return json.load(f)
    return None


def save_analysis(analysis: dict):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(ANALYSIS_FILE, "w") as f:
        json.dump(analysis, f, indent=2, default=str)


# ============================================================================
# STATISTICS
# ============================================================================

def compute_stats(trades: list[dict]) -> dict:
    """Compute trading statistics from collected events."""
    if not trades:
        return {"total_events": 0, "message": "No trade data yet"}

    # Event counts
    type_counts = Counter(t.get("type", "unknown") for t in trades)

    # Per-EA breakdown
    ea_stats = {}
    for t in trades:
        ea = t.get("ea", "Unknown")
        symbol = t.get("symbol", "??")
        key = f"{ea} ({symbol})"
        if key not in ea_stats:
            ea_stats[key] = Counter()
        ea_stats[key][t.get("type", "unknown")] += 1

    # Time distribution (by hour)
    hour_dist = Counter()
    for t in trades:
        time_str = t.get("time", "")
        try:
            # Format: YYYY-MM-DD HH:MM:SS.mmm
            parts = time_str.split(" ")
            if len(parts) >= 2:
                hour = int(parts[1].split(":")[0])
                hour_dist[hour] += 1
        except (ValueError, IndexError):
            pass

    # Date range
    dates = set()
    for t in trades:
        time_str = t.get("time", "")
        if " " in time_str:
            dates.add(time_str.split(" ")[0])

    return {
        "total_events": len(trades),
        "event_types": dict(type_counts),
        "ea_breakdown": {k: dict(v) for k, v in ea_stats.items()},
        "hour_distribution": dict(sorted(hour_dist.items())),
        "date_range": {
            "first": min(dates) if dates else None,
            "last": max(dates) if dates else None,
            "days": len(dates),
        },
        "analyzed_at": datetime.now().isoformat(),
    }


# ============================================================================
# MONEY MANAGEMENT RECOMMENDATIONS
# ============================================================================

def recommend_money_management(stats: dict, prev_analysis: Optional[dict] = None) -> list[str]:
    """Generate money management recommendations based on trade data."""
    recommendations = []
    events = stats.get("total_events", 0)

    if events == 0:
        return ["⏳ No trade data yet. EAs need market hours to generate trades."]

    if events < 10:
        recommendations.append(
            f"📊 Only {events} events collected. Need at least 20-30 trades for meaningful analysis. "
            "Continue collecting data."
        )
        return recommendations

    # Analyze close types
    type_counts = stats.get("event_types", {})
    opens = type_counts.get("open", 0)
    closes = type_counts.get("close", 0)
    signals = type_counts.get("signal", 0)

    if opens > 0:
        # Check if BE moves are working
        be_moves = type_counts.get("be_move", 0)
        partial_tps = type_counts.get("partial_tp", 0)

        if partial_tps > 0 and be_moves == 0:
            recommendations.append(
                "⚠️ Partial TPs happening but no BE moves detected. "
                "Check if BE logic is triggering correctly."
            )

        if be_moves > opens * 0.8:
            recommendations.append(
                "📈 BE moves on >80% of trades. Strategy enters well. "
                "Consider: increase lot or widen TP target."
            )

        if be_moves < opens * 0.2 and opens > 10:
            recommendations.append(
                "📉 BE moves on <20% of trades. Most trades stopping out before 0.5R. "
                "Consider: reduce lot size, widen SL, or review entry timing."
            )

    # Per-EA check
    ea_breakdown = stats.get("ea_breakdown", {})
    for ea_key, counts in ea_breakdown.items():
        ea_opens = counts.get("open", 0)
        ea_closes = counts.get("close", 0)
        if ea_opens > 0 and ea_closes == 0:
            recommendations.append(
                f"🔄 {ea_key}: {ea_opens} opens but no closes yet. Positions may still be open."
            )

    # Compare with previous analysis
    if prev_analysis:
        prev_events = prev_analysis.get("total_events", 0)
        growth = events - prev_events
        if growth == 0:
            recommendations.append(
                "⚠️ No new events since last analysis. "
                "Check if MT5 is running and EAs are active."
            )
        else:
            recommendations.append(
                f"📊 +{growth} new events since last analysis."
            )

    # General strategy-specific wisdom
    recommendations.append(
        "\n💡 **Money Management Rules (built-in):**\n"
        "  1. **Fixed Lot**: Current $0.02 — safe for $500 account\n"
        "  2. **Loss Streak**: After 3 consecutive losses → reduce to $0.01\n"
        "  3. **Equity Curve**: If balance drops >5% → pause and review\n"
        "  4. **Win Streak**: After 5 consecutive wins → can increase to $0.03\n"
        "  5. **Max Daily Loss**: Stop trading if daily loss exceeds 3%"
    )

    return recommendations


# ============================================================================
# REPORT GENERATION
# ============================================================================

def generate_report() -> str:
    """Generate a Markdown analysis report."""
    trades = load_trades()
    stats = compute_stats(trades)
    prev = load_previous_analysis()
    recommendations = recommend_money_management(stats, prev)

    # Save current analysis for future comparison
    save_analysis(stats)

    # Build report
    lines = [
        "# Trade Monitor Report",
        f"\n**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"**Data range**: {stats.get('date_range', {}).get('first', 'N/A')} — {stats.get('date_range', {}).get('last', 'N/A')}",
        f"**Total events**: {stats.get('total_events', 0)}",
        "",
        "## Event Summary",
        "",
        "| Type | Count |",
        "|------|-------|",
    ]

    for etype, count in sorted(stats.get("event_types", {}).items()):
        lines.append(f"| {etype} | {count} |")

    lines.append("")
    lines.append("## Per-EA Breakdown")
    lines.append("")

    for ea_key, counts in stats.get("ea_breakdown", {}).items():
        lines.append(f"### {ea_key}")
        lines.append("")
        lines.append("| Event | Count |")
        lines.append("|-------|-------|")
        for etype, count in sorted(counts.items()):
            lines.append(f"| {etype} | {count} |")
        lines.append("")

    if stats.get("hour_distribution"):
        lines.append("## Trading Hours Distribution")
        lines.append("")
        lines.append("| Hour (GMT+7) | Events |")
        lines.append("|-------------|--------|")
        for hour, count in sorted(stats.get("hour_distribution", {}).items()):
            lines.append(f"| {hour:02d}:00 | {count} |")
        lines.append("")

    lines.append("## Recommendations")
    lines.append("")
    for rec in recommendations:
        lines.append(f"- {rec}")

    lines.append("")
    lines.append("## Active Strategies")
    lines.append("")
    for name, cfg in STRATEGIES.items():
        lines.append(f"- **{name}**: {cfg['ea']} on {cfg['symbol']} {cfg['timeframe']} "
                      f"(lot={cfg['lot']}, backtest: +{cfg['backtest_annual_return']}%/year)")

    report = "\n".join(lines)

    # Save report
    with open(REPORT_FILE, "w") as f:
        f.write(report)

    return report


if __name__ == "__main__":
    report = generate_report()
    print(report)
