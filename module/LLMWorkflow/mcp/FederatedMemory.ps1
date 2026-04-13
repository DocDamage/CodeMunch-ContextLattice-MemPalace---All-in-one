#requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Federated/Team Memory System for LLM Workflow Platform
.DESCRIPTION
    Provides shared team memory across multiple workspaces and federated 
    knowledge sharing between organizations. Supports end-to-end encryption,
    conflict resolution, access control, and GDPR compliance.
.NOTES
    File: FederatedMemory.ps1
    Version: 1.0.0
    Compatible with: PowerShell 5.1+
#>

#===============================================================================
# Configuration and State
#===============================================================================

$script:FederationStoragePath = Join-Path $HOME '.llm-workflow/federation'
$script:SharedSpacesPath = Join-Path $HOME '.llm-workflow/shared-spaces'
$script:TeamWorkspacesPath = Join-Path $HOME '.llm-workflow/team-workspaces'
$script:AuditLogPath = Join-Path $HOME '.llm-workflow/logs/federation-audit.log'
$script:SyncStatePath = Join-Path $HOME '.llm-workflow/sync-state'

# Conflict resolution strategies
$script:ConflictStrategies = @('last-write-wins', 'merge', 'manual')

# Trust levels for federation peers
$script:TrustLevels = @('low', 'medium', 'high')

# Role definitions for access control
$script:Roles = @{
    'admin' = @{ permissions = @('read', 'write', 'delete', 'manage', 'federate') }
    'editor' = @{ permissions = @('read', 'write', 'federate') }
    'viewer' = @{ permissions = @('read') }
    'auditor' = @{ permissions = @('read', 'audit') }
}

# Default retention policy (GDPR compliant)
$script:DefaultRetentionPolicy = @{
    defaultDays = 365
    sensitiveDays = 90
    auditLogDays = 2555  # 7 years for compliance
    gdprDeletionDays = 30  # Time to process deletion requests
}

#region Private Helper Functions

function Initialize-FederationStorage {
    <#
    .SYNOPSIS
        Initializes the federation storage directory structure.
    #>
    [CmdletBinding()]
    param()
    
    $paths = @(
        $script:FederationStoragePath,
        $script:SharedSpacesPath,
        $script:TeamWorkspacesPath,
        $script:SyncStatePath
    )
    
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Verbose "Created directory: $path"
        }
    }
    
    # Ensure audit log directory exists
    $auditDir = Split-Path -Parent $script:AuditLogPath
    if (-not (Test-Path -LiteralPath $auditDir)) {
        New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
    }
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
        [string]$ResourceId,
        
        [string]$UserId = $env:USERNAME,
        
        [string]$Action = '',
        
        [bool]$Success = $true,
        
        [hashtable]$Details = @{}
    )
    
    $logEntry = [pscustomobject]@{
        timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')
        operation = $Operation
        resourceId = $ResourceId
        userId = $UserId
        action = $Action
        success = $Success
        details = $Details
        sourceIp = $env:REMOTE_ADDR
        userAgent = $env:HTTP_USER_AGENT
    }
    
    try {
        $logEntry | ConvertTo-Json -Compress | Add-Content -LiteralPath $script:AuditLogPath -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Failed to write audit log: $_"
    }
}

function Get-FederationFilePath {
    <#
    .SYNOPSIS
        Gets the file path for a federation by ID.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FederationId
    )
    
    return Join-Path $script:FederationStoragePath "$FederationId.json"
}

function Get-SharedSpaceFilePath {
    <#
    .SYNOPSIS
        Gets the file path for a shared memory space.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpaceId
    )
    
    return Join-Path $script:SharedSpacesPath "$SpaceId.json"
}

function Get-TeamWorkspaceFilePath {
    <#
    .SYNOPSIS
        Gets the file path for a team workspace.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TeamId
    )
    
    return Join-Path $script:TeamWorkspacesPath "$TeamId.json"
}

function Test-FederationIdValid {
    <#
    .SYNOPSIS
        Validates federation ID format.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FederationId
    )
    
    # Federation IDs: lowercase alphanumeric, hyphens
    # Must start with 'fed-', 5-64 characters
    if ($FederationId -notmatch '^fed-[a-z0-9-]{2,60}$') {
        return $false
    }
    
    return $true
}

function Test-SpaceIdValid {
    <#
    .SYNOPSIS
        Validates shared space ID format.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpaceId
    )
    
    # Space IDs: lowercase alphanumeric, hyphens, underscores
    # Must start with letter, 3-64 characters
    if ($SpaceId -notmatch '^[a-z][a-z0-9_-]{2,63}$') {
        return $false
    }
    
    return $true
}

function Test-TeamIdValid {
    <#
    .SYNOPSIS
        Validates team workspace ID format.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TeamId
    )
    
    # Team IDs: lowercase alphanumeric, hyphens
    # Must start with 'team-', 6-64 characters
    if ($TeamId -notmatch '^team-[a-z0-9-]{2,60}$') {
        return $false
    }
    
    return $true
}

function Invoke-FederationRequest {
    <#
    .SYNOPSIS
        Makes a secure request to a federation peer.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Auth,
        
        [string]$Method = 'GET',
        
        [object]$Body = $null,
        
        [int]$TimeoutSec = 30
    )
    
    $headers = @{
        'Accept' = 'application/json'
        'X-Federation-Version' = '1.0'
    }
    
    # Add authentication headers
    switch ($Auth.type) {
        'mTLS' {
            # Certificate-based authentication would be handled at transport level
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
            Uri = $Url
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
        $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode } else { $null }
        return @{ Success = $false; Error = $_.Exception.Message; StatusCode = $statusCode }
    }
}

function Get-EncryptionKey {
    <#
    .SYNOPSIS
        Gets or generates an encryption key for a shared space.
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpaceId,
        
        [switch]$CreateIfNotExists
    )
    
    $keyPath = Join-Path $script:SharedSpacesPath ".$SpaceId.key"
    
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
        
        # Set restrictive permissions
        $acl = Get-Acl -LiteralPath $keyPath
        $acl.SetAccessRuleProtection($true, $false)
        
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $currentUser, 'Read', 'Allow'
        )
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $keyPath $acl
        
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
    
    # Generate IV
    $iv = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($iv)
    
    # Encrypt
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $Key
    $aes.IV = $iv
    $aes.Mode = [System.Security.Cryptography.CipherMode]::GCM
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::None
    
    $encryptor = $aes.CreateEncryptor()
    $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($Data)
    $encrypted = $encryptor.TransformFinalBlock($dataBytes, 0, $dataBytes.Length)
    
    # Combine IV + encrypted data + auth tag
    $result = New-Object byte[] ($iv.Length + $encrypted.Length)
    [Buffer]::BlockCopy($iv, 0, $result, 0, $iv.Length)
    [Buffer]::BlockCopy($encrypted, 0, $result, $iv.Length, $encrypted.Length)
    
    return [Convert]::ToBase64String($result)
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
        $aes.Mode = [System.Security.Cryptography.CipherMode]::GCM
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::None
        
        $decryptor = $aes.CreateDecryptor()
        $decrypted = $decryptor.TransformFinalBlock($encrypted, 0, $encrypted.Length)
        
        return [System.Text.Encoding]::UTF8.GetString($decrypted)
    }
    catch {
        Write-Error "Failed to decrypt data: $_"
        return $null
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
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Data)
    $hash = $sha256.ComputeHash($bytes)
    return [BitConverter]::ToString($hash).Replace('-', '').ToLower()
}

#endregion

#region Memory Federation Functions

