<#
.SYNOPSIS
    Lists, installs, or removes LockSentry modules defined in Modules.json.

.DESCRIPTION
    This script performs module management based on the selected environment:
      - Loads Config\<Environment>\Modules.json
      - Supports listing installed modules, installing them from source, or removing all versions.

    Installation logic:
      - For each module:
        - Finds one *.psd1 manifest in the source folder
        - Extracts ModuleVersion from the manifest
        - Copies source contents into: DestinationRoot\<Name>\<Version>\
        - Renames the manifest to <Name>.psd1 for Import-Module compatibility
        - Optionally skips or reinstalls based on AlwaysReinstall

.PARAMETER Environment
    Required environment name (e.g., dev or prod) to resolve config path.

.PARAMETER Install
    Install modules listed in Modules.json, respecting AlwaysReinstall setting.

.PARAMETER Remove
    Remove all installed versions of each module listed.

.PARAMETER List
    Show currently installed module versions. This is the default behavior.

.NOTES
    File Name    : Manage-Modules.ps1
    Author       : Leon Mil
    Created On   : 2025-06-01
    Last Updated : 2025-06-10
    Version      : 1.0.0
    Tags         : Modules, Installation, PowerShell, LockSentry
    Environment  : dev | prod

.EXAMPLE
    .\Manage-Modules.ps1 -Environment dev -Install

.EXAMPLE
    .\Manage-Modules.ps1 -Environment prod -Remove

.EXAMPLE
    .\Manage-Modules.ps1 -Environment dev -List
#>



# ===================== PARAMETERS =====================
<#
.SYNOPSIS
    Defines the execution mode and environment for module management.

.DESCRIPTION
    Accepts a required environment name and optional flags to control behavior:
    - Environment: Specifies which config file to load (e.g., dev or prod)
    - Install:     Installs all modules defined in the config
    - List:        Displays currently installed module versions (default)
    - Remove:      Deletes all installed versions of each configured module
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('dev','prod')]
    [string] $Environment,

    [switch] $Install,  # Install modules
    [switch] $List,     # List installed module versions
    [switch] $Remove    # Remove all installed modules
)

# ===================== Privilege Validation =====================
# Ensure the script is running with administrative privileges
$winPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $winPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator. Exiting." -ForegroundColor Red
    exit 1
}

# ===================== Load Configuration =====================
# Load Modules.json based on the specified environment
$ConfigFile = Join-Path $PSScriptRoot ("Config\$Environment\Modules.json")

# If user requested List or Remove and Modules.json is missing, bail out
if (($List.IsPresent -or $Remove.IsPresent) -and -not (Test-Path $ConfigFile)) {
    Write-Host "[WARN] Modules.json not found at $ConfigFile; nothing to list or remove." -ForegroundColor Yellow
    return
}

if (($List.IsPresent -or $Remove.IsPresent) -and -not (Test-Path $ConfigFile)) {
    Write-Host "[WARN] Modules.json not found at $ConfigFile; nothing to list or remove." -ForegroundColor Yellow
}

# Otherwise, fail if ConfigFile does not exist at all
if (-not (Test-Path $ConfigFile)) {
    Write-Error "Config file not found: $ConfigFile"
    exit 1
}

# Read JSON
$config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json

# ===================== Evaluate Settings =====================

# Determine AlwaysReinstall flag and the target install path
if ($config.PSObject.Properties.Match('AlwaysReinstall').Count -gt 0 -and ($config.AlwaysReinstall -is [bool])) {
    $alwaysReinstall = $config.AlwaysReinstall
} else {
    $alwaysReinstall = $false
}

# Determine the destination root folder
if ($config.PSObject.Properties.Match('DestinationRoot').Count -gt 0 -and $config.DestinationRoot.Trim()) {
    $destRoot = $config.DestinationRoot
} else {
    $destRoot = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'
}

