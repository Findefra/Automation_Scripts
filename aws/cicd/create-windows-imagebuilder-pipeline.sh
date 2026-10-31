#!/usr/bin/env bash
# create-windows-imagebuilder-pipeline.sh
# Creates an EC2 Image Builder pipeline that produces a hardened Windows AMI with CI/CD + basic ML tooling.
# Real-world note: Image Builder is far superior to custom Packer + CodeBuild for enterprise Windows images because of native patching and SSM integration.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
PIPELINE_NAME="Windows-CI-ML-Base-$(date +%Y%m%d)"
RECIPE_NAME="Windows-CI-ML-Recipe"
INFRA_NAME="Windows-CI-ML-Infra"
DIST_NAME="Windows-CI-ML-Dist"

# Create infrastructure configuration
aws imagebuilder create-infrastructure-configuration \
  --region "$REGION" \
  --name "$INFRA_NAME" \
  --instance-types m6i.large m6i.xlarge \
  --instance-profile-name "ImageBuilder-Instance-Profile" \
  --subnet-id "subnet-0abc123" \
  --security-group-ids "sg-0def456" \
  --terminate-instance-on-failure true

# Create distribution configuration (share to required accounts/OUs)
aws imagebuilder create-distribution-configuration \
  --region "$REGION" \
  --name "$DIST_NAME" \
  --distributions "[{
    \"region\": \"$REGION\",
    \"amiDistributionConfiguration\": {
      \"name\": \"Windows-CI-ML-{{ imagebuilder:buildDate }}\",
      \"amiTags\": {\"Role\": \"CI-CD-ML\", \"OS\": \"Windows\"}
    }
  }]"

# Create recipe (simplified – add your components for hardening, agents, CUDA, etc.)
aws imagebuilder create-image-recipe \
  --region "$REGION" \
  --name "$RECIPE_NAME" \
  --semantic-version "1.0.0" \
  --parent-image "arn:aws:imagebuilder:$REGION:aws:image/windows-server-2022-english-full-base-x86/x.x.x" \
  --components "[
    {\"componentArn\": \"arn:aws:imagebuilder:$REGION:aws:component/update-windows/x.x.x\"},
    {\"componentArn\": \"arn:aws:imagebuilder:$REGION:aws:component/amazon-cloudwatch-agent-windows/x.x.x\"}
  ]" \
  --block-device-mappings "[{\"deviceName\": \"/dev/sda1\", \"ebs\": {\"volumeSize\": 100, \"volumeType\": \"gp3\", \"encrypted\": true}}]"

# Create and start the pipeline
aws imagebuilder create-image-pipeline \
  --region "$REGION" \
  --name "$PIPELINE_NAME" \
  --image-recipe-arn "$(aws imagebuilder list-image-recipes --region $REGION --query "imageRecipeSummaryList[?name=='$RECIPE_NAME'].arn" --output text)" \
  --infrastructure-configuration-arn "$(aws imagebuilder list-infrastructure-configurations --region $REGION --query "infrastructureConfigurationSummaryList[?name=='$INFRA_NAME'].arn" --output text)" \
  --distribution-configuration-arn "$(aws imagebuilder list-distribution-configurations --region $REGION --query "distributionConfigurationSummaryList[?name=='$DIST_NAME'].arn" --output text)" \
  --status ENABLED \
  --schedule "scheduleExpression=cron(0 2 ? * SUN *),pipelineExecutionStartCondition=EXPRESSION_MATCH_ONLY"

echo "Windows Image Builder pipeline created: $PIPELINE_NAME"
echo "Trigger a build with: aws imagebuilder start-image-pipeline-execution --image-pipeline-arn <arn>"
