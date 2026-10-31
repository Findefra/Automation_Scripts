# Set-AppHostTuning.ps1
# Performance and network tuning suitable for application hosts

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\lib\Cloud-Info.ps1")
Require-Admin

Write-OpsLog -Level INFO -Message "Applying application-host tuning"

# High-performance power plan
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
Write-OpsLog -Level INFO -Message "Set High Performance power plan"

# Network tuning (TCP)
netsh int tcp set global autotuninglevel=normal | Out-Null
netsh int tcp set global chimney=disabled | Out-Null
netsh int tcp set global rss=enabled | Out-Null
netsh int tcp set global netdma=disabled | Out-Null

# Increase ephemeral port range if needed for high connection counts
netsh int ipv4 set dynamicport tcp start=10000 num=55535 | Out-Null

# Disable unnecessary visual effects / animations for server
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name VisualFXSetting -Value 2 -ErrorAction SilentlyContinue

Write-OpsLog -Level INFO -Message "Application-host tuning applied"
