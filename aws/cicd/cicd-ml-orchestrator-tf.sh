#!/usr/bin/env bash
# cicd-ml-orchestrator-tf.sh
# 1. Applies Terraform Image Builder pipelines (if needed)
# 2. Triggers a new image build
# 3. Optionally launches a test instance from the new AMI using the Terraform module

set -euo pipefail

ACTION="${1:-help}"
REGION="${AWS_REGION:-us-east-1}"

case "$ACTION" in
  apply-pipelines)
    ./apply-imagebuilder-tf.sh apply
    ;;
  build-windows)
    PIPELINE_ARN=$(aws imagebuilder list-image-pipelines --region "$REGION" \
      --query "imagePipelineList[?name=='windows-ci-ml-pipeline'].arn" --output text)
    aws imagebuilder start-image-pipeline-execution --image-pipeline-arn "$PIPELINE_ARN"
    echo "Windows build started"
    ;;
  build-rhel)
    PIPELINE_ARN=$(aws imagebuilder list-image-pipelines --region "$REGION" \
      --query "imagePipelineList[?name=='rhel-ci-ml-pipeline'].arn" --output text)
    aws imagebuilder start-image-pipeline-execution --image-pipeline-arn "$PIPELINE_ARN"
    echo "RHEL build started"
    ;;
  launch-test)
    # Example: call Terraform module to launch a short-lived test instance
    cd modules/ec2-ci-ml
    terraform apply -auto-approve \
      -var="os=rhel" \
      -var="instance_type=g5.xlarge" \
      -var="subnet_id=$SUBNET_ID" \
      -var="security_group_ids=[\"$SG_ID\"]" \
      -var="iam_instance_profile=EC2-RHEL-CI-ML-Role" \
      -var="key_name=$KEY_NAME"
    ;;
  *)
    echo "Usage: $0 {apply-pipelines|build-windows|build-rhel|launch-test}"
    exit 1
    ;;
esac
