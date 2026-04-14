#Requires -Version 5.1
<#
.SYNOPSIS
    Godot Networking System extractor for LLM Workflow Extraction Pipeline.

.DESCRIPTION
    Extracts structured networking configuration from Godot networking systems.
    Supports multiple networking frameworks including:
    - maximkulkin/godot-rollback-netcode (rollback networking)
    - foxssake/netfox (high-level networking)
    - Godot built-in MultiplayerAPI
    
    Parses network manager configurations, rollback settings, state serialization,
    input handling, RPC definitions, and sync manager configurations from:
    - .gd files (GDScript networking code)
    - .tscn files (network node scenes)
    - .json/.cfg configuration files
    
    This parser implements Section 25.7 of the canonical architecture for the
    Godot Engine pack's structured extraction pipeline.

.REQUIRED FUNCTIONS
    - Export-NetworkSystem: Extract network system configuration
    - Export-RollbackConfig: Extract rollback/prediction settings
    - Export-NetworkMessages: Extract message/RPC definitions
    - Get-NetworkTopology: Analyze network architecture
    - Export-InputPrediction: Extract input prediction patterns
    - Get-NetworkMetrics: Calculate networking metrics

.PARAMETER Path
    Path to the Godot networking file to parse.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Format
    Format of the networking file (auto, rollback_netcode, netfox, gdscript, json, scene).

.OUTPUTS
    JSON with network configurations, rollback settings, RPC definitions,
    topology analysis, and provenance metadata.

.NOTES
    File Name      : GodotNetworkingExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 2.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Pack           : godot-engine
#>

Set-StrictMode -Version Latest

# ============================================================================
# Module Constants and Version
# ============================================================================

$script:ParserVersion = '2.0.0'
$script:ParserName = 'GodotNetworkingExtractor'

# Supported file formats
$script:SupportedFormats = @('auto', 'rollback_netcode', 'netfox', 'gdscript', 'json', 'scene')

# Regex Patterns for Networking Parsing
$script:NetworkPatterns = @{
    # Godot built-in multiplayer patterns
    MultiplayerAPI = 'extends\s+(?:MultiplayerAPI|SceneMultiplayer)'
    NetworkPeer = 'multiplayer\.create_client|multiplayer\.create_server|ENetMultiplayerPeer|WebSocketMultiplayerPeer'
    RPCDeclaration = '^\s*@rpc\s*(?:\([^)]*\))?\s*\n?\s*func\s+(?<name>\w+)'
    RPCMode = '@rpc\s*\(\s*(?<mode>\w+)\s*(?:,\s*(?<sync>\w+))?\s*\)'
    MultiplayerAuthority = 'multiplayer\.is_server\(\)|is_multiplayer_authority\(\)|set_multiplayer_authority'
    MultiplayerSignals = '(?:multiplayer\.)?(?:peer_connected|peer_disconnected|server_disconnected)\.connect'
    
    # Rollback Netcode (maximkulkin/godot-rollback-netcode)
    RollbackManager = 'extends\s+(?:RollbackManager|NetworkRollbackManager)'
    RollbackConfig = '@export\s+var\s+(?:input_delay|max_predicted_frames|rollback_enabled)'
    InputDelay = '@export\s+var\s+input_delay\s*:\s*int\s*=\s*(?<value>\d+)'
    MaxPredictedFrames = '@export\s+var\s+max_predicted_frames\s*:\s*int\s*=\s*(?<value>\d+)'
    RollbackEnabled = '@export\s+var\s+rollback_enabled\s*:\s*bool\s*=\s*(?<value>true|false)'
    SaveState = 'func\s+_save_state\s*\('
    LoadState = 'func\s+_load_state\s*\('
    NetworkProcess = 'func\s+_network_process\s*\('
    NetworkInput = 'func\s+_get_local_input\s*\('
    
    # Netfox (foxssake/netfox)
    NetfoxRollback = 'extends\s+(?:RollbackSynchronizer|NetworkRollback)'
    NetfoxProperty = '@export\s+var\s+.*_rollback|RollbackProperties'
    NetfoxTick = 'NetworkTick|RollbackTick|_rollback_tick'
    NetfoxSync = 'NetworkSynchronizer|StateSynchronizer'
    
    # State serialization patterns
    SerializeState = 'func\s+(?:serialize|serialize_state|to_bytes|get_state)\s*\('
    DeserializeState = 'func\s+(?:deserialize|deserialize_state|from_bytes|set_state)\s*\('
    StateProperty = '@export\s+var\s+(?:state_|sync_|net_)'
    
    # Input handling patterns
    InputCollection = 'func\s+(?:_collect_input|get_input|_get_local_input|read_input)\s*\('
    InputStruct = 'class\s+(?:InputData|PlayerInput|NetworkInput)'
    InputBuffer = 'InputBuffer|input_history|input_queue'
    
    # Network message patterns
    MessageHandler = 'func\s+_on_(?:message|packet|data)_(?:received|received)'
    SendMessage = 'rpc|rpc_id|send_bytes|put_packet'
    MessageType = 'enum\s+(?:MessageType|PacketType|NetworkMessage)'
    
    # Sync manager patterns
    SyncManager = 'extends\s+(?:SyncManager|NetworkSyncManager|StateSync)'
    SyncInterval = '@export\s+var\s+(?:sync_interval|tick_rate|update_rate)'
    Interpolation = '@export\s+var\s+(?:interpolation_delay|interp_delay)'
    Reconciliation = '@export\s+var\s+(?:reconciliation_enabled|reconcile_states)'
    
    # Network entity/component patterns
    NetworkEntity = 'extends\s+(?:NetworkEntity|SyncBody|NetworkedCharacter)'
    NetworkComponent = 'class_name\s+\w+Component.*Network|extends\s+\w+NetworkComponent'
    
    # Scene file patterns
    NetworkNodeType = 'type="(?:RollbackManager|SyncManager|NetworkManager|NetworkEntity)"'
    MultiplayerNode = 'type="MultiplayerSpawner|MultiplayerSynchronizer"'
    
    # Configuration patterns
    NetworkPort = '(?:port|server_port)\s*[=:]\s*(?<port>\d+)'
    MaxPlayers = '(?:max_players|max_clients|player_limit)\s*[=:]\s*(?<value>\d+)'
    ServerAddress = "(?:server_address|host|hostname)\s*[=:]\s*[`"](?<addr>[^`"]+)[`"]"
}

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Creates provenance metadata for extraction results.
.DESCRIPTION
    Generates standardized metadata including source file, extraction timestamp,
    and parser version for tracking extraction provenance.
.PARAMETER SourceFile
    Path to the source file being parsed.
.PARAMETER Success
    Whether the extraction was successful.
.PARAMETER Errors
    Array of error messages.
.OUTPUTS
    System.Collections.Hashtable. Provenance metadata object.
#>
function New-ProvenanceMetadata {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        
        [Parameter()]
        [bool]$Success = $true,
        
        [Parameter()]
        [array]$Errors = @()
    )
    
    return @{
        sourceFile = $SourceFile
        extractionTimestamp = [DateTime]::UtcNow.ToString("o")
        parserName = $script:ParserName
        parserVersion = $script:ParserVersion
        success = $Success
        errors = $Errors
    }
}

