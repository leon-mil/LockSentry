@{
    RootModule        = 'SmbFileManager.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '11111111-1111-1111-1111-111111111111'
    Author            = 'Leon Mil'
    Description       = 'Manage SMB file locks: scan and close.'
    RequiredModules   = @('LockSentry.Core')

    # Export every public function defined in SmbFileManager.psm1:
    FunctionsToExport = @(
        'Get-SmbOpenHandles',
        'Format-And-Log',
        'Show-FileLockSummary',
        'AutoCloseAllLocks',
        'AutoCloseTargetLocks',
        'Invoke-SmbFileProcess'
    )
}
