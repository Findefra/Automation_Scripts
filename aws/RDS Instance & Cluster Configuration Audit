#!/usr/bin/env bash
# quarterly-rds-config.sh
# Checks Multi-AZ, backup retention, deletion protection, encryption, and public accessibility.
# Real lesson: Publicly accessible RDS instances still appear in mature accounts. Deletion protection is frequently left off on non-prod.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/rds-config-$(date +%Y%m%d).csv"
echo "Region,Identifier,Engine,Class,MultiAZ,BackupRetention,DeletionProtection,StorageEncrypted,PubliclyAccessible,Issues" > "$REPORT"

for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  aws rds describe-db-instances --region "$region" --output json 2>/dev/null | \
  jq -r --arg region "$region" '
    .DBInstances[] |
    . as $db |
    [
      $region,
      $db.DBInstanceIdentifier,
      $db.Engine,
      $db.DBInstanceClass,
      $db.MultiAZ,
      $db.BackupRetentionPeriod,
      $db.DeletionProtection,
      $db.StorageEncrypted,
      $db.PubliclyAccessible,
      (
        [
          (if $db.PubliclyAccessible then "PubliclyAccessible" else empty end),
          (if $db.BackupRetentionPeriod < 7 then "LowBackupRetention" else empty end),
          (if $db.DeletionProtection == false then "NoDeletionProtection" else empty end),
          (if $db.StorageEncrypted == false then "Unencrypted" else empty end),
          (if $db.MultiAZ == false and ($db.Engine | test("aurora|postgres|mysql")) then "NoMultiAZ" else empty end)
        ] | join(";")
      )
    ] | @csv
  ' >> "$REPORT" || true
done

echo "RDS configuration report: $REPORT"
echo "Anything marked PubliclyAccessible or Unencrypted needs immediate attention."
