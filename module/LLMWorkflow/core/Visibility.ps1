#requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Workspace and Visibility Boundary System - Visibility Enforcement
.DESCRIPTION
    Provides visibility boundary enforcement and secret protection for the
    LLM Workflow platform. Ensures secrets and sensitive content are properly
    redacted and access controls are enforced.
.NOTES
    File: Visibility.ps1
    Version: 1.0.0
    Compatible with: PowerShell 5.1+
#>

# Secret detection patterns
$script:SecretPatterns = @{
    # API Keys
    OpenAI_API_Key = @{
        Pattern = 'sk-[a-zA-Z0-9]{48}'
        Type = 'api_key'
        Severity = 'critical'
    }
    Anthropic_API_Key = @{
        Pattern = 'sk-ant-[a-zA-Z0-9]{32,}'
        Type = 'api_key'
        Severity = 'critical'
    }
    AWS_Access_Key = @{
        Pattern = 'AKIA[0-9A-Z]{16}'
        Type = 'api_key'
        Severity = 'critical'
    }
    AWS_Secret_Key = @{
        Pattern = '[0-9a-zA-Z/+]{40}'
        Type = 'secret_key'
        Severity = 'critical'
    }
    Generic_API_Key = @{
        Pattern = '(?i)(api[_-]?key|apikey)\s*[:=]\s*["'']?[a-zA-Z0-9_\-]{16,}["'']?'
        Type = 'api_key'
        Severity = 'high'
    }
    
    # Tokens
    Bearer_Token = @{
        Pattern = 'bearer\s+[a-zA-Z0-9_\-\.]+'
        Type = 'token'
        Severity = 'high'
    }
    JWT_Token = @{
        Pattern = 'eyJ[a-zA-Z0-9_\-]*\.eyJ[a-zA-Z0-9_\-]*\.[a-zA-Z0-9_\-]*'
        Type = 'jwt'
        Severity = 'high'
    }
    
    # Connection Strings
    SQL_Connection = @{
        Pattern = '(?i)(Server|Data Source)=[^;]+;.*(Password|Pwd)=[^;]+'
        Type = 'connection_string'
        Severity = 'critical'
    }
    MongoDB_URI = @{
        Pattern = 'mongodb(\+srv)?://[^:]+:[^@]+@'
        Type = 'connection_string'
        Severity = 'critical'
    }
    Redis_Connection = @{
        Pattern = 'redis://:[^@]+@'
        Type = 'connection_string'
        Severity = 'critical'
    }
    
    # Private Keys
    RSA_Private_Key = @{
        Pattern = '-----BEGIN RSA PRIVATE KEY-----'
        Type = 'private_key'
        Severity = 'critical'
    }
    SSH_Private_Key = @{
        Pattern = '-----BEGIN OPENSSH PRIVATE KEY-----'
        Type = 'private_key'
        Severity = 'critical'
    }
    PEM_Private_Key = @{
        Pattern = '-----BEGIN PRIVATE KEY-----'
        Type = 'private_key'
        Severity = 'critical'
    }
    
    # PII Patterns
    Credit_Card = @{
        Pattern = '\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|6(?:011|5[0-9]{2})[0-9]{12}|(?:2131|1800|35\d{3})\d{11})\b'
        Type = 'pii'
        Severity = 'critical'
    }
    SSN = @{
        Pattern = '\b\d{3}-\d{2}-\d{4}\b'
        Type = 'pii'
        Severity = 'critical'
    }
    Email_Address = @{
        Pattern = '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'
        Type = 'pii'
        Severity = 'medium'
    }
    
    # Passwords
    Password_in_URL = @{
        Pattern = '(?i)[:/][^/:]+:[^@/]+@'
        Type = 'password'
        Severity = 'critical'
    }
    Password_Assignment = @{
        Pattern = '(?i)(password|passwd|pwd)\s*[:=]\s*["''][^"'']+["'']'
        Type = 'password'
        Severity = 'high'
    }
}

# Visibility levels in order of restrictiveness (most restrictive first)
$script:VisibilityLevels = @('private', 'local-team', 'shared', 'public-reference')

#region Private Helper Functions

