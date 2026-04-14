#requires -Version 5.1
<#
.SYNOPSIS
    Durable workflow orchestration primitives for the LLM Workflow platform.

.DESCRIPTION
    Provides lightweight checkpoint-and-resume durable execution for
    PowerShell-based workflows.  Checkpoints are written as JSON files
    under .llm-workflow/checkpoints/ and contain enough state to resume
    after process crashes or operator-initiated stops.

.NOTES
    File: DurableOrchestrator.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Compatible with: PowerShell 5.1+

.EXAMPLE
    $wf = New-DurableWorkflow -WorkflowId "pack-build" -Steps @(
        @{ Name = "validate"; Action = { Test-PackManifest } },
        @{ Name = "build";    Action = { Invoke-PackBuild } }
    )
    Invoke-DurableWorkflow -Workflow $wf

.EXAMPLE
    Resume-DurableWorkflow -Workflow $wf
#>

Set-StrictMode -Version Latest

$failureTaxonomyPath = Join-Path $PSScriptRoot 'FailureTaxonomy.ps1'
if (Test-Path $failureTaxonomyPath) {
    . $failureTaxonomyPath
}

$script:CheckpointDirName = ".llm-workflow\checkpoints"

#===============================================================================
# Internal helpers
#===============================================================================

function New-WorkflowRunId {
    <#
    .SYNOPSIS
        Generates a new run identifier for durable workflows.
    #>
    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $random = -join ((1..4) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    return "$timestamp-$random"
}

function Get-CheckpointDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )

    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }

    $dir = Join-Path $resolvedRoot $script:CheckpointDirName
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    return $dir
}

function Get-CheckpointPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkflowId,

        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [string]$ProjectRoot = "."
    )

    $dir = Get-CheckpointDirectory -ProjectRoot $ProjectRoot
    return Join-Path $dir "$WorkflowId.$RunId.checkpoint.json"
}

function Write-Checkpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkflowId,

        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        [int]$StepIndex,

        [array]$StepResults = @(),

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$ProjectRoot = "."
    )

    $path = Get-CheckpointPath -WorkflowId $WorkflowId -RunId $RunId -ProjectRoot $ProjectRoot

    $data = [ordered]@{
        workflowId  = $WorkflowId
        runId       = $RunId
        stepIndex   = $StepIndex
        stepResults = $StepResults
        status      = $Status
        timestamp   = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    $json = $data | ConvertTo-Json -Depth 10 -Compress:$false
    $writeAttempts = 3
    $writeSuccess = $false
    for ($a = 1; $a -le $writeAttempts; $a++) {
        try {
            $json | Out-File -FilePath $path -Encoding utf8 -Force -ErrorAction Stop
            $writeSuccess = $true
            break
        }
        catch [System.IO.IOException] {
            if ($a -lt $writeAttempts) {
                Start-Sleep -Milliseconds 100
            }
            else {
                throw "Failed to write checkpoint to '$path': $_"
            }
        }
        catch {
            throw "Failed to write checkpoint to '$path': $_"
        }
    }
    if (-not $writeSuccess) {
        throw "Failed to write checkpoint to '$path' after $writeAttempts attempts."
    }
}

function Read-Checkpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkflowId,

        [string]$RunId = "",

        [string]$ProjectRoot = "."
    )

    $dir = Get-CheckpointDirectory -ProjectRoot $ProjectRoot

    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        $path = Join-Path $dir "$WorkflowId.$RunId.checkpoint.json"
        if (Test-Path -LiteralPath $path) {
            $content = Get-Content -LiteralPath $path -Raw
            $checkpoint = $content | ConvertFrom-Json

            # PowerShell 5.1 array-unwrapping guard
            if ($checkpoint.stepResults -isnot [array] -and $checkpoint.stepResults -isnot [System.Collections.ArrayList]) {
                if ($null -ne $checkpoint.stepResults) {
                    $checkpoint.stepResults = @($checkpoint.stepResults)
                }
                else {
                    $checkpoint.stepResults = @()
                }
            }
            return $checkpoint
        }
        return $null
    }
    else {
        $pattern = "$WorkflowId.*.checkpoint.json"
        $files = Get-ChildItem -Path $dir -Filter $pattern -File -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending

        if ($files) {
            $content = Get-Content -LiteralPath $files[0].FullName -Raw
            $checkpoint = $content | ConvertFrom-Json

            if ($checkpoint.stepResults -isnot [array] -and $checkpoint.stepResults -isnot [System.Collections.ArrayList]) {
                if ($null -ne $checkpoint.stepResults) {
                    $checkpoint.stepResults = @($checkpoint.stepResults)
                }
                else {
                    $checkpoint.stepResults = @()
                }
            }
            return $checkpoint
        }
        return $null
    }
}

#===============================================================================
# Public functions
#===============================================================================

