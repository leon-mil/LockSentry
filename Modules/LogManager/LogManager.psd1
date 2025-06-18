@{
    RootModule        = 'LogManager.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '00000000-0000-0000-0000-000000000000'
    Author            = 'Leon Mil'
    Description       = 'Centralized logging utility for LockSentry modules.'
    FunctionsToExport = @('Initialize-Log', 'Write-Log')
}
