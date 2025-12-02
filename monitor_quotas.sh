#!/bin/bash

# =============================================================================
# WEKA Quota Monitor & Slack Uploader (Portable)
# =============================================================================

# --- Configuration -----------------------------------------------------------
# Source Secrets (Token, Channel, Thread)
source /opt/WekaSlackBot/.secrets

MESSAGE_TITLE="Daily Quota Report - $(hostname)"

# Auth Token (Use the secure path we created)
export WEKA_TOKEN="/opt/WekaSlackBot/auth-token.json"

# Paths
SCRIPT_DIR="$(dirname "$0")"
UPLOADER_SCRIPT="$SCRIPT_DIR/slack_uploader.py"
REPORT_DIR="/tmp/weka_reports"
DATE_STR=$(TZ=America/New_York date "+%Y-%m-%d-%H:%M-%Z")
REPORT_FILE="$REPORT_DIR/quota_report_${DATE_STR}.txt"

# --- Prerequisites Check -----------------------------------------------------
if ! command -v weka > /dev/null; then
    echo "[ERROR] 'weka' CLI not found."
    exit 1
fi
if ! command -v jq > /dev/null; then
    echo "[ERROR] 'jq' not found. Please install it (sudo apt install jq)."
    exit 1
fi

# --- Execution ---------------------------------------------------------------
mkdir -p "$REPORT_DIR"
echo "Starting report generation for $DATE_STR..."

# 1. Data Collection (JSON)
# UPDATED: Added --all for quotas and changed fs list command
QUOTA_JSON=$(weka fs quota list --all --json)
FS_JSON=$(weka fs --json)
SNAPSHOT_JSON=$(weka fs snapshot -J)

# 2. Calculations (Global)
# Sum of all 'total_bytes' in quotas
TOTAL_QUOTA_USED=$(echo "$QUOTA_JSON" | jq '[.[] | .total_bytes] | add // 0')
# Sum of 'used_total' across all filesystems
TOTAL_FS_USED=$(echo "$FS_JSON" | jq '[.[] | .used_total] | add // 0')
# Sum of 'total_budget' across all filesystems
TOTAL_FS_CAPACITY=$(echo "$FS_JSON" | jq '[.[] | .total_budget] | add // 0')

# Global Snapshot Overhead
TOTAL_QUOTA_USED=${TOTAL_QUOTA_USED:-0}
TOTAL_FS_USED=${TOTAL_FS_USED:-0}
SNAPSHOT_OVERHEAD=$((TOTAL_FS_USED - TOTAL_QUOTA_USED))

# Helper to format bytes (IEC standard)
fmt_bytes() {
    numfmt --to=iec --suffix=B "$1"
}

# 3. Generate Report Header (Global)
echo "========================================" > "$REPORT_FILE"
echo " WEKA Quota & Snapshot Report" >> "$REPORT_FILE"
echo " Cluster: $(weka status | grep 'cluster' | awk '{print $2}')" >> "$REPORT_FILE"
echo " Date:    $DATE_STR" >> "$REPORT_FILE"
echo "========================================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "--- CLUSTER SUMMARY ---" >> "$REPORT_FILE"
echo "Total Filesystem Used: $(fmt_bytes $TOTAL_FS_USED) / $(fmt_bytes $TOTAL_FS_CAPACITY)" >> "$REPORT_FILE"
echo "Sum of Quota Usage:    $(fmt_bytes $TOTAL_QUOTA_USED)" >> "$REPORT_FILE"
echo "Total Snapshot Data:   $(fmt_bytes $SNAPSHOT_OVERHEAD) (...not in any Active FS ~ Estimate)" >> "$REPORT_FILE"
echo "-----------------------" >> "$REPORT_FILE"

# 4. Per-Filesystem Reports
echo "" >> "$REPORT_FILE"
echo "========================================" >> "$REPORT_FILE"
echo " DETAILED FILESYSTEM REPORTS" >> "$REPORT_FILE"
echo "========================================" >> "$REPORT_FILE"

