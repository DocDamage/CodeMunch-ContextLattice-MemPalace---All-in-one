<#
.SYNOPSIS
    Pack Transaction and Lockfile management for LLM Workflow platform.

.DESCRIPTION
    Functions for pack build transactions, lockfiles, and release discipline
    per Section 10 of the canonical architecture.

.NOTES
    Author: LLM Workflow Platform
    Version: 0.4.0
    Date: 2026-04-12
#>

# Transaction states
$script:TransactionStates = @(
    'prepare',
    'build',
    'validate',
    'promote',
    'rollback'
)

if (-not (Get-Command ConvertTo-LLMHashtable -ErrorAction SilentlyContinue)) {
    function ConvertTo-LLMHashtable {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline = $true)]$InputObject)

        process {
            if ($null -eq $InputObject) { return $null }

            if ($InputObject -is [System.Collections.IDictionary]) {
                $hash = @{}
                foreach ($key in $InputObject.Keys) {
                    $hash[$key] = ConvertTo-LLMHashtable -InputObject $InputObject[$key]
                }
                return $hash
            }

            if ($InputObject -is [PSCustomObject] -or $InputObject -is [System.Management.Automation.PSCustomObject]) {
                $hash = @{}
                foreach ($prop in $InputObject.PSObject.Properties) {
                    $hash[$prop.Name] = ConvertTo-LLMHashtable -InputObject $prop.Value
                }
                return $hash
            }

            if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
                $result = @()
                foreach ($item in $InputObject) {
                    $result += ,(ConvertTo-LLMHashtable -InputObject $item)
                }
                return $result
            }

            return $InputObject
        }
    }
}

if (-not (Get-Command ConvertFrom-LLMJsonToHashtable -ErrorAction SilentlyContinue)) {
    function ConvertFrom-LLMJsonToHashtable {
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$Json)

        $convertFromJson = Get-Command ConvertFrom-Json -ErrorAction Stop
        if ($convertFromJson.Parameters.ContainsKey('AsHashtable')) {
            return ($Json | ConvertFrom-Json -AsHashtable)
        }

        return ConvertTo-LLMHashtable -InputObject ($Json | ConvertFrom-Json)
    }
}

<#
.SYNOPSIS
    Creates a new pack transaction.

.DESCRIPTION
    Initializes a pack transaction per Section 10.1.
    Transactions follow: prepare -> build -> validate -> promote -> (rollback if needed)

.PARAMETER PackId
    The pack ID.

.PARAMETER PackVersion
    The pack version being built.

.PARAMETER RunId
    The run ID for this transaction.

.PARAMETER ParentTransactionId
    Optional parent transaction for chained builds.
#>
function New-PackTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackId,

        [Parameter(Mandatory)]
        [string]$PackVersion,

        [Parameter()]
        [string]$RunId,

        [Parameter()]
        [string]$ParentTransactionId
    )

    begin {
        if (-not $RunId) {
            $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
        }
    }

    process {
        $transaction = @{
            schemaVersion = 1
            transactionId = $RunId
            packId = $PackId
            packVersion = $PackVersion
            state = 'prepare'
            parentTransactionId = $ParentTransactionId
            stages = @{
                prepare = @{ status = 'in-progress'; startedUtc = [DateTime]::UtcNow.ToString("o"); completedUtc = $null; errors = @() }
                build = @{ status = 'pending'; startedUtc = $null; completedUtc = $null; errors = @() }
                validate = @{ status = 'pending'; startedUtc = $null; completedUtc = $null; errors = @() }
                promote = @{ status = 'pending'; startedUtc = $null; completedUtc = $null; errors = @() }
            }
            createdUtc = [DateTime]::UtcNow.ToString("o")
            updatedUtc = [DateTime]::UtcNow.ToString("o")
            createdByRunId = $RunId
        }

        return $transaction
    }
}

<#
.SYNOPSIS
    Advances a transaction to the next stage.

.DESCRIPTION
    Moves the transaction through the pipeline stages.

.PARAMETER Transaction
    The transaction object.

.PARAMETER Stage
    The stage to transition to.

.PARAMETER Success
    Whether the previous stage succeeded.

.PARAMETER Errors
    Any errors from the previous stage.
