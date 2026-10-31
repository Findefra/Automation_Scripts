# Invoke-DiskHygiene.ps1
# Aggressive but safe cleanup of the usual disk killers on Windows Server

[CmdletBinding()]
param(
    [int]$FreeSpaceThresholdPercent = 15
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "..\lib\Cloud-Info.ps1")
Require-Admin

Write-OpsLog -Level INFO -Message "Starting disk hygiene"

function Get-FreePercent {
    $drive = Get-PSDrive -Name C
    return [math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 1)
}

$before = Get-FreePercent
Write-OpsLog -Level INFO -Message "C: free space before: $before%"

# 1. Windows Update download cache
$wuCache = "$env:SystemRoot\SoftwareDistribution\Download"
if (Test-Path $wuCache) {
    Get-ChildItem $wuCache -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-OpsLog -Level INFO -Message "Cleared Windows Update download cache"
}

# 2. Temp folders
@("$env:TEMP", "$env:SystemRoot\Temp", "C:\Windows\Temp") | ForEach-Object {
    if (Test-Path $_) {
        Get-ChildItem $_ -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-OpsLog -Level INFO -Message "Cleaned temporary folders"

# 3. IIS logs (if present)
$iisLogs = "C:\inetpub\logs\LogFiles"
if (Test-Path $iisLogs) {
    Get-ChildItem $iisLogs -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-OpsLog -Level INFO -Message "Cleaned old IIS logs"
}

# 4. CBS / Component Based Servicing logs
$cbs = "$env:SystemRoot\Logs\CBS"
if (Test-Path $cbs) {
    Get-ChildItem $cbs -Filter "*.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 100MB -or $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# 5. Recycle Bin
Clear-RecycleBin -Force -ErrorAction SilentlyContinue

# 6. Delivery Optimization cache
$doCache = "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization\Cache"
if (Test-Path $doCache) {
    Remove-Item "$doCache\*" -Recurse -Force -ErrorAction SilentlyContinue
}

$after = Get-FreePercent
Write-OpsLog -Level INFO -Message "C: free space after: $after% (was $before%)"

if ($after -lt $FreeSpaceThresholdPercent) {
    Write-OpsLog -Level ERROR -Message "Free space still below threshold ($FreeSpaceThresholdPercent%)"
    exit 1
}