function New-DurableWorkflow {
    <#
    .SYNOPSIS
        Creates a workflow definition with steps and checkpoints.

    .DESCRIPTION
        Returns a hashtable representing the durable workflow.  The caller
        supplies an array of step definitions; each step is a hashtable that
        may contain Name and Action keys.

    .PARAMETER WorkflowId
        Unique identifier for this workflow type.

    .PARAMETER Steps
        Array of step definitions (hashtables with Name and Action).

    .PARAMETER RunId
        Optional run identifier.  If omitted, a new run ID is generated.

    .PARAMETER ProjectRoot
        Project root directory.  Defaults to the current directory.

    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkflowId,

        [Parameter(Mandatory = $true)]
        [array]$Steps,

        [string]$RunId = "",

        [string]$ProjectRoot = "."
    )

    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $RunId = New-WorkflowRunId
    }

    return @{
        WorkflowId  = $WorkflowId
        RunId       = $RunId
        Steps       = $Steps
        ProjectRoot = $ProjectRoot
    }
}

function Invoke-DurableWorkflow {
    <#
    .SYNOPSIS
        Executes a durable workflow, saving checkpoints after each step.

    .DESCRIPTION
        Runs the steps defined in the workflow object.  After every
        successful step a checkpoint is written with status "running".
        If a step throws, the checkpoint is written with status "failed"
        and the exception is re-thrown.  When -Resume is specified, the
        function reads the latest checkpoint and skips already-completed
        steps.

    .PARAMETER Workflow
        Workflow object returned by New-DurableWorkflow.

    .PARAMETER Resume
        If set, resumes from the latest checkpoint instead of starting
        from the beginning.

    .PARAMETER ProjectRoot
        Project root directory.  Defaults to the workflow's ProjectRoot.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with the final state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Workflow,

        [switch]$Resume,

        [string]$ProjectRoot = ".",

        [int]$MaxRetryCount = 3,

        [int]$RetryDelaySeconds = 2
    )

    $wf = $Workflow
    if ($wf -is [System.Management.Automation.PSCustomObject]) {
        $ht = @{}
        $wf.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
        $wf = $ht
    }

    $workflowId = $wf.WorkflowId
    $runId      = $wf.RunId
    $steps      = $wf.Steps
    $projRoot   = if ($ProjectRoot -and $ProjectRoot -ne ".") { $ProjectRoot } else { $wf.ProjectRoot }

    if ([string]::IsNullOrWhiteSpace($workflowId)) {
        throw "Workflow object is missing WorkflowId."
    }
    if ($null -eq $steps -or $steps.Count -eq 0) {
        throw "Workflow object has no Steps."
    }

    $stepIndex   = 0
    $stepResults = [System.Collections.ArrayList]::new()

    if ($Resume) {
        $checkpoint = Read-Checkpoint -WorkflowId $workflowId -RunId $runId -ProjectRoot $projRoot
        if ($checkpoint) {
            $stepIndex = $checkpoint.stepIndex
            if ($checkpoint.stepResults) {
                foreach ($r in $checkpoint.stepResults) {
                    # Only keep results from steps that completed successfully
                    if ($r.stepIndex -lt $stepIndex) {
                        $stepResults.Add($r) | Out-Null
                    }
                }
            }
            Write-Verbose "[DurableOrchestrator] Resuming workflow '$workflowId' ($runId) from step $stepIndex"
        }
        else {
            Write-Warning "[DurableOrchestrator] No checkpoint found for workflow '$workflowId' ($runId). Starting from the beginning."
        }
    }

    for ($i = $stepIndex; $i -lt $steps.Count; $i++) {
        $step     = $steps[$i]
        $stepName = if ($step.Name) { $step.Name } else { "Step-$i" }
        $action   = $step.Action

        $output = $null
        $status = "success"
        $stepSucceeded = $false

        for ($attempt = 0; $attempt -le $MaxRetryCount; $attempt++) {
            try {
                if ($action) {
                    $result = & $action
                    if ($null -ne $result) {
                        $output = ($result | Out-String).Trim()
                    }
                }
                $stepSucceeded = $true
                break
            }
            catch {
                $isRecoverable = $false
                if ($_.Exception) {
                    $isRecoverable = Test-RecoverableFailure -Exception $_.Exception
                }

                if ($isRecoverable -and $attempt -lt $MaxRetryCount) {
                    $delay = $RetryDelaySeconds * ($attempt + 1)
                    Write-Verbose "[DurableOrchestrator] Step '$stepName' failed (attempt $($attempt + 1)). Retrying in $delay seconds..."
                    Start-Sleep -Seconds $delay
                }
                else {
                    $status = "failed"
                    $output = $_.Exception.Message

                    $record = [pscustomobject]@{
                        stepName  = $stepName
                        stepIndex = $i
                        status    = $status
                        output    = $output
                        timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    }
                    $stepResults.Add($record) | Out-Null
                    Write-Checkpoint -WorkflowId $workflowId -RunId $runId -StepIndex $i `
                        -StepResults $stepResults.ToArray() -Status "failed" -ProjectRoot $projRoot
                    throw "Workflow step '$stepName' failed: $_"
                }
            }
        }

        if (-not $stepSucceeded) {
            throw "Workflow step '$stepName' failed after $MaxRetryCount retries."
        }

        $record = [pscustomobject]@{
            stepName  = $stepName
            stepIndex = $i
            status    = $status
            output    = $output
            timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        $stepResults.Add($record) | Out-Null
        Write-Checkpoint -WorkflowId $workflowId -RunId $runId -StepIndex ($i + 1) `
            -StepResults $stepResults.ToArray() -Status "running" -ProjectRoot $projRoot
    }

    Write-Checkpoint -WorkflowId $workflowId -RunId $runId -StepIndex $steps.Count `
        -StepResults $stepResults.ToArray() -Status "completed" -ProjectRoot $projRoot

    return [pscustomobject]@{
        WorkflowId  = $workflowId
        RunId       = $runId
        StepIndex   = $steps.Count
        StepResults = $stepResults.ToArray()
        Status      = "completed"
    }
}

function Start-DurableWorkflow {
    <#
    .SYNOPSIS
        Creates and immediately executes a durable workflow with sensible defaults.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkflowId,

        [Parameter(Mandatory = $true)]
        [array]$Steps,

        [string]$RunId = "",

        [string]$ProjectRoot = "."
    )

    $wf = New-DurableWorkflow -WorkflowId $WorkflowId -Steps $Steps -RunId $RunId -ProjectRoot $ProjectRoot
    return Invoke-DurableWorkflow -Workflow $wf -ProjectRoot $ProjectRoot -MaxRetryCount 3
}

function Get-DurableWorkflowState {
    <#
    .SYNOPSIS
        Reads the last saved checkpoint for a workflow.

    .DESCRIPTION
        Returns the most recent checkpoint object for the given workflow.
        If RunId is omitted, the latest checkpoint across all runs for the
        workflow is returned.

    .PARAMETER WorkflowId
        The workflow identifier.

    .PARAMETER RunId
        Optional run identifier.

    .PARAMETER ProjectRoot
        Project root directory.  Defaults to the current directory.

    .OUTPUTS
        System.Management.Automation.PSCustomObject or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkflowId,

        [string]$RunId = "",

        [string]$ProjectRoot = "."
    )

    return Read-Checkpoint -WorkflowId $WorkflowId -RunId $RunId -ProjectRoot $ProjectRoot
}

function Resume-DurableWorkflow {
    <#
    .SYNOPSIS
        Resumes a workflow from the last checkpoint.

    .DESCRIPTION
        Loads the latest checkpoint and continues execution from the next
        unfinished step.

    .PARAMETER Workflow
        Workflow object returned by New-DurableWorkflow.

    .PARAMETER ProjectRoot
        Project root directory.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with the final state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Workflow,

        [string]$ProjectRoot = "."
    )

    return Invoke-DurableWorkflow -Workflow $Workflow -Resume -ProjectRoot $ProjectRoot
}

function Stop-DurableWorkflow {
    <#
    .SYNOPSIS
        Gracefully stops a workflow and saves a checkpoint.

    .DESCRIPTION
        Reads the latest checkpoint (if any) and updates its status to
        "stopped".  If no checkpoint exists, a new one is created at
        step index 0.

    .PARAMETER WorkflowId
        The workflow identifier.

    .PARAMETER RunId
        Optional run identifier.

    .PARAMETER ProjectRoot
        Project root directory.

    .OUTPUTS
        System.Management.Automation.PSCustomObject representing the
        stopped checkpoint.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkflowId,

        [string]$RunId = "",

        [string]$ProjectRoot = "."
    )

    $checkpoint     = $null
    $resolvedRunId  = $RunId

    if ([string]::IsNullOrWhiteSpace($resolvedRunId)) {
        $checkpoint = Read-Checkpoint -WorkflowId $WorkflowId -RunId "" -ProjectRoot $ProjectRoot
        if ($checkpoint) {
            $resolvedRunId = $checkpoint.runId
        }
    }
    else {
        $checkpoint = Read-Checkpoint -WorkflowId $WorkflowId -RunId $resolvedRunId -ProjectRoot $ProjectRoot
    }

    if (-not $checkpoint) {
        if ([string]::IsNullOrWhiteSpace($resolvedRunId)) {
            $resolvedRunId = New-WorkflowRunId
        }
        $checkpoint = [pscustomobject]@{
            workflowId  = $WorkflowId
            runId       = $resolvedRunId
            stepIndex   = 0
            stepResults = @()
            status      = "stopped"
            timestamp   = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    }
    else {
        $checkpoint.status    = "stopped"
        $checkpoint.timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    Write-Checkpoint -WorkflowId $WorkflowId -RunId $resolvedRunId `
        -StepIndex $checkpoint.stepIndex -StepResults $checkpoint.stepResults `
        -Status $checkpoint.status -ProjectRoot $ProjectRoot

    return $checkpoint
}

if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'New-DurableWorkflow',
        'Invoke-DurableWorkflow',
        'Start-DurableWorkflow',
        'Get-DurableWorkflowState',
        'Resume-DurableWorkflow',
        'Stop-DurableWorkflow'
    )
}
