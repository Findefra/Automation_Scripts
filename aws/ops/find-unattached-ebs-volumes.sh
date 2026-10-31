#!/bin/bash
set -euo pipefail

REGION=${1:-"us-east-1"}
echo "🔍 Searching for unattached EBS volumes in $REGION..."

# Fetch all available (unattached) volumes
unattached_volumes=$(aws ec2 describe-volumes \
    --region "$REGION" \
    --filters "Name=status,Values=available" \
    --query "Volumes[*].VolumeId" \
    --output text)

if [ -z "$unattached_volumes" ] || [ "$unattached_volumes" = "None" ]; then
    echo "✅ No unattached volumes found."
    exit 0
fi

echo "⚠️ Found the following unattached volumes:"
echo "$unattached_volumes" | tr '\t' '\n'
echo "----------------------------------------"

# Loop and safely confirm deletion for each
for vol_id in $unattached_volumes; do
    read -rp "Delete volume $vol_id? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "🗑️ Deleting $vol_id..."
        aws ec2 delete-volume --region "$REGION" --volume-id "$vol_id"
    else
        echo "⏭️ Skipping $vol_id."
    fi
done
