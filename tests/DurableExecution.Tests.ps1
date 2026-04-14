#requires -Version 5.1
<#
.SYNOPSIS
    Pester v5 tests for durable execution and failure taxonomy modules.

.DESCRIPTION
    Covers workflow checkpoint creation, resume from checkpoint, step-by-step
    execution, failure classification, and recovery action selection.

.NOTES
    File: DurableExecution.Tests.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Requires: Pester 5.0+
#>

BeforeAll {
    $script:TestRoot = Join-Path $env:TEMP "LLMWorkflow_DurableTests_$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null

    $script:ModuleRoot = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "module") "LLMWorkflow") "workflow"
    $durablePath = Join-Path $script:ModuleRoot "DurableOrchestrator.ps1"
    $failurePath = Join-Path $script:ModuleRoot "FailureTaxonomy.ps1"

    if (Test-Path $durablePath) { try { . $durablePath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $failurePath) { try { . $failurePath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
}

AfterAll {
    if (Test-Path $script:TestRoot) {
        Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "DurableOrchestrator Module Tests" {
    BeforeEach {
        $cpDir = Join-Path (Join-Path $script:TestRoot ".llm-workflow") "checkpoints"
        if (Test-Path $cpDir) {
            Remove-Item -Path "$cpDir\*" -Force -ErrorAction SilentlyContinue
        }
    }

    Context "New-DurableWorkflow Function" {
        It "Should create a workflow definition with required properties" {
            $wf = New-DurableWorkflow -WorkflowId "test-wf" -Steps @(@{ Name = "s1"; Action = { "a" } }) -ProjectRoot $script:TestRoot
            $wf.WorkflowId | Should -Be "test-wf"
            $wf.Steps.Count | Should -Be 1
            $wf.RunId | Should -Not -BeNullOrEmpty
            $wf.ProjectRoot | Should -Be $script:TestRoot
        }

        It "Should generate a RunId when none is provided" {
            $wf = New-DurableWorkflow -WorkflowId "test-wf" -Steps @(@{ Name = "dummy"; Action = { "x" } }) -ProjectRoot $script:TestRoot
            $wf.RunId | Should -Match "^\d{8}T\d{6}Z-[0-9a-f]{4}$"
        }
    }

    Context "Invoke-DurableWorkflow Function - checkpoint creation and step-by-step execution" {
        It "Should execute all steps and save a completed checkpoint" {
            $steps = @(
                @{ Name = "step1"; Action = { "output1" } },
                @{ Name = "step2"; Action = { "output2" } }
            )
            $wf = New-DurableWorkflow -WorkflowId "checkpoint-wf" -Steps $steps -ProjectRoot $script:TestRoot
            $result = Invoke-DurableWorkflow -Workflow $wf -ProjectRoot $script:TestRoot

            $result.Status | Should -Be "completed"
            @($result.StepResults).Count | Should -Be 2

            $state = Get-DurableWorkflowState -WorkflowId "checkpoint-wf" -RunId $wf.RunId -ProjectRoot $script:TestRoot
            $state | Should -Not -BeNullOrEmpty
            $state.status | Should -Be "completed"
            $state.stepIndex | Should -Be 2
            @($state.stepResults).Count | Should -Be 2
            $state.stepResults[0].stepName | Should -Be "step1"
            $state.stepResults[0].status | Should -Be "success"
            $state.stepResults[1].stepName | Should -Be "step2"
            $state.stepResults[1].status | Should -Be "success"
        }

        It "Should save a checkpoint after each step" {
            $steps = @(
                @{ Name = "step1"; Action = { "a" } },
                @{ Name = "step2"; Action = { "b" } }
            )
            $wf = New-DurableWorkflow -WorkflowId "step-check-wf" -Steps $steps -ProjectRoot $script:TestRoot
            Invoke-DurableWorkflow -Workflow $wf -ProjectRoot $script:TestRoot | Out-Null

            $state = Get-DurableWorkflowState -WorkflowId "step-check-wf" -RunId $wf.RunId -ProjectRoot $script:TestRoot
            @($state.stepResults).Count | Should -Be 2
        }

        It "Should handle a single-step workflow without array unwrapping issues" {
            $steps = @(
                @{ Name = "onlyStep"; Action = { "done" } }
            )
            $wf = New-DurableWorkflow -WorkflowId "single-step-wf" -Steps $steps -ProjectRoot $script:TestRoot
            Invoke-DurableWorkflow -Workflow $wf -ProjectRoot $script:TestRoot | Out-Null

            $state = Get-DurableWorkflowState -WorkflowId "single-step-wf" -RunId $wf.RunId -ProjectRoot $script:TestRoot
            $state.status | Should -Be "completed"
            @($state.stepResults).Count | Should -Be 1
            $state.stepResults[0].stepName | Should -Be "onlyStep"
        }
    }

    Context "Resume-DurableWorkflow Function" {
        It "Should resume from checkpoint after a step failure" {
            $shared = @{ fail = $true }
            $steps = @(
                @{ Name = "step1"; Action = { "ok" } },
                @{ Name = "step2"; Action = { if ($shared.fail) { throw "intentional failure" } ; "ok2" } }
            )
            $wf = New-DurableWorkflow -WorkflowId "resume-wf" -Steps $steps -ProjectRoot $script:TestRoot

            { Invoke-DurableWorkflow -Workflow $wf -ProjectRoot $script:TestRoot } | Should -Throw "*intentional failure*"

            $state = Get-DurableWorkflowState -WorkflowId "resume-wf" -RunId $wf.RunId -ProjectRoot $script:TestRoot
            $state.status | Should -Be "failed"
            $state.stepIndex | Should -Be 1
            @($state.stepResults).Count | Should -Be 2
            $state.stepResults[1].status | Should -Be "failed"

            # Fix the failure and resume
            $shared.fail = $false
            $result = Resume-DurableWorkflow -Workflow $wf -ProjectRoot $script:TestRoot
            $result.Status | Should -Be "completed"
            @($result.StepResults).Count | Should -Be 2
            $result.StepResults[1].status | Should -Be "success"
        }

        It "Should skip completed steps on resume" {
            $shared = @{ counter = 0 }
            $steps = @(
                @{ Name = "step1"; Action = { $shared.counter++ ; "ok" } },
                @{ Name = "step2"; Action = { $shared.counter++ ; "ok2" } }
            )
            $wf = New-DurableWorkflow -WorkflowId "skip-wf" -Steps $steps -ProjectRoot $script:TestRoot
            Invoke-DurableWorkflow -Workflow $wf -ProjectRoot $script:TestRoot | Out-Null

            $shared.counter = 0
            Resume-DurableWorkflow -Workflow $wf -ProjectRoot $script:TestRoot | Out-Null
            # Counter should remain 0 because both steps were already completed
            $shared.counter | Should -Be 0
        }

        It "Should resume after multiple failures and eventually complete" {
            $shared = @{ failCount = 2 }
            $steps = @(
                @{ Name = "step1"; Action = { "ok" } },
                @{ Name = "step2"; Action = { if ($shared.failCount -gt 0) { $shared.failCount-- ; throw "intentional failure" } ; "ok2" } }
            )
            $wf = New-DurableWorkflow -WorkflowId "multi-resume-wf" -Steps $steps -ProjectRoot $script:TestRoot

            { Invoke-DurableWorkflow -Workflow $wf -ProjectRoot $script:TestRoot } | Should -Throw "*intentional failure*"
            $state1 = Get-DurableWorkflowState -WorkflowId "multi-resume-wf" -RunId $wf.RunId -ProjectRoot $script:TestRoot
            $state1.status | Should -Be "failed"

            { Resume-DurableWorkflow -Workflow $wf -ProjectRoot $script:TestRoot } | Should -Throw "*intentional failure*"
            $state2 = Get-DurableWorkflowState -WorkflowId "multi-resume-wf" -RunId $wf.RunId -ProjectRoot $script:TestRoot
            $state2.status | Should -Be "failed"

            $result = Resume-DurableWorkflow -Workflow $wf -ProjectRoot $script:TestRoot
            $result.Status | Should -Be "completed"
            @($result.StepResults).Count | Should -Be 2
            $result.StepResults[1].status | Should -Be "success"
        }
    }

    Context "Stop-DurableWorkflow Function" {
        It "Should write a stopped checkpoint for an existing workflow" {
            $wf = New-DurableWorkflow -WorkflowId "stop-wf" -Steps @(@{ Name = "s1"; Action = { "a" } }) -ProjectRoot $script:TestRoot
            Invoke-DurableWorkflow -Workflow $wf -ProjectRoot $script:TestRoot | Out-Null

            $state = Stop-DurableWorkflow -WorkflowId "stop-wf" -RunId $wf.RunId -ProjectRoot $script:TestRoot
            $state.status | Should -Be "stopped"

            $diskState = Get-DurableWorkflowState -WorkflowId "stop-wf" -RunId $wf.RunId -ProjectRoot $script:TestRoot
            $diskState.status | Should -Be "stopped"
        }

        It "Should create a stopped checkpoint even when no prior checkpoint exists" {
            $state = Stop-DurableWorkflow -WorkflowId "fresh-stop-wf" -ProjectRoot $script:TestRoot
            $state.status | Should -Be "stopped"
            $state.stepIndex | Should -Be 0

            $diskState = Get-DurableWorkflowState -WorkflowId "fresh-stop-wf" -RunId $state.runId -ProjectRoot $script:TestRoot
            $diskState.status | Should -Be "stopped"
        }

        It "Should resume a stopped workflow and complete remaining steps" {
            $shared = @{ counter = 0 }
            $steps = @(
                @{ Name = "step1"; Action = { $shared.counter++ ; "ok1" } },
                @{ Name = "step2"; Action = { $shared.counter++ ; "ok2" } }
            )
            $wf = New-DurableWorkflow -WorkflowId "stopped-resume-wf" -Steps $steps -ProjectRoot $script:TestRoot

            Write-Checkpoint -WorkflowId $wf.WorkflowId -RunId $wf.RunId -StepIndex 1 `
                -StepResults @(
                    [pscustomobject]@{ stepName = "step1"; stepIndex = 0; status = "success"; output = "ok1"; timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ") }
                ) -Status "stopped" -ProjectRoot $script:TestRoot

            $result = Resume-DurableWorkflow -Workflow $wf -ProjectRoot $script:TestRoot
            $result.Status | Should -Be "completed"
            @($result.StepResults).Count | Should -Be 2
            $result.StepResults[1].stepName | Should -Be "step2"
            $result.StepResults[1].status | Should -Be "success"
            $shared.counter | Should -Be 1
        }
    }

    Context "Checkpoint corruption handling" {
        It "Should throw a meaningful error when resuming from corrupted checkpoint JSON" {
            $wf = New-DurableWorkflow -WorkflowId "corrupt-wf" -Steps @(@{ Name = "s1"; Action = { "a" } }) -ProjectRoot $script:TestRoot
            $cpDir = Get-CheckpointDirectory -ProjectRoot $script:TestRoot
            $cpPath = Join-Path $cpDir "$($wf.WorkflowId).$($wf.RunId).checkpoint.json"
            "this is not json{{" | Out-File -FilePath $cpPath -Encoding utf8 -Force

            { Resume-DurableWorkflow -Workflow $wf -ProjectRoot $script:TestRoot } | Should -Throw
        }
    }

    Context "Retry logic integration" {
        It "Should retry transient failures up to MaxRetryCount before failing" {
            $shared = @{ attempts = 0 }
            $steps = @(
                @{ Name = "flakyStep"; Action = { $shared.attempts++ ; throw [System.IO.IOException]::new("Network connection unavailable") } }
            )
            $wf = New-DurableWorkflow -WorkflowId "retry-wf" -Steps $steps -ProjectRoot $script:TestRoot

            { Invoke-DurableWorkflow -Workflow $wf -ProjectRoot $script:TestRoot -MaxRetryCount 2 -RetryDelaySeconds 0 } | Should -Throw "*flakyStep*"

            $shared.attempts | Should -Be 3
            $state = Get-DurableWorkflowState -WorkflowId "retry-wf" -RunId $wf.RunId -ProjectRoot $script:TestRoot
            $state.status | Should -Be "failed"
        }
    }
}

Describe "FailureTaxonomy Module Tests" {
    Context "Get-FailureTaxonomy Function" {
        It "Should return all six failure categories" {
            $taxonomy = Get-FailureTaxonomy
            @($taxonomy).Count | Should -Be 6
            $names = $taxonomy | ForEach-Object { $_.Category }
            @('transient', 'persistent', 'permission', 'resource', 'timeout', 'data') | ForEach-Object {
                $names | Should -Contain $_
            }
        }
    }

    Context "Test-RecoverableFailure Function" {
        It "Should classify transient failures as recoverable" {
            Test-RecoverableFailure -Category "transient" | Should -Be $true
            Test-RecoverableFailure -Message "The remote server returned an error: (503) Server Unavailable" | Should -Be $true
        }

        It "Should classify persistent failures as non-recoverable" {
            Test-RecoverableFailure -Category "persistent" | Should -Be $false
            Test-RecoverableFailure -Message "Object reference not set to an instance of an object" | Should -Be $false
        }

        It "Should classify permission failures as non-recoverable" {
            Test-RecoverableFailure -Category "permission" | Should -Be $false
            Test-RecoverableFailure -Message "Access to the path is denied" | Should -Be $false
        }

        It "Should classify resource failures as recoverable" {
            Test-RecoverableFailure -Category "resource" | Should -Be $true
            $ex = [System.OutOfMemoryException]::new("Out of memory")
            Test-RecoverableFailure -Exception $ex | Should -Be $true
        }

        It "Should classify timeout failures as recoverable" {
            Test-RecoverableFailure -Category "timeout" | Should -Be $true
            Test-RecoverableFailure -Message "The operation has timed out" | Should -Be $true
        }

        It "Should classify data failures as non-recoverable" {
            Test-RecoverableFailure -Category "data" | Should -Be $false
            Test-RecoverableFailure -Message "Schema validation failed" | Should -Be $false
        }
    }

    Context "Get-RecoveryAction Function" {
        It "Should suggest retry for transient failures" {
            $action = Get-RecoveryAction -Category "transient"
            $action | Should -Match "Retry"
        }

        It "Should suggest operator alert for persistent failures" {
            $action = Get-RecoveryAction -Category "persistent"
            $action | Should -Match "operator"
        }

        It "Should suggest credential check for permission failures" {
            $action = Get-RecoveryAction -Message "Unauthorized"
            $action | Should -Match "credential|permission|re-authorize"
        }

        It "Should suggest resource action for out-of-memory" {
            $action = Get-RecoveryAction -Exception ([System.OutOfMemoryException]::new("Out of memory"))
            $action | Should -Match "resource|scale|free"
        }
    }
}