#>
function Move-PackTransactionStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Transaction,

        [Parameter(Mandatory)]
        [ValidateSet('prepare', 'build', 'validate', 'promote', 'rollback')]
        [string]$Stage,

        [Parameter()]
        [bool]$Success = $true,

        [Parameter()]
        [string[]]$Errors = @()
    )

    process {
        $currentStage = $Transaction.state
        $now = [DateTime]::UtcNow.ToString("o")

        if (-not $Success) {
            # Failure is attributed to the requested stage. If we were transitioning
            # from a different in-progress stage, mark it completed first.
            if ($Stage -ne $currentStage -and $Transaction.stages[$currentStage]) {
                $Transaction.stages[$currentStage].status = 'completed'
                $Transaction.stages[$currentStage].completedUtc = $now
                $Transaction.stages[$currentStage].errors = @()
            }

            if ($Transaction.stages[$Stage]) {
                if (-not $Transaction.stages[$Stage].startedUtc) {
                    $Transaction.stages[$Stage].startedUtc = $now
                }
                $Transaction.stages[$Stage].completedUtc = $now
                $Transaction.stages[$Stage].status = 'failed'
                $Transaction.stages[$Stage].errors = $Errors
            }

            $Transaction.state = 'rollback'
            $Transaction.updatedUtc = $now
            return $Transaction
        }

        # Complete current stage
        if ($Transaction.stages[$currentStage]) {
            $Transaction.stages[$currentStage].completedUtc = $now
            $Transaction.stages[$currentStage].errors = @()
            $Transaction.stages[$currentStage].status = 'completed'
        }

        # Transition to new stage
        $Transaction.state = $Stage
        if ($Transaction.stages[$Stage]) {
            $Transaction.stages[$Stage].status = 'in-progress'
            $Transaction.stages[$Stage].startedUtc = $now
        }

        $Transaction.updatedUtc = $now
        return $Transaction
    }
}

<#
.SYNOPSIS
    Creates a pack lockfile.

.DESCRIPTION
    Creates a deterministic pack.lock.json per Section 10.2.

.PARAMETER PackId
    The pack ID.

.PARAMETER PackVersion
    The pack version.

.PARAMETER ToolkitVersion
    The toolkit version used.

.PARAMETER TaxonomyVersion
    The taxonomy version.

.PARAMETER Sources
    Array of source entries with resolved refs.

.PARAMETER RunId
    The run ID.
#>
function New-PackLockfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackId,

        [Parameter(Mandatory)]
        [string]$PackVersion,

        [Parameter()]
        [string]$ToolkitVersion = "0.4.0",

        [Parameter()]
        [string]$TaxonomyVersion = "1",

        [Parameter()]
        [array]$Sources = @(),

        [Parameter()]
        [hashtable]$BuildMetadata = @{},

        [Parameter()]
        [string]$RunId
    )

    begin {
        if (-not $RunId) {
            $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
        }
    }

    process {
        $lockSources = @($Sources | ForEach-Object {
            @{
                sourceId = $_.sourceId
                repoUrl = $_.repoUrl
                selectedRef = $_.selectedRef
                resolvedCommit = $_.resolvedCommit
                parseMode = $_.parseMode
                parserVersion = $_.parserVersion
                chunkCount = $_.chunkCount
                extractedAt = [DateTime]::UtcNow.ToString("o")
            }
        })

        $lockfile = @{
            schemaVersion = 1
            packId = $PackId
            packVersion = $PackVersion
            builtUtc = [DateTime]::UtcNow.ToString("o")
            toolkitVersion = $ToolkitVersion
            taxonomyVersion = $TaxonomyVersion
            sources = $lockSources
            buildMetadata = $BuildMetadata
            createdByRunId = $RunId
        }

        return $lockfile
    }
}

<#
.SYNOPSIS
    Saves a pack lockfile to disk.

.DESCRIPTION
    Saves the lockfile to the builds directory.

.PARAMETER Lockfile
    The lockfile object.

.PARAMETER Staging
    Whether to save to staging (true) or promoted (false).
