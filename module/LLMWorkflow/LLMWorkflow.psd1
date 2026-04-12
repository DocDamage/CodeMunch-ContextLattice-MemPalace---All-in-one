@{
    RootModule = 'LLMWorkflow.psm1'
    ModuleVersion = '0.2.0'
    GUID = '8e7e91da-f11c-4a09-8ba2-4af68cc2d5fc'
    Author = 'DocDamage'
    CompanyName = 'DocDamage'
    Copyright = '(c) DocDamage. All rights reserved.'
    Description = 'All-in-one workflow module for CodeMunch Pro, ContextLattice, and MemPalace.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Install-LLMWorkflow', 'Uninstall-LLMWorkflow', 'Update-LLMWorkflow', 'Get-LLMWorkflowVersion', 'Test-LLMWorkflowSetup', 'Invoke-LLMWorkflowUp', 'Test-ProviderKey', 'Get-ProviderProfile', 'Resolve-ProviderProfile', 'Get-ProviderPreferenceOrder', 'Get-LLMWorkflowPlugins', 'Register-LLMWorkflowPlugin', 'Unregister-LLMWorkflowPlugin', 'Invoke-LLMWorkflowPlugins', 'Get-LLMWorkflowPalaces', 'Test-LLMWorkflowPalace', 'Sync-LLMWorkflowPalace', 'Sync-LLMWorkflowAllPalaces', 'Get-LLMWorkflowPluginManifest', 'Save-LLMWorkflowPluginManifest', 'New-LLMWorkflowGamePreset', 'Get-LLMWorkflowGameTemplates', 'Export-LLMWorkflowAssetManifest', 'Show-LLMWorkflowDashboard', 'Invoke-LLMWorkflowHeal', 'Test-LLMWorkflowIssue', 'Repair-LLMWorkflowIssue', 'Get-LLMWorkflowRepairHistory', 'Clear-LLMWorkflowRepairHistory', 'Export-LLMWorkflowRepairHistory')
    AliasesToExport = @('llmup', 'llmdown', 'llmcheck', 'llmver', 'llmupdate', 'llmplugins', 'llmpalaces', 'llmsync', 'llmdashboard', 'llmheal')
    CmdletsToExport = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('CodeMunch', 'ContextLattice', 'MemPalace', 'workflow')
            ProjectUri = 'https://github.com/DocDamage/CodeMunch-ContextLattice-MemPalace---All-in-one'
            LicenseUri = 'https://github.com/DocDamage/CodeMunch-ContextLattice-MemPalace---All-in-one/blob/main/LICENSE'
            ReleaseNotes = 'v0.2.0: update/version/setup commands, drift guard, release+security automation, uninstall hardening.'
        }
    }
}