function Write-VisibilityAuditLog {
    <#
    .SYNOPSIS
        Logs visibility control decisions for audit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceId,
        
        [bool]$Allowed,
        
        [string]$Reason = ''
    )
    
    $logEntry = [pscustomobject]@{
        timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')
        operation = $Operation
        resourceId = $ResourceId
        allowed = $Allowed
        reason = $Reason
        user = $env:USERNAME
    }
    
    $logDir = Join-Path $HOME '.llm-workflow/logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $logPath = Join-Path $logDir 'visibility-audit.log'
    $logEntry | ConvertTo-Json -Compress | Add-Content -LiteralPath $logPath -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Get-VisibilityRank {
    <#
    .SYNOPSIS
        Gets the numeric rank of a visibility level (lower = more restrictive).
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Visibility
    )
    
    $index = $script:VisibilityLevels.IndexOf($Visibility)
    if ($index -eq -1) {
        return 999
    }
    return $index
}

#endregion

#region Public Functions

function Test-VisibilityRule {
    <#
    .SYNOPSIS
        Tests if an operation is allowed under visibility rules.
    .DESCRIPTION
        Evaluates whether a requested operation (read, export, federate)
        is permitted based on visibility settings and workspace context.
    .PARAMETER Operation
        The operation type: read, export, federate, or share.
    .PARAMETER Visibility
        The visibility level of the resource.
    .PARAMETER WorkspaceContext
        The current workspace context.
    .PARAMETER TargetContext
        The target context for the operation (e.g., export destination).
    .EXAMPLE
        Test-VisibilityRule -Operation 'export' -Visibility 'private' -WorkspaceContext $workspace
        Tests if exporting private content is allowed.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('read', 'export', 'federate', 'share')]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('private', 'local-team', 'shared', 'public-reference')]
        [string]$Visibility,
        
        [Parameter(Mandatory = $true)]
        [pscustomobject]$WorkspaceContext,
        
        [string]$TargetContext = ''
    )
    
    $result = @{
        Allowed = $false
        Reason = ''
        RequiresRedaction = $false
        AuditRequired = $true
    }
    
    switch ($Operation) {
        'read' {
            if ($Visibility -eq 'private') {
                $result.Allowed = $true
                $result.AuditRequired = $true
            }
            elseif ($Visibility -eq 'local-team') {
                $result.Allowed = $true
                $result.AuditRequired = $false
            }
            else {
                $result.Allowed = $true
                $result.AuditRequired = $false
            }
        }
        
        'export' {
            switch ($Visibility) {
                'private' {
                    $result.Allowed = $false
                    $result.Reason = 'Private content cannot be exported'
                    $result.AuditRequired = $true
                }
                'local-team' {
                    $result.Allowed = ($WorkspaceContext.type -in @('team', 'project'))
                    $result.Reason = if (-not $result.Allowed) { 'Team content only exportable from team/project workspaces' } else { '' }
                    $result.AuditRequired = $true
                }
                'shared' {
                    $result.Allowed = $true
                    $result.RequiresRedaction = $true
                    $result.AuditRequired = $true
                }
                'public-reference' {
                    $result.Allowed = $true
                    $result.AuditRequired = $false
                }
            }
        }
        
        'federate' {
            switch ($Visibility) {
                'private' {
                    $result.Allowed = $false
                    $result.Reason = 'Private content cannot be federated'
                    $result.AuditRequired = $true
                }
                'local-team' {
                    $result.Allowed = $false
                    $result.Reason = 'Team content cannot be federated'
                    $result.AuditRequired = $true
                }
                'shared' {
                    $result.Allowed = $true
                    $result.RequiresRedaction = $true
                    $result.AuditRequired = $true
                }
                'public-reference' {
                    $result.Allowed = $true
                    $result.AuditRequired = $false
                }
            }
        }
        
        'share' {
            switch ($Visibility) {
                'private' {
                    $result.Allowed = $false
                    $result.Reason = 'Private content cannot be shared'
                    $result.AuditRequired = $true
                }
                'local-team' {
                    $result.Allowed = ($WorkspaceContext.type -in @('team', 'project'))
                    $result.Reason = if (-not $result.Allowed) { 'Team content only shareable within team/project workspaces' } else { '' }
                    $result.AuditRequired = $true
                }
                'shared' {
                    $result.Allowed = $true
                    $result.AuditRequired = $false
                }
                'public-reference' {
                    $result.Allowed = $true
                    $result.AuditRequired = $false
                }
            }
        }
    }
    
    Write-VisibilityAuditLog -Operation $Operation -ResourceId "visibility:$Visibility" -Allowed $result.Allowed -Reason $result.Reason
    
    return [pscustomobject]$result
}

