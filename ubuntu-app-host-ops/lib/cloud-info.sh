#!/bin/bash
# cloud-info.sh — reliable cloud detection + metadata (IMDSv2 / Azure Metadata)
# Shared library for Ubuntu application host scripts.

set -euo pipefail

_CLOUD=""
_INSTANCE_ID=""
_REGION=""
_PRIVATE_IP=""

detect_cloud() {
  if [[ -n "${_CLOUD}" ]]; then
    echo "${_CLOUD}"
    return
  fi

  if curl -s -m 2 -f -H "Metadata:true" \
      "http://169.254.169.254/metadata/instance?api-version=2021-02-01" >/dev/null 2>&1; then
    _CLOUD="azure"
  elif TOKEN=$(curl -s -m 2 -f -X PUT "http://169.254.169.254/latest/api/token" \
               -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null); then
    if curl -s -m 2 -f -H "X-aws-ec2-metadata-token: ${TOKEN}" \
         "http://169.254.169.254/latest/meta-data/instance-id" >/dev/null 2>&1; then
      _CLOUD="aws"
    else
      _CLOUD="unknown"
    fi
  else
    _CLOUD="unknown"
  fi
  echo "${_CLOUD}"
}

get_instance_id() {
  [[ -n "${_INSTANCE_ID}" ]] && { echo "${_INSTANCE_ID}"; return; }
  local cloud
  cloud=$(detect_cloud)
  case "${cloud}" in
    aws)
      local token
      token=$(curl -s -m 2 -X PUT "http://169.254.169.254/latest/api/token" \
              -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
      _INSTANCE_ID=$(curl -s -m 2 -H "X-aws-ec2-metadata-token: ${token}" \
                     http://169.254.169.254/latest/meta-data/instance-id)
      ;;
    azure)
      _INSTANCE_ID=$(curl -s -m 2 -H "Metadata:true" \
        "http://169.254.169.254/metadata/instance/compute/vmId?api-version=2021-02-01&format=text")
      ;;
    *)
      _INSTANCE_ID="unknown"
      ;;
  esac
  echo "${_INSTANCE_ID}"
}

get_region() {
  [[ -n "${_REGION}" ]] && { echo "${_REGION}"; return; }
  local cloud
  cloud=$(detect_cloud)
  case "${cloud}" in
    aws)
      local token
      token=$(curl -s -m 2 -X PUT "http://169.254.169.254/latest/api/token" \
              -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
      _REGION=$(curl -s -m 2 -H "X-aws-ec2-metadata-token: ${token}" \
                http://169.254.169.254/latest/meta-data/placement/region)
      ;;
    azure)
      _REGION=$(curl -s -m 2 -H "Metadata:true" \
        "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")
      ;;
    *)
      _REGION="unknown"
      ;;
  esac
  echo "${_REGION}"
}

get_private_ip() {
  [[ -n "${_PRIVATE_IP}" ]] && { echo "${_PRIVATE_IP}"; return; }
  local cloud
  cloud=$(detect_cloud)
  case "${cloud}" in
    aws)
      local token
      token=$(curl -s -m 2 -X PUT "http://169.254.169.254/latest/api/token" \
              -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
      _PRIVATE_IP=$(curl -s -m 2 -H "X-aws-ec2-metadata-token: ${token}" \
                    http://169.254.169.254/latest/meta-data/local-ipv4)
      ;;
    azure)
      _PRIVATE_IP=$(curl -s -m 2 -H "Metadata:true" \
        "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2021-02-01&format=text")
      ;;
    *)
      _PRIVATE_IP=$(hostname -I | awk '{print $1}')
      ;;
  esac
  echo "${_PRIVATE_IP}"
}

log() {
  local level="$1"
  shift
  local msg="$*"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local iid
  iid=$(get_instance_id 2>/dev/null || echo "unknown")
  echo "${ts} [${level}] [${iid}] ${msg}" | tee -a "/var/log/ops/$(basename "$0" .sh).log"
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    log ERROR "This script must be run as root"
    exit 1
  fi
}
