#!/usr/bin/env bash
# quarterly-org-accounts.sh
# Full account inventory with status, joined method, and age.
# Real lesson: Suspended and “pending closure” accounts linger for months and still generate noise in Config, Security Hub, and billing.
# Common mistake: Treating the Organizations console list as complete — always pull via CLI and reconcile against your CMDB or account vending system.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/org-accounts-$(date +%Y%m%d).csv"
echo "AccountId,Name,Email,Status,JoinedMethod,JoinedTimestamp,AgeDays,ParentId,Issues" > "$REPORT"

aws organizations list-accounts --output json | \
jq -r '
  .Accounts[] |
  . as $a |
  [
    $a.Id,
    $a.Name,
    $a.Email,
    $a.Status,
    $a.JoinedMethod,
    $a.JoinedTimestamp,
    ((now - ($a.JoinedTimestamp | fromdateiso8601)) / 86400 | floor),
    "see-parents",
    (
      [
        (if $a.Status == "SUSPENDED" then "Suspended" else empty end),
        (if $a.Status == "PENDING_CLOSURE" then "PendingClosure" else empty end)
      ] | join(";")
    )
  ] | @csv
' >> "$REPORT"

# Optional: list parents for each account (OU structure)
echo "" >> "$REPORT"
echo "# OU / Parent mapping (run separately if needed)" >> "$REPORT"
aws organizations list-accounts --query 'Accounts[].Id' --output text | tr '\t' '\n' | while read -r acct; do
  parent=$(aws organizations list-parents --child-id "$acct" --query 'Parents[0].Id' --output text 2>/dev/null || echo "ROOT")
  echo "$acct,$parent" >> "$REPORT"
done

echo "Organizations account inventory: $REPORT"
echo "Action: Any SUSPENDED or PENDING_CLOSURE account older than 30 days should have a closure ticket."
