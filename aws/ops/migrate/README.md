# AWS Application Migration Service (MGN) – Wave + Application Migration

Orchestrates on-premises → **us-east-1** rehost migrations using AWS Application Migration Service (MGN / AWS Transform MGN).

## Hierarchy

```
Source Servers  →  Application  →  Wave
```

1. Creates an **Application** and associates the source servers  
2. Creates a **Wave** and associates the Application  
3. Enables **BASIC** instance-type right-sizing  
4. Performs pre-migration backup  
5. Launches **TEST** instances  
6. Optionally performs **automatic cutover** after a successful test  
7. Uploads a detailed JSON report to S3  

## Script

| File | Description |
|------|-------------|
| `mgn_wave_application_migrate.sh` | Main orchestration script |

## Prerequisites

- AWS CLI v2 + `jq`
- IAM permissions: `mgn:*`, `s3:PutObject`, `ec2:Describe*`, `iam:PassRole` (if using instance profiles)
- AWS Replication Agent already installed on source servers
- Network connectivity from sources to AWS (outbound 443 + replication ports)
- S3 bucket for reports (set `S3_REPORT_BUCKET` in the script)

## Configuration

Edit the top of `mgn_wave_application_migrate.sh`:

```bash
AWS_REGION="us-east-1"
S3_REPORT_BUCKET="your-migration-reports-bucket"   # required
ENABLE_RIGHT_SIZING="true"                         # BASIC right-sizing
AUTO_CUTOVER_AFTER_TEST="false"                    # or pass --auto-cutover
DEFAULT_SUBNET_ID=""                               # optional
DEFAULT_SECURITY_GROUP_IDS=""                      # optional
DEFAULT_IAM_INSTANCE_PROFILE=""                    # optional
```

## Usage

```bash
chmod +x mgn_wave_application_migrate.sh

# Discovery
./mgn_wave_application_migrate.sh --list-servers
./mgn_wave_application_migrate.sh --list-applications
./mgn_wave_application_migrate.sh --list-waves

# Full flow (create Application + Wave, associate, right-size, test, report)
./mgn_wave_application_migrate.sh \
  --app-name "App-Core" \
  --wave-name "Wave-1" \
  --server-ids s-0a1b2c3d4e5f67890,s-0f9e8d7c6b5a43210 \
  --os linux

# Same + automatic cutover after successful test
./mgn_wave_application_migrate.sh \
  --app-name "App-Core" \
  --wave-name "Wave-1" \
  --server-ids s-0a1b2c3d4e5f67890 \
  --auto-cutover --yes

# Dry-run (no changes)
./mgn_wave_application_migrate.sh \
  --app-name "App-Test" --wave-name "Wave-Test" \
  --server-ids s-xxx --dry-run
```

## Options

| Flag | Description |
|------|-------------|
| `--app-name NAME` | Application name (required) |
| `--wave-name NAME` | Wave name (required) |
| `--server-ids id1,id2,...` | Comma-separated source server IDs (required) |
| `--os linux\|windows` | Backup method (default: linux) |
| `--auto-cutover` | Automatically start cutover after successful test |
| `--enable-right-sizing` / `--disable-right-sizing` | Control BASIC right-sizing |
| `--dry-run` | Show actions without executing |
| `--yes` | Skip confirmation prompts |
| `--list-waves` / `--list-applications` / `--list-servers` | Discovery helpers |

## Safety notes

- Always run with `--dry-run` first in a non-production account.
- Prefer TEST → validate → CUTOVER over automatic cutover for production workloads.
- After cutover, finalize with:
  ```bash
  aws mgn finalize-cutover --source-server-i-ds <ids> --region us-east-1
  ```
- The AWS Replication Agent is **not** installed by this script; install it on sources beforehand.

## Related

- Parent ops scripts: `../`
- AWS audits: `../../audits/`
- Image Builder / CI pipelines: `../../cicd/`
