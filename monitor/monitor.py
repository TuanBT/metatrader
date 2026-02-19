#!/usr/bin/env python3
"""
Trade Monitor CLI — Main entry point.

Usage:
    python monitor.py status    — Check MT5 + EA health
    python monitor.py collect   — Pull trade data from server
    python monitor.py report    — Generate analysis report
    python monitor.py full      — All of the above
    python monitor.py logs      — Show recent EA logs
"""
import sys
import os

# Ensure we can import sibling modules
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def cmd_status():
    """Check MT5 and EA health."""
    from health_check import full_health_check
    full_health_check()


def cmd_collect():
    """Collect trade data from MT5 server."""
    from collector import collect
    print("📡 Collecting trade data from MT5 server...")
    result = collect(days_back=14)
    print(f"  Logs scanned: {result.get('logs_scanned', 0)}")
    print(f"  New events:   {result.get('new_events', 0)}")
    print(f"  Total events: {result.get('total_events', 0)}")


def cmd_report():
    """Generate analysis report."""
    from analyzer import generate_report
    print("📊 Generating analysis report...\n")
    report = generate_report()
    print(report)


def cmd_logs():
    """Show recent EA logs from server."""
    from ssh_helper import read_remote_log
    from config import MT5_LOGS
    from datetime import datetime

    today = datetime.now().strftime("%Y%m%d")
    log_path = f"{MT5_LOGS}\\{today}.log"
    print(f"📋 Recent EA logs ({today}):\n")
    try:
        content = read_remote_log(log_path, tail=30)
        for line in content.split("\n"):
            # Strip MT5 log prefix
            import re
            cleaned = re.sub(r"^[A-Z]{2}\s+\d\s+", "", line.strip())
            if cleaned:
                print(f"  {cleaned}")
    except Exception as e:
        print(f"  ⚠️ Cannot read logs: {e}")


def cmd_full():
    """Run full pipeline: status → collect → report."""
    print("=" * 60)
    print("  TRADE MONITOR — Full Report")
    print("=" * 60)
    print()

    cmd_status()
    print()

    cmd_collect()
    print()

    cmd_report()


def cmd_help():
    print(__doc__)


COMMANDS = {
    "status": cmd_status,
    "collect": cmd_collect,
    "report": cmd_report,
    "full": cmd_full,
    "logs": cmd_logs,
    "help": cmd_help,
}


def main():
    if len(sys.argv) < 2:
        cmd_help()
        return

    cmd = sys.argv[1].lower()
    if cmd in COMMANDS:
        COMMANDS[cmd]()
    else:
        print(f"Unknown command: {cmd}")
        cmd_help()


if __name__ == "__main__":
    main()
