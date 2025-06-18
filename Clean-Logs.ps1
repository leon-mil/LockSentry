<#
.SYNOPSIS
    Archive and delete log files based on retention or manual override.
    Log cleanup and archival script for LockSentry environments.

.DESCRIPTION
    Performs automated or manual cleanup of log files based on configuration settings.
    Supports multiple cleanup modes:
      - ArchiveAll: Move all matching files to archive folders by date.
      - PurgeLogs: Delete all log files in the active log folder.
      - PurgeArchive: Delete all files and folders in the archive directory.
      - Retention-based: Archive and delete files based on time thresholds from config.

.PARAMETER Environment
    Specifies which config to load ("dev" or "prod").

.PARAMETER ArchiveAll
    Archives all matching log files regardless of timestamp.

.PARAMETER PurgeLogs
    Deletes all matching log files in the LogFolder.

.PARAMETER PurgeArchive
    Deletes all archived files and their folders.

.NOTES
    File Name    : Clean-Logs.ps1
    Author       : Leon Mil
    Created On   : 2025-06-01
    Last Updated : 2025-06-10
    Version      : v1.0.0
    Tags         : Logging, Cleanup, Archival, Retention
    Environment  : dev | prod

.EXAMPLE
    .\Clean-Logs.ps1 -Environment dev
    Runs automated archive/delete logic based on config.

.EXAMPLE
    .\Clean-Logs.ps1 -Environment prod -ArchiveAll
    Archives all matching files immediately.

.EXAMPLE
    .\Clean-Logs.ps1 -Environment dev -PurgeLogs
    Deletes all logs in the target LogFolder.

.EXAMPLE
    .\Clean-Logs.ps1 -Environment prod -PurgeArchive
    Deletes all archived logs and folders.
#>

# ===================== Parameters/CmdletBinding =====================
<#
.SYNOPSIS
    Defines script parameters for environment targeting and log management mode.

.DESCRIPTION
    Accepts one mandatory environment selector and optional switches for log cleanup modes:
    - Environment: Specifies which config file to load (dev or prod).
    - ArchiveAll: Archives all matching log files, regardless of age.
    - PurgeLogs: Deletes all log files from the LogFolder.
    - PurgeArchive: Deletes all archived logs and their subfolders.

.PARAMETER Environment
    The target environment to load configuration from (dev or prod). Required.

.PARAMETER ArchiveAll
    If specified, archives all files from LogFolder to ArchiveFolder immediately.

.PARAMETER PurgeLogs
    If specified, deletes all logs from the LogFolder regardless of age.

.PARAMETER PurgeArchive
    If specified, deletes all archived files and empty folders under ArchiveFolder.

.EXAMPLE
    .\Clean-Logs.ps1 -Environment dev -PurgeLogs
    # Deletes all logs in the development log folder.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('dev','prod')] 
    [string] $Environment,
    [switch] $ArchiveAll,
    [switch] $PurgeLogs,
    [switch] $PurgeArchive
)

# Load configuration
# $jsonPath = Join-Path $PSScriptRoot 'Config\LogCleanup.json'
$jsonPath = Join-Path $PSScriptRoot ("Config\$Environment\LogCleanup.json")
if (-not (Test-Path $jsonPath)) {
    Write-Host "[INFO] LogCleanup.json not found. Exiting cleanup"
    return
}
$config = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json

if (-not $config.EnableCleanup) {
    Write-Host "[INFO] EnableCleanup is false. Skipping cleanup"
    return
}

# ===================== Configuration Settings =====================
# Extract relevant fields from the loaded config:
# - LogFolder:       Directory where active logs are located.
# - ArchiveFolder:   Destination folder for archived logs.
# - FilePatterns:    List of file patterns (e.g., *.log) to include in cleanup.
# - ArchiveAfter:    TimeSpan string (d:h:m:s) defining archive threshold.
# - DeleteAfter:     TimeSpan string (d:h:m:s) defining delete threshold.
$logFolder     = $config.LogFolder
$archiveFolder = $config.ArchiveFolder
$patterns      = $config.FilePatterns
$archiveAfter  = $config.ArchiveAfter
$deleteAfter   = $config.DeleteAfter

# ===================== NewArchiveFolder =====================
<#
.SYNOPSIS
    Creates archive subfolder for a given Year-Month string.

.DESCRIPTION
    Ensures the archive folder for the specified Year-Month exists,
    creating it if necessary, and returns the resulting path.

.PARAMETER YearMonth
    A string in the format 'yyyy-MM' to name the archive folder.

.OUTPUTS
    [string] Full path to the created or existing archive folder.

.EXAMPLE
    $folder = NewArchiveFolder -YearMonth "2025-06"
#>
function NewArchiveFolder {
    param(
        [Parameter(Mandatory)][string] $YearMonth
    )
    $dest = Join-Path $archiveFolder $YearMonth
    if (-not (Test-Path $dest)) {
        New-Item -Path $dest -ItemType Directory -Force | Out-Null
    }
    return $dest
}

<#
.SYNOPSIS
    Archives all log files in the configured log folder.

.DESCRIPTION
    When the -ArchiveAll switch is specified, this block:
    - Iterates over each configured file pattern.
    - Moves all matching files—regardless of last write time—into subfolders of ArchiveFolder.
    - Each file is placed into a subfolder named by its last write year and month (yyyy-MM).
    - Provides console output for each archived file and the target archive folder.

    This operation is useful for bulk archiving logs outside of the time-based retention policy.

.EXAMPLE
    .\Clean-Logs.ps1 -Environment prod -ArchiveAll
    # Archives all log files from the prod log directory into ArchiveFolder/yyyy-MM.
