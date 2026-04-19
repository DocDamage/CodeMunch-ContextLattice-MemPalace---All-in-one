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
