<#
.SYNOPSIS
    Manages MCP servers for LLM Workflow platform.

.DESCRIPTION
    Provides commands to start, stop, restart MCP servers, view server status,
    view logs, and update configurations for all pack MCP servers.

.PARAMETER Command
    Management command to execute: 'start', 'stop', 'restart', 'status', 'logs', 'config'.

.PARAMETER Server
    Target server: 'gateway', 'godot', 'blender', 'rpgmaker', or 'all'. Default: all.

.PARAMETER ConfigPath
    Path to configuration file for updates.

.PARAMETER ConfigKey
    Configuration key to update (for 'config' command).

.PARAMETER ConfigValue
    Configuration value to set (for 'config' command).

.PARAMETER LogLines
    Number of log lines to display. Default: 50.

.PARAMETER Follow
    Follow log output (tail -f equivalent).

.PARAMETER Force
    Force operation without confirmation.

.PARAMETER JsonOutput
    Output results as JSON.

.PARAMETER WaitForHealthy
    Wait for server to become healthy after start/restart.

.PARAMETER TimeoutSeconds
    Timeout for operations. Default: 60.

.EXAMPLE
    .\mcp-server-manager.ps1 -Command status

.EXAMPLE
    .\mcp-server-manager.ps1 -Command start -Server godot

.EXAMPLE
    .\mcp-server-manager.ps1 -Command logs -Server gateway -LogLines 100 -Follow

.EXAMPLE
    .\mcp-server-manager.ps1 -Command config -Server all -ConfigKey "port" -ConfigValue "9090"

.NOTES
    File Name      : mcp-server-manager.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Requires       : PowerShell 5.1+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('start', 'stop', 'restart', 'status', 'logs', 'config')]
    [string]$Command,

    [Parameter()]
    [ValidateSet('gateway', 'godot', 'blender', 'rpgmaker', 'all')]
    [string]$Server = 'all',

    [Parameter()]
    [string]$ConfigPath = "",

    [Parameter()]
    [string]$ConfigKey = "",

    [Parameter()]
    [string]$ConfigValue = "",

    [Parameter()]
    [int]$LogLines = 50,

    [Parameter()]
    [switch]$Follow,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$JsonOutput,

    [Parameter()]
    [switch]$WaitForHealthy,

    [Parameter()]
    [ValidateRange(1, 300)]
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = "Stop"
$script:ScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { (Split-Path -Parent $PSCommandPath) }

# =============================================================================
# Configuration
# =============================================================================

$script:ServerConfigs = @{
    gateway = @{
        Name = "Composite Gateway"
        ProcessName = "pwsh"
        ArgumentsPattern = "deploy-composite-gateway"
        DefaultPort = 8080
        LogPath = ".llm-workflow/logs"
        ConfigFile = "mcp-gateway.json"
    }
    godot = @{
        Name = "Godot MCP"
        ProcessName = "godot-mcp"
        ArgumentsPattern = "godot-mcp"
        DefaultPort = 8091
        LogPath = ".llm-workflow/logs"
        ConfigFile = "godot-mcp.json"
    }
    blender = @{
        Name = "Blender MCP"
        ProcessName = "blender"
        ArgumentsPattern = "blender-mcp"
        DefaultPort = 8092
        LogPath = ".llm-workflow/logs"
        ConfigFile = "blender-mcp.json"
    }
    rpgmaker = @{
        Name = "RPG Maker MZ MCP"
        ProcessName = "node"
        ArgumentsPattern = "rpgmaker-mcp"
        DefaultPort = 8093
        LogPath = ".llm-workflow/logs"
        ConfigFile = "rpgmaker-mcp.json"
    }
}

# =============================================================================
# Utility Functions
# =============================================================================

function Write-ManagerLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $logEntry = "[$timestamp] [MCP-Manager-$Level] $Message"
    
    switch ($Level) {
        'ERROR'   { Write-Host $logEntry -ForegroundColor Red }
        'WARN'    { Write-Host $logEntry -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $logEntry -ForegroundColor Green }
        default   { Write-Output $logEntry }
    }
}

function Get-TargetServers {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    if ($Server -eq 'all') {
        return @('gateway', 'godot', 'blender', 'rpgmaker')
    }
    return @($Server)
}

