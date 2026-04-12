@{
    RootModule = 'LLMWorkflow.psm1'
    ModuleVersion = '0.3.0'
    GUID = '8e7e91da-f11c-4a09-8ba2-4af68cc2d5fc'
    Author = 'DocDamage'
    CompanyName = 'DocDamage'
    Copyright = '(c) DocDamage. All rights reserved.'
    Description = 'All-in-one workflow module for CodeMunch Pro, ContextLattice, and MemPalace.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Install-LLMWorkflow', 'Uninstall-LLMWorkflow', 'Update-LLMWorkflow', 'Get-LLMWorkflowVersion', 'Test-LLMWorkflowSetup', 'Invoke-LLMWorkflowUp', 'Test-ProviderKey', 'Get-ProviderProfile', 'Resolve-ProviderProfile', 'Get-ProviderPreferenceOrder', 'Get-LLMWorkflowPlugins', 'Register-LLMWorkflowPlugin', 'Unregister-LLMWorkflowPlugin', 'Invoke-LLMWorkflowPlugins', 'Get-LLMWorkflowPalaces', 'Test-LLMWorkflowPalace', 'Sync-LLMWorkflowPalace', 'Sync-LLMWorkflowAllPalaces', 'Get-LLMWorkflowPluginManifest', 'Save-LLMWorkflowPluginManifest', 'New-LLMWorkflowGamePreset', 'Get-LLMWorkflowGameTemplates', 'Export-LLMWorkflowAssetManifest', 'Show-LLMWorkflowDashboard', 'Invoke-LLMWorkflowHeal', 'Test-LLMWorkflowIssue', 'Repair-LLMWorkflowIssue', 'Get-LLMWorkflowRepairHistory', 'Clear-LLMWorkflowRepairHistory', 'Export-LLMWorkflowRepairHistory', 
        # Phase 1 Priority 1: Journaling + Checkpoints (RunId, Logging, Journal)
        'New-RunId', 'Get-CurrentRunId', 'Set-CurrentRunId', 'Clear-CurrentRunId', 'Test-RunIdFormat', 'Parse-RunId',
        'New-LogEntry', 'Write-StructuredLog', 'Get-LogPath', 'Read-StructuredLog', 'Set-LogDirectory',
        'New-RunManifest', 'Complete-RunManifest', 'New-JournalEntry', 'Get-JournalState', 'Export-JournalReport', 'Add-RunArtifact',
        # Phase 1 Priority 2: File Locking + Atomic Writes
        'Lock-File', 'Unlock-File', 'Test-FileLock', 'Get-LockInfo', 'Remove-StaleLock', 'Test-StaleLock', 'Release-AllLocks', 'Get-AllLocks',
        'Write-AtomicFile', 'Backup-AndWrite', 'Write-JsonAtomic', 'Read-JsonAtomic', 'Sync-File', 'Sync-Directory', 'Backup-File', 'Add-JsonLine',
        'Read-StateFile', 'Write-StateFile', 'Update-StateFile', 'Test-StateVersion', 'Backup-StateFile', 'Migrate-StateFile', 'Get-StateFiles', 'Initialize-StateFile',
        # Phase 1 Priority 3: Effective Configuration
        'Get-DefaultConfig', 'Get-ConfigSchema', 'Test-ConfigValue', 'Test-SecretKey', 'Protect-ConfigSecrets', 'Get-ValidExecutionModes', 'Test-ExecutionMode',
        'Get-ConfigPath', 'Find-ProjectRoot', 'Initialize-ProjectConfigDir', 'Initialize-CentralConfigDir', 'Get-ProjectConfig', 'Get-ProfileConfig', 'Get-EnvironmentConfig', 'Save-ProjectConfig', 'Save-CentralConfig',
        'Get-EffectiveConfig', 'Get-ConfigValue', 'Test-ConfigValidation', 'Export-ConfigExplanation', 'Get-ExecutionMode', 'Set-ExecutionMode', 'Clear-ConfigCache',
        'Get-LLMWorkflowEffectiveConfig', 'Invoke-LLMConfig', 'Register-LLMConfigAlias',
        # Phase 1 Priority 4: Policy + Execution Modes
        'Get-PolicyRules', 'Test-PolicyPermission', 'Assert-PolicyPermission', 'Test-RequiresConfirmation', 'Request-Confirmation', 'Register-PolicyAction', 'Get-PolicyExitCode',
        'Get-ExecutionModePolicy', 'Test-ExecutionModeCapability', 'Switch-ExecutionMode', 'Get-AllowedCommands', 'Get-CommandSafetyLevel', 'Get-ExecutionModeContext', 'Get-CurrentExecutionMode',
        'New-CommandContract', 'Test-CommandContract', 'Invoke-WithContract', 'New-ExecutionPlan', 'Add-PlanStep', 'Show-ExecutionPlan', 'Invoke-ExecutionPlan',
        # Phase 1 Priority 5: Workspace + Visibility Boundaries
        'Get-CurrentWorkspace', 'New-Workspace', 'Switch-Workspace', 'Get-WorkspacePacks', 'Test-WorkspaceContext', 'Get-WorkspaceList', 'Remove-Workspace',
        'Test-VisibilityRule', 'Get-PackVisibility', 'Test-ExportPermission', 'Protect-SecretData', 'Test-SecretInContent', 'Protect-LogEntry', 'Assert-NotExportable',
        'New-PackVisibilityConfig', 'Test-PackAccess', 'Get-RetrievalPriority', 'Test-CanAnswerFromPack', 'Get-PackAnswerLabel', 'Select-PacksForQuery')
    AliasesToExport = @('llmup', 'llmdown', 'llmcheck', 'llmver', 'llmupdate', 'llmplugins', 'llmpalaces', 'llmsync', 'llmdashboard', 'llmheal')
    CmdletsToExport = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('CodeMunch', 'ContextLattice', 'MemPalace', 'workflow')
            ProjectUri = 'https://github.com/DocDamage/CodeMunch-ContextLattice-MemPalace---All-in-one'
            LicenseUri = 'https://github.com/DocDamage/CodeMunch-ContextLattice-MemPalace---All-in-one/blob/main/LICENSE'
            ReleaseNotes = 'v0.3.0: Phase 1 core infrastructure - Journaling, File Locking, Effective Config, Policy, Workspace Boundaries. RPG Maker MZ pack foundation.'
        }
    }
}
