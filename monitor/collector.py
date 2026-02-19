"""
Trade Collector — Pulls trade data from MT5 server EA logs.

Reads EA logs, parses trade entries/exits/partial TPs/BE moves,
and saves structured trade records to local JSON for later analysis.
"""
import json
import os
import re
from datetime import datetime, date
from typing import Optional

from config import MT5_LOGS, DATA_DIR, STRATEGIES
from ssh_helper import ssh_cmd, ssh_powershell, read_remote_log


# ============================================================================
# DATA FILE
# ============================================================================
TRADES_FILE = os.path.join(DATA_DIR, "trades.json")
STATE_FILE  = os.path.join(DATA_DIR, "collector_state.json")


def load_trades() -> list[dict]:
    """Load existing trade records from local JSON."""
    if os.path.exists(TRADES_FILE):
        with open(TRADES_FILE, "r") as f:
            return json.load(f)
    return []


def save_trades(trades: list[dict]):
    """Save trade records to local JSON."""
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(TRADES_FILE, "w") as f:
        json.dump(trades, f, indent=2, default=str)


def load_state() -> dict:
    """Load collector state (last log date processed, etc.)."""
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, "r") as f:
            return json.load(f)
    return {"last_log_date": None, "last_line_count": 0}


def save_state(state: dict):
    """Save collector state."""
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


# ============================================================================
# LOG PARSING
# ============================================================================

# EA log patterns (Expert logs in MQL5/Logs/)
# Format: "HH:MM:SS.mmm  Expert Name (SYMBOLm,TF)  message"
RE_TRADE_OPEN = re.compile(
    r"(\d{2}:\d{2}:\d{2}\.\d+)\s+"
    r"(Expert \w[\w ]+)\s+\((\w+),(\w+)\)\s+"
    r".*(?:BUY|SELL)\s+.*(?:open|entry|order\s+sent|position\s+opened)",
    re.IGNORECASE,
)

RE_TRADE_CLOSE = re.compile(
    r"(\d{2}:\d{2}:\d{2}\.\d+)\s+"
    r"(Expert \w[\w ]+)\s+\((\w+),(\w+)\)\s+"
    r".*(?:close|TP hit|SL hit|position\s+closed|take\s+profit|stop\s+loss)",
    re.IGNORECASE,
)

RE_PARTIAL_TP = re.compile(
    r"(\d{2}:\d{2}:\d{2}\.\d+)\s+"
    r"(Expert \w[\w ]+)\s+\((\w+),(\w+)\)\s+"
    r".*(?:partial|close\s+\d+%)",
    re.IGNORECASE,
)

RE_BE_MOVE = re.compile(
    r"(\d{2}:\d{2}:\d{2}\.\d+)\s+"
    r"(Expert \w[\w ]+)\s+\((\w+),(\w+)\)\s+"
    r".*(?:breakeven|BE|move\s+SL\s+to)",
    re.IGNORECASE,
)

RE_SIGNAL = re.compile(
    r"(\d{2}:\d{2}:\d{2}\.\d+)\s+"
    r"(Expert \w[\w ]+)\s+\((\w+),(\w+)\)\s+"
    r".*(?:SIGNAL|signal\s+detected|entry\s+signal|🔔)",
    re.IGNORECASE,
)


def list_log_files() -> list[str]:
    """List available EA log files on server, sorted by date."""
    try:
        output = ssh_cmd(f'dir "{MT5_LOGS}" /b /od 2>nul')
        files = [f.strip() for f in output.split("\n") if f.strip().endswith(".log")]
        return files
    except Exception:
        return []


def pull_log(log_filename: str, tail: int = 500) -> str:
    """Pull a log file content from the server."""
    log_path = f"{MT5_LOGS}\\{log_filename}"
    return read_remote_log(log_path, tail=tail)


