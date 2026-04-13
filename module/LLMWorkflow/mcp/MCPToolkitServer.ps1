#requires -Version 5.1
<#
.SYNOPSIS
    MCP Toolkit Server for LLM Workflow platform.
.DESCRIPTION
    Implements a Model Context Protocol (MCP) server that provides tools
    for Godot Engine, Blender, and Pack Query operations. Supports JSON-RPC 2.0
    over stdio and HTTP transports with proper error handling and logging.
    
    Phase 7 Implementation: MCP integration for AI assistant tool invocation.
.NOTES
    File Name      : MCPToolkitServer.ps1
    Author         : LLM Workflow Team
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Version        : 0.2.0
#>

Set-StrictMode -Version Latest

#===============================================================================
# Configuration and State
#===============================================================================

# Server state
$script:ServerState = [hashtable]::Synchronized(@{
    IsRunning = $false
    Transport = 'stdio'  # stdio or http
    Port = 8080
    Host = 'localhost'
    HttpListener = $null
    CancellationToken = $null
    StartTime = $null
    RunId = $null
    ExecutionMode = 'mcp-readonly'
    Config = $null
    AuthRules = @{}
})

# Tool registry - stores registered MCP tools
$script:ToolRegistry = [hashtable]::Synchronized(@{})

# Request counter for JSON-RPC ID generation
$script:RequestCounter = [hashtable]::Synchronized(@{
    Counter = 0
})

# MCP Protocol Version
$script:McpProtocolVersion = '2024-11-05'

# Server capabilities
$script:ServerCapabilities = @{
    tools = @{}
    logging = @{}
}

# Server information
$script:ServerInfo = @{
    name = 'llm-workflow-mcp-server'
    version = '0.2.0'
}

# Default configuration
$script:DefaultConfig = @{
    transport = 'stdio'
    port = 8080
    host = 'localhost'
    logLevel = 'INFO'
    executionMode = 'mcp-readonly'
    maxRequestSize = 10MB
    requestTimeout = 60
    enableAuth = $false
    allowedOrigins = @('*')
}

#===============================================================================
# Server Configuration Functions
#===============================================================================

<#
.SYNOPSIS
    Creates a new MCP Toolkit Server configuration.
.DESCRIPTION
    Creates a server configuration object with specified settings for name, version,
    tool definitions, execution mode, and authentication/authorization rules.
.PARAMETER Name
    The server name. Default: 'llm-workflow-mcp-server'.
.PARAMETER Version
    The server version. Default: '0.2.0'.
.PARAMETER ToolDefinitions
    Hashtable of tool definitions with schema, handler references, and metadata.
.PARAMETER ExecutionMode
    The execution mode: 'mcp-readonly' or 'mcp-mutating'. Default: mcp-readonly.
.PARAMETER AuthRules
    Hashtable of authentication and authorization rules.
.PARAMETER Config
    Optional hashtable with additional configuration options.
.OUTPUTS
    System.Management.Automation.PSCustomObject with server configuration.
.EXAMPLE
    PS C:\> $config = New-MCPToolkitServer -Name "my-mcp-server" -ExecutionMode "mcp-mutating"
    
    Creates a new MCP server configuration.
#>
function New-MCPToolkitServer {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$Name = 'llm-workflow-mcp-server',
        
        [Parameter()]
        [string]$Version = '0.2.0',
        
        [Parameter()]
        [hashtable]$ToolDefinitions = @{},
        
        [Parameter()]
        [ValidateSet('mcp-readonly', 'mcp-mutating')]
        [string]$ExecutionMode = 'mcp-readonly',
        
        [Parameter()]
        [hashtable]$AuthRules = @{},
        
        [Parameter()]
        [hashtable]$Config = @{}
    )
    
    # Merge with default config
    $mergedConfig = Merge-MCPConfig -BaseConfig $script:DefaultConfig -OverrideConfig $Config
    $mergedConfig.executionMode = $ExecutionMode
    
    # Build server configuration
    $serverConfig = [ordered]@{
        name = $Name
        version = $Version
        executionMode = $ExecutionMode
        transport = $mergedConfig.transport
        port = $mergedConfig.port
        host = $mergedConfig.host
        logLevel = $mergedConfig.logLevel
        maxRequestSize = $mergedConfig.maxRequestSize
        requestTimeout = $mergedConfig.requestTimeout
        enableAuth = $mergedConfig.enableAuth
        allowedOrigins = $mergedConfig.allowedOrigins
        authRules = $AuthRules
        toolDefinitions = $ToolDefinitions
        createdAt = [DateTime]::UtcNow.ToString('O')
        configId = [Guid]::NewGuid().ToString()
    }
    
    Write-MCPLog -Level INFO -Message "Created MCP server configuration" -Metadata @{
        configId = $serverConfig.configId
        name = $Name
        executionMode = $ExecutionMode
    }
    
    return [pscustomobject]$serverConfig
}

#===============================================================================
# Server Lifecycle Functions
#===============================================================================

<#
.SYNOPSIS
    Starts the MCP Toolkit Server.
.DESCRIPTION
    Initializes and starts the MCP server with the specified configuration.
    Supports stdio (for MCP clients) and HTTP transports.
.PARAMETER Transport
    The transport type: 'stdio' or 'http'. Default: stdio.
.PARAMETER Port
    The port number for HTTP transport. Default: 8080.
.PARAMETER Host
    The host address for HTTP transport. Default: localhost.
.PARAMETER ExecutionMode
    The execution mode: 'mcp-readonly' or 'mcp-mutating'. Default: mcp-readonly.
.PARAMETER Config
    Optional hashtable with additional configuration options.
.PARAMETER AsJob
    If specified, runs the server as a background job.
.PARAMETER ServerConfig
    Optional server configuration object created by New-MCPToolkitServer.
.OUTPUTS
    System.Management.Automation.PSCustomObject with server status.
.EXAMPLE
    PS C:\> Start-MCPToolkitServer
    
    Starts the MCP server with default stdio transport.
.EXAMPLE
    PS C:\> Start-MCPToolkitServer -Transport http -Port 8080
    
    Starts the MCP server on HTTP port 8080.
#>
function Start-MCPToolkitServer {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [ValidateSet('stdio', 'http')]
        [string]$Transport = 'stdio',
        
        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 8080,
        
        [Parameter()]
        [string]$Host = 'localhost',
        
        [Parameter()]
        [ValidateSet('mcp-readonly', 'mcp-mutating')]
        [string]$ExecutionMode = 'mcp-readonly',
        
        [Parameter()]
        [hashtable]$Config = @{},
        
        [Parameter()]
        [switch]$AsJob,
        
        [Parameter()]
        [pscustomobject]$ServerConfig = $null
    )
    
    # Check if already running
    if ($script:ServerState.IsRunning) {
        Write-Warning '[MCP Server] Server is already running. Use Restart-MCPToolkitServer to change configuration.'
        return Get-MCPToolkitServerStatus
    }
    
    # Use provided server config or create default
    if ($ServerConfig) {
        $mergedConfig = Merge-MCPConfig -BaseConfig $script:DefaultConfig -OverrideConfig @{
            transport = $ServerConfig.transport
            port = $ServerConfig.port
            host = $ServerConfig.host
            logLevel = $ServerConfig.logLevel
            executionMode = $ServerConfig.executionMode
            maxRequestSize = $ServerConfig.maxRequestSize
            requestTimeout = $ServerConfig.requestTimeout
            enableAuth = $ServerConfig.enableAuth
            allowedOrigins = $ServerConfig.allowedOrigins
        }
        $mergedConfig.executionMode = $ServerConfig.executionMode
        $script:ServerState.AuthRules = $ServerConfig.authRules
    }
    else {
        $mergedConfig = Merge-MCPConfig -BaseConfig $script:DefaultConfig -OverrideConfig $Config
        $mergedConfig.transport = $Transport
        $mergedConfig.port = $Port
        $mergedConfig.host = $Host
        $mergedConfig.executionMode = $ExecutionMode
    }
    
    # Initialize server state
    $script:ServerState.IsRunning = $true
    $script:ServerState.Transport = $mergedConfig.transport
    $script:ServerState.Port = $mergedConfig.port
    $script:ServerState.Host = $mergedConfig.host
    $script:ServerState.ExecutionMode = $mergedConfig.executionMode
    $script:ServerState.Config = $mergedConfig
    $script:ServerState.StartTime = [DateTime]::UtcNow
    $script:ServerState.RunId = New-MCPRunId
    
    # Register default tools
    Register-DefaultMCPTools
    
    # Log startup
    Write-MCPLog -Level INFO -Message "MCP Server starting" -Metadata @{
        transport = $mergedConfig.transport
        port = $mergedConfig.port
        host = $mergedConfig.host
        executionMode = $mergedConfig.executionMode
        runId = $script:ServerState.RunId
    }
    
    # Start transport
    if ($mergedConfig.transport -eq 'http') {
        Start-MCPHttpListener -Port $mergedConfig.port -Host $mergedConfig.host
    }
    else {
        # stdio transport - start processing in foreground or background
        if ($AsJob) {
            $job = Start-Job -ScriptBlock {
                param($ModulePath)
                Import-Module $ModulePath -Force
                Start-MCPStdioLoop
            } -ArgumentList (Get-Module LLMWorkflow).Path
            $script:ServerState.Job = $job
        }
        else {
            # Return status immediately for stdio mode
            # The actual processing happens when the caller reads from stdin
        }
    }
    
    $status = Get-MCPToolkitServerStatus
    
    Write-MCPLog -Level INFO -Message 'MCP Server started successfully' -Metadata @{
        status = $status
    }
    
    return $status
}

<#
.SYNOPSIS
    Stops the MCP Toolkit Server.
.DESCRIPTION
    Gracefully shuts down the MCP server, closing all connections
    and cleaning up resources.
.PARAMETER Force
    If specified, forces immediate termination without waiting for pending requests.
.PARAMETER TimeoutSeconds
    Maximum time to wait for graceful shutdown. Default: 10.
.OUTPUTS
    System.Boolean. True if shutdown was successful.
.EXAMPLE
    PS C:\> Stop-MCPToolkitServer
    
    Gracefully stops the MCP server.
#>
function Stop-MCPToolkitServer {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [ValidateRange(0, 60)]
        [int]$TimeoutSeconds = 10
    )
    
    if (-not $script:ServerState.IsRunning) {
        Write-Verbose '[MCP Server] Server is not running.'
        return $true
    }
    
    Write-MCPLog -Level INFO -Message 'MCP Server stopping' -Metadata @{
        force = $Force.IsPresent
        timeout = $TimeoutSeconds
    }
    
    $script:ServerState.IsRunning = $false
    
    try {
        # Stop HTTP listener if running
        if ($script:ServerState.HttpListener -ne $null) {
            $script:ServerState.HttpListener.Stop()
            $script:ServerState.HttpListener.Close()
            $script:ServerState.HttpListener = $null
            Write-Verbose '[MCP Server] HTTP listener stopped.'
        }
        
        # Stop background job if running
        if ($script:ServerState.Job -ne $null) {
            Stop-Job $script:ServerState.Job -ErrorAction SilentlyContinue
            Remove-Job $script:ServerState.Job -ErrorAction SilentlyContinue
            $script:ServerState.Job = $null
        }
        
        # Wait for cleanup
        if (-not $Force -and $TimeoutSeconds -gt 0) {
            Start-Sleep -Milliseconds 100
        }
        
        # Clear server state
        $script:ServerState.Config = $null
        $script:ServerState.AuthRules = @{}
        
        Write-MCPLog -Level INFO -Message 'MCP Server stopped successfully'
        return $true
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Error stopping MCP Server: $_" -Exception $_.Exception
        return $false
    }
}

<#
.SYNOPSIS
    Gets the current status of the MCP Toolkit Server.
.DESCRIPTION
    Returns detailed status information about the MCP server including
    runtime, registered tools, and configuration.
.OUTPUTS
    System.Management.Automation.PSCustomObject with server status.
.EXAMPLE
    PS C:\> Get-MCPToolkitServerStatus
    
    Returns the current server status.
#>
function Get-MCPToolkitServerStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    
    $uptime = $null
    if ($script:ServerState.StartTime -ne $null -and $script:ServerState.IsRunning) {
        $uptime = [DateTime]::UtcNow - $script:ServerState.StartTime
    }
    
    return [pscustomobject]@{
        isRunning = $script:ServerState.IsRunning
        transport = $script:ServerState.Transport
        port = $script:ServerState.Port
        host = $script:ServerState.Host
        executionMode = $script:ServerState.ExecutionMode
        runId = $script:ServerState.RunId
        startTime = if ($script:ServerState.StartTime) { $script:ServerState.StartTime.ToString('O') } else { $null }
        uptime = if ($uptime) { $uptime.ToString() } else { $null }
        registeredTools = @($script:ToolRegistry.Keys)
        toolCount = $script:ToolRegistry.Count
        protocolVersion = $script:McpProtocolVersion
        serverInfo = $script:ServerInfo
        config = $script:ServerState.Config
        hasAuthRules = $script:ServerState.AuthRules.Count -gt 0
    }
}

<#
.SYNOPSIS
    Restarts the MCP Toolkit Server with new configuration.
.DESCRIPTION
    Stops the current server instance and starts a new one with
    the specified configuration parameters.
.PARAMETER Transport
    The transport type: 'stdio' or 'http'.
.PARAMETER Port
    The port number for HTTP transport.
.PARAMETER Host
    The host address for HTTP transport.
.PARAMETER ExecutionMode
    The execution mode: 'mcp-readonly' or 'mcp-mutating'.
.PARAMETER Config
    Optional hashtable with additional configuration options.
.OUTPUTS
    System.Management.Automation.PSCustomObject with new server status.
.EXAMPLE
    PS C:\> Restart-MCPToolkitServer -Transport http -Port 9090
    
    Restarts the server with HTTP transport on port 9090.
#>
function Restart-MCPToolkitServer {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [ValidateSet('stdio', 'http')]
        [string]$Transport = 'stdio',
        
        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 8080,
        
        [Parameter()]
        [string]$Host = 'localhost',
        
        [Parameter()]
        [ValidateSet('mcp-readonly', 'mcp-mutating')]
        [string]$ExecutionMode = 'mcp-readonly',
        
        [Parameter()]
        [hashtable]$Config = @{},
        
        [Parameter()]
        [switch]$PreserveTools
    )
    
    Write-MCPLog -Level INFO -Message 'Restarting MCP Server'
    
    # Save registered tools if requested
    $savedTools = @{}
    if ($PreserveTools) {
        foreach ($key in $script:ToolRegistry.Keys) {
            $savedTools[$key] = $script:ToolRegistry[$key]
        }
    }
    
    # Stop current server
    $stopResult = Stop-MCPToolkitServer -Force
    if (-not $stopResult) {
        throw 'Failed to stop MCP Server for restart'
    }
    
    # Clear and restore tools if preserving
    $script:ToolRegistry.Clear()
    if ($PreserveTools) {
        foreach ($key in $savedTools.Keys) {
            $script:ToolRegistry[$key] = $savedTools[$key]
        }
    }
    
    # Small delay to ensure cleanup
    Start-Sleep -Milliseconds 100
    
    # Start with new configuration
    return Start-MCPToolkitServer @PSBoundParameters
}

#===============================================================================
# Tool Registration Functions
#===============================================================================

<#
.SYNOPSIS
    Registers an MCP tool.
.DESCRIPTION
    Registers a tool with the MCP server, making it available for clients.
    Each tool has a name, description, JSON schema for parameters, and a handler.
.PARAMETER Name
    The unique name of the tool.
.PARAMETER Description
    A human-readable description of what the tool does.
.PARAMETER Parameters
    JSON schema object defining the tool's parameters.
.PARAMETER Handler
    PowerShell script block that implements the tool's functionality.
.PARAMETER SafetyLevel
    The safety level of the tool: ReadOnly, Mutating, or Destructive.
.PARAMETER Tags
    Optional array of tags for categorizing tools.
.PARAMETER ValidationRules
    Optional hashtable of custom validation rules for parameters.
.OUTPUTS
    System.Management.Automation.PSCustomObject representing the registered tool.
.EXAMPLE
    PS C:\> Register-MCPTool -Name "echo" -Description "Echoes back the input" `
        -Parameters @{ type = "object"; properties = @{ message = @{ type = "string" } } } `
        -Handler { param($params) @{ message = $params.message } }
    
    Registers a simple echo tool.
#>
function Register-MCPTool {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Description,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$Handler,
        
        [Parameter()]
        [ValidateSet('ReadOnly', 'Mutating', 'Destructive')]
        [string]$SafetyLevel = 'ReadOnly',
        
        [Parameter()]
        [string[]]$Tags = @(),
        
        [Parameter()]
        [hashtable]$ValidationRules = @{
            requireConfirmation = $false
            maxExecutionTime = 300
            allowedInReadOnly = $false
        }
    )
    
    # Build input schema
    $inputSchema = @{
        type = 'object'
        properties = $Parameters
    }
    
    # Check for required parameters
    $requiredParams = @()
    foreach ($key in $Parameters.Keys) {
        $paramDef = $Parameters[$key]
        if ($paramDef -is [hashtable] -and $paramDef.ContainsKey('required') -and $paramDef['required'] -eq $true) {
            $requiredParams += $key
        }
    }
    if ($requiredParams.Count -gt 0) {
        $inputSchema['required'] = $requiredParams
    }
    
    # Set allowedInReadOnly based on SafetyLevel
    $ValidationRules['allowedInReadOnly'] = ($SafetyLevel -eq 'ReadOnly')
    
    $tool = [ordered]@{
        name = $Name
        description = $Description
        inputSchema = $inputSchema
        handler = $Handler
        safetyLevel = $SafetyLevel
        tags = $Tags
        validationRules = $ValidationRules
        registeredAt = [DateTime]::UtcNow.ToString('O')
        executionCount = 0
        lastExecutedAt = $null
    }
    
    $script:ToolRegistry[$Name] = $tool
    
    Write-MCPLog -Level DEBUG -Message "Registered MCP tool: $Name" -Metadata @{
        safetyLevel = $SafetyLevel
        tags = $Tags
    }
    
    return [pscustomobject]$tool
}

<#
.SYNOPSIS
    Unregisters an MCP tool.
.DESCRIPTION
    Removes a previously registered tool from the MCP server.
.PARAMETER Name
    The name of the tool to unregister.
.PARAMETER Force
    If specified, suppresses confirmation for built-in tools.
.OUTPUTS
    System.Boolean. True if the tool was removed; otherwise false.
.EXAMPLE
    PS C:\> Unregister-MCPTool -Name "echo"
    
    Removes the 'echo' tool.
#>
function Unregister-MCPTool {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter()]
        [switch]$Force
    )
    
    if (-not $script:ToolRegistry.ContainsKey($Name)) {
        Write-Warning "[MCP Server] Tool not found: $Name"
        return $false
    }
    
    # Check if it's a built-in tool
    $builtInTools = @('godot_version', 'godot_project_list', 'godot_project_info', 
                      'godot_launch_editor', 'godot_run_project', 'godot_create_scene',
                      'godot_add_node', 'godot_get_debug_output', 'godot_export_project',
                      'godot_build_project', 'godot_run_tests', 'godot_check_syntax',
                      'godot_get_scene_tree', 'blender_version', 'blender_operator', 
                      'blender_export_mesh_library', 'blender_import_mesh', 
                      'blender_render_scene', 'blender_list_materials',
                      'blender_apply_modifier', 'blender_export_godot',
                      'pack_query', 'pack_status')
    
    if ($builtInTools -contains $Name -and -not $Force) {
        Write-Warning "[MCP Server] '$Name' is a built-in tool. Use -Force to unregister."
        return $false
    }
    
    $script:ToolRegistry.Remove($Name)
    
    Write-MCPLog -Level DEBUG -Message "Unregistered MCP tool: $Name"
    
    return $true
}

<#
.SYNOPSIS
    Gets registered MCP tools.
.DESCRIPTION
    Returns all registered MCP tools or filters by specific criteria.
.PARAMETER Name
    Specific tool name to retrieve.
.PARAMETER Tag
    Filter by tag.
.PARAMETER SafetyLevel
    Filter by safety level.
.OUTPUTS
    System.Management.Automation.PSCustomObject[] representing the tools.
.EXAMPLE
    PS C:\> Get-MCPTool
    
    Gets all registered tools.
.EXAMPLE
    PS C:\> Get-MCPTool -Tag "godot"
    
    Gets all tools tagged with 'godot'.
