#!/bin/bash
set -euo pipefail

BUCKET_NAME="my-company-backup-bucket-2026"
BACKUP_DIR="/var/www/html"
OUTPUT_FILE="/tmp/backup-$(date +%F).tar.gz"

echo "Creating local archive..."
tar -czf "$OUTPUT_FILE" "$BACKUP_DIR"

echo "Uploading archive to Amazon S3..."
aws s3 cp "$OUTPUT_FILE" "s3://$BUCKET_NAME/backups/$(basename "$OUTPUT_FILE")"

echo "Cleaning up local temporary file..."
rm -f "$OUTPUT_FILE"
