# --- CONFIG: update these paths as needed ---
$firefoxPath = "C:\Program Files\Mozilla Firefox\firefox.exe"
$bravePath   = "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"
$dragonPath  = "C:\Program Files (x86)\Comodo\Dragon\dragon.exe"

# Optional: if you want to force “restore previous session” via startup args
# Firefox must be set in Settings > General > “Open previous windows and tabs”
$firefoxArgs = ""
$braveArgs   = ""
$dragonArgs  = ""

# --- FUNCTIONS ---

function Start-App {
    param (
        [string]$Path,
        [string]$Arguments = ""
    )

    if (Test-Path $Path) {
        Start-Process -FilePath $Path -ArgumentList $Arguments | Out-Null
    }
}

# Wait helper: 2 minutes between apps
function Wait-TwoMinutes {
    Start-Sleep -Seconds 120
}

# Switch to a specific virtual desktop by name using VirtualDesktop module
function Switch-ToGeneralBrowsingDesktop {
    try {
        if (-not (Get-Module -ListAvailable -Name VirtualDesktop)) {
            # Install for current user if missing (requires internet once)
            Install-Module -Name VirtualDesktop -Scope CurrentUser -Force -AllowClobber
        }

        Import-Module VirtualDesktop

        # Get all desktops and switch to the one named "General Browsing"
        $desktops = Get-VDDesktop
        $target = $desktops | Where-Object { $_.Name -eq "General Browsing" }

        if ($null -ne $target) {
            Switch-VDDesktop -Desktop $target
        }
    }
    catch {
        # Fail silently if virtual desktop switching fails
    }
}

# --- MAIN SEQUENCE ---

# Start Firefox (relies on browser setting to restore last session)
Start-App -Path $firefoxPath -Arguments $firefoxArgs
Wait-TwoMinutes

# Start Brave
Start-App -Path $bravePath -Arguments $braveArgs
Wait-TwoMinutes

# Start Comodo Dragon
Start-App -Path $dragonPath -Arguments $dragonArgs
Wait-TwoMinutes

# Return to "General Browsing" desktop
Switch-ToGeneralBrowsingDesktop