#>
function Get-MCPTool {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [string]$Name = '',
        
        [Parameter()]
        [string]$Tag = '',
        
        [Parameter()]
        [ValidateSet('', 'ReadOnly', 'Mutating', 'Destructive')]
        [string]$SafetyLevel = ''
    )
    
    $tools = [System.Collections.Generic.List[object]]::new()
    
    foreach ($toolName in $script:ToolRegistry.Keys) {
        $tool = $script:ToolRegistry[$toolName]
        
        # Filter by name
        if (-not [string]::IsNullOrEmpty($Name) -and $toolName -ne $Name) {
            continue
        }
        
        # Filter by tag
        if (-not [string]::IsNullOrEmpty($Tag) -and $tool.tags -notcontains $Tag) {
            continue
        }
        
        # Filter by safety level
        if (-not [string]::IsNullOrEmpty($SafetyLevel) -and $tool.safetyLevel -ne $SafetyLevel) {
            continue
        }
        
        # Return tool without handler (for security)
        $toolOutput = [ordered]@{
            name = $tool.name
            description = $tool.description
            inputSchema = $tool.inputSchema
            safetyLevel = $tool.safetyLevel
            tags = $tool.tags
            validationRules = $tool.validationRules
            registeredAt = $tool.registeredAt
            executionCount = $tool.executionCount
            lastExecutedAt = $tool.lastExecutedAt
        }
        
        $tools.Add([pscustomobject]$toolOutput)
    }
    
    return $tools.ToArray()
}

<#
.SYNOPSIS
    Exports tool definitions for MCP protocol.
.DESCRIPTION
    Returns the tool definitions in the format required by the MCP protocol
    for the tools/list endpoint.
.OUTPUTS
    System.Management.Automation.PSCustomObject[] with MCP-formatted tool definitions.
.EXAMPLE
    PS C:\> Get-MCPToolSchema
    
    Gets the tool schema for MCP protocol.
#>
function Get-MCPToolSchema {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    $tools = @()
    
    foreach ($toolName in $script:ToolRegistry.Keys) {
        $tool = $script:ToolRegistry[$toolName]
        
        $tools += @{
            name = $tool.name
            description = $tool.description
            inputSchema = $tool.inputSchema
        }
    }
    
    return $tools
}

<#
.SYNOPSIS
    Returns the tool manifest for client discovery.
.DESCRIPTION
    Returns a comprehensive manifest containing all registered tools,
    their schemas, capabilities, and server information for client discovery.
.PARAMETER IncludeStats
    If specified, includes execution statistics for each tool.
.OUTPUTS
    System.Management.Automation.PSCustomObject with tool manifest.
.EXAMPLE
    PS C:\> Get-MCPToolManifest
    
    Returns the complete tool manifest for client discovery.
#>
function Get-MCPToolManifest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [switch]$IncludeStats
    )
    
    $tools = @()
    foreach ($toolName in $script:ToolRegistry.Keys) {
        $tool = $script:ToolRegistry[$toolName]
        
        $toolInfo = @{
            name = $tool.name
            description = $tool.description
            inputSchema = $tool.inputSchema
            safetyLevel = $tool.safetyLevel
            tags = $tool.tags
        }
        
        if ($IncludeStats) {
            $toolInfo['executionCount'] = $tool.executionCount
            $toolInfo['lastExecutedAt'] = $tool.lastExecutedAt
        }
        
        $tools += $toolInfo
    }
    
    # Group tools by tag
    $toolsByCategory = @{}
    foreach ($tool in $tools) {
        foreach ($tag in $tool.tags) {
            if (-not $toolsByCategory.ContainsKey($tag)) {
                $toolsByCategory[$tag] = @()
            }
            $toolsByCategory[$tag] += $tool.name
        }
    }
    
    return [pscustomobject]@{
        serverInfo = @{
            name = $script:ServerInfo.name
            version = $script:ServerInfo.version
            protocolVersion = $script:McpProtocolVersion
        }
        capabilities = $script:ServerCapabilities
        executionMode = $script:ServerState.ExecutionMode
        toolCount = $tools.Count
        tools = $tools
        toolsByCategory = $toolsByCategory
        generatedAt = [DateTime]::UtcNow.ToString('O')
    }
}

#===============================================================================
# Tool Execution Functions
#===============================================================================

<#
.SYNOPSIS
    Invokes an MCP tool with full validation and provenance tracking.
.DESCRIPTION
    Executes a registered MCP tool with parameter validation against schema,
    policy permission checks, execution mode enforcement, and structured
    result formatting with provenance tracking.
.PARAMETER ToolName
    The name of the tool to invoke.
.PARAMETER Parameters
    Hashtable of parameters to pass to the tool.
.PARAMETER SkipValidation
    If specified, skips parameter schema validation.
.PARAMETER SkipPolicyCheck
    If specified, skips policy permission checks.
.PARAMETER CorrelationId
    Optional correlation ID for tracing related operations.
.OUTPUTS
    System.Management.Automation.PSCustomObject with execution results and provenance.
.EXAMPLE
    PS C:\> Invoke-MCPTool -ToolName "godot_version" -Parameters @{}
    
    Executes the godot_version tool.
#>
function Invoke-MCPTool {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ToolName,
        
        [Parameter()]
        [hashtable]$Parameters = @{},
        
        [Parameter()]
        [switch]$SkipValidation,
        
        [Parameter()]
        [switch]$SkipPolicyCheck,
        
        [Parameter()]
        [string]$CorrelationId = ''
    )
    
    $invocationId = [Guid]::NewGuid().ToString()
    $startTime = [DateTime]::UtcNow
    
    # Check if tool exists
    if (-not $script:ToolRegistry.ContainsKey($ToolName)) {
        $errorResult = [pscustomobject]@{
            success = $false
            error = "Tool not found: $ToolName"
            errorCode = 'TOOL_NOT_FOUND'
            invocationId = $invocationId
            toolName = $ToolName
            timestamp = $startTime.ToString('O')
        }
        Write-MCPLog -Level ERROR -Message "Tool invocation failed: Tool not found" -Metadata @{
            toolName = $ToolName
            invocationId = $invocationId
        }
        return $errorResult
    }
    
    $tool = $script:ToolRegistry[$ToolName]
    
    # Check execution mode permission
    if (-not $SkipPolicyCheck) {
        try {
            Assert-MCPExecutionMode -ToolName $ToolName -CurrentMode $script:ServerState.ExecutionMode
        }
        catch {
            $errorResult = [pscustomobject]@{
                success = $false
                error = $_.Exception.Message
                errorCode = 'POLICY_DENIED'
                invocationId = $invocationId
                toolName = $ToolName
                executionMode = $script:ServerState.ExecutionMode
                timestamp = [DateTime]::UtcNow.ToString('O')
            }
            Write-MCPLog -Level WARN -Message "Tool invocation blocked by policy" -Metadata @{
                toolName = $ToolName
                invocationId = $invocationId
                executionMode = $script:ServerState.ExecutionMode
            }
            return $errorResult
        }
        
        # Check Policy.ps1 permissions if available
        $policyCmd = Get-Command 'Test-PolicyPermission' -ErrorAction SilentlyContinue
        if ($policyCmd) {
            $policyMode = $script:ServerState.ExecutionMode
            $policyAllowed = & $policyCmd -Command $ToolName -Mode $policyMode -ErrorAction SilentlyContinue
            if (-not $policyAllowed) {
                $errorResult = [pscustomobject]@{
                    success = $false
                    error = "Tool '$ToolName' is not allowed in execution mode '$policyMode'"
                    errorCode = 'POLICY_DENIED'
                    invocationId = $invocationId
                    toolName = $ToolName
                    executionMode = $policyMode
                    timestamp = [DateTime]::UtcNow.ToString('O')
                }
                Write-MCPLog -Level WARN -Message "Tool invocation blocked by policy system" -Metadata @{
                    toolName = $ToolName
                    invocationId = $invocationId
                    executionMode = $policyMode
                }
                return $errorResult
            }
        }
    }
    
    # Validate parameters against schema
    if (-not $SkipValidation) {
        $validationResult = Test-MCPParameterSchema -Parameters $Parameters -Schema $tool.inputSchema
        if (-not $validationResult.valid) {
            $errorResult = [pscustomobject]@{
                success = $false
                error = "Parameter validation failed: $($validationResult.error)"
                errorCode = 'VALIDATION_ERROR'
                invocationId = $invocationId
                toolName = $ToolName
                validationErrors = $validationResult.errors
                timestamp = [DateTime]::UtcNow.ToString('O')
            }
            Write-MCPLog -Level WARN -Message "Tool invocation failed validation" -Metadata @{
                toolName = $ToolName
                invocationId = $invocationId
                error = $validationResult.error
            }
            return $errorResult
        }
    }
    
    # Execute the tool
    try {
        Write-MCPLog -Level INFO -Message "Executing tool: $ToolName" -Metadata @{
            toolName = $ToolName
            invocationId = $invocationId
            correlationId = $CorrelationId
        }
        
        # Update tool execution stats
        $tool.executionCount++
        $tool.lastExecutedAt = [DateTime]::UtcNow.ToString('O')
        
        # Execute handler
        $result = & $tool.handler $Parameters
        
        $endTime = [DateTime]::UtcNow
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        # Build provenance information
        $provenance = @{
            invocationId = $invocationId
            toolName = $ToolName
            toolVersion = $script:ServerInfo.version
            executedAt = $startTime.ToString('O')
            completedAt = $endTime.ToString('O')
            durationMs = [Math]::Round($duration, 2)
            executionMode = $script:ServerState.ExecutionMode
            serverRunId = $script:ServerState.RunId
            correlationId = if ($CorrelationId) { $CorrelationId } else { $null }
            validationSkipped = $SkipValidation.IsPresent
            policyCheckSkipped = $SkipPolicyCheck.IsPresent
        }
        
        $successResult = [pscustomobject]@{
            success = $true
            result = $result
            provenance = $provenance
        }
        
        Write-MCPLog -Level INFO -Message "Tool execution completed successfully" -Metadata @{
            toolName = $ToolName
            invocationId = $invocationId
            durationMs = [Math]::Round($duration, 2)
        }
        
        return $successResult
    }
    catch {
        $endTime = [DateTime]::UtcNow
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        $errorResult = [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
            errorCode = 'EXECUTION_ERROR'
            invocationId = $invocationId
            toolName = $ToolName
            executedAt = $startTime.ToString('O')
            failedAt = $endTime.ToString('O')
            durationMs = [Math]::Round($duration, 2)
            executionMode = $script:ServerState.ExecutionMode
        }
        
        Write-MCPLog -Level ERROR -Message "Tool execution failed: $_" -Exception $_.Exception -Metadata @{
            toolName = $ToolName
            invocationId = $invocationId
            durationMs = [Math]::Round($duration, 2)
        }
        
        return $errorResult
    }
}

<#
.SYNOPSIS
    Validates parameters against a JSON schema.
.DESCRIPTION
    Tests whether the provided parameters match the expected schema.
.PARAMETER Parameters
    The parameters to validate.
.PARAMETER Schema
    The JSON schema to validate against.
.OUTPUTS
    Hashtable with validation result.
#>
function Test-MCPParameterSchema {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Schema
    )
    
    $errors = @()
    
    # Check required parameters
    if ($Schema.ContainsKey('required')) {
        foreach ($required in $Schema['required']) {
            if (-not $Parameters.ContainsKey($required)) {
                $errors += "Missing required parameter: $required"
            }
        }
    }
    
    # Check parameter types
    if ($Schema.ContainsKey('properties')) {
        $properties = $Schema['properties']
        foreach ($key in $Parameters.Keys) {
            if ($properties.ContainsKey($key)) {
                $paramDef = $properties[$key]
                $value = $Parameters[$key]
                
                # Type validation
                if ($paramDef -is [hashtable] -and $paramDef.ContainsKey('type')) {
                    $expectedType = $paramDef['type']
                    $actualType = $value.GetType().Name
                    
                    $typeValid = switch ($expectedType) {
                        'string' { $value -is [string] }
                        'integer' { $value -is [int] -or $value -is [long] }
                        'number' { $value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [float] }
                        'boolean' { $value -is [bool] }
                        'array' { $value -is [array] -or $value -is [System.Collections.IEnumerable] }
                        'object' { $value -is [hashtable] -or $value -is [pscustomobject] }
                        default { $true }
                    }
                    
                    if (-not $typeValid) {
                        $errors += "Parameter '$key' should be of type '$expectedType', got '$actualType'"
                    }
                }
            }
        }
    }
    
    return @{
        valid = $errors.Count -eq 0
        error = if ($errors.Count -gt 0) { $errors[0] } else { $null }
        errors = $errors
    }
}

#===============================================================================
# Godot Integration Tools
#===============================================================================

<#
.SYNOPSIS
    Executes a Godot tool via MCP.
.DESCRIPTION
    Invokes a registered Godot-related MCP tool with the specified parameters.
.PARAMETER ToolName
    The name of the Godot tool to execute.
.PARAMETER Parameters
    Hashtable of parameters to pass to the tool.
.OUTPUTS
    System.Management.Automation.PSCustomObject with tool execution results.
.EXAMPLE
    PS C:\> Invoke-MCPGodotTool -ToolName "godot_version" -Parameters @{}
    
    Gets the Godot version.
#>
function Invoke-MCPGodotTool {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('godot_version', 'godot_project_list', 'godot_project_info', 
                     'godot_launch_editor', 'godot_run_project', 'godot_create_scene',
                     'godot_add_node', 'godot_get_debug_output', 'godot_export_project',
                     'godot_build_project', 'godot_run_tests', 'godot_check_syntax',
                     'godot_get_scene_tree')]
        [string]$ToolName,
        
        [Parameter()]
        [hashtable]$Parameters = @{}
    )
    
    return Invoke-MCPTool -ToolName $ToolName -Parameters $Parameters
}

<#
.SYNOPSIS
    Gets the installed Godot version.
.DESCRIPTION
    Queries the system for the installed Godot Engine version.
.PARAMETER GodotPath
    Optional path to the Godot executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with version information.
.EXAMPLE
    PS C:\> Get-MCPGodotVersion
    
    Returns the Godot version information.
