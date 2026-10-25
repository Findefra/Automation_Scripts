#!/usr/bin/env bash
# quarterly-lambda-runtimes.sh
# Lists functions on deprecated or soon-to-be-deprecated runtimes and functions not updated in 180+ days.
# Real lesson: Runtime deprecation is announced months in advance and still catches teams off guard.
# Common mistake: Only checking the runtime and ignoring the last modified date — many functions are abandoned.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/lambda-runtimes-$(date +%Y%m%d).csv"
echo "Region,FunctionName,Runtime,LastModified,AgeDays,PackageType,CodeSizeMB,Issues" > "$REPORT"

# Adjust this list as AWS publishes new deprecation dates
DEPRECATED_OR_SOON="python3.8 python3.9 nodejs14.x nodejs16.x java8 java8.al2 go1.x provided"

for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  aws lambda list-functions --region "$region" --output json 2>/dev/null | \
  jq -r --arg region "$region" --arg dep "$DEPRECATED_OR_SOON" '
    .Functions[] |
    . as $f |
    ($f.Runtime // "unknown") as $rt |
    ($f.LastModified) as $mod |
    (
      [
        (if ($dep | split(" ") | index($rt)) then "DeprecatedOrSoonRuntime" else empty end),
        (if ((now - ($mod | fromdateiso8601)) / 86400) > 180 then "NotModifiedIn180Days" else empty end)
      ] | join(";")
    ) as $issues |
    select($issues != "") |
    [
      $region,
      $f.FunctionName,
      $rt,
      $mod,
      ((now - ($mod | fromdateiso8601)) / 86400 | floor),
      ($f.PackageType // "Zip"),
      (($f.CodeSize // 0) / 1024 / 1024 | floor),
      $issues
    ] | @csv
  ' >> "$REPORT" || true
done

echo "Lambda runtime / staleness report: $REPORT"
echo "Anything on a deprecated runtime needs a migration ticket this quarter."
