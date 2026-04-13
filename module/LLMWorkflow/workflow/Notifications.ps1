#requires -Version 5.1
<#
.SYNOPSIS
    Notification hooks system for LLM Workflow platform.
.DESCRIPTION
    Provides asynchronous notification delivery with support for webhooks,
    command execution, logging, and event hooks. Includes rate limiting,
    retry logic with exponential backoff, and structured JSON payloads.
    
    Notification hooks allow external systems to receive events from the
    LLM Workflow platform in real-time or near real-time.
.NOTES
    File Name      : Notifications.ps1
    Author         : LLM Workflow Team
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Version        : 0.4.0
#>

Set-StrictMode -Version Latest

# Schema version for notification payloads
$script:SchemaVersion = 1

# Default hooks directory
$script:DefaultHooksDirectory = ".llm-workflow/hooks"

# In-memory hook registry (for session-scoped hooks)
$script:HookRegistry = [hashtable]::Synchronized(@{})

# Rate limiting state
$script:RateLimitState = [hashtable]::Synchronized(@{})

# Valid hook types
$script:ValidHookTypes = @('webhook', 'command', 'log', 'event')

# Valid event filters
$script:ValidEventFilters = @('on-success', 'on-failure', 'on-warning', 'on-info', 'on-critical')

# Valid severity levels
$script:ValidSeverities = @('info', 'warning', 'error', 'critical', 'success')

# Valid event types per canonical document
$script:ValidEventTypes = @(
    'pack.build.started',
    'pack.build.completed',
    'pack.build.failed',
    'sync.started',
    'sync.completed',
    'health.degraded',
    'health.critical',
    'compatibility.warning',
    'source.quarantined'
)

<#
.SYNOPSIS
    Registers a new notification hook.
.DESCRIPTION
    Registers a notification endpoint that will receive events matching
    the specified filters. Hooks can be persisted to disk or remain
    session-scoped.
.PARAMETER Name
    Unique name for this hook. Used for identification and removal.
.PARAMETER HookType
    The type of hook: webhook, command, log, or event.
.PARAMETER Target
    The target URL for webhooks, or command path for command hooks.
.PARAMETER EventFilter
    Array of event filters to subscribe to (on-success, on-failure, on-warning, on-info, on-critical).
.PARAMETER EventTypes
    Array of specific event types to subscribe to. If empty, subscribes to all.
.PARAMETER RateLimitSeconds
    Minimum seconds between notifications for this hook. Default: 0 (no limit).
.PARAMETER Authentication
    Hashtable with authentication details (type, token, username, password).
.PARAMETER Headers
    Additional headers for webhook requests.
.PARAMETER TimeoutSeconds
    Timeout for webhook/command execution. Default: 30.
.PARAMETER RetryCount
    Number of retry attempts. Default: 3.
.PARAMETER PassThruStdin
    For command hooks, pass payload via stdin instead of args.
.PARAMETER Persist
    If specified, persists the hook to disk for cross-session use.
.OUTPUTS
    System.Management.Automation.PSCustomObject representing the registered hook.
.EXAMPLE
    PS C:\> Register-NotificationHook -Name "slack-alerts" -HookType webhook -Target "https://hooks.slack.com/..." -EventFilter @("on-failure", "on-critical")
    
    Registers a Slack webhook for failure and critical events.
.EXAMPLE
    PS C:\> Register-NotificationHook -Name "build-script" -HookType command -Target "C:\Scripts\notify.ps1" -EventFilter @("on-success")
    
    Registers a command hook that runs on successful builds.