function Register-MemoryFederation {
    <#
    .SYNOPSIS
        Registers a federation peer for memory sharing.
    .DESCRIPTION
        Creates a federation configuration for bidirectional or unidirectional
        memory sharing with another organization or workspace.
    .PARAMETER FederationId
        Unique identifier for the federation (must start with 'fed-').
    .PARAMETER PeerUrl
        URL of the peer's LLM Workflow API endpoint.
    .PARAMETER Auth
        Authentication configuration hashtable.
    .PARAMETER SyncDirection
        Direction of sync: push, pull, or bidirectional.
    .PARAMETER SyncSchedule
        Cron expression for sync schedule.
    .PARAMETER SharedCollections
        Array of collection names to share.
    .PARAMETER TrustLevel
        Trust level: low, medium, or high.
    .EXAMPLE
        Register-MemoryFederation -FederationId 'fed-acme-corp' -PeerUrl 'https://llmworkflow.acme.com/api/v1' -Auth @{type='mTLS'; certPath='/path/to/cert'}
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FederationId,
        
        [Parameter(Mandatory = $true)]
        [string]$PeerUrl,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Auth,
        
        [ValidateSet('push', 'pull', 'bidirectional')]
        [string]$SyncDirection = 'bidirectional',
        
        [string]$SyncSchedule = '0 */6 * * *',
        
        [string[]]$SharedCollections = @(),
        
        [ValidateSet('low', 'medium', 'high')]
        [string]$TrustLevel = 'medium'
    )
    
    Initialize-FederationStorage
    
    # Validate federation ID
    if (-not (Test-FederationIdValid -FederationId $FederationId)) {
        throw "Invalid federation ID: '$FederationId'. Must start with 'fed-' followed by lowercase alphanumeric characters and hyphens."
    }
    
    # Check for existing federation
    $federationPath = Get-FederationFilePath -FederationId $FederationId
    if (Test-Path -LiteralPath $federationPath) {
        throw "Federation already exists: $FederationId"
    }
    
    # Validate URL
    try {
        $uri = [System.Uri]$PeerUrl
        if ($uri.Scheme -notin @('https', 'http')) {
            throw "URL must use HTTP or HTTPS scheme"
        }
    }
    catch {
        throw "Invalid peer URL: $PeerUrl"
    }
    
    # Build federation configuration
    $federation = @{
        federationId = $FederationId
        peerUrl = $PeerUrl
        auth = $Auth
        syncDirection = $SyncDirection
        syncSchedule = $SyncSchedule
        sharedCollections = $SharedCollections
        trustLevel = $TrustLevel
        status = 'active'
        createdAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        lastSync = $null
        syncCount = 0
        version = 1
    }
    
    # Save federation
    $federation | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $federationPath -Encoding UTF8
    
    Write-FederationAuditLog -Operation 'Register' -ResourceId $FederationId -Action 'register' -Success $true -Details @{
        peerUrl = $PeerUrl
        syncDirection = $SyncDirection
        trustLevel = $TrustLevel
    }
    
    Write-Verbose "Registered federation: $FederationId"
    return [pscustomobject]$federation
}

function Unregister-MemoryFederation {
    <#
    .SYNOPSIS
        Removes a federation registration.
    .DESCRIPTION
        Unregisters a federation peer and optionally removes all 
        associated shared data.
    .PARAMETER FederationId
        ID of the federation to remove.
    .PARAMETER RemoveSharedData
        Also remove all data shared through this federation.
    .PARAMETER Force
        Force removal without confirmation.
    .EXAMPLE
        Unregister-MemoryFederation -FederationId 'fed-acme-corp'
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FederationId,
        
        [switch]$RemoveSharedData,
        
        [switch]$Force
    )
    
    $federationPath = Get-FederationFilePath -FederationId $FederationId
    if (-not (Test-Path -LiteralPath $federationPath)) {
        throw "Federation not found: $FederationId"
    }
    
    $federation = Get-Content -LiteralPath $federationPath -Raw | ConvertFrom-Json
    
    if ($Force -or $PSCmdlet.ShouldProcess($FederationId, 'Unregister federation')) {
        # Remove federation file
        Remove-Item -LiteralPath $federationPath -Force
        
        # Remove shared data if requested
        if ($RemoveSharedData) {
            foreach ($collection in $federation.sharedCollections) {
                $spacePath = Get-SharedSpaceFilePath -SpaceId $collection
                if (Test-Path -LiteralPath $spacePath) {
                    Remove-Item -LiteralPath $spacePath -Force
                    Write-Verbose "Removed shared space: $collection"
                }
            }
        }
        
        Write-FederationAuditLog -Operation 'Unregister' -ResourceId $FederationId -Action 'unregister' -Success $true -Details @{
            removeSharedData = $RemoveSharedData.IsPresent
        }
        
        Write-Verbose "Unregistered federation: $FederationId"
    }
}

function Get-MemoryFederations {
    <#
    .SYNOPSIS
        Lists all registered federation peers.
    .DESCRIPTION
        Returns a list of all federation configurations, optionally
        filtered by status or trust level.
    .PARAMETER Status
        Filter by federation status.
    .PARAMETER TrustLevel
        Filter by trust level.
    .PARAMETER IncludeDetails
        Include full federation details.
    .EXAMPLE
        Get-MemoryFederations -Status 'active'
    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [ValidateSet('active', 'inactive', 'suspended', 'error')]
        [string]$Status = '',
        
        [ValidateSet('low', 'medium', 'high')]
        [string]$TrustLevel = '',
        
        [switch]$IncludeDetails
    )
    
    Initialize-FederationStorage
    
    $federationFiles = Get-ChildItem -Path $script:FederationStoragePath -Filter 'fed-*.json' -ErrorAction SilentlyContinue
    
    $federations = @()
    foreach ($file in $federationFiles) {
        try {
            $federation = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            
            # Apply filters
            if ($Status -and $federation.status -ne $Status) {
                continue
            }
            if ($TrustLevel -and $federation.trustLevel -ne $TrustLevel) {
                continue
            }
            
            if ($IncludeDetails) {
                $federations += $federation
            }
            else {
                $federations += [pscustomobject]@{
                    FederationId = $federation.federationId
                    PeerUrl = $federation.peerUrl
                    Status = $federation.status
                    TrustLevel = $federation.trustLevel
                    SyncDirection = $federation.syncDirection
                    LastSync = $federation.lastSync
                }
            }
        }
        catch {
            Write-Warning "Failed to load federation from $($file.Name): $_"
        }
    }
    
    return $federations
}

function Test-FederationHealth {
    <#
    .SYNOPSIS
        Checks the health and connectivity of a federation peer.
    .DESCRIPTION
        Performs a health check against a federation peer's API
        endpoint and returns connectivity status.
    .PARAMETER FederationId
        ID of the federation to check.
    .PARAMETER TimeoutSec
        Request timeout in seconds.
    .EXAMPLE
        Test-FederationHealth -FederationId 'fed-acme-corp'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FederationId,
        
        [int]$TimeoutSec = 10
    )
    
    $federationPath = Get-FederationFilePath -FederationId $FederationId
    if (-not (Test-Path -LiteralPath $federationPath)) {
        throw "Federation not found: $FederationId"
    }
    
    $federation = Get-Content -LiteralPath $federationPath -Raw | ConvertFrom-Json
    
    $healthUrl = "$($federation.peerUrl)/health"
    $startTime = Get-Date
    
    $response = Invoke-FederationRequest -Url $healthUrl -Auth $federation.auth -Method 'GET' -TimeoutSec $TimeoutSec
    $endTime = Get-Date
    $latencyMs = [math]::Round(($endTime - $startTime).TotalMilliseconds)
    
    $result = @{
        FederationId = $FederationId
        PeerUrl = $federation.peerUrl
        Status = if ($response.Success) { 'healthy' } else { 'unhealthy' }
        LatencyMs = $latencyMs
        LastChecked = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        Error = $response.Error
    }
    
    # Update federation status
    $federation.status = $result.Status
    $federation | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $federationPath -Encoding UTF8
    
    Write-FederationAuditLog -Operation 'HealthCheck' -ResourceId $FederationId -Action 'health_check' -Success $response.Success -Details @{
        latencyMs = $latencyMs
        error = $response.Error
    }
    
    return [pscustomobject]$result
}

#endregion

#region Shared Memory Space Functions

