# Run-All-Ops.ps1
# Master runner for Windows Server ops scripts

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Yes,
    [string]$Only,
    [string]$Skip
)

$ErrorActionPreference = "Stop"
$ScriptRoot = $PSScriptRoot
. (Join-Path $ScriptRoot "lib\Cloud-Info.ps1")
Require-Admin

$scriptsDir = Join-Path $ScriptRoot "scripts"

# Execution order (higher-risk scripts last)
$ordered = @(
    "Set-AppHostTuning.ps1",
    "Set-SecurityHardening.ps1",
    "Set-FirewallBaseline.ps1",
    "Set-LoggingHygiene.ps1",
    "Set-RdpHardening.ps1",
    "Invoke-DiskHygiene.ps1",
    "Get-PackageDrift.ps1",
    "Watch-Application.ps1",
    "Get-DailySnapshot.ps1",
    "Invoke-SafeUpdate.ps1",
    "Invoke-GracefulDrain.ps1"
)

function Should-Run([string]$name) {
    $base = $name -replace '\.ps1$',''
    if ($Only) {
        $list = $Only -split ',' | ForEach-Object { $_.Trim() }
        return ($list -contains $base -or $list -contains $name)
    }
    if ($Skip) {
        $list = $Skip -split ',' | ForEach-Object { $_.Trim() }
        if ($list -contains $base -or $list -contains $name) { return $false }
    }
    return $true
}

Write-Host "============================================================"
Write-Host " Windows Server Ops Runner"
Write-Host " Scripts dir : $scriptsDir"
Write-Host " DryRun      : $DryRun"
Write-Host "============================================================"
Write-Host ""

$toRun = @()
foreach ($s in $ordered) {
    if (Should-Run $s) {
        $path = Join-Path $scriptsDir $s
        if (Test-Path $path) { $toRun += $s }
        else { Write-OpsLog -Level WARN -Message "Script not found: $path" }
    }
}

if ($toRun.Count -eq 0) {
    Write-OpsLog -Level ERROR -Message "No scripts selected"
    exit 1
}

Write-Host "Scripts that will run:"
$toRun | ForEach-Object { Write-Host "  - $_" }
Write-Host ""

if ($DryRun) {
    Write-OpsLog -Level INFO -Message "Dry-run complete — nothing executed"
    exit 0
}

if (-not $Yes) {
    $ans = Read-Host "Proceed with running the above scripts? [y/N]"
    if ($ans -notmatch '^[Yy]$') {
        Write-OpsLog -Level INFO -Message "Aborted by user"
        exit 0
    }
}

$failed = 0
foreach ($s in $toRun) {
    Write-Host ""
    Write-OpsLog -Level INFO -Message "========== Running $s =========="
    try {
        & (Join-Path $scriptsDir $s)
        Write-OpsLog -Level INFO -Message "$s completed successfully"
    }
    catch {
        Write-OpsLog -Level ERROR -Message "$s failed: $_"
        $failed++
        if ($s -eq "Invoke-SafeUpdate.ps1") {
            Write-OpsLog -Level ERROR -Message "SafeUpdate failed — stopping further execution"
            break
        }
    }
}

Write-Host ""
if ($failed -gt 0) {
    Write-OpsLog -Level ERROR -Message "Finished with $failed failure(s)"
    exit 1
}
else {
    Write-OpsLog -Level INFO -Message "All selected scripts completed successfully"
    exit 0
}
