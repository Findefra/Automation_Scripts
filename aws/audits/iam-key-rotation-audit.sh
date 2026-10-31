#!/bin/bash
set -euo pipefail

MAX_AGE_DAYS=90
CURRENT_SEC=$(date +%s)

echo "🛡️ Auditing IAM Access Key ages (Threshold: $MAX_AGE_DAYS days)..."
printf "%-20s %-25s %-12s %-10s\n" "USER" "KEY_ID" "AGE_DAYS" "STATUS"
echo "----------------------------------------------------------------------"

# Get all IAM users
users=$(aws iam list-users --query "Users[*].UserName" --output text)

for user in $users; do
    # Get access keys for this specific user
    keys_json=$(aws iam list-access-keys --user-name "$user" --output json)
    
    # Parse out metadata per key 
    echo "$keys_json" | jq -c '.AccessKeyMetadata[]' | while read -r key; do
        key_id=$(echo "$key" | jq -r '.AccessKeyId')
        status=$(echo "$key" | jq -r '.Status')
        create_date=$(echo "$key" | jq -r '.CreateDate')
        
        # Convert creation date string into Unix epoch timestamp
        # Works on both GNU/Linux and macOS implementations
        if date -d "$create_date" +%s &>/dev/null; then
            create_sec=$(date -d "$create_date" +%s)
        else
            create_sec=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${create_date//+00:00/Z}" +%s)
        fi
        
        # Calculate Delta days
        age_days=$(( (CURRENT_SEC - create_sec) / 86400 ))
        
        if [ "$age_days" -gt "$MAX_AGE_DAYS" ] && [ "$status" = "Active" ]; then
            printf "⚠️ \033[0;31m%-18s %-25s %-12s %-10s\033[0m\n" "$user" "$key_id" "$age_days" "$status"
        else
            printf "  %-18s %-25s %-12s %-10s\n" "$user" "$key_id" "$age_days" "$status"
        fi
    done
done
