#!/usr/bin/env bash
# cicd-ml-orchestrator.sh
# Helper that (1) triggers Image Builder pipelines and (2) launches short-lived Windows/RHEL instances from the latest baked AMIs for CI or ML jobs.
# Real-world note: Keep the “bake” and “run” stages separate. Never bake heavy ML frameworks into the base image used by CI runners.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ACTION="${1:-help}"          # build-windows | build-rhel | launch-windows | launch-rhel

case "$ACTION" in
  build-windows)
    PIPELINE_ARN=$(aws imagebuilder list-image-pipelines --region "$REGION" \
      --query "imagePipelineList[?contains(name,'Windows-CI-ML')].arn" --output text | head -1)
    aws imagebuilder start-image-pipeline-execution --region "$REGION" --image-pipeline-arn "$PIPELINE_ARN"
    echo "Windows image build started."
    ;;
  build-rhel)
    PIPELINE_ARN=$(aws imagebuilder list-image-pipelines --region "$REGION" \
      --query "imagePipelineList[?contains(name,'RHEL-CI-ML')].arn" --output text | head -1)
    aws imagebuilder start-image-pipeline-execution --region "$REGION" --image-pipeline-arn "$PIPELINE_ARN"
    echo "RHEL image build started."
    ;;
  launch-windows|launch-rhel)
    OS=$(echo "$ACTION" | cut -d- -f2)
    LATEST_AMI=$(aws ec2 describe-images --region "$REGION" --owners self \
      --filters "Name=tag:Role,Values=CI-CD-ML" "Name=tag:OS,Values=${OS^^}" "Name=state,Values=available" \
      --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)
    echo "Latest $OS AMI: $LATEST_AMI"
    # Re-use the launch logic from scripts 1 or 2, substituting $LATEST_AMI
    echo "Insert run-instances call here using $LATEST_AMI"
    ;;
  *)
    echo "Usage: $0 {build-windows|build-rhel|launch-windows|launch-rhel}"
    exit 1
    ;;
esac
