#!/usr/bin/env bash
# quarterly-sg-review.sh
# Flags security groups with wide open ingress or references to non-existent groups.
# Real lesson: Focus on production and shared services first. Dev accounts can wait.

set -euo pipefail
REPORT="./quarterly-reports/sg-review-$(date +%Y%m%d).csv"
echo "Region,GroupId,GroupName,Issue,Details" > "$REPORT"

for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  aws ec2 describe-security-groups --region "$region" --output json | \
  jq -r --arg region "$region" '
    .SecurityGroups[] |
    . as $sg |
    (
      # Wide open ingress
      (.IpPermissions[]? | select(.IpRanges[]?.CidrIp == "0.0.0.0/0" or .Ipv6Ranges[]?.CidrIpv6 == "::/0") |
        [$region, $sg.GroupId, $sg.GroupName, "WIDE_OPEN", (.FromPort|tostring) + "-" + (.ToPort|tostring) + " from " + ((.IpRanges[0].CidrIp // .Ipv6Ranges[0].CidrIpv6) // "unknown")] | @csv
      ),
      # Self-referencing or potential stale (simplified)
      (.IpPermissions[]? | select(.UserIdGroupPairs != null) |
        [$region, $sg.GroupId, $sg.GroupName, "REFERENCES_OTHER_SG", (.UserIdGroupPairs[0].GroupId // "unknown")] | @csv
      )
    )
  ' >> "$REPORT"
done

echo "Review complete: $REPORT"
echo "Priority: Anything with 22, 3389, 5432, 3306, 27017 open to the world."