function Find-ServerProcess {
    [CmdletBinding()]
    [OutputType([System.Diagnostics.Process])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerKey
    )

    $config = $script:ServerConfigs[$ServerKey]
    if (-not $config) { return $null }

    # Try exact match first
    $processes = Get-Process -Name $config.ProcessName -ErrorAction SilentlyContinue | 
                 Where-Object { 
                     $_.CommandLine -like "*$($config.ArgumentsPattern)*" -or
                     $_.ProcessName -eq $config.ProcessName
                 }

    # For PowerShell scripts, look for specific arguments
    if (-not $processes -and $config.ProcessName -eq "pwsh") {
        $processes = Get-Process -Name "pwsh", "powershell" -ErrorAction SilentlyContinue | 
                     Where-Object { 
                         try {
                             $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine
                             $cmdLine -like "*$($config.ArgumentsPattern)*"
                         }
                         catch { $false }
                     }
    }

    return $processes | Select-Object -First 1
}

function Test-ServerHealth {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerKey
    )

    $config = $script:ServerConfigs[$ServerKey]
    if (-not $config) { return $false }

    try {
        $port = $config.DefaultPort
        if ($ServerKey -eq 'gateway') {
            $port = 8080
        }

        $response = Invoke-RestMethod -Uri "http://localhost:$port/health" `
                                      -Method GET `
                                      -TimeoutSec 5
        return ($response.status -eq 'healthy')
    }
    catch {
        return $false
    }
}

# =============================================================================
# Command Functions
# =============================================================================

function Invoke-StartCommand {
    [CmdletBinding()]
    param()

    $targets = Get-TargetServers
    $results = @()

    foreach ($target in $targets) {
        $config = $script:ServerConfigs[$target]
        Write-ManagerLog -Level INFO -Message "Starting $($config.Name)..."

        # Check if already running
        $existingProcess = Find-ServerProcess -ServerKey $target
        if ($existingProcess) {
            Write-ManagerLog -Level WARN -Message "$($config.Name) is already running (PID: $($existingProcess.Id))"
            $results += [PSCustomObject]@{
                Server = $target
                Action = "start"
                Success = $true
                Message = "Already running (PID: $($existingProcess.Id))"
                ProcessId = $existingProcess.Id
            }
            continue
        }

        try {
            # Determine startup script and arguments
            $scriptPath = Join-Path $script:ScriptRoot "deploy-$target-mcp.ps1"
            if (-not (Test-Path -LiteralPath $scriptPath)) {
                $scriptPath = Join-Path $script:ScriptRoot "deploy-composite-gateway.ps1"
            }

            if (-not (Test-Path -LiteralPath $scriptPath)) {
                throw "Deployment script not found for $target"
            }

            # Start the server
            $process = $null
            if ($target -eq 'gateway') {
                $process = Start-Process -FilePath "pwsh" `
                                         -ArgumentList @("-File", $scriptPath, "-Transport", "http", "-Port", $config.DefaultPort) `
                                         -WindowStyle Hidden `
                                         -PassThru
            }
            else {
                $process = Start-Process -FilePath "pwsh" `
                                         -ArgumentList @("-File", $scriptPath, "-Mode", "http", "-Port", $config.DefaultPort) `
                                         -WindowStyle Hidden `
                                         -PassThru
            }

            # Wait for health check if requested
            if ($WaitForHealthy) {
                Write-ManagerLog -Level INFO -Message "Waiting for $($config.Name) to become healthy..."
                $healthy = $false
                $attempts = 0
                $maxAttempts = [int]($TimeoutSeconds / 2)

                while (-not $healthy -and $attempts -lt $maxAttempts) {
                    Start-Sleep -Seconds 2
                    $healthy = Test-ServerHealth -ServerKey $target
                    $attempts++
                }

                if (-not $healthy) {
                    throw "Server failed to become healthy within $TimeoutSeconds seconds"
                }
            }

            Write-ManagerLog -Level SUCCESS -Message "$($config.Name) started successfully (PID: $($process.Id))"
            $results += [PSCustomObject]@{
                Server = $target
                Action = "start"
                Success = $true
                Message = "Started successfully"
                ProcessId = $process.Id
            }
        }
        catch {
            Write-ManagerLog -Level ERROR -Message "Failed to start $($config.Name): $_"
            $results += [PSCustomObject]@{
                Server = $target
                Action = "start"
                Success = $false
                Message = $_.Exception.Message
                ProcessId = $null
            }
        }
    }

    return $results
}