<#
.SYNOPSIS
    Detects the networking format from file content.
.DESCRIPTION
    Analyzes the content to determine the networking framework being used.
.PARAMETER Content
    The file content to analyze.
.PARAMETER Extension
    The file extension.
.OUTPUTS
    System.String. The detected format.
#>
function Get-NetworkFormat {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Extension = ''
    )
    
    # Check for rollback netcode patterns first
    if ($Content -match $script:NetworkPatterns.RollbackManager -or
        $Content -match '_save_state|_load_state|_network_process' -or
        $Content -match 'RollbackManager|NetworkRollback') {
        return 'rollback_netcode'
    }
    
    # Check for netfox patterns
    if ($Content -match $script:NetworkPatterns.NetfoxRollback -or
        $Content -match 'RollbackSynchronizer|foxssake' -or
        $Content -match 'NetworkTick|RollbackTick') {
        return 'netfox'
    }
    
    # Check extension
    switch ($Extension.ToLower()) {
        '.tscn' { return 'scene' }
        '.json' { 
            if ($Content -match '"network"|"multiplayer"|"rollback"') {
                return 'json'
            }
        }
    }
    
    # Default to gdscript
    return 'gdscript'
}

<#
.SYNOPSIS
    Extracts RPC definitions from GDScript content.
.DESCRIPTION
    Parses RPC function declarations including their mode (authority, any_peer, etc.)
    and sync configuration.
.PARAMETER Content
    The GDScript content to parse.
.OUTPUTS
    System.Array. Array of RPC definition objects.
#>
function Get-RPCDefinitions {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    $rpcs = @()
    $lines = $Content -split "`r?`n"
    $lineNumber = 0
    $currentRPC = $null
    
    foreach ($line in $lines) {
        $lineNumber++
        
        # Check for @rpc annotation
        if ($line -match $script:NetworkPatterns.RPCMode) {
            $currentRPC = @{
                name = ''
                mode = $matches['mode']
                sync = if ($matches['sync']) { $matches['sync'] } else { 'sync' }
                lineNumber = $lineNumber
                parameters = @()
                returnType = 'void'
                docComment = ''
            }
        }
        # Check for function after @rpc
        elseif ($currentRPC -and $line -match '^\s*func\s+(?<name>\w+)\s*\((?<params>[^)]*)\)(?:\s*->\s*(?<ret>\w+))?') {
            $currentRPC.name = $matches['name']
            $currentRPC.returnType = if ($matches['ret']) { $matches['ret'] } else { 'void' }
            
            # Parse parameters
            if ($matches['params']) {
                $paramList = $matches['params'] -split ',' | ForEach-Object { $_.Trim() }
                foreach ($param in $paramList) {
                    if ($param -match '(?<name>\w+)\s*:\s*(?<type>\w+)') {
                        $currentRPC.parameters += @{
                            name = $matches['name']
                            type = $matches['type']
                        }
                    }
                    elseif ($param -match '(?<name>\w+)') {
                        $currentRPC.parameters += @{
                            name = $matches['name']
                            type = 'Variant'
                        }
                    }
                }
            }
            
            $rpcs += $currentRPC
            $currentRPC = $null
        }
        # Check for @rpc without explicit mode (defaults)
        elseif ($line -match '^\s*@rpc\s*$') {
            $currentRPC = @{
                name = ''
                mode = 'authority'
                sync = 'sync'
                lineNumber = $lineNumber
                parameters = @()
                returnType = 'void'
            }
        }
    }
    
    return $rpcs
}

<#
.SYNOPSIS
    Extracts state serialization patterns from content.
.DESCRIPTION
    Parses state save/load and serialization/deserialization functions.
.PARAMETER Content
    The GDScript content to parse.
.OUTPUTS
    System.Collections.Hashtable. Object containing serialization patterns.
