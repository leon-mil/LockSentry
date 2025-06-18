<#
.SYNOPSIS
    Core utility functions for LockSentry, including formatted console output and JSON config loading.

.DESCRIPTION
    This module provides common reusable functions used across LockSentry scripts. Includes:
    - Write-Box: For stylized console output with optional borders and padding.
    - Get-Config: For safely loading JSON config files.

.NOTES
    File Name    : Core.psm1
    Author       : Leon Mil
    Created On   : 2025-06-01
    Last Updated : 2025-06-10
    Version      : v1.0.0
    Tags         : Core, Utilities, Logging, Config
    Environment  : common

#>

# ===================== Write-Box =====================
<#
.SYNOPSIS
    Writes a styled and optionally bordered message box to the console.

.DESCRIPTION
    Outputs a message with configurable alignment, padding, width, text color, and border styling.
    Useful for formatting log output or console banners in scripts.

.PARAMETER Text
    The message to display inside the box.

.PARAMETER PaddingLeft
    Left-side padding inside the box.

.PARAMETER PaddingRight
    Right-side padding inside the box.

.PARAMETER PaddingTop
    Number of empty lines above the text inside the border.

.PARAMETER PaddingBottom
    Number of empty lines below the text inside the border.

.PARAMETER Width
    Total width of the box. Will auto-expand to fit text if smaller.

.PARAMETER Align
    Alignment of the message inside the box. Options: Left, Center, Right.

.PARAMETER TextColor
    Foreground color of the message text.

.PARAMETER BorderColor
    Foreground color of the box border.

.PARAMETER BorderChar
    Character to use for the box border.

.PARAMETER NoBorder
    Switch to disable the border entirely.

.PARAMETER BlankLinesBefore
    Number of blank lines printed before the box.

.PARAMETER BlankLinesAfter
    Number of blank lines printed after the box.

.EXAMPLE
    Write-Box -Text "Log cleanup complete." -PaddingTop 1 -Width 50 -Align Center -TextColor Green
    # Displays a centered green message with one line of padding above, inside a bordered box of width 50.

.EXAMPLE
    Write-Box -Text "ERROR: Config file not found." -TextColor Red -BorderColor DarkRed -Align Left
    # Displays a left-aligned red error message with a dark red border.

.EXAMPLE
    Write-Box -Text "Deployment Started" -PaddingTop 1 -PaddingBottom 1 -BorderChar "*" -Width 60 -TextColor Cyan
    # Displays a message with custom border character '*', extra vertical padding, and cyan text.

.EXAMPLE
    Write-Box -Text "Task Complete" -NoBorder -TextColor Yellow
    # Displays a yellow message without any border or padding.

.EXAMPLE
    Write-Box -Text "Archiving logs..." -PaddingLeft 5 -PaddingRight 5 -Width 40 -BlankLinesBefore 1 -BlankLinesAfter 1
    # Adds horizontal padding, and inserts a blank line before and after the box for visual separation in the console.

.EXAMPLE
    Write-Box -Text "WARNING: Disk space low" -TextColor Yellow -BorderColor DarkYellow -Align Right
    # Shows a right-aligned warning message with yellow styling to indicate caution.

.NOTES
    Helps produce readable and styled output in CLI-based PowerShell utilities.
#>
function Write-Box {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [int] $PaddingLeft    = 0,
        [int] $PaddingRight   = 0,
        [int] $PaddingTop     = 0,
        [int] $PaddingBottom  = 0,
        [int] $Width          = 0,
        [ValidateSet('Left','Center','Right')][string] $Align      = 'Center',
        [ConsoleColor] $TextColor    = 'White',
        [ConsoleColor] $BorderColor  = 'DarkCyan',
        [string] $BorderChar       = '=',
        [switch] $NoBorder,
        [int] $BlankLinesBefore = 0,
        [int] $BlankLinesAfter  = 0
    )
    if ($NoBorder) { $BorderChar = '' }
    for ($i = 0; $i -lt $BlankLinesBefore; $i++) { Write-Host '' }
    $minInner = $Text.Length
    $minTotal = $minInner + 2 + $PaddingLeft + $PaddingRight
    if ($Width -lt $minTotal) { $Width = $minTotal }
    if ([string]::IsNullOrEmpty($BorderChar)) {
        for ($i = 0; $i -lt $PaddingTop; $i++) { Write-Host '' }
        $line = (' ' * $PaddingLeft) + $Text + (' ' * $PaddingRight)
        Write-Host $line -ForegroundColor $TextColor
        for ($i = 0; $i -lt $PaddingBottom; $i++) { Write-Host '' }
        for ($i = 0; $i -lt $BlankLinesAfter; $i++) { Write-Host '' }
        return
    }
    $borderLine = [string]::new($BorderChar, $Width)
    $innerWidth = $Width - 2 - $PaddingLeft - $PaddingRight
    Write-Host $borderLine -ForegroundColor $BorderColor
    for ($i = 0; $i -lt $PaddingTop; $i++) {
        Write-Host -NoNewline $BorderChar -ForegroundColor $BorderColor
        Write-Host ([string]::new(' ', $Width - 2)) -ForegroundColor $TextColor -NoNewline
        Write-Host $BorderChar -ForegroundColor $BorderColor
    }
    switch ($Align) {
        'Left'   { $bodyText = $Text.PadRight($innerWidth) }
        'Right'  { $bodyText = $Text.PadLeft($innerWidth)  }
        'Center' {
            $left  = [Math]::Floor(($innerWidth - $Text.Length)/2)
            $right = $innerWidth - $Text.Length - $left
            $bodyText = (' ' * $left) + $Text + (' ' * $right)
        }
    }
    Write-Host -NoNewline $BorderChar -ForegroundColor $BorderColor
    Write-Host -NoNewline (' ' * $PaddingLeft) -ForegroundColor $TextColor
    Write-Host -NoNewline $bodyText -ForegroundColor $TextColor
    Write-Host -NoNewline (' ' * $PaddingRight) -ForegroundColor $TextColor
    Write-Host $BorderChar -ForegroundColor $BorderColor
    for ($i = 0; $i -lt $PaddingBottom; $i++) {
        Write-Host -NoNewline $BorderChar -ForegroundColor $BorderColor
        Write-Host ([string]::new(' ', $Width - 2)) -ForegroundColor $TextColor -NoNewline
        Write-Host $BorderChar -ForegroundColor $BorderColor
    }
    Write-Host $borderLine -ForegroundColor $BorderColor
    for ($i = 0; $i -lt $BlankLinesAfter; $i++) { Write-Host '' }
}

# ===================== Get-Config =====================
<#
.SYNOPSIS
    Loads and parses a JSON configuration file.

.DESCRIPTION
    Reads the contents of a JSON file from the specified path, verifies its existence,
    and returns the parsed object for use in scripts.

.PARAMETER Path
    Full path to the JSON configuration file.

.INPUTS
    [string] Path to JSON file.

.OUTPUTS
    [PSCustomObject] Parsed JSON configuration object.

.EXAMPLE
    $config = Get-Config -Path "$PSScriptRoot\settings.json"

.NOTES
    Throws a terminating error if the file is missing or unreadable.
#>
function Get-Config {
    param(
        [Parameter(Mandatory)][string] $Path
    )
    if (-not (Test-Path $Path)) {
        Throw "Config not found: $Path"
    }
    return Get-Content $Path -Raw | ConvertFrom-Json
}

# ======================= Export ========================

# Export public functions from this module so they are accessible when the module is imported.
# Only Write-Box and Get-Config are exposed for external use; all other functions remain internal.
Export-ModuleMember -Function Write-Box, Get-Config