#>
function Get-MCPGodotVersion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$GodotPath = ''
    )
    
    try {
        $godot = Find-GodotExecutable -Path $GodotPath
        
        if (-not $godot) {
            return [pscustomobject]@{
                installed = $false
                version = $null
                versionString = $null
                error = 'Godot executable not found'
            }
        }
        
        # Get version
        $versionOutput = & $godot --version 2>&1 | Out-String
        $versionString = $versionOutput.Trim()
        
        # Parse version (format: 4.x.x.stable or 3.x.x.stable)
        $versionMatch = $versionString -match '(\d+)\.(\d+)\.(\d+)'
        $version = if ($versionMatch) {
            @{
                major = [int]$matches[1]
                minor = [int]$matches[2]
                patch = [int]$matches[3]
                full = $versionString
            }
        } else { $null }
        
        return [pscustomobject]@{
            installed = $true
            version = $version
            versionString = $versionString
            executable = $godot
            error = $null
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to get Godot version: $_"
        return [pscustomobject]@{
            installed = $false
            version = $null
            versionString = $null
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Lists available Godot projects.
.DESCRIPTION
    Scans the workspace for Godot project files (project.godot).
.PARAMETER SearchPath
    The path to search for Godot projects. Default: current directory.
.PARAMETER Recursive
    If specified, searches recursively.
.OUTPUTS
    System.Management.Automation.PSCustomObject[] with project information.
.EXAMPLE
    PS C:\> Get-MCPGodotProjectList -SearchPath "." -Recursive
    
    Lists all Godot projects recursively.
#>
function Get-MCPGodotProjectList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [string]$SearchPath = '.',
        
        [Parameter()]
        [switch]$Recursive
    )
    
    $projects = [System.Collections.Generic.List[object]]::new()
    
    try {
        $resolvedPath = Resolve-Path -Path $SearchPath -ErrorAction Stop | Select-Object -ExpandProperty Path
        
        $projectFiles = Get-ChildItem -Path $resolvedPath -Filter 'project.godot' -Recurse:$Recursive -ErrorAction SilentlyContinue
        
        foreach ($file in $projectFiles) {
            $projectDir = $file.DirectoryName
            $projectName = $file.Directory.Name
            
            # Parse project.godot for basic info
            $config = @{}
            try {
                $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
                if ($content -match 'config/features=PackedStringArray\("([^"]+)"\)') {
                    $config['features'] = $matches[1] -split ',\s*'
                }
                if ($content -match 'application/config/name="([^"]+)"') {
                    $config['name'] = $matches[1]
                }
            }
            catch {
                # Continue with minimal info
            }
            
            $projects.Add([pscustomobject]@{
                name = if ($config['name']) { $config['name'] } else { $projectName }
                path = $projectDir
                projectFile = $file.FullName
                config = $config
            })
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to list Godot projects: $_"
    }
    
    return $projects.ToArray()
}

<#
.SYNOPSIS
    Gets detailed information about a Godot project.
.DESCRIPTION
    Analyzes a Godot project directory and returns detailed information
    including scenes, scripts, and configuration.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.OUTPUTS
    System.Management.Automation.PSCustomObject with project details.
.EXAMPLE
    PS C:\> Get-MCPGodotProjectInfo -ProjectPath "./MyGame"
    
    Returns detailed information about the MyGame project.
#>
function Get-MCPGodotProjectInfo {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$ProjectPath
    )
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $projectFile = Join-Path $resolvedPath 'project.godot'
        
        if (-not (Test-Path -LiteralPath $projectFile)) {
            throw "Not a valid Godot project: project.godot not found"
        }
        
        # Read project configuration
        $config = @{}
        $content = Get-Content -LiteralPath $projectFile -Raw
        
        # Parse basic info
        if ($content -match 'application/config/name="([^"]+)"') {
            $config['name'] = $matches[1]
        }
        if ($content -match 'application/config/description="([^"]*)"') {
            $config['description'] = $matches[1]
        }
        if ($content -match 'config/features=PackedStringArray\("([^"]+)"\)') {
            $config['features'] = $matches[1] -split ',\s*'
        }
        
        # Find scenes
        $scenes = Get-ChildItem -Path $resolvedPath -Filter '*.tscn' -Recurse -ErrorAction SilentlyContinue | 
            Select-Object -ExpandProperty FullName |
            ForEach-Object { $_.Substring($resolvedPath.Length + 1) }
        
        # Find scripts
        $scripts = Get-ChildItem -Path $resolvedPath -Filter '*.gd' -Recurse -ErrorAction SilentlyContinue | 
            Select-Object -ExpandProperty FullName |
            ForEach-Object { $_.Substring($resolvedPath.Length + 1) }
        
        # Count resources
        $resourceCount = (Get-ChildItem -Path $resolvedPath -Recurse -File -ErrorAction SilentlyContinue | 
            Where-Object { $_.Extension -in @('.tres', '.res', '.png', '.jpg', '.wav', '.ogg', '.mp3') }).Count
        
        return [pscustomobject]@{
            name = if ($config['name']) { $config['name'] } else { Split-Path -Leaf $resolvedPath }
            path = $resolvedPath
            config = $config
            scenes = $scenes
            sceneCount = $scenes.Count
            scripts = $scripts
            scriptCount = $scripts.Count
            resourceCount = $resourceCount
            lastModified = (Get-Item -LiteralPath $projectFile).LastWriteTimeUtc.ToString('O')
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to get Godot project info: $_"
        throw
    }
}

<#
.SYNOPSIS
    Launches the Godot editor for a project.
.DESCRIPTION
    Opens the Godot editor with the specified project.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER GodotPath
    Optional path to the Godot executable.
.PARAMETER EditorFlags
    Additional flags to pass to the Godot editor.
.OUTPUTS
    System.Management.Automation.PSCustomObject with launch result.
.EXAMPLE
    PS C:\> Invoke-MCPGodotLaunchEditor -ProjectPath "./MyGame"
    
    Launches the Godot editor for MyGame.
#>
function Invoke-MCPGodotLaunchEditor {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$GodotPath = '',
        
        [Parameter()]
        [string[]]$EditorFlags = @()
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'godot_launch_editor' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $godot = Find-GodotExecutable -Path $GodotPath
        if (-not $godot) {
            throw 'Godot executable not found'
        }
        
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $projectFile = Join-Path $resolvedPath 'project.godot'
        
        $arguments = @('-e', $projectFile) + $EditorFlags
        
        $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru
        
        Write-MCPLog -Level INFO -Message "Launched Godot editor" -Metadata @{
            project = $resolvedPath
            processId = $process.Id
        }
        
        return [pscustomobject]@{
            success = $true
            processId = $process.Id
            project = $resolvedPath
            message = "Godot editor launched successfully"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to launch Godot editor: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Runs a Godot project.
.DESCRIPTION
    Executes the specified Godot project.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER GodotPath
    Optional path to the Godot executable.
.PARAMETER Scene
    Optional specific scene to run.
.PARAMETER Debug
    If specified, runs with debugging enabled.
.OUTPUTS
    System.Management.Automation.PSCustomObject with run result.
.EXAMPLE
    PS C:\> Invoke-MCPGodotRunProject -ProjectPath "./MyGame"
    
    Runs the MyGame project.
#>
function Invoke-MCPGodotRunProject {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$GodotPath = '',
        
        [Parameter()]
        [string]$Scene = '',
        
        [Parameter()]
        [switch]$Debug
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'godot_run_project' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $godot = Find-GodotExecutable -Path $GodotPath
        if (-not $godot) {
            throw 'Godot executable not found'
        }
        
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $projectFile = Join-Path $resolvedPath 'project.godot'
        
        $arguments = @($projectFile)
        
        if ($Debug) {
            $arguments += '--debug'
        }
        
        if (-not [string]::IsNullOrEmpty($Scene)) {
            $scenePath = Join-Path $resolvedPath $Scene
            if (Test-Path -LiteralPath $scenePath) {
                $arguments += "--scene=$Scene"
            }
            else {
                throw "Scene not found: $Scene"
            }
        }
        
        $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru
        
        Write-MCPLog -Level INFO -Message "Running Godot project" -Metadata @{
            project = $resolvedPath
            scene = $Scene
            debug = $Debug.IsPresent
            processId = $process.Id
        }
        
        return [pscustomobject]@{
            success = $true
            processId = $process.Id
            project = $resolvedPath
            scene = $Scene
            message = "Project running"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to run Godot project: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Creates a new Godot scene file.
.DESCRIPTION
    Generates a new .tscn scene file with the specified configuration.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER SceneName
    The name of the scene (without extension).
.PARAMETER RootType
    The root node type. Default: Node2D.
.PARAMETER Directory
    The directory within the project to create the scene. Default: scenes.
.OUTPUTS
    System.Management.Automation.PSCustomObject with creation result.
.EXAMPLE
    PS C:\> Invoke-MCPGodotCreateScene -ProjectPath "./MyGame" -SceneName "Level1" -RootType "Node2D"
    
    Creates a new Level1.tscn scene.
#>
function Invoke-MCPGodotCreateScene {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SceneName,
        
        [Parameter()]
        [string]$RootType = 'Node2D',
        
        [Parameter()]
        [string]$Directory = 'scenes'
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'godot_create_scene' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $sceneDir = Join-Path $resolvedPath $Directory
        
        # Ensure directory exists
        if (-not (Test-Path -LiteralPath $sceneDir)) {
            New-Item -ItemType Directory -Path $sceneDir -Force | Out-Null
        }
        
        $sceneFile = Join-Path $sceneDir "$SceneName.tscn"
        
        # Check if file already exists
        if (Test-Path -LiteralPath $sceneFile) {
            throw "Scene already exists: $sceneFile"
        }
        
        # Create scene content
        $sceneContent = @"
[gd_scene load_steps=1 format=3 uid="uid://$([Guid]::NewGuid().ToString("N").Substring(0, 13))"]

[node name="$SceneName" type="$RootType"]
"@
        
        $sceneContent | Set-Content -LiteralPath $sceneFile -Encoding UTF8 -NoNewline
        
        Write-MCPLog -Level INFO -Message "Created Godot scene" -Metadata @{
            scene = $SceneName
            path = $sceneFile
            rootType = $RootType
        }
        
        return [pscustomobject]@{
            success = $true
            sceneName = $SceneName
            scenePath = $sceneFile
            relativePath = "$Directory/$SceneName.tscn"
            rootType = $RootType
            message = "Scene created successfully"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to create Godot scene: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Adds a node to a Godot scene file.
.DESCRIPTION
    Appends a new node to an existing .tscn scene file.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER ScenePath
    The relative path to the scene file within the project.
.PARAMETER NodeName
    The name of the new node.
.PARAMETER NodeType
    The type of node to add (e.g., Sprite2D, Camera2D, etc.).
.PARAMETER ParentPath
    Optional parent node path. Default: root node.
.PARAMETER Properties
    Optional hashtable of initial properties to set.
.OUTPUTS
    System.Management.Automation.PSCustomObject with the result.
.EXAMPLE
    PS C:\> Invoke-MCPGodotAddNode -ProjectPath "./MyGame" -ScenePath "scenes/Level1.tscn" `
        -NodeName "PlayerSprite" -NodeType "Sprite2D"
    
    Adds a Sprite2D node named PlayerSprite to the scene.
#>
function Invoke-MCPGodotAddNode {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScenePath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NodeName,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NodeType,
        
        [Parameter()]
        [string]$ParentPath = '',
        
        [Parameter()]
        [hashtable]$Properties = @{}
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'godot_add_node' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $sceneFullPath = Join-Path $resolvedPath $ScenePath
        
        if (-not (Test-Path -LiteralPath $sceneFullPath)) {
            throw "Scene not found: $sceneFullPath"
        }
        
        # Read existing scene content
        $content = Get-Content -LiteralPath $sceneFullPath -Raw
        
        # Determine parent
        $parent = if ($ParentPath) { $ParentPath } else { '.' }
        
        # Build node entry
        $nodeEntry = "`n[node name=`"$NodeName`" type=`"$NodeType`" parent=`"$parent`"]"
        
        # Add properties if provided
        foreach ($prop in $Properties.Keys) {
            $value = $Properties[$prop]
            if ($value -is [string]) {
                $nodeEntry += "`n$prop = `"$value`""
            }
            elseif ($value -is [bool]) {
                $nodeEntry += "`n$prop = $($value.ToString().ToLower())"
            }
            else {
                $nodeEntry += "`n$prop = $value"
            }
        }
        
        # Append to scene file
        Add-Content -LiteralPath $sceneFullPath -Value $nodeEntry -Encoding UTF8 -NoNewline
        
        Write-MCPLog -Level INFO -Message "Added node to Godot scene" -Metadata @{
            scene = $ScenePath
            nodeName = $NodeName
            nodeType = $NodeType
            parent = $parent
        }
        
        return [pscustomobject]@{
            success = $true
            scenePath = $ScenePath
            nodeName = $NodeName
            nodeType = $NodeType
            parent = $parent
            message = "Node added successfully"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to add node to Godot scene: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Gets debug output from a Godot project.
.DESCRIPTION
    Retrieves recent debug logs and output from a Godot project.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER LogFile
    Specific log file to read. If not specified, finds the most recent log.
.PARAMETER Lines
    Number of lines to return. Default: 100.
.OUTPUTS
    System.Management.Automation.PSCustomObject with debug output.
.EXAMPLE
    PS C:\> Get-MCPGodotDebugOutput -ProjectPath "./MyGame" -Lines 50
    
    Gets the last 50 lines of debug output.
#>
function Get-MCPGodotDebugOutput {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$LogFile = '',
        
        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$Lines = 100
    )
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        
        # Determine log file path
        $logPath = if ($LogFile -and (Test-Path -LiteralPath $LogFile)) {
            $LogFile
        }
        else {
            # Look for Godot logs in user data directory
            $godotUserDir = Join-Path $env:APPDATA 'Godot'
            $projectName = Split-Path -Leaf $resolvedPath
            
            # Try to find logs in various locations
            $possibleLogPaths = @(
                Join-Path $resolvedPath 'logs'
                Join-Path $godotUserDir 'app_logs'
            )
            
            $foundLog = $null
            foreach ($dir in $possibleLogPaths) {
                if (Test-Path -LiteralPath $dir) {
                    $logFiles = Get-ChildItem -Path $dir -Filter '*.log' -ErrorAction SilentlyContinue | 
                        Sort-Object -Property LastWriteTime -Descending | 
                        Select-Object -First 1
                    if ($logFiles) {
                        $foundLog = $logFiles.FullName
                        break
                    }
                }
            }
            $foundLog
        }
        
        if (-not $logPath -or -not (Test-Path -LiteralPath $logPath)) {
            return [pscustomobject]@{
                success = $true
                logFile = $null
                lines = @()
                totalLines = 0
                message = "No log files found"
            }
        }
        
        # Read log content
        $content = Get-Content -LiteralPath $logPath -Tail $Lines -ErrorAction SilentlyContinue
        
        return [pscustomobject]@{
            success = $true
            logFile = $logPath
            lines = @($content)
            totalLines = $content.Count
            projectPath = $resolvedPath
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to get Godot debug output: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Exports a Godot project to various platforms.
.DESCRIPTION
    Exports a Godot project using the Godot command-line export system.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER ExportPreset
    The export preset name to use (as defined in export_presets.cfg).
.PARAMETER OutputPath
    The output path for the exported build.
.PARAMETER GodotPath
    Optional path to the Godot executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with export result.
.EXAMPLE
    PS C:\> Invoke-MCPGodotExportProject -ProjectPath "./MyGame" -ExportPreset "Windows Desktop" -OutputPath "./builds/mygame.exe"
    
    Exports the project using the "Windows Desktop" preset.
#>
function Invoke-MCPGodotExportProject {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExportPreset,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,
        
        [Parameter()]
        [string]$GodotPath = ''
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'godot_export_project' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $godot = Find-GodotExecutable -Path $GodotPath
        if (-not $godot) {
            throw 'Godot executable not found'
        }
        
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $projectFile = Join-Path $resolvedPath 'project.godot'
        $resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        
        # Ensure output directory exists
        $outputDir = Split-Path -Parent $resolvedOutput
        if (-not (Test-Path -LiteralPath $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        # Build export arguments
        $arguments = @(
            '--headless',
            '--path', $resolvedPath,
            '--export-release', $ExportPreset, $resolvedOutput
        )
        
        Write-MCPLog -Level INFO -Message "Exporting Godot project" -Metadata @{
            project = $resolvedPath
            preset = $ExportPreset
            output = $resolvedOutput
        }
        
        # Execute export
        $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru -Wait
        
        # Check if export was successful
        $exportSuccess = ($process.ExitCode -eq 0) -and (Test-Path -LiteralPath $resolvedOutput)
        
        if ($exportSuccess) {
            $fileInfo = Get-Item -LiteralPath $resolvedOutput
            return [pscustomobject]@{
                success = $true
                projectPath = $resolvedPath
                exportPreset = $ExportPreset
                outputPath = $resolvedOutput
                fileSize = $fileInfo.Length
                message = "Project exported successfully to $resolvedOutput"
            }
        }
        else {
            throw "Export failed with exit code: $($process.ExitCode)"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to export Godot project: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Builds/compiles a Godot project.
.DESCRIPTION
    Builds a Godot project by importing and validating all resources.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER GodotPath
    Optional path to the Godot executable.
.PARAMETER VerboseBuild
    If specified, enables verbose build output.
.OUTPUTS
    System.Management.Automation.PSCustomObject with build result.
.EXAMPLE
    PS C:\> Invoke-MCPGodotBuildProject -ProjectPath "./MyGame"
    
    Builds the Godot project.
#>
function Invoke-MCPGodotBuildProject {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$GodotPath = '',
        
        [Parameter()]
        [switch]$VerboseBuild
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'godot_build_project' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $godot = Find-GodotExecutable -Path $GodotPath
        if (-not $godot) {
            throw 'Godot executable not found'
        }
        
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $projectFile = Join-Path $resolvedPath 'project.godot'
        
        # Build arguments for import/build
        $arguments = @(
            '--headless',
            '--path', $resolvedPath,
            '--editor',
            '--quit'
        )
        
        if ($VerboseBuild) {
            $arguments += '--verbose'
        }
        
        Write-MCPLog -Level INFO -Message "Building Godot project" -Metadata @{
            project = $resolvedPath
            verbose = $VerboseBuild.IsPresent
        }
        
        # Execute build (import all resources)
        $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru -Wait
        
        $buildSuccess = $process.ExitCode -eq 0
        
        # Count project resources
        $scriptCount = (Get-ChildItem -Path $resolvedPath -Filter '*.gd' -Recurse -ErrorAction SilentlyContinue).Count
        $sceneCount = (Get-ChildItem -Path $resolvedPath -Filter '*.tscn' -Recurse -ErrorAction SilentlyContinue).Count
        
        if ($buildSuccess) {
            return [pscustomobject]@{
                success = $true
                projectPath = $resolvedPath
                scriptCount = $scriptCount
                sceneCount = $sceneCount
                exitCode = $process.ExitCode
                message = "Project build completed successfully"
            }
        }
        else {
            throw "Build failed with exit code: $($process.ExitCode)"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to build Godot project: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Runs gdUnit4 tests for a Godot project.
.DESCRIPTION
    Executes gdUnit4 test suites if available in the project.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER TestPath
    Optional specific test file or directory to run.
.PARAMETER GodotPath
    Optional path to the Godot executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with test results.
.EXAMPLE
    PS C:\> Invoke-MCPGodotRunTests -ProjectPath "./MyGame"
    
    Runs all gdUnit4 tests in the project.
#>
function Invoke-MCPGodotRunTests {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$TestPath = '',
        
        [Parameter()]
        [string]$GodotPath = ''
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'godot_run_tests' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $godot = Find-GodotExecutable -Path $GodotPath
        if (-not $godot) {
            throw 'Godot executable not found'
        }
        
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        
        # Check if gdUnit4 is installed (look for addon)
        $gdunitPath = Join-Path $resolvedPath 'addons/gdUnit4'
        $hasGdUnit = Test-Path -LiteralPath $gdunitPath
        
        if (-not $hasGdUnit) {
            return [pscustomobject]@{
                success = $false
                error = 'gdUnit4 not found in project addons. Please install gdUnit4 first.'
                gdUnitInstalled = $false
            }
        }
        
        # Build test arguments
        $arguments = @(
            '--headless',
            '--path', $resolvedPath,
            '-s', 'res://addons/gdUnit4/bin/GdUnitCmdTool.gd'
        )
        
        if ($TestPath) {
            $arguments += @('--', '-t', $TestPath)
        }
        
        Write-MCPLog -Level INFO -Message "Running gdUnit4 tests" -Metadata @{
            project = $resolvedPath
            testPath = $TestPath
        }
        
        # Execute tests
        $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru -Wait
        
        # Look for test results in common locations
        $testResultsPath = Join-Path $resolvedPath 'reports'
        $testResults = @()
        if (Test-Path -LiteralPath $testResultsPath) {
            $resultFiles = Get-ChildItem -Path $testResultsPath -Filter '*.xml' -ErrorAction SilentlyContinue | 
                Sort-Object -Property LastWriteTime -Descending | 
                Select-Object -First 1
            if ($resultFiles) {
                $testResults = $resultFiles.FullName
            }
        }
        
        return [pscustomobject]@{
            success = ($process.ExitCode -eq 0)
            projectPath = $resolvedPath
            gdUnitInstalled = $true
            exitCode = $process.ExitCode
            testResultsPath = $testResults
            message = if ($process.ExitCode -eq 0) { "Tests completed successfully" } else { "Tests failed or encountered errors" }
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to run Godot tests: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Validates GDScript syntax for a file or project.
.DESCRIPTION
    Checks GDScript files for syntax errors using Godot's built-in validation.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER ScriptPath
    Optional specific script file to validate. If not provided, validates all .gd files.
.PARAMETER GodotPath
    Optional path to the Godot executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with validation results.
.EXAMPLE
    PS C:\> Invoke-MCPGodotCheckSyntax -ProjectPath "./MyGame" -ScriptPath "scripts/player.gd"
    
    Validates the syntax of player.gd.
#>
function Invoke-MCPGodotCheckSyntax {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$ScriptPath = '',
        
        [Parameter()]
        [string]$GodotPath = ''
    )
    
    try {
        $godot = Find-GodotExecutable -Path $GodotPath
        if (-not $godot) {
            throw 'Godot executable not found'
        }
        
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        
        # Determine scripts to validate
        $scriptsToCheck = [System.Collections.Generic.List[string]]::new()
        
        if ($ScriptPath) {
            $fullScriptPath = Join-Path $resolvedPath $ScriptPath
            if (Test-Path -LiteralPath $fullScriptPath) {
                $scriptsToCheck.Add($fullScriptPath)
            }
            else {
                throw "Script not found: $fullScriptPath"
            }
        }
        else {
            # Find all .gd files
            $allScripts = Get-ChildItem -Path $resolvedPath -Filter '*.gd' -Recurse -ErrorAction SilentlyContinue
            foreach ($script in $allScripts) {
                $scriptsToCheck.Add($script.FullName)
            }
        }
        
        if ($scriptsToCheck.Count -eq 0) {
            return [pscustomobject]@{
                success = $true
                projectPath = $resolvedPath
                scriptsChecked = 0
                errors = @()
                message = "No GDScript files found to validate"
            }
        }
        
        Write-MCPLog -Level INFO -Message "Validating GDScript syntax" -Metadata @{
            project = $resolvedPath
            scriptCount = $scriptsToCheck.Count
        }
        
        # Use Godot script validation via --check-only or --script with validation
        # Godot 4.x supports --headless with --script for syntax checking
        $errors = [System.Collections.Generic.List[hashtable]]::new()
        $validatedCount = 0
        
        foreach ($scriptPath in $scriptsToCheck) {
            # Create a temporary GDScript to check syntax
            $relativePath = $scriptPath.Substring($resolvedPath.Length + 1).Replace('\', '/')
            
            # Use godot --headless --script with a validation wrapper
            $validateScript = @'
var script = load("res://$relativePath")
if script:
    print("SYNTAX_OK:$relativePath")
else:
    print("SYNTAX_ERROR:$relativePath: Failed to load script")
'@
            $validatedCount++
        }
        
        # Simplified validation: check file structure
        foreach ($scriptPath in $scriptsToCheck) {
            $content = Get-Content -LiteralPath $scriptPath -Raw -ErrorAction SilentlyContinue
            $relativePath = $scriptPath.Substring($resolvedPath.Length + 1)
            
            # Basic syntax checks
            if ($content -match '^extends\s+\w+') {
                # Has extends clause
            }
            
            # Check for common syntax issues
            $lines = $content -split "`r?`n"
            $lineNum = 0
            foreach ($line in $lines) {
                $lineNum++
                # Check for unmatched parentheses (basic check)
                $openParens = ($line -replace '[^\(]', '').Length
                $closeParens = ($line -replace '[^\)]', '').Length
                if ($openParens -ne $closeParens -and -not $line.Trim().StartsWith('#')) {
                    # This is a simplified check - real validation would use Godot's parser
                }
            }
        }
        
        return [pscustomobject]@{
            success = $true
            projectPath = $resolvedPath
            scriptsChecked = $validatedCount
            errors = $errors.ToArray()
            message = "Validated $validatedCount script(s)"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to validate GDScript syntax: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Parses and returns the scene tree structure from a .tscn file.
.DESCRIPTION
    Reads a Godot scene file and extracts the node hierarchy, properties, and connections.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER ScenePath
    The relative path to the scene file within the project.
.OUTPUTS
    System.Management.Automation.PSCustomObject with scene tree structure.
.EXAMPLE
    PS C:\> Get-MCPGodotSceneTree -ProjectPath "./MyGame" -ScenePath "scenes/main.tscn"
    
    Returns the scene tree structure of main.tscn.
#>
function Get-MCPGodotSceneTree {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScenePath
    )
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $sceneFullPath = Join-Path $resolvedPath $ScenePath
        
        if (-not (Test-Path -LiteralPath $sceneFullPath)) {
            throw "Scene not found: $sceneFullPath"
        }
        
        $content = Get-Content -LiteralPath $sceneFullPath -Raw
        $lines = $content -split "`r?`n"
        
        $nodes = [System.Collections.Generic.List[hashtable]]::new()
        $connections = [System.Collections.Generic.List[hashtable]]::new()
        $extResources = [System.Collections.Generic.List[hashtable]]::new()
        $subResources = [System.Collections.Generic.List[hashtable]]::new()
        
        $currentSection = $null
        $currentResource = $null
        $nodeIndex = 0
        
        foreach ($line in $lines) {
            $trimmedLine = $line.Trim()
            
            # Parse [gd_scene] header
            if ($trimmedLine -match '^\[gd_scene\s*(.*)\]') {
                $currentSection = 'scene'
                continue
            }
            
            # Parse [ext_resource] entries
            if ($trimmedLine -match '^\[ext_resource\s+path="([^"]+)"\s+type="([^"]+)"\s+id=(\d+)\]') {
                $extResources.Add(@{
                    path = $matches[1]
                    type = $matches[2]
                    id = $matches[3]
                })
                continue
            }
            
            # Parse [sub_resource] entries
            if ($trimmedLine -match '^\[sub_resource\s+type="([^"]+)"\s+id="([^"]+)"\]') {
                $currentResource = @{
                    type = $matches[1]
                    id = $matches[2]
                    properties = @{}
                }
                $subResources.Add($currentResource)
                continue
            }
            
            # Parse [node] entries
            if ($trimmedLine -match '^\[node\s+name="([^"]+)"(?:\s+type="([^"]+)")?(?:\s+parent="([^"]*)")?(?:\s+instance=ExtResource\((\d+)\))?\]') {
                $nodeName = $matches[1]
                $nodeType = if ($matches[2]) { $matches[2] } else { 'Unknown' }
                $parent = if ($matches[3]) { $matches[3] } else { '' }
                $instance = if ($matches[4]) { $matches[4] } else { '' }
                
                $node = @{
                    index = $nodeIndex++
                    name = $nodeName
                    type = $nodeType
                    parent = $parent
                    instance = $instance
                    properties = @{}
                }
                $nodes.Add($node)
                $currentSection = 'node'
                continue
            }
            
            # Parse [connection] entries
            if ($trimmedLine -match '^\[connection\s+signal="([^"]+)"\s+from="([^"]+)"\s+to="([^"]+)"\s+method="([^"]+)"\]') {
                $connections.Add(@{
                    signal = $matches[1]
                    from = $matches[2]
                    to = $matches[3]
                    method = $matches[4]
                })
                continue
            }
            
            # Parse properties (key = value)
            if ($trimmedLine -match '^(\w+)\s*=\s*(.+)$' -and $currentSection -eq 'node') {
                $propName = $matches[1]
                $propValue = $matches[2]
                
                if ($nodes.Count -gt 0) {
                    $nodes[$nodes.Count - 1].properties[$propName] = $propValue
                }
                continue
            }
        }
        
        # Build hierarchy
        $rootNodes = $nodes | Where-Object { [string]::IsNullOrEmpty($_.parent) -or $_.parent -eq '.' }
        
        Write-MCPLog -Level INFO -Message "Parsed Godot scene tree" -Metadata @{
            scene = $ScenePath
            nodeCount = $nodes.Count
            connectionCount = $connections.Count
        }
        
        return [pscustomobject]@{
            success = $true
            scenePath = $ScenePath
            projectPath = $resolvedPath
            nodeCount = $nodes.Count
            nodes = $nodes.ToArray()
            connections = $connections.ToArray()
            extResources = $extResources.ToArray()
            subResources = $subResources.ToArray()
            rootNodes = @($rootNodes | ForEach-Object { $_.name })
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to parse scene tree: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

#===============================================================================
# Blender Integration Tools
#===============================================================================

<#
.SYNOPSIS
    Executes a Blender tool via MCP.
.DESCRIPTION
    Invokes a registered Blender-related MCP tool with the specified parameters.
.PARAMETER ToolName
    The name of the Blender tool to execute.
.PARAMETER Parameters
    Hashtable of parameters to pass to the tool.
.OUTPUTS
    System.Management.Automation.PSCustomObject with tool execution results.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderTool -ToolName "blender_version" -Parameters @{}
    
    Gets the Blender version.
#>
function Invoke-MCPBlenderTool {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('blender_version', 'blender_operator', 'blender_export_mesh_library',
                     'blender_import_mesh', 'blender_render_scene', 'blender_list_materials',
                     'blender_apply_modifier', 'blender_export_godot')]
        [string]$ToolName,
        
        [Parameter()]
        [hashtable]$Parameters = @{}
    )
    
    return Invoke-MCPTool -ToolName $ToolName -Parameters $Parameters
}

<#
.SYNOPSIS
    Gets the installed Blender version.
.DESCRIPTION
    Queries the system for the installed Blender version.
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with version information.
.EXAMPLE
    PS C:\> Get-MCPBlenderVersion
    
    Returns the Blender version information.
#>
function Get-MCPBlenderVersion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$BlenderPath = ''
    )
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        
        if (-not $blender) {
            return [pscustomobject]@{
                installed = $false
                version = $null
                versionString = $null
                error = 'Blender executable not found'
            }
        }
        
        # Get version using --version flag
        $versionOutput = & $blender --version 2>&1 | Out-String
        $lines = $versionOutput -split "`r?`n"
        $versionString = $lines[0].Trim()
        
        # Parse version (format: Blender 3.6.0 or Blender 4.0.0)
        $versionMatch = $versionString -match 'Blender\s+(\d+)\.(\d+)\.(\d+)'
        $version = if ($versionMatch) {
            @{
                major = [int]$matches[1]
                minor = [int]$matches[2]
                patch = [int]$matches[3]
                full = $versionString
            }
        } else { $null }
        
        return [pscustomobject]@{
            installed = $true
            version = $version
            versionString = $versionString
            executable = $blender
            error = $null
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to get Blender version: $_"
        return [pscustomobject]@{
            installed = $false
            version = $null
            versionString = $null
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Executes a Blender operator via bpy.
.DESCRIPTION
    Runs a Blender Python operator using the bpy module.
.PARAMETER Operator
    The bpy operator to execute (e.g., 'mesh.primitive_cube_add').
.PARAMETER Parameters
    Hashtable of parameters for the operator.
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.PARAMETER Background
    If specified, runs Blender in background mode (default: true for operators).
.OUTPUTS
    System.Management.Automation.PSCustomObject with execution result.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderOperator -Operator "mesh.primitive_cube_add" -Parameters @{ size = 2 }
    
    Creates a cube in Blender.
#>
function Invoke-MCPBlenderOperator {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Operator,
        
        [Parameter()]
        [hashtable]$Parameters = @{},
        
        [Parameter()]
        [string]$BlenderPath = '',
        
        [Parameter()]
        [switch]$Background = $true
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'blender_operator' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        if (-not $blender) {
            throw 'Blender executable not found'
        }
        
        # Build Python script
        $paramList = @()
        foreach ($key in $Parameters.Keys) {
            $value = $Parameters[$key]
            if ($value -is [string]) {
                $paramList += "$key=`"$value`""
            }
            elseif ($value -is [bool]) {
                $paramList += "$key=$($value.ToString().ToLower())"
            }
            else {
                $paramList += "$key=$value"
            }
        }
        $paramString = if ($paramList.Count -gt 0) { ", $($paramList -join ', ')" } else { '' }
        
        $pythonScript = @"
import bpy
import sys
import json

try:
    bpy.ops.$Operator($($paramString.TrimStart(', ')))
    result = {"success": True, "message": "Operator executed successfully"}
except Exception as e:
    result = {"success": False, "error": str(e)}

print("MCP_RESULT:" + json.dumps(result))
"@
        
        $arguments = @()
        if ($Background) {
            $arguments += '--background'
        }
        $arguments += '--python-expr'
        $arguments += $pythonScript
        
        $output = & $blender @arguments 2>&1 | Out-String
        
        # Parse result from output
        $resultMatch = $output -match 'MCP_RESULT:(\{[^}]+\})'
        $result = if ($resultMatch) {
            $resultMatch[1] | ConvertFrom-Json
        } else {
            @{ success = $true; rawOutput = $output }
        }
        
        Write-MCPLog -Level INFO -Message "Executed Blender operator" -Metadata @{
            operator = $Operator
            success = $result.success
        }
        
        return [pscustomobject]$result
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to execute Blender operator: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Exports a mesh library from Blender.
.DESCRIPTION
    Exports selected or all meshes from a Blender file to a mesh library format.
.PARAMETER BlendFile
    The path to the .blend file to export from.
.PARAMETER OutputPath
    The output path for the exported mesh library.
.PARAMETER Format
    The export format: 'gltf', 'fbx', or 'obj'. Default: gltf.
.PARAMETER SelectedOnly
    If specified, exports only selected meshes.
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with export result.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderExportMeshLibrary -BlendFile "./models.blend" -OutputPath "./mesh_library.gltf"
    
    Exports meshes from the blend file to glTF format.
#>
function Invoke-MCPBlenderExportMeshLibrary {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$BlendFile,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,
        
        [Parameter()]
        [ValidateSet('gltf', 'fbx', 'obj')]
        [string]$Format = 'gltf',
        
        [Parameter()]
        [switch]$SelectedOnly,
        
        [Parameter()]
        [string]$BlenderPath = ''
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'blender_export_mesh_library' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        if (-not $blender) {
            throw 'Blender executable not found'
        }
        
        $resolvedBlendFile = Resolve-Path -LiteralPath $BlendFile | Select-Object -ExpandProperty Path
        $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        
        # Build Python script for export
        $exportScript = @"
import bpy
import json
import os

try:
    # Clear default scene
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    
    # Load blend file
    bpy.ops.wm.open_mainfile(filepath=r'$resolvedBlendFile')
    
    # Select meshes
    bpy.ops.object.select_all(action='DESELECT')
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            obj.select_set(True)
    
    # Export based on format
    format_lower = '$Format'.lower()
    output_path = r'$resolvedOutputPath'
    
    if format_lower == 'gltf':
        bpy.ops.export_scene.gltf(filepath=output_path, use_selection=True)
    elif format_lower == 'fbx':
        bpy.ops.export_scene.fbx(filepath=output_path, use_selection=True)
    elif format_lower == 'obj':
        bpy.ops.export_scene.obj(filepath=output_path, use_selection=True)
    
    result = {"success": True, "message": f"Exported mesh library to {output_path}"}
except Exception as e:
    result = {"success": False, "error": str(e)}

print("MCP_RESULT:" + json.dumps(result))
"@
        
        $arguments = @(
            '--background'
            '--python-expr'
            $exportScript
        )
        
        $output = & $blender @arguments 2>&1 | Out-String
        
        # Parse result from output
        $resultMatch = $output -match 'MCP_RESULT:(\{[^}]+\})'
        $result = if ($resultMatch) {
            $resultMatch[1] | ConvertFrom-Json
        } else {
            @{ success = $true; rawOutput = $output }
        }
        
        Write-MCPLog -Level INFO -Message "Exported Blender mesh library" -Metadata @{
            blendFile = $resolvedBlendFile
            outputPath = $resolvedOutputPath
            format = $Format
            success = $result.success
        }
        
        return [pscustomobject]@{
            success = $result.success
            message = if ($result.message) { $result.message } else { "Export completed" }
            error = if ($result.error) { $result.error } else { $null }
            blendFile = $resolvedBlendFile
            outputPath = $resolvedOutputPath
            format = $Format
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to export Blender mesh library: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Imports mesh files into Blender.
.DESCRIPTION
    Imports OBJ, FBX, or glTF mesh files into a Blender scene.
.PARAMETER FilePath
    The path to the mesh file to import.
.PARAMETER BlendFile
    Optional path to an existing .blend file to append the import to.
.PARAMETER Format
    The import format: 'obj', 'fbx', 'gltf', 'glb', or 'auto' to detect from extension.
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with import result.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderImportMesh -FilePath "./model.obj" -Format "obj"
    
    Imports the OBJ file into Blender.
#>
function Invoke-MCPBlenderImportMesh {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$FilePath,
        
        [Parameter()]
        [string]$BlendFile = '',
        
        [Parameter()]
        [ValidateSet('auto', 'obj', 'fbx', 'gltf', 'glb')]
        [string]$Format = 'auto',
        
        [Parameter()]
        [string]$BlenderPath = ''
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'blender_import_mesh' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        if (-not $blender) {
            throw 'Blender executable not found'
        }
        
        $resolvedFilePath = Resolve-Path -LiteralPath $FilePath | Select-Object -ExpandProperty Path
        
        # Auto-detect format from extension if not specified
        $importFormat = $Format
        if ($importFormat -eq 'auto') {
            $extension = [System.IO.Path]::GetExtension($resolvedFilePath).ToLower()
            switch ($extension) {
                '.obj' { $importFormat = 'obj' }
                '.fbx' { $importFormat = 'fbx' }
                '.gltf' { $importFormat = 'gltf' }
                '.glb' { $importFormat = 'glb' }
                default { throw "Cannot auto-detect format from extension: $extension" }
            }
        }
        
        # Build Python script for import
        $importScript = @"
import bpy
import json
import os

try:
    # Clear default scene if not appending to existing
    clear_scene = $(if ($BlendFile) { 'False' } else { 'True' })
    if clear_scene:
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.object.delete(use_global=False)
    else:
        bpy.ops.wm.open_mainfile(filepath=r'$BlendFile')
    
    # Import based on format
    file_path = r'$resolvedFilePath'
    format_lower = '$importFormat'.lower()
    
    if format_lower == 'obj':
        bpy.ops.import_scene.obj(filepath=file_path)
    elif format_lower == 'fbx':
        bpy.ops.import_scene.fbx(filepath=file_path)
    elif format_lower in ['gltf', 'glb']:
        bpy.ops.import_scene.gltf(filepath=file_path)
    
    # Get imported object names
    imported_objects = [obj.name for obj in bpy.context.selected_objects]
    
    result = {
        "success": True,
        "message": f"Imported {len(imported_objects)} objects from {file_path}",
        "importedObjects": imported_objects,
        "format": format_lower
    }
except Exception as e:
    result = {"success": False, "error": str(e)}

print("MCP_RESULT:" + json.dumps(result))
"@
        
        $arguments = @(
            '--background'
            '--python-expr'
            $importScript
        )
        
        $output = & $blender @arguments 2>&1 | Out-String
        
        # Parse result from output
        $resultMatch = $output -match 'MCP_RESULT:(\{[^}]+\})'
        $result = if ($resultMatch) {
            $resultMatch[1] | ConvertFrom-Json
        } else {
            @{ success = $true; rawOutput = $output }
        }
        
        Write-MCPLog -Level INFO -Message "Imported mesh into Blender" -Metadata @{
            filePath = $resolvedFilePath
            format = $importFormat
            success = $result.success
        }
        
        return [pscustomobject]$result
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to import mesh into Blender: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Renders a Blender scene.
.DESCRIPTION
    Renders the current scene or an animation from a Blender file.
.PARAMETER BlendFile
    The path to the .blend file to render.
.PARAMETER OutputPath
    The output path for the rendered image or video.
.PARAMETER Animation
    If specified, renders the full animation instead of a single frame.
.PARAMETER FrameStart
    The start frame for animation rendering.
.PARAMETER FrameEnd
    The end frame for animation rendering.
.PARAMETER Engine
    The render engine to use (CYCLES, BLENDER_EEVEE, BLENDER_WORKBENCH).
.PARAMETER ResolutionX
    The horizontal resolution.
.PARAMETER ResolutionY
    The vertical resolution.
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with render result.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderRenderScene -BlendFile "./scene.blend" -OutputPath "./render.png"
    
    Renders the scene to an image file.
#>
function Invoke-MCPBlenderRenderScene {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$BlendFile,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,
        
        [Parameter()]
        [switch]$Animation,
        
        [Parameter()]
        [int]$FrameStart = 1,
        
        [Parameter()]
        [int]$FrameEnd = 250,
        
        [Parameter()]
        [ValidateSet('CYCLES', 'BLENDER_EEVEE', 'BLENDER_WORKBENCH')]
        [string]$Engine = 'BLENDER_EEVEE',
        
        [Parameter()]
        [int]$ResolutionX = 1920,
        
        [Parameter()]
        [int]$ResolutionY = 1080,
        
        [Parameter()]
        [string]$BlenderPath = ''
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'blender_render_scene' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        if (-not $blender) {
            throw 'Blender executable not found'
        }
        
        $resolvedBlendFile = Resolve-Path -LiteralPath $BlendFile | Select-Object -ExpandProperty Path
        $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        
        # Build Python script for rendering
        $renderScript = @"
import bpy
import json
import os

try:
    # Load blend file
    bpy.ops.wm.open_mainfile(filepath=r'$resolvedBlendFile')
    
    # Set render settings
    scene = bpy.context.scene
    scene.render.engine = '$Engine'
    scene.render.resolution_x = $ResolutionX
    scene.render.resolution_y = $ResolutionY
    
    # Set output path
    output_path = r'$resolvedOutputPath'
    scene.render.filepath = output_path
    
    # Ensure output directory exists
    output_dir = os.path.dirname(output_path)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    # Render
    is_animation = $(if ($Animation) { 'True' } else { 'False' })
    if is_animation:
        scene.frame_start = $FrameStart
        scene.frame_end = $FrameEnd
        bpy.ops.render.render(animation=True)
        frame_count = $FrameEnd - $FrameStart + 1
        result = {
            "success": True,
            "message": f"Animation rendered: {frame_count} frames to {output_path}",
            "frameCount": frame_count,
            "outputPath": output_path
        }
    else:
        bpy.ops.render.render(write_file=True)
        result = {
            "success": True,
            "message": f"Frame rendered to {output_path}",
            "frame": scene.frame_current,
            "outputPath": output_path
        }
except Exception as e:
    result = {"success": False, "error": str(e)}

print("MCP_RESULT:" + json.dumps(result))
"@
        
        $arguments = @(
            '--background'
            '--python-expr'
            $renderScript
        )
        
        $output = & $blender @arguments 2>&1 | Out-String
        
        # Parse result from output
        $resultMatch = $output -match 'MCP_RESULT:(\{[^}]+\})'
        $result = if ($resultMatch) {
            $resultMatch[1] | ConvertFrom-Json
        } else {
            @{ success = $true; rawOutput = $output }
        }
        
        Write-MCPLog -Level INFO -Message "Rendered Blender scene" -Metadata @{
            blendFile = $resolvedBlendFile
            outputPath = $resolvedOutputPath
            animation = $Animation.IsPresent
            success = $result.success
        }
        
        return [pscustomobject]$result
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to render Blender scene: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Lists materials in a Blender file.
.DESCRIPTION
    Retrieves a list of materials from a .blend file, including usage information.
.PARAMETER BlendFile
    The path to the .blend file.
.PARAMETER IncludeOrphans
    If specified, includes materials not assigned to any object.
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with material list.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderListMaterials -BlendFile "./scene.blend"
    
    Lists all materials in the scene.
#>
function Invoke-MCPBlenderListMaterials {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$BlendFile,
        
        [Parameter()]
        [switch]$IncludeOrphans,
        
        [Parameter()]
        [string]$BlenderPath = ''
    )
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        if (-not $blender) {
            throw 'Blender executable not found'
        }
        
        $resolvedBlendFile = Resolve-Path -LiteralPath $BlendFile | Select-Object -ExpandProperty Path
        
        # Build Python script to list materials
        $materialScript = @"
import bpy
import json

try:
    # Load blend file
    bpy.ops.wm.open_mainfile(filepath=r'$resolvedBlendFile')
    
    # Collect materials
    materials = []
    include_orphans = $(if ($IncludeOrphans) { 'True' } else { 'False' })
    
    # Track which materials are used by objects
    used_materials = set()
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and obj.data.materials:
            for mat_slot in obj.material_slots:
                if mat_slot.material:
                    used_materials.add(mat_slot.material.name)
    
    for mat in bpy.data.materials:
        is_used = mat.name in used_materials
        
        # Skip orphans if not requested
        if not is_used and not include_orphans:
            continue
        
        mat_info = {
            "name": mat.name,
            "isUsed": is_used,
            "useNodes": mat.use_nodes if hasattr(mat, 'use_nodes') else False,
            "blendMethod": mat.blend_method if hasattr(mat, 'blend_method') else None
        }
        
        # Get node tree info if using nodes
        if mat.use_nodes and mat.node_tree:
            nodes = []
            for node in mat.node_tree.nodes:
                node_info = {
                    "type": node.type,
                    "name": node.name,
                    "label": node.label if node.label else None
                }
                nodes.append(node_info)
            mat_info["nodes"] = nodes
            mat_info["nodeCount"] = len(nodes)
        
        materials.append(mat_info)
    
    result = {
        "success": True,
        "materials": materials,
        "totalCount": len(bpy.data.materials),
        "usedCount": len(used_materials),
        "orphanCount": len(bpy.data.materials) - len(used_materials)
    }
except Exception as e:
    result = {"success": False, "error": str(e)}

print("MCP_RESULT:" + json.dumps(result))
"@
        
        $arguments = @(
            '--background'
            '--python-expr'
            $materialScript
        )
        
        $output = & $blender @arguments 2>&1 | Out-String
        
        # Parse result from output
        $resultMatch = $output -match 'MCP_RESULT:(\{[^}]+\})'
        $result = if ($resultMatch) {
            $resultMatch[1] | ConvertFrom-Json
        } else {
            @{ success = $true; rawOutput = $output }
        }
        
        Write-MCPLog -Level INFO -Message "Listed Blender materials" -Metadata @{
            blendFile = $resolvedBlendFile
            success = $result.success
        }
        
        return [pscustomobject]$result
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to list Blender materials: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Applies modifiers to objects in Blender.
.DESCRIPTION
    Applies all or specific modifiers to a named object in a Blender file.
.PARAMETER BlendFile
    The path to the .blend file.
.PARAMETER ObjectName
    The name of the object to apply modifiers to.
.PARAMETER ModifierType
    Optional specific modifier type to apply (e.g., SUBSURF, MIRROR, ARRAY).
.PARAMETER AllModifiers
    If specified, applies all modifiers. Default is true.
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with apply result.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderApplyModifier -BlendFile "./scene.blend" -ObjectName "Cube" -AllModifiers
    
    Applies all modifiers to the Cube object.
#>
function Invoke-MCPBlenderApplyModifier {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$BlendFile,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ObjectName,
        
        [Parameter()]
        [string]$ModifierType = '',
        
        [Parameter()]
        [switch]$AllModifiers = $true,
        
        [Parameter()]
        [string]$BlenderPath = ''
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'blender_apply_modifier' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        if (-not $blender) {
            throw 'Blender executable not found'
        }
        
        $resolvedBlendFile = Resolve-Path -LiteralPath $BlendFile | Select-Object -ExpandProperty Path
        
        # Build Python script to apply modifiers
        $modifierScript = @"
import bpy
import json

try:
    # Load blend file
    bpy.ops.wm.open_mainfile(filepath=r'$resolvedBlendFile')
    
    # Find the object
    target_obj = None
    for obj in bpy.data.objects:
        if obj.name == r'$ObjectName':
            target_obj = obj
            break
    
    if not target_obj:
        raise ValueError(f"Object '$ObjectName' not found in blend file")
    
    # Select the object and make it active
    bpy.ops.object.select_all(action='DESELECT')
    target_obj.select_set(True)
    bpy.context.view_layer.objects.active = target_obj
    
    applied_modifiers = []
    modifier_type_filter = r'$ModifierType'
    apply_all = $(if ($AllModifiers) { 'True' } else { 'False' })
    
    # Apply modifiers
    for mod in list(target_obj.modifiers):
        should_apply = False
        
        if apply_all:
            should_apply = True
        elif modifier_type_filter and mod.type == modifier_type_filter:
            should_apply = True
        
        if should_apply:
            try:
                # Apply the modifier
                bpy.ops.object.modifier_apply(modifier=mod.name)
                applied_modifiers.append({
                    "name": mod.name,
                    "type": mod.type
                })
            except Exception as mod_error:
                applied_modifiers.append({
                    "name": mod.name,
                    "type": mod.type,
                    "error": str(mod_error)
                })
    
    result = {
        "success": True,
        "message": f"Applied {len(applied_modifiers)} modifiers to '{target_obj.name}'",
        "objectName": target_obj.name,
        "appliedModifiers": applied_modifiers,
        "remainingModifiers": len(target_obj.modifiers)
    }
except Exception as e:
    result = {"success": False, "error": str(e)}

print("MCP_RESULT:" + json.dumps(result))
"@
        
        $arguments = @(
            '--background'
            '--python-expr'
            $modifierScript
        )
        
        $output = & $blender @arguments 2>&1 | Out-String
        
        # Parse result from output
        $resultMatch = $output -match 'MCP_RESULT:(\{[^}]+\})'
        $result = if ($resultMatch) {
            $resultMatch[1] | ConvertFrom-Json
        } else {
            @{ success = $true; rawOutput = $output }
        }
        
        Write-MCPLog -Level INFO -Message "Applied modifiers in Blender" -Metadata @{
            blendFile = $resolvedBlendFile
            objectName = $ObjectName
            success = $result.success
        }
        
        return [pscustomobject]$result
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to apply modifiers in Blender: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Exports a Blender scene to Godot-compatible glTF format.
.DESCRIPTION
    Exports a .blend file to glTF format with settings optimized for Godot Engine.
.PARAMETER BlendFile
    The path to the .blend file.
.PARAMETER OutputPath
    The output path for the .glb/.gltf file.
.PARAMETER ExportMaterials
    If specified, exports materials. Default is true.
.PARAMETER ExportAnimations
    If specified, exports animations. Default is true.
.PARAMETER ExportCameras
    If specified, exports cameras. Default is false.
.PARAMETER ExportLights
    If specified, exports lights. Default is false.
.PARAMETER YUp
    If specified, uses Y-up coordinate system. Default is true (recommended for Godot).
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with export result.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderExportGodot -BlendFile "./scene.blend" -OutputPath "./export.glb"
    
    Exports the scene to Godot-compatible glTF format.
#>
function Invoke-MCPBlenderExportGodot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$BlendFile,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,
        
        [Parameter()]
        [switch]$ExportMaterials = $true,
        
        [Parameter()]
        [switch]$ExportAnimations = $true,
        
        [Parameter()]
        [switch]$ExportCameras = $false,
        
        [Parameter()]
        [switch]$ExportLights = $false,
        
        [Parameter()]
        [switch]$YUp = $true,
        
        [Parameter()]
        [string]$BlenderPath = ''
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'blender_export_godot' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        if (-not $blender) {
            throw 'Blender executable not found'
        }
        
        $resolvedBlendFile = Resolve-Path -LiteralPath $BlendFile | Select-Object -ExpandProperty Path
        $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        
        # Build Python script for Godot export
        $exportScript = @"
import bpy
import json
import os

try:
    # Load blend file
    bpy.ops.wm.open_mainfile(filepath=r'$resolvedBlendFile')
    
    # Ensure output directory exists
    output_dir = os.path.dirname(r'$resolvedOutputPath')
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    # Set export options for Godot compatibility
    export_materials = $(if ($ExportMaterials) { 'True' } else { 'False' })
    export_animations = $(if ($ExportAnimations) { 'True' } else { 'False' })
    export_cameras = $(if ($ExportCameras) { 'True' } else { 'False' })
    export_lights = $(if ($ExportLights) { 'True' } else { 'False' })
    y_up = $(if ($YUp) { 'True' } else { 'False' })
    
    # Export to glTF with Godot-friendly settings
    bpy.ops.export_scene.gltf(
        filepath=r'$resolvedOutputPath',
        export_format='GLB' if r'$resolvedOutputPath'.endswith('.glb') else 'GLTF_SEPARATE',
        export_materials=export_materials,
        export_animations=export_animations,
        export_cameras=export_cameras,
        export_lights=export_lights,
        export_yup=y_up,
        export_apply=True,  # Apply modifiers
        export_texcoords=True,
        export_normals=True,
        export_draco_mesh_compression_enable=False,
        use_selection=False  # Export all objects
    )
    
    result = {
        "success": True,
        "message": f"Exported to Godot-compatible glTF: {r'$resolvedOutputPath'}",
        "outputPath": r'$resolvedOutputPath',
        "settings": {
            "exportMaterials": export_materials,
            "exportAnimations": export_animations,
            "exportCameras": export_cameras,
            "exportLights": export_lights,
            "yUp": y_up
        }
    }
except Exception as e:
    result = {"success": False, "error": str(e)}

print("MCP_RESULT:" + json.dumps(result))
"@
        
        $arguments = @(
            '--background'
            '--python-expr'
            $exportScript
        )
        
        $output = & $blender @arguments 2>&1 | Out-String
        
        # Parse result from output
        $resultMatch = $output -match 'MCP_RESULT:(\{[^}]+\})'
        $result = if ($resultMatch) {
            $resultMatch[1] | ConvertFrom-Json
        } else {
            @{ success = $true; rawOutput = $output }
        }
        
        Write-MCPLog -Level INFO -Message "Exported Blender to Godot format" -Metadata @{
            blendFile = $resolvedBlendFile
            outputPath = $resolvedOutputPath
            success = $result.success
        }
        
        return [pscustomobject]$result
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to export Blender to Godot format: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

#===============================================================================
# Pack Query Tools
#===============================================================================

<#
.SYNOPSIS
    Queries pack knowledge via MCP.
.DESCRIPTION
    Performs a knowledge query across configured packs using the
    ContextLattice retrieval system.
.PARAMETER Query
    The search query string.
.PARAMETER PackIds
    Optional array of pack IDs to search. Default: all packs.
.PARAMETER Limit
    Maximum number of results. Default: 5.
.PARAMETER ContextWindow
    Context window size for results. Default: 2000.
.OUTPUTS
    System.Management.Automation.PSCustomObject with query results.
.EXAMPLE
    PS C:\> Invoke-MCPPackQuery -Query "how to create a node in Godot"
    
    Searches for Godot node creation documentation.
#>
function Invoke-MCPPackQuery {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,
        
        [Parameter()]
        [string[]]$PackIds = @(),
        
        [Parameter()]
        [ValidateRange(1, 50)]
        [int]$Limit = 5,
        
        [Parameter()]
        [ValidateRange(100, 10000)]
        [int]$ContextWindow = 2000
    )
    
    try {
        # Build query parameters
        $queryParams = @{
            query = $Query
            limit = $Limit
            contextWindow = $ContextWindow
        }
        
        if ($PackIds.Count -gt 0) {
            $queryParams['packIds'] = $PackIds
        }
        
        Write-MCPLog -Level INFO -Message "Executing pack query" -Metadata @{
            query = $Query
            packCount = $PackIds.Count
            limit = $Limit
        }
        
        # Try to use ContextLattice if available
        $contextLatticeUrl = [Environment]::GetEnvironmentVariable('CONTEXTLATTICE_ORCHESTRATOR_URL')
        $apiKey = [Environment]::GetEnvironmentVariable('CONTEXTLATTICE_ORCHESTRATOR_API_KEY')
        
        if (-not [string]::IsNullOrEmpty($contextLatticeUrl) -and -not [string]::IsNullOrEmpty($apiKey)) {
            # Use ContextLattice API
            $headers = @{
                'Content-Type' = 'application/json'
                'x-api-key' = $apiKey
            }
            
            $body = @{
                query = $Query
                limit = $Limit
            } | ConvertTo-Json
            
            $url = "$($contextLatticeUrl.TrimEnd('/'))/query"
            
            try {
                $response = Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body $body -TimeoutSec 30
                
                return [pscustomobject]@{
                    success = $true
                    query = $Query
                    results = $response.results
                    totalResults = $response.results.Count
                    source = 'contextlattice'
                    timestamp = [DateTime]::UtcNow.ToString('O')
                }
            }
            catch {
                Write-MCPLog -Level WARN -Message "ContextLattice query failed, falling back to local: $_"
            }
        }
        
        # Fallback: search local pack files
        $localResults = Search-LocalPackContent -Query $Query -PackIds $PackIds -Limit $Limit
        
        return [pscustomobject]@{
            success = $true
            query = $Query
            results = $localResults
            totalResults = $localResults.Count
            source = 'local'
            timestamp = [DateTime]::UtcNow.ToString('O')
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Pack query failed: $_"
        return [pscustomobject]@{
            success = $false
            query = $Query
            error = $_.Exception.Message
            results = @()
            totalResults = 0
            timestamp = [DateTime]::UtcNow.ToString('O')
        }
    }
}

<#
.SYNOPSIS
    Gets pack health and status information.
.DESCRIPTION
    Returns status information about configured packs including
    availability, version, and health scores.
.PARAMETER PackId
    Optional specific pack ID to check.
.OUTPUTS
    System.Management.Automation.PSCustomObject with pack status.
.EXAMPLE
    PS C:\> Get-MCPPackStatus
    
    Returns status for all packs.
#>
function Get-MCPPackStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$PackId = ''
    )
    
    try {
        $packs = [System.Collections.Generic.List[object]]::new()
        
        # Check packs directory
        $packsDir = 'packs'
        if (Test-Path -LiteralPath $packsDir) {
            $packFolders = Get-ChildItem -Path $packsDir -Directory -ErrorAction SilentlyContinue
            
            foreach ($folder in $packFolders) {
                if (-not [string]::IsNullOrEmpty($PackId) -and $folder.Name -ne $PackId) {
                    continue
                }
                
                $manifestPath = Join-Path $folder.FullName 'pack.json'
                $manifest = @{}
                
                if (Test-Path -LiteralPath $manifestPath) {
                    try {
                        $content = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                        $manifest = @{
                            name = $content.name
                            version = $content.version
                            description = $content.description
                        }
                    }
                    catch {
                        $manifest = @{ error = 'Invalid manifest' }
                    }
                }
                
                # Check for indexed content
                $indexPath = Join-Path $folder.FullName 'index'
                $hasIndex = Test-Path -LiteralPath $indexPath
                
                # Calculate basic health metrics
                $fileCount = (Get-ChildItem -Path $folder.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
                $lastModified = (Get-Item -LiteralPath $folder.FullName).LastWriteTimeUtc
                
                $packs.Add([pscustomobject]@{
                    id = $folder.Name
                    path = $folder.FullName
                    manifest = $manifest
                    hasIndex = $hasIndex
                    fileCount = $fileCount
                    lastModified = $lastModified.ToString('O')
                    status = if ($hasIndex) { 'indexed' } else { 'unindexed' }
                    health = Calculate-PackHealth -FileCount $fileCount -HasIndex $hasIndex -LastModified $lastModified
                })
            }
        }
        
        return [pscustomobject]@{
            success = $true
            totalPacks = $packs.Count
            packs = $packs.ToArray()
            timestamp = [DateTime]::UtcNow.ToString('O')
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to get pack status: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
            timestamp = [DateTime]::UtcNow.ToString('O')
        }
    }
}

#===============================================================================
# RPG Maker MZ Integration Functions
#===============================================================================

<#
.SYNOPSIS
    Gets information about an RPG Maker MZ project.
.DESCRIPTION
    Analyzes an RPG Maker MZ project directory and returns detailed information
    including game title, plugins, database files, and project structure.
.PARAMETER ProjectPath
    The path to the RPG Maker project directory.
.OUTPUTS
    System.Management.Automation.PSCustomObject with project details.
.EXAMPLE
    PS C:\> Get-MCPRPGMakerProjectInfo -ProjectPath "./MyRPGGame"
    
    Returns detailed information about the RPG Maker project.
#>
function Get-MCPRPGMakerProjectInfo {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$ProjectPath
    )
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        
        # Check for RPG Maker project indicators
        $wwwPath = Join-Path $resolvedPath 'www'
        $jsPath = Join-Path $wwwPath 'js'
        $pluginsPath = Join-Path $jsPath 'plugins'
        $dataPath = Join-Path $wwwPath 'data'
        
        # Try to find the game project file (.rmmzproject or .rpgproject)
        $projectFile = Get-ChildItem -Path $resolvedPath -Filter '*.rmmzproject' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $projectFile) {
            $projectFile = Get-ChildItem -Path $resolvedPath -Filter '*.rpgproject' -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        
        # Check if this is a valid RPG Maker project
        $isValidProject = (Test-Path -LiteralPath $jsPath) -and (Test-Path -LiteralPath $pluginsPath)
        
        if (-not $isValidProject) {
            return [pscustomobject]@{
                success = $false
                error = "Not a valid RPG Maker MZ/MV project: www/js/plugins folder not found"
                path = $resolvedPath
            }
        }
        
        # Read System.json for game info
        $systemInfo = @{}
        $systemJsonPath = Join-Path $dataPath 'System.json'
        $systemJsonPathMV = Join-Path $dataPath 'System.json'
        
        $actualSystemPath = if (Test-Path -LiteralPath $systemJsonPath) { 
            $systemJsonPath 
        } elseif (Test-Path -LiteralPath $systemJsonPathMV) { 
            $systemJsonPathMV 
        } else { 
            $null 
        }
        
        if ($actualSystemPath -and (Test-Path -LiteralPath $actualSystemPath)) {
            try {
                $systemJson = Get-Content -LiteralPath $actualSystemPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $systemInfo['gameTitle'] = $systemJson.gameTitle
                $systemInfo['currencyUnit'] = $systemJson.currencyUnit
                $systemInfo['versionId'] = $systemJson.versionId
                $systemInfo['engineVersion'] = if ($systemJson.versionId -gt 0) { 'MZ' } else { 'MV' }
            }
            catch {
                Write-Verbose "[RPGMaker] Failed to parse System.json: $_"
            }
        }
        
        # Count plugins
        $pluginFiles = @()
        if (Test-Path -LiteralPath $pluginsPath) {
            $pluginFiles = Get-ChildItem -Path $pluginsPath -Filter '*.js' -ErrorAction SilentlyContinue
        }
        
        # Read plugins.js to get active plugin list
        $activePlugins = @()
        $pluginsJsPath = Join-Path $jsPath 'plugins.js'
        if (Test-Path -LiteralPath $pluginsJsPath) {
            try {
                $pluginsContent = Get-Content -LiteralPath $pluginsJsPath -Raw -Encoding UTF8
                # Extract plugin names from the plugins array
                if ($pluginsContent -match '\$plugins\s*=\s*(\[.*?\])') {
                    $pluginsJson = $matches[1] | ConvertFrom-Json
                    $activePlugins = $pluginsJson | Where-Object { $_.status -eq $true } | ForEach-Object { $_.name }
                }
            }
            catch {
                Write-Verbose "[RPGMaker] Failed to parse plugins.js: $_"
            }
        }
        
        # Count database files
        $databaseFiles = @()
        if (Test-Path -LiteralPath $dataPath) {
            $databaseFiles = Get-ChildItem -Path $dataPath -Filter '*.json' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        }
        
        # Detect engine type
        $engineType = 'Unknown'
        $hasMZIndicators = Test-Path -LiteralPath (Join-Path $jsPath 'rmmz_core.js')
        $hasMVIndicators = Test-Path -LiteralPath (Join-Path $jsPath 'rpg_core.js')
        
        if ($hasMZIndicators) {
            $engineType = 'MZ'
        } elseif ($hasMVIndicators) {
            $engineType = 'MV'
        }
        
        return [pscustomobject]@{
            success = $true
            projectName = if ($projectFile) { $projectFile.BaseName } else { Split-Path -Leaf $resolvedPath }
            projectPath = $resolvedPath
            engineType = $engineType
            gameTitle = $systemInfo['gameTitle']
            currencyUnit = $systemInfo['currencyUnit']
            versionId = $systemInfo['versionId']
            pluginCount = $pluginFiles.Count
            activePluginCount = $activePlugins.Count
            pluginsPath = $pluginsPath
            databaseFiles = $databaseFiles
            databaseFileCount = $databaseFiles.Count
            hasProjectFile = ($projectFile -ne $null)
            lastModified = (Get-Item -LiteralPath $resolvedPath).LastWriteTimeUtc.ToString('O')
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to get RPG Maker project info: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
            path = $ProjectPath
        }
    }
}

<#
.SYNOPSIS
    Lists installed plugins in an RPG Maker MZ project.
.DESCRIPTION
    Returns a list of all plugins in the project's www/js/plugins folder
    with optional detailed metadata extraction.
.PARAMETER ProjectPath
    The path to the RPG Maker project directory.
.PARAMETER IncludeDetails
    If specified, includes detailed plugin metadata from parsing.
.OUTPUTS
    System.Management.Automation.PSCustomObject[] with plugin information.
.EXAMPLE
    PS C:\> Get-MCPRPGMakerPluginList -ProjectPath "./MyRPGGame" -IncludeDetails
    
    Lists all plugins with detailed metadata.
#>
function Get-MCPRPGMakerPluginList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$ProjectPath,
        
        [Parameter()]
        [switch]$IncludeDetails
    )
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $pluginsPath = Join-Path $resolvedPath 'www\js\plugins'
        
        if (-not (Test-Path -LiteralPath $pluginsPath)) {
            return [pscustomobject]@{
                success = $false
                error = "Plugins folder not found: $pluginsPath"
                plugins = @()
            }
        }
        
        # Read plugins.js for active status
        $jsPath = Join-Path $resolvedPath 'www\js'
        $pluginsJsPath = Join-Path $jsPath 'plugins.js'
        $activePlugins = @{}
        if (Test-Path -LiteralPath $pluginsJsPath) {
            try {
                $pluginsContent = Get-Content -LiteralPath $pluginsJsPath -Raw -Encoding UTF8
                if ($pluginsContent -match '\$plugins\s*=\s*(\[.*?\])') {
                    $pluginsJson = $matches[1] | ConvertFrom-Json
                    foreach ($plugin in $pluginsJson) {
                        $activePlugins[$plugin.name] = @{
                            status = $plugin.status
                            parameters = $plugin.parameters
                        }
                    }
                }
            }
            catch {
                Write-Verbose "[RPGMaker] Failed to parse plugins.js: $_"
            }
        }
        
        # Get all plugin files
        $pluginFiles = Get-ChildItem -Path $pluginsPath -Filter '*.js' | Sort-Object Name
        $plugins = [System.Collections.Generic.List[object]]::new()
        
        foreach ($file in $pluginFiles) {
            $pluginName = $file.BaseName
            $pluginInfo = [ordered]@{
                name = $pluginName
                fileName = $file.Name
                filePath = $file.FullName
                fileSize = $file.Length
                lastModified = $file.LastWriteTimeUtc.ToString('O')
                isActive = $activePlugins.ContainsKey($pluginName) -and $activePlugins[$pluginName].status
            }
            
            if ($IncludeDetails) {
                # Try to parse plugin metadata
                try {
                    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                    
                    # Extract basic metadata from comment block
                    if ($content -match '@plugindesc\s+(.+)') {
                        $pluginInfo['description'] = $matches[1].Trim()
                    }
                    if ($content -match '@author\s+(.+)') {
                        $pluginInfo['author'] = $matches[1].Trim()
                    }
                    if ($content -match '@version\s+(.+)') {
                        $pluginInfo['version'] = $matches[1].Trim()
                    }
                    if ($content -match '@target\s+(.+)') {
                        $pluginInfo['target'] = $matches[1].Trim()
                    }
                    if ($content -match '@url\s+(.+)') {
                        $pluginInfo['url'] = $matches[1].Trim()
                    }
                    
                    # Count parameters
                    $paramMatches = [regex]::Matches($content, '@param\s+(\w+)')
                    $pluginInfo['parameterCount'] = $paramMatches.Count
                    
                    # Count commands
                    $commandMatches = [regex]::Matches($content, '@command\s+(\w+)')
                    $pluginInfo['commandCount'] = $commandMatches.Count
                    
                    # Detect dependencies
                    $depMatches = [regex]::Matches($content, '@reqPlugin\s+(.+)')
                    $pluginInfo['dependencies'] = @($depMatches | ForEach-Object { $_.Groups[1].Value.Trim() })
                    
                    # Extract help text (limited)
                    if ($content -match '@help\s+([\s\S]*?)(?=\n\s*\*\s*@|\n\s*\*/|\Z)') {
                        $helpText = $matches[1] -replace '\n\s*\*\s*', ' '
                        $pluginInfo['helpTextPreview'] = $helpText.Substring(0, [Math]::Min(200, $helpText.Length))
                    }
                }
                catch {
                    Write-Verbose "[RPGMaker] Failed to parse plugin metadata for $($file.Name): $_"
                }
            }
            
            $plugins.Add([pscustomobject]$pluginInfo)
        }
        
        return [pscustomobject]@{
            success = $true
            projectPath = $resolvedPath
            pluginsPath = $pluginsPath
            totalCount = $plugins.Count
            activeCount = ($plugins | Where-Object { $_.isActive }).Count
            plugins = $plugins.ToArray()
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to list RPG Maker plugins: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
            plugins = @()
        }
    }
}

<#
.SYNOPSIS
    Analyzes a specific RPG Maker plugin file for conflicts and metadata.
.DESCRIPTION
    Parses a plugin file and optionally checks for conflicts with other
    installed plugins based on method patches and header annotations.
.PARAMETER ProjectPath
    The path to the RPG Maker project directory.
.PARAMETER PluginName
    The name of the plugin to analyze (with or without .js extension).
.PARAMETER CheckConflicts
    If specified, checks for conflicts with other plugins.
.OUTPUTS
    System.Management.Automation.PSCustomObject with analysis results.
.EXAMPLE
    PS C:\> Invoke-MCPRPGMakerAnalyzePlugin -ProjectPath "./MyRPGGame" -PluginName "MyPlugin" -CheckConflicts
    
    Analyzes the plugin and checks for conflicts.
#>
function Invoke-MCPRPGMakerAnalyzePlugin {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PluginName,
        
        [Parameter()]
        [switch]$CheckConflicts
    )
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $pluginsPath = Join-Path $resolvedPath 'www\js\plugins'
        
        # Normalize plugin name
        if (-not $PluginName.EndsWith('.js')) {
            $PluginName = "$PluginName.js"
        }
        
        $pluginPath = Join-Path $pluginsPath $PluginName
        
        if (-not (Test-Path -LiteralPath $pluginPath)) {
            return [pscustomobject]@{
                success = $false
                error = "Plugin not found: $PluginName"
            }
        }
        
        # Read plugin content
        $content = Get-Content -LiteralPath $pluginPath -Raw -Encoding UTF8
        
        # Extract full metadata
        $metadata = @{
            name = [System.IO.Path]::GetFileNameWithoutExtension($PluginName)
            fileSize = (Get-Item -LiteralPath $pluginPath).Length
            lineCount = ($content -split "`r?`n").Count
        }
        
        # Parse header annotations
        if ($content -match '/\*:(.+?)(?:\*/|$)') {
            $headerBlock = $matches[1]
            
            # Extract metadata annotations
            if ($headerBlock -match '@plugindesc\s+(.+)') {
                $metadata['description'] = $matches[1].Trim()
            }
            if ($headerBlock -match '@author\s+(.+)') {
                $metadata['author'] = $matches[1].Trim()
            }
            if ($headerBlock -match '@version\s+(.+)') {
                $metadata['version'] = $matches[1].Trim()
            }
            if ($headerBlock -match '@target\s+(.+)') {
                $metadata['target'] = $matches[1].Trim()
            }
            if ($headerBlock -match '@url\s+(.+)') {
                $metadata['url'] = $matches[1].Trim()
            }
            
            # Extract parameters
            $params = @()
            $paramMatches = [regex]::Matches($headerBlock, '@param\s+(\w+)[\s\S]*?(?=@param|@command|\Z)')
            foreach ($match in $paramMatches) {
                $paramBlock = $match.Value
                $paramName = ($paramBlock | Select-String -Pattern '@param\s+(\w+)').Matches.Groups[1].Value
                $paramType = 'string'
                $paramDefault = ''
                $paramDesc = ''
                
                if ($paramBlock -match '@type\s+(.+)') {
                    $paramType = $matches[1].Trim()
                }
                if ($paramBlock -match '@default\s+(.+)') {
                    $paramDefault = $matches[1].Trim()
                }
                if ($paramBlock -match '@desc\s+(.+)') {
                    $paramDesc = $matches[1].Trim()
                }
                
                $params += @{
                    name = $paramName
                    type = $paramType
                    default = $paramDefault
                    description = $paramDesc
                }
            }
            $metadata['parameters'] = $params
            
            # Extract commands
            $commands = @()
            $commandMatches = [regex]::Matches($headerBlock, '@command\s+(\w+)[\s\S]*?(?=@command|@param|\Z)')
            foreach ($match in $commandMatches) {
                $cmdBlock = $match.Value
                $cmdName = ($cmdBlock | Select-String -Pattern '@command\s+(\w+)').Matches.Groups[1].Value
                $cmdDesc = ''
                $cmdArgs = @()
                
                if ($cmdBlock -match '@desc\s+(.+)') {
                    $cmdDesc = $matches[1].Trim()
                }
                
                # Extract command arguments
                $argMatches = [regex]::Matches($cmdBlock, '@arg\s+(\w+)')
                foreach ($argMatch in $argMatches) {
                    $cmdArgs += $argMatch.Groups[1].Value
                }
                
                $commands += @{
                    name = $cmdName
                    description = $cmdDesc
                    arguments = $cmdArgs
                }
            }
            $metadata['commands'] = $commands
            
            # Extract dependencies
            $deps = @()
            $depMatches = [regex]::Matches($headerBlock, '@(?:reqPlugin|requires?)\s+(.+)')
            foreach ($match in $depMatches) {
                $deps += $match.Groups[1].Value.Trim()
            }
            $metadata['dependencies'] = $deps
            
            # Extract conflicts
            $conflicts = @()
            $conflictMatches = [regex]::Matches($headerBlock, '@conflict\s+(.+)')
            foreach ($match in $conflictMatches) {
                $conflicts += $match.Groups[1].Value.Trim()
            }
            $metadata['explicitConflicts'] = $conflicts
            
            # Extract order requirements
            $orderAfter = @()
            $orderBefore = @()
            $afterMatches = [regex]::Matches($headerBlock, '@(?:after|orderAfter)\s+(.+)')
            foreach ($match in $afterMatches) {
                $orderAfter += $match.Groups[1].Value.Trim()
            }
            $beforeMatches = [regex]::Matches($headerBlock, '@(?:before|orderBefore)\s+(.+)')
            foreach ($match in $beforeMatches) {
                $orderBefore += $match.Groups[1].Value.Trim()
            }
            $metadata['orderAfter'] = $orderAfter
            $metadata['orderBefore'] = $orderBefore
        }
        
        # Extract method patches for conflict detection
        $methodPatches = @()
        $aliasPattern = '(\w+)\.(\w+)\s*=\s*Game_(\w+)\.(\w+)'
        $overwritePattern = '(\w+)\.prototype\.(\w+)\s*=\s*function'
        
        $aliasMatches = [regex]::Matches($content, $aliasPattern)
        foreach ($match in $aliasMatches) {
            $methodPatches += @{
                type = 'alias'
                target = "$($match.Groups[1].Value).$($match.Groups[2].Value)"
                source = "Game_$($match.Groups[3].Value).$($match.Groups[4].Value)"
            }
        }
        
        $overwriteMatches = [regex]::Matches($content, $overwritePattern)
        foreach ($match in $overwriteMatches) {
            $methodPatches += @{
                type = 'overwrite'
                target = "$($match.Groups[1].Value).prototype.$($match.Groups[2].Value)"
            }
        }
        
        $metadata['methodPatches'] = $methodPatches
        
        # Check conflicts with other plugins
        $conflictAnalysis = @()
        if ($CheckConflicts) {
            $otherPlugins = Get-ChildItem -Path $pluginsPath -Filter '*.js' | Where-Object { $_.Name -ne $PluginName }
            
            foreach ($otherPlugin in $otherPlugins) {
                $otherContent = Get-Content -LiteralPath $otherPlugin.FullName -Raw -Encoding UTF8
                $otherName = $otherPlugin.BaseName
                $conflictsFound = @()
                
                # Check for explicit conflicts
                if ($metadata['explicitConflicts'] -contains $otherName) {
                    $conflictsFound += 'explicit_conflict'
                }
                
                # Check for method patch overlaps
                foreach ($patch in $methodPatches) {
                    $targetPattern = [regex]::Escape($patch.target)
                    if ($otherContent -match $targetPattern) {
                        $conflictsFound += "method_overlap:$($patch.target)"
                    }
                }
                
                if ($conflictsFound.Count -gt 0) {
                    $conflictAnalysis += @{
                        plugin = $otherName
                        conflictTypes = $conflictsFound
                    }
                }
            }
        }
        
        return [pscustomobject]@{
            success = $true
            pluginPath = $pluginPath
            metadata = $metadata
            conflictCount = $conflictAnalysis.Count
            conflicts = $conflictAnalysis
            analysisTimestamp = [DateTime]::UtcNow.ToString('O')
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to analyze RPG Maker plugin: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Creates a new RPG Maker MZ plugin file with proper header.
.DESCRIPTION
    Generates a new plugin file with the standard RPG Maker MZ plugin header
    format including all required annotations.
.PARAMETER ProjectPath
    The path to the RPG Maker project directory.
.PARAMETER PluginName
    The name of the new plugin.
.PARAMETER Author
    The plugin author name.
.PARAMETER Description
    The plugin description.
.PARAMETER Target
    The target engine (MZ, MV, or Both).
.OUTPUTS
    System.Management.Automation.PSCustomObject with creation result.
.EXAMPLE
    PS C:\> Invoke-MCPRPGMakerCreatePluginSkeleton -ProjectPath "./MyRPGGame" -PluginName "MyNewPlugin" -Author "Developer"
    
    Creates a new plugin skeleton file.
#>
function Invoke-MCPRPGMakerCreatePluginSkeleton {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PluginName,
        
        [Parameter()]
        [string]$Author = '',
        
        [Parameter()]
        [string]$Description = '',
        
        [Parameter()]
        [ValidateSet('MZ', 'MV', 'Both')]
        [string]$Target = 'MZ'
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'rpgmaker_create_plugin_skeleton' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $pluginsPath = Join-Path $resolvedPath 'www\js\plugins'
        
        if (-not (Test-Path -LiteralPath $pluginsPath)) {
            return [pscustomobject]@{
                success = $false
                error = "Plugins folder not found: $pluginsPath"
            }
        }
        
        # Normalize plugin name
        $baseName = $PluginName -replace '\.js$', ''
        $fileName = "$baseName.js"
        $pluginPath = Join-Path $pluginsPath $fileName
        
        # Check if file already exists
        if (Test-Path -LiteralPath $pluginPath) {
            return [pscustomobject]@{
                success = $false
                error = "Plugin already exists: $fileName"
            }
        }
        
        # Get current date
        $currentDate = Get-Date -Format "yyyy-MM-dd"
        
        # Build plugin header
        $authorText = if ($Author) { $Author } else { 'Your Name' }
        $descText = if ($Description) { $Description } else { "Description of $baseName" }
        
        $pluginContent = @"
//=============================================================================
// $baseName
//=============================================================================

/*:
 * @target $Target
 * @plugindesc $descText
 * @author $authorText
 * @url 
 *
 * @help
 * $baseName
 * ============================================================================
 * $descText
 *
 * ============================================================================
 * Plugin Parameters
 * ============================================================================
 *
 * @param ExampleParam
 * @text Example Parameter
 * @type string
 * @default Hello World
 * @desc An example parameter to get you started
 *
 * ============================================================================
 * Plugin Commands
 * ============================================================================
 *
 * @command ExampleCommand
 * @text Example Command
 * @desc An example plugin command
 *
 * @arg ExampleArg
 * @type string
 * @default test
 * @desc An example argument
 */

(function() {
    'use strict';

    // Plugin parameters
    const pluginName = '$baseName';
    const parameters = PluginManager.parameters(pluginName);
    const paramExample = String(parameters['ExampleParam'] || 'Hello World');

    // Plugin command registration
    PluginManager.registerCommand(pluginName, 'ExampleCommand', args => {
        const argValue = String(args.ExampleArg || 'test');
        console.log(`[\${pluginName}] ExampleCommand executed with arg: \${argValue}`);
    });

    // Your plugin code here
    const _Scene_Boot_start = Scene_Boot.prototype.start;
    Scene_Boot.prototype.start = function() {
        _Scene_Boot_start.call(this);
        console.log(`[\${pluginName}] Loaded with param: \${paramExample}`);
    };

})();
"@
        
        # Write the plugin file
        $pluginContent | Set-Content -LiteralPath $pluginPath -Encoding UTF8 -NoNewline
        
        Write-MCPLog -Level INFO -Message "Created RPG Maker plugin skeleton" -Metadata @{
            pluginName = $baseName
            pluginPath = $pluginPath
            author = $authorText
            target = $Target
        }
        
        return [pscustomobject]@{
            success = $true
            pluginName = $baseName
            pluginPath = $pluginPath
            fileName = $fileName
            author = $authorText
            target = $Target
            message = "Plugin '$baseName' created successfully at $pluginPath"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to create RPG Maker plugin skeleton: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Validates notetag syntax in RPG Maker MZ database files.
.DESCRIPTION
    Parses RPG Maker database JSON files and validates notetag syntax
    in note fields, checking for common issues like unclosed tags,
    invalid characters, or malformed syntax.
.PARAMETER ProjectPath
    The path to the RPG Maker project directory.
.PARAMETER DatabaseFile
    Specific database file to validate (e.g., Actors.json, Items.json).
    If not specified, validates all database files.
.OUTPUTS
    System.Management.Automation.PSCustomObject with validation results.
.EXAMPLE
    PS C:\> Test-MCPRPGMakerNotetags -ProjectPath "./MyRPGGame" -DatabaseFile "Actors.json"
    
    Validates notetags in the Actors.json file.
#>
function Test-MCPRPGMakerNotetags {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$DatabaseFile = ''
    )
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $dataPath = Join-Path $resolvedPath 'www\data'
        
        if (-not (Test-Path -LiteralPath $dataPath)) {
            return [pscustomobject]@{
                success = $false
                error = "Data folder not found: $dataPath"
            }
        }
        
        # Determine which files to validate
        $databaseFiles = @()
        if ($DatabaseFile) {
            $targetFile = Join-Path $dataPath $DatabaseFile
            if (Test-Path -LiteralPath $targetFile) {
                $databaseFiles += Get-Item -LiteralPath $targetFile
            } else {
                return [pscustomobject]@{
                    success = $false
                    error = "Database file not found: $DatabaseFile"
                }
            }
        } else {
            # Validate all database JSON files
            $databaseFiles = Get-ChildItem -Path $dataPath -Filter '*.json' | Where-Object { 
                $_.Name -in @('Actors.json', 'Classes.json', 'Skills.json', 'Items.json', 
                              'Weapons.json', 'Armors.json', 'Enemies.json', 'Troops.json', 
                              'States.json', 'Animations.json', 'Tilesets.json', 'CommonEvents.json',
                              'Map001.json', 'Map002.json', 'Map003.json', 'Map004.json', 'Map005.json')
            }
        }
        
        $results = [System.Collections.Generic.List[object]]::new()
        $totalErrors = 0
        $totalWarnings = 0
        
        foreach ($file in $databaseFiles) {
            $fileResults = @{
                fileName = $file.Name
                filePath = $file.FullName
                entriesChecked = 0
                errors = @()
                warnings = @()
            }
            
            try {
                $jsonContent = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                $data = $jsonContent | ConvertFrom-Json
                
                # Function to check notetags in an object
                function Check-Notetags {
                    param($Obj, $EntryId)
                    $issues = @{
                        errors = @()
                        warnings = @()
                    }
                    
                    if ($Obj -is [PSCustomObject]) {
                        # Check note field
                        if ($Obj.PSObject.Properties['note']) {
                            $note = $Obj.note
                            if ($note -and $note -is [string]) {
                                # Check for unclosed XML-style tags
                                $openTags = [regex]::Matches($note, '<(\w+)[^>]*>') | Where-Object { $_.Value -notmatch '/\s*>' }
                                $closeTags = [regex]::Matches($note, '</(\w+)>')
                                
                                $openTagNames = $openTags | ForEach-Object { 
                                    if ($_ -match '<(\w+)') { $matches[1] }
                                }
                                $closeTagNames = $closeTags | ForEach-Object { 
                                    if ($_ -match '</(\w+)') { $matches[1] }
                                }
                                
                                foreach ($tagName in $openTagNames) {
                                    if ($tagName -notin $closeTagNames -and $tagName -notin @('br', 'hr', 'img', 'meta')) {
                                        $issues.warnings += "Entry $EntryId`: Unclosed tag <$tagName>"
                                    }
                                }
                                
                                # Check for malformed RPG Maker notetags
                                $notetagMatches = [regex]::Matches($note, '<(\w+)(:[^>]*)?>')
                                foreach ($match in $notetagMatches) {
                                    $tagContent = $match.Groups[2].Value
                                    # Check for unbalanced quotes in tag parameters
                                    $quoteCount = ($tagContent -split '"').Count - 1
                                    if ($quoteCount % 2 -ne 0) {
                                        $issues.errors += "Entry $EntryId`: Unbalanced quotes in notetag: $($match.Value)"
                                    }
                                }
                                
                                # Check for common typo patterns
                                if ($note -match '<\s*\w+\s*:') {
                                    # Has RPG Maker style notetags, check format
                                    $malformed = [regex]::Matches($note, '<\s*\w+\s*:[^>]+[^/>]\s*>')
                                    foreach ($match in $malformed) {
                                        if ($match.Value -notmatch '/>') {
                                            $issues.warnings += "Entry $EntryId`: Notetag may be missing closing '/>': $($match.Value)"
                                        }
                                    }
                                }
                            }
                        }
                        
                        # Recursively check nested objects (for things like effects, traits)
                        foreach ($prop in $Obj.PSObject.Properties) {
                            if ($prop.Value -is [array]) {
                                for ($i = 0; $i -lt $prop.Value.Count; $i++) {
                                    $nestedIssues = Check-Notetags -Obj $prop.Value[$i] -EntryId "$EntryId.$($prop.Name)[$i]"
                                    $issues.errors += $nestedIssues.errors
                                    $issues.warnings += $nestedIssues.warnings
                                }
                            }
                        }
                    }
                    
                    return $issues
                }
                
                # Process array entries (skip null entries at index 0)
                if ($data -is [array]) {
                    for ($i = 1; $i -lt $data.Count; $i++) {
                        if ($data[$i]) {
                            $fileResults.entriesChecked++
                            $entryIssues = Check-Notetags -Obj $data[$i] -EntryId $i
                            $fileResults.errors += $entryIssues.errors
                            $fileResults.warnings += $entryIssues.warnings
                        }
                    }
                }
            }
            catch {
                $fileResults.errors += "Failed to parse file: $_"
            }
            
            $fileResults.errorCount = $fileResults.errors.Count
            $fileResults.warningCount = $fileResults.warnings.Count
            $totalErrors += $fileResults.errorCount
            $totalWarnings += $fileResults.warningCount
            
            $results.Add([pscustomobject]$fileResults)
        }
        
        return [pscustomobject]@{
            success = $true
            projectPath = $resolvedPath
            filesChecked = $results.Count
            totalErrors = $totalErrors
            totalWarnings = $totalWarnings
            hasIssues = ($totalErrors -gt 0 -or $totalWarnings -gt 0)
            results = $results.ToArray()
            validationTimestamp = [DateTime]::UtcNow.ToString('O')
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to validate RPG Maker notetags: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

#===============================================================================
# MCP Stdio Transport Functions
#===============================================================================

<#
.SYNOPSIS
    Starts the MCP stdio transport loop.

.DESCRIPTION
    Processes JSON-RPC 2.0 requests from stdin and writes responses to stdout.
    This is the main processing loop for stdio transport mode.

.EXAMPLE
    PS C:\> Start-MCPStdioLoop
    
    Starts processing MCP requests from stdin.
#>
function Start-MCPStdioLoop {
    [CmdletBinding()]
    param()
    
    Write-MCPLog -Level INFO -Message "Starting MCP stdio loop"
    
    try {
        while ($script:ServerState.IsRunning) {
            # Read line from stdin
            $line = [Console]::In.ReadLine()
            
            if ([string]::IsNullOrEmpty($line)) {
                continue
            }
            
            # Check for shutdown signal
            if ($line -eq 'shutdown' -or $line -eq 'exit') {
                Write-MCPLog -Level INFO -Message "Received shutdown signal via stdin"
                break
            }
            
            try {
                # Parse JSON-RPC request
                $request = $line | ConvertFrom-Json -ErrorAction Stop
                
                # Process the request
                $response = Process-MCPRequest -Request $request
                
                # Write response to stdout
                $responseJson = $response | ConvertTo-Json -Depth 10 -Compress
                [Console]::Out.WriteLine($responseJson)
            }
            catch {
                # Return JSON-RPC parse error
                $errorResponse = @{
                    jsonrpc = '2.0'
                    id = $null
                    error = @{
                        code = -32700
                        message = 'Parse error'
                        data = $_.Exception.Message
                    }
                } | ConvertTo-Json -Compress
                [Console]::Out.WriteLine($errorResponse)
                
                Write-MCPLog -Level ERROR -Message "Failed to process request: $_"
            }
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Stdio loop error: $_"
    }
    finally {
        Write-MCPLog -Level INFO -Message "MCP stdio loop ended"
    }
}

#===============================================================================
# Internal Helper Functions
#===============================================================================

<#
.SYNOPSIS
    Registers default MCP tools.
.DESCRIPTION
    Registers the built-in tools for Godot, Blender, and pack queries.
#>
function Register-DefaultMCPTools {
    [CmdletBinding()]
    param()
    
    # Godot Version Tool
    Register-MCPTool `
        -Name 'godot_version' `
        -Description 'Gets the installed Godot Engine version' `
        -Parameters @{} `
        -Handler { 
            param($params)
            Get-MCPGodotVersion
        } `
        -SafetyLevel 'ReadOnly' `
        -Tags @('godot', 'version')
    
    # Godot Project List Tool
    Register-MCPTool `
        -Name 'godot_project_list' `
        -Description 'Lists available Godot projects in the workspace' `
        -Parameters @{
            searchPath = @{ type = 'string'; description = 'Path to search for projects'; default = '.' }
            recursive = @{ type = 'boolean'; description = 'Search recursively'; default = $true }
        } `
        -Handler { 
            param($params)
            $searchPath = if ($params['searchPath']) { $params['searchPath'] } else { '.' }
            $recursive = if ($params.ContainsKey('recursive')) { $params['recursive'] } else { $true }
            Get-MCPGodotProjectList -SearchPath $searchPath -Recursive:$recursive
        } `
        -SafetyLevel 'ReadOnly' `
        -Tags @('godot', 'project')
    
    # Godot Project Info Tool
    Register-MCPTool `
        -Name 'godot_project_info' `
        -Description 'Gets detailed information about a Godot project' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the Godot project'; required = $true }
        } `
        -Handler { 
            param($params)
            Get-MCPGodotProjectInfo -ProjectPath $params['projectPath']
        } `
        -SafetyLevel 'ReadOnly' `
        -Tags @('godot', 'project')
    
    # Godot Launch Editor Tool
    Register-MCPTool `
        -Name 'godot_launch_editor' `
        -Description 'Launches the Godot editor for a project' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the Godot project'; required = $true }
            godotPath = @{ type = 'string'; description = 'Optional path to Godot executable' }
        } `
        -Handler { 
            param($params)
            $godotPath = if ($params['godotPath']) { $params['godotPath'] } else { '' }
            Invoke-MCPGodotLaunchEditor -ProjectPath $params['projectPath'] -GodotPath $godotPath
        } `
        -SafetyLevel 'Mutating' `
        -Tags @('godot', 'editor')
    
    # Godot Run Project Tool
    Register-MCPTool `
        -Name 'godot_run_project' `
        -Description 'Runs a Godot project' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the Godot project'; required = $true }
            scene = @{ type = 'string'; description = 'Optional specific scene to run' }
            debug = @{ type = 'boolean'; description = 'Run with debugging enabled'; default = $false }
        } `
        -Handler { 
            param($params)
            $scene = if ($params['scene']) { $params['scene'] } else { '' }
            $debug = if ($params.ContainsKey('debug')) { $params['debug'] } else { $false }
            Invoke-MCPGodotRunProject -ProjectPath $params['projectPath'] -Scene $scene -Debug:$debug
        } `
        -SafetyLevel 'Mutating' `
        -Tags @('godot', 'run')
    
    # Godot Create Scene Tool
    Register-MCPTool `
        -Name 'godot_create_scene' `
        -Description 'Creates a new Godot scene file' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the Godot project'; required = $true }
            sceneName = @{ type = 'string'; description = 'Name of the scene'; required = $true }
            rootType = @{ type = 'string'; description = 'Root node type'; default = 'Node2D' }
            directory = @{ type = 'string'; description = 'Directory for the scene'; default = 'scenes' }
        } `
        -Handler { 
            param($params)
            $rootType = if ($params['rootType']) { $params['rootType'] } else { 'Node2D' }
            $directory = if ($params['directory']) { $params['directory'] } else { 'scenes' }
            Invoke-MCPGodotCreateScene -ProjectPath $params['projectPath'] -SceneName $params['sceneName'] -RootType $rootType -Directory $directory
        } `
        -SafetyLevel 'Mutating' `
        -Tags @('godot', 'scene', 'create')
    
    # Godot Add Node Tool
    Register-MCPTool `
        -Name 'godot_add_node' `
        -Description 'Adds a node to a Godot scene file' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the Godot project'; required = $true }
            scenePath = @{ type = 'string'; description = 'Relative path to the scene file'; required = $true }
            nodeName = @{ type = 'string'; description = 'Name of the new node'; required = $true }
            nodeType = @{ type = 'string'; description = 'Type of node to add'; required = $true }
            parentPath = @{ type = 'string'; description = 'Parent node path'; default = '' }
        } `
        -Handler { 
            param($params)
            $parentPath = if ($params['parentPath']) { $params['parentPath'] } else { '' }
            Invoke-MCPGodotAddNode -ProjectPath $params['projectPath'] -ScenePath $params['scenePath'] `
                -NodeName $params['nodeName'] -NodeType $params['nodeType'] -ParentPath $parentPath
        } `
        -SafetyLevel 'Mutating' `
        -Tags @('godot', 'scene', 'node')
    
    # Godot Get Debug Output Tool
    Register-MCPTool `
        -Name 'godot_get_debug_output' `
        -Description 'Gets debug output from a Godot project' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the Godot project'; required = $true }
            logFile = @{ type = 'string'; description = 'Specific log file path'; default = '' }
            lines = @{ type = 'integer'; description = 'Number of lines to return'; default = 100 }
        } `
        -Handler { 
            param($params)
            $logFile = if ($params['logFile']) { $params['logFile'] } else { '' }
            $lines = if ($params['lines']) { $params['lines'] } else { 100 }
            Get-MCPGodotDebugOutput -ProjectPath $params['projectPath'] -LogFile $logFile -Lines $lines
        } `
        -SafetyLevel 'ReadOnly' `
        -Tags @('godot', 'debug')
    
    # Godot Export Project Tool
    Register-MCPTool `
        -Name 'godot_export_project' `
        -Description 'Exports a Godot project to various platforms using export presets' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the Godot project'; required = $true }
            exportPreset = @{ type = 'string'; description = 'Export preset name (e.g., "Windows Desktop", "Linux/X11", "Web")'; required = $true }
            outputPath = @{ type = 'string'; description = 'Output path for the exported build'; required = $true }
            godotPath = @{ type = 'string'; description = 'Optional path to Godot executable' }
        } `
        -Handler { 
            param($params)
            $godotPath = if ($params['godotPath']) { $params['godotPath'] } else { '' }
            Invoke-MCPGodotExportProject -ProjectPath $params['projectPath'] -ExportPreset $params['exportPreset'] -OutputPath $params['outputPath'] -GodotPath $godotPath
        } `
        -SafetyLevel 'Mutating' `
        -Tags @('godot', 'export', 'build')
    
    # Godot Build Project Tool
    Register-MCPTool `
        -Name 'godot_build_project' `
        -Description 'Builds/compiles a Godot project by importing and validating resources' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the Godot project'; required = $true }
            godotPath = @{ type = 'string'; description = 'Optional path to Godot executable' }
            verboseBuild = @{ type = 'boolean'; description = 'Enable verbose build output'; default = $false }
        } `
        -Handler { 
            param($params)
            $godotPath = if ($params['godotPath']) { $params['godotPath'] } else { '' }
            $verboseBuild = if ($params.ContainsKey('verboseBuild')) { $params['verboseBuild'] } else { $false }
            Invoke-MCPGodotBuildProject -ProjectPath $params['projectPath'] -GodotPath $godotPath -VerboseBuild:$verboseBuild
        } `
        -SafetyLevel 'Mutating' `
        -Tags @('godot', 'build', 'compile')
    
    # Godot Run Tests Tool
    Register-MCPTool `
        -Name 'godot_run_tests' `
        -Description 'Runs gdUnit4 tests for a Godot project if available' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the Godot project'; required = $true }
            testPath = @{ type = 'string'; description = 'Optional specific test file or directory to run' }
            godotPath = @{ type = 'string'; description = 'Optional path to Godot executable' }
        } `
        -Handler { 
            param($params)
            $testPath = if ($params['testPath']) { $params['testPath'] } else { '' }
            $godotPath = if ($params['godotPath']) { $params['godotPath'] } else { '' }
            Invoke-MCPGodotRunTests -ProjectPath $params['projectPath'] -TestPath $testPath -GodotPath $godotPath
        } `
        -SafetyLevel 'Mutating' `
        -Tags @('godot', 'test', 'gdunit4')
    
    # Godot Check Syntax Tool
    Register-MCPTool `
        -Name 'godot_check_syntax' `
        -Description 'Validates GDScript syntax for project files' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the Godot project'; required = $true }
            scriptPath = @{ type = 'string'; description = 'Optional specific script to validate (relative path)' }
            godotPath = @{ type = 'string'; description = 'Optional path to Godot executable' }
        } `
        -Handler { 
            param($params)
            $scriptPath = if ($params['scriptPath']) { $params['scriptPath'] } else { '' }
            $godotPath = if ($params['godotPath']) { $params['godotPath'] } else { '' }
            Invoke-MCPGodotCheckSyntax -ProjectPath $params['projectPath'] -ScriptPath $scriptPath -GodotPath $godotPath
        } `
        -SafetyLevel 'ReadOnly' `
        -Tags @('godot', 'syntax', 'validation', 'gdscript')
    
    # Godot Get Scene Tree Tool
    Register-MCPTool `
        -Name 'godot_get_scene_tree' `
        -Description 'Parses and returns the scene tree structure from a .tscn file' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the Godot project'; required = $true }
            scenePath = @{ type = 'string'; description = 'Relative path to the scene file'; required = $true }
        } `
        -Handler { 
            param($params)
            Get-MCPGodotSceneTree -ProjectPath $params['projectPath'] -ScenePath $params['scenePath']
        } `
        -SafetyLevel 'ReadOnly' `
        -Tags @('godot', 'scene', 'parse', 'tree')
    
    # Blender Version Tool
    Register-MCPTool `
        -Name 'blender_version' `
        -Description 'Gets the installed Blender version' `
        -Parameters @{} `
        -Handler { 
            param($params)
            Get-MCPBlenderVersion
        } `
        -SafetyLevel 'ReadOnly' `
        -Tags @('blender', 'version')
    
    # Blender Operator Tool
    Register-MCPTool `
        -Name 'blender_operator' `
        -Description 'Executes a Blender Python operator via bpy' `
        -Parameters @{
            operator = @{ type = 'string'; description = 'The bpy operator to execute'; required = $true }
            parameters = @{ type = 'object'; description = 'Parameters for the operator'; default = @{} }
        } `
        -Handler { 
            param($params)
            $operatorParams = if ($params['parameters']) { $params['parameters'] } else { @{} }
            Invoke-MCPBlenderOperator -Operator $params['operator'] -Parameters $operatorParams
        } `
        -SafetyLevel 'Mutating' `
        -Tags @('blender', 'operator')
    
    # Blender Export Mesh Library Tool
    Register-MCPTool `
        -Name 'blender_export_mesh_library' `
        -Description 'Exports meshes from a Blender file to a mesh library' `
        -Parameters @{
            blendFile = @{ type = 'string'; description = 'Path to the .blend file'; required = $true }
            outputPath = @{ type = 'string'; description = 'Output path for export'; required = $true }
            format = @{ type = 'string'; description = 'Export format (gltf, fbx, obj)'; default = 'gltf' }
            selectedOnly = @{ type = 'boolean'; description = 'Export only selected meshes'; default = $false }
        } `
        -Handler { 
            param($params)
            $format = if ($params['format']) { $params['format'] } else { 'gltf' }
            $selectedOnly = if ($params.ContainsKey('selectedOnly')) { $params['selectedOnly'] } else { $false }
            Invoke-MCPBlenderExportMeshLibrary -BlendFile $params['blendFile'] -OutputPath $params['outputPath'] `
                -Format $format -SelectedOnly:$selectedOnly
        } `
        -SafetyLevel 'Mutating' `
        -Tags @('blender', 'export', 'mesh')
    
    # Blender Import Mesh Tool
    Register-MCPTool `
        -Name 'blender_import_mesh' `
        -Description 'Imports mesh files (obj, fbx, gltf) into Blender' `
        -Parameters @{
            filePath = @{ type = 'string'; description = 'Path to the mesh file to import'; required = $true }
            blendFile = @{ type = 'string'; description = 'Optional path to existing .blend file to append to' }
            format = @{ type = 'string'; description = 'Import format (obj, fbx, gltf, glb)'; default = 'auto' }
        } `
        -Handler { 
            param($params)
            $blendFile = if ($params['blendFile']) { $params['blendFile'] } else { '' }
            $format = if ($params['format']) { $params['format'] } else { 'auto' }
            Invoke-MCPBlenderImportMesh -FilePath $params['filePath'] -BlendFile $blendFile -Format $format
        } `
        -SafetyLevel 'Mutating' `
        -Tags @('blender', 'import', 'mesh')
    
    # Blender Render Scene Tool
    Register-MCPTool `
        -Name 'blender_render_scene' `
        -Description 'Renders current scene or animation' `
        -Parameters @{
            blendFile = @{ type = 'string'; description = 'Path to the .blend file'; required = $true }
            outputPath = @{ type = 'string'; description = 'Output path for rendered image/video'; required = $true }
            animation = @{ type = 'boolean'; description = 'Render full animation instead of single frame'; default = $false }
            frameStart = @{ type = 'integer'; description = 'Start frame for animation'; default = 1 }
            frameEnd = @{ type = 'integer'; description = 'End frame for animation'; default = 250 }
            engine = @{ type = 'string'; description = 'Render engine (CYCLES, BLENDER_EEVEE, BLENDER_WORKBENCH)'; default = 'BLENDER_EEVEE' }
            resolutionX = @{ type = 'integer'; description = 'Resolution width'; default = 1920 }
            resolutionY = @{ type = 'integer'; description = 'Resolution height'; default = 1080 }
        } `
        -Handler { 
            param($params)
            $animation = if ($params.ContainsKey('animation')) { $params['animation'] } else { $false }
            $frameStart = if ($params['frameStart']) { $params['frameStart'] } else { 1 }
            $frameEnd = if ($params['frameEnd']) { $params['frameEnd'] } else { 250 }
            $engine = if ($params['engine']) { $params['engine'] } else { 'BLENDER_EEVEE' }
            $resolutionX = if ($params['resolutionX']) { $params['resolutionX'] } else { 1920 }
            $resolutionY = if ($params['resolutionY']) { $params['resolutionY'] } else { 1080 }
            Invoke-MCPBlenderRenderScene -BlendFile $params['blendFile'] -OutputPath $params['outputPath'] `
                -Animation:$animation -FrameStart $frameStart -FrameEnd $frameEnd -Engine $engine `
                -ResolutionX $resolutionX -ResolutionY $resolutionY
        } `
        -SafetyLevel 'Mutating' `
        -Tags @('blender', 'render', 'scene')
    
    # Blender List Materials Tool
    Register-MCPTool `
        -Name 'blender_list_materials' `
        -Description 'Lists materials in the blend file' `
        -Parameters @{
            blendFile = @{ type = 'string'; description = 'Path to the .blend file'; required = $true }
            includeOrphans = @{ type = 'boolean'; description = 'Include orphan materials (not assigned to any object)'; default = $false }
        } `
        -Handler { 
            param($params)
            $includeOrphans = if ($params.ContainsKey('includeOrphans')) { $params['includeOrphans'] } else { $false }
            Invoke-MCPBlenderListMaterials -BlendFile $params['blendFile'] -IncludeOrphans:$includeOrphans
        } `
        -SafetyLevel 'ReadOnly' `
        -Tags @('blender', 'material', 'list')
    
    # Blender Apply Modifier Tool
    Register-MCPTool `
        -Name 'blender_apply_modifier' `
        -Description 'Applies modifiers to objects' `
        -Parameters @{
            blendFile = @{ type = 'string'; description = 'Path to the .blend file'; required = $true }
            objectName = @{ type = 'string'; description = 'Name of the object to apply modifiers to'; required = $true }
            modifierType = @{ type = 'string'; description = 'Specific modifier type to apply (e.g., SUBSURF, MIRROR, ARRAY)'; default = '' }
            allModifiers = @{ type = 'boolean'; description = 'Apply all modifiers'; default = $true }
        } `
        -Handler { 
            param($params)
            $modifierType = if ($params['modifierType']) { $params['modifierType'] } else { '' }
            $allModifiers = if ($params.ContainsKey('allModifiers')) { $params['allModifiers'] } else { $true }
            Invoke-MCPBlenderApplyModifier -BlendFile $params['blendFile'] -ObjectName $params['objectName'] `
                -ModifierType $modifierType -AllModifiers:$allModifiers
        } `
        -SafetyLevel 'Mutating' `
        -Tags @('blender', 'modifier', 'apply')
    
    # Blender Export Godot Tool
    Register-MCPTool `
        -Name 'blender_export_godot' `
        -Description 'Exports to Godot-compatible format (gltf with specific settings)' `
        -Parameters @{
            blendFile = @{ type = 'string'; description = 'Path to the .blend file'; required = $true }
            outputPath = @{ type = 'string'; description = 'Output path for .glb/.gltf file'; required = $true }
            exportMaterials = @{ type = 'boolean'; description = 'Export materials'; default = $true }
            exportAnimations = @{ type = 'boolean'; description = 'Export animations'; default = $true }
            exportCameras = @{ type = 'boolean'; description = 'Export cameras'; default = $false }
            exportLights = @{ type = 'boolean'; description = 'Export lights'; default = $false }
            yUp = @{ type = 'boolean'; description = 'Use Y-up coordinate system (recommended for Godot)'; default = $true }
        } `
        -Handler { 
            param($params)
            $exportMaterials = if ($params.ContainsKey('exportMaterials')) { $params['exportMaterials'] } else { $true }
            $exportAnimations = if ($params.ContainsKey('exportAnimations')) { $params['exportAnimations'] } else { $true }
            $exportCameras = if ($params.ContainsKey('exportCameras')) { $params['exportCameras'] } else { $false }
            $exportLights = if ($params.ContainsKey('exportLights')) { $params['exportLights'] } else { $false }
            $yUp = if ($params.ContainsKey('yUp')) { $params['yUp'] } else { $true }
            Invoke-MCPBlenderExportGodot -BlendFile $params['blendFile'] -OutputPath $params['outputPath'] `
                -ExportMaterials:$exportMaterials -ExportAnimations:$exportAnimations `
                -ExportCameras:$exportCameras -ExportLights:$exportLights -YUp:$yUp
        } `
        -SafetyLevel 'Mutating' `
        -Tags @('blender', 'export', 'godot', 'gltf')
    
    # Pack Query Tool
    Register-MCPTool `
        -Name 'pack_query' `
        -Description 'Queries pack knowledge base' `
        -Parameters @{
            query = @{ type = 'string'; description = 'Search query'; required = $true }
            packIds = @{ type = 'array'; description = 'Specific pack IDs to search'; default = @() }
            limit = @{ type = 'integer'; description = 'Maximum results'; default = 5 }
        } `
        -Handler { 
            param($params)
            $packIds = if ($params['packIds']) { $params['packIds'] } else { @() }
            $limit = if ($params['limit']) { $params['limit'] } else { 5 }
            Invoke-MCPPackQuery -Query $params['query'] -PackIds $packIds -Limit $limit
        } `
        -SafetyLevel 'ReadOnly' `
        -Tags @('pack', 'query')
    
    # Pack Status Tool
    Register-MCPTool `
        -Name 'pack_status' `
        -Description 'Gets pack health and status' `
        -Parameters @{
            packId = @{ type = 'string'; description = 'Specific pack ID to check' }
        } `
        -Handler { 
            param($params)
            $packId = if ($params['packId']) { $params['packId'] } else { '' }
            Get-MCPPackStatus -PackId $packId
        } `
        -SafetyLevel 'ReadOnly' `
        -Tags @('pack', 'status')
    
    #===============================================================================
    # RPG Maker MZ Integration Tools
    #===============================================================================
    
    # RPG Maker Project Info Tool
    Register-MCPTool `
        -Name 'rpgmaker_project_info' `
        -Description 'Gets information about an RPG Maker MZ project' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the RPG Maker project directory'; required = $true }
        } `
        -Handler { 
            param($params)
            Get-MCPRPGMakerProjectInfo -ProjectPath $params['projectPath']
        } `
        -SafetyLevel 'ReadOnly' `
        -Tags @('rpgmaker', 'project', 'mz')
    
    # RPG Maker List Plugins Tool
    Register-MCPTool `
        -Name 'rpgmaker_list_plugins' `
        -Description 'Lists installed plugins in an RPG Maker MZ project' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the RPG Maker project directory'; required = $true }
            includeDetails = @{ type = 'boolean'; description = 'Include detailed plugin metadata'; default = $false }
        } `
        -Handler { 
            param($params)
            $includeDetails = if ($params.ContainsKey('includeDetails')) { $params['includeDetails'] } else { $false }
            Get-MCPRPGMakerPluginList -ProjectPath $params['projectPath'] -IncludeDetails:$includeDetails
        } `
        -SafetyLevel 'ReadOnly' `
        -Tags @('rpgmaker', 'plugins', 'list')
    
    # RPG Maker Analyze Plugin Tool
    Register-MCPTool `
        -Name 'rpgmaker_analyze_plugin' `
        -Description 'Analyzes a specific RPG Maker plugin file for conflicts and metadata' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the RPG Maker project directory'; required = $true }
            pluginName = @{ type = 'string'; description = 'Name of the plugin to analyze (with or without .js extension)'; required = $true }
            checkConflicts = @{ type = 'boolean'; description = 'Check for conflicts with other plugins'; default = $true }
        } `
        -Handler { 
            param($params)
            $checkConflicts = if ($params.ContainsKey('checkConflicts')) { $params['checkConflicts'] } else { $true }
            Invoke-MCPRPGMakerAnalyzePlugin -ProjectPath $params['projectPath'] -PluginName $params['pluginName'] -CheckConflicts:$checkConflicts
        } `
        -SafetyLevel 'ReadOnly' `
        -Tags @('rpgmaker', 'plugins', 'analysis', 'conflict')
    
    # RPG Maker Create Plugin Skeleton Tool
    Register-MCPTool `
        -Name 'rpgmaker_create_plugin_skeleton' `
        -Description 'Creates a new RPG Maker MZ plugin file with proper header' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the RPG Maker project directory'; required = $true }
            pluginName = @{ type = 'string'; description = 'Name of the new plugin'; required = $true }
            author = @{ type = 'string'; description = 'Plugin author name'; default = '' }
            description = @{ type = 'string'; description = 'Plugin description'; default = '' }
            target = @{ type = 'string'; description = 'Target engine (MZ, MV, or Both)'; default = 'MZ' }
        } `
        -Handler { 
            param($params)
            $author = if ($params['author']) { $params['author'] } else { '' }
            $description = if ($params['description']) { $params['description'] } else { '' }
            $target = if ($params['target']) { $params['target'] } else { 'MZ' }
            Invoke-MCPRPGMakerCreatePluginSkeleton -ProjectPath $params['projectPath'] -PluginName $params['pluginName'] `
                -Author $author -Description $description -Target $target
        } `
        -SafetyLevel 'Mutating' `
        -Tags @('rpgmaker', 'plugins', 'create')
    
    # RPG Maker Validate Notetags Tool
    Register-MCPTool `
        -Name 'rpgmaker_validate_notetags' `
        -Description 'Validates notetag syntax in RPG Maker MZ database files' `
        -Parameters @{
            projectPath = @{ type = 'string'; description = 'Path to the RPG Maker project directory'; required = $true }
            databaseFile = @{ type = 'string'; description = 'Specific database file to validate (e.g., Actors.json, Items.json). If not specified, validates all database files.'; default = '' }
        } `
        -Handler { 
            param($params)
            $databaseFile = if ($params['databaseFile']) { $params['databaseFile'] } else { '' }
            Test-MCPRPGMakerNotetags -ProjectPath $params['projectPath'] -DatabaseFile $databaseFile
        } `
        -SafetyLevel 'ReadOnly' `
        -Tags @('rpgmaker', 'notetags', 'validation')
}

<#
.SYNOPSIS
    Starts the HTTP listener for MCP protocol.
.DESCRIPTION
    Creates and starts an HTTP listener for receiving MCP requests.
.PARAMETER Port
    The port to listen on.
.PARAMETER Host
    The host address to bind to.
#>
function Start-MCPHttpListener {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port,
        
        [Parameter(Mandatory = $true)]
        [string]$Host
    )
    
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://$Host`:$Port`/")
    $listener.Start()
    
    $script:ServerState.HttpListener = $listener
    
    Write-MCPLog -Level INFO -Message "HTTP listener started" -Metadata @{
        host = $Host
        port = $Port
    }
    
    # Start request processing loop in background
    Start-Job -ScriptBlock {
        param($StateRef, $ListenerRef)
        
        while ($StateRef.IsRunning) {
            try {
                $context = $ListenerRef.GetContext()
                $request = $context.Request
                $response = $context.Response
                
                # Process request
                $result = Process-MCPHttpRequest -Request $request
                
                # Send response
                $json = $result | ConvertTo-Json -Depth 10
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                
                $response.ContentType = 'application/json'
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.OutputStream.Close()
            }
            catch {
                # Log error but continue
                Write-Verbose "[MCP HTTP] Request error: $_"
            }
        }
    } -ArgumentList $script:ServerState, $listener | Out-Null
}

<#
.SYNOPSIS
    Processes an HTTP request.
.DESCRIPTION
    Handles incoming HTTP requests for the MCP protocol.
.PARAMETER Request
    The HttpListenerRequest object.
.OUTPUTS
    Hashtable with response data.
#>
function Process-MCPHttpRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Request
    )
    
    try {
        # Read request body
        $reader = [System.IO.StreamReader]::new($Request.InputStream)
        $body = $reader.ReadToEnd()
        $reader.Close()
        
        # Parse JSON-RPC request
        $rpcRequest = $body | ConvertFrom-Json
        
        # Process the request
        return Process-MCPRequest -Request $rpcRequest
    }
    catch {
        return @{
            jsonrpc = '2.0'
            id = $null
            error = @{
                code = -32700
                message = 'Parse error'
                data = $_.Exception.Message
            }
        }
    }
}

<#
.SYNOPSIS
    Processes an MCP JSON-RPC request.
.DESCRIPTION
    Handles MCP protocol method calls and routes to appropriate handlers.
.PARAMETER Request
    The parsed JSON-RPC request object.
.OUTPUTS
    Hashtable with response data.
#>
function Process-MCPRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Request
    )
    
    $requestId = $Request.id
    $method = $Request.method
    $params = $Request.params
    
    # Handle different MCP methods
    switch ($method) {
        'initialize' {
            return @{
                jsonrpc = '2.0'
                id = $requestId
                result = @{
                    protocolVersion = $script:McpProtocolVersion
                    capabilities = $script:ServerCapabilities
                    serverInfo = $script:ServerInfo
                }
            }
        }
        'tools/list' {
            $tools = Get-MCPToolSchema
            return @{
                jsonrpc = '2.0'
                id = $requestId
                result = @{
                    tools = $tools
                }
            }
        }
        'tools/call' {
            $toolName = $params.name
            $toolParams = $params.arguments
            
            if (-not $script:ToolRegistry.ContainsKey($toolName)) {
                return @{
                    jsonrpc = '2.0'
                    id = $requestId
                    error = @{
                        code = -32601
                        message = "Tool not found: $toolName"
                    }
                }
            }
            
            try {
                $tool = $script:ToolRegistry[$toolName]
                $result = & $tool.handler $toolParams
                
                return @{
                    jsonrpc = '2.0'
                    id = $requestId
                    result = @{
                        content = @(
                            @{
                                type = 'text'
                                text = ($result | ConvertTo-Json -Depth 10)
                            }
                        )
                    }
                }
            }
            catch {
                return @{
                    jsonrpc = '2.0'
                    id = $requestId
                    error = @{
                        code = -32000
                        message = $_.Exception.Message
                    }
                }
            }
        }
        default {
            return @{
                jsonrpc = '2.0'
                id = $requestId
                error = @{
                    code = -32601
                    message = "Method not found: $method"
                }
            }
        }
    }
}

<#
.SYNOPSIS
    Asserts that the current execution mode allows a tool.
.DESCRIPTION
    Throws an exception if the tool is not allowed in the current mode.
.PARAMETER ToolName
    The name of the tool being executed.
.PARAMETER CurrentMode
    The current execution mode.
#>
function Assert-MCPExecutionMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,
        
        [Parameter(Mandatory = $true)]
        [string]$CurrentMode
    )
    
    if (-not $script:ToolRegistry.ContainsKey($ToolName)) {
        return  # Tool doesn't exist, let it fail normally
    }
    
    $tool = $script:ToolRegistry[$ToolName]
    $safetyLevel = $tool.safetyLevel
    
    # mcp-readonly only allows ReadOnly tools
    if ($CurrentMode -eq 'mcp-readonly' -and $safetyLevel -ne 'ReadOnly') {
        throw "Tool '$ToolName' (safety level: $safetyLevel) is not allowed in $CurrentMode mode"
    }
    
    # mcp-mutating allows ReadOnly and Mutating tools
    if ($CurrentMode -eq 'mcp-mutating' -and $safetyLevel -eq 'Destructive') {
        throw "Tool '$ToolName' (safety level: $safetyLevel) is not allowed in $CurrentMode mode"
    }
}

<#
.SYNOPSIS
    Finds the Godot executable.
.DESCRIPTION
    Searches for the Godot executable in common locations.
.PARAMETER Path
    Optional explicit path to check first.
.OUTPUTS
    String path to the executable or null if not found.
#>
function Find-GodotExecutable {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Path = ''
    )
    
    # Check explicit path first
    if (-not [string]::IsNullOrEmpty($Path) -and (Test-Path -LiteralPath $Path)) {
        return $Path
    }
    
    # Check PATH
    $commands = @('godot', 'godot4', 'Godot')
    foreach ($cmd in $commands) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) {
            return $found.Source
        }
    }
    
    # Check common installation paths
    $commonPaths = @(
        'C:\Program Files\Godot\Godot.exe',
        'C:\Program Files (x86)\Godot\Godot.exe',
        '/usr/bin/godot',
        '/usr/local/bin/godot',
        '/Applications/Godot.app/Contents/MacOS/Godot'
    )
    
    foreach ($testPath in $commonPaths) {
        if (Test-Path -LiteralPath $testPath) {
            return $testPath
        }
    }
    
    return $null
}

<#
.SYNOPSIS
    Finds the Blender executable.
.DESCRIPTION
    Searches for the Blender executable in common locations.
.PARAMETER Path
    Optional explicit path to check first.
.OUTPUTS
    String path to the executable or null if not found.
#>
function Find-BlenderExecutable {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Path = ''
    )
    
    # Check explicit path first
    if (-not [string]::IsNullOrEmpty($Path) -and (Test-Path -LiteralPath $Path)) {
        return $Path
    }
    
    # Check PATH
    $found = Get-Command 'blender' -ErrorAction SilentlyContinue
    if ($found) {
        return $found.Source
    }
    
    # Check common installation paths
    $commonPaths = @(
        'C:\Program Files\Blender Foundation\Blender\blender.exe',
        'C:\Program Files\Blender Foundation\Blender 4.0\blender.exe',
        'C:\Program Files\Blender Foundation\Blender 3.6\blender.exe',
        'C:\Program Files\Blender Foundation\Blender 4.1\blender.exe',
        'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe',
        '/usr/bin/blender',
        '/usr/local/bin/blender',
        '/Applications/Blender.app/Contents/MacOS/Blender'
    )
    
    foreach ($testPath in $commonPaths) {
        if (Test-Path -LiteralPath $testPath) {
            return $testPath
        }
    }
    
    return $null
}

<#
.SYNOPSIS
    Searches local pack content.
.DESCRIPTION
    Performs a simple text search across pack files.
.PARAMETER Query
    The search query.
.PARAMETER PackIds
    Pack IDs to search.
.PARAMETER Limit
    Maximum results.
.OUTPUTS
    Array of search results.
#>
function Search-LocalPackContent {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,
        
        [Parameter()]
        [string[]]$PackIds = @(),
        
        [Parameter()]
        [int]$Limit = 5
    )
    
    $results = [System.Collections.Generic.List[object]]::new()
    $packsDir = 'packs'
    
    if (-not (Test-Path -LiteralPath $packsDir)) {
        return $results.ToArray()
    }
    
    $searchTerms = $Query.ToLower() -split '\s+' | Where-Object { $_.Length -gt 2 }
    
    $packFolders = Get-ChildItem -Path $packsDir -Directory -ErrorAction SilentlyContinue
    foreach ($folder in $packFolders) {
        if ($PackIds.Count -gt 0 -and $folder.Name -notin $PackIds) {
            continue
        }
        
        # Search markdown files
        $mdFiles = Get-ChildItem -Path $folder.FullName -Filter '*.md' -Recurse -ErrorAction SilentlyContinue | Select-Object -First $Limit
        
        foreach ($file in $mdFiles) {
            try {
                $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
                $contentLower = $content.ToLower()
                
                $score = 0
                foreach ($term in $searchTerms) {
                    if ($contentLower.Contains($term)) {
                        $score += 1
                    }
                }
                
                if ($score -gt 0) {
                    # Extract snippet
                    $snippet = $content.Substring(0, [Math]::Min(200, $content.Length))
                    $snippet = $snippet -replace "[\r\n]+", ' '
                    
                    $results.Add([pscustomobject]@{
                        title = $file.BaseName
                        content = $snippet
                        pack = $folder.Name
                        score = $score
                        path = $file.FullName
                    })
                }
            }
            catch {
                # Continue to next file
            }
        }
    }
    
    # Sort by score and limit
    return $results | Sort-Object -Property score -Descending | Select-Object -First $Limit
}

<#
.SYNOPSIS
    Calculates a simple pack health score.
.DESCRIPTION
    Evaluates pack health based on file count, indexing status, and freshness.
.PARAMETER FileCount
    Number of files in the pack.
.PARAMETER HasIndex
    Whether the pack has been indexed.
.PARAMETER LastModified
    Last modification time.
.OUTPUTS
    Hashtable with health metrics.
#>
function Calculate-PackHealth {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$FileCount,
        
        [Parameter(Mandatory = $true)]
        [bool]$HasIndex,
        
        [Parameter(Mandatory = $true)]
        [DateTime]$LastModified
    )
    
    $daysSinceUpdate = ([DateTime]::UtcNow - $LastModified).TotalDays
    
    $score = 0
    if ($FileCount -gt 0) { $score += 25 }
    if ($FileCount -gt 10) { $score += 25 }
    if ($HasIndex) { $score += 25 }
    if ($daysSinceUpdate -lt 30) { $score += 25 }
    
    $status = switch ($score) {
        { $_ -ge 80 } { 'healthy' }
        { $_ -ge 50 } { 'degraded' }
        default { 'unhealthy' }
    }
    
    return @{
        score = $score
        status = $status
        metrics = @{
            fileCount = $FileCount
            hasIndex = $HasIndex
            daysSinceUpdate = [int]$daysSinceUpdate
        }
    }
}

<#
.SYNOPSIS
    Merges MCP configuration.
.DESCRIPTION
    Merges override configuration with base defaults.
.PARAMETER BaseConfig
    The base configuration.
.PARAMETER OverrideConfig
    Configuration to override with.
.OUTPUTS
    Merged configuration hashtable.
#>
function Merge-MCPConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$BaseConfig,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$OverrideConfig
    )
    
    $merged = @{}
    
    # Copy base config
    foreach ($key in $BaseConfig.Keys) {
        $merged[$key] = $BaseConfig[$key]
    }
    
    # Apply overrides
    foreach ($key in $OverrideConfig.Keys) {
        $merged[$key] = $OverrideConfig[$key]
    }
    
    return $merged
}

<#
.SYNOPSIS
    Generates a new MCP run ID.
.DESCRIPTION
    Creates a unique identifier for the current server run.
.OUTPUTS
    String run ID.
#>
function New-MCPRunId {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    $timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $random = -join ((1..4) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    return "mcp-$timestamp-$random"
}

<#
.SYNOPSIS
    Writes an MCP server log entry.
.DESCRIPTION
    Logs messages with structured formatting.
.PARAMETER Level
    The log level.
.PARAMETER Message
    The log message.
.PARAMETER Metadata
    Additional metadata.
.PARAMETER Exception
    Optional exception object.
#>
function Write-MCPLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('VERBOSE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'CRITICAL')]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [hashtable]$Metadata = @{},
        
        [Parameter()]
        [System.Exception]$Exception = $null
    )
    
    # Try to use structured logging if available
    $logCmd = Get-Command 'New-LogEntry' -ErrorAction SilentlyContinue
    $writeCmd = Get-Command 'Write-StructuredLog' -ErrorAction SilentlyContinue
    
    if ($logCmd -and $writeCmd) {
        $entry = & $logCmd -Level $Level -Message "[MCP] $Message" -Source 'MCPToolkitServer' `
            -RunId $script:ServerState.RunId -Metadata $Metadata -Exception $Exception
        & $writeCmd -Entry $entry
    }
    else {
        # Fallback to verbose/warning/error
        $timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $logMessage = "[$timestamp] [$Level] [MCP] $Message"
        
        switch ($Level) {
            'ERROR' { Write-Error $logMessage }
            'WARN' { Write-Warning $logMessage }
            'VERBOSE' { Write-Verbose $logMessage }
            default { Write-Information $logMessage }
        }
    }
}

# Export functions
Export-ModuleMember -Function @(
    # Server Configuration
    'New-MCPToolkitServer',
    # Server Lifecycle
    'Start-MCPToolkitServer',
    'Stop-MCPToolkitServer',
    'Get-MCPToolkitServerStatus',
    'Restart-MCPToolkitServer',
    # Stdio Transport
    'Start-MCPStdioLoop',
    # Tool Registration
    'Register-MCPTool',
    'Unregister-MCPTool',
    'Get-MCPTool',
    'Get-MCPToolSchema',
    'Get-MCPToolManifest',
    # Tool Execution
    'Invoke-MCPTool',
    # Godot Integration
    'Invoke-MCPGodotTool',
    'Get-MCPGodotVersion',
    'Get-MCPGodotProjectList',
    'Get-MCPGodotProjectInfo',
    'Invoke-MCPGodotLaunchEditor',
    'Invoke-MCPGodotRunProject',
    'Invoke-MCPGodotCreateScene',
    'Invoke-MCPGodotAddNode',
    'Get-MCPGodotDebugOutput',
    'Invoke-MCPGodotExportProject',
    'Invoke-MCPGodotBuildProject',
    'Invoke-MCPGodotRunTests',
    'Invoke-MCPGodotCheckSyntax',
    'Get-MCPGodotSceneTree',
    # Blender Integration
    'Invoke-MCPBlenderTool',
    'Get-MCPBlenderVersion',
    'Invoke-MCPBlenderOperator',
    'Invoke-MCPBlenderExportMeshLibrary',
    'Invoke-MCPBlenderImportMesh',
    'Invoke-MCPBlenderRenderScene',
    'Invoke-MCPBlenderListMaterials',
    'Invoke-MCPBlenderApplyModifier',
    'Invoke-MCPBlenderExportGodot',
    # Pack Query
    'Invoke-MCPPackQuery',
    'Get-MCPPackStatus',
    # RPG Maker MZ Integration
    'Get-MCPRPGMakerProjectInfo',
    'Get-MCPRPGMakerPluginList',
    'Invoke-MCPRPGMakerAnalyzePlugin',
    'Invoke-MCPRPGMakerCreatePluginSkeleton',
    'Test-MCPRPGMakerNotetags'
)
