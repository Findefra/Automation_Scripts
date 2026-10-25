#!/usr/bin/env bash
# create-rhel-imagebuilder-pipeline.sh
# Creates an EC2 Image Builder pipeline for a hardened RHEL image with CI tools and optional NVIDIA/CUDA support.
# Real-world note: Keep the recipe lean. Put heavy ML frameworks (PyTorch, TensorFlow, CUDA) in a second “ML-optimized” recipe that starts from this base.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
PIPELINE_NAME="RHEL-CI-ML-Base-$(date +%Y%m%d)"
RECIPE_NAME="RHEL-CI-ML-Recipe"
INFRA_NAME="RHEL-CI-ML-Infra"
DIST_NAME="RHEL-CI-ML-Dist"

aws imagebuilder create-infrastructure-configuration \
  --region "$REGION" \
  --name "$INFRA_NAME" \
  --instance-types m6i.large m6i.xlarge g5.xlarge \
  --instance-profile-name "ImageBuilder-Instance-Profile" \
  --subnet-id "subnet-0abc123" \
  --security-group-ids "sg-0def456" \
  --terminate-instance-on-failure true

aws imagebuilder create-distribution-configuration \
  --region "$REGION" \
  --name "$DIST_NAME" \
  --distributions "[{
    \"region\": \"$REGION\",
    \"amiDistributionConfiguration\": {
      \"name\": \"RHEL-CI-ML-{{ imagebuilder:buildDate }}\",
      \"amiTags\": {\"Role\": \"CI-CD-ML\", \"OS\": \"RHEL\"}
    }
  }]"

# Parent image = latest RHEL 9 from Red Hat
PARENT_AMI=$(aws ec2 describe-images --region "$REGION" --owners 309956199498 \
  --filters "Name=name,Values=RHEL-9.*x86_64*" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)

aws imagebuilder create-image-recipe \
  --region "$REGION" \
  --name "$RECIPE_NAME" \
  --semantic-version "1.0.0" \
  --parent-image "$PARENT_AMI" \
  --components "[
    {\"componentArn\": \"arn:aws:imagebuilder:$REGION:aws:component/update-linux/x.x.x\"},
    {\"componentArn\": \"arn:aws:imagebuilder:$REGION:aws:component/amazon-cloudwatch-agent-linux/x.x.x\"},
    {\"componentArn\": \"arn:aws:imagebuilder:$REGION:aws:component/amazon-ssm-agent-linux/x.x.x\"}
  ]" \
  --block-device-mappings "[{\"deviceName\": \"/dev/sda1\", \"ebs\": {\"volumeSize\": 80, \"volumeType\": \"gp3\", \"encrypted\": true}}]"

aws imagebuilder create-image-pipeline \
  --region "$REGION" \
  --name "$PIPELINE_NAME" \
  --image-recipe-arn "$(aws imagebuilder list-image-recipes --region $REGION --query "imageRecipeSummaryList[?name=='$RECIPE_NAME'].arn" --output text)" \
  --infrastructure-configuration-arn "$(aws imagebuilder list-infrastructure-configurations --region $REGION --query "infrastructureConfigurationSummaryList[?name=='$INFRA_NAME'].arn" --output text)" \
  --distribution-configuration-arn "$(aws imagebuilder list-distribution-configurations --region $REGION --query "distributionConfigurationSummaryList[?name=='$DIST_NAME'].arn" --output text)" \
  --status ENABLED \
  --schedule "scheduleExpression=cron(0 3 ? * SUN *),pipelineExecutionStartCondition=EXPRESSION_MATCH_ONLY"

echo "RHEL Image Builder pipeline created: $PIPELINE_NAME"