function New-SharedMemorySpace {
    <#
    .SYNOPSIS
        Creates a new shared memory space.
    .DESCRIPTION
        Creates a shared memory space for team collaboration with
        configurable access control and encryption.
    .PARAMETER SpaceId
        Unique identifier for the space.
    .PARAMETER DisplayName
        Human-readable name for the space.
    .PARAMETER Description
        Description of the space's purpose.
    .PARAMETER Owners
        Array of user IDs who own the space.
    .PARAMETER EncryptionEnabled
        Enable end-to-end encryption.
    .PARAMETER RetentionDays
        Data retention period in days.
    .EXAMPLE
        New-SharedMemorySpace -SpaceId 'team-patterns' -DisplayName 'Team Patterns' -Owners @('user1', 'user2')
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpaceId,
        
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,
        
        [string]$Description = '',
        
        [string[]]$Owners = @(),
        
        [switch]$EncryptionEnabled,
        
        [int]$RetentionDays = $script:DefaultRetentionPolicy.defaultDays
    )
    
    Initialize-FederationStorage
    
    # Validate space ID
    if (-not (Test-SpaceIdValid -SpaceId $SpaceId)) {
        throw "Invalid space ID: '$SpaceId'. Must be 3-64 lowercase alphanumeric characters starting with a letter."
    }
    
    # Check for existing space
    $spacePath = Get-SharedSpaceFilePath -SpaceId $SpaceId
    if (Test-Path -LiteralPath $spacePath) {
        throw "Shared space already exists: $SpaceId"
    }
    
    # Generate encryption key if enabled
    $encryptionKeyId = $null
    if ($EncryptionEnabled) {
        $key = Get-EncryptionKey -SpaceId $SpaceId -CreateIfNotExists
        $encryptionKeyId = "$SpaceId-key"
    }
    
    # Build space configuration
    $space = @{
        spaceId = $SpaceId
        displayName = $DisplayName
        description = $Description
        owners = $Owners
        members = @()
        accessGrants = @{}  # userId -> role
        encryptionEnabled = $EncryptionEnabled.IsPresent
        encryptionKeyId = $encryptionKeyId
        retentionDays = $RetentionDays
        createdAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        version = 1
        collections = @()
        gdprDeletionRequests = @()
    }
    
    # Add current user as owner if no owners specified
    if ($Owners.Count -eq 0) {
        $space.owners = @($env:USERNAME)
    }
    
    # Grant admin access to owners
    foreach ($owner in $space.owners) {
        $space.accessGrants[$owner] = 'admin'
    }
    
    # Save space
    $space | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $spacePath -Encoding UTF8
    
    Write-FederationAuditLog -Operation 'CreateSpace' -ResourceId $SpaceId -Action 'create_shared_space' -Success $true -Details @{
        displayName = $DisplayName
        encryptionEnabled = $EncryptionEnabled.IsPresent
        owners = $space.owners
    }
    
    Write-Verbose "Created shared memory space: $SpaceId"
    return [pscustomobject]$space
}

function Get-SharedMemorySpace {
    <#
    .SYNOPSIS
        Gets information about a shared memory space.
    .DESCRIPTION
        Retrieves the configuration and metadata for a shared
        memory space, including access grants and members.
    .PARAMETER SpaceId
        ID of the shared space.
    .PARAMETER IncludeCollections
        Include collection data.
    .EXAMPLE
        Get-SharedMemorySpace -SpaceId 'team-patterns'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpaceId,
        
        [switch]$IncludeCollections
    )
    
    $spacePath = Get-SharedSpaceFilePath -SpaceId $SpaceId
    if (-not (Test-Path -LiteralPath $spacePath)) {
        throw "Shared space not found: $SpaceId"
    }
    
    $space = Get-Content -LiteralPath $spacePath -Raw | ConvertFrom-Json
    
    if (-not $IncludeCollections) {
        # Return without collections data
        $spaceWithoutCollections = @{
            spaceId = $space.spaceId
            displayName = $space.displayName
            description = $space.description
            owners = $space.owners
            members = $space.members
            accessGrants = $space.accessGrants
            encryptionEnabled = $space.encryptionEnabled
            retentionDays = $space.retentionDays
            createdAt = $space.createdAt
            modifiedAt = $space.modifiedAt
            version = $space.version
        }
        return [pscustomobject]$spaceWithoutCollections
    }
    
    return [pscustomobject]$space
}

function Remove-SharedMemorySpace {
    <#
    .SYNOPSIS
        Deletes a shared memory space.
    .DESCRIPTION
        Permanently removes a shared memory space and all its data.
        Requires admin permission.
    .PARAMETER SpaceId
        ID of the space to remove.
    .PARAMETER Force
        Force removal without confirmation.
    .EXAMPLE
        Remove-SharedMemorySpace -SpaceId 'team-patterns' -Force
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpaceId,
        
        [switch]$Force
    )
    
    $spacePath = Get-SharedSpaceFilePath -SpaceId $SpaceId
    if (-not (Test-Path -LiteralPath $spacePath)) {
        throw "Shared space not found: $SpaceId"
    }
    
    # Check admin access
    $space = Get-Content -LiteralPath $spacePath -Raw | ConvertFrom-Json
    $currentUser = $env:USERNAME
    
    if ($space.accessGrants.$currentUser -ne 'admin' -and $space.owners -notcontains $currentUser) {
        throw "Access denied: Admin permission required to remove space"
    }
    
    if ($Force -or $PSCmdlet.ShouldProcess($SpaceId, 'Remove shared memory space')) {
        # Remove space file
        Remove-Item -LiteralPath $spacePath -Force
        
        # Remove encryption key if exists
        $keyPath = Join-Path $script:SharedSpacesPath ".$SpaceId.key"
        if (Test-Path -LiteralPath $keyPath) {
            Remove-Item -LiteralPath $keyPath -Force
        }
        
        Write-FederationAuditLog -Operation 'RemoveSpace' -ResourceId $SpaceId -Action 'remove_shared_space' -Success $true -Details @{
            removedBy = $currentUser
        }
        
        Write-Verbose "Removed shared memory space: $SpaceId"
    }
}

function Grant-MemoryAccess {
    <#
    .SYNOPSIS
        Grants access to a shared memory space.
    .DESCRIPTION
        Grants a user or team access to a shared memory space
        with a specified role.
    .PARAMETER SpaceId
        ID of the shared space.
    .PARAMETER UserId
        User or team ID to grant access to.
    .PARAMETER Role
        Role to assign: admin, editor, viewer, or auditor.
    .PARAMETER GrantedBy
        User ID granting the access.
    .EXAMPLE
        Grant-MemoryAccess -SpaceId 'team-patterns' -UserId 'developer1' -Role 'editor'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpaceId,
        
        [Parameter(Mandatory = $true)]
        [string]$UserId,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('admin', 'editor', 'viewer', 'auditor')]
        [string]$Role,
        
        [string]$GrantedBy = $env:USERNAME
    )
    
    $spacePath = Get-SharedSpaceFilePath -SpaceId $SpaceId
    if (-not (Test-Path -LiteralPath $spacePath)) {
        throw "Shared space not found: $SpaceId"
    }
    
    $space = Get-Content -LiteralPath $spacePath -Raw | ConvertFrom-Json
    
    # Check if granter has admin access
    if ($space.accessGrants.$GrantedBy -ne 'admin' -and $space.owners -notcontains $GrantedBy) {
        throw "Access denied: Admin permission required to grant access"
    }
    
    # Add or update access grant
    if (-not $space.accessGrants) {
        $space.accessGrants = @{}
    }
    $space.accessGrants.$UserId = $Role
    
    # Add to members if not already present
    if ($space.members -notcontains $UserId) {
        $space.members += $UserId
    }
    
    $space.modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $space.version++
    
    $space | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $spacePath -Encoding UTF8
    
    Write-FederationAuditLog -Operation 'GrantAccess' -ResourceId $SpaceId -Action 'grant_access' -Success $true -Details @{
        userId = $UserId
        role = $Role
        grantedBy = $GrantedBy
    }
    
    Write-Verbose "Granted $Role access to $UserId for space: $SpaceId"
    return [pscustomobject]@{
        SpaceId = $SpaceId
        UserId = $UserId
        Role = $Role
        GrantedBy = $GrantedBy
        GrantedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    }
}