#>
function Save-PackLockfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Lockfile,

        [Parameter()]
        [bool]$Staging = $true
    )

    process {
        $packId = $Lockfile.packId
        $version = $Lockfile.packVersion
        $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmss")

        $dir = if ($Staging) { "packs/staging" } else { "packs/promoted" }
        $dir = Join-Path $dir $packId

        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $path = Join-Path $dir "$version-$timestamp.pack.lock.json"
        $Lockfile | ConvertTo-Json -Depth 10 | Out-File -FilePath $path -Encoding UTF8

        # Also save as latest
        $latestPath = Join-Path $dir "latest.pack.lock.json"
        $Lockfile | ConvertTo-Json -Depth 10 | Out-File -FilePath $latestPath -Encoding UTF8

        Write-Verbose "Lockfile saved to $path"
        return $path
    }
}

<#
.SYNOPSIS
    Loads a pack lockfile.

.DESCRIPTION
    Loads a lockfile from staging or promoted.

.PARAMETER PackId
    The pack ID.

.PARAMETER Version
    Specific version to load (loads latest if not specified).

.PARAMETER PromotedOnly
    Only look in promoted directory.
#>
function Get-PackLockfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackId,

        [Parameter()]
        [string]$Version,

        [Parameter()]
        [switch]$PromotedOnly
    )

    process {
        $dirs = @()
        if (-not $PromotedOnly) {
            $dirs += "packs/staging/$packId"
        }
        $dirs += "packs/promoted/$packId"

        foreach ($dir in $dirs) {
            if (-not (Test-Path $dir)) { continue }

            if ($Version) {
                $pattern = "*$Version*.pack.lock.json"
                $files = Get-ChildItem -Path $dir -Filter $pattern | Sort-Object LastWriteTime -Descending
            }
            else {
                $latest = Join-Path $dir "latest.pack.lock.json"
                if (Test-Path $latest) {
                    return ConvertFrom-LLMJsonToHashtable -Json (Get-Content $latest -Raw)
                }
                $files = Get-ChildItem -Path $dir -Filter "*.pack.lock.json" | Sort-Object LastWriteTime -Descending
            }

            if ($files) {
                return ConvertFrom-LLMJsonToHashtable -Json (Get-Content $files[0].FullName -Raw)
            }
        }

        Write-Warning "No lockfile found for pack $PackId"
        return $null
    }
}

<#
.SYNOPSIS
    Creates a pack build manifest.

.DESCRIPTION
    Creates a comprehensive build manifest per Section 10.4.

.PARAMETER PackId
    The pack ID.

.PARAMETER PackVersion
    The pack version.

.PARAMETER Lockfile
    The associated lockfile.

.PARAMETER ArtifactCounts
    Hashtable of artifact counts by type.

.PARAMETER EvalResults
    Evaluation results summary.

.PARAMETER RunId
    The run ID.
#>
function New-PackBuildManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackId,

        [Parameter(Mandatory)]
        [string]$PackVersion,

        [Parameter()]
        [hashtable]$Lockfile,

        [Parameter()]
        [hashtable]$ArtifactCounts = @{},

        [Parameter()]
        [hashtable]$ExtractionCounts = @{},

        [Parameter()]
        [hashtable]$EvalResults = @{},

        [Parameter()]
        [string]$RollbackTarget,

        [Parameter()]
        [string]$RunId
    )

    begin {
        if (-not $RunId) {
            $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
        }
    }

    process {
        $manifest = @{
            schemaVersion = 1
            packId = $PackId
            packVersion = $PackVersion
            builtUtc = [DateTime]::UtcNow.ToString("o")
            lockfilePath = $null
            artifactCounts = $ArtifactCounts
            extractionCounts = $ExtractionCounts
            evalResults = $EvalResults
            statusSummary = @{
                overallStatus = if ($EvalResults.passed) { 'passed' } else { 'failed' }
                testCount = $EvalResults.testCount
                passCount = $EvalResults.passCount
                failCount = $EvalResults.failCount
            }
            rollbackTarget = $RollbackTarget
            createdByRunId = $RunId
        }

        if ($Lockfile) {
            $manifest.lockfilePath = "packs/builds/$PackId/$PackVersion.lock.json"
        }

        return $manifest
    }
}

<#
.SYNOPSIS
    Promotes a staged build to promoted.

.DESCRIPTION
    Moves a build from staging to promoted after validation passes.
    Per Section 10.1: No staged build becomes live until validation and eval pass.

.PARAMETER PackId
    The pack ID.

.PARAMETER Version
    The version to promote.

