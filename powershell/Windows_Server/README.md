# Windows Server Maintenance & Management Scripts

Practical PowerShell scripts for Windows Server (2019 / 2022 / 2025) focused on both **core infrastructure** and **application hosts** running in AWS or Azure.

These are written from real operational experience — not textbook checklists. They emphasize:

- Safe patching with health gates
- Disk space recovery under pressure
- Service / application watchdogs
- Consistent inventory & drift detection
- Cloud-aware identity (IMDSv2 / Azure Instance Metadata)
- Idempotent, logged, lock-protected execution

---

## Layout

```
powershell/Windows_Server/
├── README.md
├── Run-All-Ops.ps1
├── lib/
│   └── Cloud-Info.ps1
└── scripts/
    ├── Invoke-SafeUpdate.ps1
    ├── Invoke-DiskHygiene.ps1
    ├── Set-AppHostTuning.ps1
    ├── Set-SecurityHardening.ps1
    ├── Set-FirewallBaseline.ps1
    ├── Watch-Application.ps1
    ├── Get-PackageDrift.ps1
    ├── Set-LoggingHygiene.ps1
    ├── Set-RdpHardening.ps1
    ├── Invoke-GracefulDrain.ps1
    └── Get-DailySnapshot.ps1
```

Recommended install location on servers:

```
C:\Ops\
├── lib\
└── scripts\
```

---

## Quick Start

```powershell
# Run from an elevated PowerShell session
Set-Location C:\Ops   # or the repo path

# Preview
.\Run-All-Ops.ps1 -DryRun

# Run everything (with confirmation)
.\Run-All-Ops.ps1

# Run without prompts
.\Run-All-Ops.ps1 -Yes

# Run selected scripts only
.\Run-All-Ops.ps1 -Only DiskHygiene,LoggingHygiene,DailySnapshot -Yes

# Skip higher-risk scripts
.\Run-All-Ops.ps1 -Skip SafeUpdate,GracefulDrain -Yes
```

Pass application context via parameters or environment:

```powershell
$env:APP_SERVICE = "MyApp"
$env:HEALTH_URL  = "http://127.0.0.1:8080/health"
.\Run-All-Ops.ps1 -Yes
```

---

## Script Summary

| Script | Purpose |
|--------|---------|
| `Cloud-Info.ps1` | AWS / Azure metadata + structured logging helper |
| `Invoke-SafeUpdate.ps1` | Windows Update with pre/post health gates |
| `Invoke-DiskHygiene.ps1` | Aggressive but safe cleanup of temp, logs, IIS, Windows Update cache |
| `Set-AppHostTuning.ps1` | Performance / network / power tuning for app hosts |
| `Set-SecurityHardening.ps1` | Baseline security settings (SMBv1, LLMNR, etc.) |
| `Set-FirewallBaseline.ps1` | Windows Firewall rules aligned to application needs |
| `Watch-Application.ps1` | Service + HTTP health watchdog with restart logic |
| `Get-PackageDrift.ps1` | Detect unexpected installed software changes |
| `Set-LoggingHygiene.ps1` | Event log size limits + cleanup |
| `Set-RdpHardening.ps1` | RDP lockdown (NLA, encryption, idle timeouts) |
| `Invoke-GracefulDrain.ps1` | Pre-scale-in / pre-patch drain of application |
| `Get-DailySnapshot.ps1` | Compact daily evidence pack |

---

## Scheduling (Task Scheduler or SSM / Azure Run Command)

Recommended cadence:

- `Invoke-DiskHygiene` → every 30–60 min
- `Watch-Application` → every 1–2 min (or use a tight scheduled task)
- `Get-DailySnapshot` → daily 03:00
- `Invoke-SafeUpdate` → controlled maintenance window only (prefer SSM/Azure Run Command)

---

## Notes

- All scripts expect to run **elevated**.
- Logging goes to `C:\Ops\Logs\` by default.
- Cloud detection prefers IMDSv2 and Azure Instance Metadata Service.
- The master runner continues on non-critical failures and stops on `SafeUpdate` failure.
