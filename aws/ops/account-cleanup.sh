#!/usr/bin/env bash
set -euo pipefail
# AWS Account Cleanup Script - Use at your own risk!
# Set your profile if needed: export AWS_PROFILE=yourprofile

echo "=== AWS Account Cleanup - START ==="
echo "WARNING: This will delete resources irreversibly. Ctrl+C to abort."
sleep 5

# Get all regions
REGIONS=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

# Function to clean a region
clean_region() {
    local region=$1
    echo "=== Cleaning region: $region ==="
    aws configure set region "$region"

    # EC2 Instances, Volumes, Snapshots, Key Pairs, EIPs, etc.
    echo "Terminating EC2 instances..."
    for instance in $(aws ec2 describe-instances --query "Reservations[].Instances[].InstanceId" --output text); do
        aws ec2 terminate-instances --instance-ids "$instance" || true
    done
    aws ec2 wait instance-terminated --instance-ids $(aws ec2 describe-instances --query "Reservations[].Instances[].InstanceId" --output text) 2>/dev/null || true

    echo "Deleting EBS volumes..."
    for vol in $(aws ec2 describe-volumes --query "Volumes[?State!='in-use'].VolumeId" --output text); do
        aws ec2 delete-volume --volume-id "$vol" || true
    done

    echo "Releasing Elastic IPs..."
    for eip in $(aws ec2 describe-addresses --query "Addresses[].AllocationId" --output text); do
        aws ec2 release-address --allocation-id "$eip" || true
    done

    # S3 Buckets (global)
    echo "Emptying and deleting S3 buckets..."
    for bucket in $(aws s3api list-buckets --query "Buckets[].Name" --output text); do
        echo "Emptying $bucket..."
        aws s3 rm s3://"$bucket" --recursive || true
        aws s3api delete-bucket --bucket "$bucket" || true
    done

    # RDS (delete instances, clusters)
    echo "Deleting RDS instances..."
    for db in $(aws rds describe-db-instances --query "DBInstances[].DBInstanceIdentifier" --output text); do
        aws rds delete-db-instance --db-instance-identifier "$db" --skip-final-snapshot || true
    done

    # More services (expand as needed)
    echo "Deleting Lambda functions..."
    for func in $(aws lambda list-functions --query "Functions[].FunctionName" --output text); do
        aws lambda delete-function --function-name "$func" || true
    done

    echo "Deleting VPCs (after dependencies)..."
    # This is complex - handle security groups, subnets, IGWs, etc. first in real scenarios
    for vpc in $(aws ec2 describe-vpcs --query "Vpcs[?IsDefault==\`false\`].VpcId" --output text); do
        aws ec2 delete-vpc --vpc-id "$vpc" || true
    done

    # Add similar loops for: ELB/ALB/NLB, Auto Scaling, CloudFormation stacks, IAM roles/users (careful!), Route53, etc.
}

for region in $REGIONS; do
    clean_region "$region"
done

# Global / IAM cleanup (run last, carefully)
echo "=== Global Cleanup (IAM, etc.) ==="
# Example: Delete non-root IAM users, policies, etc. (highly sensitive)
echo "IAM cleanup skipped in this template - handle manually or extend script."

echo "=== Cleanup finished. Review AWS Cost Explorer for remnants. ==="