#>
function Get-StateSerialization {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    $serialization = @{
        hasSaveState = $false
        hasLoadState = $false
        hasSerialize = $false
        hasDeserialize = $false
        saveStateLine = 0
        loadStateLine = 0
        properties = @()
        stateFields = @()
    }
    
    $lines = $Content -split "`r?`n"
    $lineNumber = 0
    $inSaveState = $false
    $inLoadState = $false
    $saveStateDepth = 0
    $loadStateDepth = 0
    
    foreach ($line in $lines) {
        $lineNumber++
        
        # Detect save state function
        if ($line -match $script:NetworkPatterns.SaveState) {
            $serialization.hasSaveState = $true
            $serialization.saveStateLine = $lineNumber
            $inSaveState = $true
            $saveStateDepth = 0
        }
        # Detect load state function
        elseif ($line -match $script:NetworkPatterns.LoadState) {
            $serialization.hasLoadState = $true
            $serialization.loadStateLine = $lineNumber
            $inLoadState = $true
            $loadStateDepth = 0
        }
        # Detect serialize function
        elseif ($line -match $script:NetworkPatterns.SerializeState) {
            $serialization.hasSerialize = $true
        }
        # Detect deserialize function
        elseif ($line -match $script:NetworkPatterns.DeserializeState) {
            $serialization.hasDeserialize = $true
        }
        
        # Extract state properties from @export vars with state_/sync_/net_ prefix
        if ($line -match $script:NetworkPatterns.StateProperty) {
            if ($line -match '@export\s+var\s+(?<name>\w+)\s*:\s*(?<type>\w+)') {
                $serialization.properties += @{
                    name = $matches['name']
                    type = $matches['type']
                    lineNumber = $lineNumber
                    category = 'network_state'
                }
            }
        }
        
        # Track function depth for save/load state
        if ($inSaveState -or $inLoadState) {
            $openBraces = ([regex]::Matches($line, '\{')).Count
            $closeBraces = ([regex]::Matches($line, '\}')).Count
            
            if ($inSaveState) {
                $saveStateDepth += $openBraces - $closeBraces
                
                # Look for state dictionary fields
                if ($line -match "[`"'](?<field>\w+)[`"']\s*:\s*(?<value>.+)") {
                    $serialization.stateFields += @{
                        name = $matches['field']
                        value = $matches['value'].Trim()
                        lineNumber = $lineNumber
                        context = 'save_state'
                    }
                }
                
                if ($saveStateDepth -le 0 -and $openBraces -ne $closeBraces) {
                    $inSaveState = $false
                }
            }
            
            if ($inLoadState) {
                $loadStateDepth += $openBraces - $closeBraces
                
                if ($loadStateDepth -le 0 -and $openBraces -ne $closeBraces) {
                    $inLoadState = $false
                }
            }
        }
    }
    
    return $serialization
}

<#
.SYNOPSIS
    Extracts input handling patterns from content.
.DESCRIPTION
    Parses input collection, buffering, and prediction patterns.
.PARAMETER Content
    The GDScript content to parse.
.OUTPUTS
    System.Collections.Hashtable. Object containing input handling patterns.
#>
function Get-InputHandling {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    $inputHandling = @{
        hasInputCollection = $false
        hasInputStruct = $false
        hasInputBuffer = $false
        collectionLine = 0
        inputFields = @()
        inputMethods = @()
    }
    
    $lines = $Content -split "`r?`n"
    $lineNumber = 0
    
    foreach ($line in $lines) {
        $lineNumber++
        
        # Check for input collection function
        if ($line -match $script:NetworkPatterns.InputCollection) {
            $inputHandling.hasInputCollection = $true
            $inputHandling.collectionLine = $lineNumber
            if ($line -match 'func\s+(?<name>\w+)') {
                $inputHandling.inputMethods += @{
                    name = $matches['name']
                    lineNumber = $lineNumber
                    type = 'collection'
                }
            }
        }
        
        # Check for input struct/class
        if ($line -match $script:NetworkPatterns.InputStruct) {
            $inputHandling.hasInputStruct = $true
        }
        
        # Check for input buffer
        if ($line -match $script:NetworkPatterns.InputBuffer) {
            $inputHandling.hasInputBuffer = $true
        }
        
        # Extract input-related exports
        if ($line -match '@export\s+var\s+(?:input_|move_|action_|jump_)(?<name>\w+)') {
            $inputHandling.inputFields += @{
                name = $matches['name']
                lineNumber = $lineNumber
                category = 'input'
            }
        }
    }
    
    return $inputHandling
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Extracts network system configuration from Godot files.

.DESCRIPTION
    Parses GDScript files, scene files, or configuration files to extract
    network system configuration including network managers, peer settings,
    connection parameters, and multiplayer node configurations.

.PARAMETER Path
    Path to the Godot networking file.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Format
    Format of the networking file (auto, rollback_netcode, netfox, gdscript, json, scene).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - networkManager: Network manager configuration
    - peerConfig: Peer connection settings
    - multiplayerNodes: Multiplayer node configurations
    - rpcDefinitions: RPC function definitions
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $network = Export-NetworkSystem -Path "res://network/network_manager.gd"
    
    $network = Export-NetworkSystem -Content $gdscriptContent -Format "rollback_netcode"
#>
function Export-NetworkSystem {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'rollback_netcode', 'netfox', 'gdscript', 'json', 'scene')]
        [string]$Format = 'auto'
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    networkManager = @{}
                    peerConfig = @{}
                    multiplayerNodes = @()
                    rpcDefinitions = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ rpcCount = 0; hasNetworkManager = $false }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            
            if ($Format -eq 'auto') {
                $ext = [System.IO.Path]::GetExtension($Path).ToLower()
                $Format = Get-NetworkFormat -Content $Content -Extension $ext
            }
        }
        else {
            if ($Format -eq 'auto') {
                $Format = Get-NetworkFormat -Content $Content
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                networkManager = @{}
                peerConfig = @{}
                multiplayerNodes = @()
                rpcDefinitions = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ rpcCount = 0; hasNetworkManager = $false }
            }
        }
        
        # Extract network manager info
        $networkManager = @{
            detected = $false
            type = 'unknown'
            className = ''
            extends = ''
            framework = $Format
        }
        
        # Check for network manager types
        if ($Content -match $script:NetworkPatterns.RollbackManager) {
            $networkManager.detected = $true
            $networkManager.type = 'rollback_manager'
            $networkManager.framework = 'rollback_netcode'
        }
        elseif ($Content -match $script:NetworkPatterns.SyncManager) {
            $networkManager.detected = $true
            $networkManager.type = 'sync_manager'
        }
        elseif ($Content -match 'class_name\s+(?<name>\w+Manager)') {
            $networkManager.detected = $true
            $networkManager.type = 'custom_manager'
            $networkManager.className = $matches['name']
        }
        
        # Extract class extends
        if ($Content -match 'extends\s+(?<class>\w+)') {
            $networkManager.extends = $matches['class']
        }
        
        # Extract peer configuration
        $peerConfig = @{
            port = 0
            maxPlayers = 0
            serverAddress = ''
            hasClientCode = $false
            hasServerCode = $false
        }
        
        # Look for port configuration
        if ($Content -match $script:NetworkPatterns.NetworkPort) {
            $peerConfig.port = [int]$matches['port']
        }
        
        # Look for max players
        if ($Content -match $script:NetworkPatterns.MaxPlayers) {
            $peerConfig.maxPlayers = [int]$matches['value']
        }
        
        # Look for server address
        if ($Content -match $script:NetworkPatterns.ServerAddress) {
            $peerConfig.serverAddress = $matches['addr']
        }
        
        # Check for client/server code
        $peerConfig.hasClientCode = $Content -match 'create_client|ENetMultiplayerPeer\.new\(\)'
        $peerConfig.hasServerCode = $Content -match 'create_server|listen\(|create_host'
        
        # Extract RPC definitions
        $rpcDefinitions = Get-RPCDefinitions -Content $Content
        
        # Extract multiplayer nodes (from scene files)
        $multiplayerNodes = @()
        if ($Format -eq 'scene') {
            # Parse scene file for multiplayer nodes
            $sceneMatches = [regex]::Matches($Content, 'type="(?<type>Multiplayer\w+)".*name="(?<name>\w+)"')
            foreach ($match in $sceneMatches) {
                $multiplayerNodes += @{
                    type = $match.Groups['type'].Value
                    name = $match.Groups['name'].Value
                }
            }
        }
        
        # Check for multiplayer authority patterns
        $hasAuthorityCheck = $Content -match $script:NetworkPatterns.MultiplayerAuthority
        
        return @{
            networkManager = $networkManager
            peerConfig = $peerConfig
            multiplayerNodes = $multiplayerNodes
            rpcDefinitions = $rpcDefinitions
            hasAuthorityCheck = $hasAuthorityCheck
            framework = $Format
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                rpcCount = $rpcDefinitions.Count
                hasNetworkManager = $networkManager.detected
                hasClientCode = $peerConfig.hasClientCode
                hasServerCode = $peerConfig.hasServerCode
                multiplayerNodeCount = $multiplayerNodes.Count
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract network system: $_"
        return @{
            networkManager = @{}
            peerConfig = @{}
            multiplayerNodes = @()
            rpcDefinitions = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ rpcCount = 0; hasNetworkManager = $false }
        }
    }
}