function Revoke-MemoryAccess {
    <#
    .SYNOPSIS
        Revokes access to a shared memory space.
    .DESCRIPTION
        Removes a user's access to a shared memory space.
    .PARAMETER SpaceId
        ID of the shared space.
    .PARAMETER UserId
        User ID to revoke access from.
    .PARAMETER RevokedBy
        User ID revoking the access.
    .EXAMPLE
        Revoke-MemoryAccess -SpaceId 'team-patterns' -UserId 'developer1'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpaceId,
        
        [Parameter(Mandatory = $true)]
        [string]$UserId,
        
        [string]$RevokedBy = $env:USERNAME
    )
    
    $spacePath = Get-SharedSpaceFilePath -SpaceId $SpaceId
    if (-not (Test-Path -LiteralPath $spacePath)) {
        throw "Shared space not found: $SpaceId"
    }
    
    $space = Get-Content -LiteralPath $spacePath -Raw | ConvertFrom-Json
    
    # Check if revoker has admin access
    if ($space.accessGrants.$RevokedBy -ne 'admin' -and $space.owners -notcontains $RevokedBy) {
        throw "Access denied: Admin permission required to revoke access"
    }
    
    # Cannot revoke owner's access
    if ($space.owners -contains $UserId) {
        throw "Cannot revoke access from owner: $UserId"
    }
    
    # Remove access grant
    $space.accessGrants.PSObject.Properties.Remove($UserId)
    
    # Remove from members
    $space.members = @($space.members | Where-Object { $_ -ne $UserId })
    
    $space.modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $space.version++
    
    $space | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $spacePath -Encoding UTF8
    
    Write-FederationAuditLog -Operation 'RevokeAccess' -ResourceId $SpaceId -Action 'revoke_access' -Success $true -Details @{
        userId = $UserId
        revokedBy = $RevokedBy
    }
    
    Write-Verbose "Revoked access from $UserId for space: $SpaceId"
    return [pscustomobject]@{
        SpaceId = $SpaceId
        UserId = $UserId
        RevokedBy = $RevokedBy
        RevokedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    }
}

#endregion

#region Sync Operations Functions

function Sync-MemoryWithPeer {
    <#
    .SYNOPSIS
        Performs bidirectional synchronization with a federation peer.
    .DESCRIPTION
        Syncs memory collections with a federation peer, handling
        conflicts according to the configured strategy.
    .PARAMETER FederationId
        ID of the federation peer.
    .PARAMETER Collections
        Specific collections to sync (all shared if not specified).
    .PARAMETER ConflictStrategy
        Strategy for handling conflicts.
    .PARAMETER DryRun
        Preview changes without applying.
    .EXAMPLE
        Sync-MemoryWithPeer -FederationId 'fed-acme-corp' -ConflictStrategy 'last-write-wins'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FederationId,
        
        [string[]]$Collections = @(),
        
        [ValidateSet('last-write-wins', 'merge', 'manual')]
        [string]$ConflictStrategy = 'last-write-wins',
        
        [switch]$DryRun
    )
    
    $federationPath = Get-FederationFilePath -FederationId $FederationId
    if (-not (Test-Path -LiteralPath $federationPath)) {
        throw "Federation not found: $FederationId"
    }
    
    $federation = Get-Content -LiteralPath $federationPath -Raw | ConvertFrom-Json
    
    $collectionsToSync = if ($Collections.Count -gt 0) { $Collections } else { $federation.sharedCollections }
    
    $results = @{
        FederationId = $FederationId
        StartedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        Collections = @()
        TotalPushed = 0
        TotalPulled = 0
        Conflicts = @()
        Errors = @()
    }
    
    foreach ($collection in $collectionsToSync) {
        $collectionResult = @{
            Collection = $collection
            Pushed = 0
            Pulled = 0
            Conflicts = @()
        }
        
        # Push changes
        if ($federation.syncDirection -in @('push', 'bidirectional')) {
            try {
                $pushResult = Push-MemoryToPeer -FederationId $FederationId -Collection $collection -DryRun:$DryRun
                $collectionResult.Pushed = $pushResult.ItemsPushed
                $results.TotalPushed += $pushResult.ItemsPushed
            }
            catch {
                $results.Errors += @{ Collection = $collection; Operation = 'push'; Error = $_.Exception.Message }
            }
        }
        
        # Pull changes
        if ($federation.syncDirection -in @('pull', 'bidirectional')) {
            try {
                $pullResult = Pull-MemoryFromPeer -FederationId $FederationId -Collection $collection -ConflictStrategy $ConflictStrategy -DryRun:$DryRun
                $collectionResult.Pulled = $pullResult.ItemsPulled
                $results.TotalPulled += $pullResult.ItemsPulled
                $collectionResult.Conflicts = $pullResult.Conflicts
                $results.Conflicts += $pullResult.Conflicts
            }
            catch {
                $results.Errors += @{ Collection = $collection; Operation = 'pull'; Error = $_.Exception.Message }
            }
        }
        
        $results.Collections += $collectionResult
    }
    
    $results.CompletedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    
    # Update federation stats
    if (-not $DryRun) {
        $federation.lastSync = $results.CompletedAt
        $federation.syncCount++
        $federation | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $federationPath -Encoding UTF8
    }
    
    Write-FederationAuditLog -Operation 'Sync' -ResourceId $FederationId -Action 'sync_with_peer' -Success ($results.Errors.Count -eq 0) -Details @{
        collections = $collectionsToSync
        conflictStrategy = $ConflictStrategy
        dryRun = $DryRun.IsPresent
        pushed = $results.TotalPushed
        pulled = $results.TotalPulled
        conflicts = $results.Conflicts.Count
    }
    
    return [pscustomobject]$results
}

function Push-MemoryToPeer {
    <#
    .SYNOPSIS
        Pushes memory changes to a federation peer.
    .DESCRIPTION
        Sends local memory changes to a federation peer endpoint.
    .PARAMETER FederationId
        ID of the federation peer.
    .PARAMETER Collection
        Collection to push.
    .PARAMETER Since
        Only push changes since this timestamp.
    .PARAMETER DryRun
        Preview changes without pushing.
    .EXAMPLE
        Push-MemoryToPeer -FederationId 'fed-acme-corp' -Collection 'team-patterns'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FederationId,
        
        [Parameter(Mandatory = $true)]
        [string]$Collection,
        
        [datetime]$Since = [datetime]::MinValue,
        
        [switch]$DryRun
    )
    
    $federationPath = Get-FederationFilePath -FederationId $FederationId
    $federation = Get-Content -LiteralPath $federationPath -Raw | ConvertFrom-Json
    
    # Get local collection data
    $spacePath = Get-SharedSpaceFilePath -SpaceId $Collection
    if (-not (Test-Path -LiteralPath $spacePath)) {
        throw "Collection not found: $Collection"
    }
    
    $space = Get-Content -LiteralPath $spacePath -Raw | ConvertFrom-Json
    
    # Filter items modified since specified time
    $itemsToPush = @($space.collections | Where-Object { 
        $itemModified = [datetime]::Parse($_.modifiedAt)
        return $itemModified -gt $Since
    })
    
    if ($DryRun) {
        return [pscustomobject]@{
            FederationId = $FederationId
            Collection = $Collection
            ItemsToPush = $itemsToPush.Count
            DryRun = $true
        }
    }
    
    # Encrypt data if needed
    $dataToSend = $itemsToPush | ConvertTo-Json -Depth 10
    if ($space.encryptionEnabled) {
        $key = Get-EncryptionKey -SpaceId $Collection
        if ($key) {
            $dataToSend = Protect-FederatedData -Data $dataToSend -Key $key
        }
    }
    
    # Push to peer
    $pushUrl = "$($federation.peerUrl)/collections/$Collection"
    $response = Invoke-FederationRequest -Url $pushUrl -Auth $federation.auth -Method 'POST' -Body @{
        items = $itemsToPush
        encrypted = $space.encryptionEnabled
        version = $space.version
    }
    
    if (-not $response.Success) {
        throw "Failed to push to peer: $($response.Error)"
    }
    
    Write-FederationAuditLog -Operation 'Push' -ResourceId $FederationId -Action 'push_to_peer' -Success $true -Details @{
        collection = $Collection
        itemsPushed = $itemsToPush.Count
    }
    
    return [pscustomobject]@{
        FederationId = $FederationId
        Collection = $Collection
        ItemsPushed = $itemsToPush.Count
        SyncedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    }
}