function Get-PackVisibility {
    <#
    .SYNOPSIS
        Returns visibility settings for a pack.
    .DESCRIPTION
        Retrieves the visibility configuration for a specified pack,
        including visibility level, exportability, and federation rules.
    .PARAMETER PackId
        The unique identifier of the pack.
    .PARAMETER WorkspaceContext
        Optional workspace context for workspace-specific rules.
    .EXAMPLE
        Get-PackVisibility -PackId 'rpgmaker_private_project'
        Returns visibility settings for the specified pack.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,
        
        [pscustomobject]$WorkspaceContext = $null
    )
    
    $visibility = @{
        PackId = $PackId
        Visibility = 'shared'
        Exportable = $true
        Federatable = $false
        AllowedAnswerContexts = @('same-project', 'same-pack', 'any')
        WorkspaceLocal = $false
    }
    
    if ($PackId -match '_private_|-private-') {
        $visibility.Visibility = 'private'
        $visibility.Exportable = $false
        $visibility.Federatable = $false
        $visibility.AllowedAnswerContexts = @('local-only')
        $visibility.WorkspaceLocal = $true
    }
    elseif ($PackId -match '_team_|-team-') {
        $visibility.Visibility = 'local-team'
        $visibility.Exportable = $true
        $visibility.Federatable = $false
        $visibility.AllowedAnswerContexts = @('same-project', 'local-only')
    }
    elseif ($PackId -match '_public_|-public-|reference') {
        $visibility.Visibility = 'public-reference'
        $visibility.Exportable = $true
        $visibility.Federatable = $true
        $visibility.AllowedAnswerContexts = @('any')
    }
    
    if ($WorkspaceContext -and $WorkspaceContext.visibilityRules) {
        $packRule = $WorkspaceContext.visibilityRules[$PackId]
        if ($packRule) {
            switch ($packRule) {
                'workspace-local' {
                    $visibility.Visibility = 'private'
                    $visibility.WorkspaceLocal = $true
                }
                'team-only' {
                    $visibility.Visibility = 'local-team'
                }
                'public' {
                    $visibility.Visibility = 'public-reference'
                }
            }
        }
    }
    
    return [pscustomobject]$visibility
}

function Test-ExportPermission {
    <#
    .SYNOPSIS
        Tests if content can be exported based on visibility policy.
    .DESCRIPTION
        Comprehensive export permission check that evaluates content
        visibility, workspace context, and performs secret scanning.
    .PARAMETER Content
        The content to be exported (string or object).
    .PARAMETER Context
        The workspace context.
    .PARAMETER ContentVisibility
        The visibility level of the content.
    .PARAMETER SkipSecretScan
        Skip secret scanning (not recommended).
    .EXAMPLE
        Test-ExportPermission -Content $data -Context $workspace -ContentVisibility 'shared'
        Tests if the content can be exported.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Content,
        
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,
        
        [ValidateSet('private', 'local-team', 'shared', 'public-reference')]
        [string]$ContentVisibility = 'shared',
        
        [switch]$SkipSecretScan
    )
    
    $result = @{
        Allowed = $false
        BlockedBy = @()
        Warnings = @()
        RequiresRedaction = $false
        SecretScanResults = $null
    }
    
    $visibilityCheck = Test-VisibilityRule -Operation 'export' -Visibility $ContentVisibility -WorkspaceContext $Context
    if (-not $visibilityCheck.Allowed) {
        $result.BlockedBy += 'visibility'
        $result.Warnings += $visibilityCheck.Reason
    }
    
    if (-not $SkipSecretScan) {
        $contentString = if ($Content -is [string]) { $Content } else { $Content | ConvertTo-Json -Depth 10 }
        $scanResult = Test-SecretInContent -Content $contentString
        $result.SecretScanResults = $scanResult
        
        if ($scanResult.HasSecrets) {
            $result.RequiresRedaction = $true
            $criticalCount = ($scanResult.Findings | Where-Object { $_.Severity -eq 'critical' }).Count
            if ($criticalCount -gt 0) {
                $result.BlockedBy += 'secrets'
                $result.Warnings += "Found $criticalCount critical secrets that must be redacted"
            }
        }
    }
    
    $result.Allowed = ($result.BlockedBy.Count -eq 0)
    
    return [pscustomobject]$result
}