#>
function Register-NotificationHook {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('webhook', 'command', 'log', 'event')]
        [string]$HookType,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Target,
        
        [Parameter()]
        [ValidateSet('on-success', 'on-failure', 'on-warning', 'on-info', 'on-critical')]
        [string[]]$EventFilter = @('on-failure'),
        
        [Parameter()]
        [ValidateSet('pack.build.started', 'pack.build.completed', 'pack.build.failed', 
                     'sync.started', 'sync.completed', 'health.degraded', 
                     'health.critical', 'compatibility.warning', 'source.quarantined')]
        [string[]]$EventTypes = @(),
        
        [Parameter()]
        [ValidateRange(0, 86400)]
        [int]$RateLimitSeconds = 0,
        
        [Parameter()]
        [hashtable]$Authentication = @{},
        
        [Parameter()]
        [hashtable]$Headers = @{},
        
        [Parameter()]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 30,
        
        [Parameter()]
        [ValidateRange(0, 10)]
        [int]$RetryCount = 3,
        
        [Parameter()]
        [switch]$PassThruStdin,
        
        [Parameter()]
        [switch]$Persist
    )
    
    # Validate webhook URLs
    if ($HookType -eq 'webhook') {
        try {
            $null = [Uri]$Target
        }
        catch {
            throw "Invalid webhook URL: $Target"
        }
    }
    
    # Validate command exists
    if ($HookType -eq 'command') {
        if (-not (Test-Path -LiteralPath $Target)) {
            # Check if it's a command in PATH
            $cmd = Get-Command $Target -ErrorAction SilentlyContinue
            if (-not $cmd) {
                throw "Command not found: $Target"
            }
        }
    }
    
    # Create hook object
    $hook = [ordered]@{
        id              = [Guid]::NewGuid().ToString("N")
        name            = $Name
        hookType        = $HookType
        target          = $Target
        eventFilter     = @($EventFilter)
        eventTypes      = @($EventTypes)
        rateLimitSeconds = $RateLimitSeconds
        authentication  = $Authentication
        headers         = $Headers
        timeoutSeconds  = $TimeoutSeconds
        retryCount      = $RetryCount
        passThruStdin   = $PassThruStdin.IsPresent
        createdAt       = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        enabled         = $true
        persist         = $Persist.IsPresent
    }
    
    $hookObject = [pscustomobject]$hook
    
    # Store in memory registry
    $script:HookRegistry[$Name] = $hookObject
    
    # Persist to disk if requested
    if ($Persist) {
        try {
            $hooksDir = $script:DefaultHooksDirectory
            if (-not (Test-Path -LiteralPath $hooksDir)) {
                New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
            }
            
            $hookPath = Join-Path $hooksDir "$Name.json"
            $hook | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $hookPath -Encoding UTF8
        }
        catch {
            Write-Warning "[Notifications] Failed to persist hook '$Name': $_"
        }
    }
    
    Write-Verbose "[Notifications] Registered hook '$Name' (ID: $($hook.id), Type: $HookType)"
    
    return $hookObject
}

<#
.SYNOPSIS
    Unregisters a notification hook.
.DESCRIPTION
    Removes a previously registered notification hook from both the
    in-memory registry and persisted storage.
.PARAMETER Name
    The name of the hook to unregister.
.PARAMETER Force
    If specified, suppresses confirmation prompt.
.OUTPUTS
    System.Boolean. True if the hook was removed; otherwise false.
.EXAMPLE
    PS C:\> Unregister-NotificationHook -Name "slack-alerts"
    
    Removes the 'slack-alerts' hook.
#>
function Unregister-NotificationHook {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Name,
        
        [Parameter()]
        [switch]$Force
    )
    
    process {
        $removed = $false
        
        # Remove from in-memory registry
        if ($script:HookRegistry.ContainsKey($Name)) {
            if ($Force -or $PSCmdlet.ShouldProcess($Name, "Unregister notification hook")) {
                $null = $script:HookRegistry.Remove($Name)
                $removed = $true
                Write-Verbose "[Notifications] Removed hook '$Name' from registry"
            }
        }
        
        # Remove from persisted storage
        $hookPath = Join-Path $script:DefaultHooksDirectory "$Name.json"
        if (Test-Path -LiteralPath $hookPath) {
            if ($Force -or $PSCmdlet.ShouldProcess($Name, "Remove persisted hook file")) {
                try {
                    Remove-Item -LiteralPath $hookPath -Force
                    $removed = $true
                    Write-Verbose "[Notifications] Removed persisted hook '$Name'"
                }
                catch {
                    Write-Warning "[Notifications] Failed to remove persisted hook '$Name': $_"
                }
            }
        }
        
        if (-not $removed) {
            Write-Verbose "[Notifications] Hook '$Name' not found"
        }
        
        return $removed
    }
}

<#
.SYNOPSIS
    Gets registered notification hooks.