function Pull-MemoryFromPeer {
    <#
    .SYNOPSIS
        Pulls memory changes from a federation peer.
    .DESCRIPTION
        Retrieves memory changes from a federation peer and applies
        them locally with conflict resolution.
    .PARAMETER FederationId
        ID of the federation peer.
    .PARAMETER Collection
        Collection to pull.
    .PARAMETER ConflictStrategy
        Strategy for handling conflicts.
    .PARAMETER DryRun
        Preview changes without applying.
    .EXAMPLE
        Pull-MemoryFromPeer -FederationId 'fed-acme-corp' -Collection 'team-patterns'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FederationId,
        
        [Parameter(Mandatory = $true)]
        [string]$Collection,
        
        [ValidateSet('last-write-wins', 'merge', 'manual')]
        [string]$ConflictStrategy = 'last-write-wins',
        
        [switch]$DryRun
    )
    
    $federationPath = Get-FederationFilePath -FederationId $FederationId
    $federation = Get-Content -LiteralPath $federationPath -Raw | ConvertFrom-Json
    
    # Get from peer
    $pullUrl = "$($federation.peerUrl)/collections/$Collection"
    $response = Invoke-FederationRequest -Url $pullUrl -Auth $federation.auth -Method 'GET'
    
    if (-not $response.Success) {
        throw "Failed to pull from peer: $($response.Error)"
    }
    
    $remoteItems = $response.Data.items
    $conflicts = @()
    $itemsApplied = 0
    
    # Get local space
    $spacePath = Get-SharedSpaceFilePath -SpaceId $Collection
    $space = if (Test-Path -LiteralPath $spacePath) {
        Get-Content -LiteralPath $spacePath -Raw | ConvertFrom-Json
    } else {
        # Create space if it doesn't exist
        New-SharedMemorySpace -SpaceId $Collection -DisplayName $Collection | Out-Null
        Get-Content -LiteralPath $spacePath -Raw | ConvertFrom-Json
    }
    
    if (-not $DryRun) {
        foreach ($remoteItem in $remoteItems) {
            $localItem = $space.collections | Where-Object { $_.id -eq $remoteItem.id }
            
            if ($localItem) {
                # Check for conflict
                $localModified = [datetime]::Parse($localItem.modifiedAt)
                $remoteModified = [datetime]::Parse($remoteItem.modifiedAt)
                
                if ($localModified -ne $remoteModified) {
                    # Conflict detected
                    $conflictResolution = Resolve-MemoryConflict -LocalItem $localItem -RemoteItem $remoteItem -Strategy $ConflictStrategy
                    
                    if ($conflictResolution.RequiresManualResolution) {
                        $conflicts += @{
                            ItemId = $remoteItem.id
                            LocalVersion = $localItem.version
                            RemoteVersion = $remoteItem.version
                        }
                    }
                    else {
                        # Apply resolved version
                        $space.collections = @($space.collections | Where-Object { $_.id -ne $remoteItem.id })
                        $space.collections += $conflictResolution.ResolvedItem
                        $itemsApplied++
                    }
                }
            }
            else {
                # New item, just add it
                $space.collections += $remoteItem
                $itemsApplied++
            }
        }
        
        # Save space
        $space.modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        $space.version++
        $space | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $spacePath -Encoding UTF8
    }
    
    Write-FederationAuditLog -Operation 'Pull' -ResourceId $FederationId -Action 'pull_from_peer' -Success $true -Details @{
        collection = $Collection
        itemsPulled = $remoteItems.Count
        itemsApplied = $itemsApplied
        conflicts = $conflicts.Count
    }
    
    return [pscustomobject]@{
        FederationId = $FederationId
        Collection = $Collection
        ItemsPulled = $remoteItems.Count
        ItemsApplied = $itemsApplied
        Conflicts = $conflicts
        PulledAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    }
}

function Get-MemorySyncStatus {
    <#
    .SYNOPSIS
        Gets the synchronization status for a federation.
    .DESCRIPTION
        Returns sync status including last sync time, pending changes,
        and conflict counts.
    .PARAMETER FederationId
        ID of the federation.
    .PARAMETER Collection
        Specific collection to check (optional).
    .EXAMPLE
        Get-MemorySyncStatus -FederationId 'fed-acme-corp'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FederationId,
        
        [string]$Collection = ''
    )
    
    $federationPath = Get-FederationFilePath -FederationId $FederationId
    if (-not (Test-Path -LiteralPath $federationPath)) {
        throw "Federation not found: $FederationId"
    }
    
    $federation = Get-Content -LiteralPath $federationPath -Raw | ConvertFrom-Json
    
    $status = @{
        FederationId = $FederationId
        Status = $federation.status
        LastSync = $federation.lastSync
        SyncCount = $federation.syncCount
        SyncDirection = $federation.syncDirection
        NextScheduledSync = $null
        Collections = @()
        PendingChanges = 0
        Conflicts = @()
    }
    
    # Calculate next scheduled sync
    if ($federation.syncSchedule) {
        # Simple cron parsing for hourly/daily patterns
        if ($federation.syncSchedule -match '0 \*/(\d+) \* \* \*') {
            $hours = [int]$matches[1]
            $status.NextScheduledSync = (Get-Date).AddHours($hours).ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
    }
    
    # Check each collection
    $collectionsToCheck = if ($Collection) { @($Collection) } else { $federation.sharedCollections }
    
    foreach ($coll in $collectionsToCheck) {
        $spacePath = Get-SharedSpaceFilePath -SpaceId $coll
        if (Test-Path -LiteralPath $spacePath) {
            $space = Get-Content -LiteralPath $spacePath -Raw | ConvertFrom-Json
            $lastModified = $space.modifiedAt
            
            $collectionStatus = @{
                Collection = $coll
                LocalVersion = $space.version
                LastModified = $lastModified
                PendingChanges = ($lastModified -gt $federation.lastSync)
            }
            
            $status.Collections += $collectionStatus
            if ($collectionStatus.PendingChanges) {
                $status.PendingChanges++
            }
        }
    }
    
    return [pscustomobject]$status
}

