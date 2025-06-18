<#
.SYNOPSIS
    Manages SMB session discovery, filtering, and closure within LockSentry.

.DESCRIPTION
    Provides session-level tools for:
    - Summarizing configuration
    - Displaying open sessions and related handles
    - Closing all or filtered sessions based on user-defined criteria
    - Logging all key actions and session states

.NOTES
    File Name    : SmbSessionManager.psm1
    Author       : Leon Mil
    Created On   : 2025-06-01
    Last Updated : 2025-06-10
    Version      : v1.0.0
    Tags         : SMB, Sessions, Close, Scan, Logging
    Environment  : prod | dev
#>

# ===================== Dependencies =====================
# Import core and logging functionality required for reading config files,
# structured output (Write-Box), and logging (Write-Log).
# DisableNameChecking allows internal function names that may not match conventions.

Import-Module LockSentry.Core -Force -DisableNameChecking
Import-Module LockSentry.LogManager -Force -DisableNameChecking

# ===================== Show-SessionConfigSummary =====================
<#
.SYNOPSIS
    Displays session-related configuration summary to the console.

.DESCRIPTION
    Visually prints LockSentry session configuration including directories,
    logging flags, mode, and user filters for scan/close operations.

.PARAMETER Config
    Configuration object loaded from JSON file.

.EXAMPLE
    Show-SessionConfigSummary -Config $config
#>
function Show-SessionConfigSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Config
    )

    Write-Box -Text "Configuration Summary" -Width 60 -Align Center `
        -BorderChar '#' -BorderColor Cyan -TextColor Yellow `
        -BlankLinesBefore 1 -BlankLinesAfter 1

    Write-Box -Text "Directories to Scan:" -NoBorder -Width 30 -Align Left `
        -TextColor Green -BlankLinesAfter 1
  
    $Config.DirectoriesToScan | ForEach-Object { Write-Host "  - $_" }

    Write-Box -Text "Settings:" -NoBorder -Width 30 -Align Left -TextColor Green `
        -BlankLinesBefore 1 -BlankLinesAfter 1

    [PSCustomObject]@{ Name = 'Mode'; Value = $Config.Mode },
    [PSCustomObject]@{ Name = 'ShowSummary'; Value = $Config.ShowSummary },
    [PSCustomObject]@{ Name = 'EnableLog'; Value = $Config.EnableLog },
    [PSCustomObject]@{ Name = 'CloseSession'; Value = $Config.CloseSession } |
    Format-Table -AutoSize |
    Out-String -Width 4096 -Stream |
    Where-Object { $_.Trim() } |
    ForEach-Object { $_.TrimEnd() }

    Write-Box -Text "Available Modes:" -NoBorder -Width 30 -Align Left -TextColor Green `
        -BlankLinesBefore 1 -BlankLinesAfter 1
    @(
        @{ Mode = 'All'; Description = 'Close every session'; Current = ($Config.Mode -eq 'All') },
        @{ Mode = 'Targets'; Description = 'Close matching sessions'; Current = ($Config.Mode -eq 'Targets') },
        @{ Mode = 'ScanOnly'; Description = 'Report only'; Current = ($Config.Mode -eq 'ScanOnly') }
    ) | ForEach-Object {
        [PSCustomObject]@{
            Mode        = $_.Mode
            Description = $_.Description
            Current     = if ($_.Current) { '*' } else { '' }
        }
    } | Format-Table -AutoSize |
    Out-String -Width 4096 -Stream |
    Where-Object { $_.Trim() } |
    ForEach-Object { $_.TrimEnd() }

    Write-Box -Text "User Filters:" -NoBorder -Width 30 -Align Left -TextColor Green `
        -BlankLinesBefore 1 -BlankLinesAfter 1
  ($Config.IncludeUsers + $Config.ExcludeUsers | Select-Object -Unique) |
    ForEach-Object {
        [PSCustomObject]@{
            User      = $_
            InInclude = $Config.IncludeUsers -contains $_
            InExclude = $Config.ExcludeUsers -contains $_
        }
    } | Format-Table -AutoSize |
    Out-String -Width 4096 -Stream |
    Where-Object { $_.Trim() } |
    ForEach-Object { $_.TrimEnd() }
}

