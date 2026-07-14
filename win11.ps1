# to Run, boot OSDCloudUSB, at the PS Prompt:
# iex (irm win11.bencarver.com)

#region Initialization
function Write-DarkGrayDate {
    [CmdletBinding()]
    param ([Parameter(Position = 0)][string]$Message)
    if ($Message) {
        Write-Host -ForegroundColor DarkGray "$((Get-Date).ToString('yyyy-MM-dd-HHmmss')) $Message"
    } else {
        Write-Host -ForegroundColor DarkGray "$((Get-Date).ToString('yyyy-MM-dd-HHmmss')) " -NoNewline
    }
}
function Write-DarkGrayHost {[CmdletBinding()] param([Parameter(Mandatory=$true,Position=0)][string]$Message) Write-Host -ForegroundColor DarkGray $Message}
function Write-DarkGrayLine {[CmdletBinding()] param() Write-Host -ForegroundColor DarkGray '========================================================================='}
function Write-SectionHeader {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true,Position=0)][string]$Message)
    Write-DarkGrayLine
    Write-DarkGrayDate
    Write-Host -ForegroundColor Cyan $Message
}
function Write-SectionSuccess {
    [CmdletBinding()]
    param([Parameter(Position=0)][string]$Message='Success!')
    Write-DarkGrayDate
    Write-Host -ForegroundColor Green $Message
}
#endregion

# === Fork branding & source locations ===
# PARITY: this is the ONLINE deploy script (fetched by WinPE via win11.bencarver.com). Its
# Ambrosia-specific logic — the ZTI disk-safety guard and the ThinkBook driver-pack staging —
# must stay in sync with the OFFLINE fallback, ventoy-imaging/osdcloud/Invoke-OSDCloud-Ambrosia.ps1.
# Change one, mirror it in the other, or an online-vs-offline boot behaves differently.
$ScriptName    = 'win11.bencarver.com'
$ScriptVersion = '26.07.13.1'

# If you’re forking the helper BIOS scripts too, point this to YOUR GitHub raw base:
# Example: 'https://raw.githubusercontent.com/bencarver/osd-scripts/main/OSD/CloudOSD'
$VendorScriptBase = 'https://raw.githubusercontent.com/gwblok/garytown/master/OSD/CloudOSD'

Write-Host -ForegroundColor Green "$ScriptName $ScriptVersion"
#iex (irm functions.bencarver.com)    # optional: your custom functions
#iex (irm functions.osdcloud.com)     # optional: OSDCloud extra functions

<# Offline Driver Details
If you extract Driver Packs to your Flash Drive, you can DISM them in while in WinPE and it will make the process much faster, plus ensure driver support for first Boot
Extract to: OSDCLoudUSB:\OSDCloud\DriverPacks\DISM\$ComputerManufacturer\$ComputerProduct
Use OSD Module to determine Vars
$ComputerProduct = (Get-MyComputerProduct)
$ComputerManufacturer = (Get-MyComputerManufacturer -Brief)
#>

# Variables to define the Windows OS / Edition etc to be applied during OSDCloud
$Product       = (Get-MyComputerProduct)
$Model         = (Get-MyComputerModel)
$Manufacturer  = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer

$OSVersion     = 'Windows 11'      # Used to Determine Driver Pack
# Pin 25H2 (matches OSDCloud.json in the offline path) rather than 'Latest'/'Windows 11', which
# is dynamic and would jump to the next feature update when it ships. Start-OSDCloud's -OSName
# ValidSet keeps the " x64" suffix. TODO(windows): reconfirm against `Get-OSDCloudOperatingSystems`.
#$OSReleaseID   = 'Latest'          # dynamic — would follow whatever MS ships next
$OSReleaseID   = '25H2'            # Used to Determine Driver Pack
#$OSName        = 'Windows 11 24H2 x64'
$OSName        = 'Windows 11 25H2 x64'
$OSEdition     = 'Pro'             # <— changed from Enterprise to Pro
$OSActivation  = 'Volume'
$OSLanguage    = 'en-us'

# Set OSDCloud Vars
$Global:MyOSDCloud = [ordered]@{
    Restart                 = [bool]$true
    RecoveryPartition       = [bool]$true
    OEMActivation           = [bool]$true
    WindowsUpdate           = [bool]$true
    WindowsUpdateDrivers    = [bool]$true
    WindowsDefenderUpdate   = [bool]$true
    SetTimeZone             = [bool]$true
    ClearDiskConfirm        = [bool]$false
    ShutdownSetupComplete   = [bool]$false
    SyncMSUpCatDriverUSB    = [bool]$true
    CheckSHA1               = [bool]$true
}

