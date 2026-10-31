#!/usr/bin/env bash
#
# Installer for the once-per-24h RHEL login system report.
# Writes /usr/local/bin/login-system-report.sh and makes it executable.
#
set -euo pipefail

sudo tee /usr/local/bin/login-system-report.sh > /dev/null << 'EOF'
#!/bin/bash
# ================================================
# RHEL 10 Login Report - Runs once per 24 hours
# Includes dust, btop, htop, bleachbit, and glances
# ================================================

STAMP_FILE="$HOME/.cache/last-login-report.timestamp"
CURRENT_TIME=$(date +%s)
REPORT_INTERVAL=$((24 * 60 * 60))  # 24 hours in seconds

# Skip if run in last 24 hours
if [ -f "$STAMP_FILE" ]; then
    LAST_RUN=$(cat "$STAMP_FILE")
    if [ $((CURRENT_TIME - LAST_RUN)) -lt $REPORT_INTERVAL ]; then
        exit 0
    fi
fi

mkdir -p "$HOME/.cache"

clear
echo -e "\033[1;36m==================================================================\033[0m"
echo -e "\033[1;32m          Welcome to $(hostname) - Daily System Report\033[0m"
echo -e "\033[1;36m==================================================================\033[0m"
echo -e "Generated on: $(date)\n"

# 1. Colored Disk Usage Summary
echo -e "\033[1;33m=== 1. Disk Usage Summary (dust) ===\033[0m"
dust -d 7 -b / 2>/dev/null || du -sh /* 2>/dev/null | sort -hr | head -n 10
echo ""

# 2. Top Processes (htop + btop)
echo -e "\033[1;33m=== 2. Top Processes & Resource Usage ===\033[0m"
echo -e "\033[1;34m--- htop snapshot ---\033[0m"
htop -b -n 1 | head -n 40
echo ""

echo -e "\033[1;34m--- btop batch summary ---\033[0m"
timeout 8s btop --batch 2>/dev/null || echo "btop summary captured."
echo ""

# 3. Glances Full System Overview (NEW)
echo -e "\033[1;33m=== 3. System Overview (Glances) ===\033[0m"
glances --stdout cpu,mem,disk,net,load,uptime 2>/dev/null | head -n 30 || {
    echo "Glances not available, trying atop..."
    atop -1 2>/dev/null | head -n 25 || echo "No Glances or Atop summary available."
}
echo ""

# 4. BleachBit Cleanup Preview
echo -e "\033[1;33m=== 4. Cleanup Preview (BleachBit) ===\033[0m"
echo "Potential reclaimable space:"
bleachbit -p system.cache system.tmp apt.autoclean thumbnails 2>/dev/null | tail -n 12 || echo "BleachBit preview done."
echo ""

# 5. Top 5 Processes by Utilization
echo -e "\033[1;33m=== 5. Top 5 Processes by CPU & Memory ===\033[0m"
echo -e "\033[1mPID\t%CPU\t%MEM\tCOMMAND\033[0m"
ps aux --sort=-%cpu | awk 'NR<=6 {printf "%s\t%s\t%s\t%s\n", $2, $3, $4, $11}' | tail -n 5
echo ""

echo -e "\033[1;32m✅ Report complete. Next report will appear after 24 hours.\033[0m"
echo -e "\033[1;36m==================================================================\033[0m"

# Update timestamp
echo "$CURRENT_TIME" > "$STAMP_FILE"
EOF

sudo chmod +x /usr/local/bin/login-system-report.sh
