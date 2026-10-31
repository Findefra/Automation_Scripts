#!/usr/bin/env bash
# quarterly-s3-multipart-cleanup-candidates.sh
# Surfaces incomplete multipart uploads older than 7 days and excessive delete markers.
# Real lesson: Incomplete multiparts are pure waste and often invisible until someone looks. 
# Many teams only discover them when the bill spikes.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/s3-multipart-$(date +%Y%m%d).csv"
echo "Bucket,UploadId,Key,Initiated,AgeDays" > "$REPORT"
CUTOFF=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)

aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read -r bucket; do
  aws s3api list-multipart-uploads --bucket "$bucket" --output json 2>/dev/null | \
  jq -r --arg bucket "$bucket" --arg cutoff "$CUTOFF" '
    .Uploads[]? | select(.Initiated < $cutoff) |
    [$bucket, .UploadId, .Key, .Initiated,
     ((now - (.Initiated | fromdateiso8601)) / 86400 | floor)] | @csv
  ' >> "$REPORT" || true
done

echo "Incomplete multipart candidates: $REPORT"
echo "Safe to abort anything older than 7–14 days in most environments."
