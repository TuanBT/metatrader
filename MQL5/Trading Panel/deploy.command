#!/bin/bash
# Deploy Expert Trading Panel to VPS & Compile
# Usage: Double-click this file in Finder or run: ./deploy.command

VPS_HOST="103.122.221.141"
VPS_USER="administrator"
VPS_PASS="PNS1G3e7oc3h6PWJD4dsA"
LOCAL_FILE="$(dirname "$0")/Expert Trading Panel.mq5"
REMOTE_TEMP="C:\\Temp\\ExpertTradingPanel.mq5"
REMOTE_DEST="C:\\Users\\Administrator\\AppData\\Roaming\\MetaQuotes\\Terminal\\53785E099C927DB68A545C249CDBCE06\\MQL5\\Experts\\Trading Panel\\Expert Trading Panel.mq5"

echo "═══════════════════════════════════════════"
echo "  Deploy Expert Trading Panel to VPS"
echo "═══════════════════════════════════════════"

# Step 1: Upload
echo ""
echo "► Uploading..."
sshpass -p "$VPS_PASS" scp "$LOCAL_FILE" "${VPS_USER}@${VPS_HOST}:${REMOTE_TEMP}"
if [ $? -ne 0 ]; then
    echo "✗ Upload FAILED"
    read -p "Press Enter to close..."
    exit 1
fi
echo "✓ Upload OK"

# Step 2: Copy to MT5 folder
echo ""
echo "► Copying to MT5 Experts folder..."
sshpass -p "$VPS_PASS" ssh "${VPS_USER}@${VPS_HOST}" "copy /Y \"${REMOTE_TEMP}\" \"${REMOTE_DEST}\""
if [ $? -ne 0 ]; then
    echo "✗ Copy FAILED"
    read -p "Press Enter to close..."
    exit 1
fi
echo "✓ Copy OK"

# Step 3: Compile
echo ""
echo "► Compiling..."
sshpass -p "$VPS_PASS" ssh "${VPS_USER}@${VPS_HOST}" "powershell -File C:\\Temp\\compile_tp.ps1"
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
