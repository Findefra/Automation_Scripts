# Get-DailySnapshot.ps1
# Compact daily evidence pack for audits and troubleshooting

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "..\lib\Cloud-Info.ps1")
Require-Admin

$outDir = "C:\Ops\Snapshots"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd")
$report = Join-Path $outDir "snapshot-$stamp.txt"

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("=== OPS SNAPSHOT $((Get-Date).ToUniversalTime().ToString('u')) ===")
[void]$sb.AppendLine("Instance : $(Get-InstanceId)")
[void]$sb.AppendLine("Cloud    : $(Get-CloudProvider)")
[void]$sb.AppendLine("Computer : $env:COMPUTERNAME")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("--- OS ---")
[void]$sb.AppendLine((Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber | Format-List | Out-String))
[void]$sb.AppendLine("--- Disk ---")
[void]$sb.AppendLine((Get-PSDrive -Name C | Format-List | Out-String))
[void]$sb.AppendLine("--- Key Services ---")
Get-Service -Name wuauserv, EventLog, TermService, WinRM -ErrorAction SilentlyContinue |
    ForEach-Object { [void]$sb.AppendLine("$($_.Name) : $($_.Status)") }
[void]$sb.AppendLine("")
[void]$sb.AppendLine("--- Recent Hotfixes (last 10) ---")
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 10 |
    ForEach-Object { [void]$sb.AppendLine("$($_.HotFixID)  $($_.InstalledOn)") }

$sb.ToString() | Set-Content -Path $report -Encoding UTF8
Write-OpsLog -Level INFO -Message "Daily snapshot written to $report"
