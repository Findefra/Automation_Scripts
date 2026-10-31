# Watch-Application.ps1
# Simple service + HTTP health watchdog with restart logic

[CmdletBinding()]
param(
    [string]$AppService = $env:APP_SERVICE,
    [string]$HealthUrl  = $env:HEALTH_URL,
    [int]$MaxFailures   = 3
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "..\lib\Cloud-Info.ps1")
Require-Admin

if (-not $AppService) {
    Write-OpsLog -Level WARN -Message "APP_SERVICE not set — nothing to watch"
    exit 0
}

$stateFile = "C:\Ops\Logs\watchdog-state.txt"
if (-not (Test-Path (Split-Path $stateFile))) { New-Item -ItemType Directory -Path (Split-Path $stateFile) -Force | Out-Null }

$failures = 0
if (Test-Path $stateFile) { $failures = [int](Get-Content $stateFile) }

$healthy = $true

$svc = Get-Service -Name $AppService -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    Write-OpsLog -Level WARN -Message "Service $AppService is not running"
    $healthy = $false
}

if ($HealthUrl) {
    try {
        $null = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 3
    }
    catch {
        Write-OpsLog -Level WARN -Message "Health URL $HealthUrl failed"
        $healthy = $false
    }
}

if ($healthy) {
    Set-Content -Path $stateFile -Value "0"
    exit 0
}

$failures++
Set-Content -Path $stateFile -Value $failures
Write-OpsLog -Level WARN -Message "Failure count now $failures / $MaxFailures"

if ($failures -ge $MaxFailures) {
    Write-OpsLog -Level ERROR -Message "Restarting service $AppService"
    Restart-Service -Name $AppService -Force -ErrorAction SilentlyContinue
    Set-Content -Path $stateFile -Value "0"
}
