# Cloud-Info.ps1
# Shared helpers: cloud detection, instance metadata, structured logging
# Dot-source this file from other scripts.

function Get-CloudProvider {
    if ($script:CloudProvider) { return $script:CloudProvider }

    try {
        $headers = @{ "Metadata" = "true" }
        $null = Invoke-RestMethod -Uri "http://169.254.169.254/metadata/instance?api-version=2021-02-01" `
            -Headers $headers -TimeoutSec 2 -ErrorAction Stop
        $script:CloudProvider = "Azure"
    }
    catch {
        try {
            $token = Invoke-RestMethod -Method Put -Uri "http://169.254.169.254/latest/api/token" `
                -Headers @{ "X-aws-ec2-metadata-token-ttl-seconds" = "21600" } -TimeoutSec 2 -ErrorAction Stop
            $null = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/instance-id" `
                -Headers @{ "X-aws-ec2-metadata-token" = $token } -TimeoutSec 2 -ErrorAction Stop
            $script:CloudProvider = "AWS"
        }
        catch {
            $script:CloudProvider = "Unknown"
        }
    }
    return $script:CloudProvider
}

function Get-InstanceId {
    if ($script:InstanceId) { return $script:InstanceId }
    $cloud = Get-CloudProvider
    try {
        switch ($cloud) {
            "AWS" {
                $token = Invoke-RestMethod -Method Put -Uri "http://169.254.169.254/latest/api/token" `
                    -Headers @{ "X-aws-ec2-metadata-token-ttl-seconds" = "21600" } -TimeoutSec 2
                $script:InstanceId = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/instance-id" `
                    -Headers @{ "X-aws-ec2-metadata-token" = $token } -TimeoutSec 2
            }
            "Azure" {
                $script:InstanceId = Invoke-RestMethod -Uri "http://169.254.169.254/metadata/instance/compute/vmId?api-version=2021-02-01&format=text" `
                    -Headers @{ "Metadata" = "true" } -TimeoutSec 2
            }
            default { $script:InstanceId = $env:COMPUTERNAME }
        }
    }
    catch { $script:InstanceId = $env:COMPUTERNAME }
    return $script:InstanceId
}

function Write-OpsLog {
    param(
        [Parameter(Mandatory)][ValidateSet("INFO","WARN","ERROR","DEBUG")][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $logDir = "C:\Ops\Logs"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logFile = Join-Path $logDir ("{0}.log" -f (Split-Path $MyInvocation.PSCommandPath -Leaf).Replace(".ps1",""))
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $iid = Get-InstanceId
    $line = "{0} [{1}] [{2}] {3}" -f $ts, $Level, $iid, $Message
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Admin {
    if (-not (Test-IsAdmin)) {
        Write-OpsLog -Level ERROR -Message "This script must be run elevated (as Administrator)"
        throw "Administrator privileges required"
    }
}
