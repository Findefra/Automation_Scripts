# SVB Base Image Builder Pipelines

Unified automation for creating hardened **Windows Server**, **Ubuntu**, and **RHEL** golden AMIs with EC2 Image Builder.

## Layout

```
aws/cicd/
├── create-svb-base-image-pipelines.sh   # Master script – creates all 3 pipelines
├── publish-svb-components.sh            # Publishes custom component YAML → Image Builder
├── components/
│   ├── svb-linux-hardening.yaml         # Extra Linux hardening (SSH, sysctl, auditd)
│   ├── svb-windows-hardening.yaml       # Extra Windows hardening (SMBv1, firewall, audit)
│   └── svb-linux-vuln-scan.yaml         # Package inventory + lightweight vuln surface check
└── SVB-ImageBuilder-README.md
```

## Quick Start

### 1. Publish custom components (optional but recommended)

```bash
export AWS_REGION=us-east-1
export COMPONENT_BUCKET=your-imagebuilder-components-bucket

chmod +x publish-svb-components.sh
./publish-svb-components.sh
# Capture the printed CUSTOM_*_ARN export lines
```

### 2. Create the three pipelines

```bash
export AWS_REGION=us-east-1
export INSTANCE_PROFILE_NAME=EC2InstanceProfileForImageBuilder   # or your profile

# Optional – attach custom components
export CUSTOM_HARDENING_LINUX_ARN="arn:aws:imagebuilder:..."
export CUSTOM_HARDENING_WINDOWS_ARN="arn:aws:imagebuilder:..."
export CUSTOM_VULN_SCAN_ARN="arn:aws:imagebuilder:..."

chmod +x create-svb-base-image-pipelines.sh
./create-svb-base-image-pipelines.sh
```

### Useful flags

```bash
./create-svb-base-image-pipelines.sh --skip-shared   # reuse existing infra/dist configs
./create-svb-base-image-pipelines.sh --os windows    # only Windows
./create-svb-base-image-pipelines.sh --os ubuntu
./create-svb-base-image-pipelines.sh --os rhel
```

## What gets created

| Resource | Name |
|----------|------|
| Infra config | `SVB-ImageBuilder-InfraConfig` |
| Dist config  | `SVB-ImageBuilder-DistConfig` |
| Recipes      | `SVB_BaseImageRecipe_WindowsServer` / `_Ubuntu` / `_RHEL` |
| Pipelines    | `SVB_BaseImagePipeline_WindowsServer` / `_Ubuntu` / `_RHEL` |

**Schedule:** 1st & 3rd Sunday (staggered hours 02:00 / 03:00 / 04:00 UTC)  
**Start condition:** `EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE`  
**SSM agent:** retained after build  
**Managed components:** `update-linux` / `update-windows`, CloudWatch agent

## Custom components

| Component | Platform | Purpose |
|-----------|----------|---------|
| SVB-Linux-Hardening | Linux | SSH hardening, sysctl, auditd, chrony |
| SVB-Windows-Hardening | Windows | Disable SMBv1, password/firewall/audit policy |
| SVB-Linux-VulnScan | Linux | Package inventory + high-risk package check; report at `/var/log/svb-vuln-scan.txt` |

These are complementary to AWS-managed components and (where subscribed) CIS Marketplace components. CIS hardening components always run last when present in a recipe.

## Trigger a build

```bash
aws imagebuilder start-image-pipeline-execution \
  --region us-east-1 \
  --image-pipeline-arn arn:aws:imagebuilder:us-east-1:ACCOUNT:image-pipeline/SVB_BaseImagePipeline_Ubuntu
```

## Notes

- Keep base recipes lean. Heavy ML / CUDA stacks belong in a second-stage recipe that starts from these golden images.
- For CIS Benchmark Level 1, subscribe to the CIS Marketplace components and add their ARNs to the recipe (they run last automatically).
- Region default is `us-east-1`; override with `AWS_REGION` if needed.