# ===================== Get-SmbOpenHandles =====================
<#
.SYNOPSIS
    Retrieves a list of open SMB file handles filtered by directory.

.DESCRIPTION
    Scans for open files using Get-SmbOpenFile and filters results
    to only those matching provided paths. Logs each found item.

.PARAMETER Dirs
    List of root directory paths to scan under.

.PARAMETER Quiet
    Suppresses output if specified.

.OUTPUTS
    [PSCustomObject[]] representing session, file, and path metadata.

.EXAMPLE
    Get-SmbOpenHandles -Dirs "D:\\DATA\\FILES"
#>
function Get-SmbOpenHandles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $Dirs,
        [switch]                      $Quiet
    )
    $res = @()
    foreach ($d in $Dirs) {
        # if (-not $Quiet) { Write-Host "Scanning SMB opens in: $d" }
        if (-not $Quiet) {
            Write-Host "Scanning SMB opens in: $d"
            Write-Log -Message "Scanning SMB opens in: $d" -Level INFO
        }
        $res += Get-SmbOpenFile |
        Where-Object Path -like "$d*" |
        ForEach-Object {
            Write-Log -Message "Locked file: $($_.Path), FileId: $($_.FileId), User: $($_.ClientUserName), Computer: $($_.ClientComputerName)" -Level INFO
            [PSCustomObject]@{
                SessionId = $_.SessionId
                FileId    = $_.FileId
                FilePath  = $_.Path
            }
        }        
    }
    return $res
}

# ===================== Show-Sessions =====================
<#
.SYNOPSIS
    Displays active SMB sessions in a formatted table.

.DESCRIPTION
    Prints session details such as SessionId, User, Client name, and open count.
    Returns nothing if no sessions exist.

.PARAMETER Sessions
    Array of [Microsoft.Windows.Smb.Share.SmbSession] objects.

.EXAMPLE
    Show-Sessions -Sessions (Get-SmbSession)
#>
function Show-Sessions {
    [CmdletBinding()]
    param([Microsoft.Windows.Smb.Share.SmbSession[]] $Sessions)

    if (-not $Sessions.Count) {
        Write-Host "No SMB sessions found." -ForegroundColor Yellow
        return
    }

    Write-Box -Text "CURRENT SMB SESSIONS" -Width 60 -Align Center `
        -BorderChar '#' -BorderColor Cyan -TextColor Yellow `
        -BlankLinesBefore 1 -BlankLinesAfter 1

    $Sessions |
    Format-Table @{
        Name = 'SessionId'; Expression = { $_.SessionId }; Width = 16
    }, @{
        Name = 'ClientUserName'; Expression = { $_.ClientUserName }; Width = 25
    }, @{
        Name = 'ClientComputerName'; Expression = { $_.ClientComputerName }; Width = 20
    }, @{
        Name = 'NumOpens'; Expression = { $_.NumOpens }; Width = 8
    } -AutoSize | Out-String | ForEach-Object { $_.TrimEnd() } | ForEach-Object { Write-Host $_ }
}

# ===================== Show-SmbSessionGroups =====================
<#
.SYNOPSIS
    Groups file handles by session and prints them.

.DESCRIPTION
    For each provided SessionId, retrieves the full SMB session,
    logs its metadata, and displays a grouped list of open files.

.PARAMETER SessionIds
    List of session IDs to display.

.PARAMETER Handles
    Array of file handle objects with SessionId properties.

.EXAMPLE
    Show-SmbSessionGroups -SessionIds $ids -Handles $handles
