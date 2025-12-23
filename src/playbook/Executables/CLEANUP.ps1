.\AtlasModules\initPowerShell.ps1
function Invoke-AtlasDiskCleanup {
    # Kill running cleanmgr instances, as they will prevent new cleanmgr from starting
    Get-Process -Name cleanmgr -EA 0 | Stop-Process -Force -EA 0
    # Disk Cleanup preset
    # 2 = enabled
    # 0 = disabled
    $baseKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $regValues = @{
        "Active Setup Temp Folders"             = 2
        "BranchCache"                           = 2
        "D3D Shader Cache"                      = 0
        "Delivery Optimization Files"           = 2
        "Diagnostic Data Viewer database files" = 2
        "Downloaded Program Files"              = 2
        "Internet Cache Files"                  = 2
        "Language Pack"                         = 0
        "Old ChkDsk Files"                      = 2
        "Recycle Bin"                           = 0
        "RetailDemo Offline Content"            = 2
        "Setup Log Files"                       = 2
        "System error memory dump files"        = 2
        "System error minidump files"           = 2
        "Temporary Files"                       = 0
        "Thumbnail Cache"                       = 2
        "Update Cleanup"                        = 0
        "User file versions"                    = 2
        "Windows Error Reporting Files"         = 2
        "Windows Defender"                      = 2
        "Temporary Sync Files"                  = 2
        "Device Driver Packages"                = 2
    }
    foreach ($entry in $regValues.GetEnumerator()) {
        $key = "$baseKey\$($entry.Key)"

        if (!(Test-Path $key)) {
            Write-Output "'$key' not found, not configuring it."
        }
        else {
            Set-ItemProperty -Path "$baseKey\$($entry.Key)" -Name 'StateFlags0064' -Value $entry.Value -Type DWORD
        }
    }

    # Run preset 64 (0-65535)
    # As cleanmgr has multiple processes, there's no point in making the window hidden as it won't apply
    Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:64" 2>&1 | Out-Null
}

# Check for other installations of Windows
# If so, don't cleanup as it will also cleanup other drives, which will be slow, and we don't want to touch other data
$noCleanmgr = $false
$drives = (Get-PSDrive -PSProvider FileSystem).Root | Where-Object { $_ -notmatch $(Get-SystemDrive) }
foreach ($drive in $drives) {
    if (Test-Path -Path $(Join-Path -Path $drive -ChildPath 'Windows') -PathType Container) {
        Write-Output "Not running Disk Cleanup, other Windows drives found."
        $noCleanmgr = $true
        break
    }
}

if (!$noCleanmgr) {
    Write-Output "No other Windows drives found, running Disk Cleanup."
    Invoke-AtlasDiskCleanup
}

# Clear the user temp folder
foreach ($path in @($env:temp, $env:tmp, "$env:localappdata\Temp")) {
    if (Test-Path $path -PathType Container) {
        $userTemp = $path
        break
    }
}
if ($userTemp) {
    Write-Output "Cleaning user TEMP folder..."
    Get-ChildItem -Path $userTemp | Where-Object { $_.Name -ne 'AME' } | Remove-Item -Force -Recurse -EA 0
}
else {
    Write-Error "User temp folder not found!"
}

# Clear the system temp folder
$machine = [System.EnvironmentVariableTarget]::Machine
foreach ($path in @(
        [System.Environment]::GetEnvironmentVariable("Temp", $machine),
        [System.Environment]::GetEnvironmentVariable("Tmp", $machine),
        "$([Environment]::GetFolderPath('Windows'))\Temp"
    )) {
    if (Test-Path $path -PathType Container) {
        $sysTemp = $path
        break
    }
}
if ($sysTemp) {
    Write-Output "Cleaning system TEMP folder..."
    Remove-Item -Path "$sysTemp\*" -Force -Recurse -EA 0
}
else {
    Write-Error "System temp folder not found!"
}

# Delete all system restore points
# This is so that users can't attempt to revert from Atlas to stock with Restore Points
# It won't work, a full Windows reinstall is required ^
vssadmin delete shadows /all /quiet

# Clean Windows Update cache (SoftwareDistribution)
$windir = [Environment]::GetFolderPath('Windows')
$softwareDistribution = "$windir\SoftwareDistribution\Download"
if (Test-Path $softwareDistribution -PathType Container) {
    Write-Output "Cleaning Windows Update cache..."
    Remove-Item -Path "$softwareDistribution\*" -Force -Recurse -EA 0
}

# Clean Prefetch folder
$prefetchPath = "$windir\Prefetch"
if (Test-Path $prefetchPath -PathType Container) {
    Write-Output "Cleaning Prefetch folder..."
    Remove-Item -Path "$prefetchPath\*.pf" -Force -EA 0
}

# Clean Windows.old if present
$sysDrive = (Get-SystemDrive).TrimEnd('\')
$windowsOld = "$sysDrive\Windows.old"
if (Test-Path $windowsOld -PathType Container) {
    Write-Output "Cleaning Windows.old folder..."
    takeown /f $windowsOld /r /d y 2>&1 | Out-Null
    icacls $windowsOld /grant administrators:F /t 2>&1 | Out-Null
    Remove-Item -Path $windowsOld -Force -Recurse -EA 0
}

# Clean Edge cache and data remnants
$edgeCachePaths = @(
    "$env:localappdata\Microsoft\Edge\User Data\Default\Cache",
    "$env:localappdata\Microsoft\Edge\User Data\Default\Code Cache",
    "$env:localappdata\Microsoft\Edge\User Data\Default\GPUCache",
    "$env:localappdata\Microsoft\Edge\User Data\ShaderCache"
)
foreach ($cachePath in $edgeCachePaths) {
    if (Test-Path $cachePath -PathType Container) {
        Write-Output "Cleaning Edge cache: $cachePath"
        Remove-Item -Path "$cachePath\*" -Force -Recurse -EA 0
    }
}

# Clean Windows Error Reporting files
$werPath = "$env:localappdata\Microsoft\Windows\WER"
if (Test-Path $werPath -PathType Container) {
    Write-Output "Cleaning Windows Error Reporting files..."
    Remove-Item -Path "$werPath\*" -Force -Recurse -EA 0
}

# Clean thumbnail cache
$thumbcachePath = "$env:localappdata\Microsoft\Windows\Explorer"
if (Test-Path $thumbcachePath -PathType Container) {
    Write-Output "Cleaning thumbnail cache..."
    Remove-Item -Path "$thumbcachePath\thumbcache_*.db" -Force -EA 0
    Remove-Item -Path "$thumbcachePath\iconcache_*.db" -Force -EA 0
}

# Clean Windows logs
$logsPath = "$windir\Logs"
if (Test-Path $logsPath -PathType Container) {
    Write-Output "Cleaning Windows logs..."
    Get-ChildItem -Path $logsPath -Include *.log,*.etl -Recurse -EA 0 | Remove-Item -Force -EA 0
}
