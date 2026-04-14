#requires -Version 5.1
Set-StrictMode -Version Latest


function New-ReviewPolicy {
    <#
    .SYNOPSIS
        Defines a new review policy.
    
    .DESCRIPTION
        Creates and stores a custom review policy for a specific operation type.
    
    .PARAMETER PolicyName
        The name of the policy (operation type).
    
    .PARAMETER Rules
        Hashtable of trigger rules.
    
    .PARAMETER DefaultReviewers
        Array of default reviewers.
    
    .PARAMETER Conditions
        Approval conditions.
    
    .PARAMETER OperationType
        The operation type category.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject representing the created policy.
    
    .EXAMPLE
        New-ReviewPolicy -PolicyName "custom-operation" -Rules $rules -DefaultReviewers @("alice", "bob")
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Rules,
        
        [array]$DefaultReviewers = @(),
        
        [hashtable]$Conditions = $null,
        
        [string]$OperationType = 'unknown',
        
        [string]$ProjectRoot = "."
    )
    
    # Determine conditions (PowerShell 5.1 compatibility)
    if ($Conditions) {
        $policyConditions = $Conditions
    }
    else {
        $policyConditions = @{
            minApprovers = 1
            requireOwnerApproval = $false
            autoExpireHours = 72
        }
    }
    
    $policy = @{
        name = $PolicyName
        description = "Custom review policy for $PolicyName"
        operationType = $OperationType
        triggers = $Rules
        conditions = $policyConditions
        defaultReviewers = $DefaultReviewers
        createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    $state.policies[$PolicyName] = $policy
    Save-ReviewState -State $state -ProjectRoot $ProjectRoot
    
    Write-Verbose "Created review policy '$PolicyName'"
    
    return New-Object -TypeName PSObject -Property $policy
}



function Get-ReviewPolicy {
    <#
    .SYNOPSIS
        Gets a review policy by name.
    
    .PARAMETER PolicyName
        The policy name.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject representing the policy, or null if not found.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyName,
        
        [string]$ProjectRoot = "."
    )
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    
    if ($state.policies.ContainsKey($PolicyName)) {
        return New-Object -TypeName PSObject -Property $state.policies[$PolicyName]
    }
    
    if ($script:DefaultReviewPolicies.ContainsKey($PolicyName)) {
        return New-Object -TypeName PSObject -Property $script:DefaultReviewPolicies[$PolicyName]
    }
    
    return $null
}



function Invoke-ReviewNotification {
    <#
    .SYNOPSIS
        Triggers notification hooks for review events.
    
    .DESCRIPTION
        Sends notifications via configured channels (email, webhook, etc.).
        This is a stub for integration with external notification systems.
    
    .PARAMETER Request
        The review request.
    
    .PARAMETER EventType
        The type of event: created, decision-submitted, expired, etc.
    
    .PARAMETER ProjectRoot
        The project root directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Request,
        
        [Parameter(Mandatory = $true)]
        [string]$EventType,
        
        [string]$ProjectRoot = "."
    )
    
    # Track notification in request
    $notificationRecord = @{
        eventType = $EventType
        timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        channels = @()
    }
    
    # Hook: Check for notification configuration
    $notifyConfigPath = Join-Path $ProjectRoot ".llm-workflow/notify-config.json"
    $config = $null
    
    if (Test-Path -LiteralPath $notifyConfigPath) {
        try {
            $config = Get-Content -LiteralPath $notifyConfigPath -Raw | ConvertFrom-Json -AsHashtable
        }
        catch {
            Write-Verbose "Failed to load notification config: $_"
        }
    }
    
    # Email notification stub
    if ($config -and $config.email -and $config.email.enabled) {
        $notificationRecord.channels += "email"
        # Integration point: Send-MailMessage or external email service
        Write-Verbose "[Notification] Email would be sent for $EventType on $($Request.requestId)"
    }
    
    # Webhook notification stub
    if ($config -and $config.webhook -and $config.webhook.enabled) {
        $notificationRecord.channels += "webhook"
        # Integration point: Invoke-RestMethod to webhook URL
        Write-Verbose "[Notification] Webhook would be called for $EventType on $($Request.requestId)"
    }
    
    # Console notification (always for high priority)
    if ($Request.priority -in @('high', 'critical') -or $EventType -eq 'expired') {
        $notificationRecord.channels += "console"
        Write-Host "[Review Gate] $EventType for $($Request.operation) - Request: $($Request.requestId)" -ForegroundColor Yellow
    }
    
    # Update request with notification record
    if (-not $Request.ContainsKey('notificationsSent') -or $null -eq $Request.notificationsSent) {
        $Request['notificationsSent'] = @()
    }
    $notificationsArray = @($Request.notificationsSent)
    $notificationsArray += @($notificationRecord)
    $Request['notificationsSent'] = $notificationsArray
    
    # Save state if request exists
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    if ($state.requests.ContainsKey($Request.requestId)) {
        $state.requests[$Request.requestId] = $Request
        Save-ReviewState -State $state -ProjectRoot $ProjectRoot
    }
}



function Invoke-ReviewEscalation {
    <#
    .SYNOPSIS
        Escalates expired or stuck review requests.
    
    .DESCRIPTION
        Checks for reviews that need escalation and triggers escalation
        notifications. Should be run periodically (e.g., via scheduled task).
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        Array of escalated review requests.
    
    .EXAMPLE
        # Run daily via scheduled task
        Invoke-ReviewEscalation | ForEach-Object { Send-EscalationEmail $_ }
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$ProjectRoot = "."
    )
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    $escalated = @()
    $now = [DateTime]::UtcNow
    
    foreach ($requestId in $state.requests.Keys) {
        $request = $state.requests[$requestId]
        
        # Skip completed or already escalated
        if ($request.status -notin @('pending', 'needs-work')) {
            continue
        }
        
        # Check expiration
        if ($request.expiresAt) {
            $expires = [DateTime]::Parse($request.expiresAt)
            
            if ($expires -lt $now -and $request.status -ne 'expired') {
                # Mark as expired/escalated
                $request.status = 'escalated'
                $request.escalatedAt = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                $request.updatedAt = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                
                # Trigger escalation notification (suppress output)
                [void](Invoke-ReviewNotification -Request $request -EventType "expired" -ProjectRoot $ProjectRoot)
                
                # Log escalation
                Write-ReviewLogEntry -Entry @{
                    eventType = 'request-escalated'
                    requestId = $requestId
                    operation = $request.operation
                    reason = 'timeout-expired'
                } -ProjectRoot $ProjectRoot
                
                $escalated += (New-Object -TypeName PSObject -Property $request)
                
                Write-Warning "Review request $requestId has expired and been escalated"
            }
        }
    }
    
    $escalatedCount = @($escalated).Count
    if ($escalatedCount -gt 0) {
        [void](Save-ReviewState -State $state -ProjectRoot $ProjectRoot)
    }
    
    # Ensure we always return an array (PowerShell 5.1 compatible)
    return @($escalated)
}