.DESCRIPTION
    Retrieves all registered notification hooks from both the in-memory
    registry and persisted storage. Optionally filters by hook type or name.
.PARAMETER Name
    Specific hook name to retrieve. If not specified, returns all hooks.
.PARAMETER HookType
    Filter by hook type.
.PARAMETER IncludeDisabled
    If specified, includes disabled hooks in the results.
.OUTPUTS
    System.Management.Automation.PSCustomObject[] representing the registered hooks.
.EXAMPLE
    PS C:\> Get-NotificationHooks
    
    Gets all registered hooks.
.EXAMPLE
    PS C:\> Get-NotificationHooks -HookType webhook
    
    Gets only webhook-type hooks.
#>
function Get-NotificationHooks {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [string]$Name = "",
        
        [Parameter()]
        [ValidateSet('webhook', 'command', 'log', 'event')]
        [string]$HookType = "",
        
        [Parameter()]
        [switch]$IncludeDisabled
    )
    
    $hooks = [System.Collections.Generic.List[object]]::new()
    $seenNames = [System.Collections.Generic.HashSet[string]]::new()
    
    # Load persisted hooks first (so memory hooks can override)
    $hooksDir = $script:DefaultHooksDirectory
    if (Test-Path -LiteralPath $hooksDir) {
        $hookFiles = Get-ChildItem -LiteralPath $hooksDir -Filter "*.json" -File
        foreach ($file in $hookFiles) {
            try {
                $hookData = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
                $hookName = $file.BaseName
                
                if (-not $IncludeDisabled -and -not $hookData.enabled) {
                    continue
                }
                
                if (-not [string]::IsNullOrEmpty($Name) -and $hookName -ne $Name) {
                    continue
                }
                
                if (-not [string]::IsNullOrEmpty($HookType) -and $hookData.hookType -ne $HookType) {
                    continue
                }
                
                $hooks.Add($hookData)
                $null = $seenNames.Add($hookName)
            }
            catch {
                Write-Warning "[Notifications] Failed to load hook from $($file.Name): $_"
            }
        }
    }
    
    # Add/override with memory hooks
    foreach ($hookName in $script:HookRegistry.Keys) {
        $hook = $script:HookRegistry[$hookName]
        
        if (-not $IncludeDisabled -and -not $hook.enabled) {
            continue
        }
        
        if (-not [string]::IsNullOrEmpty($Name) -and $hookName -ne $Name) {
            continue
        }
        
        if (-not [string]::IsNullOrEmpty($HookType) -and $hook.hookType -ne $HookType) {
            continue
        }
        
        # Remove existing entry if present
        $existingIndex = -1
        for ($i = 0; $i -lt $hooks.Count; $i++) {
            if ($hooks[$i].name -eq $hookName) {
                $existingIndex = $i
                break
            }
        }
        
        if ($existingIndex -ge 0) {
            $hooks[$existingIndex] = $hook
        }
        else {
            $hooks.Add($hook)
        }
    }
    
    return $hooks.ToArray()
}

<#
.SYNOPSIS
    Sends a notification to all registered hooks.
.DESCRIPTION
    Distributes notifications to all registered hooks that match the
    event type and filter criteria. Delivery is asynchronous and
    non-blocking. Failures are logged but don't fail the operation.
.PARAMETER EventType
    The type of event being notified.
.PARAMETER Message
    The notification message.
.PARAMETER Severity
    The severity level (info, warning, error, critical, success).
.PARAMETER RunId
    The run ID associated with this event. Defaults to current run ID.
.PARAMETER PackId
    The pack ID associated with this event.
.PARAMETER PackVersion
    The pack version associated with this event.
.PARAMETER Context
    Additional context data as a hashtable.
.PARAMETER Async
    If specified (default), notifications are sent asynchronously.
.PARAMETER Hooks
    Optional array of specific hooks to send to. If not specified, uses all registered hooks.
.OUTPUTS
    System.Management.Automation.PSCustomObject with delivery results.
.EXAMPLE
    PS C:\> Send-Notification -EventType "pack.build.completed" -Message "Build successful" -Severity "success" -PackId "rpgmaker-mz"
    
    Sends a build completion notification to all matching hooks.
