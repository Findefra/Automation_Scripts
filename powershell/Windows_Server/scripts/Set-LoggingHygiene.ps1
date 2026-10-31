# Set-LoggingHygiene.ps1
# Event log size limits and cleanup of oversized logs

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "..\lib\Cloud-Info.ps1")
Require-Admin

Write-OpsLog -Level INFO -Message "Applying logging hygiene"

$logs = @("Application", "System", "Security")
foreach ($log in $logs) {
    try {
        Limit-EventLog -LogName $log -MaximumSize 256MB -OverflowAction OverwriteAsNeeded -ErrorAction Stop
        Write-OpsLog -Level INFO -Message "Set $log log max size 256MB"
    }
    catch {
        # Fallback via wevtutil
        wevtutil sl $log /ms:268435456 2>$null
    }
}

# Clear very large archived .evtx if present under winevt
$archive = "$env:SystemRoot\System32\winevt\Logs"
if (Test-Path $archive) {
    Get-ChildItem $archive -Filter "*.evtx" -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 500MB } |
        ForEach-Object {
            Write-OpsLog -Level WARN -Message "Large event log file: $($_.Name) ($([math]::Round($_.Length/1MB)) MB)"
        }
}

Write-OpsLog -Level INFO -Message "Logging hygiene complete"
