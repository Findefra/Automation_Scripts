# Invoke-SafeUpdate.ps1
# Windows Update with pre/post health gates. Prefer running from controlled windows.

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$ForceReboot,
    [string]$AppService = $env:APP_SERVICE,
    [string]$HealthUrl  = $env:HEALTH_URL
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\lib\Cloud-Info.ps1")
Require-Admin

Write-OpsLog -Level INFO -Message "Starting safe Windows Update (DryRun=$DryRun)"

# Pre-flight health
if ($AppService) {
    $svc = Get-Service -Name $AppService -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne "Running") {
        Write-OpsLog -Level ERROR -Message "Application service '$AppService' is not running — aborting"
        exit 1
    }
}
if ($HealthUrl) {
    try {
        $null = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 5
    }
    catch {
        Write-OpsLog -Level ERROR -Message "Health check $HealthUrl failed before update — aborting"
        exit 1
    }
}

if ($DryRun) {
    Write-OpsLog -Level INFO -Message "Dry-run: would search and install updates"
    exit 0
}

# Use Windows Update COM / PSWindowsUpdate if available; fallback to UsoClient
try {
    if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
        Import-Module PSWindowsUpdate
        Write-OpsLog -Level INFO -Message "Installing updates via PSWindowsUpdate"
        Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot | Out-Null
    }
    else {
        Write-OpsLog -Level INFO -Message "Triggering UsoClient scan + install"
        UsoClient StartScan
        Start-Sleep -Seconds 30
        UsoClient StartDownload
        Start-Sleep -Seconds 60
        UsoClient StartInstall
    }
}
catch {
    Write-OpsLog -Level ERROR -Message "Update failed: $_"
    exit 1
}

# Reboot decision
$needsReboot = $ForceReboot
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
    $needsReboot = $true
}

if (-not $needsReboot) {
    Write-OpsLog -Level INFO -Message "No reboot required"
    exit 0
}

Write-OpsLog -Level WARN -Message "Reboot required — running post-update health gate"

if ($AppService) {
    Restart-Service -Name $AppService -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 15
    $svc = Get-Service -Name $AppService
    if ($svc.Status -ne "Running") {
        Write-OpsLog -Level ERROR -Message "Application service failed after update — NOT rebooting"
        exit 1
    }
}

if ($HealthUrl) {
    $ok = $false
    for ($i = 1; $i -le 12; $i++) {
        try {
            $null = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 5
            $ok = $true
            break
        }
        catch { Start-Sleep -Seconds 10 }
    }
    if (-not $ok) {
        Write-OpsLog -Level ERROR -Message "Health check still failing — NOT rebooting"
        exit 1
    }
}

Write-OpsLog -Level WARN -Message "Rebooting in 5 seconds..."
Start-Sleep -Seconds 5
Restart-Computer -Force