function Invoke-StopCommand {
    [CmdletBinding()]
    param()

    $targets = Get-TargetServers
    $results = @()

    foreach ($target in $targets) {
        $config = $script:ServerConfigs[$target]
        Write-ManagerLog -Level INFO -Message "Stopping $($config.Name)..."

        $process = Find-ServerProcess -ServerKey $target
        if (-not $process) {
            Write-ManagerLog -Level WARN -Message "$($config.Name) is not running"
            $results += [PSCustomObject]@{
                Server = $target
                Action = "stop"
                Success = $true
                Message = "Not running"
                ProcessId = $null
            }
            continue
        }

        try {
            # Try graceful shutdown first
            $process.CloseMainWindow() | Out-Null
            
            # Wait for process to exit
            if (-not $process.WaitForExit(5000)) {
                if ($Force) {
                    $process.Kill()
                    $process.WaitForExit(2000)
                }
                else {
                    Write-ManagerLog -Level WARN -Message "$($config.Name) did not exit gracefully. Use -Force to kill."
                }
            }

            Write-ManagerLog -Level SUCCESS -Message "$($config.Name) stopped successfully"
            $results += [PSCustomObject]@{
                Server = $target
                Action = "stop"
                Success = $true
                Message = "Stopped successfully"
                ProcessId = $process.Id
            }
        }
        catch {
            Write-ManagerLog -Level ERROR -Message "Failed to stop $($config.Name): $_"
            $results += [PSCustomObject]@{
                Server = $target
                Action = "stop"
                Success = $false
                Message = $_.Exception.Message
                ProcessId = $process.Id
            }
        }
    }

    return $results
}

function Invoke-RestartCommand {
    [CmdletBinding()]
    param()

    Write-ManagerLog -Level INFO -Message "Restarting servers..."
    
    # Stop first
    $stopResults = Invoke-StopCommand
    Start-Sleep -Seconds 2
    
    # Then start
    $startResults = Invoke-StartCommand

    return @($stopResults; $startResults)
}

function Invoke-StatusCommand {
    [CmdletBinding()]
    param()

    $targets = Get-TargetServers
    $results = @()

    foreach ($target in $targets) {
        $config = $script:ServerConfigs[$target]
        $process = Find-ServerProcess -ServerKey $target
        $healthy = if ($process) { Test-ServerHealth -ServerKey $target } else { $false }

        $status = if ($process) { 
            if ($healthy) { "Running (Healthy)" } else { "Running (Unhealthy)" }
        } else { 
            "Stopped" 
        }

        $results += [PSCustomObject]@{
            Server = $target
            Name = $config.Name
            Status = $status
            ProcessId = if ($process) { $process.Id } else { $null }
            CpuPercent = if ($process) { [math]::Round($process.CPU, 2) } else { $null }
            MemoryMB = if ($process) { [math]::Round($process.WorkingSet64 / 1MB, 2) } else { $null }
            StartTime = if ($process) { $process.StartTime.ToString('o') } else { $null }
            Port = $config.DefaultPort
            Healthy = $healthy
        }
    }

    return $results
}

function Invoke-LogsCommand {
    [CmdletBinding()]
    param()

    $config = $script:ServerConfigs[$Server]
    $logDirectory = Join-Path $script:ScriptRoot "..\.." | Join-Path -ChildPath $config.LogPath
    $logDirectory = Resolve-Path $logDirectory -ErrorAction SilentlyContinue

    if (-not $logDirectory) {
        Write-ManagerLog -Level ERROR -Message "Log directory not found"
        return
    }

    $logFiles = Get-ChildItem -Path $logDirectory -Filter "*.jsonl" | Sort-Object LastWriteTime -Descending

    if (-not $logFiles) {
        Write-ManagerLog -Level WARN -Message "No log files found"
        return
    }

    # Filter by server if specified
    if ($Server -ne 'all') {
        $logFiles = $logFiles | Where-Object { $_.Name -like "*$Server*" -or $_.Name -like "*gateway*" }
    }

    $targetLogFile = $logFiles | Select-Object -First 1

    if ($Follow) {
        # Tail -f equivalent
        Write-ManagerLog -Level INFO -Message "Following log file: $($targetLogFile.FullName)"
        Get-Content -LiteralPath $targetLogFile.FullName -Tail $LogLines -Wait
    }
    else {
        # Display last N lines
        Get-Content -LiteralPath $targetLogFile.FullName -Tail $LogLines | ForEach-Object {
            try {
                $entry = $_ | ConvertFrom-Json
                $timestamp = $entry.timestamp
                $level = $entry.level.PadRight(7)
                $message = $entry.message
                Write-Output "[$timestamp] [$level] $message"
            }
            catch {
                Write-Output $_
            }
        }
    }
}

