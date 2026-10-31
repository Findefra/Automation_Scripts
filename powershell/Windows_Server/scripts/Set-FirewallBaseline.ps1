# Set-FirewallBaseline.ps1
# Windows Firewall baseline — only open what the application needs

[CmdletBinding()]
param(
    [int[]]$AllowedTcpPorts = @(22, 80, 443, 3389, 8080)
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\lib\Cloud-Info.ps1")
Require-Admin

Write-OpsLog -Level INFO -Message "Applying Windows Firewall baseline"

# Ensure firewall is on for all profiles
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

# Remove previous ops rules to stay idempotent
Get-NetFirewallRule -DisplayName "Ops-*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule

foreach ($port in $AllowedTcpPorts) {
    New-NetFirewallRule -DisplayName "Ops-Allow-TCP-$port" `
        -Direction Inbound -Protocol TCP -LocalPort $port `
        -Action Allow -Profile Any | Out-Null
    Write-OpsLog -Level INFO -Message "Allowed TCP $port"
}

Write-OpsLog -Level INFO -Message "Firewall baseline applied"
