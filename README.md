# Automation_Scripts

![Validate Scripts](https://github.com/Findefra/Automation_Scripts/actions/workflows/validate-scripts.yml/badge.svg)

A collection of Bash, Python, and PowerShell automation scripts for AWS, RHEL
servers, Windows workstations, and general productivity.

## Repository Structure

```
Automation_Scripts/
├── aws/                  # AWS automation (bash, Terraform, CloudFormation)
│   ├── audits/           # Read-only quarterly audit & inventory scripts
│   ├── cicd/             # EC2 Image Builder, CI/CD launch & Terraform pipelines
│   └── ops/              # Backups, cleanup, jq examples
├── python/               # Standalone Python utilities
│   └── docs/             # Scheduling & usage notes
├── powershell/           # Windows automation (Visionline installers, maintenance)
└── redhat/               # RHEL 9/10 server tooling installers
```

## Contents

### `aws/audits/` — Read-Only Audits

Quarterly review scripts that inventory and flag issues across an AWS account.
All are read-only: they report, they never modify or delete resources. Most
write a timestamped CSV report to `./quarterly-reports/`.

| Script | Checks |
|---|---|
| `cert-expiry-sweep.sh` | ACM + classic IAM certificates nearing expiry |
| `cicd-iam-role-audit.sh` | CodeBuild/CodePipeline roles with admin-level policies |
| `cloudwatch-tail-logs.sh` | Tail live CloudWatch logs across groups |
| `codebuild-config-audit.sh` | Privileged mode, outdated images, missing encryption |
| `codepipeline-health.sh` | Failed, stuck, and long-inactive pipelines |
| `ec2-inventory.sh` | Running instances + volumes with age and tag gaps |
| `ec2-stopped-orphans.sh` | Stopped instances / unattached volumes idle > 30 days |
| `ecr-image-age.sh` | Untagged and orphaned ECR images |
| `ecr-repo-compliance.sh` | Scan-on-push, repository policies, lifecycle rules |
| `iam-key-age-audit.sh` | Access keys older than 90 days, stale console logins |
| `iam-key-rotation-audit.sh` | Expiring IAM access keys needing rotation |
| `iam-user-group-audit.sh` | IAM users missing group membership |
| `lambda-runtime-deprecation.sh` | Deprecated runtimes, functions not updated in 180+ days |
| `lambda-unused-functions.sh` | Zero-invocation functions missing DLQ / tracing |
| `org-account-inventory.sh` | Organizations accounts, suspended / stale accounts |
| `public-exposure-check.sh` | Public S3 + high-risk exposed surfaces |
| `quarterly-unused-resources.sh` | Orphaned cost drivers across all regions |
| `rds-config-audit.sh` | Multi-AZ, backups, encryption, public accessibility |
| `rds-snapshot-age.sh` | Old manual and lingering automated snapshots |
| `ri-sp-coverage.sh` | Reserved Instance / Savings Plans coverage gaps |
| `rightsizing-candidates.sh` | Low-CPU EC2 / low-connection RDS candidates |
| `s3-bucket-health.sh` | Versioning, encryption, public access, lifecycle drift |
| `s3-multipart-cleanup.sh` | Incomplete multipart uploads, old delete markers |
| `scp-surface-review.sh` | SCP guardrail coverage across OUs |
| `security-group-review.sh` | Wide-open ingress, stale rule references |
| `sso-assignment-hygiene.sh` | Idle / over-provisioned SSO assignments |
| `sso-permission-set-audit.sh` | Permission sets and high-risk managed policies |
| `tag-compliance.sh` | Missing required tags across services |

### `aws/cicd/` — Image Builder & CI/CD

Build hardened Windows/RHEL AMIs with EC2 Image Builder, then launch CI/CD
agents or ML instances from them.

| Script | Purpose |
|---|---|
| `create-rhel-imagebuilder-pipeline.sh` | Create the RHEL base image pipeline |
| `create-windows-imagebuilder-pipeline.sh` | Create the Windows base image pipeline |
| `imagebuilder-pipelines.tf` | Terraform for both pipelines (recommended core) |
| `apply-imagebuilder-tf.sh` | Safely apply the Terraform config (plan first) |
| `ec2-ci-ml-module.tf` | Terraform launch module for Windows/RHEL instances |
| `launch-rhel-ec2.sh` / `launch-windows-ec2.sh` | Launch hardened instances from baked AMIs |
| `launch-template.yaml` | CloudFormation quick launch template (when TF is overkill) |
| `cicd-ml-orchestrator.sh` | Trigger builds + orchestrate instances |
| `cicd-ml-orchestrator-tf.sh` | Combined Terraform + build + launch orchestrator |
| `svb-120day-image-lifecycle.sh` | Deregister AMIs and Image Builder resources > 120 days |

### `aws/ops/` — Operational Scripts

| Script | Purpose |
|---|---|
| `s3-backup-upload.sh` | Archive a directory and upload to S3 |
| `find-unattached-ebs-volumes.sh` | Find **and delete** unattached EBS volumes |
| `account-cleanup.sh` | Irreversible full-account cleanup — use with extreme caution |
| `jq-examples.sh` | jq patterns for parsing AWS CLI JSON output |

### `python/` — Python Utilities

All scripts are runnable CLI tools (`python <script> --help`) with dry-run
defaults for anything that renames, moves, or deletes files. See
`python/README.md` for details and `python/requirements.txt` for dependencies.

### `powershell/` — Windows Automation

Visionline (ASSA ABLOY) silent/GUI installers, Windows maintenance, and a
browser startup helper. See `powershell/README.md`.

### `redhat/` — RHEL Server Tooling

RHEL 9/10 CLI/TUI tool installers (v1 and improved v2) and a once-per-day login
system report. See `redhat/README.md` for the v1 vs v2 comparison.

## Usage Notes

- **AWS scripts** require the AWS CLI v2 with credentials configured
  (`aws configure` or `AWS_PROFILE`). Most audits are safe to run against any
  account; scripts in `aws/ops/` can delete resources — review before running.
- **Python scripts** need Python 3.9+: `pip install -r python/requirements.txt`.
- **PowerShell scripts** may require execution policy changes:
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

## Contributing

- One script (or tightly coupled set) per file, named in `kebab-case.sh`,
  `snake_case.py`, or `Verb-Noun.ps1`.
- Bash scripts: `#!/usr/bin/env bash` + `set -euo pipefail`.
- Include a header comment stating purpose, prerequisites, and usage.
- Destructive operations require an explicit opt-in flag, never a default.
