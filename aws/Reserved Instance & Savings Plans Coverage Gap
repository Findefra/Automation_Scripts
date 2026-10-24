#!/usr/bin/env bash
# quarterly-ri-sp-coverage.sh
# High-level view of RI utilization and Savings Plans coverage.
# Real lesson: The official Cost Explorer recommendations are better than most home-grown logic.
# This script exists to force a quarterly human review and to catch accounts that never enable the right Cost Explorer views.

set -euo pipefail
export AWS_PAGER=""
REPORT_DIR="./quarterly-reports/$(date +%Y-Q%q)"
mkdir -p "$REPORT_DIR"

echo "Generating RI utilization (last 30 days)..."
aws ce get-reservation-utilization \
  --time-period Start=$(date -u -d '30 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output json > "$REPORT_DIR/ri-utilization.json"

echo "Generating Savings Plans coverage..."
aws ce get-savings-plans-coverage \
  --time-period Start=$(date -u -d '30 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY \
  --output json > "$REPORT_DIR/sp-coverage.json"

# Simple summary extraction
jq -r '
  .Total.UtilizationPercentage as $util |
  "RI Utilization (30d): \($util)%"
' "$REPORT_DIR/ri-utilization.json"

jq -r '
  .SavingsPlansCoverages[0].Coverage.CoveragePercentage as $cov |
  "Savings Plans Coverage (approx): \($cov)%"
' "$REPORT_DIR/sp-coverage.json" 2>/dev/null || echo "No Savings Plans data or permissions issue"

echo "Full JSON reports in $REPORT_DIR/"
echo "Next step: Compare against Cost Explorer RI/SP recommendations and open tickets for purchase or modification."
