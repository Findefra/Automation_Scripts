#!/bin/bash
set -euo pipefail

LOG_GROUP=${1:-""}
STREAM_PREFIX=${2:-""} # Optional stream filtering

if [ -z "$LOG_GROUP" ]; then
    echo "❌ Error: Please specify a CloudWatch log group name."
    echo "Usage: $0 /aws/lambda/my-function-name [stream_prefix]"
    exit 1
fi

echo "👀 Tailing CloudWatch Log Group: $LOG_GROUP..."

# Validates standard dependencies
command -v aws >/dev/null 2>&1 || { echo "AWS CLI required." >&2; exit 1; }

# Tails the log group stream continuously using active flags
if [ -n "$STREAM_PREFIX" ]; then
    aws logs tail "$LOG_GROUP" --log-stream-name-prefix "$STREAM_PREFIX" --follow --format short
else
    aws logs tail "$LOG_GROUP" --follow --format short
fi