#>
function Send-Notification {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('pack.build.started', 'pack.build.completed', 'pack.build.failed', 
                     'sync.started', 'sync.completed', 'health.degraded', 
                     'health.critical', 'compatibility.warning', 'source.quarantined')]
        [string]$EventType,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('info', 'warning', 'error', 'critical', 'success')]
        [string]$Severity = "info",
        
        [Parameter()]
        [string]$RunId = "",
        
        [Parameter()]
        [string]$PackId = "",
        
        [Parameter()]
        [string]$PackVersion = "",
        
        [Parameter()]
        [hashtable]$Context = @{},
        
        [Parameter()]
        [switch]$Async = $true,
        
        [Parameter()]
        [array]$Hooks = @()
    )
    
    # Get current run ID if not provided
    if ([string]::IsNullOrEmpty($RunId)) {
        try {
            $runIdCmd = Get-Command Get-CurrentRunId -ErrorAction SilentlyContinue
            if ($runIdCmd) {
                $RunId = & $runIdCmd -ErrorAction SilentlyContinue
            }
        }
        catch {
            $RunId = "unknown"
        }
        if ([string]::IsNullOrEmpty($RunId)) {
            $RunId = "unknown"
        }
    }
    
    # Create payload
    $payload = New-NotificationPayload -EventType $EventType -Message $Message -Severity $Severity `
        -RunId $RunId -PackId $PackId -PackVersion $PackVersion -Context $Context
    
    # Get hooks to notify
    if ($Hooks.Count -eq 0) {
        $Hooks = Get-NotificationHooks -IncludeDisabled:$false
    }
    
    # Filter hooks by event type and severity
    $filteredHooks = @()
    $eventFilter = ConvertTo-EventFilter -Severity $Severity
    
    foreach ($hook in $Hooks) {
        # Check if hook subscribes to this event type (if specific types configured)
        if ($hook.eventTypes -and $hook.eventTypes.Count -gt 0) {
            if ($hook.eventTypes -notcontains $EventType) {
                continue
            }
        }
        
        # Check if hook subscribes to this severity/filter
        if ($hook.eventFilter -and $hook.eventFilter.Count -gt 0) {
            if ($hook.eventFilter -notcontains $eventFilter) {
                continue
            }
        }
        
        # Check rate limiting
        if (Test-RateLimit -HookName $hook.name -RateLimitSeconds $hook.rateLimitSeconds) {
            Write-Verbose "[Notifications] Hook '$($hook.name)' rate limited, skipping"
            continue
        }
        
        $filteredHooks += $hook
    }
    
    $results = @{
        sent        = 0
        failed      = 0
        skipped     = 0
        hooks       = @()
        payload     = $payload
    }
    
    if ($filteredHooks.Count -eq 0) {
        Write-Verbose "[Notifications] No hooks matched for event '$EventType'"
        return [pscustomobject]$results
    }
    
    # Send to each hook
    foreach ($hook in $filteredHooks) {
        $hookResult = @{
            name    = $hook.name
            type    = $hook.hookType
            success = $false
            error   = $null
        }
        
        try {
            if ($Async) {
                # Use runspace pool for async execution
                $runspacePool = [runspacefactory]::CreateRunspacePool(1, 5)
                $runspacePool.Open()
                
                $powershell = [powershell]::Create().AddScript({
                    param($Hook, $Payload)
                    Send-ToHook -Hook $Hook -Payload $Payload
                }).AddArgument($hook).AddArgument($payload)
                
                $powershell.RunspacePool = $runspacePool
                $asyncResult = $powershell.BeginInvoke()
                
                # Don't wait - fire and forget
                $hookResult.success = $true
                $hookResult.async = $true
                
                # Cleanup (best effort)
                $null = Register-ObjectEvent -InputObject $asyncResult.AsyncWaitHandle -EventName "WaitHandle" -Action {
                    $powershell.EndInvoke($asyncResult)
                    $powershell.Dispose()
                    $runspacePool.Close()
                    $runspacePool.Dispose()
                } -ErrorAction SilentlyContinue
            }
            else {
                $sendResult = Send-ToHook -Hook $hook -Payload $payload
                $hookResult.success = $sendResult
                $hookResult.async = $false
            }
            
            if ($hookResult.success) {
                $results.sent++
            }
            else {
                $results.failed++
            }
        }
        catch {
            $hookResult.success = $false
            $hookResult.error = $_.Exception.Message
            $results.failed++
            
            # Fail-safe: log but don't throw
            Write-Verbose "[Notifications] Failed to notify hook '$($hook.name)': $_"
        }
        
        $results.hooks += [pscustomobject]$hookResult
    }
    
    $results.skipped = $Hooks.Count - $filteredHooks.Count
    
    return [pscustomobject]$results
}

<#
.SYNOPSIS
    Invokes a webhook notification.
.DESCRIPTION
    Sends an HTTP POST request to the configured webhook URL with the
    notification payload. Includes retry logic with exponential backoff
    and timeout handling.
.PARAMETER Url
    The webhook URL.
.PARAMETER Payload
    The notification payload object.
.PARAMETER Headers
    Additional headers to include in the request.
.PARAMETER Authentication
    Authentication details (type, token, username, password).
.PARAMETER TimeoutSeconds
    Request timeout in seconds.
.PARAMETER RetryCount
    Number of retry attempts.
.PARAMETER RetryDelaySeconds
    Initial delay between retries (doubles with each attempt).
.OUTPUTS
    System.Boolean. True if the webhook was delivered successfully.
.EXAMPLE
    PS C:\> Invoke-NotificationWebhook -Url "https://hooks.slack.com/..." -Payload $payload
    
    Sends a webhook notification.
#>
function Invoke-NotificationWebhook {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Payload,
        
        [Parameter()]
        [hashtable]$Headers = @{},
        
        [Parameter()]
        [hashtable]$Authentication = @{},
        
        [Parameter()]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 30,
        
        [Parameter()]
        [ValidateRange(0, 10)]
        [int]$RetryCount = 3,
        
        [Parameter()]
        [int]$RetryDelaySeconds = 2
    )
    
    # Prepare headers
    $requestHeaders = @{
        'Content-Type' = 'application/json'
        'User-Agent'   = 'LLM-Workflow-Notifier/0.4.0'
    }
    
    # Add custom headers
    foreach ($key in $Headers.Keys) {
        $requestHeaders[$key] = $Headers[$key]
    }
    
    # Add authentication
    if ($Authentication.Count -gt 0) {
        $authType = $Authentication['type']
        switch ($authType) {
            'bearer' {
                $requestHeaders['Authorization'] = "Bearer $($Authentication['token'])"
            }
            'basic' {
                $creds = "$($Authentication['username']):$($Authentication['password'])"
                $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($creds))
                $requestHeaders['Authorization'] = "Basic $encoded"
            }
            'header' {
                $requestHeaders[$Authentication['headerName']] = $Authentication['token']
            }
        }
    }
    
    $jsonPayload = $Payload | ConvertTo-Json -Depth 10 -Compress
    $attempt = 0
    $lastError = $null
    
    while ($attempt -le $RetryCount) {
        try {
            $response = Invoke-RestMethod -Uri $Url -Method POST `
                -Headers $requestHeaders -Body $jsonPayload `
                -TimeoutSec $TimeoutSeconds -ErrorAction Stop
            
            Write-Verbose "[Notifications] Webhook delivered to $Url (attempt $($attempt + 1))"
            return $true
        }
        catch {
            $lastError = $_
            $attempt++
            
            if ($attempt -le $RetryCount) {
                $delay = $RetryDelaySeconds * [Math]::Pow(2, $attempt - 1)
                Write-Verbose "[Notifications] Webhook attempt $attempt failed, retrying in ${delay}s..."
                Start-Sleep -Seconds $delay
            }
        }
    }
    
    Write-Warning "[Notifications] Webhook delivery failed after $RetryCount retries: $lastError"
    return $false
}

<#
.SYNOPSIS
    Invokes a command notification.
.DESCRIPTION
    Executes the configured command with the notification payload passed
    as JSON. Supports both stdin and argument passing modes.
.PARAMETER Command
    The command to execute.
.PARAMETER Payload
    The notification payload object.
.PARAMETER PassThruStdin
    If specified, passes the JSON payload via stdin instead of as an argument.
.PARAMETER TimeoutSeconds
    Command execution timeout.
.OUTPUTS
    System.Boolean. True if the command executed successfully.
.EXAMPLE
    PS C:\> Invoke-NotificationCommand -Command "C:\Scripts\notify.ps1" -Payload $payload
    
    Executes a notification command.
#>
function Invoke-NotificationCommand {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Payload,
        
        [Parameter()]
        [switch]$PassThruStdin,
        
        [Parameter()]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 30
    )
    
    $jsonPayload = $Payload | ConvertTo-Json -Depth 10 -Compress
    $escapedPayload = $jsonPayload.Replace('"', '\"')
    
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        
        # Determine if command is a file or executable in PATH
        if (Test-Path -LiteralPath $Command) {
            $psi.FileName = $Command
            $psi.WorkingDirectory = Split-Path -Parent $Command
        }
        else {
            $cmd = Get-Command $Command -ErrorAction Stop
            $psi.FileName = $cmd.Source
        }
        
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        
        if ($PassThruStdin) {
            $psi.RedirectStandardInput = $true
            $psi.Arguments = ""
        }
        else {
            # Escape the JSON for command line
            if ($IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6)) {
                $psi.Arguments = '"' + $escapedPayload + '"'
            }
            else {
                $psi.Arguments = $jsonPayload
            }
        }
        
        $process = [System.Diagnostics.Process]::Start($psi)
        
        if ($PassThruStdin) {
            $process.StandardInput.WriteLine($jsonPayload)
            $process.StandardInput.Close()
        }
        
        # Wait with timeout
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        
        if (-not $completed) {
            try {
                $process.Kill()
            }
            catch {
                # Best effort
            }
            throw "Command execution timed out after $TimeoutSeconds seconds"
        }
        
        $exitCode = $process.ExitCode
        $stderr = $process.StandardError.ReadToEnd()
        $stdout = $process.StandardOutput.ReadToEnd()
        
        $process.Dispose()
        
        if ($exitCode -ne 0) {
            throw "Command exited with code $exitCode. Stderr: $stderr"
        }
        
        Write-Verbose "[Notifications] Command executed successfully: $Command"
        return $true
    }
    catch {
        Write-Warning "[Notifications] Command execution failed: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Tests a notification hook configuration.
.DESCRIPTION
    Sends a test notification through the specified hook and validates
    delivery. Reports detailed status information.
.PARAMETER Name
    The name of the hook to test.
.PARAMETER Payload
    Optional custom payload for testing. If not specified, uses a default test payload.
.OUTPUTS
    System.Management.Automation.PSCustomObject with test results.
.EXAMPLE
    PS C:\> Test-NotificationHook -Name "slack-alerts"
    
    Tests the 'slack-alerts' hook with a test notification.
#>
function Test-NotificationHook {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter()]
        [pscustomobject]$Payload = $null
    )
    
    $hook = Get-NotificationHooks -Name $Name
    
    if (-not $hook) {
        throw "Hook not found: $Name"
    }
    
    if ($hook -is [array]) {
        $hook = $hook[0]
    }
    
    # Create test payload if not provided
    if (-not $Payload) {
        $Payload = New-NotificationPayload `
            -EventType "pack.build.completed" `
            -Message "Test notification from LLM Workflow" `
            -Severity "info" `
            -RunId (New-RunId) `
            -PackId "test-pack" `
            -PackVersion "1.0.0-test" `
            -Context @{ test = $true; timestamp = [DateTime]::UtcNow.ToString("O") }
    }
    
    $result = [ordered]@{
        name       = $Name
        hookType   = $hook.hookType
        target     = $hook.target
        success    = $false
        durationMs = 0
        error      = $null
        details    = @{}
    }
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        switch ($hook.hookType) {
            'webhook' {
                $webhookResult = Invoke-NotificationWebhook `
                    -Url $hook.target `
                    -Payload $Payload `
                    -Headers $hook.headers `
                    -Authentication $hook.authentication `
                    -TimeoutSeconds $hook.timeoutSeconds `
                    -RetryCount 0  # No retries for test
                
                $result.success = $webhookResult
                $result.details['httpStatus'] = "Test delivery"
            }
            'command' {
                $cmdResult = Invoke-NotificationCommand `
                    -Command $hook.target `
                    -Payload $Payload `
                    -PassThruStdin:$hook.passThruStdin `
                    -TimeoutSeconds $hook.timeoutSeconds
                
                $result.success = $cmdResult
                $result.details['exitCode'] = if ($cmdResult) { 0 } else { -1 }
            }
            'log' {
                # Log hooks always succeed
                $result.success = $true
                $result.details['logTarget'] = $hook.target
            }
            'event' {
                # Event hooks always succeed (they're in-memory)
                $result.success = $true
                $result.details['eventSource'] = "internal"
            }
        }
    }
    catch {
        $result.success = $false
        $result.error = $_.Exception.Message
    }
    
    $stopwatch.Stop()
    $result.durationMs = $stopwatch.ElapsedMilliseconds
    
    return [pscustomobject]$result
}

