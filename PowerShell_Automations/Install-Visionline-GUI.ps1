<#
.SYNOPSIS
    GUI-driven silent installer for Ving / Visionline (ASSA ABLOY) MSI.

.DESCRIPTION
    Opens a simple Windows Forms dialog to collect:
      - MSI path
      - Log path
      - Optional install directory
      - License code
      - Server host / IP
      - Ving port (default 3015)
      - Vostio port (default 4000)
      - Allow reboot checkbox

    Then performs a fully silent MSI install + common post-config steps
    (firewall rules, VTCLink service, etc.).

.NOTES
    Must be run as Administrator.
    Requires .NET Framework (standard on Windows 10/11/Server).
#>

# ---------------------------------------------------------------------------
# Load Windows Forms
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------------------
# Helper: write to both console and log file
# ---------------------------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [System.Windows.Forms.TextBox]$StatusBox = $null
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    if ($script:LogPath -and (Test-Path (Split-Path $script:LogPath -Parent) -ErrorAction SilentlyContinue)) {
        Add-Content -Path $script:LogPath -Value $line -ErrorAction SilentlyContinue
    }
    if ($StatusBox) {
        $StatusBox.AppendText("$line`r`n")
        $StatusBox.SelectionStart = $StatusBox.Text.Length
        $StatusBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# ---------------------------------------------------------------------------
# Main GUI
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Ving / Visionline Silent Installer"
$form.Size = New-Object System.Drawing.Size(620, 620)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# --- Labels & TextBoxes ---
$y = 20
$labelWidth = 140
$boxWidth   = 380
$boxHeight  = 24
$spacing    = 32

function Add-LabeledTextBox {
    param($LabelText, $DefaultValue = "", $IsPassword = $false)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $LabelText
    $lbl.Location = New-Object System.Drawing.Point(20, $script:y)
    $lbl.Size = New-Object System.Drawing.Size($labelWidth, 20)
    $form.Controls.Add($lbl)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(170, ($script:y - 2))
    $tb.Size = New-Object System.Drawing.Size($boxWidth, $boxHeight)
    $tb.Text = $DefaultValue
    if ($IsPassword) { $tb.UseSystemPasswordChar = $true }
    $form.Controls.Add($tb)

    $script:y += $spacing
    return $tb
}

# MSI Path + Browse
$lblMsi = New-Object System.Windows.Forms.Label
$lblMsi.Text = "MSI Path:"
$lblMsi.Location = New-Object System.Drawing.Point(20, $y)
$lblMsi.Size = New-Object System.Drawing.Size($labelWidth, 20)
$form.Controls.Add($lblMsi)

$tbMsi = New-Object System.Windows.Forms.TextBox
$tbMsi.Location = New-Object System.Drawing.Point(170, ($y - 2))
$tbMsi.Size = New-Object System.Drawing.Size(300, $boxHeight)
$form.Controls.Add($tbMsi)

$btnBrowseMsi = New-Object System.Windows.Forms.Button
$btnBrowseMsi.Text = "Browse..."
$btnBrowseMsi.Location = New-Object System.Drawing.Point(480, ($y - 3))
$btnBrowseMsi.Size = New-Object System.Drawing.Size(80, 26)
$form.Controls.Add($btnBrowseMsi)

$y += $spacing

# Log Path + Browse
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Log Path:"
$lblLog.Location = New-Object System.Drawing.Point(20, $y)
$lblLog.Size = New-Object System.Drawing.Size($labelWidth, 20)
$form.Controls.Add($lblLog)

$tbLog = New-Object System.Windows.Forms.TextBox
$tbLog.Location = New-Object System.Drawing.Point(170, ($y - 2))
$tbLog.Size = New-Object System.Drawing.Size(300, $boxHeight)
$tbLog.Text = "C:\Logs\Visionline_Install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$form.Controls.Add($tbLog)

$btnBrowseLog = New-Object System.Windows.Forms.Button
$btnBrowseLog.Text = "Browse..."
$btnBrowseLog.Location = New-Object System.Drawing.Point(480, ($y - 3))
$btnBrowseLog.Size = New-Object System.Drawing.Size(80, 26)
$form.Controls.Add($btnBrowseLog)

$y += $spacing

# Remaining fields
$tbInstallDir  = Add-LabeledTextBox "Install Dir (opt):" ""
$tbLicense     = Add-LabeledTextBox "License Code:" ""
$tbServerHost  = Add-LabeledTextBox "Server Host / IP:" "127.0.0.1"
$tbVingPort    = Add-LabeledTextBox "Ving Port:" "3015"
$tbVostioPort  = Add-LabeledTextBox "Vostio Port:" "4000"

# Allow Reboot checkbox
$chkReboot = New-Object System.Windows.Forms.CheckBox
$chkReboot.Text = "Allow reboot if required by the installer"
$chkReboot.Location = New-Object System.Drawing.Point(170, $y)
$chkReboot.Size = New-Object System.Drawing.Size(350, 24)
$form.Controls.Add($chkReboot)
$y += 40

# Status / log output box
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status:"
$lblStatus.Location = New-Object System.Drawing.Point(20, $y)
$lblStatus.Size = New-Object System.Drawing.Size(100, 20)
$form.Controls.Add($lblStatus)
$y += 22

$tbStatus = New-Object System.Windows.Forms.TextBox
$tbStatus.Location = New-Object System.Drawing.Point(20, $y)
$tbStatus.Size = New-Object System.Drawing.Size(560, 180)
$tbStatus.Multiline = $true
$tbStatus.ScrollBars = "Vertical"
$tbStatus.ReadOnly = $true
$tbStatus.BackColor = [System.Drawing.Color]::WhiteSmoke
$form.Controls.Add($tbStatus)
$y += 195

# Buttons
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Install"
$btnInstall.Location = New-Object System.Drawing.Point(320, $y)
$btnInstall.Size = New-Object System.Drawing.Size(120, 34)
$btnInstall.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnInstall.ForeColor = [System.Drawing.Color]::White
$btnInstall.FlatStyle = "Flat"
$form.Controls.Add($btnInstall)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Location = New-Object System.Drawing.Point(460, $y)
$btnClose.Size = New-Object System.Drawing.Size(120, 34)
$form.Controls.Add($btnClose)

# ---------------------------------------------------------------------------
# Browse handlers
# ---------------------------------------------------------------------------
$btnBrowseMsi.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "MSI Packages (*.msi)|*.msi|All files (*.*)|*.*"
    $ofd.Title = "Select Visionline / Ving MSI"
    if ($ofd.ShowDialog() -eq "OK") {
        $tbMsi.Text = $ofd.FileName
    }
})

