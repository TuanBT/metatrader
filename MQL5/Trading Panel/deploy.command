#!/bin/bash
# Deploy Expert Trading Panel + Strategy includes to VPS & Compile
# Usage: Double-click this file in Finder or run: ./deploy.command

VPS_HOST="103.122.221.141"
VPS_USER="administrator"
VPS_PASS="PNS1G3e7oc3h6PWJD4dsA"
SCRIPT_DIR="$(dirname "$0")"
REMOTE_DIR="C:\\Users\\Administrator\\AppData\\Roaming\\MetaQuotes\\Terminal\\53785E099C927DB68A545C249CDBCE06\\MQL5\\Experts\\Trading Panel"
SSH_OPTS="-o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no"

FILES=(
    "Expert Trading Panel.mq5"
    "Candle Counter Strategy.mqh"
    "Trend Signal Strategy.mqh"
)

echo "═══════════════════════════════════════════"
echo "  Deploy Trading Panel to VPS"
echo "═══════════════════════════════════════════"

# Step 1: Upload all files
echo ""
FAIL=0
for f in "${FILES[@]}"; do
    echo "► Uploading $f..."
    sshpass -p "$VPS_PASS" scp $SSH_OPTS "$SCRIPT_DIR/$f" "${VPS_USER}@${VPS_HOST}:${REMOTE_DIR}\\$f"
    if [ $? -ne 0 ]; then
        echo "✗ Upload FAILED: $f"
        FAIL=1
    else
        echo "✓ $f"
    fi
done

if [ $FAIL -ne 0 ]; then
    read -p "Press Enter to close..."
    exit 1
fi

# Step 2: Compile
echo ""
echo "► Compiling..."
sshpass -p "$VPS_PASS" ssh $SSH_OPTS "${VPS_USER}@${VPS_HOST}" "powershell -ExecutionPolicy Bypass -File C:\\Temp\\compile_tp.ps1"
if [ $? -ne 0 ]; then
    echo "✗ Compile FAILED"
    read -p "Press Enter to close..."
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════"
echo "  ✓ Deploy complete! Reload EA on chart."
echo "═══════════════════════════════════════════"
echo ""
read -p "Press Enter to close..."
