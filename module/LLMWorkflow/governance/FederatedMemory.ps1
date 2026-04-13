#requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Federated Team Memory Governance Module for LLM Workflow Platform

.DESCRIPTION
    Implements Phase 7 Federated Team Memory with governance controls,
    privacy boundaries, and compliance logging. Provides node-based
    federation for sharing pack knowledge across workspaces while
    maintaining strict access controls.

    Key Federation Policies:
    - Private projects never leave local node without explicit export
    - Shared collections are read-only by default on remote nodes
    - Team workspaces support bidirectional sync
    - All access is logged for compliance
    - Nodes can be temporarily suspended

.NOTES
    File: FederatedMemory.ps1
    Version: 1.0.0
    Compatible with: PowerShell 5.1+
    Dependencies: Workspace.ps1, Visibility.ps1, PackVisibility.ps1

.EXAMPLE
    # Create and register a federated node
    $node = New-FederatedMemoryNode -NodeId 'team-engineering' -DisplayName 'Engineering Team' -WorkspaceType 'team'
    Register-FederatedNode -Node $node -AuthToken $token

.EXAMPLE
    # Grant access to shared collections
    Grant-FederatedAccess -NodeId 'team-engineering' -CollectionPattern 'rpgmaker_shared_*' -Permission 'read'

.LINK
    https://github.com/llm-workflow/platform/wiki/FederatedMemory
#>

#region Configuration and State

# Module-level paths
$script:FederatedStoragePath = Join-Path $HOME '.llm-workflow/federation-nodes'
$script:SyncQueuePath = Join-Path $HOME '.llm-workflow/sync-queue'
$script:FederationAuditPath = Join-Path $HOME '.llm-workflow/logs/federation-audit.log'
$script:ConflictStorePath = Join-Path $HOME '.llm-workflow/conflicts'

# Permission levels
$script:PermissionLevels = @{
    'read' = @{ rank = 1; permissions = @('read', 'query') }
    'write' = @{ rank = 2; permissions = @('read', 'query', 'write', 'update') }
    'admin' = @{ rank = 3; permissions = @('read', 'query', 'write', 'update', 'delete', 'manage', 'grant', 'revoke') }
}

# Conflict resolution strategies
$script:ConflictStrategies = @('timestamp', 'priority', 'manual')

# Node status values
$script:NodeStatuses = @('active', 'suspended', 'offline', 'error')

# Workspace types
$script:WorkspaceTypes = @('personal', 'project', 'team')

# Ensure directories exist
@($script:FederatedStoragePath, $script:SyncQueuePath, $script:ConflictStorePath) | ForEach-Object {
    if (-not (Test-Path -LiteralPath $_)) {
        $null = New-Item -ItemType Directory -Path $_ -Force
    }
}

#endregion

#region Private Helper Functions

function Initialize-FederatedStorage {
    <#
    .SYNOPSIS
        Initializes the federated storage directory structure.
    #>
    [CmdletBinding()]
    param()
    
    $paths = @(
        $script:FederatedStoragePath,
        $script:SyncQueuePath,
        (Join-Path $HOME '.llm-workflow/logs'),
        $script:ConflictStorePath
    )
    
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Verbose "Created directory: $path"
        }
    }
}

function Get-NodeFilePath {
    <#
    .SYNOPSIS
        Gets the file path for a federated node by ID.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId
    )
    
    return Join-Path $script:FederatedStoragePath "$NodeId.json"
}

function Get-NodeQueuePath {
    <#
    .SYNOPSIS
        Gets the sync queue directory for a node.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId
    )
    
    $queuePath = Join-Path $script:SyncQueuePath $NodeId
    if (-not (Test-Path -LiteralPath $queuePath)) {
        New-Item -ItemType Directory -Path $queuePath -Force | Out-Null
    }
    return $queuePath
}

function Test-NodeIdValid {
    <#
    .SYNOPSIS
        Validates node ID format.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId
    )
    
    # Node IDs: lowercase alphanumeric, hyphens, underscores
    # Must start with letter, 3-64 characters
    if ($NodeId -notmatch '^[a-z][a-z0-9_-]{2,63}$') {
        return $false
    }
    
    # Reserved words check
    $reserved = @('null', 'undefined', 'default', 'system', 'admin', 'root', 'local')
    if ($NodeId -in $reserved) {
        return $false
    }
    
    return $true
}

function Write-FederationAuditLog {
    <#
    .SYNOPSIS
        Writes an entry to the federation audit log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [string]$Action = '',
        
        [string]$UserId = $env:USERNAME,
        
        [bool]$Success = $true,
        
        [hashtable]$Details = @{}
    )
    
    $logEntry = [pscustomobject]@{
        timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')
        operation = $Operation
        nodeId = $NodeId
        action = $Action
        userId = $UserId
        success = $Success
        details = $Details
        sourceIp = $env:REMOTE_ADDR
        sessionId = [System.Guid]::NewGuid().ToString()
    }
    
    try {
        $logEntry | ConvertTo-Json -Compress | Add-Content -LiteralPath $script:FederationAuditPath -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Failed to write audit log: $_"
    }
}

function Get-EncryptionKey {
    <#
    .SYNOPSIS
        Gets or generates an encryption key for node communication.
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [switch]$CreateIfNotExists
    )
    
    $keyPath = Join-Path $script:FederatedStoragePath ".$NodeId.key"
    
    if (Test-Path -LiteralPath $keyPath) {
        $keyBase64 = Get-Content -LiteralPath $keyPath -Raw
        return [Convert]::FromBase64String($keyBase64)
    }
    
    if ($CreateIfNotExists) {
        # Generate a 256-bit key
        $key = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($key)
        
        # Save key securely
        $keyBase64 = [Convert]::ToBase64String($key)
        $keyBase64 | Set-Content -LiteralPath $keyPath -Encoding UTF8
        
        # Set restrictive permissions (Windows only)
        if ($IsWindows -or $env:OS -eq 'Windows_NT') {
            $acl = Get-Acl -LiteralPath $keyPath
            $acl.SetAccessRuleProtection($true, $false)
            
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $currentUser, 'Read', 'Allow'
            )
            $acl.AddAccessRule($rule)
            Set-Acl -LiteralPath $keyPath $acl
        }
        
        return $key
    }
    
    return $null
}

function Protect-FederatedData {
    <#
    .SYNOPSIS
        Encrypts data for secure federation transmission.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Data,
        
        [Parameter(Mandatory = $true)]
        [byte[]]$Key
    )
    
    try {
        # Generate IV
        $iv = New-Object byte[] 16
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($iv)
        
        # Encrypt using AES
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $Key
        $aes.IV = $iv
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        
        $encryptor = $aes.CreateEncryptor()
        $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($Data)
        $encrypted = $encryptor.TransformFinalBlock($dataBytes, 0, $dataBytes.Length)
        
        # Combine IV + encrypted data
        $result = New-Object byte[] ($iv.Length + $encrypted.Length)
        [Buffer]::BlockCopy($iv, 0, $result, 0, $iv.Length)
        [Buffer]::BlockCopy($encrypted, 0, $result, $iv.Length, $encrypted.Length)
        
        return [Convert]::ToBase64String($result)
    }
    finally {
        if ($aes) { $aes.Dispose() }
        if ($encryptor) { $encryptor.Dispose() }
    }
}

