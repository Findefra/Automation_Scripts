# Invoke-GracefulDrain.ps1
# Pre-scale-in / pre-maintenance drain of the application

[CmdletBinding()]
param(
    [string]$AppService   = $env:APP_SERVICE,
    [string]$HealthUrl    = $env:HEALTH_URL,
    [int]$DrainSeconds    = 45
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "..\lib\Cloud-Info.ps1")
Require-Admin

Write-OpsLog -Level INFO -Message "Starting graceful drain (service=$AppService, timeout=${DrainSeconds}s)"

if ($HealthUrl) {
    for ($i = 1; $i -le $DrainSeconds; $i++) {
        try {
            $null = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 1
            Start-Sleep -Seconds 1
        }
        catch {
            Write-OpsLog -Level INFO -Message "Health endpoint no longer responding — drain complete"
            break
        }
    }
}
else {
    Start-Sleep -Seconds $DrainSeconds
}

if ($AppService) {
    Stop-Service -Name $AppService -Force -ErrorAction SilentlyContinue
    Write-OpsLog -Level INFO -Message "Service $AppService stopped"
}

Write-OpsLog -Level INFO -Message "Graceful drain finished"
