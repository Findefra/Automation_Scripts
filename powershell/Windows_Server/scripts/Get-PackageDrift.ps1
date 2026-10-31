# Get-PackageDrift.ps1
# Detect unexpected changes in installed software

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\lib\Cloud-Info.ps1")
Require-Admin

$baselineDir = "C:\Ops\State"
if (-not (Test-Path $baselineDir)) { New-Item -ItemType Directory -Path $baselineDir -Force | Out-Null }

$baseline = Join-Path $baselineDir "package-baseline.txt"
$current  = Join-Path $baselineDir "package-current.txt"

# Capture installed products (both 32 & 64 bit uninstall keys)
$apps = @()
$paths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($p in $paths) {
    Get-ItemProperty $p -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        ForEach-Object { $apps += ("{0}|{1}" -f $_.DisplayName, $_.DisplayVersion) }
}
$apps | Sort-Object -Unique | Set-Content -Path $current -Encoding UTF8

if (-not (Test-Path $baseline)) {
    Copy-Item $current $baseline
    Write-OpsLog -Level INFO -Message "Created initial package baseline"
    exit 0
}

$diff = Compare-Object (Get-Content $baseline) (Get-Content $current)
if ($diff) {
    Write-OpsLog -Level WARN -Message "Package drift detected"
    $diff | ForEach-Object { Write-OpsLog -Level WARN -Message ("  {0} {1}" -f $_.SideIndicator, $_.InputObject) }
}
else {
    Write-OpsLog -Level INFO -Message "No package drift"
}