def parse_log_lines(lines: str, log_date: str) -> list[dict]:
    """Parse log lines into structured events."""
    events = []
    for line in lines.split("\n"):
        # Strip MT5 log prefix (2-char hash + spaces + level)
        cleaned = re.sub(r"^[A-Z]{2}\s+\d\s+", "", line.strip())
        if not cleaned:
            continue

        event = None

        # Check for trade open
        m = RE_TRADE_OPEN.search(cleaned)
        if m:
            event = {
                "type": "open",
                "time": f"{log_date} {m.group(1)}",
                "ea": m.group(2).strip(),
                "symbol": m.group(3),
                "timeframe": m.group(4),
                "raw": cleaned,
            }

        # Check for trade close (SL/TP)
        if not event:
            m = RE_TRADE_CLOSE.search(cleaned)
            if m:
                event = {
                    "type": "close",
                    "time": f"{log_date} {m.group(1)}",
                    "ea": m.group(2).strip(),
                    "symbol": m.group(3),
                    "timeframe": m.group(4),
                    "raw": cleaned,
                }

        # Check for partial TP
        if not event:
            m = RE_PARTIAL_TP.search(cleaned)
            if m:
                event = {
                    "type": "partial_tp",
                    "time": f"{log_date} {m.group(1)}",
                    "ea": m.group(2).strip(),
                    "symbol": m.group(3),
                    "timeframe": m.group(4),
                    "raw": cleaned,
                }

        # Check for BE move
        if not event:
            m = RE_BE_MOVE.search(cleaned)
            if m:
                event = {
                    "type": "be_move",
                    "time": f"{log_date} {m.group(1)}",
                    "ea": m.group(2).strip(),
                    "symbol": m.group(3),
                    "timeframe": m.group(4),
                    "raw": cleaned,
                }

        # Check for signal
        if not event:
            m = RE_SIGNAL.search(cleaned)
            if m:
                event = {
                    "type": "signal",
                    "time": f"{log_date} {m.group(1)}",
                    "ea": m.group(2).strip(),
                    "symbol": m.group(3),
                    "timeframe": m.group(4),
                    "raw": cleaned,
                }

        if event:
            events.append(event)

    return events


def collect(days_back: int = 7) -> dict:
    """
    Main collection function.
    Pulls recent EA logs, parses trade events, appends to local store.
    Returns summary of what was collected.
    """
    state = load_state()
    trades = load_trades()
    existing_count = len(trades)

    log_files = list_log_files()
    if not log_files:
        return {"status": "no_logs", "message": "No log files found on server"}

    # Process recent logs
    new_events = []
    for log_file in log_files[-days_back:]:
        log_date = log_file.replace(".log", "")
        # Format: YYYYMMDD → YYYY-MM-DD
        if len(log_date) == 8:
            log_date_fmt = f"{log_date[:4]}-{log_date[4:6]}-{log_date[6:]}"
        else:
            continue

        try:
            content = pull_log(log_file, tail=2000)
            events = parse_log_lines(content, log_date_fmt)
            new_events.extend(events)
        except Exception as e:
            print(f"  ⚠ Error reading {log_file}: {e}")

    # Deduplicate against existing trades (by time + type + ea + symbol)
    existing_keys = {
        f"{t.get('time', '')}|{t.get('type', '')}|{t.get('ea', '')}|{t.get('symbol', '')}"
        for t in trades
    }

    added = 0
    for event in new_events:
        key = f"{event['time']}|{event['type']}|{event['ea']}|{event['symbol']}"
        if key not in existing_keys:
            trades.append(event)
            existing_keys.add(key)
            added += 1

    # Save
    save_trades(trades)
    save_state({
        "last_collection": datetime.now().isoformat(),
        "last_log_date": log_files[-1].replace(".log", "") if log_files else None,
        "total_events": len(trades),
    })

    return {
        "status": "ok",
        "logs_scanned": min(days_back, len(log_files)),
        "new_events": added,
        "total_events": len(trades),
    }


if __name__ == "__main__":
    print("📡 Collecting trade data from MT5 server...")
    result = collect(days_back=14)
    print(f"✅ {result}")
