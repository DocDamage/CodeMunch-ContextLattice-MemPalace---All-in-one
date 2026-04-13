#requires -Version 5.1
<#
.SYNOPSIS
    MCP Toolkit Server Tests for LLM Workflow Platform

.DESCRIPTION
    Comprehensive Pester v5 test suite for MCP modules:
    - MCPToolkitServer.ps1: Server start/stop, tool registration
    - Tool invocation with mocks
    - Parameter validation
    - Execution mode enforcement

.NOTES
    File: MCP.Tests.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Requires: Pester 5.0+
#>

BeforeAll {
    # Set up test environment
    $script:TestRoot = Join-Path $env:TEMP "LLMWorkflow_MCPTests_$([Guid]::NewGuid().ToString('N'))"
    $script:ModuleRoot = Join-Path $PSScriptRoot ".." "module" "LLMWorkflow"
    $script:McpModulePath = Join-Path $script:ModuleRoot "mcp"
    
    # Create test directory
    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    
    # Import MCP module by dot-sourcing
    $mcpServerPath = Join-Path $script:McpModulePath "MCPToolkitServer.ps1"
    if (Test-Path $mcpServerPath) { 
        . $mcpServerPath 
    }
}

AfterAll {
    # Ensure server is stopped
    if (Get-Command Stop-MCPToolkitServer -ErrorAction SilentlyContinue) {
        Stop-MCPToolkitServer -Force -ErrorAction SilentlyContinue | Out-Null
    }
    
    # Cleanup test directory
    if (Test-Path $script:TestRoot) {
        Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "MCPToolkitServer Module Tests" {
    
    BeforeEach {
        # Ensure server is stopped before each test
        if ($script:ServerState -and $script:ServerState.IsRunning) {
            Stop-MCPToolkitServer -Force -ErrorAction SilentlyContinue | Out-Null
        }
        # Clear tool registry
        if ($script:ToolRegistry) {
            $script:ToolRegistry.Clear()
        }
        Start-Sleep -Milliseconds 100
    }

    AfterEach {
        # Clean up after each test
        if ($script:ServerState -and $script:ServerState.IsRunning) {
            Stop-MCPToolkitServer -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    Context "New-MCPToolkitServer Function - Happy Path" {
        It "Should create server configuration with defaults" {
            $config = New-MCPToolkitServer
            
            $config | Should -Not -BeNullOrEmpty
            $config.name | Should -Be "llm-workflow-mcp-server"
            $config.version | Should -Be "0.2.0"
            $config.executionMode | Should -Be "mcp-readonly"
            $config.transport | Should -Be "stdio"
            $config.port | Should -Be 8080
            $config.host | Should -Be "localhost"
            $config.configId | Should -Not -BeNullOrEmpty
        }

        It "Should create server with custom configuration" {
            $config = New-MCPToolkitServer `
                -Name "custom-mcp-server" `
                -Version "1.0.0" `
                -ExecutionMode "mcp-mutating" `
                -ToolDefinitions @{ test = @{ name = "test" } }
            
            $config.name | Should -Be "custom-mcp-server"
            $config.version | Should -Be "1.0.0"
            $config.executionMode | Should -Be "mcp-mutating"
            $config.toolDefinitions | Should -Not -BeNullOrEmpty
        }

        It "Should support both execution modes" {
            $readonlyConfig = New-MCPToolkitServer -ExecutionMode "mcp-readonly"
            $mutatingConfig = New-MCPToolkitServer -ExecutionMode "mcp-mutating"
            
            $readonlyConfig.executionMode | Should -Be "mcp-readonly"
            $mutatingConfig.executionMode | Should -Be "mcp-mutating"
        }
    }

    Context "New-MCPToolkitServer Function - Error Cases" {
        It "Should throw on invalid execution mode" {
            { New-MCPToolkitServer -ExecutionMode "invalid-mode" } | Should -Throw
        }
    }

    Context "Start-MCPToolkitServer Function" {
        It "Should start server with stdio transport" {
            $status = Start-MCPToolkitServer -Transport "stdio"
            
            $status | Should -Not -BeNullOrEmpty
            $status.isRunning | Should -Be $true
            $status.transport | Should -Be "stdio"
            $status.executionMode | Should -Be "mcp-readonly"
            $status.runId | Should -Not -BeNullOrEmpty
        }

        It "Should start server with http transport" {
            $status = Start-MCPToolkitServer -Transport "http" -Port 18080
            
            $status | Should -Not -BeNullOrEmpty
            $status.isRunning | Should -Be $true
            $status.transport | Should -Be "http"
            $status.port | Should -Be 18080
            
            Stop-MCPToolkitServer -Force | Out-Null
        }

        It "Should return status if server is already running" {
            Start-MCPToolkitServer -Transport "stdio" | Out-Null
            
            $status = Start-MCPToolkitServer -Transport "stdio"
            
            # Should warn but not fail
            $status.isRunning | Should -Be $true
        }

        It "Should initialize with server configuration object" {
            $config = New-MCPToolkitServer -Name "test-server" -ExecutionMode "mcp-readonly"
            
            $status = Start-MCPToolkitServer -ServerConfig $config
            
            $status.isRunning | Should -Be $true
            $status.serverInfo.name | Should -Be "llm-workflow-mcp-server"
        }
    }

    Context "Stop-MCPToolkitServer Function" {
        It "Should stop running server" {
            Start-MCPToolkitServer -Transport "stdio" | Out-Null
            
            $stopped = Stop-MCPToolkitServer
            
            $stopped | Should -Be $true
            $script:ServerState.IsRunning | Should -Be $false
        }

        It "Should return true when server is not running" {
            Stop-MCPToolkitServer -Force -ErrorAction SilentlyContinue | Out-Null
            
            $stopped = Stop-MCPToolkitServer
            
            $stopped | Should -Be $true
        }

        It "Should force stop with -Force" {
            Start-MCPToolkitServer -Transport "stdio" | Out-Null
            
            $stopped = Stop-MCPToolkitServer -Force
            
            $stopped | Should -Be $true
        }
    }

    Context "Get-MCPToolkitServerStatus Function" {
        It "Should return status when server is running" {
            Start-MCPToolkitServer -Transport "stdio" -ExecutionMode "mcp-readonly" | Out-Null
            
            $status = Get-MCPToolkitServerStatus
            
            $status | Should -Not -BeNullOrEmpty
            $status.isRunning | Should -Be $true
            $status.transport | Should -Be "stdio"
            $status.executionMode | Should -Be "mcp-readonly"
            $status.registeredTools | Should -Not -BeNullOrEmpty
            $status.protocolVersion | Should -Not -BeNullOrEmpty
        }

        It "Should return status when server is not running" {
            Stop-MCPToolkitServer -Force -ErrorAction SilentlyContinue | Out-Null
            
            $status = Get-MCPToolkitServerStatus
            
            $status.isRunning | Should -Be $false
            $status.uptime | Should -BeNullOrEmpty
        }
    }

    Context "Restart-MCPToolkitServer Function" {
        It "Should restart with new configuration" {
            Start-MCPToolkitServer -Transport "stdio" -ExecutionMode "mcp-readonly" | Out-Null
            
            $newStatus = Restart-MCPToolkitServer -Transport "stdio" -ExecutionMode "mcp-mutating"
            
            $newStatus.isRunning | Should -Be $true
            $newStatus.executionMode | Should -Be "mcp-mutating"
        }

        It "Should preserve registered tools with -PreserveTools" {
            Start-MCPToolkitServer -Transport "stdio" | Out-Null
            
            # Register a test tool
            Register-MCPTool -Name "test-tool" -Description "Test tool" `
                -Parameters @{ param1 = @{ type = "string" } } `
                -Handler { param($params) @{ result = "test" } } | Out-Null
            
            $beforeTools = (Get-MCPToolkitServerStatus).registeredTools
            
            Restart-MCPToolkitServer -Transport "stdio" -PreserveTools | Out-Null
            
            $afterTools = (Get-MCPToolkitServerStatus).registeredTools
            $afterTools | Should -Contain "test-tool"
        }
    }

    Context "Register-MCPTool Function - Happy Path" {
        It "Should register a tool with basic parameters" {
            $tool = Register-MCPTool `
                -Name "echo" `
                -Description "Echoes back the input" `
                -Parameters @{ message = @{ type = "string" } } `
                -Handler { param($params) @{ message = $params.message } }
            
            $tool | Should -Not -BeNullOrEmpty
            $tool.name | Should -Be "echo"
            $tool.description | Should -Be "Echoes back the input"
            $tool.inputSchema | Should -Not -BeNullOrEmpty
            $tool.safetyLevel | Should -Be "ReadOnly"
        }

        It "Should register tool with all safety levels" {
            $readonlyTool = Register-MCPTool `
                -Name "readonly-tool" `
                -Description "Read-only tool" `
                -Parameters @{} `
                -Handler {} `
                -SafetyLevel "ReadOnly"
            
            $mutatingTool = Register-MCPTool `
                -Name "mutating-tool" `
                -Description "Mutating tool" `
                -Parameters @{} `
                -Handler {} `
                -SafetyLevel "Mutating"
            
            $destructiveTool = Register-MCPTool `
                -Name "destructive-tool" `
                -Description "Destructive tool" `
                -Parameters @{} `
                -Handler {} `
                -SafetyLevel "Destructive"
            
            $readonlyTool.safetyLevel | Should -Be "ReadOnly"
            $mutatingTool.safetyLevel | Should -Be "Mutating"
            $destructiveTool.safetyLevel | Should -Be "Destructive"
        }

        It "Should support tags" {
            $tool = Register-MCPTool `
                -Name "tagged-tool" `
                -Description "A tagged tool" `
                -Parameters @{} `
                -Handler {} `
                -Tags @("godot", "build")
            
            $tool.tags | Should -Contain "godot"
            $tool.tags | Should -Contain "build"
        }
    }

    Context "Register-MCPTool Function - Validation" {
        It "Should require name parameter" {
            { Register-MCPTool -Name "" -Description "Test" -Parameters @{} -Handler {} } | 
                Should -Throw
        }

        It "Should require description parameter" {
            { Register-MCPTool -Name "test" -Description "" -Parameters @{} -Handler {} } | 
                Should -Throw
        }

        It "Should create input schema with required fields" {
            $tool = Register-MCPTool `
                -Name "validation-test" `
                -Description "Test validation" `
                -Parameters @{
                    requiredParam = @{ type = "string"; required = $true }
                    optionalParam = @{ type = "string"; required = $false }
                } `
                -Handler {}
            
            $tool.inputSchema.required | Should -Contain "requiredParam"
            $tool.inputSchema.required | Should -Not -Contain "optionalParam"
        }
    }

    Context "Unregister-MCPTool Function" {
        It "Should unregister an existing tool" {
            Register-MCPTool -Name "unregister-test" -Description "Test" -Parameters @{} -Handler {} | Out-Null
            
            $result = Unregister-MCPTool -Name "unregister-test"
            
            $result | Should -Be $true
            $script:ToolRegistry.ContainsKey("unregister-test") | Should -Be $false
        }

        It "Should return false for non-existent tool" {
            $result = Unregister-MCPTool -Name "nonexistent-tool"
            
            $result | Should -Be $false
        }

        It "Should not allow unregistering built-in tools without -Force" {
            Start-MCPToolkitServer -Transport "stdio" | Out-Null
            
            # Try to unregister a built-in tool
            $result = Unregister-MCPTool -Name "pack_query"
            
            # Should fail without -Force
            $result | Should -Be $false
        }
    }

    Context "Get-MCPTool Function" {
        BeforeEach {
            Start-MCPToolkitServer -Transport "stdio" | Out-Null
            # Register test tools
            Register-MCPTool -Name "tool-1" -Description "Tool 1" -Parameters @{} -Handler {} -Tags @("tag1") -SafetyLevel "ReadOnly" | Out-Null
            Register-MCPTool -Name "tool-2" -Description "Tool 2" -Parameters @{} -Handler {} -Tags @("tag2") -SafetyLevel "Mutating" | Out-Null
        }

        It "Should return all registered tools" {
            $tools = Get-MCPTool
            
            $tools.Count | Should -BeGreaterThan 0
        }

        It "Should filter by name" {
            $tool = Get-MCPTool -Name "tool-1"
            
            $tool.Count | Should -Be 1
            $tool[0].name | Should -Be "tool-1"
        }

        It "Should filter by tag" {
            $tools = Get-MCPTool -Tag "tag1"
            
            $tools | ForEach-Object { $_.tags | Should -Contain "tag1" }
        }

        It "Should filter by safety level" {
            $tools = Get-MCPTool -SafetyLevel "ReadOnly"
            
            $tools | ForEach-Object { $_.safetyLevel | Should -Be "ReadOnly" }
        }

        It "Should not return handler in output" {
            $tool = Get-MCPTool -Name "tool-1"
            
            $tool[0].PSObject.Properties.Name | Should -Not -Contain "handler"
        }
    }

    Context "Get-MCPToolSchema Function" {
        It "Should return schema for all tools" {
            Start-MCPToolkitServer -Transport "stdio" | Out-Null
            
            $schema = Get-MCPToolSchema
            
            $schema | Should -Not -BeNullOrEmpty
            $schema.Count | Should -BeGreaterThan 0
        }
    }

    Context "Get-MCPToolManifest Function" {
        It "Should return complete manifest" {
            Start-MCPToolkitServer -Transport "stdio" | Out-Null
            
            $manifest = Get-MCPToolManifest
            
            $manifest | Should -Not -BeNullOrEmpty
            $manifest.serverInfo | Should -Not -BeNullOrEmpty
            $manifest.tools | Should -Not -BeNullOrEmpty
            $manifest.toolCount | Should -BeGreaterThan 0
            $manifest.generatedAt | Should -Not -BeNullOrEmpty
        }

        It "Should include stats when requested" {
            Start-MCPToolkitServer -Transport "stdio" | Out-Null
            
            $manifest = Get-MCPToolManifest -IncludeStats
            
            $manifest.tools[0].PSObject.Properties.Name | Should -Contain "executionCount"
        }
    }

    Context "Invoke-MCPTool Function - Happy Path" {
        BeforeEach {
            Start-MCPToolkitServer -Transport "stdio" -ExecutionMode "mcp-mutating" | Out-Null
        }

        It "Should invoke registered tool successfully" {
            Register-MCPTool `
                -Name "test-echo" `
                -Description "Test echo tool" `
                -Parameters @{ message = @{ type = "string" } } `
                -Handler { param($params) @{ result = $params.message } } | Out-Null
            
            $result = Invoke-MCPTool -ToolName "test-echo" -Parameters @{ message = "hello" } -SkipPolicyCheck
            
            $result.success | Should -Be $true
            $result.result | Should -Be "hello"
            $result.invocationId | Should -Not -BeNullOrEmpty
        }

        It "Should track tool execution stats" {
            Register-MCPTool `
                -Name "stats-test" `
                -Description "Stats test" `
                -Parameters @{} `
                -Handler { param($params) @{} } | Out-Null
            
            $beforeCount = $script:ToolRegistry["stats-test"].executionCount
            Invoke-MCPTool -ToolName "stats-test" -Parameters @{} -SkipPolicyCheck | Out-Null
            $afterCount = $script:ToolRegistry["stats-test"].executionCount
            
            $afterCount | Should -Be ($beforeCount + 1)
        }
    }

    Context "Invoke-MCPTool Function - Error Cases" {
        It "Should return error for non-existent tool" {
            Start-MCPToolkitServer -Transport "stdio" | Out-Null
            
            $result = Invoke-MCPTool -ToolName "nonexistent-tool" -Parameters @{}
            
            $result.success | Should -Be $false
            $result.errorCode | Should -Be "TOOL_NOT_FOUND"
        }

        It "Should validate parameters when SkipValidation is not set" {
            Start-MCPToolkitServer -Transport "stdio" -ExecutionMode "mcp-mutating" | Out-Null
            
            Register-MCPTool `
                -Name "validation-required" `
                -Description "Validation test" `
                -Parameters @{
                    required = @{ type = "string" }
                } `
                -Handler { param($params) @{} } | Out-Null
            
            $result = Invoke-MCPTool -ToolName "validation-required" -Parameters @{ wrongParam = "value" } -SkipPolicyCheck
            
            $result.success | Should -Be $false
            $result.errorCode | Should -Be "VALIDATION_ERROR"
        }
    }

    Context "Invoke-MCPTool Function - Execution Mode Enforcement" {
        It "Should block mutating tools in readonly mode" {
            Start-MCPToolkitServer -Transport "stdio" -ExecutionMode "mcp-readonly" | Out-Null
            
            Register-MCPTool `
                -Name "mutating-action" `
                -Description "Mutating action" `
                -Parameters @{} `
                -Handler { param($params) @{} } `
                -SafetyLevel "Mutating" | Out-Null
            
            $result = Invoke-MCPTool -ToolName "mutating-action" -Parameters @{}
            
            $result.success | Should -Be $false
            $result.errorCode | Should -Be "POLICY_DENIED"
        }

        It "Should allow readonly tools in readonly mode" {
            Start-MCPToolkitServer -Transport "stdio" -ExecutionMode "mcp-readonly" | Out-Null
            
            Register-MCPTool `
                -Name "readonly-action" `
                -Description "Readonly action" `
                -Parameters @{} `
                -Handler { param($params) @{ data = "result" } } `
                -SafetyLevel "ReadOnly" | Out-Null
            
            $result = Invoke-MCPTool -ToolName "readonly-action" -Parameters @{}
            
            $result.success | Should -Be $true
        }

        It "Should allow all tools in mutating mode" {
            Start-MCPToolkitServer -Transport "stdio" -ExecutionMode "mcp-mutating" | Out-Null
            
            Register-MCPTool `
                -Name "destructive-action" `
                -Description "Destructive action" `
                -Parameters @{} `
                -Handler { param($params) @{} } `
                -SafetyLevel "Destructive" | Out-Null
            
            $result = Invoke-MCPTool -ToolName "destructive-action" -Parameters @{} -SkipPolicyCheck
            
            $result.success | Should -Be $true
        }
    }

    Context "Test-MCPParameterSchema Function" {
        It "Should validate required parameters" {
            $schema = @{
                type = "object"
                properties = @{
                    requiredParam = @{ type = "string" }
                }
                required = @("requiredParam")
            }
            
            $result = Test-MCPParameterSchema -Parameters @{} -Schema $schema
            
            $result.valid | Should -Be $false
            $result.error | Should -Match "*required*"
        }

        It "Should validate parameter types" {
            $schema = @{
                type = "object"
                properties = @{
                    count = @{ type = "number" }
                }
            }
            
            $result = Test-MCPParameterSchema -Parameters @{ count = "not-a-number" } -Schema $schema
            
            $result.valid | Should -Be $false
        }

        It "Should pass validation with valid parameters" {
            $schema = @{
                type = "object"
                properties = @{
                    message = @{ type = "string" }
                    count = @{ type = "integer" }
                }
            }
            
            $result = Test-MCPParameterSchema -Parameters @{ message = "test"; count = 42 } -Schema $schema
            
            $result.valid | Should -Be $true
        }
    }

    Context "Assert-MCPExecutionMode Function" {
        It "Should not throw for allowed tool in mode" {
            { Assert-MCPExecutionMode -ToolName "readonly-tool" -CurrentMode "mcp-readonly" } | Should -Not -Throw
        }

        It "Should throw for disallowed tool in mode" {
            { Assert-MCPExecutionMode -ToolName "mutating-tool" -CurrentMode "mcp-readonly" } | Should -Throw
        }
    }

    Context "Write-MCPLog Function" {
        It "Should not throw when logging" {
            { Write-MCPLog -Level INFO -Message "Test message" } | Should -Not -Throw
            { Write-MCPLog -Level DEBUG -Message "Debug message" -Metadata @{ key = "value" } } | Should -Not -Throw
            { Write-MCPLog -Level ERROR -Message "Error message" -Exception (New-Object System.Exception("Test")) } | Should -Not -Throw
        }
    }

    Context "MCP JSON-RPC Functions" {
        It "Should create valid JSON-RPC request" {
            $request = New-MCPJsonRpcRequest -Method "tools/list" -Params @{}
            
            $request.jsonrpc | Should -Be "2.0"
            $request.method | Should -Be "tools/list"
            $request.id | Should -Not -BeNullOrEmpty
        }

        It "Should create valid JSON-RPC response" {
            $response = New-MCPJsonRpcResponse -Id 1 -Result @{ tools = @() }
            
            $response.jsonrpc | Should -Be "2.0"
            $response.id | Should -Be 1
            $response.result | Should -Not -BeNullOrEmpty
        }

        It "Should create valid JSON-RPC error" {
            $error = New-MCPJsonRpcError -Id 1 -Code -32600 -Message "Invalid request"
            
            $error.jsonrpc | Should -Be "2.0"
            $error.id | Should -Be 1
            $error.error.code | Should -Be -32600
            $error.error.message | Should -Be "Invalid request"
        }
    }
}