function Invoke-ConfigCommand {
    [CmdletBinding()]
    param()

    $targets = Get-TargetServers
    $results = @()

    foreach ($target in $targets) {
        $config = $script:ServerConfigs[$target]
        
        # Determine config file path
        $configFilePath = if ($ConfigPath) { 
            $ConfigPath 
        } else { 
            Join-Path ".llm-workflow" $config.ConfigFile 
        }
        
        $fullConfigPath = Join-Path $script:ScriptRoot "..\.." | Join-Path -ChildPath $configFilePath
        $fullConfigPath = Resolve-Path $fullConfigPath -ErrorAction SilentlyContinue

        if ($ConfigKey -and $PSBoundParameters.ContainsKey('ConfigValue')) {
            # Update configuration
            try {
                $configData = @{}
                if (Test-Path -LiteralPath $fullConfigPath) {
                    $configData = Get-Content -LiteralPath $fullConfigPath -Raw | ConvertFrom-Json -AsHashtable
                }

                # Set nested value using dot notation
                $keys = $ConfigKey -split '\.'
                $current = $configData
                for ($i = 0; $i -lt $keys.Count - 1; $i++) {
                    if (-not $current.ContainsKey($keys[$i])) {
                        $current[$keys[$i]] = @{}
                    }
                    $current = $current[$keys[$i]]
                }
                $current[$keys[-1]] = $ConfigValue

                # Save configuration
                $configData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $fullConfigPath -Encoding UTF8
                
                Write-ManagerLog -Level SUCCESS -Message "Updated $($config.Name) config: $ConfigKey = $ConfigValue"
                $results += [PSCustomObject]@{
                    Server = $target
                    Action = "config-update"
                    Success = $true
                    ConfigFile = $fullConfigPath
                    Key = $ConfigKey
                    Value = $ConfigValue
                }
            }
            catch {
                Write-ManagerLog -Level ERROR -Message "Failed to update $($config.Name) config: $_"
                $results += [PSCustomObject]@{
                    Server = $target
                    Action = "config-update"
                    Success = $false
                    Error = $_.Exception.Message
                }
            }
        }
        else {
            # Display configuration
            try {
                if (Test-Path -LiteralPath $fullConfigPath) {
                    $configData = Get-Content -LiteralPath $fullConfigPath -Raw | ConvertFrom-Json -AsHashtable
                    $results += [PSCustomObject]@{
                        Server = $target
                        ConfigFile = $fullConfigPath
                        Configuration = $configData
                    }
                }
                else {
                    $results += [PSCustomObject]@{
                        Server = $target
                        ConfigFile = $fullConfigPath
                        Configuration = "[File not found]"
                    }
                }
            }
            catch {
                Write-ManagerLog -Level ERROR -Message "Failed to read $($config.Name) config: $_"
            }
        }
    }

    return $results
}

# =============================================================================
# Output Functions
# =============================================================================

function Format-Output {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Data
    )

    if ($JsonOutput) {
        return $Data | ConvertTo-Json -Depth 10
    }

    # Table output
    if ($Data.Count -gt 0) {
        $Data | Format-Table -AutoSize
    }
}

# =============================================================================
# Main Execution
# =============================================================================

function Main {
    [CmdletBinding()]
    param()

    Write-ManagerLog -Level INFO -Message "=== MCP Server Manager ==="
    Write-ManagerLog -Level INFO -Message "Command: $Command, Server: $Server"

    try {
        $results = switch ($Command) {
            'start'   { Invoke-StartCommand }
            'stop'    { Invoke-StopCommand }
            'restart' { Invoke-RestartCommand }
            'status'  { Invoke-StatusCommand }
            'logs'    { Invoke-LogsCommand; return }
            'config'  { Invoke-ConfigCommand }
            default   { throw "Unknown command: $Command" }
        }

        if ($results) {
            Format-Output -Data $results
        }

        Write-ManagerLog -Level INFO -Message "=== Operation Completed ==="
    }
    catch {
        Write-ManagerLog -Level ERROR -Message "Operation failed: $_"
        exit 1
    }
}

# Run main function
Main
