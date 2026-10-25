#!/usr/bin/env bash
# quarterly-ec2-inventory.sh
# Full running instance + attached volume inventory with age, type, and missing required tags.
# Real lesson: The “temporary” instances and volumes created during incidents are the ones that live forever.

set -euo pipefail
export AWS_PAGER=""
REQUIRED_TAGS=("Environment" "Owner" "CostCenter" "Application")
REPORT="./quarterly-reports/ec2-inventory-$(date +%Y%m%d).csv"
echo "Region,InstanceId,InstanceType,State,LaunchTime,Name,MissingTags,VolumeIds,TotalVolumeGB" > "$REPORT"

for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  aws ec2 describe-instances --region "$region" --output json | \
  jq -r --arg region "$region" --argjson req "$(printf '%s\n' "${REQUIRED_TAGS[@]}" | jq -R . | jq -s .)" '
    .Reservations[].Instances[] |
    . as $i |
    ($i.Tags // [] | map({(.Key): .Value}) | add) as $tags |
    ($req - ($tags | keys)) as $missing |
    [
      $region,
      $i.InstanceId,
      $i.InstanceType,
      $i.State.Name,
      $i.LaunchTime,
      ($tags.Name // "no-name"),
      ($missing | join(";")),
      ($i.BlockDeviceMappings | map(.Ebs.VolumeId) | join(";")),
      "calc-later"
    ] | @csv
  ' >> "$REPORT"
done

echo "EC2 inventory written to $REPORT"
echo "Filter for MissingTags != empty and LaunchTime older than 180 days as first cleanup targets."
