# Set-SecurityHardening.ps1
# Baseline security hardening for Windows Server application / infrastructure hosts

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "..\lib\Cloud-Info.ps1")
Require-Admin

Write-OpsLog -Level INFO -Message "Applying security hardening baseline"

# Disable SMBv1
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null
Write-OpsLog -Level INFO -Message "SMBv1 disabled"

# Disable LLMNR
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name EnableMulticast -Value 0 -Type DWord
Write-OpsLog -Level INFO -Message "LLMNR disabled"

# Disable NetBIOS over TCP/IP on all adapters (where possible)
Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" | ForEach-Object {
    $_.SetTcpipNetbios(2) | Out-Null   # 2 = Disable NetBIOS
}
Write-OpsLog -Level INFO -Message "NetBIOS over TCP/IP disabled where possible"

# Enable Windows Defender real-time if present
if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
    Write-OpsLog -Level INFO -Message "Windows Defender real-time monitoring enabled"
}

Write-OpsLog -Level INFO -Message "Security hardening baseline complete"