# Used to Determine Driver Pack
$DriverPack = Get-OSDCloudDriverPack -Product $Product -OSVersion $OSVersion -OSReleaseID $OSReleaseID
if ($DriverPack) {
    $Global:MyOSDCloud.DriverPackName = $DriverPack.Name
}
#$Global:MyOSDCloud.DriverPackName = "None"

<# If Drivers are expanded on the USB Drive, disable installing a Driver Pack
if (Test-DISMFromOSDCloudUSB -eq $true){
    Write-Host "Found Driver Pack Extracted on Cloud USB Flash Drive, disabling Driver Download via OSDCloud" -ForegroundColor Green
    if ($Global:MyOSDCloud.SyncMSUpCatDriverUSB -eq $true){
        write-host "Setting DriverPackName to 'Microsoft Update Catalog'"
        $Global:MyOSDCloud.DriverPackName = 'Microsoft Update Catalog'
    } else {
        write-host "Setting DriverPackName to 'None'"
        $Global:MyOSDCloud.DriverPackName = "None"
    }
}
#>

# --- Ambrosia: ThinkBook machine type + manual driver-pack handoff -----------
# OSDCloud can't auto-inject our ThinkBook packs (21UY G9 IRL / 21SJ G8 IAL are absent from the
# Lenovo MECM/SCCM catalog it reads). We resolve the 4-char machine type here and, if the media
# has a pack staged for it (Build-OSDCloudMedia.ps1 -FetchDrivers puts it at
# OSDCloud\DriverPacks\Ambrosia\<MT>), tell OSDCloud NOT to fetch a pack — we stage it after apply.
$sku   = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).SystemSKUNumber
$csMod = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Model
$MachineType = if ($sku -match '_MT_([A-Za-z0-9]{4})') { $Matches[1] }
               elseif ($csMod -match '^([A-Za-z0-9]{4})') { $Matches[1] }
               else { $null }
Write-Host ("Ambrosia: target {0}  (SKU {1}; machine type {2})" -f $csMod, $sku, $MachineType) -ForegroundColor Cyan

