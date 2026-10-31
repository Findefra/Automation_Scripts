#!/usr/bin/env bash
# quarterly-public-exposure.sh
# Aggressive but practical public exposure sweep.
# Real lesson: Block Public Access is necessary but not sufficient. Policy and ACL drift still happen.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/public-exposure-$(date +%Y%m%d).csv"
echo "Service,Resource,RegionOrGlobal,Issue,Details" > "$REPORT"

# S3 buckets – public ACL or policy that allows * 
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read -r bucket; do
  # Public ACL check
  if aws s3api get-bucket-acl --bucket "$bucket" 2>/dev/null | grep -q 'AllUsers\|AuthenticatedUsers'; then
    echo "S3,$bucket,global,PUBLIC_ACL,Grants to AllUsers or AuthenticatedUsers" >> "$REPORT"
  fi
  # Crude public policy check (look for Principal "*")
  if aws s3api get-bucket-policy --bucket "$bucket" 2>/dev/null | grep -q '"Principal".*"[*]"'; then
    echo "S3,$bucket,global,PUBLIC_POLICY,Policy contains Principal *" >> "$REPORT"
  fi
done

# Public EBS snapshots
for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  aws ec2 describe-snapshots --region "$region" --owner-ids self --restorable-by-user-ids all \
    --query 'Snapshots[].SnapshotId' --output text 2>/dev/null | tr '\t' '\n' | while read -r snap; do
      [[ -n "$snap" ]] && echo "EC2-Snapshot,$snap,$region,PUBLIC_SNAPSHOT,Restorable by all" >> "$REPORT"
    done
done

# Public AMIs (owned by this account)
for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  aws ec2 describe-images --region "$region" --owners self --executable-users all \
    --query 'Images[].ImageId' --output text 2>/dev/null | tr '\t' '\n' | while read -r ami; do
      [[ -n "$ami" ]] && echo "EC2-AMI,$ami,$region,PUBLIC_AMI,Executable by all" >> "$REPORT"
    done
done

echo "Public exposure candidates: $REPORT"
echo "Any row in this file deserves an immediate owner assignment and risk acceptance or remediation."