function Protect-SecretData {
    <#
    .SYNOPSIS
        Redacts secrets from data before export or display.
    .DESCRIPTION
        Scans content for potential secrets and redacts them with
        configurable replacement patterns.
    .PARAMETER Content
        The content containing potential secrets.
    .PARAMETER Findings
        Pre-computed secret findings from Test-SecretInContent.
    .PARAMETER ReplacementPattern
        Pattern for redacted content (default: '[REDACTED:<type>]').
    .PARAMETER HashReplacement
        Replace with hash instead of generic token.
    .EXAMPLE
        Protect-SecretData -Content $json -Findings $scan.Findings
        Returns content with secrets redacted.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter(Mandatory = $true)]
        [array]$Findings,
        
        [string]$ReplacementPattern = '[REDACTED:{0}]',
        
        [switch]$HashReplacement
    )
    
    # Sort by position (descending) to avoid offset issues during replacement
    $sortedFindings = @($Findings | Sort-Object -Property StartIndex -Descending)
    
    # Handle overlapping findings - remove overlaps
    $filteredFindings = @()
    $lastStart = -1
    foreach ($finding in $sortedFindings) {
        if ($finding.StartIndex -lt $lastStart -and $lastStart -ne -1) {
            # This finding overlaps with previous, skip it
            continue
        }
        $filteredFindings += $finding
        $lastStart = $finding.StartIndex
    }
    
    # Re-sort back to original order for processing
    $processOrder = @($filteredFindings | Sort-Object -Property StartIndex -Descending)
    
    $redactedContent = $Content
    $offset = 0
    
    # Track position adjustments due to replacements
    $positionMap = @{}
    
    foreach ($finding in $processOrder) {
        $originalStart = $finding.StartIndex
        $originalLength = $finding.Length
        
        # Calculate adjusted position based on previous replacements
        $adjustedStart = $originalStart
        foreach ($pos in $positionMap.Keys | Sort-Object -Descending) {
            if ($originalStart -gt $pos) {
                $adjustedStart += $positionMap[$pos]
            }
        }
        
        $replacement = if ($HashReplacement) {
            $hash = [System.BitConverter]::ToString(
                [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                    [System.Text.Encoding]::UTF8.GetBytes($finding.MatchedValue)
                )
            ).Replace('-', '').Substring(0, 8)
            "[REDACTED:$hash]"
        }
        else {
            $ReplacementPattern -f $finding.Type
        }
        
        $replacementLength = $replacement.Length
        $lengthDiff = $replacementLength - $originalLength
        
        # Only process if we're still within bounds
        if ($adjustedStart -ge 0 -and $adjustedStart -lt $redactedContent.Length) {
            $redactedContent = $redactedContent.Substring(0, $adjustedStart) + 
                              $replacement + 
                              $redactedContent.Substring($adjustedStart + $originalLength)
            
            # Record position adjustment
            $positionMap[$originalStart] = $lengthDiff
        }
    }
    
    return $redactedContent
}

