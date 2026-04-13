#requires -Version 5.1
<#
.SYNOPSIS
    Failure taxonomy and recovery guidance for the LLM Workflow platform.

.DESCRIPTION
    Classifies failures into categories, determines whether each category is
    recoverable, and suggests the appropriate recovery action.  Supports
    classification by explicit category, exception object, or raw message text.

.NOTES
    File: FailureTaxonomy.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Compatible with: PowerShell 5.1+

.EXAMPLE
    Get-FailureTaxonomy

.EXAMPLE
    Test-RecoverableFailure -Category "transient"

.EXAMPLE
    Get-RecoveryAction -Message "The remote server returned an error: (503)"
#>

Set-StrictMode -Version Latest

$script:FailureTaxonomyMap = @{
    transient = [pscustomobject]@{
        Category       = 'transient'
        Description    = 'Temporary failures likely to resolve on retry (network hiccups, service unavailable).'
        Recoverable    = $true
        RecoveryAction = 'Retry with exponential backoff.'
    }
    persistent = [pscustomobject]@{
        Category       = 'persistent'
        Description    = 'Persistent logic or configuration errors that will not resolve on retry.'
        Recoverable    = $false
        RecoveryAction = 'Alert operator and halt workflow; investigate root cause.'
    }
    permission = [pscustomobject]@{
        Category       = 'permission'
        Description    = 'Authentication or authorization failures.'
        Recoverable    = $false
        RecoveryAction = 'Verify credentials, permissions, and tokens; re-authorize before retry.'
    }
    resource = [pscustomobject]@{
        Category       = 'resource'
        Description    = 'Resource exhaustion such as disk full or memory pressure.'
        Recoverable    = $true
        RecoveryAction = 'Free resources, scale up, or split workload, then retry.'
    }
    timeout = [pscustomobject]@{
        Category       = 'timeout'
        Description    = 'Operation exceeded its allotted time.'
        Recoverable    = $true
        RecoveryAction = 'Increase timeout, split workload into smaller chunks, or retry.'
    }
    data = [pscustomobject]@{
        Category       = 'data'
        Description    = 'Data validation, schema mismatch, or missing required fields.'
        Recoverable    = $false
        RecoveryAction = 'Inspect source data, correct schema issues, and re-ingest.'
    }
}

function Resolve-FailureCategory {
    <#
    .SYNOPSIS
        Maps an exception message to a failure category.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return 'persistent'
    }

    $lower = $Message.ToLowerInvariant()
    switch -Regex ($lower) {
        'timeout|timed out|deadline exceeded' { return 'timeout' }
        'unauthorized|access denied|permission|forbidden|auth' { return 'permission' }
        'disk full|out of memory|memory|resource|quota|rate limit' { return 'resource' }
        'network|connection|unavailable|transient|temporary|503|502|504' { return 'transient' }
        'schema|validation|invalid data|missing field|data' { return 'data' }
        default { return 'persistent' }
    }
}

function Get-FailureTaxonomy {
    <#
    .SYNOPSIS
        Returns the full failure taxonomy.

    .DESCRIPTION
        Returns all six failure categories as an array of objects.

    .OUTPUTS
        System.Object[]
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param()

    $result = @($script:FailureTaxonomyMap.Values)
    return ,$result
}

function Test-RecoverableFailure {
    <#
    .SYNOPSIS
        Determines whether a failure is recoverable.

    .DESCRIPTION
        Accepts an explicit category, an exception object, or a message
        string and returns $true when the failure is classified as
        recoverable.

    .PARAMETER Category
        Explicit failure category.

    .PARAMETER Exception
        A .NET exception object whose Message will be analysed.

    .PARAMETER Message
        Raw failure message text.

    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(ParameterSetName = 'Category')]
        [ValidateSet('transient', 'persistent', 'permission', 'resource', 'timeout', 'data')]
        [string]$Category,

        [Parameter(ParameterSetName = 'Exception', ValueFromPipeline = $true)]
        [Exception]$Exception,

        [Parameter(ParameterSetName = 'Message')]
        [string]$Message
    )

    process {
        $cat = if ($PSCmdlet.ParameterSetName -eq 'Category') {
            $Category
        }
        else {
            $text = if ($Exception) { $Exception.Message } else { $Message }
            Resolve-FailureCategory -Message $text
        }

        if ($script:FailureTaxonomyMap.ContainsKey($cat)) {
            return $script:FailureTaxonomyMap[$cat].Recoverable
        }
        return $false
    }
}

function Get-RecoveryAction {
    <#
    .SYNOPSIS
        Suggests the appropriate recovery action for a failure.

    .DESCRIPTION
        Accepts an explicit category, an exception object, or a message
        string and returns the recommended recovery action.

    .PARAMETER Category
        Explicit failure category.

    .PARAMETER Exception
        A .NET exception object whose Message will be analysed.

    .PARAMETER Message
        Raw failure message text.

    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(ParameterSetName = 'Category')]
        [ValidateSet('transient', 'persistent', 'permission', 'resource', 'timeout', 'data')]
        [string]$Category,

        [Parameter(ParameterSetName = 'Exception', ValueFromPipeline = $true)]
        [Exception]$Exception,

        [Parameter(ParameterSetName = 'Message')]
        [string]$Message
    )

    process {
        $cat = if ($PSCmdlet.ParameterSetName -eq 'Category') {
            $Category
        }
        else {
            $text = if ($Exception) { $Exception.Message } else { $Message }
            Resolve-FailureCategory -Message $text
        }

        if ($script:FailureTaxonomyMap.ContainsKey($cat)) {
            return $script:FailureTaxonomyMap[$cat].RecoveryAction
        }
        return 'Alert operator and halt workflow; investigate root cause.'
    }
}

if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'Get-FailureTaxonomy',
        'Test-RecoverableFailure',
        'Get-RecoveryAction'
    )
}
