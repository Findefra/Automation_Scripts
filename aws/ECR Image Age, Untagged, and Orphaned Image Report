#!/usr/bin/env bash
# quarterly-ecr-image-age.sh
# Surfaces untagged images and images older than 90/180 days across all repositories.
# Real lesson: Untagged images are the #1 source of ECR storage bloat. Teams push by digest during CI and never clean up.
# Common mistake: Deleting by age alone without checking if the image is still referenced by a running task/service or a latest tag.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/ecr-image-age-$(date +%Y%m%d).csv"
echo "Region,Repository,ImageDigest,ImageTags,PushedAt,AgeDays,SizeMB,Status" > "$REPORT"
CUTOFF_90=$(date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ)
CUTOFF_180=$(date -u -d '180 days ago' +%Y-%m-%dT%H:%M:%SZ)

for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  repos=$(aws ecr describe-repositories --region "$region" --query 'repositories[].repositoryName' --output text 2>/dev/null || true)
  for repo in $repos; do
    aws ecr describe-images --region "$region" --repository-name "$repo" --output json 2>/dev/null | \
    jq -r --arg region "$region" --arg repo "$repo" --arg c90 "$CUTOFF_90" --arg c180 "$CUTOFF_180" '
      .imageDetails[] |
      . as $img |
      ($img.imageTags // []) as $tags |
      ($img.imagePushedAt) as $pushed |
      (
        if ($tags | length) == 0 then "UNTAGGED"
        elif $pushed < $c180 then "OLDER_THAN_180D"
        elif $pushed < $c90 then "OLDER_THAN_90D"
        else "OK"
        end
      ) as $status |
      select($status != "OK") |
      [
        $region,
        $repo,
        $img.imageDigest,
        ($tags | join("|")),
        $pushed,
        ((now - ($pushed | fromdateiso8601)) / 86400 | floor),
        (($img.imageSizeInBytes // 0) / 1024 / 1024 | floor),
        $status
      ] | @csv
    ' >> "$REPORT" || true
  done
done

echo "ECR image age/untagged report: $REPORT"
echo "Start with UNTAGGED images. Confirm they are not referenced by any ECS task definition or Lambda before deletion."