$AmbrosiaPackSrc = $null
if ($MachineType) {
    $AmbrosiaPackSrc = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } |
        ForEach-Object { Join-Path ("{0}:\" -f $_.DriveLetter) ("OSDCloud\DriverPacks\Ambrosia\{0}" -f $MachineType) } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}
if ($AmbrosiaPackSrc) {
    Write-Host ("Ambrosia: found staged ThinkBook pack {0}; disabling OSDCloud driver download." -f $AmbrosiaPackSrc) -ForegroundColor Green
    $Global:MyOSDCloud.DriverPackName = 'None'
}

# Enable HPIA | Update HP BIOS | Update HP TPM
if (Test-HPIASupport){
    Write-SectionHeader -Message "Detected HP Device, Enabling HPIA, HP BIOS and HP TPM Updates"
    $Global:MyOSDCloud.HPTPMUpdate  = [bool]$True
    if ($Product -ne '83B2' -and $Model -notmatch "zbook"){ $Global:MyOSDCloud.HPIAALL = [bool]$true } # device-specific skip as in original
    $Global:MyOSDCloud.HPBIOSUpdate = [bool]$true

    # Apply HP BIOS settings (from your fork if you changed VendorScriptBase)
    iex (irm "$VendorScriptBase/Manage-HPBiosSettings.ps1")
    Manage-HPBiosSettings -SetSettings
}

# Lenovo BIOS settings
if ($Manufacturer -match "Lenovo") {
    iex (irm "$VendorScriptBase/Manage-LenovoBiosSettings.ps1")
    try { Manage-LenovoBIOSSettings -SetSettings } catch { }
}

# Write variables to console
Write-SectionHeader "OSDCloud Variables"
Write-Output $Global:MyOSDCloud

# Start OSDCloud deployment
Write-SectionHeader -Message "Starting OSDCloud"

# --- Ambrosia ZTI disk-safety guard ------------------------------------------
# ZTI is zero-touch and auto-wipes the internal disk with NO prompt. We only let it engage when
# there is EXACTLY ONE eligible internal disk; with 0 (dead/absent SSD) or >1 (multi-disk) we fall
# back to the interactive disk prompt. An internal NVMe reports BusType 'NVMe' (not 'USB'), so the
# filter keeps it and excludes the boot media. TODO(windows): a USB SSD/HDD bridge can report
# SATA/NVMe and slip through; test with the exact deploy USB attached before trusting ZTI.
$ZTIIntent = $false   # keep in sync with OSDCloud.json "ZTI" (offline path); set $true for hands-off
$eligible = @(Get-Disk | Where-Object { $_.BusType -ne 'USB' -and $_.Size -gt 60GB })
Write-Host ("Ambrosia: eligible internal disks: {0}" -f $eligible.Count) -ForegroundColor Cyan
$eligible | Format-Table Number, FriendlyName, BusType, @{n='GB';e={[int]($_.Size/1GB)}} -AutoSize | Out-String | Write-Host

$osdParams = @{ OSName = $OSName; OSEdition = $OSEdition; OSActivation = $OSActivation; OSLanguage = $OSLanguage }
if ($ZTIIntent -and $eligible.Count -eq 1) {
    Write-Host "Ambrosia: exactly one eligible internal disk -> zero-touch (ZTI)." -ForegroundColor Green
    $osdParams.ZTI = $true
    $Global:MyOSDCloud.ClearDiskConfirm = [bool]$false
} else {
    if ($ZTIIntent) { Write-Warning ("Ambrosia: ZTI requested but found {0} eligible internal disks -> disk PROMPT for safety." -f $eligible.Count) }
    $Global:MyOSDCloud.ClearDiskConfirm = [bool]$true
}

Write-Host ("Start-OSDCloud {0} {1} {2} {3}  ZTI={4}" -f $OSName,$OSEdition,$OSActivation,$OSLanguage,[bool]$osdParams.ZTI)
Start-OSDCloud @osdParams

Write-SectionHeader -Message "OSDCloud Process Complete, Running Custom Actions From Script Before Reboot"

# --- Ambrosia: stage the model-matched ThinkBook pack to the target OS -------
# OSDCloud applied Windows to the internal disk; find that volume (has \Windows, not WinPE's X:)
# and copy the pack we located on the USB ($AmbrosiaPackSrc) to <OS>:\Drivers\<MT> so
# SetupComplete\Ambrosia-Post.ps1 can pnputil-install it in the new OS.
# TODO(windows): confirm the applied-OS drive letter (OSDCloud usually maps it to C:).
if ($MachineType -and $AmbrosiaPackSrc) {
    $osVol = Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveLetter -and $_.DriveLetter -ne 'X' -and (Test-Path ("{0}:\Windows\System32" -f $_.DriveLetter)) } |
        Select-Object -First 1
    if ($osVol) {
        $dst = "{0}:\Drivers\{1}" -f $osVol.DriveLetter, $MachineType
        Write-Host ("Ambrosia: staging driver pack {0} -> {1}" -f $AmbrosiaPackSrc, $dst) -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path $dst | Out-Null
        Copy-Item -Path (Join-Path $AmbrosiaPackSrc '*') -Destination $dst -Recurse -Force
    } else {
        Write-Warning "Ambrosia: could not find the applied-OS volume; skipping driver-pack staging (OS falls back to Windows Update drivers)."
    }
} elseif ($MachineType) {
    Write-Warning ("Ambrosia: no staged pack for machine type {0} on the media; OS falls back to Windows Update drivers." -f $MachineType)
}

# Copy CMTrace local (handy for post-install log viewing)
if (Test-Path -Path "x:\windows\system32\cmtrace.exe"){
    Copy-Item "x:\windows\system32\cmtrace.exe" -Destination "C:\Windows\System\cmtrace.exe" -Verbose
}

# Lenovo PowerShell modules for post-OS use
if ($Manufacturer -match "Lenovo") {
    $PowerShellSavePath = 'C:\Program Files\WindowsPowerShell'
    Write-Host "Copy-PSModuleToFolder -Name LSUClient to $PowerShellSavePath\Modules"
    Copy-PSModuleToFolder -Name LSUClient -Destination "$PowerShellSavePath\Modules"
    Write-Host "Copy-PSModuleToFolder -Name Lenovo.Client.Scripting to $PowerShellSavePath\Modules"
    Copy-PSModuleToFolder -Name Lenovo.Client.Scripting -Destination "$PowerShellSavePath\Modules"
}

#restart-computer  # (OSDCloud typically handles the reboot)