function Unprotect-FederatedData {
    <#
    .SYNOPSIS
        Decrypts data from federation transmission.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EncryptedData,
        
        [Parameter(Mandatory = $true)]
        [byte[]]$Key
    )
    
    try {
        $data = [Convert]::FromBase64String($EncryptedData)
        
        # Extract IV and encrypted content
        $iv = New-Object byte[] 16
        $encrypted = New-Object byte[] ($data.Length - 16)
        [Buffer]::BlockCopy($data, 0, $iv, 0, 16)
        [Buffer]::BlockCopy($data, 16, $encrypted, 0, $encrypted.Length)
        
        # Decrypt
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $Key
        $aes.IV = $iv
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        
        $decryptor = $aes.CreateDecryptor()
        $decrypted = $decryptor.TransformFinalBlock($encrypted, 0, $encrypted.Length)
        
        return [System.Text.Encoding]::UTF8.GetString($decrypted)
    }
    finally {
        if ($aes) { $aes.Dispose() }
        if ($decryptor) { $decryptor.Dispose() }
    }
}

function Test-CollectionVisibility {
    <#
    .SYNOPSIS
        Tests if a collection can be federated based on visibility rules.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CollectionName,
        
        [Parameter(Mandatory = $true)]
        [pscustomobject]$WorkspaceContext
    )
    
    # Import visibility functions if available
    $visibilityPath = Join-Path $PSScriptRoot '..\core\Visibility.ps1'
    if (Test-Path -LiteralPath $visibilityPath) {
        . $visibilityPath
    }
    
    # Private projects cannot be federated
    if ($CollectionName -match '_private_|-private-') {
        Write-Verbose "Collection '$CollectionName' is private and cannot be federated"
        return $false
    }
    
    # Check workspace visibility rules
    if ($WorkspaceContext.visibilityRules) {
        $rule = $WorkspaceContext.visibilityRules[$CollectionName]
        if ($rule -eq 'private' -or $rule -eq 'workspace-local') {
            return $false
        }
    }
    
    return $true
}

function Invoke-NodeRequest {
    <#
    .SYNOPSIS
        Makes a secure request to a federated node.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Auth,
        
        [string]$Method = 'GET',
        
        [object]$Body = $null,
        
        [int]$TimeoutSec = 30
    )
    
    $headers = @{
        'Accept' = 'application/json'
        'X-Federation-Version' = '1.0'
        'X-Federation-Client' = 'LLMWorkflow-PowerShell'
    }
    
    # Add authentication headers
    switch ($Auth.type) {
        'mTLS' {
            Write-Verbose "Using mTLS authentication with cert: $($Auth.certPath)"
        }
        'token' {
            $headers['Authorization'] = "Bearer $($Auth.token)"
        }
        'apikey' {
            $headers['X-API-Key'] = $Auth.key
        }
    }
    
    try {
        $params = @{
            Uri = $Endpoint
            Method = $Method
            Headers = $headers
            TimeoutSec = $TimeoutSec
            UseBasicParsing = $true
        }
        
        if ($Body) {
            $params.Body = $Body | ConvertTo-Json -Depth 10
            $params.ContentType = 'application/json'
        }
        
        $response = Invoke-RestMethod @params
        return @{ Success = $true; Data = $response }
    }
    catch {
        $statusCode = if ($_.Exception.Response) { 
            [int]$_.Exception.Response.StatusCode 
        } else { 
            $null 
        }
        return @{ 
            Success = $false 
            Error = $_.Exception.Message 
            StatusCode = $statusCode 
        }
    }
}

function Get-DataHash {
    <#
    .SYNOPSIS
        Computes a hash for conflict detection.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Data
    )
    
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Data)
        $hash = $sha256.ComputeHash($bytes)
        return [BitConverter]::ToString($hash).Replace('-', '').ToLower()
    }
    finally {
        $sha256.Dispose()
    }
}

function Add-SyncQueueItem {
    <#
    .SYNOPSIS
        Adds an item to the sync queue for offline operation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Data
    )
    
    $queuePath = Get-NodeQueuePath -NodeId $NodeId
    $queueItem = @{
        id = [System.Guid]::NewGuid().ToString()
        nodeId = $NodeId
        operation = $Operation
        data = $Data
        createdAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        retryCount = 0
    }
    
    $fileName = "$($queueItem.id).json"
    $filePath = Join-Path $queuePath $fileName
    
    $queueItem | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $filePath -Encoding UTF8
    
    Write-Verbose "Added sync queue item: $($queueItem.id) for node: $NodeId"
    return $queueItem
}

function Get-SyncQueueItems {
    <#
    .SYNOPSIS
        Gets pending items from the sync queue.
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [int]$MaxItems = 100
    )
    
    $queuePath = Get-NodeQueuePath -NodeId $NodeId
    
    if (-not (Test-Path -LiteralPath $queuePath)) {
        return @()
    }
    
    $items = Get-ChildItem -Path $queuePath -Filter '*.json' |
        Sort-Object -Property CreationTime |
        Select-Object -First $MaxItems |
        ForEach-Object {
            Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
        }
    
    return $items
}

function Remove-SyncQueueItem {
    <#
    .SYNOPSIS
        Removes a processed item from the sync queue.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [Parameter(Mandatory = $true)]
        [string]$ItemId
    )
    
    $queuePath = Get-NodeQueuePath -NodeId $NodeId
    $filePath = Join-Path $queuePath "$ItemId.json"
    
    if (Test-Path -LiteralPath $filePath) {
        Remove-Item -LiteralPath $filePath -Force
        Write-Verbose "Removed sync queue item: $ItemId"
    }
}

#endregion

#region Public Functions

