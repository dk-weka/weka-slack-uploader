#!/bin/bash

# =============================================================================
# WEKA Quota Monitor & Slack Uploader (Portable)
# =============================================================================

# --- Configuration -----------------------------------------------------------
# Source Secrets (Token, Channel, Thread)
SECRETS_FILE="/opt/WekaSlackBot/.secrets"
if [ ! -r "$SECRETS_FILE" ]; then
    echo "[ERROR] Secrets file missing or unreadable: $SECRETS_FILE"
    exit 1
fi
source "$SECRETS_FILE"

MESSAGE_TITLE="Daily Quota Report - $(hostname)"

# Auth Token (Use the secure path we created)
export WEKA_TOKEN="/opt/WekaSlackBot/auth-token.json"

# Paths
SCRIPT_DIR="$(dirname "$0")"
UPLOADER_SCRIPT="$SCRIPT_DIR/slack_uploader.py"
REPORT_DIR="/tmp/weka_reports"
DATE_STR=$(TZ=America/New_York date "+%Y-%m-%d-%H:%M-%Z")

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
REPORT_FILE=$(mktemp "$REPORT_DIR/quota_report_XXXXXX.txt")
echo "Starting report generation for $DATE_STR..."
echo "Report file: $REPORT_FILE"

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

# Helper to format bytes (IEC standard) - Portable fallback
if command -v numfmt > /dev/null; then
    fmt_bytes() { numfmt --to=iec --suffix=B "$1"; }
else
    fmt_bytes() {
        echo "$1" | awk '{ split("B K M G T P E", v); s=1; while($1>1024 && s<7){$1/=1024; s++} printf "%.1f%sB", $1, v[s] }'
    }
fi

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
echo "Total Snapshot Data:   $(fmt_bytes $SNAPSHOT_OVERHEAD) (Exists only in snapshots ~ Estimated)" >> "$REPORT_FILE"
echo "-----------------------" >> "$REPORT_FILE"

# 4. Per-Filesystem Reports
echo "" >> "$REPORT_FILE"
echo "========================================" >> "$REPORT_FILE"
echo " DETAILED FILESYSTEM REPORTS" >> "$REPORT_FILE"
echo "========================================" >> "$REPORT_FILE"

# Iterate over each filesystem name
echo "$FS_JSON" | jq -r '.[].name' | while IFS= read -r FS_NAME; do
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
    
    if [ "$THIS_SNAP_COUNT" -gt 0 ]; then
        echo "Snap Data: $(fmt_bytes $THIS_SNAP_OVERHEAD) (Exists only in snapshots ~ Estimated)" >> "$REPORT_FILE"
    else
        echo "FS Overhead: $(fmt_bytes $THIS_SNAP_OVERHEAD)" >> "$REPORT_FILE"
    fi
    
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
        weka fs snapshot --filter "filesystem=$FS_NAME" >> "$REPORT_FILE" 2>&1
    else
        echo "(No snapshots)" >> "$REPORT_FILE"
    fi
    echo "----------------------------------------" >> "$REPORT_FILE"
done

echo "Report generated: $REPORT_FILE"

# 5. Upload to Slack
echo "Uploading to Slack..."
export SLACK_TOKEN

# Build Command Array (Secure)
CMD=("python3" "$UPLOADER_SCRIPT" "-f" "$REPORT_FILE" "-c" "$SLACK_CHANNEL_ID" "-m" "$MESSAGE_TITLE")

if [ -n "$SLACK_THREAD_TS" ]; then
    CMD+=("--thread_ts" "$SLACK_THREAD_TS")
fi

if [ "$SLACK_BROADCAST" == "true" ]; then
    CMD+=("--broadcast")
fi

# Execute
"${CMD[@]}"

if [ $? -eq 0 ]; then
    echo "Upload successful."
    
    # 6. Cleanup (Retention Policy: Keep last 7)
    echo "Cleaning up old reports (keeping last 7)..."
    ls -tp "$REPORT_DIR"/quota_report_*.txt 2>/dev/null | grep -v '/$' | tail -n +8 | xargs -I {} rm -- "{}"
else
    echo "[ERROR] Upload failed."
    exit 1
fi