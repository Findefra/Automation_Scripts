# ================================================
# Basic Maintenance Script for Windows 11
# Optimized for GigaByte-Laptop (AMD + NVIDIA)
# Run as Administrator!
# ================================================

Write-Host "=== Windows Maintenance Script Starting ===" -ForegroundColor Green
Write-Host "Device: $env:COMPUTERNAME | Windows 11 25H2`n"

# Function to check if running as Admin
function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "ERROR: Please run this script as Administrator!" -ForegroundColor Red
    exit 1
}

# 1. Clean Temporary Files
Write-Host "`n1. Cleaning Temporary Files..." -ForegroundColor Cyan
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
Write-Host "   Temp files & Recycle Bin cleaned." -ForegroundColor Green

# 2. Disk Cleanup (using Cleanmgr)
Write-Host "`n2. Running Disk Cleanup..." -ForegroundColor Cyan
cleanmgr /sagerun:1 | Out-Null
Write-Host "   Disk Cleanup completed." -ForegroundColor Green

# 3. System File Checker (SFC)
Write-Host "`n3. Running System File Checker (SFC)..." -ForegroundColor Cyan
sfc /scannow
Write-Host "   SFC completed." -ForegroundColor Green

# 4. DISM Repair (in correct order)
Write-Host "`n4. Running DISM Health Checks & Repair..." -ForegroundColor Cyan
DISM /Online /Cleanup-Image /CheckHealth
DISM /Online /Cleanup-Image /ScanHealth
DISM /Online /Cleanup-Image /RestoreHealth
DISM /Online /Cleanup-Image /StartComponentCleanup
Write-Host "   DISM operations completed." -ForegroundColor Green

# 5. Optimize Drives (TRIM for SSD + Defrag if needed)
Write-Host "`n5. Optimizing Drives..." -ForegroundColor Cyan
Optimize-Volume -DriveLetter C -ReTrim -Verbose -ErrorAction SilentlyContinue
Write-Host "   Drive optimization completed (TRIM/SSD friendly)." -ForegroundColor Green

# 6. Check Disk Health (quick)
Write-Host "`n6. Quick Disk Health Check..." -ForegroundColor Cyan
chkdsk C: /scan
Write-Host "   Disk scan completed." -ForegroundColor Green

# 7. Windows Update Check (manual trigger)
Write-Host "`n7. Checking for Windows Updates..." -ForegroundColor Cyan
Write-Host "   Opening Windows Update settings..." -ForegroundColor Yellow
Start-Process ms-settings:windowsupdate

Write-Host "`n=== Maintenance Completed! ===" -ForegroundColor Green
Write-Host "It is recommended to restart your laptop now." -ForegroundColor Yellow
Write-Host "`nWould you like to restart now? (Y/N)" -ForegroundColor White
$restart = Read-Host
if ($restart -eq 'Y' -or $restart -eq 'y') {
    Restart-Computer -Force
}