function Resolve-MemoryConflict {
    <#
    .SYNOPSIS
        Resolves a sync conflict between local and remote items.
    .DESCRIPTION
        Applies conflict resolution strategy to determine the winning
        version of a memory item.
    .PARAMETER LocalItem
        The local version of the item.
    .PARAMETER RemoteItem
        The remote version of the item.
    .PARAMETER Strategy
        Conflict resolution strategy.
    .PARAMETER ManualResolution
        Manual resolution data (for 'manual' strategy).
    .EXAMPLE
        Resolve-MemoryConflict -LocalItem $local -RemoteItem $remote -Strategy 'last-write-wins'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$LocalItem,
        
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RemoteItem,
        
        [ValidateSet('last-write-wins', 'merge', 'manual')]
        [string]$Strategy = 'last-write-wins',
        
        [pscustomobject]$ManualResolution = $null
    )
    
    $localModified = [datetime]::Parse($LocalItem.modifiedAt)
    $remoteModified = [datetime]::Parse($RemoteItem.modifiedAt)
    
    $result = @{
        ResolvedItem = $null
        StrategyUsed = $Strategy
        RequiresManualResolution = $false
        ConflictDetails = @{
            ItemId = $LocalItem.id
            LocalModified = $LocalItem.modifiedAt
            RemoteModified = $RemoteItem.modifiedAt
            LocalVersion = $LocalItem.version
            RemoteVersion = $RemoteItem.version
        }
    }
    
    switch ($Strategy) {
        'last-write-wins' {
            if ($remoteModified -gt $localModified) {
                $result.ResolvedItem = $RemoteItem
            }
            else {
                $result.ResolvedItem = $LocalItem
            }
        }
        
        'merge' {
            # Merge fields from both versions (remote wins on conflict)
            $merged = @{}
            foreach ($prop in $LocalItem.PSObject.Properties) {
                $merged[$prop.Name] = $prop.Value
            }
            foreach ($prop in $RemoteItem.PSObject.Properties) {
                $merged[$prop.Name] = $prop.Value
            }
            $merged['version'] = [math]::Max($LocalItem.version, $RemoteItem.version) + 1
            $merged['modifiedAt'] = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
            $result.ResolvedItem = [pscustomobject]$merged
        }
        
        'manual' {
            if ($ManualResolution) {
                $result.ResolvedItem = $ManualResolution
            }
            else {
                $result.RequiresManualResolution = $true
            }
        }
    }
    
    Write-FederationAuditLog -Operation 'ResolveConflict' -ResourceId $LocalItem.id -Action 'resolve_conflict' -Success (-not $result.RequiresManualResolution) -Details @{
        strategy = $Strategy
        requiresManualResolution = $result.RequiresManualResolution
        winningVersion = if ($result.ResolvedItem) { $result.ResolvedItem.version } else { $null }
    }
    
    return [pscustomobject]$result
}

#endregion

#region Team Workspace Functions

function New-TeamWorkspace {
    <#
    .SYNOPSIS
        Creates a new team workspace.
    .DESCRIPTION
        Creates a workspace for team collaboration with shared memory
        spaces, access control, and federation settings.
    .PARAMETER TeamId
        Unique identifier for the team (must start with 'team-').
    .PARAMETER DisplayName
        Human-readable name for the team.
    .PARAMETER Description
        Description of the team's purpose.
    .PARAMETER Members
        Initial team members with roles.
    .PARAMETER SharedSpaces
        Shared memory spaces to include.
    .PARAMETER FederationIds
        Federation peers to connect.
    .EXAMPLE
        New-TeamWorkspace -TeamId 'team-engineering' -DisplayName 'Engineering Team' -Members @{'user1'='admin';'user2'='editor'}
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TeamId,
        
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,
        
        [string]$Description = '',
        
        [hashtable]$Members = @{},
        
        [string[]]$SharedSpaces = @(),
        
        [string[]]$FederationIds = @()
    )
    
    Initialize-FederationStorage
    
    # Validate team ID
    if (-not (Test-TeamIdValid -TeamId $TeamId)) {
        throw "Invalid team ID: '$TeamId'. Must start with 'team-' followed by lowercase alphanumeric characters and hyphens."
    }
    
    # Check for existing team
    $teamPath = Get-TeamWorkspaceFilePath -TeamId $TeamId
    if (Test-Path -LiteralPath $teamPath) {
        throw "Team workspace already exists: $TeamId"
    }
    
    # Ensure current user is an admin
    if ($Members.Count -eq 0) {
        $Members[$env:USERNAME] = 'admin'
    }
    elseif (-not ($Members.ContainsKey($env:USERNAME))) {
        $Members[$env:USERNAME] = 'admin'
    }
    
    # Build team configuration
    $team = @{
        teamId = $TeamId
        displayName = $DisplayName
        description = $Description
        members = @{}
        sharedSpaces = $SharedSpaces
        federationIds = $FederationIds
        createdAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        version = 1
        settings = @{
            defaultVisibility = 'local-team'
            autoSync = $true
            conflictStrategy = 'last-write-wins'
        }
    }
    
    # Add members
    foreach ($member in $Members.GetEnumerator()) {
        $team.members[$member.Key] = @{
            role = $member.Value
            joinedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
            status = 'active'
        }
    }
    
    # Save team
    $team | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $teamPath -Encoding UTF8
    
    Write-FederationAuditLog -Operation 'CreateTeam' -ResourceId $TeamId -Action 'create_team' -Success $true -Details @{
        displayName = $DisplayName
        memberCount = $Members.Count
        sharedSpaces = $SharedSpaces
    }
    
    Write-Verbose "Created team workspace: $TeamId"
    return [pscustomobject]$team
}

function Get-TeamWorkspace {
    <#
    .SYNOPSIS
        Gets information about a team workspace.
    .DESCRIPTION
        Retrieves team workspace configuration including members,
        shared spaces, and federation connections.
    .PARAMETER TeamId
        ID of the team workspace.
    .PARAMETER IncludeMembers
        Include full member details.
    .EXAMPLE
        Get-TeamWorkspace -TeamId 'team-engineering'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TeamId,
        
        [switch]$IncludeMembers
    )
    
    $teamPath = Get-TeamWorkspaceFilePath -TeamId $TeamId
    if (-not (Test-Path -LiteralPath $teamPath)) {
        throw "Team workspace not found: $TeamId"
    }
    
    $team = Get-Content -LiteralPath $teamPath -Raw | ConvertFrom-Json
    
    if (-not $IncludeMembers) {
        # Return summary without full member details
        $memberSummary = @{}
        foreach ($member in $team.members.PSObject.Properties) {
            $memberSummary[$member.Name] = $member.Value.role
        }
        
        $teamSummary = @{
            teamId = $team.teamId
            displayName = $team.displayName
            description = $team.description
            memberCount = $team.members.PSObject.Properties.Count
            memberRoles = $memberSummary
            sharedSpaces = $team.sharedSpaces
            federationIds = $team.federationIds
            createdAt = $team.createdAt
            modifiedAt = $team.modifiedAt
        }
        return [pscustomobject]$teamSummary
    }
    
    return [pscustomobject]$team
}

function Add-TeamMember {
    <#
    .SYNOPSIS
        Adds a member to a team workspace.
    .DESCRIPTION
        Adds a user to a team with a specified role.
    .PARAMETER TeamId
        ID of the team workspace.
    .PARAMETER UserId
        User ID to add.
    .PARAMETER Role
        Role to assign: admin, editor, viewer, or auditor.
    .PARAMETER AddedBy
        User ID performing the addition.
    .EXAMPLE
        Add-TeamMember -TeamId 'team-engineering' -UserId 'developer1' -Role 'editor'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TeamId,
        
        [Parameter(Mandatory = $true)]
        [string]$UserId,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('admin', 'editor', 'viewer', 'auditor')]
        [string]$Role,
        
        [string]$AddedBy = $env:USERNAME
    )
    
    $teamPath = Get-TeamWorkspaceFilePath -TeamId $TeamId
    if (-not (Test-Path -LiteralPath $teamPath)) {
        throw "Team workspace not found: $TeamId"
    }
    
    $team = Get-Content -LiteralPath $teamPath -Raw | ConvertFrom-Json
    
    # Check if adder has admin access
    $adderRole = $team.members.$AddedBy.role
    if ($adderRole -ne 'admin') {
        throw "Access denied: Admin permission required to add team members"
    }
    
    # Check if user already exists
    if ($team.members.$UserId) {
        throw "User already exists in team: $UserId"
    }
    
    # Add member
    $team.members.$UserId = @{
        role = $Role
        joinedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        status = 'active'
        addedBy = $AddedBy
    }
    
    $team.modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $team.version++
    
    $team | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $teamPath -Encoding UTF8
    
    Write-FederationAuditLog -Operation 'AddMember' -ResourceId $TeamId -Action 'add_team_member' -Success $true -Details @{
        userId = $UserId
        role = $Role
        addedBy = $AddedBy
    }
    
    Write-Verbose "Added $UserId to team $TeamId with role $Role"
    return [pscustomobject]@{
        TeamId = $TeamId
        UserId = $UserId
        Role = $Role
        JoinedAt = $team.members.$UserId.joinedAt
    }
}

