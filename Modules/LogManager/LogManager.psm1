<#
.SYNOPSIS
    Logging utilities for LockSentry modules and tasks.

.DESCRIPTION
    This module provides lightweight logging support for LockSentry scripts and modules.
    It allows scripts to create timestamped log files and write structured log entries
    with levels such as INFO, WARN, ERROR, and DEBUG.

.NOTES
    File Name    : LogManager.psm1
    Author       : Leon Mil
    Created On   : 2025-06-01
    Last Updated : 2025-06-10
    Version      : v1.0.0
    Tags         : Logging, Utilities, Output, Timestamp
    Environment  : common
#>

# ===================== Global Variable =====================
# Declared globally for use in calling scripts and other modules.
$Global:LS_LogFilePath = $null

# ===================== Initialize-Log =====================
<#
.SYNOPSIS
    Initializes a log file with optional timestamp and appending support.

.DESCRIPTION
    Prepares a log file path based on a given base name and directory. Supports automatic
    directory creation, optional timestamp resolution, and the ability to overwrite or append
    to existing log files. Sets a global variable ($Global:LS_LogFilePath) for access by
    other functions and scripts.

.PARAMETER BasePath
    Target directory where the log file will be created.

.PARAMETER BaseName
    Base name of the log file (e.g., "Task_Log").

.PARAMETER UseTimestamp
    If set, adds a timestamp to the log filename.

.PARAMETER TimestampResolution
    Precision of timestamp. Can be "second" (default) or "millisecond".

.PARAMETER AppendToExisting
    If specified, existing log file will not be overwritten.

.EXAMPLE
    Initialize-Log -BasePath "D:\CPRS\PROD\Logs" -BaseName "SMBLog" -UseTimestamp

.EXAMPLE
    Initialize-Log -BasePath ""D:\CPRS\PROD\Logs" -BaseName "DailyTask" -UseTimestamp -TimestampResolution "millisecond"

.EXAMPLE
    Initialize-Log -BasePath "$PSScriptRoot\Logs" -BaseName "run" -AppendToExisting

.NOTES
    Must be called before using Write-Log.
#>
function Initialize-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $BasePath,
        [Parameter(Mandatory)] [string] $BaseName,
        [switch] $UseTimestamp,
        [ValidateSet("second", "millisecond")] [string] $TimestampResolution = "second",
        [switch] $AppendToExisting
    )

    if (!(Test-Path $BasePath)) {
        New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
    }

    $timestamp = ""
    if ($UseTimestamp) {
        $format = if ($TimestampResolution -eq "millisecond") { "yyyyMMdd_HHmmss_fff" } else { "yyyyMMdd_HHmmss" }
        $timestamp = "_$((Get-Date).ToString($format))"
    }

    $logFileName = "$BaseName$timestamp.log"
    $logFilePath = Join-Path $BasePath $logFileName

    if (-not $AppendToExisting -and (Test-Path $logFilePath)) {
        Remove-Item $logFilePath -Force
    }

    # Assigned globally for access from external scripts
    $Global:LS_LogFilePath = $logFilePath 
    if ($Global:LS_LogFilePath) { }
}

# ===================== Write-Log =====================
<#
.SYNOPSIS
    Writes a log entry to the initialized log file.

.DESCRIPTION
    Appends a timestamped log entry to the global log file. The log level can be set
    to INFO, WARN, ERROR, or DEBUG. Requires prior call to Initialize-Log.

.PARAMETER Message
    The message content to log.

.PARAMETER Level
    Log severity level. Options: INFO (default), WARN, ERROR, DEBUG.

.EXAMPLE
    Write-Log -Message "Script started"

.EXAMPLE
    Write-Log -Message "Configuration file missing" -Level WARN

.EXAMPLE
    Write-Log -Message "Validation failed for user input" -Level ERROR

.NOTES
    Will throw an error if Initialize-Log was not called first.
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")] [string] $Level = "INFO"
    )

    if (-not $Global:LS_LogFilePath) {
        throw "Log has not been initialized. Call Initialize-Log first."
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $entry = "[{0}] [{1}] {2}" -f $timestamp, $Level.ToUpper(), $Message
    Add-Content -Path $Global:LS_LogFilePath -Value $entry
}

# ======================= Export ========================
# Export public functions so they are accessible when this module is imported.
# Only Initialize-Log and Write-Log are exposed; all other logic remains internal.
Export-ModuleMember -Function Initialize-Log, Write-Log
