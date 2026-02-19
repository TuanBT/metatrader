"""
Health Check — Verify MT5 and EAs are running correctly.
"""
import re
from datetime import datetime

from config import MT5_LOGS, STRATEGIES
from ssh_helper import ssh_cmd, ssh_powershell, read_remote_log


def check_mt5_running() -> dict:
    """Check if MT5 terminal is running on the server."""
    try:
        output = ssh_cmd('tasklist /fi "IMAGENAME eq terminal64.exe" /nh 2>nul')
        if "terminal64.exe" in output:
            # Extract PID and memory
            parts = output.split()
            pid = parts[1] if len(parts) > 1 else "?"
            mem = parts[-2] if len(parts) > 2 else "?"
            return {"running": True, "pid": pid, "memory": mem}
        return {"running": False}
    except Exception as e:
        return {"running": None, "error": str(e)}


def check_ea_loaded() -> dict:
    """Check which EAs are currently loaded by reading today's terminal log."""
    today = datetime.now().strftime("%Y%m%d")
    # Terminal log (not EA log) has "loaded successfully" messages
    terminal_log = f"{MT5_LOGS}\\..\\..\\Logs\\{today}.log"
    try:
        content = read_remote_log(terminal_log, tail=200)
        loaded = []
        for line in content.split("\n"):
            if "loaded successfully" in line:
                # Extract EA name and symbol
                m = re.search(r"(Expert \w[\w ]+)\s+\((\w+),(\w+)\)", line)
                if m:
                    loaded.append({
                        "ea": m.group(1).strip(),
                        "symbol": m.group(2),
                        "timeframe": m.group(3),
                    })
        # Deduplicate — keep only the latest load per EA+symbol
        seen = {}
        for ea in loaded:
            key = f"{ea['ea']}|{ea['symbol']}"
            seen[key] = ea
        return {"loaded_eas": list(seen.values()), "today_log": today}
    except Exception as e:
        return {"loaded_eas": [], "error": str(e)}


def check_account_info() -> dict:
    """Get basic account info from terminal log."""
    today = datetime.now().strftime("%Y%m%d")
    log_path = f"{MT5_LOGS}\\..\\..\\Logs\\{today}.log"
    try:
        content = read_remote_log(log_path, tail=50, encoding="Unicode")
        info = {}
        for line in content.split("\n"):
            if "synchronized" in line:
                m = re.search(r"(\d+)\s+positions?,\s+(\d+)\s+orders?", line)
                if m:
                    info["positions"] = int(m.group(1))
                    info["orders"] = int(m.group(2))
            if "trading has been enabled" in line:
                info["trading_enabled"] = True
                if "hedging" in line:
                    info["mode"] = "hedging"
        return info
    except Exception:
        return {}


def full_health_check() -> dict:
    """Run all health checks."""
    print("🔍 Checking MT5 health...")

    mt5 = check_mt5_running()
    print(f"  MT5 Process: {'✅ Running' if mt5.get('running') else '❌ Not running'}")

    eas = check_ea_loaded()
    for ea in eas.get("loaded_eas", []):
        print(f"  EA: ✅ {ea['ea']} ({ea['symbol']}, {ea['timeframe']})")

    account = check_account_info()
    if account:
        print(f"  Account: {account.get('positions', '?')} positions, "
              f"{account.get('orders', '?')} orders, "
              f"{'hedging' if account.get('mode') == 'hedging' else '?'} mode")

    # Verify expected EAs
    expected = {f"{s['ea']}" for s in STRATEGIES.values()}
    loaded_names = {ea["ea"] for ea in eas.get("loaded_eas", [])}
    missing = expected - loaded_names
    if missing:
        print(f"  ⚠️ Missing EAs: {', '.join(missing)}")

    return {
        "mt5": mt5,
        "eas": eas,
        "account": account,
        "missing_eas": list(missing) if missing else [],
        "checked_at": datetime.now().isoformat(),
    }


if __name__ == "__main__":
    result = full_health_check()
    print(f"\n📋 Health check complete: {len(result.get('eas', {}).get('loaded_eas', []))} EAs loaded")