<#
.SYNOPSIS
    Extracts rollback and prediction configuration from Godot files.

.DESCRIPTION
    Parses rollback networking configuration including input delay settings,
    maximum predicted frames, state serialization, and rollback-specific
    callbacks for maximkulkin/godot-rollback-netcode.

.PARAMETER Path
    Path to the Godot networking file.

.PARAMETER Content
    File content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - rollbackSettings: Rollback-specific settings
    - stateSerialization: State save/load patterns
    - inputHandling: Input collection patterns
    - networkCallbacks: Network lifecycle callbacks
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $rollback = Export-RollbackConfig -Path "res://network/rollback_manager.gd"
    
    $rollback = Export-RollbackConfig -Content $gdscriptContent
#>
function Export-RollbackConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    rollbackSettings = @{}
                    stateSerialization = @{}
                    inputHandling = @{}
                    networkCallbacks = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ isRollbackSystem = $false }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                rollbackSettings = @{}
                stateSerialization = @{}
                inputHandling = @{}
                networkCallbacks = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ isRollbackSystem = $false }
            }
        }
        
        # Check if this is a rollback system
        $isRollbackSystem = $Content -match $script:NetworkPatterns.RollbackManager -or
                           $Content -match '_save_state|_load_state|_network_process'
        
        # Extract rollback settings
        $rollbackSettings = @{
            inputDelay = 0
            maxPredictedFrames = 0
            rollbackEnabled = $true
            isRollbackSystem = $isRollbackSystem
            detectedSettings = @()
        }
        
        # Look for input delay
        if ($Content -match $script:NetworkPatterns.InputDelay) {
            $rollbackSettings.inputDelay = [int]$matches['value']
            $rollbackSettings.detectedSettings += 'input_delay'
        }
        
        # Look for max predicted frames
        if ($Content -match $script:NetworkPatterns.MaxPredictedFrames) {
            $rollbackSettings.maxPredictedFrames = [int]$matches['value']
            $rollbackSettings.detectedSettings += 'max_predicted_frames'
        }
        
        # Look for rollback enabled
        if ($Content -match $script:NetworkPatterns.RollbackEnabled) {
            $rollbackSettings.rollbackEnabled = [bool]::Parse($matches['value'])
            $rollbackSettings.detectedSettings += 'rollback_enabled'
        }
        
        # Look for other @export rollback settings
        $exportMatches = [regex]::Matches($Content, '@export\s+var\s+(?<name>\w+)\s*:\s*(?<type>\w+)\s*=\s*(?<value>[^\n]+)')
        foreach ($match in $exportMatches) {
            $name = $match.Groups['name'].Value
            if ($name -match 'rollback|predict|delay|buffer|sync') {
                $rollbackSettings[$name] = $match.Groups['value'].Value.Trim()
            }
        }
        
        # Extract state serialization
        $stateSerialization = Get-StateSerialization -Content $Content
        
        # Extract input handling
        $inputHandling = Get-InputHandling -Content $Content
        
        # Extract network callbacks
        $networkCallbacks = @()
        $callbackPatterns = @(
            @{ Pattern = '_save_state'; Type = 'state_management' }
            @{ Pattern = '_load_state'; Type = 'state_management' }
            @{ Pattern = '_network_process'; Type = 'network_tick' }
            @{ Pattern = '_get_local_input'; Type = 'input_collection' }
            @{ Pattern = '_on_peer_connected'; Type = 'connection' }
            @{ Pattern = '_on_peer_disconnected'; Type = 'connection' }
            @{ Pattern = '_network_ready'; Type = 'lifecycle' }
        )
        
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        foreach ($line in $lines) {
            $lineNumber++
            foreach ($callback in $callbackPatterns) {
                if ($line -match "func\s+$($callback.Pattern)") {
                    $networkCallbacks += @{
                        name = $callback.Pattern
                        type = $callback.Type
                        lineNumber = $lineNumber
                    }
                }
            }
        }
        
        return @{
            rollbackSettings = $rollbackSettings
            stateSerialization = $stateSerialization
            inputHandling = $inputHandling
            networkCallbacks = $networkCallbacks
            isRollbackSystem = $isRollbackSystem
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                isRollbackSystem = $isRollbackSystem
                inputDelay = $rollbackSettings.inputDelay
                maxPredictedFrames = $rollbackSettings.maxPredictedFrames
                stateCallbacks = ($networkCallbacks | Where-Object { $_.type -eq 'state_management' }).Count
                inputCallbacks = ($networkCallbacks | Where-Object { $_.type -eq 'input_collection' }).Count
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract rollback config: $_"
        return @{
            rollbackSettings = @{}
            stateSerialization = @{}
            inputHandling = @{}
            networkCallbacks = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ isRollbackSystem = $false }
        }
    }
}