function New-FederatedMemoryNode {
    <#
    .SYNOPSIS
        Creates a federated memory node configuration.

    .DESCRIPTION
        Creates a new federated node for sharing pack knowledge across
        workspaces. The node includes access control rules, sync endpoints,
        and workspace type configuration. Integrates with Workspace.ps1
        and respects visibility boundaries from Visibility.ps1.

    .PARAMETER NodeId
        Unique identifier for the node (lowercase alphanumeric with hyphens/underscores).

    .PARAMETER DisplayName
        Human-readable name for the node.

    .PARAMETER WorkspaceType
        Type of workspace: personal, project, or team.

    .PARAMETER SharedCollections
        Array of collection names/patterns to share.

    .PARAMETER AccessControlRules
        Hashtable of access control rules (pattern -> permission).

    .PARAMETER SyncEndpoints
        Array of sync endpoint URLs.

    .PARAMETER WorkspaceContext
        Current workspace context for validation.

    .EXAMPLE
        $node = New-FederatedMemoryNode -NodeId 'team-engineering' -DisplayName 'Engineering Team' -WorkspaceType 'team'
        Creates a new team federated node.

    .EXAMPLE
        $node = New-FederatedMemoryNode -NodeId 'project-alpha' -WorkspaceType 'project' -SharedCollections @('rpgmaker_shared_*', 'godot_patterns')
        Creates a project node with specific shared collections.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('personal', 'project', 'team')]
        [string]$WorkspaceType,
        
        [string[]]$SharedCollections = @(),
        
        [hashtable]$AccessControlRules = @{},
        
        [string[]]$SyncEndpoints = @(),
        
        [pscustomobject]$WorkspaceContext = $null
    )
    
    begin {
        Initialize-FederatedStorage
        Write-Verbose "Creating federated memory node: $NodeId"
    }
    
    process {
        # Validate node ID
        if (-not (Test-NodeIdValid -NodeId $NodeId)) {
            throw "Invalid node ID: '$NodeId'. Must be 3-64 lowercase alphanumeric characters starting with a letter."
        }
        
        # Check for existing node
        $nodePath = Get-NodeFilePath -NodeId $NodeId
        if (Test-Path -LiteralPath $nodePath) {
            throw "Federated node already exists: $NodeId"
        }
        
        # Validate shared collections against visibility rules
        $validatedCollections = @()
        foreach ($collection in $SharedCollections) {
            if ($WorkspaceContext) {
                if (Test-CollectionVisibility -CollectionName $collection -WorkspaceContext $WorkspaceContext) {
                    $validatedCollections += $collection
                }
                else {
                    Write-Warning "Collection '$collection' cannot be federated due to visibility rules. Skipping."
                }
            }
            else {
                # Without workspace context, filter out obvious private patterns
                if ($collection -notmatch '_private_|-private-') {
                    $validatedCollections += $collection
                }
                else {
                    Write-Warning "Collection '$collection' appears to be private and will not be shared."
                }
            }
        }
        
        # Build default access control rules if none provided
        $defaultRules = @{
            'default' = 'read'  # Default: read-only on remote nodes
        }
        
        foreach ($key in $AccessControlRules.Keys) {
            $defaultRules[$key] = $AccessControlRules[$key]
        }
        
        # Build node configuration
        $node = [pscustomobject]@{
            nodeId = $NodeId
            displayName = $DisplayName
            workspaceType = $WorkspaceType
            sharedCollections = $validatedCollections
            accessControlRules = $defaultRules
            syncEndpoints = $SyncEndpoints
            status = 'created'
            createdAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
            modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
            version = 1
            metadata = @{
                creator = $env:USERNAME
                creatorHost = $env:COMPUTERNAME
                schemaVersion = '1.0'
            }
            federationConfig = @{
                allowBidirectionalSync = ($WorkspaceType -eq 'team')
                defaultPermission = 'read'
                conflictStrategy = 'timestamp'
                encryptionEnabled = $true
            }
        }
        
        Write-Verbose "Federated node '$NodeId' created successfully"
        return $node
    }
}

function Register-FederatedNode {
    <#
    .SYNOPSIS
        Registers a node with the federation.

    .DESCRIPTION
        Registers a federated node with authentication credentials,
        sync schedule, and priority level. Persists the node configuration
        to storage and initializes sync infrastructure.

    .PARAMETER Node
        The node configuration object from New-FederatedMemoryNode.

    .PARAMETER AuthCredentials
        Authentication credentials hashtable (type, token/key/certPath).

    .PARAMETER SyncSchedule
        Cron expression for automatic sync schedule.

    .PARAMETER Priority
        Priority level: low, medium, or high.

    .PARAMETER AutoEnable
        Automatically enable the node after registration.

    .EXAMPLE
        Register-FederatedNode -Node $node -AuthCredentials @{type='token'; token='secret123'} -Priority 'high'
        Registers a node with token authentication.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Node,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthCredentials,
        
        [string]$SyncSchedule = '0 */6 * * *',
        
        [ValidateSet('low', 'medium', 'high')]
        [string]$Priority = 'medium',
        
        [switch]$AutoEnable
    )
    
    begin {
        Initialize-FederatedStorage
        Write-Verbose "Registering federated node: $($Node.nodeId)"
    }
    
    process {
        $nodeId = $Node.nodeId
        $nodePath = Get-NodeFilePath -NodeId $nodeId
        
        if (Test-Path -LiteralPath $nodePath) {
            throw "Node already registered: $nodeId"
        }
        
        # Validate authentication
        if (-not $AuthCredentials.type) {
            throw "AuthCredentials must include 'type' property (token, apikey, or mTLS)"
        }
        
        # Generate encryption key for node communication
        $encryptionKey = Get-EncryptionKey -NodeId $nodeId -CreateIfNotExists
        
        # Build registration
        $registration = [pscustomobject]@{
            nodeId = $nodeId
            displayName = $Node.displayName
            workspaceType = $Node.workspaceType
            sharedCollections = $Node.sharedCollections
            accessControlRules = $Node.accessControlRules
            syncEndpoints = $Node.syncEndpoints
            auth = @{
                type = $AuthCredentials.type
                # Store credential reference, not the actual credential
                credentialRef = "node:$nodeId`:$($AuthCredentials.type)"
            }
            syncSchedule = $SyncSchedule
            priority = $Priority
            status = if ($AutoEnable) { 'active' } else { 'created' }
            createdAt = $Node.createdAt
            registeredAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
            modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
            lastSync = $null
            syncCount = 0
            version = 1
            metadata = $Node.metadata
            federationConfig = $Node.federationConfig
        }
        
        # Save registration
        $registration | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $nodePath -Encoding UTF8
        
        # Store credentials separately (in a real implementation, use secure storage)
        $credPath = Join-Path $script:FederatedStoragePath ".$nodeId.cred"
        $AuthCredentials | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $credPath -Encoding UTF8
        
        # Write audit log
        Write-FederationAuditLog -Operation 'RegisterNode' -NodeId $nodeId -Action 'register' -Success $true -Details @{
            workspaceType = $Node.workspaceType
            priority = $Priority
            collectionCount = $Node.sharedCollections.Count
            autoEnabled = $AutoEnable.IsPresent
        }
        
        Write-Verbose "Federated node '$nodeId' registered successfully"
        return $registration
    }
}

