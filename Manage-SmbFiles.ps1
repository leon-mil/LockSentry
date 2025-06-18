<#
.SYNOPSIS
    Executes SMB file handle scan and closure using LockSentry.SmbFileManager.

.DESCRIPTION
    This script loads the environment-specific configuration file (SmbFiles.json) and:
      - Imports all required modules (Core, LogManager, SmbFileManager)
      - Initializes logging if enabled
      - Invokes the file handle processing routine to scan, log, and optionally close open files

.PARAMETER EnvName
    Target environment to use when resolving the config file path (e.g., dev or prod). Default is 'dev'.

.NOTES
    File Name    : Manage-SmbFiles.ps1
    Author       : Leon Mil
    Created On   : 2025-06-01
    Last Updated : 2025-06-10
    Version      : 1.0.0
    Tags         : SMB, File Locks, Automation, Logging
    Environment  : dev | prod

.EXAMPLE
    .\Manage-SmbFiles.ps1
    # Runs the file handle cleanup using the default (dev) config.

.EXAMPLE
    .\Manage-SmbFiles.ps1 -EnvName prod
    # Runs the process using the production SmbFiles.json configuration.
#>

param(
  [ValidateSet('dev','prod')]
  [string] $EnvName = 'dev'
)

# ===================== MODULE IMPORTS =====================

# Import LockSentry core utilities (Write-Box, Get-Config)
Import-Module LockSentry.Core             -Force -DisableNameChecking

# Import logging utilities (Initialize-Log, Write-Log)
Import-Module LockSentry.LogManager       -Force -DisableNameChecking

# Import SMB file manager for detecting and closing open file handles
Import-Module LockSentry.SmbFileManager   -Force -DisableNameChecking

# Build the per-environment path to SmbFiles.json:
$smbFilesConfig = Join-Path $PSScriptRoot "Config\$EnvName\SmbFiles.json"
$config = Get-Content -Raw -Path $smbFilesConfig | ConvertFrom-Json

# ===================== INITIALIZE LOGGING =====================
# Start logging only if enabled in config and not already initialized globally
if ($config.EnableLog -and -not (Get-Variable -Name LogInitialized -Scope Global -ErrorAction SilentlyContinue)) {
  Initialize-Log `
      -BasePath $config.LogDirectory `
      -BaseName "SMBLog" `
      -UseTimestamp:($config.UseTimestamp) `
      -TimestampResolution $config.TimestampResolution `
      -AppendToExisting:($config.AppendToExisting)
}

# ===================== EXECUTE WORKFLOW =====================
# Run the SMB file lock scanning and cleanup process using the loaded config
Invoke-SmbFileProcess -ConfigFile $smbFilesConfig