#>
function Show-SmbSessionGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]          $SessionIds,
        [Parameter(Mandatory)][pscustomobject[]]  $Handles
    )

    if (-not $SessionIds.Count) {
        Write-Box -Text 'No SMB sessions to display' -NoBorder -TextColor Yellow
        return
    }

    foreach ($sid in $SessionIds) {
        try {
            $sess = Get-SmbSession -SessionId $sid -ErrorAction Stop
        }
        catch {
            Write-Box -Text "Session $sid no longer exists, skipping" `
                -NoBorder -TextColor Green
            continue
        }

        Write-Box -Text "Session $sid | User: $($sess.ClientUserName) | Computer: $($sess.ClientComputerName)" `
            -Align Left -BorderChar '+' -BorderColor Cyan -TextColor Yellow `
            -Width 80 -PaddingLeft 2 -PaddingRight 2 -BlankLinesBefore 1

        Write-Log -Message "Session found: ID=$sid, User=$($sess.ClientUserName), Computer=$($sess.ClientComputerName)" -Level INFO

        # $Handles |
        #   Where-Object SessionId -eq $sid |
        #   Sort-Object FilePath |
        #   Format-Table @{
        #     Name       = 'FilePath'; Expression = { $_.FilePath }; Width = 50
        #   }, @{
        #     Name       = 'FileId';   Expression = { $_.FileId };   Width = 15
        #   } -AutoSize | Out-String | ForEach-Object { Write-Host $_.TrimEnd() }

        $sessionFiles = $Handles | Where-Object SessionId -eq $sid | Sort-Object FilePath

        # Log each file path
        foreach ($f in $sessionFiles) {
            Write-Log -Message "  LOCKED FILE: $($f.FilePath) | FileId=$($f.FileId)" -Level INFO
        }

        # Output to terminal
        $sessionFiles |
        Format-Table @{
            Name = 'FilePath'; Expression = { $_.FilePath }; Width = 50
        }, @{
            Name = 'FileId'; Expression = { $_.FileId }; Width = 15
        } -AutoSize | Out-String | ForEach-Object { Write-Host $_.TrimEnd() }

        Write-Host ''  # gap
    }
}

# ===================== Close-AllSessions =====================
<#
.SYNOPSIS
    Force-closes all sessions provided by ID.

.DESCRIPTION
    Attempts to close each session and logs the outcome.

.PARAMETER SessionIds
    Array of SessionId strings to close.

.EXAMPLE
    Close-AllSessions -SessionIds $ids
#>
function Close-AllSessions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $SessionIds
    )

    if (-not $SessionIds.Count) {
        Write-Host "[Close-AllSessions] No sessions to close." -ForegroundColor Yellow
        return
    }

    Write-Box -Text "ALL MODE: Closing All Sessions" -Width 60 -Align Center `
        -BorderChar '#' -BorderColor Cyan -TextColor Yellow `
        -BlankLinesBefore 1 -BlankLinesAfter 1

    foreach ($sid in $SessionIds) {
        try {
            Close-SmbSession -SessionId $sid -Force -ErrorAction Stop
            Write-Host "Session $sid closed." -ForegroundColor Green
            Write-Log -Message "Closed session $sid" -Level INFO
        }
        catch {
            # Wrap both variables in subexpressions so the colon isn’t mis-parsed
            Write-Warning "Could not close session $($sid): $($_)"
            Write-Log -Message "FAILED to close session $(sid): $_" -Level ERROR
        }
    }
}

# ===================== Close-TargetSessions =====================
<#
.SYNOPSIS
    Closes only those sessions matching specified user filters.

.DESCRIPTION
    Evaluates each session against include and exclude lists.
    Only sessions meeting criteria will be closed and logged.

.PARAMETER SessionIds
    List of candidate session IDs to evaluate.

.PARAMETER IncludeUsers
    Array of usernames to include (optional).

.PARAMETER ExcludeUsers
    Array of usernames to exclude (optional).

.EXAMPLE
    Close-TargetSessions -SessionIds $ids -IncludeUsers @('user1') -ExcludeUsers @('svcAccount')
#>
function Close-TargetSessions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $SessionIds,
        [string[]] $IncludeUsers = @(),
        [string[]] $ExcludeUsers = @()
    )

    $includes = $IncludeUsers | ForEach-Object { $_.Trim().ToLowerInvariant() }
    $excludes = $ExcludeUsers | ForEach-Object { $_.Trim().ToLowerInvariant() }

    $sessions = Get-SmbSession | Where-Object { $SessionIds -contains $_.SessionId }
    if (-not $sessions) {
        Write-Host "[Targets] No sessions to evaluate." -ForegroundColor Yellow
        return
    }

    # $toClose = @()
    # foreach ($s in $sessions) {
    #     $user     = $s.ClientUserName.Split('\')[-1].Trim().ToLowerInvariant()
    #     $keep     = (($includes.Count -eq 0) -or ($includes -contains $user)) -and
    #                 (($excludes.Count -eq 0) -or -not ($excludes -contains $user))
    #     if ($keep) { $toClose += $s }
    #     Write-Log -Message "Evaluating session $($s.SessionId) for user $(user): Included=$keep" -Level DEBUG
    # }

    $toClose = @()
    foreach ($s in $sessions) {
        $user = $s.ClientUserName.Split('\')[-1].Trim().ToLowerInvariant()
        $included = ($includes.Count -eq 0) -or ($includes -contains $user)
        $excluded = ($excludes.Count -ne 0) -and ($excludes -contains $user)
        $shouldClose = $included -and -not $excluded

        Write-Log -Message "Evaluated session $($s.SessionId): User=$user | Included=$included | Excluded=$excluded | ShouldClose=$shouldClose" -Level DEBUG

        if ($shouldClose) {
            $toClose += $s
        }
    }

    if (-not $toClose) {
        $excludedMatched = $sessions |
        ForEach-Object { 
            $u = $_.ClientUserName.Split('\')[-1].ToLowerInvariant()
            if ($excludes -contains $u) { $u }
        } | Select-Object -Unique
        $excludedList = if ($excludedMatched.Count) { $excludedMatched -join ', ' } else { 'none' }
        Write-Host "[Targets] No matching sessions to close; excluded sessions belong to: $excludedList" -ForegroundColor Yellow
        Write-Log -Message "[Targets] No sessions matched filter criteria. Excluded users: $excludedList" -Level WARN
        return
    }

    Write-Box -Text "TARGETS MODE: Closing Sessions" -Width 60 -Align Center `
        -BorderChar '#' -BorderColor Cyan -TextColor Yellow `
        -BlankLinesBefore 1 -BlankLinesAfter 1

    foreach ($sess in $toClose) {
        try {
            Close-SmbSession -SessionId $sess.SessionId -Force -ErrorAction Stop
            $u = $sess.ClientUserName.Split('\')[-1]
            Write-Host "Closed session $($sess.SessionId) for user $u on $($sess.ClientComputerName)." -ForegroundColor Green
            Write-Log -Message "Closed session $($sess.SessionId) for user $u on $($sess.ClientComputerName)" -Level INFO
        }
        catch {
            Write-Warning "Failed to close session $($sess.SessionId): $_"
            Write-Log -Message "FAILED to close session $($sess.SessionId): $_" -Level ERROR
        }
    }

    $ids = $toClose | Select-Object -ExpandProperty SessionId
    Write-Host "Closed $($ids.Count) session(s): $($ids -join ', ')" -ForegroundColor Cyan
    Write-Log -Message "Closed $($ids.Count) session(s): $($ids -join ', ')" -Level INFO
}

# ===================== Invoke-SmbSessionProcess =====================
<#
.SYNOPSIS
    Orchestrates SMB session analysis and cleanup using a JSON config file.

.DESCRIPTION
    Loads config file, shows summaries and directories, scans for session-based
    file locks, displays grouped handle info, and applies close logic as defined.

.PARAMETER ConfigFile
    Path to JSON configuration file for session scanning.

.EXAMPLE
    Invoke-SmbSessionProcess -ConfigFile "$PSScriptRoot\Scan-Session.json"
#>
function Invoke-SmbSessionProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ConfigFile
    )

    # Load config
    $config = Get-Config -Path $ConfigFile
    $config.Mode = $config.Mode.Trim()

    # Show config file if requested
    if ($config.ShowConfigFile) {
        Write-Box -Text "CONFIG FILE" -Width 60 -Align Center `
            -BorderChar '#' -BorderColor Cyan -TextColor Yellow `
            -BlankLinesBefore 1 -BlankLinesAfter 1
        Write-Host "Using config file: $ConfigFile" -ForegroundColor Yellow
    }

    # Show summary if requested
    if ($config.ShowSummary) {
        Show-SessionConfigSummary -Config $config
    }

    # Show targeted directories (no scanning yet)
    if ($config.ShowTargetDirs) {
        Write-Box -Text "TARGETED DIRECTORIES" -Width 60 -Align Center `
            -BorderChar '#' -BorderColor Cyan -TextColor Yellow `
            -BlankLinesBefore 1 -BlankLinesAfter 1
        $config.DirectoriesToScan | ForEach-Object { Write-Host "  - $_" }
    }

    # ACTIONS header
    Write-Box -Text "ACTIONS" -Width 60 -Align Center `
        -BorderChar '#' -BorderColor Cyan -TextColor Yellow `
        -BlankLinesBefore 1 -BlankLinesAfter 1

    # Now perform the scan (prints “Scanning SMB opens in: …”)
    $handles = @( Get-SmbOpenHandles -Dirs $config.DirectoriesToScan )
    $sessionIds = $handles | Select-Object -ExpandProperty SessionId -Unique

    # Show or drop into session groups
    if ($sessionIds.Count) {
        Show-SmbSessionGroups -SessionIds $sessionIds -Handles $handles
    }
    else {
        Write-Box -Text "[Targets] No sessions to display." `
            -NoBorder -TextColor Yellow -BlankLinesBefore 1 -BlankLinesAfter 0
    }

    # Close sessions if requested
    if ($config.CloseSession) {
        switch ($config.Mode.ToLower()) {
            'all' {
                if ($sessionIds.Count) { Close-AllSessions    -SessionIds $sessionIds }
                else { 
                    Write-Box -Text "[All] No sessions to close." `
                        -NoBorder -TextColor Yellow -BlankLinesBefore 1 -BlankLinesAfter 0 
                }
            }
            'targets' {
                if ($sessionIds.Count) {
                    Close-TargetSessions -SessionIds   $sessionIds `
                        -IncludeUsers $config.IncludeUsers `
                        -ExcludeUsers $config.ExcludeUsers
                }
                else {
                    Write-Box -Text "[Targets] No sessions to close." `
                        -NoBorder -TextColor Yellow -BlankLinesBefore 0 -BlankLinesAfter 0
                }
            }
            'scanonly' {
                Write-Box -Text "[ScanOnly] No sessions closed (report only)." `
                    -NoBorder -TextColor Yellow -BlankLinesBefore 1 -BlankLinesAfter 1
            }
            default {
                Throw "Unknown Mode: $($config.Mode)"
            }
        }
    }
    else {
        Write-Box -Text "[Session Close] Disabled by CloseSession flag." `
            -NoBorder -TextColor Yellow -BlankLinesBefore 1 -BlankLinesAfter 1
    }

    # LOGGING
    if ($config.EnableLog) {
        Write-Box -Text "LOGGING" -Width 60 -Align Center `
            -BorderChar '#' -BorderColor Cyan -TextColor Yellow `
            -BlankLinesBefore 1 -BlankLinesAfter 1

        # Write-SessionLog -LogDir $config.LogDirectory
        # Write-Log -Message "No open sessions remaining ($([datetime]::Now))" -Level INFO        

        if ($sessionIds.Count -eq 0) {
            Write-Log -Message "No open sessions remaining ($([datetime]::Now))" -Level INFO
        }
        else {            
            Write-Log -Message "$($SessionIds.Count) active SMB session(s) found and analyzed." -Level INFO
        }
    }
}

# ======================= Export ========================
# Export public functions used in LockSentry orchestration scripts.
# Internal functions remain private.
Export-ModuleMember -Function `
    Show-SessionConfigSummary, Get-SmbOpenHandles, Show-Sessions, Show-SmbSessionGroups, `
    Close-AllSessions, Close-TargetSessions, Invoke-SmbSessionProcess    