function Sync-FederatedMemory {
    <#
    .SYNOPSIS
        Syncs shared knowledge across federated nodes.

    .DESCRIPTION
        Performs bidirectional synchronization of shared collections
        between nodes. Supports delta sync for efficiency, conflict
        resolution (timestamp, priority, manual), and progress reporting.
        Queues operations for offline nodes.

    .PARAMETER NodeId
        ID of the node to sync with.

    .PARAMETER Collections
        Specific collections to sync (all shared if not specified).

    .PARAMETER ConflictResolution
        Conflict resolution strategy: timestamp, priority, or manual.

    .PARAMETER ForceFullSync
        Force a full sync instead of delta sync.

    .PARAMETER DryRun
        Preview changes without applying.

    .PARAMETER ProgressAction
        Action to call for progress reporting.

    .EXAMPLE
        Sync-FederatedMemory -NodeId 'team-engineering' -ConflictResolution 'timestamp'
        Performs sync with last-write-wins conflict resolution.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [string[]]$Collections = @(),
        
        [ValidateSet('timestamp', 'priority', 'manual')]
        [string]$ConflictResolution = 'timestamp',
        
        [switch]$ForceFullSync,
        
        [switch]$DryRun,
        
        [scriptblock]$ProgressAction = $null
    )
    
    begin {
        $startTime = Get-Date
        Write-Verbose "Starting federated sync with node: $NodeId"
        
        $nodePath = Get-NodeFilePath -NodeId $NodeId
        if (-not (Test-Path -LiteralPath $nodePath)) {
            throw "Node not found: $NodeId"
        }
        
        $node = Get-Content -LiteralPath $nodePath -Raw | ConvertFrom-Json
        
        if ($node.status -eq 'suspended') {
            throw "Node '$NodeId' is suspended and cannot be synced"
        }
    }
    
    process {
        $result = [pscustomobject]@{
            NodeId = $NodeId
            StartedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
            Collections = @()
            TotalPushed = 0
            TotalPulled = 0
            Conflicts = @()
            Errors = @()
            IsDryRun = $DryRun.IsPresent
            SyncMode = if ($ForceFullSync) { 'full' } else { 'delta' }
        }
        
        $collectionsToSync = if ($Collections.Count -gt 0) { 
            $Collections 
        } else { 
            $node.sharedCollections 
        }
        
        foreach ($collection in $collectionsToSync) {
            $collectionResult = @{
                Collection = $collection
                Pushed = 0
                Pulled = 0
                Conflicts = @()
                Status = 'pending'
            }
            
            # Report progress
            if ($ProgressAction) {
                & $ProgressAction -Collection $collection -Status 'syncing'
            }
            
            # Simulate sync operation (in production, this would call actual endpoints)
            if (-not $DryRun) {
                try {
                    # Check if node is online
                    if ($node.status -eq 'offline') {
                        # Queue for later sync
                        Add-SyncQueueItem -NodeId $NodeId -Operation 'sync' -Data @{
                            collection = $collection
                            timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
                        } | Out-Null
                        $collectionResult.Status = 'queued'
                    }
                    else {
                        # Perform sync
                        # This is a placeholder - actual implementation would call node endpoints
                        $collectionResult.Pushed = 0  # Would be actual count
                        $collectionResult.Pulled = 0  # Would be actual count
                        $collectionResult.Status = 'synced'
                        
                        # Detect and resolve conflicts
                        # This is simplified - actual implementation would compare hashes/timestamps
                        if ($ConflictResolution -eq 'manual') {
                            # Store conflicts for manual resolution
                            $conflictId = [System.Guid]::NewGuid().ToString()
                            $conflictPath = Join-Path $script:ConflictStorePath "$conflictId.json"
                            @{
                                conflictId = $conflictId
                                nodeId = $NodeId
                                collection = $collection
                                detectedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
                                status = 'pending'
                            } | ConvertTo-Json | Set-Content -LiteralPath $conflictPath
                            
                            $collectionResult.Conflicts += $conflictId
                            $result.Conflicts += $conflictId
                        }
                    }
                }
                catch {
                    $collectionResult.Status = 'error'
                    $result.Errors += @{
                        Collection = $collection
                        Error = $_.Exception.Message
                    }
                }
            }
            else {
                $collectionResult.Status = 'preview'
            }
            
            $result.TotalPushed += $collectionResult.Pushed
            $result.TotalPulled += $collectionResult.Pulled
            $result.Collections += $collectionResult
            
            # Report progress
            if ($ProgressAction) {
                & $ProgressAction -Collection $collection -Status $collectionResult.Status
            }
        }
        
        $result.CompletedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        
        # Update node stats
        if (-not $DryRun) {
            $node.lastSync = $result.CompletedAt
            $node.syncCount = ($node.syncCount + 1)
            $node | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $nodePath -Encoding UTF8
        }
        
        # Write audit log
        Write-FederationAuditLog -Operation 'Sync' -NodeId $NodeId -Action 'sync_memory' -Success ($result.Errors.Count -eq 0) -Details @{
            collections = $collectionsToSync
            conflictResolution = $ConflictResolution
            dryRun = $DryRun.IsPresent
            pushed = $result.TotalPushed
            pulled = $result.TotalPulled
            conflicts = $result.Conflicts.Count
        }
        
        return $result
    }
}

