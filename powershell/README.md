# PowerShell Automations

Windows automation scripts. Run from an elevated PowerShell session unless
noted otherwise. If scripts are blocked, allow them for your user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## Scripts

| Script | Purpose |
|---|---|
| `Install-Visionline-GUI.ps1` | GUI-driven silent installer for Ving / Visionline (ASSA ABLOY) MSI — collects MSI path, log path, license, and server settings in a Windows Forms dialog |
| `Install-Visionline-Silent.ps1` | Fully silent Visionline install from MSI: full logging, firewall rules for Visionline/Vostio ports, VTCLink service set to Automatic |
| `Start-BrowsersAndReturnDesktop.ps1` | Starts Firefox, Brave, and Comodo Dragon with 2-minute gaps, then switches back to the "General Browsing" virtual desktop (uses the VirtualDesktop module) |
| `Windows-Maintenance.ps1` | Windows 11 maintenance: temp cleanup, Disk Cleanup, SFC, DISM repair, SSD TRIM, disk health scan, optional restart (requires Administrator) |

## Notes

- The Visionline installers assume the official ASSA ABLOY MSI and standard
  Visionline/Vostio ports; adjust the variables at the top of each script for
  your environment.
- `Start-BrowsersAndReturnDesktop.ps1` auto-installs the `VirtualDesktop`
  module from the PowerShell Gallery on first run and fails silently if the
  named desktop doesn't exist.
- `Windows-Maintenance.ps1` is tuned for a Windows 11 laptop (AMD + NVIDIA,
  SSD); review the DISM and Optimize-Volume steps before running on other
  hardware.
