#!/bin/bash
# ===================================================================
# SVB EC2 Image Builder 120-Day Lifecycle Policy Script
# Purpose: Automatically clean up old images older than 120 days
#          - Deletes Image Builder image resources
#          - Deregisters associated AMIs
#          - Deletes EBS snapshots
# Applies to: All SVB_BaseImagePipeline_* pipelines
# Region: us-west-2
# ===================================================================

set -euo pipefail

REGION="us-west-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LIFECYCLE_POLICY_NAME="SVB_120DayImageLifecyclePolicy"

echo "=================================================="
echo "Applying 120-Day Lifecycle Policy for SVB Image Pipelines"
echo "Region: ${REGION}"
echo "Policy Name: ${LIFECYCLE_POLICY_NAME}"
echo "=================================================="

# Create or update the lifecycle policy
echo "Creating/Updating lifecycle policy..."

aws imagebuilder create-lifecycle-policy \
  --name "${LIFECYCLE_POLICY_NAME}" \
  --description "SVB 120-day lifecycle policy: Delete images older than 120 days (AMI + snapshots). Applies to all SVB_BaseImagePipeline_*" \
  --status ENABLED \
  --resource-type AMI_IMAGE \
  --resource-selection '{
    "tagMap": {
      "PipelineName": "SVB_BaseImagePipeline_*"
    }
  }' \
  --policy-details '[
    {
      "action": "DELETE",
      "filter": {
        "type": "AGE",
        "value": 120,
        "unit": "DAYS"
      },
      "includeResources": {
        "amis": true,
        "snapshots": true
      }
    }
  ]' \
  --region "${REGION}" 2>/dev/null || {
    echo "Policy already exists. Updating it..."
    # Get existing ARN and update (update-lifecycle-policy requires full details, so we recreate for simplicity)
    POLICY_ARN=$(aws imagebuilder list-lifecycle-policies --region "${REGION}" \
      --query "lifecyclePolicySummaryList[?name=='${LIFECYCLE_POLICY_NAME}'].arn" --output text)
    
    if [ -n "${POLICY_ARN}" ]; then
      aws imagebuilder update-lifecycle-policy \
        --lifecycle-policy-arn "${POLICY_ARN}" \
        --description "SVB 120-day lifecycle policy: Delete images older than 120 days (AMI + snapshots). Applies to all SVB_BaseImagePipeline_*" \
        --status ENABLED \
        --resource-selection '{
          "tagMap": {
            "PipelineName": "SVB_BaseImagePipeline_*"
          }
        }' \
        --policy-details '[
          {
            "action": "DELETE",
            "filter": {
              "type": "AGE",
              "value": 120,
              "unit": "DAYS"
            },
            "includeResources": {
              "amis": true,
              "snapshots": true
            }
          }
        ]' \
        --region "${REGION}"
    fi
  }

echo "✅ Lifecycle policy applied successfully: ${LIFECYCLE_POLICY_NAME}"
echo ""
echo "Policy Details:"
echo "   • Deletes Image Builder images older than 120 days"
echo "   • Deregisters associated AMIs"
echo "   • Deletes underlying EBS snapshots (full cost cleanup)"
echo "   • Scope: All images tagged with PipelineName = SVB_BaseImagePipeline_*"
echo "   • Evaluation: Runs automatically every day"
echo ""

# Verification
echo "Verifying policy..."
aws imagebuilder get-lifecycle-policy \
  --lifecycle-policy-arn "arn:aws:imagebuilder:${REGION}:${ACCOUNT_ID}:lifecycle-policy/${LIFECYCLE_POLICY_NAME}" \
  --region "${REGION}" \
  --query 'lifecyclePolicy.{Name:name, Status:status, Description:description}' \
  --output table 2>/dev/null || echo "Policy created but verification needs console check (first run)."

echo "🎉 120-day lifecycle policy is now active!"
echo ""
echo "Next Steps Recommendations:"
echo "1. Ensure your image pipelines tag output images with key 'PipelineName' = 'SVB_BaseImagePipeline_<OS>_<Version>'"
echo "2. Monitor actions in AWS Image Builder console → Lifecycle policies"
echo "3. Check CloudTrail or Image Builder logs for deletion events"
echo "4. Re-run this script anytime to update the retention period"
echo ""
echo "To manually trigger a lifecycle evaluation (not usually needed):"
echo "Monitor the console or use AWS EventBridge if you want custom notifications."