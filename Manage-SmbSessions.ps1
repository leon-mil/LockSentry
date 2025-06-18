<#
.SYNOPSIS
    Executes SMB session scan, summary, and optional closure via SmbSessionManager.

.DESCRIPTION
    This script loads the environment-specific SmbSessions.json configuration and:
      - Imports required modules (Core, LogManager, SmbSessionManager)
      - Initializes logging if enabled
      - Executes the SMB session handling routine (scan, filter, close, and log)

.PARAMETER EnvName
    Target environment to use when resolving the config file path (e.g., dev or prod). Default is 'dev'.

.NOTES
    File Name    : Manage-SmbSessions.ps1
    Author       : Leon Mil
    Created On   : 2025-06-01
    Last Updated : 2025-06-10
    Version      : 1.0.0
    Tags         : SMB, Sessions, Automation, Logging
    Environment  : dev | prod

.EXAMPLE
    .\Manage-SmbSessions.ps1
    # Runs the session manager using the default (dev) environment config.

.EXAMPLE
    .\Manage-SmbSessions.ps1 -EnvName prod
    # Runs the session cleanup using the production SmbSessions.json configuration.
#>

# ===================== PARAMETERS =====================
param(
  [ValidateSet('dev','prod')]
  [string] $EnvName = 'dev'
)

# ===================== MODULE IMPORTS =====================
# Load core functionality (Write-Box, Get-Config)
Import-Module LockSentry.Core               -Force -DisableNameChecking

# Load logging utilities (Initialize-Log, Write-Log)
Import-Module LockSentry.LogManager         -Force -DisableNameChecking

# Load the SMB session manager for scanning & closing sessions
Import-Module LockSentry.SmbSessionManager  -Force -DisableNameChecking

# ===================== LOAD CONFIG =====================
# Load the environment-specific SmbSessions.json
$smbSessionsConfig = Join-Path $PSScriptRoot "Config\$EnvName\SmbSessions.json"
$config = Get-Content -Raw -Path $smbSessionsConfig | ConvertFrom-Json

# ===================== INITIALIZE LOGGING =====================
# Start logging only if enabled in config and not already initialized globally
if ($config.EnableLog -and -not (Get-Variable -Name LogInitialized -Scope Global -ErrorAction SilentlyContinue)) {
  Initialize-Log `
    -BasePath $config.LogDirectory `
    -BaseName "SessionLog" `
    -UseTimestamp:($config.UseTimestamp) `
    -TimestampResolution $config.TimestampResolution `
    -AppendToExisting:($config.AppendToExisting)
}

# ===================== EXECUTE WORKFLOW =====================
# Run the SMB session management process using the loaded config
Invoke-SmbSessionProcess -ConfigFile $smbSessionsConfig