<#
.SYNOPSIS
    Extracts network message and RPC definitions from Godot files.

.DESCRIPTION
    Parses RPC (Remote Procedure Call) definitions, message types, and
    network message handlers from GDScript files.

.PARAMETER Path
    Path to the Godot networking file.

.PARAMETER Content
    File content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - rpcDefinitions: RPC function definitions
    - messageTypes: Custom message type enums
    - messageHandlers: Message handler functions
    - networkSignals: Network-related signal connections
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $messages = Export-NetworkMessages -Path "res://network/network_manager.gd"
    
    $messages = Export-NetworkMessages -Content $gdscriptContent
#>
function Export-NetworkMessages {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    rpcDefinitions = @()
                    messageTypes = @()
                    messageHandlers = @()
                    networkSignals = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ rpcCount = 0; messageTypeCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                rpcDefinitions = @()
                messageTypes = @()
                messageHandlers = @()
                networkSignals = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ rpcCount = 0; messageTypeCount = 0 }
            }
        }
        
        # Extract RPC definitions
        $rpcDefinitions = Get-RPCDefinitions -Content $Content
        
        # Extract message types from enums
        $messageTypes = @()
        if ($Content -match $script:NetworkPatterns.MessageType) {
            # Find enum definition
            $enumMatch = [regex]::Match($Content, 'enum\s+(?:MessageType|PacketType|NetworkMessage)\s*\{(?<values>[^}]+)\}')
            if ($enumMatch.Success) {
                $valuesStr = $enumMatch.Groups['values'].Value
                $valueMatches = [regex]::Matches($valuesStr, '(?<name>\w+)\s*(?:=\s*(?<value>\d+))?')
                foreach ($match in $valueMatches) {
                    $messageTypes += @{
                        name = $match.Groups['name'].Value
                        value = if ($match.Groups['value'].Success) { [int]$match.Groups['value'].Value } else { $null }
                    }
                }
            }
        }
        
        # Extract message handlers
        $messageHandlers = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        foreach ($line in $lines) {
            $lineNumber++
            if ($line -match $script:NetworkPatterns.MessageHandler) {
                if ($line -match 'func\s+(?<name>\w+)') {
                    $messageHandlers += @{
                        name = $matches['name']
                        lineNumber = $lineNumber
                        type = 'message_handler'
                    }
                }
            }
            if ($line -match 'func\s+_on_(?:peer_connected|peer_disconnected|server_disconnected)') {
                if ($line -match 'func\s+(?<name>\w+)') {
                    $messageHandlers += @{
                        name = $matches['name']
                        lineNumber = $lineNumber
                        type = 'connection_handler'
                    }
                }
            }
        }
        
        # Extract network signals
        $networkSignals = @()
        $signalMatches = [regex]::Matches($Content, '(?<signal>peer_connected|peer_disconnected|server_disconnected|connection_failed)\.connect\s*\(\s*(?<handler>\w+)')
        foreach ($match in $signalMatches) {
            $networkSignals += @{
                signal = $match.Groups['signal'].Value
                handler = $match.Groups['handler'].Value
            }
        }
        
        # Count RPC modes
        $rpcModes = @{}
        foreach ($rpc in $rpcDefinitions) {
            $mode = $rpc.mode
            if (-not $rpcModes.ContainsKey($mode)) {
                $rpcModes[$mode] = 0
            }
            $rpcModes[$mode]++
        }
        
        return @{
            rpcDefinitions = $rpcDefinitions
            messageTypes = $messageTypes
            messageHandlers = $messageHandlers
            networkSignals = $networkSignals
            rpcModes = $rpcModes
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                rpcCount = $rpcDefinitions.Count
                messageTypeCount = $messageTypes.Count
                handlerCount = $messageHandlers.Count
                signalCount = $networkSignals.Count
                authorityRPCs = $rpcModes['authority']
                anyPeerRPCs = $rpcModes['any_peer']
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract network messages: $_"
        return @{
            rpcDefinitions = @()
            messageTypes = @()
            messageHandlers = @()
            networkSignals = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ rpcCount = 0; messageTypeCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Analyzes network topology from Godot networking files.

.DESCRIPTION
    Analyzes the network architecture including client-server relationships,
    node hierarchies, sync relationships, and data flow patterns.

.PARAMETER Path
    Path to the Godot networking file or project directory.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER ProjectPath
    Path to the Godot project directory for full topology analysis.

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - architecture: Detected network architecture type
    - topology: Node topology information
    - syncRelationships: Synchronization relationships between nodes
    - dataFlow: Data flow patterns
    - metadata: Provenance metadata
    - statistics: Topology statistics

.EXAMPLE
    $topology = Get-NetworkTopology -Path "res://network/"
    
    $topology = Get-NetworkTopology -Content $gdscriptContent
#>
function Get-NetworkTopology {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(ParameterSetName = 'Path')]
        [string]$ProjectPath
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (Test-Path -LiteralPath $Path -PathType Container) {
                # Directory scan
                $networkFiles = Get-ChildItem -Path $Path -Recurse -Include "*.gd" -ErrorAction SilentlyContinue
                $Content = ''
                foreach ($file in $networkFiles) {
                    $Content += Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                    $Content += "`n"
                }
                $sourceFile = $Path
            }
            elseif (Test-Path -LiteralPath $Path) {
                $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
                $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            }
            else {
                return @{
                    architecture = @{}
                    topology = @{}
                    syncRelationships = @()
                    dataFlow = @{}
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("Path not found: $Path")
                    statistics = @{ hasServer = $false; hasClient = $false }
                }
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                architecture = @{}
                topology = @{}
                syncRelationships = @()
                dataFlow = @{}
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ hasServer = $false; hasClient = $false }
            }
        }
        
        # Detect architecture type
        $architecture = @{
            type = 'unknown'
            isAuthoritativeServer = $false
            isListenServer = $false
            isP2P = $false
            usesRollback = $false
            usesPrediction = $false
            usesInterpolation = $false
            usesReconciliation = $false
        }
        
        # Check for rollback
        if ($Content -match $script:NetworkPatterns.RollbackManager -or
            $Content -match 'rollback|_save_state|_load_state') {
            $architecture.type = 'rollback'
            $architecture.usesRollback = $true
            $architecture.usesPrediction = $true
        }
        # Check for client-server
        elseif ($Content -match 'create_server' -and $Content -match 'create_client') {
            $architecture.type = 'hybrid'
            $architecture.isListenServer = $true
        }
        elseif ($Content -match 'create_server') {
            $architecture.type = 'server'
            $architecture.isAuthoritativeServer = $true
        }
        elseif ($Content -match 'create_client') {
            $architecture.type = 'client'
        }
        
        # Check for P2P
        if ($Content -match 'WebRTC|mesh_network|p2p') {
            $architecture.isP2P = $true
        }
        
        # Check for interpolation
        if ($Content -match $script:NetworkPatterns.Interpolation -or
            $Content -match 'interp|lerp|interpolate') {
            $architecture.usesInterpolation = $true
        }
        
        # Check for reconciliation
        if ($Content -match $script:NetworkPatterns.Reconciliation -or
            $Content -match 'reconcil') {
            $architecture.usesReconciliation = $true
        }
        
        # Extract topology nodes
        $topology = @{
            networkManagers = @()
            syncNodes = @()
            entityNodes = @()
            componentNodes = @()
        }
        
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        foreach ($line in $lines) {
            $lineNumber++
            
            # Network managers
            if ($line -match 'class_name\s+(?<name>\w+)') {
                $className = $matches['name']
                if ($className -match 'Manager|Network|Rollback|Sync') {
                    $topology.networkManagers += @{
                        name = $className
                        lineNumber = $lineNumber
                        type = 'manager'
                    }
                }
                if ($className -match 'Entity|Character|Player|NPC') {
                    $topology.entityNodes += @{
                        name = $className
                        lineNumber = $lineNumber
                        type = 'entity'
                    }
                }
            }
        }
        
        # Extract sync relationships
        $syncRelationships = @()
        
        # Look for MultiplayerSynchronizer nodes in scene files
        $syncMatches = [regex]::Matches($Content, 'type="MultiplayerSynchronizer".*name="(?<name>\w+)"')
        foreach ($match in $syncMatches) {
            $syncRelationships += @{
                node = $match.Groups['name'].Value
                type = 'MultiplayerSynchronizer'
                replicationConfig = @()
            }
        }
        
        # Look for replication configuration
        $replicationMatches = [regex]::Matches($Content, "root_path\s*=\s*NodePath\([`"](?<path>[^`"]+)[`"]\)")
        foreach ($match in $replicationMatches) {
            $syncRelationships += @{
                path = $match.Groups['path'].Value
                type = 'replication_root'
            }
        }
        
        # Data flow analysis
        $dataFlow = @{
            serverToClient = @()
            clientToServer = @()
            broadcast = @()
        }
        
        # Analyze RPC directions
        $rpcDefs = Get-RPCDefinitions -Content $Content
        foreach ($rpc in $rpcDefs) {
            if ($rpc.mode -eq 'authority') {
                $dataFlow.serverToClient += @{
                    function = $rpc.name
                    type = 'rpc'
                }
            }
            elseif ($rpc.mode -eq 'any_peer') {
                $dataFlow.clientToServer += @{
                    function = $rpc.name
                    type = 'rpc'
                }
            }
        }
        
        return @{
            architecture = $architecture
            topology = $topology
            syncRelationships = $syncRelationships
            dataFlow = $dataFlow
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                hasServer = $architecture.type -in @('server', 'hybrid')
                hasClient = $architecture.type -in @('client', 'hybrid')
                usesRollback = $architecture.usesRollback
                usesPrediction = $architecture.usesPrediction
                usesInterpolation = $architecture.usesInterpolation
                managerCount = $topology.networkManagers.Count
                entityCount = $topology.entityNodes.Count
                syncNodeCount = $syncRelationships.Count
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to analyze network topology: $_"
        return @{
            architecture = @{}
            topology = @{}
            syncRelationships = @()
            dataFlow = @{}
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ hasServer = $false; hasClient = $false }
        }
    }
}

