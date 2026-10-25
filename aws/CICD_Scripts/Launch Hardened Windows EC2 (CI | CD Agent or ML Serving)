#!/usr/bin/env bash
# launch-windows-ec2.sh
# Launches a hardened Windows Server instance suitable for CI/CD runners or lightweight ML serving.
# Real-world note: Always use the latest AWS-provided Windows AMI and immediately apply CIS-style hardening via SSM or user-data.
# Common failure: Forgetting to set the correct IAM instance profile → SSM and CloudWatch never come online.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
INSTANCE_TYPE="${INSTANCE_TYPE:-m6i.xlarge}"          # Change to g5/g6 for GPU ML work
KEY_NAME="${KEY_NAME:-your-key-pair}"
SUBNET_ID="${SUBNET_ID:-subnet-0abc123}"
SG_ID="${SG_ID:-sg-0def456}"
IAM_PROFILE="${IAM_PROFILE:-EC2-Windows-CI-ML-Role}"
ROOT_VOLUME_SIZE="${ROOT_VOLUME_SIZE:-100}"

# Latest Windows Server 2022 AMI (adjust filter as needed)
AMI_ID=$(aws ec2 describe-images --region "$REGION" \
  --owners amazon \
  --filters "Name=name,Values=Windows_Server-2022-English-Full-Base-*" \
            "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)

echo "Using AMI: $AMI_ID"

USER_DATA=$(cat <<'EOF'
<powershell>
# Basic hardening + tools
Install-WindowsFeature -Name Web-Server,RSAT-AD-PowerShell -IncludeManagementTools
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
# Install SSM, CloudWatch agent, and common CI tools would go here
</powershell>
EOF
)

aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile Name="$IAM_PROFILE" \
  --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$ROOT_VOLUME_SIZE,\"VolumeType\":\"gp3\",\"Encrypted\":true,\"DeleteOnTermination\":true}}]" \
  --user-data "$USER_DATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=win-ci-ml-$(date +%Y%m%d)},{Key=Role,Value=CI-CD-or-ML},{Key=OS,Value=Windows}]" \
  --metadata-options "HttpTokens=required,HttpPutResponseHopLimit=2" \
  --monitoring Enabled=true

echo "Windows instance launch requested. Wait for SSM online before further configuration."
