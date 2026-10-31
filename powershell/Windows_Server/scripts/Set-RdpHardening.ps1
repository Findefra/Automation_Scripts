# Set-RdpHardening.ps1
# Harden Remote Desktop for Windows Server

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\lib\Cloud-Info.ps1")
Require-Admin

Write-OpsLog -Level INFO -Message "Applying RDP hardening"

# Require Network Level Authentication
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
    -Name UserAuthentication -Value 1

# Set encryption level to High
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
    -Name MinEncryptionLevel -Value 3

# Idle and disconnected session timeouts (minutes)
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
    -Name MaxIdleTime -Value 900000 -Type DWord -Force   # 15 min
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
    -Name MaxDisconnectionTime -Value 1800000 -Type DWord -Force  # 30 min

# Restrict RDP to administrators only is usually done via Group Policy / Local Groups
# Ensure the firewall rule for RDP is present but limited later by Set-FirewallBaseline if desired

Write-OpsLog -Level INFO -Message "RDP hardening applied (NLA + high encryption + idle timeouts)"
