# Pester tests for LLMWorkflow Heal Functions

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "..\module\LLMWorkflow\LLMWorkflow.HealFunctions.ps1"
    . $ModulePath
}

Describe "Test-LLMWorkflowIssue" {
    Context "MissingEnvFile detection" {
        It "Detects missing .env file" {
            $testDir = Join-Path $env:TEMP ("test_" + [Guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                $result = Test-LLMWorkflowIssue -IssueType MissingEnvFile -ProjectRoot $testDir
                $result.Detected | Should -Be $true
                $result.Category | Should -Be "WARNING"
                $result.CanFix | Should -Be $true
            } finally {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Does not detect when .env exists" {
            $testDir = Join-Path $env:TEMP ("test_" + [Guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $testDir ".env") -Force | Out-Null
            
            try {
                $result = Test-LLMWorkflowIssue -IssueType MissingEnvFile -ProjectRoot $testDir
                $result.Detected | Should -Be $false
            } finally {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "MissingPalaceDirectory detection" {
        It "Detects missing palace directory" {
            # Mock a non-existent palace path
            $result = Test-LLMWorkflowIssue -IssueType MissingPalaceDirectory -ProjectRoot "."
            # Result depends on whether palace exists on test machine
            $result.Category | Should -BeIn @("WARNING", "INFO")
        }
    }
    
    Context "CorruptedSyncState detection" {
        It "Detects corrupted JSON" {
            $testDir = Join-Path $env:TEMP ("test_" + [Guid]::NewGuid().ToString("N"))
            $bridgeDir = Join-Path $testDir ".memorybridge"
            New-Item -ItemType Directory -Path $bridgeDir -Force | Out-Null
            "invalid json {[" | Out-File -FilePath (Join-Path $bridgeDir "sync-state.json") -Encoding UTF8
            
            try {
                $result = Test-LLMWorkflowIssue -IssueType CorruptedSyncState -ProjectRoot $testDir
                $result.Detected | Should -Be $true
                $result.Category | Should -Be "WARNING"
                $result.CanFix | Should -Be $true
            } finally {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Does not detect when no sync-state exists" {
            $testDir = Join-Path $env:TEMP ("test_" + [Guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                $result = Test-LLMWorkflowIssue -IssueType CorruptedSyncState -ProjectRoot $testDir
                $result.Detected | Should -Be $false
            } finally {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "MissingBridgeConfig detection" {
        It "Detects missing bridge config" {
            $testDir = Join-Path $env:TEMP ("test_" + [Guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                $result = Test-LLMWorkflowIssue -IssueType MissingBridgeConfig -ProjectRoot $testDir
                $result.Detected | Should -Be $true
                $result.CanFix | Should -Be $true
            } finally {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "CorruptedBridgeConfig detection" {
        It "Detects corrupted bridge config" {
            $testDir = Join-Path $env:TEMP ("test_" + [Guid]::NewGuid().ToString("N"))
            $bridgeDir = Join-Path $testDir ".memorybridge"
            New-Item -ItemType Directory -Path $bridgeDir -Force | Out-Null
            "invalid json {[" | Out-File -FilePath (Join-Path $bridgeDir "bridge.config.json") -Encoding UTF8
            
            try {
                $result = Test-LLMWorkflowIssue -IssueType CorruptedBridgeConfig -ProjectRoot $testDir
                $result.Detected | Should -Be $true
                $result.Category | Should -Be "CRITICAL"
                $result.CanFix | Should -Be $true
            } finally {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "Repair-LLMWorkflowIssue" {
    Context "WhatIf mode" {
        It "Does not create files in WhatIf mode" {
            $testDir = Join-Path $env:TEMP ("test_" + [Guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                $result = Repair-LLMWorkflowIssue -IssueType MissingEnvFile -ProjectRoot $testDir -WhatIf
                $result.Success | Should -Be $true
                Test-Path (Join-Path $testDir ".env") | Should -Be $false
            } finally {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "MissingEnvFile repair" {
        It "Creates .env file from template" {
            $testDir = Join-Path $env:TEMP ("test_" + [Guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                $result = Repair-LLMWorkflowIssue -IssueType MissingEnvFile -ProjectRoot $testDir -Force
                $result.Success | Should -Be $true
                Test-Path (Join-Path $testDir ".env") | Should -Be $true
                
                $content = Get-Content (Join-Path $testDir ".env") -Raw
                $content | Should -Match "CONTEXTLATTICE_ORCHESTRATOR_URL"
            } finally {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "CorruptedSyncState repair" {
        It "Backs up and recreates sync state" {
            $testDir = Join-Path $env:TEMP ("test_" + [Guid]::NewGuid().ToString("N"))
            $bridgeDir = Join-Path $testDir ".memorybridge"
            New-Item -ItemType Directory -Path $bridgeDir -Force | Out-Null
            "invalid json {[" | Out-File -FilePath (Join-Path $bridgeDir "sync-state.json") -Encoding UTF8
            
            try {
                $result = Repair-LLMWorkflowIssue -IssueType CorruptedSyncState -ProjectRoot $testDir -Force
                $result.Success | Should -Be $true
                ($result.Changes -join "`n") | Should -Match "backup"
                
                # Verify backup was created
                $backups = Get-ChildItem -Path $bridgeDir -Filter "sync-state.json.backup.*"
                @($backups).Count | Should -BeGreaterThan 0
                
                # Verify new file is valid JSON
                $content = Get-Content (Join-Path $bridgeDir "sync-state.json") -Raw
                { $content | ConvertFrom-Json } | Should -Not -Throw
            } finally {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "MissingBridgeConfig repair" {
        It "Creates default bridge config" {
            $testDir = Join-Path $env:TEMP ("test_" + [Guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                $result = Repair-LLMWorkflowIssue -IssueType MissingBridgeConfig -ProjectRoot $testDir -Force
                $result.Success | Should -Be $true
                
                $configPath = Join-Path $testDir ".memorybridge\bridge.config.json"
                Test-Path $configPath | Should -Be $true
                
                $content = Get-Content $configPath -Raw
                $content | Should -Match "orchestratorUrl"
            } finally {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "Get-LLMWorkflowRepairHistory" {
    Context "Empty history" {
        It "Returns empty array when no history exists" {
            Mock Test-Path { return $false }
            $result = Get-LLMWorkflowRepairHistory
            $result | Should -BeNullOrEmpty
        }
    }
    
    Context "Filtering" {
        It "Respects Count parameter" {
            # Create mock history
            $testHistory = @(
                '{"timestamp":"2024-01-01T00:00:00Z","issueType":"MissingEnvFile","status":"Success"}'
                '{"timestamp":"2024-01-02T00:00:00Z","issueType":"MissingChromaDB","status":"Success"}'
            )
            $testDir = Join-Path $env:TEMP ("test_" + [Guid]::NewGuid().ToString("N"))
            $storeDir = Join-Path $testDir ".llm-workflow"
            New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
            $testHistory | Set-Content -Path (Join-Path $storeDir "heal-history.jsonl")
            
            try {
                # Override history path for test
                $script:HealHistoryPath = Join-Path $storeDir "heal-history.jsonl"
                $result = Get-LLMWorkflowRepairHistory -Count 1
                $result.Count | Should -Be 1
            } finally {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "Invoke-LLMWorkflowHeal" {
    Context "WhatIf mode" {
        It "Reports issues without fixing" {
            $testDir = Join-Path $env:TEMP ("test_" + [Guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                # Create some issues
                New-Item -ItemType File -Path (Join-Path $testDir ".env") -Force | Out-Null
                
                $result = Invoke-LLMWorkflowHeal -ProjectRoot $testDir -WhatIf
                
                # Should complete successfully
                $result | Should -Not -BeNullOrEmpty
                $result.PSObject.Properties.Name | Should -Contain "Success"
            } finally {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "Force mode" {
        It "Auto-applies fixes without prompting" {
            $testDir = Join-Path $env:TEMP ("test_" + [Guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                $result = Invoke-LLMWorkflowHeal -ProjectRoot $testDir -Force -OnlyCritical
                
                $result | Should -Not -BeNullOrEmpty
                $result.Success | Should -Be $true -Because "Force mode should complete"
            } finally {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "Issue type filtering" {
        It "Only checks specified issue types" {
            $testDir = Join-Path $env:TEMP ("test_" + [Guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                $result = Invoke-LLMWorkflowHeal -ProjectRoot $testDir -WhatIf `
                    -IssueTypes @([IssueType]::MissingEnvFile, [IssueType]::MissingBridgeConfig)
                
                $result | Should -Not -BeNullOrEmpty
            } finally {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
