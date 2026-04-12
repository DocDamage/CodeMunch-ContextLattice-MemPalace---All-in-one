# LLM Workflow Plugin Architecture Tests
# Requires Pester module: Install-Module Pester -Scope CurrentUser -Force

# Setup (Pester 3 compatible)
$moduleRoot = Join-Path $PSScriptRoot ".."
$moduleDir = Join-Path $moduleRoot "module"
$llmWorkflowDir = Join-Path $moduleDir "LLMWorkflow"
$modulePath = Join-Path $llmWorkflowDir "LLMWorkflow.psm1"
Import-Module $modulePath -Force

$script:TestDir = Join-Path $env:TEMP ("llmworkflow-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $script:TestDir ".llm-workflow") -Force | Out-Null

# Helper function to reset manifest
function Reset-TestManifest {
    $emptyManifest = @{
        version = "1.0"
        plugins = @()
    }
    Save-LLMWorkflowPluginManifest -Manifest $emptyManifest -ProjectRoot $script:TestDir
}

Describe "Plugin Manifest Tests" {
    It "Should create empty manifest when none exists" {
        Reset-TestManifest
        $manifest = Get-LLMWorkflowPluginManifest -ProjectRoot $script:TestDir
        $manifest.version | Should Be "1.0"
        $manifest.plugins.Count | Should Be 0
    }
    
    It "Should save and load manifest correctly" {
        Reset-TestManifest
        $testManifest = @{
            version = "1.0"
            plugins = @(@{
                name = "test-plugin"
                description = "Test plugin"
                runOn = @("bootstrap")
            })
        }
        Save-LLMWorkflowPluginManifest -Manifest $testManifest -ProjectRoot $script:TestDir
        
        $loaded = Get-LLMWorkflowPluginManifest -ProjectRoot $script:TestDir
        $loaded.version | Should Be "1.0"
        $loaded.plugins.Count | Should Be 1
        $loaded.plugins[0].name | Should Be "test-plugin"
    }
}

Describe "Plugin Registration Tests" {
    It "Should register plugin inline" {
        Reset-TestManifest
        Register-LLMWorkflowPlugin -Name "inline-test" -Description "Inline test" `
            -BootstrapScript "tools/test/bootstrap.ps1" `
            -RunOn @("bootstrap") `
            -ProjectRoot $script:TestDir
        
        $plugins = Get-LLMWorkflowPlugins -ProjectRoot $script:TestDir
        $plugins.Count | Should Be 1
        $plugins[0].Name | Should Be "inline-test"
        $plugins[0].Description | Should Be "Inline test"
    }
    
    It "Should update existing plugin with same name" {
        Reset-TestManifest
        Register-LLMWorkflowPlugin -Name "duplicate-test" -Description "First" -RunOn @("bootstrap") -ProjectRoot $script:TestDir
        Register-LLMWorkflowPlugin -Name "duplicate-test" -Description "Second" -RunOn @("check") -ProjectRoot $script:TestDir
        
        $plugins = Get-LLMWorkflowPlugins -ProjectRoot $script:TestDir
        $plugins.Count | Should Be 1
        $plugins[0].Description | Should Be "Second"
    }
    
    It "Should unregister plugin" {
        Reset-TestManifest
        Register-LLMWorkflowPlugin -Name "remove-test" -Description "To be removed" -RunOn @("bootstrap") -ProjectRoot $script:TestDir
        Unregister-LLMWorkflowPlugin -Name "remove-test" -ProjectRoot $script:TestDir
        
        $plugins = Get-LLMWorkflowPlugins -ProjectRoot $script:TestDir
        $plugins.Count | Should Be 0
    }
    
    It "Should filter plugins by trigger" {
        Reset-TestManifest
        Register-LLMWorkflowPlugin -Name "bootstrap-only" -Description "Bootstrap" -RunOn @("bootstrap") -ProjectRoot $script:TestDir
        Register-LLMWorkflowPlugin -Name "check-only" -Description "Check" -RunOn @("check") -ProjectRoot $script:TestDir
        Register-LLMWorkflowPlugin -Name "both" -Description "Both" -RunOn @("bootstrap", "check") -ProjectRoot $script:TestDir
        
        $bootstrapPlugins = Get-LLMWorkflowPlugins -ProjectRoot $script:TestDir -Trigger bootstrap
        $checkPlugins = Get-LLMWorkflowPlugins -ProjectRoot $script:TestDir -Trigger check
        $allPlugins = Get-LLMWorkflowPlugins -ProjectRoot $script:TestDir
        
        $bootstrapPlugins.Count | Should Be 2
        $checkPlugins.Count | Should Be 2
        $allPlugins.Count | Should Be 3
    }
}

Describe "Plugin Validation Tests" {
    # Create fake plugin scripts
    $toolsDir = Join-Path (Join-Path $script:TestDir "tools") "validated-plugin"
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    "# Dummy bootstrap script" | Set-Content -Path (Join-Path $toolsDir "bootstrap.ps1")
    "# Dummy check script" | Set-Content -Path (Join-Path $toolsDir "check.ps1")
    
    It "Should mark plugin as invalid when script is missing" {
        Reset-TestManifest
        Register-LLMWorkflowPlugin -Name "invalid-plugin" -Description "Invalid" `
            -BootstrapScript "tools/missing/bootstrap.ps1" `
            -RunOn @("bootstrap") `
            -ProjectRoot $script:TestDir
        
        $plugins = Get-LLMWorkflowPlugins -ProjectRoot $script:TestDir
        $plugins[0].Valid | Should Be $false
    }
    
    It "Should mark plugin as valid when scripts exist" {
        Reset-TestManifest
        Register-LLMWorkflowPlugin -Name "valid-plugin" -Description "Valid" `
            -BootstrapScript "tools/validated-plugin/bootstrap.ps1" `
            -CheckScript "tools/validated-plugin/check.ps1" `
            -RunOn @("bootstrap", "check") `
            -ProjectRoot $script:TestDir
        
        $plugins = Get-LLMWorkflowPlugins -ProjectRoot $script:TestDir
        $plugins[0].Valid | Should Be $true
    }
}

Describe "Plugin Manifest File Tests" {
    It "Should return correct manifest path" {
        Reset-TestManifest
        $expectedPath = Join-Path (Join-Path $script:TestDir ".llm-workflow") "plugins.json"
        # We can verify the file exists after save
        $testManifest = @{
            version = "1.0"
            plugins = @()
        }
        Save-LLMWorkflowPluginManifest -Manifest $testManifest -ProjectRoot $script:TestDir
        Test-Path -LiteralPath $expectedPath | Should Be $true
    }
}

# Cleanup (Pester 3 compatible)
if (Test-Path -LiteralPath $script:TestDir) {
    Remove-Item -LiteralPath $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Plugin Architecture tests complete!"
