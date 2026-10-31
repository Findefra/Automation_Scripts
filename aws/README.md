# AWS Automations

Bash, Terraform, and CloudFormation automation for AWS accounts.

## Layout

| Folder | Contents |
|---|---|
| `audits/` | Read-only quarterly audit & inventory scripts — they report, never modify |
| `cicd/` | EC2 Image Builder pipelines and hardened CI/CD + ML instance launching |
| `ops/` | Backups, cleanup (some destructive), and jq parsing examples |

## Requirements

- AWS CLI v2 with credentials configured (`aws configure` or `AWS_PROFILE`)
- `jq` for the scripts that parse CLI output
- Terraform >= 1.0 for the `.tf` files in `cicd/`

## Safety

- Scripts in `audits/` are safe to run against any account.
- Scripts in `ops/` can delete resources. Read `account-cleanup.sh` and
  `find-unattached-ebs-volumes.sh` in full before running them.
- The Image Builder scripts in `cicd/` create real billable resources; apply
  the Terraform with `apply-imagebuilder-tf.sh` (which plans first).

## Conventions

- `#!/usr/bin/env bash` + `set -euo pipefail` on all operational scripts.
- Audit reports are written to `./quarterly-reports/` with a timestamped name.
- Destructive actions require an explicit flag or confirmation, never a default.
