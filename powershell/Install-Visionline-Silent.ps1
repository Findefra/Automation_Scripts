<#
.SYNOPSIS
    Silent installation and configuration of Ving / Visionline (ASSA ABLOY) from MSI.

.DESCRIPTION
    - Installs the MSI silently with full logging
    - Creates firewall rules for the standard Visionline / Vostio ports
    - Ensures the VTCLink service is set to Automatic and started
    - Optionally writes basic configuration values (license, server settings, etc.)
    - Returns proper exit codes for automation tools (SCCM, Intune, Ansible, etc.)

.NOTES
    Run elevated (Administrator).
    Replace the MSI path and any public properties with the values supplied by ASSA ABLOY.
    For true unattended installs ASSA ABLOY recommends creating a response file first
    (see their official Installation Instruction document, section "Installing in silent mode").
#>

[CmdletBinding()]
param (
    # Full path to the Visionline / Ving MSI
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$MsiPath,

    # Optional: path where the verbose log will be written
    [string]$LogPath = "C:\Logs\Visionline_Install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",

    # Optional: install directory (leave empty for default)
    [string]$InstallDir = "",

    # Optional: license code supplied by ASSA ABLOY
    [string]$LicenseCode = "",

    # Optional: Visionline server hostname / IP (used in post-config)
    [string]$ServerHost = "127.0.0.1",

    # Port used by classic Ving Vision (default 3015)
    [int]$VingPort = 3015,

    # Port used by Vostio PMS Converter (default 4000)
    [int]$VostioPort = 4000,

    # Force a reboot if the installer requests one
    [switch]$AllowReboot
)

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
}

function Test-Administrator {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if (-not (Test-Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

# Ensure log directory exists
$logDir = Split-Path $LogPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

Write-Log "Starting Ving / Visionline silent installation"
Write-Log "MSI          : $MsiPath"
Write-Log "Log file     : $LogPath"

# ---------------------------------------------------------------------------
# Build msiexec argument list
# ---------------------------------------------------------------------------
$msiArgs = @(
    "/i `"$MsiPath`""
    "/qn"                          # completely silent
    "/norestart"                   # do not reboot automatically
    "/L*v `"$LogPath`""            # verbose log
    "ALLUSERS=1"                   # per-machine install
    "REBOOT=ReallySuppress"
)

# Optional public properties – add any that ASSA ABLOY documents
if ($InstallDir) {
    $msiArgs += "INSTALLDIR=`"$InstallDir`""
}
if ($LicenseCode) {
    # Property name may differ – confirm with official docs / support
    $msiArgs += "LICENSECODE=`"$LicenseCode`""
}

$argumentString = $msiArgs -join " "
Write-Log "msiexec arguments: $argumentString"

# ---------------------------------------------------------------------------
# Perform the installation
# ---------------------------------------------------------------------------
$process = Start-Process -FilePath "msiexec.exe" `
                         -ArgumentList $argumentString `
                         -Wait `
                         -PassThru `
                         -NoNewWindow

$exitCode = $process.ExitCode
Write-Log "msiexec exited with code $exitCode"

# Standard MSI success codes
# 0     = success
# 3010  = success, reboot required
if ($exitCode -notin @(0, 3010)) {
    Write-Log "Installation FAILED. See log for details." "ERROR"
    exit $exitCode
}

Write-Log "MSI installation completed successfully."

# ---------------------------------------------------------------------------
# Post-install configuration
# ---------------------------------------------------------------------------

# 1. Firewall rules for the standard ports
$firewallRules = @(
    @{ Name = "Visionline - Ving Port $VingPort"; Port = $VingPort },
    @{ Name = "Visionline - Vostio Port $VostioPort"; Port = $VostioPort }
)

foreach ($rule in $firewallRules) {
    $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule -DisplayName $rule.Name `
                            -Direction Inbound `
                            -Protocol TCP `
                            -LocalPort $rule.Port `
                            -Action Allow `
                            -Profile Any `
                            -ErrorAction Stop | Out-Null
        Write-Log "Created firewall rule: $($rule.Name)"
    } else {
        Write-Log "Firewall rule already exists: $($rule.Name)"
    }
}

# 2. Ensure VTCLink service is Automatic and running
#    (service name may vary slightly by version – adjust if needed)
$vtcServiceNames = @("VTCLink", "VingCard VTCLink", "Visionline VTCLink")
$serviceFound = $false

foreach ($svcName in $vtcServiceNames) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        $serviceFound = $true
        if ($svc.StartType -ne "Automatic") {
            Set-Service -Name $svc.Name -StartupType Automatic
            Write-Log "Set $($svc.Name) to Automatic"
        }
        if ($svc.Status -ne "Running") {
            Start-Service -Name $svc.Name
            Write-Log "Started service $($svc.Name)"
        } else {
            Write-Log "Service $($svc.Name) is already running"
        }
        break
    }
}

if (-not $serviceFound) {
    Write-Log "VTCLink service not found. It may be installed under a different name or require a reboot." "WARN"
}

# 3. Example configuration writes (adjust paths / keys to match your version)
#    These are placeholders – obtain the real registry keys or INI locations
#    from the official installation guide or ASSA ABLOY support.

$visionlineConfigPath = "C:\Program Files\ASSA ABLOY\Visionline"   # typical path – verify
if (Test-Path $visionlineConfigPath) {
    Write-Log "Visionline installation directory found: $visionlineConfigPath"

    # Example: write a simple settings file (only if the product supports it)
    # $settingsFile = Join-Path $visionlineConfigPath "PMSSettings.ini"
    # @"
    # [PMS]
    # ServerHost=$ServerHost
    # Port=$VingPort
    # License=$LicenseCode
    # "@ | Set-Content -Path $settingsFile -Encoding UTF8
    # Write-Log "Wrote sample PMS settings"
}

# ---------------------------------------------------------------------------
# Final status
# ---------------------------------------------------------------------------
if ($exitCode -eq 3010) {
    Write-Log "Installation succeeded but a reboot is required."
    if ($AllowReboot) {
        Write-Log "Rebooting in 30 seconds..."
        shutdown.exe /r /t 30 /c "Visionline installation requires a reboot."
    } else {
        Write-Log "Reboot suppressed. Please reboot the machine manually."
    }
    exit 3010
}

Write-Log "Ving / Visionline installation and configuration completed successfully."
exit 0
