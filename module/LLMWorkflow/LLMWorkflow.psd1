@{
    RootModule = 'LLMWorkflow.psm1'
    ModuleVersion = '0.1.0'
    GUID = '8e7e91da-f11c-4a09-8ba2-4af68cc2d5fc'
    Author = 'DocDamage'
    CompanyName = 'DocDamage'
    Copyright = '(c) DocDamage. All rights reserved.'
    Description = 'All-in-one workflow module for CodeMunch Pro, ContextLattice, and MemPalace.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Install-LLMWorkflow', 'Uninstall-LLMWorkflow', 'Invoke-LLMWorkflowUp')
    AliasesToExport = @('llmup', 'llmdown')
    CmdletsToExport = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('CodeMunch', 'ContextLattice', 'MemPalace', 'workflow')
            ProjectUri = 'https://github.com/DocDamage/CodeMunch-ContextLattice-MemPalace---All-in-one'
        }
    }
}