# ===================== MODULE LIST =====================
# Show installed versions of each module listed in the config
if ($List.IsPresent -or (-not $Install.IsPresent -and -not $Remove.IsPresent)) {
    Write-Host ""
    Write-Host "================ INSTALLED MODULES ================" -ForegroundColor Cyan
    foreach ($entry in $config.Modules) {
        $moduleName = $entry.Name
        $moduleRoot = Join-Path $destRoot $moduleName

        if (-not (Test-Path $moduleRoot)) {
            Write-Host "[INFO] ${moduleName}: Not installed" -ForegroundColor White
            continue
        }

        $versions = Get-ChildItem -Path $moduleRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        if ($versions) {
            $versionList = $versions -join ', '
            Write-Host "[INFO] ${moduleName}: Installed versions: $versionList" -ForegroundColor White
        } else {
            Write-Host "[INFO] ${moduleName}: No version folders found under $moduleRoot" -ForegroundColor White
        }
    }
    Write-Host ""
    return
}

# ===================== MODULE REMOVAL =====================
# Remove all installed versions of each module
if ($Remove.IsPresent) {
    Write-Host ""
    Write-Host "================ MODULE REMOVAL ================" -ForegroundColor Cyan
    foreach ($entry in $config.Modules) {
        $moduleName = $entry.Name
        $moduleRoot = Join-Path $destRoot $moduleName

        if (-not (Test-Path $moduleRoot)) {
            Write-Host "[INFO] ${moduleName}: Nothing to delete" -ForegroundColor White
            continue
        }

        try {
            Remove-Item -Path $moduleRoot -Recurse -Force -ErrorAction Stop
            Write-Host "[INFO] Deleted all versions of $moduleName from $moduleRoot" -ForegroundColor White
        } catch {
            Write-Host "[WARN] Failed to delete $moduleName at $moduleRoot`: $_" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    return
}

# ===================== MODULE INSTALLATION =====================
# For each module:
# - Validate source and manifest
# - Copy contents to versioned folder
# - Rename manifest
# - Import the module
if ($Install.IsPresent) {
    Write-Host ""
    Write-Host "=============== MODULE INSTALLATION ===============" -ForegroundColor Cyan

    if ($alwaysReinstall) {
        Write-Host "[INFO] AlwaysReinstall = true  (will overwrite existing versions)" -ForegroundColor Yellow
    } else {
        Write-Host "[INFO] AlwaysReinstall = false (skip if already installed)" -ForegroundColor Yellow
    }

    $importPaths = @()

    # ===================== INSTALL EACH MODULE =====================
    # For each module in the config:
    # - Resolve source folder and validate existence
    # - Locate the single *.psd1 manifest and read ModuleVersion
    # - Build the target destination: DestinationRoot\<Module>\<Version>\
    # - If AlwaysReinstall = true: remove existing version folder
    # - If AlwaysReinstall = false and version exists: skip and queue for import
    # - Copy all source files to the versioned folder
    # - Rename the copied manifest to <ModuleName>.psd1 to support Import-Module
    # - Validate RootModule file exists
    # - Queue the renamed manifest path for import
    foreach ($entry in $config.Modules) {
        $moduleName = $entry.Name
        $srcPath    = Join-Path $PSScriptRoot $entry.SourcePath

        if (-not (Test-Path $srcPath)) {
            Write-Host "[WARN] Source folder not found for '$moduleName'`: $srcPath" -ForegroundColor Yellow
            continue
        }

        # Find exactly one *.psd1 in the source folder
        $manifests = Get-ChildItem -Path $srcPath -Filter '*.psd1' -File -ErrorAction SilentlyContinue
        if ($manifests.Count -eq 0) {
            Write-Host "[WARN] No .psd1 manifest found in $srcPath" -ForegroundColor Yellow
            continue
        }
        if ($manifests.Count -gt 1) {
            Write-Host "[WARN] Multiple .psd1 files in $srcPath`; expected exactly one." -ForegroundColor Yellow
            continue
        }

        $manifestPath = $manifests[0].FullName

        try {
            $manifestData = Import-PowerShellDataFile -Path $manifestPath
        } catch {
            Write-Host "[WARN] Unable to read manifest '$manifestPath'`: $_" -ForegroundColor Yellow
            continue
        }

        $version = $manifestData.ModuleVersion
        if (-not [version]::TryParse($version, [ref] $null)) {
            Write-Host "[WARN] Invalid ModuleVersion '$version' in $manifestPath" -ForegroundColor Yellow
            continue
        }

        # Build the “versioned” destination folder
        $moduleRoot    = Join-Path $destRoot $moduleName
        $versionFolder = Join-Path $moduleRoot $version
        
        # If the folder exists and AlwaysReinstall = true, delete it;
        # if AlwaysReinstall = false, skip and queue existing PSD1.
        if (Test-Path $versionFolder) {
            if ($alwaysReinstall) {
                Write-Host "`n[INFO] Reinstalling $moduleName v$version (AlwaysReinstall = true)" -ForegroundColor Yellow
                try {
                    Remove-Item -Path $versionFolder -Recurse -Force -ErrorAction Stop
                } catch {
                    Write-Error "Could not remove existing folder $versionFolder`: $_"
                    continue
                }
            }
            else {
                Write-Host "[INFO] Skipping $moduleName v$version (AlwaysReinstall = false; already installed)" -ForegroundColor White
                # Queue the existing PSD1 for import
                $importPaths += Join-Path $versionFolder "$moduleName.psd1"
                continue
            }
        }

        # Now that the old folder is gone (or never existed), recreate versionFolder
        try {
            New-Item -Path $versionFolder -ItemType Directory -Force | Out-Null
        } catch {
            Write-Error "Could not create directory $versionFolder`: $_"
            continue
        }

        # Copy everything from source into the newly created version folder
        try {
            Copy-Item -Path (Join-Path $srcPath '*') `
                      -Destination $versionFolder `
                      -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Error "Failed to copy files to $versionFolder`: $_"
            continue
        }

        # Rename the copied PSD1 so that ‘Import-Module <ModuleName>’ works
        $copiedManifest = Get-ChildItem -Path $versionFolder -Filter '*.psd1' -File -Recurse | Select-Object -First 1
        if ($copiedManifest) {
            $newName = "$moduleName.psd1"
            try {
                Rename-Item -Path $copiedManifest.FullName -NewName $newName -ErrorAction Stop
                Write-Host "[INFO] Renamed '$($copiedManifest.Name)' to '$newName'." -ForegroundColor White
            } catch {
                Write-Host "[WARN] Could not rename '$($copiedManifest.Name)' in '$versionFolder'`: $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[WARN] No manifest found in '$versionFolder' to rename." -ForegroundColor Yellow
            continue
        }

        # Verify that the RootModule file exists under the new path
        $rootModule = $manifestData.RootModule
        if (-not (Test-Path (Join-Path $versionFolder $rootModule))) {
            Write-Host "[WARN] RootModule '$rootModule' not found under $versionFolder" -ForegroundColor Yellow
            continue
        }

        Write-Host "[INFO] $moduleName v$version installed to '$versionFolder'" -ForegroundColor White

        # Queue up the renamed PSD1 for final import
        $importPaths += Join-Path $versionFolder "$moduleName.psd1"
    }

    # Import each newly-installed module by its PSD1 path
    if ($importPaths.Count -gt 0) {
        Write-Host "`n[INFO] Importing modules:" -ForegroundColor Yellow
        foreach ($path in $importPaths) {
            if (Test-Path $path) {
                try {
                    Import-Module $path -Force -DisableNameChecking
                    Write-Host "[INFO] Imported module from '$path'" -ForegroundColor White
                } catch {
                    Write-Host "[WARN] Could not import module from '$path'`: $_" -ForegroundColor Yellow
                }
            }
        }
    }
    Write-Host ""
    return
}

# ===================== DEFAULT TO LIST =====================
# If no switch matched, fallback to listing module versions
Write-Host ""
Write-Host "================ INSTALLED MODULES ================" -ForegroundColor Cyan
foreach ($entry in $config.Modules) {
    $moduleName = $entry.Name
    $moduleRoot = Join-Path $destRoot $moduleName

    if (-not (Test-Path $moduleRoot)) {
        Write-Host "[INFO] ${moduleName}: Not installed" -ForegroundColor White
        continue
    }

    $versions = Get-ChildItem -Path $moduleRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    if ($versions) {
        $versionList = $versions -join ', '
        Write-Host "[INFO] ${moduleName}: Installed versions: $versionList" -ForegroundColor White
    } else {
        Write-Host "[INFO] ${moduleName}: No version folders found under $moduleRoot" -ForegroundColor White
    }
}
