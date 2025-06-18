<#
.SYNOPSIS
    SMB file handle scanning and session closing utilities for LockSentry.

.DESCRIPTION
    This module scans directories for locked SMB file handles, summarizes config settings,
    logs open files, and optionally closes handles automatically based on filtering rules.

.NOTES
    File Name    : SmbFileManager.psm1
    Author       : Leon Mil
    Created On   : 2025-06-01
    Last Updated : 2025-06-10
    Version      : v1.0.0
    Tags         : SMB, Handles, File Locks, Cleanup, Logging
    Environment  : prod | dev
#>

# ===================== Dependencies =====================
# Import core and logging modules required for configuration loading
# and centralized log output. DisableNameChecking is used to allow
# unconventional function or variable names without warning.
Import-Module LockSentry.Core -Force -DisableNameChecking
Import-Module LockSentry.LogManager -Force -DisableNameChecking

# ===================== Get-SmbOpenHandles =====================
<#
.SYNOPSIS
    Retrieves open SMB file handles matching specified directories.

.DESCRIPTION
    Scans current SMB sessions for file handles where the file path starts with any of the
    specified directories. Optionally logs each detected handle and returns a list of 
    handle objects with metadata.

.PARAMETER Dirs
    An array of directory paths to scan for open SMB handles.

.PARAMETER Quiet
    If specified, suppresses console output during scanning.

.OUTPUTS
    [PSCustomObject[]] List of objects with properties:
        FilePath, SessionId, FileId, Client, Computer

.EXAMPLE
    Get-SmbOpenHandles -Dirs "D:\DATA\SHARED"

.EXAMPLE
    Get-SmbOpenHandles -Dirs @("D:\A", "D:\B") -Quiet