<#
.SYNOPSIS
    Creates a standardized notification payload.
.DESCRIPTION
    Creates a notification payload with the standardized schema including
    schema version, event type, timestamp, severity, message, context,
    run ID, and pack information.
.PARAMETER EventType
    The type of event.
.PARAMETER Message
    The notification message.
.PARAMETER Severity
    The severity level.
.PARAMETER RunId
    The run ID.
.PARAMETER PackId
    The pack ID.
.PARAMETER PackVersion
    The pack version.
.PARAMETER Context
    Additional context data.
.OUTPUTS
    System.Management.Automation.PSCustomObject representing the payload.
.EXAMPLE
    PS C:\> New-NotificationPayload -EventType "pack.build.completed" -Message "Done" -Severity "success"
    
    Creates a standardized payload for a build completion event.
#>
function New-NotificationPayload {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('pack.build.started', 'pack.build.completed', 'pack.build.failed', 
                     'sync.started', 'sync.completed', 'health.degraded', 
                     'health.critical', 'compatibility.warning', 'source.quarantined')]
        [string]$EventType,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('info', 'warning', 'error', 'critical', 'success')]
        [string]$Severity = "info",
        
        [Parameter()]
        [string]$RunId = "",
        
        [Parameter()]
        [string]$PackId = "",
        
        [Parameter()]
        [string]$PackVersion = "",
        
        [Parameter()]
        [hashtable]$Context = @{}
    )
    
    # Get current run ID if not provided
    if ([string]::IsNullOrEmpty($RunId)) {
        try {
            $runIdCmd = Get-Command Get-CurrentRunId -ErrorAction SilentlyContinue
            if ($runIdCmd) {
                $RunId = & $runIdCmd -ErrorAction SilentlyContinue
            }
        }
        catch {
            $RunId = "unknown"
        }
        if ([string]::IsNullOrEmpty($RunId)) {
            $RunId = "unknown"
        }
    }
    
    $payload = [ordered]@{
        schemaVersion = $script:SchemaVersion
        eventType     = $EventType
        timestamp     = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        severity      = $Severity
        message       = $Message
        runId         = $RunId
    }
    
    if (-not [string]::IsNullOrEmpty($PackId)) {
        $payload['packId'] = $PackId
    }
    
    if (-not [string]::IsNullOrEmpty($PackVersion)) {
        $payload['packVersion'] = $PackVersion
    }
    
    if ($Context -and $Context.Count -gt 0) {
        $payload['context'] = $Context
    }
    
    return [pscustomobject]$payload
}