function Remove-TeamMember {
    <#
    .SYNOPSIS
        Removes a member from a team workspace.
    .DESCRIPTION
        Removes a user from a team. Cannot remove the last admin.
    .PARAMETER TeamId
        ID of the team workspace.
    .PARAMETER UserId
        User ID to remove.
    .PARAMETER RemovedBy
        User ID performing the removal.
    .EXAMPLE
        Remove-TeamMember -TeamId 'team-engineering' -UserId 'developer1'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TeamId,
        
        [Parameter(Mandatory = $true)]
        [string]$UserId,
        
        [string]$RemovedBy = $env:USERNAME
    )
    
    $teamPath = Get-TeamWorkspaceFilePath -TeamId $TeamId
    if (-not (Test-Path -LiteralPath $teamPath)) {
        throw "Team workspace not found: $TeamId"
    }
    
    $team = Get-Content -LiteralPath $teamPath -Raw | ConvertFrom-Json
    
    # Check if remover has admin access
    $removerRole = $team.members.$RemovedBy.role
    if ($removerRole -ne 'admin' -and $UserId -ne $RemovedBy) {
        throw "Access denied: Admin permission required to remove team members"
    }
    
    # Check if user exists
    if (-not $team.members.$UserId) {
        throw "User not found in team: $UserId"
    }
    
    # Check if removing last admin
    if ($team.members.$UserId.role -eq 'admin') {
        $adminCount = ($team.members.PSObject.Properties | Where-Object { $_.Value.role -eq 'admin' }).Count
        if ($adminCount -le 1) {
            throw "Cannot remove the last admin from team"
        }
    }
    
    # Remove member
    $team.members.PSObject.Properties.Remove($UserId)
    
    $team.modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $team.version++
    
    $team | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $teamPath -Encoding UTF8
    
    Write-FederationAuditLog -Operation 'RemoveMember' -ResourceId $TeamId -Action 'remove_team_member' -Success $true -Details @{
        userId = $UserId
        removedBy = $RemovedBy
    }
    
    Write-Verbose "Removed $UserId from team $TeamId"
    return [pscustomobject]@{
        TeamId = $TeamId
        UserId = $UserId
        RemovedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    }
}

#endregion

#region Access Control Functions

function Test-MemoryAccess {
    <#
    .SYNOPSIS
        Tests if a user has access to a memory resource.
    .DESCRIPTION
        Validates user permissions against a shared memory space or
        team workspace, checking role-based access control.
    .PARAMETER ResourceId
        ID of the resource (space or team).
    .PARAMETER UserId
        User ID to check access for.
    .PARAMETER Permission
        Permission to check: read, write, delete, manage, federate, audit.
    .PARAMETER ResourceType
        Type of resource: space, team, or federation.
    .EXAMPLE
        Test-MemoryAccess -ResourceId 'team-patterns' -UserId 'developer1' -Permission 'write' -ResourceType 'space'
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceId,
        
        [Parameter(Mandatory = $true)]
        [string]$UserId,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('read', 'write', 'delete', 'manage', 'federate', 'audit')]
        [string]$Permission,
        
        [ValidateSet('space', 'team', 'federation')]
        [string]$ResourceType = 'space'
    )
    
    $role = $null
    
    switch ($ResourceType) {
        'space' {
            $spacePath = Get-SharedSpaceFilePath -SpaceId $ResourceId
            if (-not (Test-Path -LiteralPath $spacePath)) {
                return $false
            }
            $space = Get-Content -LiteralPath $spacePath -Raw | ConvertFrom-Json
            $role = $space.accessGrants.$UserId
            if (-not $role -and $space.owners -contains $UserId) {
                $role = 'admin'
            }
        }
        'team' {
            $teamPath = Get-TeamWorkspaceFilePath -TeamId $ResourceId
            if (-not (Test-Path -LiteralPath $teamPath)) {
                return $false
            }
            $team = Get-Content -LiteralPath $teamPath -Raw | ConvertFrom-Json
            $role = $team.members.$UserId.role
        }
        'federation' {
            # Federation access is admin-only
            $federationPath = Get-FederationFilePath -FederationId $ResourceId
            if (-not (Test-Path -LiteralPath $federationPath)) {
                return $false
            }
            # Check if user has admin access to any connected space
            $federation = Get-Content -LiteralPath $federationPath -Raw | ConvertFrom-Json
            foreach ($spaceId in $federation.sharedCollections) {
                if (Test-MemoryAccess -ResourceId $spaceId -UserId $UserId -Permission 'manage' -ResourceType 'space') {
                    $role = 'admin'
                    break
                }
            }
        }
    }
    
    if (-not $role) {
        return $false
    }
    
    $rolePermissions = $script:Roles[$role].permissions
    return $rolePermissions -contains $Permission
}

function Get-MemoryAuditLog {
    <#
    .SYNOPSIS
        Gets the access audit log.
    .DESCRIPTION
        Retrieves audit log entries for memory access, federation
        operations, and team workspace changes.
    .PARAMETER ResourceId
        Filter by specific resource ID.
    .PARAMETER UserId
        Filter by user ID.
    .PARAMETER Operation
        Filter by operation type.
    .PARAMETER Since
        Only return entries since this timestamp.
    .PARAMETER Limit
        Maximum number of entries to return.
    .EXAMPLE
        Get-MemoryAuditLog -ResourceId 'team-patterns' -Since (Get-Date).AddDays(-7)
    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [string]$ResourceId = '',
        
        [string]$UserId = '',
        
        [string]$Operation = '',
        
        [datetime]$Since = [datetime]::MinValue,
        
        [int]$Limit = 100
    )
    
    if (-not (Test-Path -LiteralPath $script:AuditLogPath)) {
        return @()
    }
    
    $entries = @()
    $lines = Get-Content -LiteralPath $script:AuditLogPath -Tail 1000 | Select-Object -Last $Limit
    
    foreach ($line in $lines) {
        try {
            $entry = $line | ConvertFrom-Json
            $entryTime = [datetime]::Parse($entry.timestamp)
            
            # Apply filters
            if ($Since -ne [datetime]::MinValue -and $entryTime -lt $Since) {
                continue
            }
            if ($ResourceId -and $entry.resourceId -ne $ResourceId) {
                continue
            }
            if ($UserId -and $entry.userId -ne $UserId) {
                continue
            }
            if ($Operation -and $entry.operation -ne $Operation) {
                continue
            }
            
            $entries += $entry
        }
        catch {
            Write-Verbose "Failed to parse audit log entry: $line"
        }
    }
    
    return $entries | Sort-Object -Property timestamp -Descending | Select-Object -First $Limit
}

