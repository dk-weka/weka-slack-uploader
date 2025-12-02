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

# 2. Calculations (Bytes)
# Sum of all 'total_bytes' in quotas
TOTAL_QUOTA_USED=$(echo "$QUOTA_JSON" | jq '[.[] | .total_bytes] | add // 0')
# Sum of 'used_total' across all filesystems
TOTAL_FS_USED=$(echo "$FS_JSON" | jq '[.[] | .used_total] | add // 0')
# Sum of 'total_budget' across all filesystems
TOTAL_FS_CAPACITY=$(echo "$FS_JSON" | jq '[.[] | .total_budget] | add // 0')

# Snapshot Overhead (FS Used - Quota Used)
TOTAL_QUOTA_USED=${TOTAL_QUOTA_USED:-0}
TOTAL_FS_USED=${TOTAL_FS_USED:-0}
SNAPSHOT_OVERHEAD=$((TOTAL_FS_USED - TOTAL_QUOTA_USED))

# Calculate Usage Percentage
if [ "$TOTAL_FS_CAPACITY" -gt 0 ]; then
    USAGE_PERCENT=$(( 100 * TOTAL_FS_USED / TOTAL_FS_CAPACITY ))
else
    USAGE_PERCENT=0
fi

# Helper to format bytes (IEC standard)
fmt_bytes() {
    numfmt --to=iec --suffix=B "$1"
}

# 3. Generate Report Header
echo "========================================" > "$REPORT_FILE"
echo " WEKA Quota & Snapshot Report" >> "$REPORT_FILE"
echo " Cluster: $(weka status | grep 'cluster' | awk '{print $2}')" >> "$REPORT_FILE"
echo " Date:    $DATE_STR" >> "$REPORT_FILE"
echo "========================================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "--- Snapshot Summary per Filesystem ---" >> "$REPORT_FILE"
if [ -n "$SNAPSHOT_JSON" ]; then
    echo "$SNAPSHOT_JSON" | jq -r '.[] | .filesystem' | sort | uniq -c | while read count fs; do
        echo "Filesystem: $fs | Snapshots: $count" >> "$REPORT_FILE"
    done
else
    echo "No snapshots found." >> "$REPORT_FILE"
fi
echo "---------------------------------------" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "--- SUMMARY ---" >> "$REPORT_FILE"
echo "Total Filesystem Used: $(fmt_bytes $TOTAL_FS_USED) / $(fmt_bytes $TOTAL_FS_CAPACITY) ($USAGE_PERCENT%)" >> "$REPORT_FILE"
echo "Sum of Quota Usage:    $(fmt_bytes $TOTAL_QUOTA_USED)" >> "$REPORT_FILE"
echo "Est. Snapshot Data:    $(fmt_bytes $SNAPSHOT_OVERHEAD) (Excl. Active FS)" >> "$REPORT_FILE"
echo "-------------------" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 4. Append Detailed Lists
echo "--- Detailed Quota List ---" >> "$REPORT_FILE"
# UPDATED: Added --all
weka fs quota list --all >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "--- Filesystem List ---" >> "$REPORT_FILE"
# UPDATED: Changed to weka fs
weka fs >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "--- Detailed Snapshot List ---" >> "$REPORT_FILE"
weka fs snapshot >> "$REPORT_FILE"

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