# AWS Ops Scripts

Operational helpers. Some of these modify or delete resources — read each
script before running it.

| Script | Safety |
|---|---|
| `s3-backup-upload.sh` | Safe: creates a tar.gz and uploads to an S3 bucket |
| `jq-examples.sh` | Safe: read-only jq patterns for AWS CLI output |
| `find-unattached-ebs-volumes.sh` | Destructive: finds and deletes unattached EBS volumes |
| `account-cleanup.sh` | Highly destructive: irreversible full-account cleanup — use at your own risk |

## Usage

```bash
# Backup a directory to S3
./s3-backup-upload.sh

# jq patterns for AWS CLI JSON
./jq-examples.sh
```

Before running the destructive scripts, set the target profile and review the
resource filters inside the script:

```bash
export AWS_PROFILE=yourprofile
```