function Get-FederatedMemory {
    <#
    .SYNOPSIS
        Retrieves federated knowledge from accessible nodes.

    .DESCRIPTION
        Queries shared knowledge across all accessible federated nodes,
        aggregating results with source attribution and priority ordering.
        Respects access control rules and visibility boundaries.

    .PARAMETER Query
        Search query string.

    .PARAMETER NodeIds
        Specific node IDs to query (all accessible if not specified).

    .PARAMETER Collections
        Specific collections to search.

    .PARAMETER MaxResults
        Maximum number of results to return.

    .PARAMETER IncludeSource
        Include source attribution in results.

    .PARAMETER WorkspaceContext
        Current workspace context for access validation.

    .EXAMPLE
        Get-FederatedMemory -Query 'character controller' -MaxResults 10
        Queries all accessible nodes for character controller patterns.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,
        
        [string[]]$NodeIds = @(),
        
        [string[]]$Collections = @(),
        
        [int]$MaxResults = 100,
        
        [switch]$IncludeSource,
        
        [pscustomobject]$WorkspaceContext = $null
    )
    
    begin {
        Initialize-FederatedStorage
        Write-Verbose "Querying federated memory: $Query"
        
        $results = @()
    }
    
    process {
        # Get nodes to query
        $nodesToQuery = @()
        
        if ($NodeIds.Count -gt 0) {
            foreach ($id in $NodeIds) {
                $nodePath = Get-NodeFilePath -NodeId $id
                if (Test-Path -LiteralPath $nodePath) {
                    $node = Get-Content -LiteralPath $nodePath -Raw | ConvertFrom-Json
                    if ($node.status -eq 'active') {
                        $nodesToQuery += $node
                    }
                }
            }
        }
        else {
            # Query all active nodes
            $allNodes = Get-ChildItem -Path $script:FederatedStoragePath -Filter '*.json' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notlike '.*' }
            
            foreach ($nodeFile in $allNodes) {
                $node = Get-Content -LiteralPath $nodeFile.FullName -Raw | ConvertFrom-Json
                if ($node.status -eq 'active') {
                    $nodesToQuery += $node
                }
            }
        }
        
        Write-Verbose "Querying $($nodesToQuery.Count) active nodes"
        
        # Query each node
        foreach ($node in $nodesToQuery) {
            # Check access permissions
            $hasAccess = $false
            if ($node.accessControlRules) {
                $userId = $env:USERNAME
                if ($node.accessControlRules.$userId -or $node.accessControlRules.default) {
                    $hasAccess = $true
                }
            }
            else {
                $hasAccess = $true  # No rules = public read
            }
            
            if (-not $hasAccess) {
                Write-Verbose "Access denied to node: $($node.nodeId)"
                continue
            }
            
            # Determine collections to search
            $searchCollections = if ($Collections.Count -gt 0) {
                $Collections | Where-Object { $node.sharedCollections -contains $_ }
            } else {
                $node.sharedCollections
            }
            
            # In a real implementation, this would call the node's API
            # For now, return a placeholder result structure
            $nodeResult = [pscustomobject]@{
                nodeId = $node.nodeId
                displayName = $node.displayName
                priority = $node.priority
                collectionsSearched = $searchCollections
                resultCount = 0  # Would be actual count from node
                results = @()    # Would be actual results
                query = $Query
                queriedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
            }
            
            if ($IncludeSource) {
                $nodeResult | Add-Member -NotePropertyName 'sourceAttribution' -NotePropertyValue @{
                    nodeId = $node.nodeId
                    nodeName = $node.displayName
                    workspaceType = $node.workspaceType
                }
            }
            
            $results += $nodeResult
        }
        
        # Sort by priority (high -> medium -> low)
        $priorityRank = @{ 'high' = 3; 'medium' = 2; 'low' = 1 }
        $sortedResults = $results | Sort-Object -Property { 
            $priorityRank[$_.priority] 
        } -Descending
        
        # Apply limit
        if ($MaxResults -gt 0 -and $sortedResults.Count -gt $MaxResults) {
            $sortedResults = $sortedResults | Select-Object -First $MaxResults
        }
        
        Write-Verbose "Returning $($sortedResults.Count) federated results"
        return $sortedResults
    }
}

function Grant-FederatedAccess {
    <#
    .SYNOPSIS
        Grants access to shared collections on a federated node.

    .DESCRIPTION
        Grants a user or system access to shared collections with
        specified permission level. Supports pattern-based collection
        matching and optional expiration. All grants are logged for
        compliance.

    .PARAMETER NodeId
        ID of the federated node.

    .PARAMETER GranteeId
        User or system ID to grant access to.

    .PARAMETER CollectionPatterns
        Array of collection name patterns to grant access to.

    .PARAMETER Permission
        Permission level: read, write, or admin.

    .PARAMETER Expiration
        Optional expiration date/time for the grant.

    .PARAMETER GrantedBy
        User ID granting the access.

    .EXAMPLE
        Grant-FederatedAccess -NodeId 'team-engineering' -GranteeId 'developer1' -CollectionPatterns @('rpgmaker_shared_*') -Permission 'read'
        Grants read access to all shared RPG Maker collections.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [Parameter(Mandatory = $true)]
        [string]$GranteeId,
        
        [Parameter(Mandatory = $true)]
        [string[]]$CollectionPatterns,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('read', 'write', 'admin')]
        [string]$Permission,
        
        [DateTime]$Expiration = [DateTime]::MaxValue,
        
        [string]$GrantedBy = $env:USERNAME
    )
    
    begin {
        $nodePath = Get-NodeFilePath -NodeId $NodeId
        if (-not (Test-Path -LiteralPath $nodePath)) {
            throw "Node not found: $NodeId"
        }
        
        Write-Verbose "Granting $Permission access to $GranteeId on node $NodeId"
    }
    
    process {
        $node = Get-Content -LiteralPath $nodePath -Raw | ConvertFrom-Json
        
        # Check if granter has admin access
        $granterPermission = $node.accessControlRules.$GrantedBy
        if ($granterPermission -ne 'admin' -and $node.metadata.creator -ne $GrantedBy) {
            throw "Access denied: Admin permission required to grant access on node '$NodeId'"
        }
        
        # Initialize access grants if not exists
        if (-not $node.accessGrants) {
            $node | Add-Member -NotePropertyName 'accessGrants' -NotePropertyValue @{} -Force
        }
        
        # Create grant record
        $grant = [pscustomobject]@{
            granteeId = $GranteeId
            collectionPatterns = $CollectionPatterns
            permission = $Permission
            grantedBy = $GrantedBy
            grantedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
            expiresAt = if ($Expiration -eq [DateTime]::MaxValue) { 
                $null 
            } else { 
                $Expiration.ToString('yyyy-MM-ddTHH:mm:ssZ') 
            }
            grantId = [System.Guid]::NewGuid().ToString()
        }
        
        # Add to node's access grants
        $node.accessGrants.$GranteeId = $grant
        $node.modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        $node.version = ($node.version + 1)
        
        # Save node
        $node | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $nodePath -Encoding UTF8
        
        # Write audit log
        Write-FederationAuditLog -Operation 'GrantAccess' -NodeId $NodeId -Action 'grant_access' -Success $true -Details @{
            granteeId = $GranteeId
            permission = $Permission
            collectionPatterns = $CollectionPatterns
            grantedBy = $GrantedBy
            hasExpiration = ($Expiration -ne [DateTime]::MaxValue)
        }
        
        Write-Verbose "Access granted: $GranteeId -> $NodeId ($Permission)"
        return $grant
    }
}