#>
function Get-SmbOpenHandles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $Dirs,
        [switch] $Quiet
    )
    $results = @()
    foreach ($d in $Dirs) {
        if (-not $Quiet) { Write-Host "Scanning SMB opens in: $d" }
        $results += Get-SmbOpenFile |
            Where-Object Path -like "$d*" |
            ForEach-Object {
                Write-Log -Message "LOCKED: $($_.Path) | User: $($_.ClientUserName) | Computer: $($_.ClientComputerName) | SessionId: $($_.SessionId) | FileId: $($_.FileId)" -Level INFO
                [PSCustomObject]@{
                    FilePath  = $_.Path
                    SessionId = $_.SessionId
                    FileId    = $_.FileId
                    Client    = ($_.ClientUserName.Split('\')[-1])
                    Computer  = $_.ClientComputerName
                }
            }
    }
    return $results
}

# ===================== Show-FileLockSummary =====================
<#
.SYNOPSIS
    Displays a visual summary of configuration settings for file handle scanning.

.DESCRIPTION
    Prints formatted console boxes and tables summarizing:
    - Directories being scanned
    - Operational mode and logging flags
    - Included and excluded users
    - Available execution modes

.PARAMETER Config
    A configuration object containing keys like DirectoriesToScan, Mode, IncludeUsers, etc.

.EXAMPLE
    Show-FileLockSummary -Config $config
#>
function Show-FileLockSummary {
    param([pscustomobject]$Config)

    Write-Box -Text "Configuration Summary" -Width 60 -Align Center `
        -BorderChar '#' -BorderColor Cyan -TextColor Yellow `
        -BlankLinesBefore 1 -BlankLinesAfter 1

    Write-Box -Text "Directories to Scan:" -NoBorder -Width 30 -Align Left `
        -TextColor Green -BlankLinesAfter 1
    $Config.DirectoriesToScan | ForEach-Object { Write-Host "  - $_" }

    Write-Box -Text "Settings:" -NoBorder -Width 30 -Align Left `
        -TextColor Green -BlankLinesBefore 1 -BlankLinesAfter 1
    [PSCustomObject]@{ Name='Mode'; Value=$Config.Mode; Description='All|Targets|ScanOnly' },
    [PSCustomObject]@{ Name='ShowSummary'; Value=$Config.ShowSummary },
    [PSCustomObject]@{ Name='EnableLog'; Value=$Config.EnableLog },
    [PSCustomObject]@{ Name='CloseHandles'; Value=$Config.CloseHandles },
    [PSCustomObject]@{ Name='LogDirectory'; Value=$Config.LogDirectory } |
      Format-Table -AutoSize | Out-String -Width 4096 -Stream |
      Where-Object { $_.Trim() } | ForEach-Object { $_.TrimEnd() }

    Write-Box -Text "Available Modes:" -NoBorder -Width 30 -Align Left `
        -TextColor Green -BlankLinesBefore 1 -BlankLinesAfter 1
    @(
      @{ Mode='All'; Description='Close every handle'; Current=($Config.Mode -eq 'All') },
      @{ Mode='Targets'; Description='Close only matching users'; Current=($Config.Mode -eq 'Targets') },
      @{ Mode='ScanOnly'; Description='Report only'; Current=($Config.Mode -eq 'ScanOnly') }
    ) | ForEach-Object {
      [PSCustomObject]@{
        Mode        = $_.Mode
        Description = $_.Description
        Current     = if ($_.Current) {'*'} else {''}
      }
    } | Format-Table -AutoSize | Out-String -Width 4096 -Stream |
      Where-Object { $_.Trim() } | ForEach-Object { $_.TrimEnd() }

    Write-Box -Text "User Filters:" -NoBorder -Width 30 -Align Left `
        -TextColor Green -BlankLinesBefore 1 -BlankLinesAfter 1
    ($Config.IncludeUsers + $Config.ExcludeUsers | Select-Object -Unique) |
      ForEach-Object {
        [PSCustomObject]@{
          User      = $_
          InInclude = $Config.IncludeUsers -contains $_
          InExclude = $Config.ExcludeUsers -contains $_
        }
      } | Format-Table -AutoSize | Out-String -Width 4096 -Stream |
      Where-Object { $_.Trim() } | ForEach-Object { $_.TrimEnd() }
}

# ===================== Format-And-Log =====================
<#
.SYNOPSIS
    Displays and logs a formatted list of open or locked SMB file handles.

.DESCRIPTION
    Sorts and prints all detected open handles in a table format. Optionally logs the results
    to a file or centralized logging system using Write-Log.

.PARAMETER Results
    Array of objects representing open SMB handles.

.PARAMETER EnableLog
    Switch to determine whether log entries should be written.

.PARAMETER LogDir
    Path to the directory where logs should be written (if not using Write-Log).

.EXAMPLE
    Format-And-Log -Results $handles -EnableLog -LogDir "D:\Logs"
#>
function Format-And-Log {
    param(
        [pscustomobject[]] $Results,
        [bool] $EnableLog,
        [string] $LogDir
    )
    if (-not $Results.Count) {
        Write-Host "No SMB handles found." -ForegroundColor Yellow
        return
    }

    $output = $Results |
        Sort-Object FilePath |
        Format-Table FilePath, Client, Computer, SessionId, FileId -AutoSize |
        Out-String | ForEach-Object { $_.TrimEnd() }

    Write-Host "Open/Locked SMB Items (remaining):" -ForegroundColor Cyan
    Write-Host $output

    # if ($EnableLog) {
    #     if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    #     $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    #     $logPath   = Join-Path $LogDir "SMBLog_$timestamp.txt"
    #     "Log generated on: $(Get-Date)`n$output" |
    #         Out-File -FilePath $logPath -Encoding UTF8
    #     Write-Host "`nLog written to: $logPath" -ForegroundColor Yellow
    # }

    if ($EnableLog) {
        Write-Log -Message \"Log generated on: $(Get-Date)\" -Level INFO
        $output | ForEach-Object {
            Write-Log -Message $_ -Level INFO
        }
    }
}

# ===================== AutoCloseAllLocks =====================
<#
.SYNOPSIS
    Closes all detected SMB file handles unconditionally.

.DESCRIPTION
    Iterates over all results and attempts to close each SMB file handle using
    Close-SmbOpenFile. Logs each closure or failure.

.PARAMETER Results
    Array of handle objects to be closed.

.OUTPUTS
    [PSCustomObject[]] Handles that failed to close (should be none).

.EXAMPLE
    AutoCloseAllLocks -Results $handles
#>
function AutoCloseAllLocks {
    param([pscustomobject[]] $Results)
    if ($Results.Count -eq 0) {
        Write-Host "[AutoCloseAllLocks] No locks to close." -ForegroundColor Yellow
        return $Results
    }
    Write-Host "[AutoCloseAllLocks] Closing $($Results.Count) locks..." -ForegroundColor Cyan
    foreach ($h in $Results) {
        try {
            Close-SmbOpenFile -SessionId $h.SessionId -FileId $h.FileId -Force
            Write-Host "Closed lock on $($h.FilePath)" -ForegroundColor Green
            Write-Log -Message "Closed lock on $($h.FilePath) | FileId: $($h.FileId) | SessionId: $($h.SessionId) | User: $($h.Client) | Computer: $($h.Computer)" -Level INFO
        } catch {
            Write-Warning "Failed to close lock on $($h.FilePath): $_"
            Write-Log -Message "FAILED to close lock on $($h.FilePath) | FileId: $($h.FileId): $_" -Level ERROR
        }
    }
    return @()  # none remain
}

# ===================== AutoCloseTargetLocks =====================
<#
.SYNOPSIS
    Closes only SMB handles that match user filter criteria.

.DESCRIPTION
    Filters a list of handle results based on include/exclude user lists.
    Closes only matching handles and logs each closure or error.

.PARAMETER Results
    Array of SMB handle objects to evaluate.

.PARAMETER IncludeUsers
    Array of usernames to include. If empty, all users are included.

.PARAMETER ExcludeUsers
    Array of usernames to exclude from closure.

.OUTPUTS
    [PSCustomObject[]] Handles that were not closed.

.EXAMPLE
    AutoCloseTargetLocks -Results $handles -IncludeUsers @("mil00001") -ExcludeUsers @("admin")
#>
function AutoCloseTargetLocks {
    [CmdletBinding()]
    param(
        [pscustomobject[]] $Results      = @(),
        [string[]]         $IncludeUsers = @(),
        [string[]]         $ExcludeUsers = @()
    )

    # Filter the handles to close
    $toClose = $Results | Where-Object {
        $user = $_.Client
        (($IncludeUsers.Count -eq 0) -or ($IncludeUsers -contains $user)) -and
        (($ExcludeUsers.Count -eq 0) -or -not ($ExcludeUsers -contains $user))
    }

    if ($toClose.Count -eq 0) {
        Write-Box -Text "[AutoCloseTargetLocks] No matching SMB handles to close." `
                  -NoBorder -TextColor Yellow -BlankLinesBefore 0 -BlankLinesAfter 0
        return $Results
    }

    # Banner
    Write-Box -Text "[AutoCloseTargetLocks] Closing $($toClose.Count) SMB handle(s)..." `
              -NoBorder -TextColor Cyan -BlankLinesBefore 1 -BlankLinesAfter 1

    # Perform closes
    foreach ($h in $toClose) {
        try {
            Close-SmbOpenFile -SessionId $h.SessionId -FileId $h.FileId -Force
            Write-Log -Message "Closed target lock on $($h.FilePath) | FileId: $($h.FileId) | SessionId: $($h.SessionId) | User: $($h.Client) | Computer: $($h.Computer)" -Level INFO

        } catch {
            Write-Box -Text "[AutoCloseTargetLocks] Failed to close $($h.FilePath): $_" `
                      -NoBorder -TextColor Red -BlankLinesBefore 0 -BlankLinesAfter 0
            Write-Log -Message "FAILED to close target lock on $($h.FilePath): $_" -Level ERROR
        }
    }

    # Build and print table with proper alignment and coloring
    $header1   = 'Closed on'
    $header2   = 'User'
    $sep       = '  '  # two spaces between columns

    # Measure max lengths
    $allPaths  = $toClose | ForEach-Object { $_.FilePath }
    $allUsers  = $toClose | ForEach-Object { $_.Client }
    $maxDirLen = ($allPaths + $header1 | Measure-Object -Property Length -Maximum).Maximum
    $maxUsrLen = ($allUsers + $header2 | Measure-Object -Property Length -Maximum).Maximum

    # Header row in cyan
    Write-Host ($header1.PadRight($maxDirLen) + $sep + $header2.PadRight($maxUsrLen)) -ForegroundColor Cyan

    # Underline row in cyan
    Write-Host (('-' * $maxDirLen) + $sep + ('-' * $maxUsrLen)) -ForegroundColor Cyan

    # Data rows: directory in green, user in yellow
    foreach ($h in $toClose) {
        $dirPadded = $h.FilePath.PadRight($maxDirLen)
        $usrPadded = $h.Client.PadRight($maxUsrLen)
        Write-Host ($dirPadded + $sep) -ForegroundColor Green -NoNewline
        Write-Host $usrPadded          -ForegroundColor Yellow
    }

    # Return remaining
    return $Results | Where-Object { $toClose -notcontains $_ }
}

# ===================== Invoke-SmbFileProcess =====================
<#
.SYNOPSIS
    Orchestrates the full SMB file handle scan and closure process using a config file.

.DESCRIPTION
    Loads a JSON config file, optionally displays summary info, scans for locked handles,
    prints initial findings, closes handles based on mode and filters, and prints/logs final state.

.PARAMETER ConfigFile
    Full path to the JSON configuration file.

.EXAMPLE
    Invoke-SmbFileProcess -ConfigFile "$PSScriptRoot\Scan-Session.json"
#>
function Invoke-SmbFileProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ConfigFile
    )
    $config = Get-Config -Path $ConfigFile

    if ($config.ShowSummary) {
        Show-FileLockSummary -Config $config
    }
    if ($config.ShowTargetDirs) {
        Write-Box -Text "TARGETED DIRECTORIES" -Width 60 -Align Center `
            -BorderChar '#' -BorderColor Cyan -TextColor Yellow `
            -BlankLinesBefore 1 -BlankLinesAfter 1
        $config.DirectoriesToScan | ForEach-Object { Write-Host "  - $_" }
    }

    Write-Box -Text "INITIAL OPEN HANDLES" -Width 60 -Align Center `
        -BorderChar '#' -BorderColor Cyan -TextColor Yellow `
        -BlankLinesBefore 1 -BlankLinesAfter 1    
    $handles = @(Get-SmbOpenHandles -Dirs $config.DirectoriesToScan -Quiet:(!$config.ShowTargetDirs))
    if ($handles.Count) {
        $handles |
          Sort-Object FilePath |
          Format-Table FilePath, Client, Computer, SessionId, FileId -AutoSize |
          Out-String | ForEach-Object { $_.TrimEnd() } |
          Write-Host
    } else {        
        Write-Box -Text "No SMB handles detected." -Width 60 -Align Left `
            -NoBorder -TextColor Yellow `
            -BlankLinesBefore 1 
    }

    Write-Box -Text "ACTIONS" -Width 60 -Align Center `
        -BorderChar '#' -BorderColor Cyan -TextColor Yellow `
        -BlankLinesBefore 1 -BlankLinesAfter 1
    if ($config.CloseHandles) {
        switch ($config.Mode.ToLower()) {
            'all'     { $remaining = AutoCloseAllLocks    -Results $handles }
            'targets' { $remaining = AutoCloseTargetLocks -Results $handles `
                                      -IncludeUsers $config.IncludeUsers `
                                      -ExcludeUsers $config.ExcludeUsers }
            'scanonly'{ Write-Host "[ScanOnly] Report only." -ForegroundColor Yellow
                        $remaining = $handles }
            default   { Throw "Unknown Mode: $($config.Mode)" }
        }
    } else {
        Write-Host "[Handle Close] Disabled by CloseHandles flag." -ForegroundColor Yellow
        $remaining = $handles
    }

    Write-Box -Text "FINAL SCAN RESULTS" -Width 60 -Align Center `
        -BorderChar '#' -BorderColor Cyan -TextColor Yellow `
        -BlankLinesBefore 1 -BlankLinesAfter 1
    if ($remaining.Count) {
        Format-And-Log -Results $remaining `
                       -EnableLog $config.EnableLog `
                       -LogDir $config.LogDirectory
    } else {
        Write-Host "No SMB handles remaining." -ForegroundColor Yellow
        # if ($config.EnableLog) {
        #     Write-Box -Text "LOGGING" -Width 60 -Align Center `
        #         -BorderChar '#' -BorderColor Cyan -TextColor Yellow `
        #         -BlankLinesBefore 1 -BlankLinesAfter 1
        #     $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        #     $logPath   = Join-Path $config.LogDirectory "SMBLog_$timestamp.txt"
        #     "No SMB handles remaining ($(Get-Date))" |
        #         Out-File -FilePath $logPath -Encoding UTF8
        #     Write-Host "Log written to: $logPath" -ForegroundColor Yellow
        # }
        Write-Log -Message "No SMB handles remaining." -Level INFO
    }
}

# ======================= Export ========================

# Export public functions to expose them when the module is imported.
# Internal helper functions are intentionally kept private.
Export-ModuleMember -Function `
  Get-SmbOpenHandles, Show-FileLockSummary, Format-And-Log, `
  AutoCloseAllLocks, AutoCloseTargetLocks, Invoke-SmbFileProcess
