#!/usr/bin/env bash
# quarterly-ec2-stopped-orphans.sh
# Stopped instances and available volumes that have been sitting for > 30 days.
# Real lesson: People stop instances “for a week” and never come back. Volumes left behind after terminations are pure cost.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/ec2-orphans-$(date +%Y%m%d).csv"
echo "Region,Type,ResourceId,StateOrStatus,AgeDays,NameOrTags,SizeGB" > "$REPORT"
CUTOFF=$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)

for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  # Stopped instances
  aws ec2 describe-instances --region "$region" \
    --filters Name=instance-state-name,Values=stopped \
    --query 'Reservations[].Instances[].[InstanceId,State.Name,LaunchTime,Tags]' --output json | \
  jq -r --arg region "$region" --arg cutoff "$CUTOFF" '
    .[] | select(.[2] < $cutoff) |
    [$region, "StoppedInstance", .[0], .[1],
     ((now - (.[2] | fromdateiso8601)) / 86400 | floor),
     (.[3] // [] | map(select(.Key=="Name")) | .[0].Value // "no-name"),
     "n/a"] | @csv
  ' >> "$REPORT"

  # Available (unattached) volumes
  aws ec2 describe-volumes --region "$region" \
    --filters Name=status,Values=available \
    --query 'Volumes[].[VolumeId,State,CreateTime,Size,Tags]' --output json | \
  jq -r --arg region "$region" --arg cutoff "$CUTOFF" '
    .[] | select(.[2] < $cutoff) |
    [$region, "UnattachedVolume", .[0], .[1],
     ((now - (.[2] | fromdateiso8601)) / 86400 | floor),
     (.[4] // [] | map(select(.Key=="Name")) | .[0].Value // "no-name"),
     .[3]] | @csv
  ' >> "$REPORT"
done

echo "Stopped / unattached orphans: $REPORT"