#region Helper Functions

<#
.SYNOPSIS
    Internal helper to send notification to a specific hook.
.DESCRIPTION
    Routes the notification to the appropriate handler based on hook type.
#>
function Send-ToHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Hook,
        
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Payload
    )
    
    # Update rate limit state
    if ($Hook.rateLimitSeconds -gt 0) {
        $script:RateLimitState[$Hook.name] = [DateTime]::UtcNow
    }
    
    switch ($Hook.hookType) {
        'webhook' {
            return Invoke-NotificationWebhook `
                -Url $Hook.target `
                -Payload $Payload `
                -Headers $Hook.headers `
                -Authentication $Hook.authentication `
                -TimeoutSeconds $Hook.timeoutSeconds `
                -RetryCount $Hook.retryCount
        }
        'command' {
            return Invoke-NotificationCommand `
                -Command $Hook.target `
                -Payload $Payload `
                -PassThruStdin:$Hook.passThruStdin `
                -TimeoutSeconds $Hook.timeoutSeconds
        }
        'log' {
            return Write-NotificationLog -Target $Hook.target -Payload $Payload
        }
        'event' {
            return Raise-NotificationEvent -Payload $Payload
        }
        default {
            Write-Warning "[Notifications] Unknown hook type: $($Hook.hookType)"
            return $false
        }
    }
}