$btnBrowseLog.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "Log files (*.log)|*.log|All files (*.*)|*.*"
    $sfd.Title = "Select log file location"
    $sfd.FileName = "Visionline_Install.log"
    if ($sfd.ShowDialog() -eq "OK") {
        $tbLog.Text = $sfd.FileName
    }
})

$btnClose.Add_Click({ $form.Close() })

# ---------------------------------------------------------------------------
# Install button logic
# ---------------------------------------------------------------------------
$btnInstall.Add_Click({
    $btnInstall.Enabled = $false
    $tbStatus.Clear()

    # Validate inputs
    if ([string]::IsNullOrWhiteSpace($tbMsi.Text) -or -not (Test-Path $tbMsi.Text -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show("Please select a valid MSI file.", "Missing MSI", "OK", "Warning")
        $btnInstall.Enabled = $true
        return
    }

    $script:LogPath = $tbLog.Text
    $logDir = Split-Path $script:LogPath -Parent
    if (-not (Test-Path $logDir)) {
        try {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Cannot create log directory: $logDir", "Error", "OK", "Error")
            $btnInstall.Enabled = $true
            return
        }
    }

    # Check elevation
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        [System.Windows.Forms.MessageBox]::Show("This tool must be run as Administrator.", "Elevation Required", "OK", "Error")
        $btnInstall.Enabled = $true
        return
    }

    Write-Log "Starting Ving / Visionline silent installation" -StatusBox $tbStatus
    Write-Log "MSI          : $($tbMsi.Text)" -StatusBox $tbStatus
    Write-Log "Log file     : $script:LogPath" -StatusBox $tbStatus

    # Build msiexec arguments
    $msiArgs = @(
        "/i `"$($tbMsi.Text)`""
        "/qn"
        "/norestart"
        "/L*v `"$script:LogPath`""
        "ALLUSERS=1"
        "REBOOT=ReallySuppress"
    )

    if (-not [string]::IsNullOrWhiteSpace($tbInstallDir.Text)) {
        $msiArgs += "INSTALLDIR=`"$($tbInstallDir.Text)`""
    }
    if (-not [string]::IsNullOrWhiteSpace($tbLicense.Text)) {
        $msiArgs += "LICENSECODE=`"$($tbLicense.Text)`""
    }

    $argumentString = $msiArgs -join " "
    Write-Log "msiexec arguments: $argumentString" -StatusBox $tbStatus

    # Run installer
    try {
        $process = Start-Process -FilePath "msiexec.exe" `
                                 -ArgumentList $argumentString `
                                 -Wait -PassThru -NoNewWindow

        $exitCode = $process.ExitCode
        Write-Log "msiexec exited with code $exitCode" -StatusBox $tbStatus

        if ($exitCode -notin @(0, 3010)) {
            Write-Log "Installation FAILED. See log for details." "ERROR" -StatusBox $tbStatus
            [System.Windows.Forms.MessageBox]::Show("Installation failed (exit code $exitCode).`nCheck the log for details.", "Failed", "OK", "Error")
            $btnInstall.Enabled = $true
            return
        }

        Write-Log "MSI installation completed successfully." -StatusBox $tbStatus
    }
    catch {
        Write-Log "Exception during install: $_" "ERROR" -StatusBox $tbStatus
        [System.Windows.Forms.MessageBox]::Show("Exception: $_", "Error", "OK", "Error")
        $btnInstall.Enabled = $true
        return
    }

    # ----- Post-install configuration -----
    $vingPort   = 3015
    $vostioPort = 4000
    [int]::TryParse($tbVingPort.Text,   [ref]$vingPort)   | Out-Null
    [int]::TryParse($tbVostioPort.Text, [ref]$vostioPort) | Out-Null

    # Firewall rules
    $firewallRules = @(
        @{ Name = "Visionline - Ving Port $vingPort";   Port = $vingPort },
        @{ Name = "Visionline - Vostio Port $vostioPort"; Port = $vostioPort }
    )

    foreach ($rule in $firewallRules) {
        $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
        if (-not $existing) {
            try {
                New-NetFirewallRule -DisplayName $rule.Name `
                                    -Direction Inbound `
                                    -Protocol TCP `
                                    -LocalPort $rule.Port `
                                    -Action Allow `
                                    -Profile Any | Out-Null
                Write-Log "Created firewall rule: $($rule.Name)" -StatusBox $tbStatus
            }
            catch {
                Write-Log "Could not create firewall rule $($rule.Name): $_" "WARN" -StatusBox $tbStatus
            }
        }
        else {
            Write-Log "Firewall rule already exists: $($rule.Name)" -StatusBox $tbStatus
        }
    }

    # VTCLink service
    $vtcServiceNames = @("VTCLink", "VingCard VTCLink", "Visionline VTCLink")
    $serviceFound = $false
    foreach ($svcName in $vtcServiceNames) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            $serviceFound = $true
            if ($svc.StartType -ne "Automatic") {
                Set-Service -Name $svc.Name -StartupType Automatic
                Write-Log "Set $($svc.Name) to Automatic" -StatusBox $tbStatus
            }
            if ($svc.Status -ne "Running") {
                Start-Service -Name $svc.Name -ErrorAction SilentlyContinue
                Write-Log "Started service $($svc.Name)" -StatusBox $tbStatus
            }
            else {
                Write-Log "Service $($svc.Name) is already running" -StatusBox $tbStatus
            }
            break
        }
    }
    if (-not $serviceFound) {
        Write-Log "VTCLink service not found (may require reboot or different name)." "WARN" -StatusBox $tbStatus
    }

    # Final status
    if ($exitCode -eq 3010) {
        Write-Log "Installation succeeded but a reboot is required." -StatusBox $tbStatus
        if ($chkReboot.Checked) {
            Write-Log "Rebooting in 30 seconds..." -StatusBox $tbStatus
            shutdown.exe /r /t 30 /c "Visionline installation requires a reboot."
        }
        else {
            Write-Log "Reboot suppressed. Please reboot the machine manually." -StatusBox $tbStatus
            [System.Windows.Forms.MessageBox]::Show("Installation succeeded.`nA reboot is required. Please reboot manually.", "Reboot Needed", "OK", "Information")
        }
    }
    else {
        Write-Log "Ving / Visionline installation and configuration completed successfully." -StatusBox $tbStatus
        [System.Windows.Forms.MessageBox]::Show("Installation and configuration completed successfully.", "Success", "OK", "Information")
    }

    $btnInstall.Enabled = $true
})

# ---------------------------------------------------------------------------
# Show the form
# ---------------------------------------------------------------------------
[void]$form.ShowDialog()