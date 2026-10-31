# AWS CI/CD — Image Builder & Instance Launch

Build hardened Windows and RHEL base images with EC2 Image Builder, then
launch CI/CD agents or ML instances from the baked AMIs.

## Recommended Flow (Terraform)

1. `imagebuilder-pipelines.tf` — Terraform for both Windows and RHEL pipelines
   (the recommended core; keep recipes lean, heavy ML stacks go in a second
   "ML-optimized" recipe).
2. `ec2-ci-ml-module.tf` — reusable launch module for hardened instances.
3. `apply-imagebuilder-tf.sh` — applies the Terraform safely (always review
   the plan first).

## Script-Only Alternative

- `create-windows-imagebuilder-pipeline.sh` / `create-rhel-imagebuilder-pipeline.sh`
  create the pipelines via CLI.
- `launch-windows-ec2.sh` / `launch-rhel-ec2.sh` launch hardened instances
  from the latest baked AMIs.
- `launch-template.yaml` is the CloudFormation quick path when Terraform is
  overkill.
- `cicd-ml-orchestrator.sh` (or `-tf.sh` for the Terraform variant) triggers
  builds and orchestrates instances.

## Image Lifecycle

`svb-120day-image-lifecycle.sh` cleans up Image Builder images older than
120 days: it deletes image resources and deregisters the associated AMIs.
Make it executable and run:

```bash
chmod +x svb-120day-image-lifecycle.sh
./svb-120day-image-lifecycle.sh
```

## Notes

- Separate "bake" and "run" stages — never bake heavy ML frameworks
  (PyTorch, CUDA) into base images.
- Use the latest AWS-provided AMIs and apply CIS hardening via SSM or
  user-data at launch.