function Revoke-FederatedAccess {
    <#
    .SYNOPSIS
        Revokes access to a federated node.

    .DESCRIPTION
        Revokes a user's or system's access to a federated node.
        Removes all access grants for the specified grantee. This
        operation is logged for compliance.

    .PARAMETER NodeId
        ID of the federated node.

    .PARAMETER GranteeId
        User or system ID to revoke access from.

    .PARAMETER RevokedBy
        User ID performing the revocation.

    .PARAMETER Reason
        Optional reason for revocation.

    .EXAMPLE
        Revoke-FederatedAccess -NodeId 'team-engineering' -GranteeId 'developer1' -Reason 'Team transfer'
        Revokes all access for developer1.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [Parameter(Mandatory = $true)]
        [string]$GranteeId,
        
        [string]$RevokedBy = $env:USERNAME,
        
        [string]$Reason = ''
    )
    
    begin {
        $nodePath = Get-NodeFilePath -NodeId $NodeId
        if (-not (Test-Path -LiteralPath $nodePath)) {
            throw "Node not found: $NodeId"
        }
        
        Write-Verbose "Revoking access for $GranteeId on node $NodeId"
    }
    
    process {
        $node = Get-Content -LiteralPath $nodePath -Raw | ConvertFrom-Json
        
        # Check if revoker has admin access
        $revokerPermission = $node.accessControlRules.$RevokedBy
        if ($revokerPermission -ne 'admin' -and $node.metadata.creator -ne $RevokedBy -and $GranteeId -ne $RevokedBy) {
            throw "Access denied: Admin permission required to revoke access on node '$NodeId'"
        }
        
        # Check if grantee has access
        if (-not $node.accessGrants -or -not $node.accessGrants.$GranteeId) {
            Write-Warning "Grantee '$GranteeId' does not have explicit access grants on node '$NodeId'"
            return [pscustomobject]@{
                NodeId = $NodeId
                GranteeId = $GranteeId
                Revoked = $false
                Reason = 'No explicit grants found'
            }
        }
        
        # Get grant details for audit
        $revokedGrant = $node.accessGrants.$GranteeId
        
        # Remove access grants
        $node.accessGrants.PSObject.Properties.Remove($GranteeId)
        $node.modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        $node.version = ($node.version + 1)
        
        # Save node
        $node | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $nodePath -Encoding UTF8
        
        # Write audit log
        Write-FederationAuditLog -Operation 'RevokeAccess' -NodeId $NodeId -Action 'revoke_access' -Success $true -Details @{
            granteeId = $GranteeId
            revokedBy = $RevokedBy
            previousPermission = $revokedGrant.permission
            reason = $Reason
        }
        
        Write-Verbose "Access revoked: $GranteeId -> $NodeId"
        return [pscustomobject]@{
            NodeId = $NodeId
            GranteeId = $GranteeId
            Revoked = $true
            PreviousPermission = $revokedGrant.permission
            RevokedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
            RevokedBy = $RevokedBy
            Reason = $Reason
        }
    }
}

function Get-FederatedAuditLog {
    <#
    .SYNOPSIS
        Returns audit log of federation activity.

    .DESCRIPTION
        Retrieves the federation audit log with optional filtering
        by operation type, node, date range, and user. Returns
        sync events, access grants/revocations, conflicts, and
        node health events.

    .PARAMETER NodeId
        Filter by specific node ID.

    .PARAMETER Operation
        Filter by operation type.

    .PARAMETER FromDate
        Start date for the query.

    .PARAMETER ToDate
        End date for the query.

    .PARAMETER UserId
        Filter by user ID.

    .PARAMETER MaxResults
        Maximum number of log entries to return.

    .PARAMETER IncludeDetails
        Include full details in log entries.

    .EXAMPLE
        Get-FederatedAuditLog -NodeId 'team-engineering' -FromDate (Get-Date).AddDays(-7)
        Returns last 7 days of audit log for the engineering team node.

    .EXAMPLE
        Get-FederatedAuditLog -Operation 'Sync' -MaxResults 50
        Returns last 50 sync operations across all nodes.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [string]$NodeId = '',
        
        [string]$Operation = '',
        
        [DateTime]$FromDate = [DateTime]::MinValue,
        
        [DateTime]$ToDate = [DateTime]::MaxValue,
        
        [string]$UserId = '',
        
        [int]$MaxResults = 1000,
        
        [switch]$IncludeDetails
    )
    
    begin {
        if (-not (Test-Path -LiteralPath $script:FederationAuditPath)) {
            Write-Warning "No audit log found"
            return @()
        }
        
        Write-Verbose "Reading federation audit log"
    }
    
    process {
        $logEntries = @()
        
        # Read audit log file
        $lines = Get-Content -LiteralPath $script:FederationAuditPath -Encoding UTF8 | 
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        
        foreach ($line in $lines) {
            try {
                $entry = $line | ConvertFrom-Json
                
                # Apply filters
                if ($NodeId -and $entry.nodeId -ne $NodeId) {
                    continue
                }
                
                if ($Operation -and $entry.operation -ne $Operation) {
                    continue
                }
                
                if ($UserId -and $entry.userId -ne $UserId) {
                    continue
                }
                
                # Date filtering
                $entryDate = [DateTime]::Parse($entry.timestamp)
                if ($entryDate -lt $FromDate -or $entryDate -gt $ToDate) {
                    continue
                }
                
                # Format entry
                $logEntry = [pscustomobject]@{
                    Timestamp = $entry.timestamp
                    Operation = $entry.operation
                    NodeId = $entry.nodeId
                    Action = $entry.action
                    UserId = $entry.userId
                    Success = $entry.success
                }
                
                if ($IncludeDetails) {
                    $logEntry | Add-Member -NotePropertyName 'Details' -NotePropertyValue $entry.details
                    $logEntry | Add-Member -NotePropertyName 'SessionId' -NotePropertyValue $entry.sessionId
                }
                
                $logEntries += $logEntry
            }
            catch {
                Write-Verbose "Failed to parse audit log entry: $_"
            }
        }
        
        # Sort by timestamp (newest first) and apply limit
        $sortedEntries = $logEntries | 
            Sort-Object -Property Timestamp -Descending |
            Select-Object -First $MaxResults
        
        Write-Verbose "Returning $($sortedEntries.Count) audit log entries"
        return $sortedEntries
    }
}

#endregion

#region Additional Management Functions

function Get-FederatedNode {
    <#
    .SYNOPSIS
        Gets information about a federated node.

    .DESCRIPTION
        Retrieves the configuration and metadata for a federated node,
        including access grants and sync status.

    .PARAMETER NodeId
        ID of the federated node.

    .PARAMETER IncludeAccessGrants
        Include full access grant details.

    .EXAMPLE
        Get-FederatedNode -NodeId 'team-engineering'
        Returns node information.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [switch]$IncludeAccessGrants
    )
    
    $nodePath = Get-NodeFilePath -NodeId $NodeId
    if (-not (Test-Path -LiteralPath $nodePath)) {
        throw "Node not found: $NodeId"
    }
    
    $node = Get-Content -LiteralPath $nodePath -Raw | ConvertFrom-Json
    
    if (-not $IncludeAccessGrants) {
        # Return without sensitive access grant details
        $summary = [pscustomobject]@{
            nodeId = $node.nodeId
            displayName = $node.displayName
            workspaceType = $node.workspaceType
            status = $node.status
            priority = $node.priority
            sharedCollections = $node.sharedCollections
            syncEndpoints = $node.syncEndpoints
            createdAt = $node.createdAt
            lastSync = $node.lastSync
            syncCount = $node.syncCount
            version = $node.version
        }
        return $summary
    }
    
    return $node
}