<#
.SYNOPSIS
    Extracts input prediction patterns from Godot networking files.

.DESCRIPTION
    Parses input prediction, reconciliation, and correction patterns
    for rollback and client-side prediction systems.

.PARAMETER Path
    Path to the Godot networking file.

.PARAMETER Content
    File content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - predictionSettings: Prediction configuration
    - inputCollection: Input collection patterns
    - reconciliation: State reconciliation patterns
    - correction: Prediction correction patterns
    - metadata: Provenance metadata
    - statistics: Prediction statistics

.EXAMPLE
    $prediction = Export-InputPrediction -Path "res://player/network_player.gd"
    
    $prediction = Export-InputPrediction -Content $gdscriptContent
#>
function Export-InputPrediction {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    predictionSettings = @{}
                    inputCollection = @{}
                    reconciliation = @{}
                    correction = @{}
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ hasPrediction = $false }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                predictionSettings = @{}
                inputCollection = @{}
                reconciliation = @{}
                correction = @{}
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ hasPrediction = $false }
            }
        }
        
        # Check for prediction
        $hasPrediction = $Content -match 'predict|_network_process|rollback' -or
                        $Content -match $script:NetworkPatterns.InputCollection
        
        # Prediction settings
        $predictionSettings = @{
            hasPrediction = $hasPrediction
            inputDelay = 0
            maxPredictionFrames = 0
            reconciliationEnabled = $false
        }
        
        # Look for prediction-related settings
        $exportMatches = [regex]::Matches($Content, '@export\s+var\s+(?<name>\w+)\s*:\s*(?<type>\w+)\s*=\s*(?<value>[^\n]+)')
        foreach ($match in $exportMatches) {
            $name = $match.Groups['name'].Value
            $value = $match.Groups['value'].Value.Trim()
            
            switch -Wildcard ($name) {
                '*delay*' { $predictionSettings.inputDelay = $value }
                '*predict*frame*' { $predictionSettings.maxPredictionFrames = $value }
                '*reconcil*' { $predictionSettings.reconciliationEnabled = $value -eq 'true' }
            }
        }
        
        # Input collection patterns
        $inputCollection = Get-InputHandling -Content $Content
        
        # Reconciliation patterns
        $reconciliation = @{
            hasReconciliation = $false
            reconcileMethods = @()
            stateComparison = @()
        }
        
        if ($Content -match 'reconcil|correct|_correct_state|snap_to') {
            $reconciliation.hasReconciliation = $true
            $predictionSettings.reconciliationEnabled = $true
        }
        
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        foreach ($line in $lines) {
            $lineNumber++
            
            # Look for reconciliation methods
            if ($line -match 'func\s+(?<name>_correct_state|_reconcile|reconcile_state|snap_to_state)') {
                $reconciliation.reconcileMethods += @{
                    name = $matches['name']
                    lineNumber = $lineNumber
                }
            }
            
            # Look for state comparison
            if ($line -match '(?:predicted_state|local_state)\s*[!]?=\s*(?:server_state|remote_state)') {
                $reconciliation.stateComparison += @{
                    lineNumber = $lineNumber
                    expression = $line.Trim()
                }
            }
        }
        
        # Correction patterns
        $correction = @{
            hasCorrection = $false
            correctionMethods = @()
            smoothingMethods = @()
        }
        
        if ($Content -match 'lerp|interpolate|smooth|blend') {
            $correction.hasCorrection = $true
        }
        
        $lineNumber = 0
        foreach ($line in $lines) {
            $lineNumber++
            if ($line -match 'lerp|interpolate|smooth') {
                $correction.smoothingMethods += @{
                    lineNumber = $lineNumber
                    expression = $line.Trim()
                }
            }
        }
        
        return @{
            predictionSettings = $predictionSettings
            inputCollection = $inputCollection
            reconciliation = $reconciliation
            correction = $correction
            hasPrediction = $hasPrediction
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                hasPrediction = $hasPrediction
                hasReconciliation = $reconciliation.hasReconciliation
                hasCorrection = $correction.hasCorrection
                inputCollectionMethods = $inputCollection.inputMethods.Count
                reconcileMethodCount = $reconciliation.reconcileMethods.Count
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract input prediction: $_"
        return @{
            predictionSettings = @{}
            inputCollection = @{}
            reconciliation = @{}
            correction = @{}
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ hasPrediction = $false }
        }
    }
}