<#
.SYNOPSIS
    Internal helper to write notification to log.
#>
function Write-NotificationLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target,
        
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Payload
    )
    
    try {
        $logEntry = $Payload | ConvertTo-Json -Depth 10 -Compress
        
        if ([string]::IsNullOrEmpty($Target) -or $Target -eq "default") {
            # Write to default log using structured logging if available
            $logCmd = Get-Command Write-StructuredLog -ErrorAction SilentlyContinue
            if ($logCmd) {
                $entryCmd = Get-Command New-LogEntry -ErrorAction SilentlyContinue
                if ($entryCmd) {
                    $entry = & $entryCmd -Level INFO -Message "[NOTIFICATION] $($Payload.message)" `
                        -RunId $Payload.runId -Metadata @{ notification = $Payload }
                    & $logCmd -Entry $entry
                }
            }
            else {
                # Fallback to simple file logging
                $logPath = Join-Path $script:DefaultHooksDirectory "notifications.log"
                $logEntry | Out-File -LiteralPath $logPath -Append -Encoding UTF8
            }
        }
        else {
            # Write to specific log file
            $logEntry | Out-File -LiteralPath $Target -Append -Encoding UTF8
        }
        
        return $true
    }
    catch {
        Write-Warning "[Notifications] Failed to write to log: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Internal helper to raise notification as PowerShell event.
#>
function Raise-NotificationEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Payload
    )
    
    try {
        $eventName = "LLMWorkflow.Notification.$($Payload.eventType)"
        $eventData = $Payload | ConvertTo-Json -Depth 10
        
        # Store in global event data (session-scoped)
        if (-not $GLOBAL:LLMWorkflowNotificationEvents) {
            $GLOBAL:LLMWorkflowNotificationEvents = [System.Collections.ArrayList]::new()
        }
        
        $null = $GLOBAL:LLMWorkflowNotificationEvents.Add(@{
            timestamp = [DateTime]::UtcNow
            eventType = $Payload.eventType
            data      = $Payload
        })
        
        # Trim to last 100 events
        while ($GLOBAL:LLMWorkflowNotificationEvents.Count -gt 100) {
            $GLOBAL:LLMWorkflowNotificationEvents.RemoveAt(0)
        }
        
        # Also try to create a real PowerShell event if possible
        try {
            New-Event -SourceIdentifier $eventName -MessageData $eventData -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            # Silently continue - the event store above is the primary mechanism
        }
        
        return $true
    }
    catch {
        Write-Warning "[Notifications] Failed to raise event: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Internal helper to check rate limiting.
#>
function Test-RateLimit {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HookName,
        
        [Parameter(Mandatory = $true)]
        [int]$RateLimitSeconds
    )
    
    if ($RateLimitSeconds -le 0) {
        return $false  # No rate limit
    }
    
    $lastSent = $script:RateLimitState[$HookName]
    if (-not $lastSent) {
        return $false  # Never sent before
    }
    
    $elapsed = ([DateTime]::UtcNow - $lastSent).TotalSeconds
    return $elapsed -lt $RateLimitSeconds
}

<#
.SYNOPSIS
    Internal helper to convert severity to event filter.
#>
function ConvertTo-EventFilter {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Severity
    )
    
    switch ($Severity.ToLowerInvariant()) {
        'success'   { return 'on-success' }
        'info'      { return 'on-info' }
        'warning'   { return 'on-warning' }
        'error'     { return 'on-failure' }
        'critical'  { return 'on-critical' }
        default     { return 'on-info' }
    }
}

#endregion

# Note: Export-ModuleMember is handled by the main LLMWorkflow.psm1 module