function Set-MemoryRetention {
    <#
    .SYNOPSIS
        Configures retention policy for memory data.
    .DESCRIPTION
        Sets data retention policies for GDPR compliance,
        including automatic deletion schedules.
    .PARAMETER SpaceId
        ID of the shared space.
    .PARAMETER RetentionDays
        Default retention period in days.
    .PARAMETER SensitiveRetentionDays
        Retention period for sensitive data.
    .PARAMETER EnableAutoDelete
        Enable automatic deletion after retention period.
    .PARAMETER ApplyToExisting
        Apply retention policy to existing data.
    .EXAMPLE
        Set-MemoryRetention -SpaceId 'team-patterns' -RetentionDays 365 -EnableAutoDelete
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpaceId,
        
        [int]$RetentionDays = $script:DefaultRetentionPolicy.defaultDays,
        
        [int]$SensitiveRetentionDays = $script:DefaultRetentionPolicy.sensitiveDays,
        
        [switch]$EnableAutoDelete,
        
        [switch]$ApplyToExisting
    )
    
    $spacePath = Get-SharedSpaceFilePath -SpaceId $SpaceId
    if (-not (Test-Path -LiteralPath $spacePath)) {
        throw "Shared space not found: $SpaceId"
    }
    
    $space = Get-Content -LiteralPath $spacePath -Raw | ConvertFrom-Json
    
    # Check admin access
    $currentUser = $env:USERNAME
    if ($space.accessGrants.$currentUser -ne 'admin' -and $space.owners -notcontains $currentUser) {
        throw "Access denied: Admin permission required to set retention policy"
    }
    
    # Update retention policy
    $space.retentionDays = $RetentionDays
    $space.sensitiveRetentionDays = $SensitiveRetentionDays
    $space.autoDeleteEnabled = $EnableAutoDelete.IsPresent
    $space.retentionConfiguredAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $space.retentionConfiguredBy = $currentUser
    
    $space.modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $space.version++
    
    $space | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $spacePath -Encoding UTF8
    
    # Apply to existing data if requested
    if ($ApplyToExisting) {
        foreach ($item in $space.collections) {
            $item.expiresAt = ([datetime]::Parse($item.modifiedAt).AddDays($RetentionDays)).ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        $space | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $spacePath -Encoding UTF8
    }
    
    Write-FederationAuditLog -Operation 'SetRetention' -ResourceId $SpaceId -Action 'set_retention' -Success $true -Details @{
        retentionDays = $RetentionDays
        sensitiveRetentionDays = $SensitiveRetentionDays
        autoDeleteEnabled = $EnableAutoDelete.IsPresent
        applyToExisting = $ApplyToExisting.IsPresent
    }
    
    Write-Verbose "Set retention policy for ${SpaceId}: $RetentionDays days"
    return [pscustomobject]@{
        SpaceId = $SpaceId
        RetentionDays = $RetentionDays
        SensitiveRetentionDays = $SensitiveRetentionDays
        AutoDeleteEnabled = $EnableAutoDelete.IsPresent
        AppliedToExisting = $ApplyToExisting.IsPresent
        ConfiguredAt = $space.retentionConfiguredAt
    }
}

#endregion

#region GDPR Compliance Functions

function Request-GdprDeletion {
    <#
    .SYNOPSIS
        Submits a GDPR data deletion request.
    .DESCRIPTION
        Marks user data for deletion in compliance with GDPR.
        Data will be deleted within the configured deletion period.
    .PARAMETER SpaceId
        ID of the shared space.
    .PARAMETER UserId
        User whose data should be deleted.
    .PARAMETER Reason
        Reason for deletion request.
    .EXAMPLE
        Request-GdprDeletion -SpaceId 'team-patterns' -UserId 'former-employee'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpaceId,
        
        [Parameter(Mandatory = $true)]
        [string]$UserId,
        
        [string]$Reason = 'user_request'
    )
    
    $spacePath = Get-SharedSpaceFilePath -SpaceId $SpaceId
    if (-not (Test-Path -LiteralPath $spacePath)) {
        throw "Shared space not found: $SpaceId"
    }
    
    $space = Get-Content -LiteralPath $spacePath -Raw | ConvertFrom-Json
    
    $deletionRequest = @{
        requestId = [Guid]::NewGuid().ToString()
        userId = $UserId
        spaceId = $SpaceId
        reason = $Reason
        requestedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        scheduledDeletion = (Get-Date).AddDays($script:DefaultRetentionPolicy.gdprDeletionDays).ToString('yyyy-MM-ddTHH:mm:ssZ')
        status = 'pending'
    }
    
    if (-not $space.gdprDeletionRequests) {
        $space.gdprDeletionRequests = @()
    }
    $space.gdprDeletionRequests += $deletionRequest
    
    $space.modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $space.version++
    
    $space | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $spacePath -Encoding UTF8
    
    Write-FederationAuditLog -Operation 'GdprDeletion' -ResourceId $SpaceId -Action 'gdpr_deletion_request' -Success $true -Details @{
        requestId = $deletionRequest.requestId
        userId = $UserId
        reason = $Reason
        scheduledDeletion = $deletionRequest.scheduledDeletion
    }
    
    Write-Verbose "GDPR deletion requested for $UserId in $SpaceId"
    return [pscustomobject]$deletionRequest
}

function Invoke-GdprDeletion {
    <#
    .SYNOPSIS
        Executes pending GDPR deletion requests.
    .DESCRIPTION
        Processes and executes all pending GDPR data deletion requests
        that have reached their scheduled deletion date.
    .PARAMETER DryRun
        Preview deletions without executing.
    .EXAMPLE
        Invoke-GdprDeletion
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch]$DryRun
    )
    
    $results = @{
        Processed = 0
        Deleted = 0
        Errors = @()
        Deletions = @()
    }
    
    $spaceFiles = Get-ChildItem -Path $script:SharedSpacesPath -Filter '*.json' -ErrorAction SilentlyContinue
    
    foreach ($file in $spaceFiles) {
        try {
            $space = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            
            if (-not $space.gdprDeletionRequests) {
                continue
            }
            
            $pendingRequests = @($space.gdprDeletionRequests | Where-Object { 
                $_.status -eq 'pending' -and [datetime]::Parse($_.scheduledDeletion) -le (Get-Date)
            })
            
            foreach ($request in $pendingRequests) {
                $results.Processed++
                
                if (-not $DryRun) {
                    try {
                        # Remove user's data from collections
                        $space.collections = @($space.collections | Where-Object { $_.createdBy -ne $request.userId })
                        
                        # Remove user from access grants
                        $space.accessGrants.PSObject.Properties.Remove($request.userId)
                        
                        # Mark request as completed
                        $request.status = 'completed'
                        $request.completedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
                        
                        $space.modifiedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
                        $space.version++
                        
                        $space | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $file.FullName -Encoding UTF8
                        
                        $results.Deleted++
                        $results.Deletions += @{
                            RequestId = $request.requestId
                            UserId = $request.userId
                            SpaceId = $space.spaceId
                            CompletedAt = $request.completedAt
                        }
                        
                        Write-FederationAuditLog -Operation 'GdprDeletion' -ResourceId $space.spaceId -Action 'gdpr_deletion_executed' -Success $true -Details @{
                            requestId = $request.requestId
                            userId = $request.userId
                        }
                    }
                    catch {
                        $results.Errors += @{
                            RequestId = $request.requestId
                            UserId = $request.userId
                            Error = $_.Exception.Message
                        }
                        $request.status = 'failed'
                    }
                }
                else {
                    $results.Deletions += @{
                        RequestId = $request.requestId
                        UserId = $request.userId
                        SpaceId = $space.spaceId
                        DryRun = $true
                    }
                }
            }
        }
        catch {
            Write-Warning "Failed to process GDPR deletions for $($file.Name): $_"
        }
    }
    
    return [pscustomobject]$results
}

#endregion

# Initialize storage on module load
Initialize-FederationStorage

# Export module members
Export-ModuleMember -Function @(
    # Memory Federation
    'Register-MemoryFederation',
    'Unregister-MemoryFederation',
    'Get-MemoryFederations',
    'Test-FederationHealth',
    
    # Shared Memory Spaces
    'New-SharedMemorySpace',
    'Get-SharedMemorySpace',
    'Remove-SharedMemorySpace',
    'Grant-MemoryAccess',
    'Revoke-MemoryAccess',
    
    # Sync Operations
    'Sync-MemoryWithPeer',
    'Push-MemoryToPeer',
    'Pull-MemoryFromPeer',
    'Get-MemorySyncStatus',
    'Resolve-MemoryConflict',
    
    # Team Workspaces
    'New-TeamWorkspace',
    'Get-TeamWorkspace',
    'Add-TeamMember',
    'Remove-TeamMember',
    
    # Access Control
    'Test-MemoryAccess',
    'Get-MemoryAuditLog',
    'Set-MemoryRetention',
    
    # GDPR Compliance
    'Request-GdprDeletion',
    'Invoke-GdprDeletion'
)