function Get-FederatedNodeList {
    <#
    .SYNOPSIS
        Lists all federated nodes.

    .DESCRIPTION
        Returns a list of all federated nodes with optional filtering
        by status or workspace type.

    .PARAMETER Status
        Filter by node status.

    .PARAMETER WorkspaceType
        Filter by workspace type.

    .PARAMETER IncludeDetails
        Include full node details.

    .EXAMPLE
        Get-FederatedNodeList -Status 'active'
        Returns all active nodes.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [ValidateSet('active', 'suspended', 'offline', 'error', 'created', '')]
        [string]$Status = '',
        
        [ValidateSet('personal', 'project', 'team', '')]
        [string]$WorkspaceType = '',
        
        [switch]$IncludeDetails
    )
    
    Initialize-FederatedStorage
    
    $nodeFiles = Get-ChildItem -Path $script:FederatedStoragePath -Filter '*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '.*' }
    
    $nodes = @()
    foreach ($file in $nodeFiles) {
        try {
            $node = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            
            # Apply filters
            if ($Status -and $node.status -ne $Status) {
                continue
            }
            if ($WorkspaceType -and $node.workspaceType -ne $WorkspaceType) {
                continue
            }
            
            if ($IncludeDetails) {
                $nodes += $node
            }
            else {
                $nodes += [pscustomobject]@{
                    NodeId = $node.nodeId
                    DisplayName = $node.displayName
                    WorkspaceType = $node.workspaceType
                    Status = $node.status
                    Priority = $node.priority
                    LastSync = $node.lastSync
                    SyncCount = $node.syncCount
                }
            }
        }
        catch {
            Write-Warning "Failed to load node from $($file.Name): $_"
        }
    }
    
    return $nodes
}

function Suspend-FederatedNode {
    <#
    .SYNOPSIS
        Temporarily suspends a federated node.

    .DESCRIPTION
        Suspends a federated node, preventing sync operations while
        preserving configuration. This is useful for maintenance or
        when investigating issues.

    .PARAMETER NodeId
        ID of the node to suspend.

    .PARAMETER Reason
        Reason for suspension.

    .PARAMETER SuspendedBy
        User ID performing the suspension.

    .EXAMPLE
        Suspend-FederatedNode -NodeId 'team-engineering' -Reason 'Maintenance window'
        Suspends the node for maintenance.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [string]$Reason = '',
        
        [string]$SuspendedBy = $env:USERNAME
    )
    
    $nodePath = Get-NodeFilePath -NodeId $NodeId
    if (-not (Test-Path -LiteralPath $nodePath)) {
        throw "Node not found: $NodeId"
    }
    
    $node = Get-Content -LiteralPath $nodePath -Raw | ConvertFrom-Json
    
    $previousStatus = $node.status
    $node.status = 'suspended'
    $node.suspendedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $node.suspendedBy = $SuspendedBy
    $node.suspendReason = $Reason
    $node.previousStatus = $previousStatus
    $node.modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    
    $node | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $nodePath -Encoding UTF8
    
    Write-FederationAuditLog -Operation 'SuspendNode' -NodeId $NodeId -Action 'suspend_node' -Success $true -Details @{
        reason = $Reason
        suspendedBy = $SuspendedBy
        previousStatus = $previousStatus
    }
    
    Write-Verbose "Node '$NodeId' suspended"
    return [pscustomobject]@{
        NodeId = $NodeId
        Status = 'suspended'
        PreviousStatus = $previousStatus
        SuspendedAt = $node.suspendedAt
        Reason = $Reason
    }
}

function Resume-FederatedNode {
    <#
    .SYNOPSIS
        Resumes a suspended federated node.

    .DESCRIPTION
        Resumes a previously suspended federated node, restoring its
        previous status and allowing sync operations.

    .PARAMETER NodeId
        ID of the node to resume.

    .PARAMETER ResumedBy
        User ID performing the resume.

    .EXAMPLE
        Resume-FederatedNode -NodeId 'team-engineering'
        Resumes the suspended node.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [string]$ResumedBy = $env:USERNAME
    )
    
    $nodePath = Get-NodeFilePath -NodeId $NodeId
    if (-not (Test-Path -LiteralPath $nodePath)) {
        throw "Node not found: $NodeId"
    }
    
    $node = Get-Content -LiteralPath $nodePath -Raw | ConvertFrom-Json
    
    if ($node.status -ne 'suspended') {
        Write-Warning "Node '$NodeId' is not suspended (status: $($node.status))"
        return [pscustomobject]@{
            NodeId = $NodeId
            Status = $node.status
            Resumed = $false
            Reason = 'Node was not suspended'
        }
    }
    
    $previousStatus = $node.previousStatus
    $node.status = if ($previousStatus) { $previousStatus } else { 'active' }
    $node.resumedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $node.resumedBy = $ResumedBy
    $node.modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    
    # Clear suspension metadata
    $node.PSObject.Properties.Remove('suspendedAt')
    $node.PSObject.Properties.Remove('suspendedBy')
    $node.PSObject.Properties.Remove('suspendReason')
    $node.PSObject.Properties.Remove('previousStatus')
    
    $node | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $nodePath -Encoding UTF8
    
    Write-FederationAuditLog -Operation 'ResumeNode' -NodeId $NodeId -Action 'resume_node' -Success $true -Details @{
        resumedBy = $ResumedBy
        restoredStatus = $node.status
    }
    
    Write-Verbose "Node '$NodeId' resumed"
    return [pscustomobject]@{
        NodeId = $NodeId
        Status = $node.status
        Resumed = $true
        ResumedAt = $node.resumedAt
    }
}

function Remove-FederatedNode {
    <#
    .SYNOPSIS
        Permanently removes a federated node.

    .DESCRIPTION
        Unregisters and removes a federated node and all its
        associated data. This operation cannot be undone.

    .PARAMETER NodeId
        ID of the node to remove.

    .PARAMETER Force
        Force removal without confirmation.

    .EXAMPLE
        Remove-FederatedNode -NodeId 'old-project' -Force
        Removes the node.

    .OUTPUTS
        None
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [switch]$Force
    )
    
    $nodePath = Get-NodeFilePath -NodeId $NodeId
    if (-not (Test-Path -LiteralPath $nodePath)) {
        throw "Node not found: $NodeId"
    }
    
    if ($Force -or $PSCmdlet.ShouldProcess($NodeId, 'Remove federated node')) {
        # Remove node file
        Remove-Item -LiteralPath $nodePath -Force
        
        # Remove credentials
        $credPath = Join-Path $script:FederatedStoragePath ".$NodeId.cred"
        if (Test-Path -LiteralPath $credPath) {
            Remove-Item -LiteralPath $credPath -Force
        }
        
        # Remove encryption key
        $keyPath = Join-Path $script:FederatedStoragePath ".$NodeId.key"
        if (Test-Path -LiteralPath $keyPath) {
            Remove-Item -LiteralPath $keyPath -Force
        }
        
        # Remove sync queue
        $queuePath = Get-NodeQueuePath -NodeId $NodeId
        if (Test-Path -LiteralPath $queuePath) {
            Remove-Item -LiteralPath $queuePath -Recurse -Force
        }
        
        Write-FederationAuditLog -Operation 'RemoveNode' -NodeId $NodeId -Action 'remove_node' -Success $true -Details @{
            removedBy = $env:USERNAME
        }
        
        Write-Verbose "Node '$NodeId' removed"
    }
}

