# AWS Audit Scripts

Read-only quarterly audits. Every script here inventories and flags issues —
none of them modify or delete resources. Reports are written to
`./quarterly-reports/` with a timestamped filename.

Run any of them with:

```bash
AWS_PROFILE=prod ./iam-key-age-audit.sh
```

## Recommended Quarterly Cycle

1. **Cost:** `quarterly-unused-resources.sh`, `ri-sp-coverage.sh`,
   `rightsizing-candidates.sh`
2. **Security:** `iam-key-age-audit.sh`, `iam-key-rotation-audit.sh`,
   `public-exposure-check.sh`, `security-group-review.sh`, `scp-surface-review.sh`
3. **Hygiene:** `s3-bucket-health.sh`, `s3-multipart-cleanup.sh`,
   `tag-compliance.sh`, `ecr-image-age.sh`
4. **Governance:** `org-account-inventory.sh`, `sso-permission-set-audit.sh`,
   `sso-assignment-hygiene.sh`, `cicd-iam-role-audit.sh`

See the root README for the full script-to-check mapping.
