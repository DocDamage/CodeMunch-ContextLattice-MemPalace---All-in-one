#requires -Version 5.1

$script:ExtractionRoot = Join-Path (Join-Path $PSScriptRoot "..") "module\LLMWorkflow\extraction"
$script:WrapperModulePath = Join-Path $env:TEMP ("ExtractionWrapper-" + [Guid]::NewGuid().ToString("N") + ".psm1")

@"
. '$script:ExtractionRoot\UnrealDescriptorParser.ps1'
. '$script:ExtractionRoot\ExtractionPipeline.ps1'
"@ | Set-Content -LiteralPath $script:WrapperModulePath -Encoding UTF8

Import-Module $script:WrapperModulePath -Force

Describe "Unreal Descriptor Extraction" {
    It "parses Unreal plugin descriptors" {
        $pluginContent = @'
{
  "FileVersion": 3,
  "Version": 12,
  "VersionName": "1.2.0",
  "FriendlyName": "Example Plugin",
  "Description": "Gameplay systems plugin",
  "Category": "Gameplay",
  "CreatedBy": "LLM Workflow",
  "CreatedByURL": "https://example.com",
  "DocsURL": "https://example.com/docs",
  "MarketplaceURL": "https://fab.com/example-plugin",
  "CanContainContent": true,
  "IsBetaVersion": false,
  "Installed": true,
  "Modules": [
    {
      "Name": "ExampleRuntime",
      "Type": "Runtime",
      "LoadingPhase": "Default",
      "AdditionalDependencies": ["Engine"]
    },
    {
      "Name": "ExampleEditor",
      "Type": "Editor",
      "LoadingPhase": "PostEngineInit"
    }
  ],
  "Plugins": [
    {
      "Name": "GameplayAbilities",
      "Enabled": true,
      "Optional": false,
      "SupportedTargetPlatforms": ["Win64", "Linux"]
    }
  ],
  "SupportedTargetPlatforms": ["Win64", "Linux"]
}
'@

        $result = Invoke-UnrealDescriptorParse -Content $pluginContent -DescriptorType plugin

        $result.descriptorType | Should -Be "plugin"
        $result.friendlyName | Should -Be "Example Plugin"
        $result.modules.Count | Should -Be 2
        $result.modules[0].name | Should -Be "ExampleRuntime"
        $result.plugins.Count | Should -Be 1
        $result.compatibility.hasEditorModule | Should -Be $true
        $result.compatibility.likelyEngineMajor | Should -Be "Unknown"
    }

    It "parses Unreal project descriptors and routes through the extraction pipeline" {
        $projectPath = Join-Path $TestDrive "SampleGame.uproject"
        @'
{
  "FileVersion": 3,
  "EngineAssociation": "5.4",
  "Category": "Games",
  "Description": "Sample project",
  "Modules": [
    {
      "Name": "SampleGame",
      "Type": "Runtime",
      "LoadingPhase": "Default"
    }
  ],
  "Plugins": [
    {
      "Name": "CommonUI",
      "Enabled": true,
      "Optional": true,
      "MarketplaceURL": "https://fab.com/commonui"
    }
  ],
  "TargetPlatforms": ["Win64", "PS5"]
}
'@ | Set-Content -LiteralPath $projectPath -Encoding UTF8

        Test-ExtractionSupported -FilePath $projectPath | Should -Be $true
        (Get-SupportedExtractionTypes -AsHashtable).ContainsKey('.uproject') | Should -Be $true

        $pipelineResult = Invoke-StructuredExtraction -FilePath $projectPath -OutputFormat hashtable

        $pipelineResult.success | Should -Be $true
        $pipelineResult.fileType | Should -Be "unreal-project"
        $pipelineResult.packType | Should -Be "unreal-engine"
        $pipelineResult.data.descriptorType | Should -Be "project"
        $pipelineResult.data.engineAssociation | Should -Be "5.4"
        $pipelineResult.data.plugins[0].name | Should -Be "CommonUI"
        $pipelineResult.data.compatibility.likelyEngineMajor | Should -Be "5.x"
    }

    It "returns schema definitions for Unreal extraction types" {
        $pluginSchema = Get-ExtractionSchema -Type "unreal-plugin"
        $projectSchema = Get-ExtractionSchema -Type "unreal-project"

        $pluginSchema | Should -Not -BeNullOrEmpty
        $projectSchema | Should -Not -BeNullOrEmpty
        ($pluginSchema.requiredProperties -contains "modules") | Should -Be $true
        ($projectSchema.requiredProperties -contains "plugins") | Should -Be $true
    }
}

if (Test-Path -LiteralPath $script:WrapperModulePath) {
    Remove-Item -LiteralPath $script:WrapperModulePath -Force -ErrorAction SilentlyContinue
}