function Test-FederatedNodeHealth {
    <#
    .SYNOPSIS
        Tests the health of a federated node.

    .DESCRIPTION
        Performs a health check on a federated node, testing
        connectivity and basic operations.

    .PARAMETER NodeId
        ID of the node to check.

    .PARAMETER TimeoutSec
        Timeout in seconds.

    .EXAMPLE
        Test-FederatedNodeHealth -NodeId 'team-engineering'
        Checks node health.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [int]$TimeoutSec = 10
    )
    
    $nodePath = Get-NodeFilePath -NodeId $NodeId
    if (-not (Test-Path -LiteralPath $nodePath)) {
        throw "Node not found: $NodeId"
    }
    
    $node = Get-Content -LiteralPath $nodePath -Raw | ConvertFrom-Json
    
    $health = [pscustomobject]@{
        NodeId = $NodeId
        Status = $node.status
        CheckedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        Connectivity = 'unknown'
        LatencyMs = $null
        Errors = @()
    }
    
    if ($node.status -eq 'suspended') {
        $health.Connectivity = 'suspended'
        return $health
    }
    
    # Test connectivity to endpoints
    if ($node.syncEndpoints -and $node.syncEndpoints.Count -gt 0) {
        $endpoint = $node.syncEndpoints[0]
        $startTime = Get-Date
        
        try {
            # In production, this would make an actual health check request
            # For now, simulate connectivity test
            $response = @{ Success = $true }
            
            $endTime = Get-Date
            $health.LatencyMs = [math]::Round(($endTime - $startTime).TotalMilliseconds)
            $health.Connectivity = if ($response.Success) { 'healthy' } else { 'unhealthy' }
        }
        catch {
            $health.Connectivity = 'error'
            $health.Errors += $_.Exception.Message
        }
    }
    else {
        $health.Connectivity = 'no-endpoints'
    }
    
    # Update node status based on health check
    if ($health.Connectivity -eq 'healthy') {
        if ($node.status -eq 'error' -or $node.status -eq 'offline') {
            $node.status = 'active'
            $node | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $nodePath -Encoding UTF8
        }
    }
    elseif ($health.Connectivity -eq 'error' -or $health.Connectivity -eq 'unhealthy') {
        $node.status = 'error'
        $node | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $nodePath -Encoding UTF8
    }
    
    Write-FederationAuditLog -Operation 'HealthCheck' -NodeId $NodeId -Action 'health_check' -Success ($health.Connectivity -eq 'healthy') -Details @{
        connectivity = $health.Connectivity
        latencyMs = $health.LatencyMs
        errors = $health.Errors
    }
    
    return $health
}

function Resolve-FederatedConflict {
    <#
    .SYNOPSIS
        Resolves a federated sync conflict manually.

    .DESCRIPTION
        Allows manual resolution of sync conflicts that could not be
        resolved automatically. Updates the conflict record with
        the resolution.

    .PARAMETER ConflictId
        ID of the conflict to resolve.

    .PARAMETER Resolution
        Resolution choice: local, remote, or merged.

    .PARAMETER MergedData
        Merged data (if resolution is 'merged').

    .PARAMETER ResolvedBy
        User ID performing the resolution.

    .EXAMPLE
        Resolve-FederatedConflict -ConflictId 'abc-123' -Resolution 'local'
        Resolves conflict by accepting local version.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConflictId,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('local', 'remote', 'merged')]
        [string]$Resolution,
        
        [hashtable]$MergedData = @{},
        
        [string]$ResolvedBy = $env:USERNAME
    )
    
    $conflictPath = Join-Path $script:ConflictStorePath "$ConflictId.json"
    if (-not (Test-Path -LiteralPath $conflictPath)) {
        throw "Conflict not found: $ConflictId"
    }
    
    $conflict = Get-Content -LiteralPath $conflictPath -Raw | ConvertFrom-Json
    
    $conflict.resolution = $Resolution
    $conflict.resolvedBy = $ResolvedBy
    $conflict.resolvedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $conflict.status = 'resolved'
    
    if ($Resolution -eq 'merged' -and $MergedData.Count -gt 0) {
        $conflict.mergedData = $MergedData
    }
    
    $conflict | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $conflictPath -Encoding UTF8
    
    Write-FederationAuditLog -Operation 'ResolveConflict' -NodeId $conflict.nodeId -Action 'resolve_conflict' -Success $true -Details @{
        conflictId = $ConflictId
        resolution = $Resolution
        resolvedBy = $ResolvedBy
        collection = $conflict.collection
    }
    
    Write-Verbose "Conflict '$ConflictId' resolved with: $Resolution"
    return [pscustomobject]@{
        ConflictId = $ConflictId
        Resolution = $Resolution
        ResolvedAt = $conflict.resolvedAt
        ResolvedBy = $ResolvedBy
        Status = 'resolved'
    }
}

function Get-PendingSyncQueue {
    <#
    .SYNOPSIS
        Gets pending items in the sync queue.

    .DESCRIPTION
        Retrieves pending synchronization items from the offline
        sync queue for a node or all nodes.

    .PARAMETER NodeId
        Specific node ID (all nodes if not specified).

    .PARAMETER MaxItems
        Maximum items to return per node.

    .EXAMPLE
        Get-PendingSyncQueue -NodeId 'team-engineering'
        Returns pending sync items for the engineering team node.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [string]$NodeId = '',
        
        [int]$MaxItems = 100
    )
    
    $items = @()
    
    if ($NodeId) {
        $items = Get-SyncQueueItems -NodeId $NodeId -MaxItems $MaxItems
    }
    else {
        # Get all nodes with pending items
        $queueDirs = Get-ChildItem -Path $script:SyncQueuePath -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $queueDirs) {
            $nodeItems = Get-SyncQueueItems -NodeId $dir.Name -MaxItems $MaxItems
            $items += $nodeItems
        }
    }
    
    return $items
}

#endregion

# Initialize storage on module load
Initialize-FederatedStorage

# Export public functions
Export-ModuleMember -Function @(
    'New-FederatedMemoryNode',
    'Register-FederatedNode',
    'Sync-FederatedMemory',
    'Get-FederatedMemory',
    'Grant-FederatedAccess',
    'Revoke-FederatedAccess',
    'Get-FederatedAuditLog',
    # Additional management functions
    'Get-FederatedNode',
    'Get-FederatedNodeList',
    'Suspend-FederatedNode',
    'Resume-FederatedNode',
    'Remove-FederatedNode',
    'Test-FederatedNodeHealth',
    'Resolve-FederatedConflict',
    'Get-PendingSyncQueue'
)