<#
.SYNOPSIS
    Calculates networking metrics from Godot networking files.

.DESCRIPTION
    Analyzes networking code and calculates metrics including:
    - RPC density and complexity
    - State size estimation
    - Network bandwidth indicators
    - Sync frequency analysis
    - Prediction accuracy indicators

.PARAMETER Path
    Path to the Godot networking file or project directory.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER ProjectPath
    Path to the Godot project directory for comprehensive metrics.

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - rpcMetrics: RPC-related metrics
    - stateMetrics: State serialization metrics
    - bandwidthEstimates: Bandwidth estimation
    - complexityScores: Complexity analysis
    - recommendations: Optimization recommendations
    - metadata: Provenance metadata

.EXAMPLE
    $metrics = Get-NetworkMetrics -Path "res://network/"
    
    $metrics = Get-NetworkMetrics -Content $gdscriptContent
#>
function Get-NetworkMetrics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(ParameterSetName = 'Path')]
        [string]$ProjectPath
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        $totalFiles = 1
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (Test-Path -LiteralPath $Path -PathType Container) {
                # Directory scan
                $networkFiles = Get-ChildItem -Path $Path -Recurse -Include "*.gd" -ErrorAction SilentlyContinue
                $Content = ''
                $totalFiles = $networkFiles.Count
                foreach ($file in $networkFiles) {
                    $Content += Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                    $Content += "`n"
                }
                $sourceFile = $Path
            }
            elseif (Test-Path -LiteralPath $Path) {
                $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
                $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            }
            else {
                return @{
                    rpcMetrics = @{}
                    stateMetrics = @{}
                    bandwidthEstimates = @{}
                    complexityScores = @{}
                    recommendations = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("Path not found: $Path")
                }
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                rpcMetrics = @{}
                stateMetrics = @{}
                bandwidthEstimates = @{}
                complexityScores = @{}
                recommendations = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
            }
        }
        
        $lines = $Content -split "`r?`n"
        $totalLines = $lines.Count
        
        # RPC Metrics
        $rpcDefs = Get-RPCDefinitions -Content $Content
        $rpcMetrics = @{
            totalRPCs = $rpcDefs.Count
            authorityRPCs = ($rpcDefs | Where-Object { $_.mode -eq 'authority' }).Count
            anyPeerRPCs = ($rpcDefs | Where-Object { $_.mode -eq 'any_peer' }).Count
            averageParameters = if ($rpcDefs.Count -gt 0) { 
                ($rpcDefs | ForEach-Object { $_.parameters.Count } | Measure-Object -Average).Average 
            } else { 0 }
            rpcsPer100Lines = if ($totalLines -gt 0) { 
                [math]::Round(($rpcDefs.Count / $totalLines) * 100, 2) 
            } else { 0 }
        }
        
        # State metrics
        $stateSerial = Get-StateSerialization -Content $Content
        $stateMetrics = @{
            hasStateSerialization = $stateSerial.hasSaveState -or $stateSerial.hasSerialize
            statePropertyCount = $stateSerial.properties.Count
            stateFieldCount = $stateSerial.stateFields.Count
            estimatedStateSize = $stateSerial.stateFields.Count * 8  # Rough estimate: 8 bytes per field
        }
        
        # Add estimated size from properties
        foreach ($prop in $stateSerial.properties) {
            switch ($prop.type) {
                'int' { $stateMetrics.estimatedStateSize += 4 }
                'float' { $stateMetrics.estimatedStateSize += 4 }
                'Vector2' { $stateMetrics.estimatedStateSize += 8 }
                'Vector3' { $stateMetrics.estimatedStateSize += 12 }
                'bool' { $stateMetrics.estimatedStateSize += 1 }
                default { $stateMetrics.estimatedStateSize += 8 }
            }
        }
        
        # Bandwidth estimates (rough calculations)
        $bandwidthEstimates = @{
            estimatedBytesPerTick = $stateMetrics.estimatedStateSize
            estimatedBytesPerSecond = 0
            estimatedBytesPerSecondWithPrediction = 0
        }
        
        # Assume 60 ticks/second for rollback games, 20 for regular sync
        $isRollback = $Content -match $script:NetworkPatterns.RollbackManager
        if ($isRollback) {
            $bandwidthEstimates.estimatedBytesPerSecond = $stateMetrics.estimatedStateSize * 60
            # Prediction adds ~20% overhead for input messages
            $bandwidthEstimates.estimatedBytesPerSecondWithPrediction = $bandwidthEstimates.estimatedBytesPerSecond * 1.2
        }
        else {
            # Check for sync interval
            if ($Content -match 'sync_interval|tick_rate') {
                if ($Content -match '(?:sync_interval|tick_rate)\s*=\s*(?<rate>\d+)') {
                    $tickRate = [int]$matches['rate']
                    $bandwidthEstimates.estimatedBytesPerSecond = $stateMetrics.estimatedStateSize * $tickRate
                }
            }
            else {
                $bandwidthEstimates.estimatedBytesPerSecond = $stateMetrics.estimatedStateSize * 20  # Default 20Hz
            }
        }
        
        # Complexity scores
        $complexityScores = @{
            overall = 0
            rpcComplexity = 0
            stateComplexity = 0
            predictionComplexity = 0
        }
        
        # RPC complexity (more RPCs = more complex)
        $complexityScores.rpcComplexity = [math]::Min(10, $rpcDefs.Count / 2)
        
        # State complexity (more state fields = more complex)
        $complexityScores.stateComplexity = [math]::Min(10, $stateSerial.stateFields.Count / 3)
        
        # Prediction complexity
        if ($isRollback) {
            $complexityScores.predictionComplexity = 8
        }
        elseif ($Content -match 'predict|interpolat') {
            $complexityScores.predictionComplexity = 5
        }
        
        # Overall complexity
        $complexityScores.overall = [math]::Round(
            ($complexityScores.rpcComplexity + $complexityScores.stateComplexity + $complexityScores.predictionComplexity) / 3,
            1
        )
        
        # Recommendations
        $recommendations = @()
        
        if ($rpcMetrics.totalRPCs -gt 20) {
            $recommendations += "High RPC count ($($rpcMetrics.totalRPCs)) - consider batching messages"
        }
        
        if ($stateMetrics.estimatedStateSize -gt 1024) {
            $recommendations += "Large state size ($($stateMetrics.estimatedStateSize) bytes) - consider delta compression"
        }
        
        if ($bandwidthEstimates.estimatedBytesPerSecond -gt 50000) {
            $recommendations += "High bandwidth usage (~$([math]::Round($bandwidthEstimates.estimatedBytesPerSecond/1024, 1)) KB/s) - optimize state size"
        }
        
        if ($isRollback -and $stateMetrics.stateFieldCount -eq 0) {
            $recommendations += "Rollback system detected but no state fields found - implement _save_state and _load_state"
        }
        
        if (-not $stateSerial.hasSaveState -and $isRollback) {
            $recommendations += "Missing _save_state implementation for rollback system"
        }
        
        if (-not $stateSerial.hasLoadState -and $isRollback) {
            $recommendations += "Missing _load_state implementation for rollback system"
        }
        
        if ($rpcMetrics.anyPeerRPCs -gt $rpcMetrics.authorityRPCs * 2) {
            $recommendations += "Many any_peer RPCs - verify server authority for cheat prevention"
        }
        
        return @{
            rpcMetrics = $rpcMetrics
            stateMetrics = $stateMetrics
            bandwidthEstimates = $bandwidthEstimates
            complexityScores = $complexityScores
            recommendations = $recommendations
            fileCount = $totalFiles
            lineCount = $totalLines
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to calculate network metrics: $_"
        return @{
            rpcMetrics = @{}
            stateMetrics = @{}
            bandwidthEstimates = @{}
            complexityScores = @{}
            recommendations = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}

# ============================================================================
# Module Exports
# ============================================================================

# Only export if running as a module (not when dot-sourced)
if ($MyInvocation.InvocationName -eq 'Import-Module' -or $MyInvocation.Line -match 'Import-Module') {
# Public functions exported via module wildcard
}