#>
if ($ArchiveAll) {
    Write-Host "[ACTION] Move all files from $logFolder to $archiveFolder"
    foreach ($pattern in $patterns) {
        Get-ChildItem -Path $logFolder -Filter $pattern -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer } |
        ForEach-Object {
            $yearMonth = $_.LastWriteTime.ToString('yyyy-MM')
            $dest      = NewArchiveFolder -YearMonth $yearMonth
            Move-Item -Path $_.FullName -Destination $dest -Force
            Write-Host "Archived: $($_.Name) to $yearMonth"
        }
    }
    Write-Host "[DONE] ArchiveAll complete"
    return
}

<#
.SYNOPSIS
    Deletes all log files from the configured log directory.

.DESCRIPTION
    When the -PurgeLogs switch is specified, this block:
    - Iterates over all file patterns defined in the configuration.
    - Deletes all matching files in the LogFolder, regardless of age or last write time.
    - Outputs each deleted file to the console for traceability.

    This is useful for fully clearing active logs, such as during a clean slate operation in dev or post-debug environments.

.EXAMPLE
    .\Clean-Logs.ps1 -Environment dev -PurgeLogs
    # Deletes all current log files from the dev log directory.
#>
if ($PurgeLogs) {
    Write-Host "[ACTION] Delete all files from $logFolder"
    foreach ($pattern in $patterns) {
        Get-ChildItem -Path $logFolder -Filter $pattern -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer } |
        ForEach-Object {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "Deleted: $($_.Name)"
        }
    }
    Write-Host "[DONE] PurgeLogs complete"
    return
}

<# 
.SYNOPSIS
    Deletes all archived log files and removes empty archive folders.

.DESCRIPTION
    When the -PurgeArchive switch is specified, this block:
    - Recursively deletes all non-container (file) items in the archive directory.
    - Logs each deleted archive file name.
    - Removes any subdirectories left empty after deletion to keep the archive folder clean.

    Useful for force-resetting the archive structure, especially during test runs or environment refreshes.

.EXAMPLE
    .\Clean-Logs.ps1 -Environment prod -PurgeArchive
    # Deletes all archived logs and cleans up empty folders under the configured archive folder.
#>
if ($PurgeArchive) {
    Write-Host "[ACTION] Delete everything in archive folder $archiveFolder"
    if (Test-Path $archiveFolder) {
        Get-ChildItem -Path $archiveFolder -Recurse -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer } |
        ForEach-Object {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "Deleted archive file: $($_.FullName.Substring($archiveFolder.Length + 1))"
        }
        Get-ChildItem -Path $archiveFolder -Directory |
        Where-Object { (Get-ChildItem -Path $_.FullName -Recurse | Measure-Object).Count -eq 0 } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "[DONE] PurgeArchive complete"
    return
}

# Parse ArchiveAfter into a TimeSpan
$partsArchive = $archiveAfter.Split(':')
[int]$daysA    = $partsArchive[0]
[int]$hoursA   = $partsArchive[1]
[int]$minsA    = $partsArchive[2]
[int]$secsA    = $partsArchive[3]
$archiveSpan   = New-TimeSpan -Days $daysA -Hours $hoursA -Minutes $minsA -Seconds $secsA

# Parse DeleteAfter into TimeSpan
$partsDelete = $deleteAfter.Split(':')
[int]$daysD   = $partsDelete[0]
[int]$hoursD  = $partsDelete[1]
[int]$minsD   = $partsDelete[2]
[int]$secsD   = $partsDelete[3]
$deleteSpan   = New-TimeSpan -Days $daysD -Hours $hoursD -Minutes $minsD -Seconds $secsD

# Automatic retention
$cutoffArchive = (Get-Date).Subtract($archiveSpan)
Write-Host "`n[AUTO] Archive files older than $archiveAfter (before $cutoffArchive)"

# Archive log files older than ArchiveAfter threshold
# Moves them into archive subfolders named yyyy-MM
foreach ($pattern in $patterns) {
    Get-ChildItem -Path $logFolder -Filter $pattern -ErrorAction SilentlyContinue |
    Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoffArchive } |
    ForEach-Object {
        $yearMonth = $_.LastWriteTime.ToString('yyyy-MM')
        $dest      = NewArchiveFolder -YearMonth $yearMonth
        Move-Item -Path $_.FullName -Destination $dest -Force
        Write-Host "Archived: $($_.Name) to $yearMonth"
    }
}

$cutoffDelete = (Get-Date).Subtract($deleteSpan)
Write-Host "`n[AUTO] Delete files older than $deleteAfter (before $cutoffDelete)"

# Delete log files older than DeleteAfter threshold
# Applies to files in LogFolder matching configured patterns
foreach ($pattern in $patterns) {
    Get-ChildItem -Path $logFolder -Filter $pattern -ErrorAction SilentlyContinue |
    Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoffDelete } |
    ForEach-Object {
        Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "Deleted (Log): $($_.Name)"
    }
}

# Delete archived files older than DeleteAfter threshold
# Then remove any empty subdirectories left behind
if (Test-Path $archiveFolder) {
    Get-ChildItem -Path $archiveFolder -Recurse -ErrorAction SilentlyContinue |
    Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoffDelete } |
    ForEach-Object {
        Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "Deleted (Archive): $($_.FullName.Substring($archiveFolder.Length + 1))"
    }
    Get-ChildItem -Path $archiveFolder -Directory |
    Where-Object { (Get-ChildItem -Path $_.FullName -Recurse | Measure-Object).Count -eq 0 } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n[DONE] Automatic cleanup complete"