# Iterate over each filesystem name
echo "$FS_JSON" | jq -r '.[].name' | while read FS_NAME; do
    echo "" >> "$REPORT_FILE"
    echo "########################################" >> "$REPORT_FILE"
    echo " FILESYSTEM: $FS_NAME" >> "$REPORT_FILE"
    echo "########################################" >> "$REPORT_FILE"

    # Filter Data for this FS
    # FS Data: Select the object where .name matches
    THIS_FS_DATA=$(echo "$FS_JSON" | jq --arg fs "$FS_NAME" '(.[] | select(.name == $fs)) // {}')
    # Quotas: Select objects where .fsName matches
    THIS_FS_QUOTAS=$(echo "$QUOTA_JSON" | jq --arg fs "$FS_NAME" '[.[] | select(.fsName == $fs)] // []')
    # Snapshots: Select objects where .filesystem matches
    THIS_FS_SNAPSHOTS=$(echo "$SNAPSHOT_JSON" | jq --arg fs "$FS_NAME" '[.[] | select(.filesystem == $fs)] // []')

    # --- Calculations ---
    # FS Usage/Cap
    THIS_USED=$(echo "$THIS_FS_DATA" | jq -r '.used_total // 0')
    THIS_CAP=$(echo "$THIS_FS_DATA" | jq -r '.total_budget // 0')
    
    # Quota Sum
    THIS_Q_USED=$(echo "$THIS_FS_QUOTAS" | jq '[.[] | .total_bytes] | add // 0')

    # Counts
    THIS_Q_COUNT=$(echo "$THIS_FS_QUOTAS" | jq 'length')
    THIS_SNAP_COUNT=$(echo "$THIS_FS_SNAPSHOTS" | jq 'length')

    # Overhead
    THIS_USED=${THIS_USED:-0}
    THIS_CAP=${THIS_CAP:-0}
    THIS_Q_USED=${THIS_Q_USED:-0}
    THIS_SNAP_OVERHEAD=$((THIS_USED - THIS_Q_USED))

    # Percentage
    if [ "$THIS_CAP" -gt 0 ]; then
        THIS_PCT=$(( 100 * THIS_USED / THIS_CAP ))
    else
        THIS_PCT=0
    fi

    # --- Section Summary ---
    echo "--- Summary ---" >> "$REPORT_FILE"
    echo "Used: $(fmt_bytes $THIS_USED) / $(fmt_bytes $THIS_CAP) ($THIS_PCT%)" >> "$REPORT_FILE"
    echo "Quota Sum: $(fmt_bytes $THIS_Q_USED)" >> "$REPORT_FILE"
    echo "Snap Data: $(fmt_bytes $THIS_SNAP_OVERHEAD) (...not in Active FS ~ Estimate)" >> "$REPORT_FILE"
    echo "Snapshots: $THIS_SNAP_COUNT" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    # --- Detailed Quota List ---
    echo "--- Quotas ---" >> "$REPORT_FILE"
    if [ "$THIS_Q_COUNT" -gt 0 ]; then
        weka fs quota list --all "$FS_NAME" >> "$REPORT_FILE" 2>&1
    else
        echo "(No quotas configured)" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"

    # --- Detailed Snapshot List ---
    echo "--- Snapshots ---" >> "$REPORT_FILE"
    if [ "$THIS_SNAP_COUNT" -gt 0 ]; then
        weka fs snapshot --filter "filesystem eq $FS_NAME" >> "$REPORT_FILE" 2>&1
    else
        echo "(No snapshots)" >> "$REPORT_FILE"
    fi
    echo "----------------------------------------" >> "$REPORT_FILE"
done

echo "Report generated: $REPORT_FILE"

# 5. Upload to Slack
echo "Uploading to Slack..."

# Build Command
CMD="python3 $UPLOADER_SCRIPT -f $REPORT_FILE -t $SLACK_TOKEN -c $SLACK_CHANNEL_ID -m \"$MESSAGE_TITLE\""

if [ -n "$SLACK_THREAD_TS" ]; then
    CMD="$CMD --thread_ts $SLACK_THREAD_TS"
fi

if [ "$SLACK_BROADCAST" == "true" ]; then
    CMD="$CMD --broadcast"
fi

# Execute
eval $CMD

if [ $? -eq 0 ]; then
    echo "Upload successful."
else
    echo "[ERROR] Upload failed."
    exit 1
fi

# 6. Cleanup (Optional)
# rm "$REPORT_FILE"