.PARAMETER Transaction
    The build transaction.
#>
function Publish-PackBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackId,

        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [hashtable]$Transaction
    )

    process {
        # Verify transaction state
        if ($Transaction.state -ne 'validate') {
            Write-Warning "Cannot promote: transaction not in validate state. Current state: $($Transaction.state)"
            return $null
        }

        if ($Transaction.stages.validate.status -eq 'failed') {
            Write-Warning "Cannot promote: validation stage has failed."
            return $null
        }

        # Load lockfile from staging
        $lockfile = Get-PackLockfile -PackId $PackId
        if (-not $lockfile) {
            Write-Error "No lockfile found in staging for $PackId"
            return $null
        }

        # Save to promoted
        $promotedPath = Save-PackLockfile -Lockfile $lockfile -Staging $false

        # Update transaction
        $Transaction = Move-PackTransactionStage -Transaction $Transaction -Stage 'promote' -Success $true

        Write-Verbose "Pack $PackId v$Version promoted to production"
        return [PSCustomObject]@{
            Success = $true
            PromotedPath = $promotedPath
            Transaction = $Transaction
        }
    }
}

<#
.SYNOPSIS
    Rolls back a failed or problematic build.

.DESCRIPTION
    Reverts to a previous rollback target.

.PARAMETER PackId
    The pack ID.

.PARAMETER Transaction
    The current transaction.

.PARAMETER RollbackTarget
    The target version to roll back to.
#>
function Undo-PackBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackId,

        [Parameter(Mandatory)]
        [hashtable]$Transaction,

        [Parameter()]
        [string]$RollbackTarget
    )

    process {
        $Transaction.state = 'rollback'
        $Transaction.updatedUtc = [DateTime]::UtcNow.ToString("o")

        if ($RollbackTarget) {
            # Load target lockfile
            $targetLockfile = Get-PackLockfile -PackId $PackId -Version $RollbackTarget -PromotedOnly

            if ($targetLockfile) {
                # Copy to promoted as current
                Save-PackLockfile -Lockfile $targetLockfile -Staging $false
                Write-Verbose "Rolled back $PackId to $RollbackTarget"
            }
            else {
                Write-Error "Rollback target not found: $RollbackTarget"
                return $null
            }
        }

        $Transaction.rollbackTarget = $RollbackTarget
        return $Transaction
    }
}

<#
.SYNOPSIS
    Creates pack status summary for health reporting.

.DESCRIPTION
    Generates a summary of pack build status.

.PARAMETER PackId
    The pack ID.
#>
function Get-PackBuildStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackId
    )

    process {
        $stagingDir = "packs/staging/$PackId"
        $promotedDir = "packs/promoted/$PackId"

        $stagingBuilds = @()
        $promotedBuilds = @()

        if (Test-Path $stagingDir) {
            $stagingBuilds = @(Get-ChildItem -Path $stagingDir -Filter "*.pack.lock.json" |
                Where-Object { $_.Name -ne 'latest.pack.lock.json' } |
                ForEach-Object {
                    $content = Get-Content $_.FullName -Raw | ConvertFrom-Json
                    [PSCustomObject]@{
                        Version = $content.packVersion
                        Built = $content.builtUtc
                        Toolkit = $content.toolkitVersion
                    }
                })
        }

        if (Test-Path $promotedDir) {
            $promotedBuilds = @(Get-ChildItem -Path $promotedDir -Filter "*.pack.lock.json" |
                Where-Object { $_.Name -ne 'latest.pack.lock.json' } |
                ForEach-Object {
                    $content = Get-Content $_.FullName -Raw | ConvertFrom-Json
                    [PSCustomObject]@{
                        Version = $content.packVersion
                        Built = $content.builtUtc
                        Toolkit = $content.toolkitVersion
                    }
                })
        }

        return [PSCustomObject]@{
            PackId = $PackId
            StagingBuilds = $stagingBuilds.Count
            PromotedBuilds = $promotedBuilds.Count
            LatestStaging = $stagingBuilds | Sort-Object Built -Descending | Select-Object -First 1
            LatestPromoted = $promotedBuilds | Sort-Object Built -Descending | Select-Object -First 1
        }
    }
}

# Export-ModuleMember handled by LLMWorkflow.psm1
