@{
    RootModule        = 'SmbSessionManager.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '22222222-2222-2222-2222-222222222222'
    Author            = 'Leon Mil'
    Description       = 'Enumerate and close SMB sessions according to JSON config.'
    RequiredModules   = @('LockSentry.Core')
    FunctionsToExport = @(
      'Show-SessionConfigSummary',
      'Get-SmbOpenHandles',
      'Show-Sessions',
      'Show-SmbSessionGroups',
      'Close-AllSessions',
      'Close-TargetSessions',
      'Invoke-SmbSessionProcess',
      'Write-SessionLog'
    )
}
