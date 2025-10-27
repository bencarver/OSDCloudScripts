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
$ScriptName    = 'win11.bencarver.com'
$ScriptVersion = '25.10.27.1'

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
$OSReleaseID   = '25H2'            # Used to Determine Driver Pack
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
Write-Host "Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage"

Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage

Write-SectionHeader -Message "OSDCloud Process Complete, Running Custom Actions From Script Before Reboot"

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
