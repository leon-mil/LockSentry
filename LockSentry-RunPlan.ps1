<#
.SYNOPSIS
    Executes the LockSentry execution plan using environment-specific configuration.

.DESCRIPTION
    Reads `RunPlan.json` under the selected environment directory (e.g., Config\prod\RunPlan.json),
    and executes each step listed in the `ExecutionPlan` array. Each step can repeat multiple times.

    Supported steps include:
      - Manage-SmbFiles.ps1   → Executes file handle scanning and closure logic
      - Manage-SmbSessions.ps1 → Executes SMB session scanning and cleanup logic

    This script also:
      - Loads and applies the active environment (from Environment.json)
      - Cleans up logs via Clean-Logs.ps1
      - Installs or updates modules from Modules.json
      - Initializes logging when configured per step
      - Validates that the script is running with Administrator privileges

.PARAMETER EnvConfigFile
    Optional path to the environment config file (default: Config\Environment.json)

.NOTES
    File Name    : LockSentry-RunPlan.ps1
    Author       : Leon Mil
    Created On   : 2025-06-01
    Last Updated : 2025-06-10
    Version      : 1.0.0
    Tags         : LockSentry, Execution Plan, SMB Cleanup, Task Runner
    Environment  : dev | prod

.EXAMPLE
    .\LockSentry-RunPlan.ps1
    # Runs all configured steps using the current environment in Config\Environment.json

.EXAMPLE
    .\LockSentry-RunPlan.ps1 -EnvConfigFile "D:\Custom\Config\Environment.json"
    # Overrides the default environment file and runs the plan accordingly
#>

param(
    [string] $EnvConfigFile = "$PSScriptRoot\Config\Environment.json"
)

# Ensure script is running as Administrator 
$winPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $winPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator. Exiting." -ForegroundColor Red
    exit 1
}

# Read current environment (dev or prod)
if (-not (Test-Path $EnvConfigFile)) {
    Write-Host "[ERROR] Environment config not found: $EnvConfigFile" -ForegroundColor Red
    exit 1
}

$envName = (Get-Content $EnvConfigFile -Raw | ConvertFrom-Json).CurrentEnv

if (-not $envName) {
    Write-Host "[ERROR] CurrentEnv not defined in $EnvConfigFile" -ForegroundColor Red
    exit 1
}

Write-Host "==> Using environment: $envName" -ForegroundColor Cyan

# Define base config folder for this environment
$configFolder = Join-Path $PSScriptRoot "Config\$envName"

# Point $ConfigFile to the env‐specific RunPlan.json
$ConfigFile = Join-Path $configFolder 'RunPlan.json'

# Clean up old log files
Write-Host "=================== LOG CLEANUP ====================" -ForegroundColor Cyan
Write-Host "Cleaning up old log files (using $configFolder\LogCleanup.json)." -ForegroundColor Yellow
& "$PSScriptRoot\Clean-Logs.ps1" -Environment $envName

# Install or update modules listed in Modules.json
$modulesConfigPath = Join-Path $configFolder 'Modules.json'
if (Test-Path $modulesConfigPath) {    
    & "$PSScriptRoot\Manage-Modules.ps1" -Environment $envName -Install
}
else {
    Write-Host "[WARN] Modules.json not found at $modulesConfigPath → skipping module installation." -ForegroundColor Yellow
}

# Import Core so Write-Box & Get-Config are available
Import-Module LockSentry.Core -Force -DisableNameChecking

# Load the run plan and execute steps
$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json

# ===================== Execute Run Plan =====================
# For each step defined in RunPlan.json:
# - Repeat it according to the specified Times count
# - Display a status banner using Write-Box
# - Dynamically import the appropriate module (SmbFileManager or SmbSessionManager)
# - Load the corresponding config file (SmbFiles.json or SmbSessions.json)
# - Initialize logging if enabled and not yet initialized
# - Execute the appropriate process function:
#     - Invoke-SmbFileProcess
#     - Invoke-SmbSessionProcess
# - Handle missing config files or unknown script names gracefully
foreach ($step in $config.ExecutionPlan) {
    for ($i = 1; $i -le $step.Times; $i++) {
        Write-Box -Text "Running step: $($step.Script) (iteration $i of $($step.Times))" `
            -Width 60 -Align Center -BorderChar '*' -BorderColor Magenta -TextColor Green `
            -BlankLinesBefore 1

        switch ($step.Script) {
            'Manage-SmbFiles.ps1' {
                Import-Module LockSentry.SmbFileManager -Force -DisableNameChecking
                $smbFilesConfig = Join-Path $configFolder 'SmbFiles.json'
                if (-not (Test-Path $smbFilesConfig)) {
                    Write-Host "[ERROR] SmbFiles.json not found at $smbFilesConfig" -ForegroundColor Red
                    continue
                }

                # Initialize logging if enabled
                $configObj = Get-Content $smbFilesConfig -Raw | ConvertFrom-Json
                if ($configObj.EnableLog -and -not (Get-Variable -Name LogInitialized -Scope Global -ErrorAction SilentlyContinue)) {
                    Initialize-Log `
                        -BasePath $configObj.LogDirectory `
                        -BaseName "SMBLog" `
                        -UseTimestamp:($configObj.UseTimestamp) `
                        -TimestampResolution $configObj.TimestampResolution `
                        -AppendToExisting:($configObj.AppendToExisting)
                }

                # Invoke-SmbFileProcess -ConfigFile "$PSScriptRoot\Config\SmbFiles.json"
                Invoke-SmbFileProcess -ConfigFile $smbFilesConfig 
            }
            'Manage-SmbSessions.ps1' {
                Import-Module LockSentry.SmbSessionManager -Force -DisableNameChecking
                # Invoke-SmbSessionProcess -ConfigFile "$PSScriptRoot\Config\SmbSessions.json"
                $smbSessionsConfig = Join-Path $configFolder 'SmbSessions.json'
                if (-not (Test-Path $smbSessionsConfig)) {
                    Write-Host "[ERROR] SmbSessions.json not found at $smbSessionsConfig" -ForegroundColor Red
                    continue
                }

                # Initialize logging if enabled
                $configObj = Get-Content $smbSessionsConfig -Raw | ConvertFrom-Json
                if ($configObj.EnableLog -and -not (Get-Variable -Name LogInitialized -Scope Global -ErrorAction SilentlyContinue)) {
                    Initialize-Log `
                        -BasePath $configObj.LogDirectory `
                        -BaseName "SessionLog" `
                        -UseTimestamp:($configObj.UseTimestamp) `
                        -TimestampResolution $configObj.TimestampResolution `
                        -AppendToExisting:($configObj.AppendToExisting)
                }

                Invoke-SmbSessionProcess -ConfigFile $smbSessionsConfig
            }
            default {
                Write-Box -Text "Unknown plan entry: $($step.Script)" `
                    -BorderChar '!' -BorderColor Red -TextColor Yellow -BlankLinesBefore 1
            }
        }

        Write-Host ""
    }
}
