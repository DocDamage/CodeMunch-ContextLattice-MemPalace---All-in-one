# Policy and Execution Mode System Tests
# Pester tests for Policy.ps1, ExecutionMode.ps1, and CommandContract.ps1

#Requires -Module Pester

BeforeAll {
    $modulePath = Split-Path -Parent $PSScriptRoot
    . (Join-Path $modulePath "Policy.ps1")
    . (Join-Path $modulePath "ExecutionMode.ps1")
    . (Join-Path $modulePath "CommandContract.ps1")
}

Describe "Policy.ps1 Tests" {
    Context "Get-PolicyRules" {
        It "Returns default policy when no file exists" {
            $policy = Get-PolicyRules -PolicyPath "/nonexistent/policy.json"
            $policy.schemaVersion | Should -Be 1
            $policy.defaultMode | Should -Be "interactive"
            $policy.rules | Should -Not -BeNullOrEmpty
        }
        
        It "Contains expected execution mode rules" {
            $policy = Get-PolicyRules
            $policy.rules.'mcp-readonly' | Should -Not -BeNullOrEmpty
            $policy.rules.watch | Should -Not -BeNullOrEmpty
            $policy.rules.ci | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Test-PolicyPermission" {
        It "Allows read-only commands in mcp-readonly mode" {
            Test-PolicyPermission -Command "doctor" -Mode "mcp-readonly" | Should -Be $true
            Test-PolicyPermission -Command "status" -Mode "mcp-readonly" | Should -Be $true
            Test-PolicyPermission -Command "search" -Mode "mcp-readonly" | Should -Be $true
        }
        
        It "Blocks destructive commands in mcp-readonly mode" {
            Test-PolicyPermission -Command "restore" -Mode "mcp-readonly" | Should -Be $false
            Test-PolicyPermission -Command "prune" -Mode "mcp-readonly" | Should -Be $false
            Test-PolicyPermission -Command "delete" -Mode "mcp-readonly" | Should -Be $false
        }
        
        It "Blocks migrate/restore/prune in watch mode" {
            Test-PolicyPermission -Command "migrate" -Mode "watch" | Should -Be $false
            Test-PolicyPermission -Command "restore" -Mode "watch" | Should -Be $false
            Test-PolicyPermission -Command "prune" -Mode "watch" | Should -Be $false
        }
        
        It "Allows sync/index/telemetry in watch mode" {
            Test-PolicyPermission -Command "sync" -Mode "watch" | Should -Be $true
            Test-PolicyPermission -Command "index" -Mode "watch" | Should -Be $true
            Test-PolicyPermission -Command "telemetry" -Mode "watch" | Should -Be $true
        }
        
        It "Allows all commands in interactive mode" {
            Test-PolicyPermission -Command "restore" -Mode "interactive" | Should -Be $true
            Test-PolicyPermission -Command "prune" -Mode "interactive" | Should -Be $true
            Test-PolicyPermission -Command "delete" -Mode "interactive" | Should -Be $true
        }
    }
    
    Context "Assert-PolicyPermission" {
        It "Throws when command is not allowed" {
            { Assert-PolicyPermission -Command "restore" -Mode "watch" } | Should -Throw
        }
        
        It "Does not throw when command is allowed" {
            { Assert-PolicyPermission -Command "sync" -Mode "watch" } | Should -Not -Throw
        }
    }
    
    Context "Test-RequiresConfirmation" {
        It "Returns true for destructive commands" {
            Test-RequiresConfirmation -Command "restore" | Should -Be $true
            Test-RequiresConfirmation -Command "prune" | Should -Be $true
            Test-RequiresConfirmation -Command "delete" | Should -Be $true
        }
        
        It "Returns false for safe commands" {
            Test-RequiresConfirmation -Command "doctor" | Should -Be $false
            Test-RequiresConfirmation -Command "status" | Should -Be $false
        }
    }
    
    Context "Register-PolicyAction" {
        It "Registers new actions requiring confirmation" {
            Register-PolicyAction -Command "custom-dangerous-op"
            Test-RequiresConfirmation -Command "custom-dangerous-op" | Should -Be $true
            Unregister-PolicyAction -Command "custom-dangerous-op"
        }
    }
    
    Context "Get-PolicyExitCode" {
        It "Returns correct exit codes" {
            Get-PolicyExitCode -Reason "PolicyBlocked" | Should -Be 9
            Get-PolicyExitCode -Reason "PermissionDeniedByMode" | Should -Be 11
            Get-PolicyExitCode -Reason "UserCancelled" | Should -Be 12
        }
    }
}

Describe "ExecutionMode.ps1 Tests" {
    Context "Get-ExecutionModePolicy" {
        It "Returns policy for valid modes" {
            $policy = Get-ExecutionModePolicy -Mode "ci"
            $policy.description | Should -Not -BeNullOrEmpty
            $policy.capabilities | Should -Not -BeNullOrEmpty
        }
        
        It "Throws for invalid mode" {
            { Get-ExecutionModePolicy -Mode "invalid-mode" } | Should -Throw
        }
    }
    
    Context "Test-ExecutionModeCapability" {
        It "Allows valid capabilities in ci mode" {
            Test-ExecutionModeCapability -Capability "sync" -Mode "ci" | Should -Be $true
            Test-ExecutionModeCapability -Capability "build" -Mode "ci" | Should -Be $true
        }
        
        It "Blocks destructive capabilities in ci mode" {
            Test-ExecutionModeCapability -Capability "restore" -Mode "ci" | Should -Be $false
            Test-ExecutionModeCapability -Capability "delete" -Mode "ci" | Should -Be $false
        }
        
        It "Allows destructive in interactive mode" {
            Test-ExecutionModeCapability -Capability "restore" -Mode "interactive" | Should -Be $true
        }
        
        It "Blocks destructive safety level in watch mode" {
            Test-ExecutionModeCapability -Capability "cleanup" -Mode "watch" -SafetyLevel "destructive" | Should -Be $false
        }
    }
    
    Context "Get-CurrentExecutionMode" {
        It "Returns a valid mode" {
            $mode = Get-CurrentExecutionMode
            $validModes = Get-ValidExecutionModes
            $validModes | Should -Contain $mode
        }
    }
    
    Context "Switch-ExecutionMode" {
        It "Changes execution mode" {
            $originalMode = Get-CurrentExecutionMode
            $result = Switch-ExecutionMode -Mode "ci" -Force
            $result.changed | Should -Be $true
            $result.previousMode | Should -Be $originalMode
            $result.newMode | Should -Be "ci"
            
            # Restore original mode
            Switch-ExecutionMode -Mode $originalMode -Force | Out-Null
        }
        
        It "Does not change when already in mode" {
            $currentMode = Get-CurrentExecutionMode
            $result = Switch-ExecutionMode -Mode $currentMode
            $result.changed | Should -Be $false
        }
    }
    
    Context "Get-AllowedCommands" {
        It "Returns allowed commands for mode" {
            $commands = Get-AllowedCommands -Mode "watch"
            $commands | Should -Contain "sync"
            $commands | Should -Contain "index"
            $commands | Should -Not -Contain "restore"
        }
        
        It "Returns detailed info with IncludeDetails" {
            $commands = Get-AllowedCommands -Mode "watch" -IncludeDetails
            $commands[0] | Should -HaveMember "command"
            $commands[0] | Should -HaveMember "safetyLevel"
        }
    }
    
    Context "Get-CommandSafetyLevel" {
        It "Returns correct safety levels" {
            (Get-CommandSafetyLevel -Command "doctor") | Should -Contain "read-only"
            (Get-CommandSafetyLevel -Command "sync") | Should -Contain "mutating"
            (Get-CommandSafetyLevel -Command "sync") | Should -Contain "networked"
            (Get-CommandSafetyLevel -Command "restore") | Should -Contain "destructive"
        }
    }
    
    Context "Get-ExecutionModeContext" {
        It "Returns comprehensive context" {
            $context = Get-ExecutionModeContext
            $context | Should -HaveMember "mode"
            $context | Should -HaveMember "capabilities"
            $context | Should -HaveMember "restrictions"
            $context | Should -HaveMember "environment"
        }
    }
    
    Context "Test-IsInteractiveMode" {
        It "Returns correct value based on mode" {
            # Save current
            $originalMode = Get-CurrentExecutionMode
            
            Switch-ExecutionMode -Mode "interactive" -Force | Out-Null
            Test-IsInteractiveMode | Should -Be $true
            
            Switch-ExecutionMode -Mode "ci" -Force | Out-Null
            Test-IsInteractiveMode | Should -Be $false
            
            # Restore
            Switch-ExecutionMode -Mode $originalMode -Force | Out-Null
        }
    }
    
    Context "Get-ValidExecutionModes" {
        It "Returns all valid modes" {
            $modes = Get-ValidExecutionModes
            $modes | Should -Contain "interactive"
            $modes | Should -Contain "ci"
            $modes | Should -Contain "watch"
            $modes | Should -Contain "mcp-readonly"
            $modes | Should -Contain "mcp-mutating"
        }
    }
}

Describe "CommandContract.ps1 Tests" {
    Context "New-CommandContract" {
        It "Creates contract with required properties" {
            $contract = New-CommandContract -Name "test-sync" `
                -Purpose "Test synchronization" `
                -SafetyLevels @("mutating", "networked") `
                -Locks @("sync")
            
            $contract.name | Should -Be "test-sync"
            $contract.purpose | Should -Be "Test synchronization"
            $contract.safetyLevels | Should -Contain "mutating"
            $contract.safetyLevels | Should -Contain "networked"
            $contract.locks | Should -Contain "sync"
            $contract.isMutating | Should -Be $true
            $contract.schemaVersion | Should -Be 1
        }
        
        It "Merges custom exit codes with standards" {
            $customCodes = @{ CustomError = 99 }
            $contract = New-CommandContract -Name "test" `
                -Purpose "Test" `
                -SafetyLevels @("read-only") `
                -ExitCodes $customCodes
            
            $contract.exitCodes.Success | Should -Be 0
            $contract.exitCodes.PolicyBlocked | Should -Be 9
            $contract.exitCodes.CustomError | Should -Be 99
        }
        
        It "Warns when mutating command lacks dry-run behavior" {
            { New-CommandContract -Name "test-mutating" `
                -Purpose "Test" `
                -SafetyLevels @("mutating") 3>&1 } | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Get-CommandContract" {
        It "Retrieves registered contract" {
            New-CommandContract -Name "test-get" -Purpose "Test get" -SafetyLevels @("read-only")
            $contract = Get-CommandContract -Name "test-get"
            $contract | Should -Not -BeNullOrEmpty
            $contract.name | Should -Be "test-get"
        }
        
        It "Returns null for unregistered contract" {
            Get-CommandContract -Name "nonexistent" | Should -BeNullOrEmpty
        }
    }
    
    Context "Test-CommandContract" {
        BeforeAll {
            $testContract = New-CommandContract -Name "test-validate" `
                -Purpose "Test validation" `
                -SafetyLevels @("mutating") `
                -Parameters @{
                    RequiredParam = @{ type = "string"; required = $true }
                    OptionalParam = @{ type = "int"; required = $false }
                } `
                -DryRunBehavior "Shows what would be synced"
        }
        
        It "Validates required parameters" {
            $result = Test-CommandContract -Contract $testContract -Arguments @{}
            $result.IsValid | Should -Be $false
            $result.Errors | Should -Contain "Missing required parameter: RequiredParam"
        }
        
        It "Passes validation with required parameters" {
            $result = Test-CommandContract -Contract $testContract -Arguments @{
                RequiredParam = "value"
            }
            $result.IsValid | Should -Be $true
        }
        
        It "Validates parameter types" {
            $result = Test-CommandContract -Contract $testContract -Arguments @{
                RequiredParam = "value"
                OptionalParam = "not-an-int"
            }
            $result.IsValid | Should -Be $false
        }
    }
    
    Context "New-ExecutionPlan" {
        It "Creates execution plan from contract" {
            $contract = New-CommandContract -Name "test-plan" `
                -Purpose "Test planning" `
                -SafetyLevels @("mutating") `
                -Locks @("test") `
                -StateTouched @("state.json") `
                -DryRunBehavior "Preview only"
            
            $plan = New-ExecutionPlan -Contract $contract
            $plan.command | Should -Be "test-plan"
            $plan.planned | Should -Be $true
            $plan.locksRequired | Should -Contain "test"
            $plan.steps | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Add-PlanStep" {
        It "Adds steps to plan" {
            $contract = New-CommandContract -Name "test-steps" -Purpose "Test" -SafetyLevels @("mutating")
            $plan = New-ExecutionPlan -Contract $contract
            
            Add-PlanStep -Plan $plan -Description "Step 1" -Action { Write-Host "Step 1" }
            Add-PlanStep -Plan $plan -Description "Step 2" -Action { Write-Host "Step 2" } -IsDestructive
            
            $plan.steps.Count | Should -Be 2
            $plan.steps[0].stepNumber | Should -Be 1
            $plan.steps[1].stepNumber | Should -Be 2
            $plan.steps[1].isDestructive | Should -Be $true
        }
    }
    
    Context "Show-ExecutionPlan" {
        It "Returns text representation by default" {
            $contract = New-CommandContract -Name "test-show" -Purpose "Show test" -SafetyLevels @("mutating")
            $plan = New-ExecutionPlan -Contract $contract
            Add-PlanStep -Plan $plan -Description "Test step" -Action {}
            
            $output = Show-ExecutionPlan -Plan $plan
            $output | Should -BeOfType [string]
            $output | Should -Match "test-show"
            $output | Should -Match "Test step"
        }
        
        It "Returns JSON when requested" {
            $contract = New-CommandContract -Name "test-json" -Purpose "JSON test" -SafetyLevels @("mutating")
            $plan = New-ExecutionPlan -Contract $contract
            
            $output = Show-ExecutionPlan -Plan $plan -Format "json"
            $output | Should -Match '"command":'
            $output | Should -Match '"planned":'
        }
    }
    
    Context "Get-StandardExitCodes" {
        It "Returns all standard exit codes" {
            $codes = Get-StandardExitCodes
            $codes.Success | Should -Be 0
            $codes.PolicyBlocked | Should -Be 9
            $codes.PermissionDeniedByMode | Should -Be 11
            $codes.UserCancelled | Should -Be 12
        }
    }
}
