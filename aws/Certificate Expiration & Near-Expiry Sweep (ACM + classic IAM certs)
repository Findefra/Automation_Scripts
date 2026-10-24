#!/usr/bin/env bash
# quarterly-cert-expiry.sh
# Surfaces ACM certificates expiring in the next 90 days and any remaining classic IAM server certificates.
# Real lesson: ACM private CAs and imported certs are the ones that bite. Always include both.

set -euo pipefail
export AWS_PAGER=""
DAYS=90
CUTOFF=$(date -u -d "+${DAYS} days" +%Y-%m-%dT%H:%M:%SZ)
REPORT="./quarterly-reports/cert-expiry-$(date +%Y%m%d).csv"
echo "Region,Type,ARN_or_Name,Domain,Expires,DaysLeft,Status,InUse" > "$REPORT"

# ACM certificates (all regions)
for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  aws acm list-certificates --region "$region" --certificate-statuses ISSUED \
    --query 'CertificateSummaryList[]' --output json 2>/dev/null | \
  jq -r --arg region "$region" --arg cutoff "$CUTOFF" '
    .[] | select(.NotAfter < $cutoff) |
    [$region, "ACM", .CertificateArn, (.DomainName // "n/a"), .NotAfter,
     ((.NotAfter | fromdateiso8601) - now | . / 86400 | floor), .Status, "check-listeners"] | @csv
  ' >> "$REPORT" || true
done

# Classic IAM server certificates (global, still appear in older accounts)
aws iam list-server-certificates --query 'ServerCertificateMetadataList[]' --output json | \
jq -r --arg cutoff "$CUTOFF" '
  .[] | select(.Expiration < $cutoff) |
  ["global", "IAM-ServerCert", .ServerCertificateName, (.ServerCertificateId // "n/a"),
   .Expiration, ((.Expiration | fromdateiso8601) - now | . / 86400 | floor), "EXPIRED_SOON", "legacy"] | @csv
' >> "$REPORT"

echo "Near-expiry certificates written to $REPORT"
echo "Immediate action: Any cert < 30 days needs an owner ticket today."
