#!/usr/bin/env bash
set -euo pipefail
# Fetch all running EC2 Instance IDs and their Launch Times
echo "Listing running EC2 Instances:"

aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" \
    | jq -r '.Reservations[].Instances[] | "\(.InstanceId) was launched at \(.LaunchTime)"'
