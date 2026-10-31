#!/usr/bin/env bash
# launch-rhel-ec2.sh
# Launches a hardened RHEL instance for CI/CD runners or ML training/inference.
# Real-world note: Prefer RHEL 9 (or Rocky/Alma if cost is a concern). Always enable FIPS and apply CIS Level 1/2 via Ansible or Image Builder later.
# Common failure: Missing NVIDIA drivers / CUDA on GPU instances → training jobs fail silently.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
INSTANCE_TYPE="${INSTANCE_TYPE:-m6i.xlarge}"          # g5.xlarge / g6.xlarge / p4 for serious ML
KEY_NAME="${KEY_NAME:-your-key-pair}"
SUBNET_ID="${SUBNET_ID:-subnet-0abc123}"
SG_ID="${SG_ID:-sg-0def456}"
IAM_PROFILE="${IAM_PROFILE:-EC2-RHEL-CI-ML-Role}"
ROOT_VOLUME_SIZE="${ROOT_VOLUME_SIZE:-80}"

# Latest RHEL 9 AMI from Red Hat
AMI_ID=$(aws ec2 describe-images --region "$REGION" \
  --owners 309956199498 \
  --filters "Name=name,Values=RHEL-9.*x86_64*" \
            "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)

echo "Using AMI: $AMI_ID"

USER_DATA=$(cat <<'EOF'
#!/bin/bash
set -e
dnf update -y
dnf install -y amazon-ssm-agent amazon-cloudwatch-agent git jq python3-pip
systemctl enable --now amazon-ssm-agent

# Optional: basic ML tooling (uncomment for GPU instances)
# dnf install -y gcc kernel-devel
# # NVIDIA driver + CUDA installation would follow here

# CIS-inspired quick hardening
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd
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
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=rhel-ci-ml-$(date +%Y%m%d)},{Key=Role,Value=CI-CD-or-ML},{Key=OS,Value=RHEL}]" \
  --metadata-options "HttpTokens=required,HttpPutResponseHopLimit=2" \
  --monitoring Enabled=true

echo "RHEL instance launch requested."