function Test-SecretInContent {
    <#
    .SYNOPSIS
        Scans content for potential secrets and PII.
    .DESCRIPTION
        Performs comprehensive scanning for API keys, tokens, connection
        strings, private keys, and personally identifiable information.
    .PARAMETER Content
        The content to scan for secrets.
    .PARAMETER IncludePatterns
        Specific pattern names to include (scans all if not specified).
    .PARAMETER ExcludePatterns
        Pattern names to exclude from scanning.
    .PARAMETER SeverityThreshold
        Minimum severity to report: low, medium, high, critical.
    .EXAMPLE
        Test-SecretInContent -Content $jsonString
        Scans content for all secret patterns.
    .EXAMPLE
        Test-SecretInContent -Content $text -SeverityThreshold 'high'
        Only reports high and critical severity findings.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [string[]]$IncludePatterns = @(),
        
        [string[]]$ExcludePatterns = @(),
        
        [ValidateSet('low', 'medium', 'high', 'critical')]
        [string]$SeverityThreshold = 'low'
    )
    
    $severityRank = @{ 'low' = 0; 'medium' = 1; 'high' = 2; 'critical' = 3 }
    $minSeverity = $severityRank[$SeverityThreshold]
    
    $findings = @()
    $patternsToScan = $script:SecretPatterns
    
    if ($IncludePatterns.Count -gt 0) {
        $patternsToScan = @{}
        foreach ($patternName in $IncludePatterns) {
            if ($script:SecretPatterns.ContainsKey($patternName)) {
                $patternsToScan[$patternName] = $script:SecretPatterns[$patternName]
            }
        }
    }
    
    foreach ($patternName in $patternsToScan.Keys) {
        if ($ExcludePatterns -contains $patternName) {
            continue
        }
        
        $patternInfo = $patternsToScan[$patternName]
        $patternSeverity = $severityRank[$patternInfo.Severity]
        
        if ($patternSeverity -lt $minSeverity) {
            continue
        }
        
        $regex = [regex]::new($patternInfo.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $matches = $regex.Matches($Content)
        
        foreach ($match in $matches) {
            $contextStart = [Math]::Max(0, $match.Index - 20)
            $contextLength = [Math]::Min(40 + $match.Length, $Content.Length - $contextStart)
            $context = $Content.Substring($contextStart, $contextLength)
            
            $findings += [pscustomobject]@{
                PatternName = $patternName
                Type = $patternInfo.Type
                Severity = $patternInfo.Severity
                MatchedValue = $match.Value
                StartIndex = $match.Index
                Length = $match.Length
                Context = $context
            }
        }
    }
    
    $sortedFindings = @($findings | Sort-Object -Property StartIndex)
    
    $summary = @()
    $findingsList = @($findings)
    if ($findingsList.Count -gt 0) {
        $grouped = $findingsList | Group-Object -Property Type
        foreach ($group in $grouped) {
            $summary += [pscustomobject]@{
                Type = $group.Name
                Count = $group.Count
            }
        }
    }
    
    return [pscustomobject]@{
        HasSecrets = ($findingsList.Count -gt 0)
        TotalFindings = $findingsList.Count
        Findings = $sortedFindings
        Summary = $summary
    }
}

function Protect-LogEntry {
    <#
    .SYNOPSIS
        Redacts sensitive data from log entries before writing.
    .DESCRIPTION
        Ensures secrets are never written to logs unredacted by scanning
        and redacting content before logging.
    .PARAMETER Message
        The log message to protect.
    .PARAMETER AllowPartialContent
        Allow partial content if redaction fails.
    .EXAMPLE
        Protect-LogEntry -Message "Error with API key: sk-..."
        Returns redacted log-safe message.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [switch]$AllowPartialContent
    )
    
    $scan = Test-SecretInContent -Content $Message -SeverityThreshold 'medium'
    
    if ($scan.HasSecrets) {
        $redacted = Protect-SecretData -Content $Message -Findings $scan.Findings
        return $redacted
    }
    
    return $Message
}

function Assert-NotExportable {
    <#
    .SYNOPSIS
        Asserts that content is not exportable.
    .DESCRIPTION
        Throws an error if the pack or content is marked as non-exportable.
        Use as a guard clause before export operations.
    .PARAMETER Pack
        The pack visibility object or pack ID.
    .PARAMETER ErrorAction
        Error action to take on assertion failure.
    .EXAMPLE
        Assert-NotExportable -Pack $pack
        Throws error if pack is not exportable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Pack,
        
        [System.Management.Automation.ActionPreference]$ErrorAction = 'Stop'
    )
    
    $packVisibility = if ($Pack -is [string]) { 
        Get-PackVisibility -PackId $Pack 
    } 
    else { 
        $Pack 
    }
    
    if (-not $packVisibility.Exportable) {
        $message = "Pack '$($packVisibility.PackId)' is not exportable (visibility: $($packVisibility.Visibility))"
        Write-VisibilityAuditLog -Operation 'assert_not_exportable' -ResourceId $packVisibility.PackId -Allowed $false -Reason 'not_exportable'
        
        if ($ErrorAction -ne 'SilentlyContinue') {
            throw $message
        }
        return $false
    }
    
    return $true
}

#endregion
