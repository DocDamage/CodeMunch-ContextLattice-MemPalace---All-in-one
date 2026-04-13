#requires -Version 5.1
<#
.SYNOPSIS
    Human Annotations and Overrides Module for LLM Workflow platform.

.DESCRIPTION
    Implements the Human Annotations system per Section 13.3 and 19.5 of the
    Canonical Architecture. Provides thread-safe annotation management with
    file locking, atomic writes, and support for project-local overrides.

    Supported annotation types:
    - correction: Fix incorrect information
    - deprecation: Mark outdated content
    - confidence: Reduce confidence in source (confidence downgrade)
    - compatibility: Add compatibility information
    - relevance: Increase relevance of source (relevance boost)
    - caveat: Add warning about content
    - override: Project-local override

.NOTES
    File: HumanAnnotations.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Phase: 6 - Human trust, replay, and governance

.EXAMPLE
    # Create a correction annotation
    $annotation = New-HumanAnnotation `
        -EntityId "source-123" `
        -EntityType "source" `
        -AnnotationType "correction" `
        -Content "The correct version is 2.5, not 2.4" `
        -Author "jsmith" `
        -Context @{ projectId = "my-project" }

.EXAMPLE
    # Get all annotations for an entity
    $annotations = Get-EntityAnnotations -EntityId "source-123" -EntityType "source"

.EXAMPLE
    # Create a project-local override
    New-ProjectOverride `
        -ProjectId "my-project" `
        -EntityId "pack-rpgmaker-001" `
        -OverrideData @{ preferredVersion = "1.2.0" } `
        -Reason "Project requires specific version for compatibility"

.LINK
    LLMWorkflow_Canonical_Document_Set_Part_1_Core_Architecture_and_Operations.md Section 13.3
    LLMWorkflow_Canonical_Document_Set_Part_1_Core_Architecture_and_Operations.md Section 19.5
#>

Set-StrictMode -Version Latest

# Module-level constants
$script:AnnotationSchemaVersion = 1
$script:ValidAnnotationTypes = @(
    'correction',
    'deprecation', 
    'confidence',
    'compatibility',
    'relevance',
    'caveat',
    'override'
)
$script:ValidEntityTypes = @('source', 'answer', 'evidence', 'pack')
$script:ValidScopes = @('global', 'workspace', 'project', 'personal')
$script:ValidStatuses = @('active', 'superseded', 'rejected')

# ============================================================================
# Internal Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Gets the path to the annotations storage directory.

.DESCRIPTION
    Creates the directory structure if it doesn't exist.
#>
function Get-AnnotationStoragePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )

    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }

    $storagePath = Join-Path $resolvedRoot ".llm-workflow\state"
    
    if (-not (Test-Path -LiteralPath $storagePath)) {
        try {
            New-Item -ItemType Directory -Path $storagePath -Force | Out-Null
        }
        catch {
            throw "Failed to create annotation storage directory: $storagePath. Error: $_"
        }
    }

    return $storagePath
}

<#
.SYNOPSIS
    Gets the path to the global annotations file.
#>
function Get-GlobalAnnotationsPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )

    $storagePath = Get-AnnotationStoragePath -ProjectRoot $ProjectRoot
    return Join-Path $storagePath "annotations.json"
}

<#
.SYNOPSIS
    Gets the path to the project overrides directory.
#>
function Get-ProjectOverridesDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )

    $storagePath = Get-AnnotationStoragePath -ProjectRoot $ProjectRoot
    $overridesPath = Join-Path $storagePath "project-overrides"
    
    if (-not (Test-Path -LiteralPath $overridesPath)) {
        try {
            New-Item -ItemType Directory -Path $overridesPath -Force | Out-Null
        }
        catch {
            throw "Failed to create project overrides directory: $overridesPath. Error: $_"
        }
    }

    return $overridesPath
}

<#
.SYNOPSIS
    Gets the path to a specific project's override file.
#>
function Get-ProjectOverridePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectId,
        
        [string]$ProjectRoot = "."
    )

    if ([string]::IsNullOrWhiteSpace($ProjectId)) {
        throw "ProjectId cannot be null or empty"
    }

    # Sanitize project ID for filesystem safety
    $safeProjectId = $ProjectId -replace '[^a-zA-Z0-9_-]', '_'
    $overridesDir = Get-ProjectOverridesDirectory -ProjectRoot $ProjectRoot
    return Join-Path $overridesDir "$safeProjectId.json"
}

<#
.SYNOPSIS
    Generates a unique annotation ID.
#>
function New-AnnotationId {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddHHmmss")
    $randomHex = (Get-Random -Minimum 0 -Maximum 268435455).ToString("x8")
    return "ann-$timestamp-$randomHex"
}

<#
.SYNOPSIS
    Validates annotation type against canonical list.
#>
function Test-AnnotationType {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    return $script:ValidAnnotationTypes -contains $Type.ToLowerInvariant()
}

<#
.SYNOPSIS
    Validates entity type against canonical list.
#>
function Test-EntityType {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    return $script:ValidEntityTypes -contains $Type.ToLowerInvariant()
}

<#
.SYNOPSIS
    Validates scope against canonical list.
#>
function Test-AnnotationScope {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Scope
    )

    return $script:ValidScopes -contains $Scope.ToLowerInvariant()
}

<#
.SYNOPSIS
    Acquires a lock for annotation file operations.
#>
function Lock-AnnotationFile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ProjectRoot = ".",
        [int]$TimeoutSeconds = 30
    )

    $lockFile = Join-Path (Get-AnnotationStoragePath -ProjectRoot $ProjectRoot) "annotations.lock"
    $startTime = [DateTime]::Now
    $acquired = $false

    while (-not $acquired) {
        try {
            $stream = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $stream.Close()
            $acquired = $true
        }
        catch [System.IO.IOException] {
            $elapsed = ([DateTime]::Now - $startTime).TotalSeconds
            if ($elapsed -ge $TimeoutSeconds) {
                throw "Timeout waiting for annotation lock"
            }
            Start-Sleep -Milliseconds 50
        }
    }

    return [pscustomobject]@{
        LockFile = $lockFile
        AcquiredAt = [DateTime]::UtcNow
    }
}

<#
.SYNOPSIS
    Releases the annotation file lock.
#>
function Unlock-AnnotationFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$LockInfo
    )

    if (Test-Path -LiteralPath $LockInfo.LockFile) {
        Remove-Item -LiteralPath $LockInfo.LockFile -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Reads the global annotations file with locking.
#>
function ConvertTo-Hashtable {
    param([Parameter(ValueFromPipeline = $true)]$InputObject)
    process {
        if ($null -eq $InputObject) { return $null }
        if ($InputObject -is [System.Collections.Hashtable]) { return $InputObject }
        if ($InputObject -is [System.Array]) {
            return @($InputObject | ForEach-Object { ConvertTo-Hashtable $_ })
        }
        $ht = @{}
        $InputObject.PSObject.Properties | ForEach-Object {
            $value = $_.Value
            if ($value -is [PSObject] -and $value -isnot [string] -and $value -isnot [System.ValueType]) {
                $ht[$_.Name] = ConvertTo-Hashtable $value
            }
            elseif ($value -is [System.Array]) {
                $ht[$_.Name] = @($value | ForEach-Object { ConvertTo-Hashtable $_ })
            }
            else {
                $ht[$_.Name] = $value
            }
        }
        return $ht
    }
}

function Read-GlobalAnnotations {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$ProjectRoot = "."
    )

    $annotationsPath = Get-GlobalAnnotationsPath -ProjectRoot $ProjectRoot
    
    if (-not (Test-Path -LiteralPath $annotationsPath)) {
        return @()
    }

    try {
        $content = Get-Content -LiteralPath $annotationsPath -Raw -ErrorAction Stop
        $data = $content | ConvertFrom-Json
        
        if ($data -and $data.annotations) {
            return @($data.annotations | ForEach-Object { ConvertTo-Hashtable $_ })
        }
        return @()
    }
    catch {
        Write-Warning "Failed to read annotations file: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Writes the global annotations file atomically with locking.
#>
function Write-GlobalAnnotations {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Annotations,
        
        [string]$ProjectRoot = "."
    )

    $annotationsPath = Get-GlobalAnnotationsPath -ProjectRoot $ProjectRoot
    $tempPath = "$annotationsPath.tmp.$PID.$([Guid]::NewGuid().ToString('N'))"

    $data = @{
        schemaVersion = $script:AnnotationSchemaVersion
        lastUpdated = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        annotationCount = $Annotations.Count
        annotations = $Annotations
    }

    try {
        $json = $data | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.Encoding]::UTF8)
        # Atomic rename - handle PowerShell 5.1 (.NET Framework) compatibility
        if (Test-Path -LiteralPath $annotationsPath) {
            [System.IO.File]::Delete($annotationsPath)
        }
        [System.IO.File]::Move($tempPath, $annotationsPath)
        return $true
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw "Failed to write annotations file: $_"
    }
}

<#
.SYNOPSIS
    Reads a project override file.
#>
function Read-ProjectOverrides {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectId,
        
        [string]$ProjectRoot = "."
    )

    $overridePath = Get-ProjectOverridePath -ProjectId $ProjectId -ProjectRoot $ProjectRoot
    
    if (-not (Test-Path -LiteralPath $overridePath)) {
        return @{
            projectId = $ProjectId
            overrides = @()
            lastUpdated = $null
        }
    }

    try {
        $content = Get-Content -LiteralPath $overridePath -Raw -ErrorAction Stop
        $data = $content | ConvertFrom-Json
        
        # Convert to hashtable for PowerShell 5.1 compatibility
        $ht = @{
            projectId = $data.projectId
            overrides = @()
            lastUpdated = $data.lastUpdated
        }
        if ($data.schemaVersion) { $ht['schemaVersion'] = $data.schemaVersion }
        
        if ($data.overrides) {
            $ht['overrides'] = @($data.overrides | ForEach-Object { ConvertTo-Hashtable $_ })
        }
        return $ht
    }
    catch {
        Write-Warning "Failed to read project overrides file: $_"
        return @{
            projectId = $ProjectId
            overrides = @()
            lastUpdated = $null
        }
    }
}

<#
.SYNOPSIS
    Writes a project override file atomically.
#>
function Write-ProjectOverrides {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Data,
        
        [string]$ProjectRoot = "."
    )

    $projectId = $Data['projectId']
    $overridePath = Get-ProjectOverridePath -ProjectId $projectId -ProjectRoot $ProjectRoot
    $tempPath = "$overridePath.tmp.$PID.$([Guid]::NewGuid().ToString('N'))"

    $Data['lastUpdated'] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $Data['schemaVersion'] = $script:AnnotationSchemaVersion

    try {
        $json = $Data | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.Encoding]::UTF8)
        # Atomic rename - handle PowerShell 5.1 (.NET Framework) compatibility
        if (Test-Path -LiteralPath $overridePath) {
            [System.IO.File]::Delete($overridePath)
        }
        [System.IO.File]::Move($tempPath, $overridePath)
        return $true
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw "Failed to write project overrides file: $_"
    }
}

<#
.SYNOPSIS
    Creates a new annotation hashtable with canonical schema.
#>
function New-AnnotationObject {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EntityId,
        
        [Parameter(Mandatory = $true)]
        [string]$EntityType,
        
        [Parameter(Mandatory = $true)]
        [string]$AnnotationType,
        
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter(Mandatory = $true)]
        [string]$Author,
        
        [hashtable]$Context = @{},
        
        [string]$AnnotationId = ""
    )

    $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    $annotation = @{
        annotationId = if ($AnnotationId) { $AnnotationId } else { New-AnnotationId }
        entityId = $EntityId
        entityType = $EntityType.ToLowerInvariant()
        annotationType = $AnnotationType.ToLowerInvariant()
        content = $Content
        author = $Author
        createdAt = $now
        updatedAt = $now
        workspaceId = $Context['workspaceId'] 
        projectId = $Context['projectId']
        scope = if ($Context['scope']) { $Context['scope'] } else { 'global' }
        status = 'active'
        votes = @{
            up = 0
            down = 0
        }
        metadata = if ($Context['metadata']) { $Context['metadata'] } else { @{} }
    }

    return $annotation
}

# ============================================================================
# Public Functions
# ============================================================================

<#
.SYNOPSIS
    Creates a new human annotation.

.DESCRIPTION
    Creates an annotation for an entity (source, answer, evidence, or pack).
    Thread-safe with file locking. Performs atomic writes.

.PARAMETER EntityId
    The unique identifier of the entity being annotated.

.PARAMETER EntityType
    The type of entity: 'source', 'answer', 'evidence', or 'pack'.

.PARAMETER AnnotationType
    The type of annotation: 'correction', 'deprecation', 'confidence', 
    'compatibility', 'relevance', 'caveat', or 'override'.

.PARAMETER Content
    The annotation text/content.

.PARAMETER Author
    The username or identifier of the person making the annotation.

.PARAMETER Context
    Additional context including workspaceId, projectId, scope, and metadata.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    PSObject. The created annotation with annotationId, timestamps, etc.

.EXAMPLE
    New-HumanAnnotation `
        -EntityId "src-godot-001" `
        -EntityType "source" `
        -AnnotationType "correction" `
        -Content "API changed in Godot 4.0" `
        -Author "developer1" `
        -Context @{ projectId = "my-game"; scope = "project" }
#>
function New-HumanAnnotation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EntityId,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('source', 'answer', 'evidence', 'pack')]
        [string]$EntityType,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('correction', 'deprecation', 'confidence', 'compatibility', 'relevance', 'caveat', 'override')]
        [string]$AnnotationType,
        
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter(Mandatory = $true)]
        [string]$Author,
        
        [hashtable]$Context = @{},
        
        [string]$ProjectRoot = "."
    )

    # Validate inputs
    if ([string]::IsNullOrWhiteSpace($EntityId)) {
        throw "EntityId cannot be null or empty"
    }
    if ([string]::IsNullOrWhiteSpace($Content)) {
        throw "Content cannot be null or empty"
    }
    if ([string]::IsNullOrWhiteSpace($Author)) {
        throw "Author cannot be null or empty"
    }

    # Create annotation object
    $annotation = New-AnnotationObject `
        -EntityId $EntityId `
        -EntityType $EntityType `
        -AnnotationType $AnnotationType `
        -Content $Content `
        -Author $Author `
        -Context $Context

    if ($PSCmdlet.ShouldProcess("annotation for $EntityType '$EntityId'", "Create")) {
        $lock = $null
        try {
            # Acquire lock
            $lock = Lock-AnnotationFile -ProjectRoot $ProjectRoot -TimeoutSeconds 30

            # Read existing annotations
            $annotations = @(Read-GlobalAnnotations -ProjectRoot $ProjectRoot)

            # Add new annotation
            $annotations += $annotation

            # Write back atomically
            Write-GlobalAnnotations -Annotations $annotations -ProjectRoot $ProjectRoot | Out-Null

            Write-Verbose "Created annotation $($annotation.annotationId) for $EntityType '$EntityId'"
        }
        finally {
            if ($lock) {
                Unlock-AnnotationFile -LockInfo $lock
            }
        }
    }

    return [pscustomobject]$annotation
}

<#
.SYNOPSIS
    Gets all annotations for a specific entity.

.DESCRIPTION
    Retrieves active annotations for the given entity ID and type.
    Returns both global annotations and project-local overrides if applicable.

.PARAMETER EntityId
    The entity identifier to search for.

.PARAMETER EntityType
    Optional entity type filter.

.PARAMETER IncludeInactive
    If specified, includes superseded and rejected annotations.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    System.Object[]. Array of annotation objects.

.EXAMPLE
    Get-EntityAnnotations -EntityId "src-godot-001" -EntityType "source"
#>
function Get-EntityAnnotations {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EntityId,
        
        [ValidateSet('source', 'answer', 'evidence', 'pack')]
        [string]$EntityType = "",
        
        [switch]$IncludeInactive,
        
        [string]$ProjectRoot = "."
    )

    $annotations = Read-GlobalAnnotations -ProjectRoot $ProjectRoot
    
    # Filter by entity
    $filtered = $annotations | Where-Object { 
        $_['entityId'] -eq $EntityId -and
        ([string]::IsNullOrWhiteSpace($EntityType) -or $_['entityType'] -eq $EntityType.ToLowerInvariant())
    }

    # Filter by status unless IncludeInactive specified
    if (-not $IncludeInactive) {
        $filtered = $filtered | Where-Object { $_['status'] -eq 'active' }
    }

    # Sort by creation date (newest first)
    $sorted = $filtered | Sort-Object -Property { $_['createdAt'] } -Descending

    return @($sorted | ForEach-Object { [pscustomobject]$_ })
}

<#
.SYNOPSIS
    Applies annotations to a target object (answer or evidence).

.DESCRIPTION
    Modifies the target object based on applicable annotations.
    Handles corrections, deprecations, confidence adjustments, etc.

.PARAMETER Target
    The target object to apply annotations to.

.PARAMETER Annotations
    Array of annotations to apply.

.PARAMETER Context
    Context for determining which annotations are applicable.

.OUTPUTS
    PSObject. The modified target object with annotations applied.

.EXAMPLE
    $answer = @{ content = "The API version is 2.4"; confidence = 0.9 }
    $annotations = Get-EntityAnnotations -EntityId "src-001"
    $corrected = Apply-Annotations -Target $answer -Annotations $annotations
#>
function Apply-Annotations {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Target,
        
        [Parameter(Mandatory = $true)]
        [array]$Annotations,
        
        [hashtable]$Context = @{}
    )

    if (-not $Target.ContainsKey('_annotations')) {
        $Target['_annotations'] = @()
    }
    if (-not $Target.ContainsKey('_caveats')) {
        $Target['_caveats'] = @()
    }
    if (-not $Target.ContainsKey('_corrections')) {
        $Target['_corrections'] = @()
    }

    $appliedCount = 0

    foreach ($annotation in $Annotations) {
        # Handle both hashtables and PSCustomObjects
        $annStatus = if ($annotation -is [System.Collections.Hashtable]) { $annotation['status'] } else { $annotation.status }
        if ($annStatus -ne 'active') {
            continue
        }

        $appliedCount++
        $annId = if ($annotation -is [System.Collections.Hashtable]) { $annotation['annotationId'] } else { $annotation.annotationId }
        $Target['_annotations'] += $annId

        $annType = if ($annotation -is [System.Collections.Hashtable]) { $annotation['annotationType'] } else { $annotation.annotationType }
        $annContent = if ($annotation -is [System.Collections.Hashtable]) { $annotation['content'] } else { $annotation.content }
        $annAuthor = if ($annotation -is [System.Collections.Hashtable]) { $annotation['author'] } else { $annotation.author }
        $annCreatedAt = if ($annotation -is [System.Collections.Hashtable]) { $annotation['createdAt'] } else { $annotation.createdAt }
        
        switch ($annType) {
            'correction' {
                $Target['_corrections'] += @{
                    original = $Target['content']
                    correction = $annContent
                    annotationId = $annId
                }
                # Apply correction to content if specified
                if ($annContent -match "^Replace:\s*(.+?)\s*->\s*(.+)$") {
                    $oldText = $Matches[1]
                    $newText = $Matches[2]
                    if ($Target['content'] -and $Target['content'].Contains($oldText)) {
                        $Target['content'] = $Target['content'].Replace($oldText, $newText)
                    }
                }
            }
            'deprecation' {
                $Target['isDeprecated'] = $true
                $Target['deprecationNote'] = $annContent
                $Target['deprecatedAt'] = $annCreatedAt
            }
            'confidence' {
                # Reduce confidence
                $adjustment = [double]$annContent
                if ($Target['confidence']) {
                    $Target['confidence'] = [math]::Max(0, $Target['confidence'] - $adjustment)
                }
                $Target['_confidenceAdjusted'] = $true
            }
            'relevance' {
                # Increase relevance score
                $boost = [double]$annContent
                if ($Target['relevanceScore']) {
                    $Target['relevanceScore'] = [math]::Min(1, $Target['relevanceScore'] + $boost)
                }
                else {
                    $Target['relevanceScore'] = $boost
                }
            }
            'compatibility' {
                if (-not $Target.ContainsKey('_compatibilityNotes')) {
                    $Target['_compatibilityNotes'] = @()
                }
                $Target['_compatibilityNotes'] += $annContent
            }
            'caveat' {
                $Target['_caveats'] += @{
                    text = $annContent
                    annotationId = $annId
                    author = $annAuthor
                }
            }
            'override' {
                # Project-local override - merge override data
                $annMetadata = if ($annotation -is [System.Collections.Hashtable]) { $annotation['metadata'] } else { $annotation.metadata }
                if ($annMetadata) {
                    if ($annMetadata -is [System.Collections.Hashtable]) {
                        foreach ($key in $annMetadata.Keys) {
                            $Target[$key] = $annMetadata[$key]
                        }
                    }
                    elseif ($annMetadata -is [PSObject]) {
                        $annMetadata.PSObject.Properties | ForEach-Object {
                            $Target[$_.Name] = $_.Value
                        }
                    }
                }
            }
        }
    }

    $Target['_annotationCount'] = $appliedCount

    Write-Verbose "Applied $appliedCount annotation(s) to target"
    return [pscustomobject]$Target
}

<#
.SYNOPSIS
    Creates a project-local override for an entity.

.DESCRIPTION
    Project-local overrides allow specific projects to customize
    entity behavior without affecting global annotations.

.PARAMETER ProjectId
    The project identifier.

.PARAMETER EntityId
    The entity being overridden.

.PARAMETER OverrideData
    Hashtable of override data to apply.

.PARAMETER Reason
    Human-readable explanation for the override.

.PARAMETER Author
    Who created the override.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    PSObject. The created override annotation.

.EXAMPLE
    New-ProjectOverride `
        -ProjectId "game-project-1" `
        -EntityId "pack-godot-001" `
        -OverrideData @{ maxVersion = "4.1"; skipValidation = $true } `
        -Reason "Project requires specific Godot version"
#>
function New-ProjectOverride {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectId,
        
        [Parameter(Mandatory = $true)]
        [string]$EntityId,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$OverrideData,
        
        [Parameter(Mandatory = $true)]
        [string]$Reason,
        
        [string]$Author = $env:USERNAME,
        
        [string]$ProjectRoot = "."
    )

    if ([string]::IsNullOrWhiteSpace($ProjectId)) {
        throw "ProjectId cannot be null or empty"
    }
    if ([string]::IsNullOrWhiteSpace($EntityId)) {
        throw "EntityId cannot be null or empty"
    }

    $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    $override = @{
        annotationId = New-AnnotationId
        entityId = $EntityId
        entityType = 'pack'
        annotationType = 'override'
        content = $Reason
        author = $Author
        createdAt = $now
        updatedAt = $now
        projectId = $ProjectId
        scope = 'project'
        status = 'active'
        metadata = $OverrideData
        votes = @{
            up = 0
            down = 0
        }
    }

    if ($PSCmdlet.ShouldProcess("override for '$EntityId' in project '$ProjectId'", "Create")) {
        $lock = $null
        try {
            # Acquire lock
            $lock = Lock-AnnotationFile -ProjectRoot $ProjectRoot -TimeoutSeconds 30

            # Read existing project overrides
            $projectData = Read-ProjectOverrides -ProjectId $ProjectId -ProjectRoot $ProjectRoot

            # Add new override
            if (-not $projectData.ContainsKey('overrides')) {
                $projectData['overrides'] = @()
            }
            $projectData['overrides'] += $override

            # Write back
            Write-ProjectOverrides -Data $projectData -ProjectRoot $ProjectRoot | Out-Null

            Write-Verbose "Created project override $($override.annotationId) for '$EntityId'"
        }
        finally {
            if ($lock) {
                Unlock-AnnotationFile -LockInfo $lock
            }
        }
    }

    return [pscustomobject]$override
}

<#
.SYNOPSIS
    Gets effective annotations for an entity with overrides applied.

.DESCRIPTION
    Retrieves all applicable annotations for an entity, including
    global annotations and project-local overrides. Merges according
    to scope precedence.

.PARAMETER EntityId
    The entity identifier.

.PARAMETER Context
    Context containing projectId, workspaceId, etc.

.PARAMETER IncludeInactive
    If specified, includes superseded and rejected annotations.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    PSObject. Object with annotations array and metadata.

.EXAMPLE
    Get-EffectiveAnnotations `
        -EntityId "pack-godot-001" `
        -Context @{ projectId = "my-game" }
#>
function Get-EffectiveAnnotations {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EntityId,
        
        [hashtable]$Context = @{},
        
        [switch]$IncludeInactive,
        
        [string]$ProjectRoot = "."
    )

    $projectId = $Context['projectId']
    $workspaceId = $Context['workspaceId']

    # Get global annotations
    $allAnnotations = Read-GlobalAnnotations -ProjectRoot $ProjectRoot
    $entityAnnotations = $allAnnotations | Where-Object { $_['entityId'] -eq $EntityId }

    # Filter by status
    if (-not $IncludeInactive) {
        $entityAnnotations = $entityAnnotations | Where-Object { $_['status'] -eq 'active' }
    }

    # Get project-specific overrides if applicable
    $projectOverrides = @()
    if (-not [string]::IsNullOrWhiteSpace($projectId)) {
        $projectData = Read-ProjectOverrides -ProjectId $projectId -ProjectRoot $ProjectRoot
        if ($projectData -and $projectData.ContainsKey('overrides')) {
            $projectOverrides = $projectData['overrides'] | Where-Object { 
                $_['entityId'] -eq $EntityId -and
                ($IncludeInactive -or $_['status'] -eq 'active')
            }
        }
    }

    # Apply scope precedence: project > workspace > global > personal
    $scopedAnnotations = @()
    
    # First, add project-local overrides (highest precedence)
    $scopedAnnotations += $projectOverrides
    
    # Then add entity-specific annotations in precedence order
    $scopeOrder = @('project', 'workspace', 'global', 'personal')
    foreach ($scope in $scopeOrder) {
        $scopeAnnotations = $entityAnnotations | Where-Object { $_['scope'] -eq $scope -and $_['annotationType'] -ne 'override' }
        $scopedAnnotations += $scopeAnnotations
    }

    # Remove duplicates (by annotationId)
    $seenIds = @{}
    $uniqueAnnotations = @()
    foreach ($ann in $scopedAnnotations) {
        $id = $ann['annotationId']
        if (-not $seenIds.ContainsKey($id)) {
            $seenIds[$id] = $true
            $uniqueAnnotations += $ann
        }
    }

    # Sort by vote score (up - down) descending, then by date
    $sorted = $uniqueAnnotations | Sort-Object -Property {
        $votes = $_['votes']
        if ($votes) {
            -($votes['up'] - $votes['down'])
        }
        else {
            0
        }
    }, { $_['createdAt'] } -Descending

    return [pscustomobject]@{
        entityId = $EntityId
        projectId = $projectId
        workspaceId = $workspaceId
        annotationCount = $sorted.Count
        annotations = @($sorted | ForEach-Object { [pscustomobject]$_ })
        hasProjectOverrides = $projectOverrides.Count -gt 0
        scopeBreakdown = @{
            project = @($sorted | Where-Object { $_['scope'] -eq 'project' }).Count
            workspace = @($sorted | Where-Object { $_['scope'] -eq 'workspace' }).Count
            global = @($sorted | Where-Object { $_['scope'] -eq 'global' }).Count
            personal = @($sorted | Where-Object { $_['scope'] -eq 'personal' }).Count
        }
    }
}

<#
.SYNOPSIS
    Exports annotations to a file.

.DESCRIPTION
    Exports annotations matching the specified filter to a JSON file.
    Useful for backup, migration, or sharing annotations.

.PARAMETER OutputPath
    The destination file path.

.PARAMETER Filter
    Filter criteria including:
    - entityTypes: Array of entity types
    - annotationTypes: Array of annotation types
    - entityIds: Array of specific entity IDs
    - scopes: Array of scopes
    - projectId: Filter by project
    - workspaceId: Filter by workspace
    - since: Export annotations created after this date
    - status: Filter by status (default: 'active')

.PARAMETER IncludeProjectOverrides
    If specified, includes project-local overrides.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    PSObject. Export result with Count, OutputPath.

.EXAMPLE
    Export-Annotations -OutputPath "annotations-backup.json" -Filter @{ scopes = @('global') }

.EXAMPLE
    Export-Annotations -OutputPath "project-annotations.json" -Filter @{ projectId = "my-project" }
#>
function Export-Annotations {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [hashtable]$Filter = @{},
        
        [switch]$IncludeProjectOverrides,
        
        [string]$ProjectRoot = "."
    )

    # Read all annotations
    $annotations = Read-GlobalAnnotations -ProjectRoot $ProjectRoot

    # Apply filters
    [array]$filtered = $annotations

    if ($Filter.ContainsKey('entityTypes') -and $Filter['entityTypes']) {
        [array]$filtered = $filtered | Where-Object { $Filter['entityTypes'] -contains $_['entityType'] }
    }

    if ($Filter.ContainsKey('annotationTypes') -and $Filter['annotationTypes']) {
        [array]$filtered = $filtered | Where-Object { $Filter['annotationTypes'] -contains $_['annotationType'] }
    }

    if ($Filter.ContainsKey('entityIds') -and $Filter['entityIds']) {
        [array]$filtered = $filtered | Where-Object { $Filter['entityIds'] -contains $_['entityId'] }
    }

    if ($Filter.ContainsKey('scopes') -and $Filter['scopes']) {
        [array]$filtered = $filtered | Where-Object { $Filter['scopes'] -contains $_['scope'] }
    }

    if ($Filter.ContainsKey('projectId') -and $Filter['projectId']) {
        [array]$filtered = $filtered | Where-Object { $_['projectId'] -eq $Filter['projectId'] -or $_['scope'] -eq 'global' }
    }

    if ($Filter.ContainsKey('workspaceId') -and $Filter['workspaceId']) {
        [array]$filtered = $filtered | Where-Object { $_['workspaceId'] -eq $Filter['workspaceId'] }
    }

    if ($Filter.ContainsKey('status')) {
        [array]$filtered = $filtered | Where-Object { $_['status'] -eq $Filter['status'] }
    }
    else {
        # Default to active only
        [array]$filtered = $filtered | Where-Object { $_['status'] -eq 'active' }
    }

    if ($Filter.ContainsKey('since') -and $Filter['since']) {
        $sinceDate = [DateTime]::Parse($Filter['since'])
        [array]$filtered = $filtered | Where-Object {
            $createdAt = [DateTime]::Parse($_['createdAt'])
            $createdAt -ge $sinceDate
        }
    }

    # Collect project overrides if requested
    $projectOverrides = @{}
    if ($IncludeProjectOverrides) {
        $overridesDir = Get-ProjectOverridesDirectory -ProjectRoot $ProjectRoot
        if (Test-Path -LiteralPath $overridesDir) {
            $overrideFiles = Get-ChildItem -Path $overridesDir -Filter "*.json"
            foreach ($file in $overrideFiles) {
                try {
                    $content = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
                    $projectId = $content['projectId']
                    if ($projectId) {
                        $projectOverrides[$projectId] = $content['overrides']
                    }
                }
                catch {
                    Write-Warning "Failed to read project override file: $($file.Name)"
                }
            }
        }
    }

    # Build export data
    $exportData = @{
        schemaVersion = $script:AnnotationSchemaVersion
        exportedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        exportedBy = [Environment]::UserName
        count = $filtered.Count
        annotations = @($filtered)
    }

    if ($IncludeProjectOverrides) {
        $exportData['projectOverrides'] = $projectOverrides
    }

    # Write export file
    $resolvedPath = Resolve-Path -Path $OutputPath -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        $resolvedPath = $OutputPath
    }

    $dir = Split-Path -Parent $resolvedPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $exportData | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($resolvedPath, $json, [System.Text.Encoding]::UTF8)

    Write-Verbose "Exported $($filtered.Count) annotation(s) to $resolvedPath"

    return [pscustomobject]@{
        Success = $true
        Count = $filtered.Count
        OutputPath = $resolvedPath
        SchemaVersion = $script:AnnotationSchemaVersion
        ExportedAt = $exportData['exportedAt']
    }
}

<#
.SYNOPSIS
    Imports annotations from a file.

.DESCRIPTION
    Imports annotations from a JSON file exported by Export-Annotations.
    Supports merge mode to combine with existing annotations.

.PARAMETER Path
    The source file path.

.PARAMETER Merge
    If specified, merges with existing annotations. Without this switch,
    existing annotations are replaced.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    PSObject. Import result with Count, Imported, Updated, Skipped.

.EXAMPLE
    Import-Annotations -Path "annotations-backup.json" -Merge
#>
function Import-Annotations {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [switch]$Merge,
        
        [string]$ProjectRoot = "."
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Import file not found: $Path"
    }

    # Read import file
    try {
        $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $importData = $content | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw "Failed to parse import file: $_"
    }

    # Validate schema version
    $importVersion = $importData['schemaVersion']
    if ($importVersion -and $importVersion -gt $script:AnnotationSchemaVersion) {
        Write-Warning "Import file schema version ($importVersion) is newer than supported ($script:AnnotationSchemaVersion). Some features may not be imported correctly."
    }

    $annotationsToImport = $importData['annotations']
    if (-not $annotationsToImport) {
        throw "No annotations found in import file"
    }

    $stats = @{
        Total = $annotationsToImport.Count
        Imported = 0
        Updated = 0
        Skipped = 0
        Failed = 0
    }

    if ($PSCmdlet.ShouldProcess("$($annotationsToImport.Count) annotation(s)", "Import")) {
        $lock = $null
        try {
            $lock = Lock-AnnotationFile -ProjectRoot $ProjectRoot -TimeoutSeconds 30

            if ($Merge) {
                # Read existing annotations
                $existingAnnotations = @(Read-GlobalAnnotations -ProjectRoot $ProjectRoot)
                $existingIds = @{}
                foreach ($ann in $existingAnnotations) {
                    $existingIds[$ann['annotationId']] = $ann
                }

                # Merge annotations
                foreach ($importAnn in $annotationsToImport) {
                    $id = $importAnn['annotationId']
                    if ($existingIds.ContainsKey($id)) {
                        # Update existing (keep newer updatedAt)
                        $existingUpdated = [DateTime]::Parse($existingIds[$id]['updatedAt'])
                        $importUpdated = [DateTime]::Parse($importAnn['updatedAt'])
                        if ($importUpdated -gt $existingUpdated) {
                            $existingIds[$id] = $importAnn
                            $stats.Updated++
                        }
                        else {
                            $stats.Skipped++
                        }
                    }
                    else {
                        # Add new
                        $existingAnnotations += $importAnn
                        $existingIds[$id] = $importAnn
                        $stats.Imported++
                    }
                }

                # Write merged annotations
                Write-GlobalAnnotations -Annotations $existingAnnotations -ProjectRoot $ProjectRoot | Out-Null
            }
            else {
                # Replace mode - validate and write
                foreach ($ann in $annotationsToImport) {
                    # Ensure required fields
                    if (-not $ann['annotationId']) {
                        $ann['annotationId'] = New-AnnotationId
                    }
                }

                Write-GlobalAnnotations -Annotations $annotationsToImport -ProjectRoot $ProjectRoot | Out-Null
                $stats.Imported = $annotationsToImport.Count
            }

            # Import project overrides if present
            if ($importData.ContainsKey('projectOverrides') -and $importData['projectOverrides']) {
                foreach ($projectId in $importData['projectOverrides'].Keys) {
                    $overrides = $importData['projectOverrides'][$projectId]
                    $existingData = Read-ProjectOverrides -ProjectId $projectId -ProjectRoot $ProjectRoot

                    if ($Merge) {
                        # Merge overrides
                        $existingOverrideIds = @{}
                        foreach ($ov in $existingData['overrides']) {
                            $existingOverrideIds[$ov['annotationId']] = $true
                        }
                        foreach ($ov in $overrides) {
                            if (-not $existingOverrideIds.ContainsKey($ov['annotationId'])) {
                                $existingData['overrides'] += $ov
                            }
                        }
                    }
                    else {
                        # Replace
                        $existingData['overrides'] = $overrides
                    }

                    Write-ProjectOverrides -Data $existingData -ProjectRoot $ProjectRoot | Out-Null
                }
            }
        }
        finally {
            if ($lock) {
                Unlock-AnnotationFile -LockInfo $lock
            }
        }
    }

    Write-Verbose "Import complete: $($stats.Imported) imported, $($stats.Updated) updated, $($stats.Skipped) skipped"

    return [pscustomobject]$stats
}

<#
.SYNOPSIS
    Gets the annotation registry information.

.DESCRIPTION
    Returns metadata about the annotation system including:
    - Total annotation count
    - Breakdown by type, scope, status
    - Storage locations
    - Schema version

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    PSObject. Registry metadata object.

.EXAMPLE
    Get-AnnotationRegistry
#>
function Get-AnnotationRegistry {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ProjectRoot = "."
    )

    $annotations = Read-GlobalAnnotations -ProjectRoot $ProjectRoot
    $globalPath = Get-GlobalAnnotationsPath -ProjectRoot $ProjectRoot
    $overridesDir = Get-ProjectOverridesDirectory -ProjectRoot $ProjectRoot

    # Count project override files
    $projectOverrideFiles = @()
    if (Test-Path -LiteralPath $overridesDir) {
        $projectOverrideFiles = Get-ChildItem -Path $overridesDir -Filter "*.json"
    }

    # Calculate breakdowns - ensure annotations is an array
    [array]$annotations = $annotations
    $byType = @{}
    $byScope = @{}
    $byStatus = @{}
    $byEntityType = @{}

    foreach ($ann in $annotations) {
        $type = $ann['annotationType']
        $scope = $ann['scope']
        $status = $ann['status']
        $entityType = $ann['entityType']

        if (-not $byType.ContainsKey($type)) { $byType[$type] = 0 }
        if (-not $byScope.ContainsKey($scope)) { $byScope[$scope] = 0 }
        if (-not $byStatus.ContainsKey($status)) { $byStatus[$status] = 0 }
        if (-not $byEntityType.ContainsKey($entityType)) { $byEntityType[$entityType] = 0 }

        $byType[$type]++
        $byScope[$scope]++
        $byStatus[$status]++
        $byEntityType[$entityType]++
    }

    return [pscustomobject]@{
        SchemaVersion = $script:AnnotationSchemaVersion
        TotalAnnotations = $annotations.Count
        ProjectOverrideFiles = $projectOverrideFiles.Count
        Storage = @{
            GlobalAnnotations = $globalPath
            ProjectOverridesDirectory = $overridesDir
        }
        Breakdown = @{
            ByType = $byType
            ByScope = $byScope
            ByStatus = $byStatus
            ByEntityType = $byEntityType
        }
        ValidTypes = @{
            AnnotationTypes = $script:ValidAnnotationTypes
            EntityTypes = $script:ValidEntityTypes
            Scopes = $script:ValidScopes
            Statuses = $script:ValidStatuses
        }
        LastUpdated = if ($annotations.Count -gt 0) { 
            ($annotations | Sort-Object { $_['updatedAt'] } -Descending | Select-Object -First 1)['updatedAt']
        } else { $null }
    }
}

<#
.SYNOPSIS
    Registers an annotation in the system.

.DESCRIPTION
    Low-level registration function for adding pre-constructed annotations.
    Used by New-HumanAnnotation and for batch imports.

.PARAMETER Annotation
    The annotation hashtable to register.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    PSObject. The registered annotation with any system-generated fields.

.EXAMPLE
    $annotation = @{ entityId = "..."; entityType = "..."; ... }
    Register-Annotation -Annotation $annotation
#>
function Register-Annotation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Annotation,
        
        [string]$ProjectRoot = "."
    )

    # Ensure required fields
    if (-not $Annotation.ContainsKey('annotationId') -or [string]::IsNullOrWhiteSpace($Annotation['annotationId'])) {
        $Annotation['annotationId'] = New-AnnotationId
    }

    if (-not $Annotation.ContainsKey('createdAt')) {
        $Annotation['createdAt'] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    if (-not $Annotation.ContainsKey('updatedAt')) {
        $Annotation['updatedAt'] = $Annotation['createdAt']
    }

    if (-not $Annotation.ContainsKey('status')) {
        $Annotation['status'] = 'active'
    }

    if (-not $Annotation.ContainsKey('votes')) {
        $Annotation['votes'] = @{ up = 0; down = 0 }
    }

    if (-not $Annotation.ContainsKey('scope')) {
        $Annotation['scope'] = 'global'
    }

    # Validate annotation type
    if (-not (Test-AnnotationType -Type $Annotation['annotationType'])) {
        throw "Invalid annotation type: $($Annotation['annotationType']). Valid types: $($script:ValidAnnotationTypes -join ', ')"
    }

    if ($PSCmdlet.ShouldProcess("annotation $($Annotation['annotationId'])", "Register")) {
        $lock = $null
        try {
            $lock = Lock-AnnotationFile -ProjectRoot $ProjectRoot -TimeoutSeconds 30

            $annotations = @(Read-GlobalAnnotations -ProjectRoot $ProjectRoot)
            $annotations += $Annotation
            Write-GlobalAnnotations -Annotations $annotations -ProjectRoot $ProjectRoot | Out-Null

            Write-Verbose "Registered annotation $($Annotation['annotationId'])"
        }
        finally {
            if ($lock) {
                Unlock-AnnotationFile -LockInfo $lock
            }
        }
    }

    return [pscustomobject]$Annotation
}

<#
.SYNOPSIS
    Updates an existing annotation.

.DESCRIPTION
    Updates the content, status, or metadata of an existing annotation.
    Preserves creation metadata and vote counts.

.PARAMETER AnnotationId
    The ID of the annotation to update.

.PARAMETER Content
    New content for the annotation.

.PARAMETER Status
    New status: 'active', 'superseded', or 'rejected'.

.PARAMETER Metadata
    Updated metadata hashtable (merged with existing).

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    PSObject. The updated annotation, or $null if not found.

.EXAMPLE
    Update-Annotation -AnnotationId "ann-20240101..." -Status "superseded"
#>
function Update-Annotation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AnnotationId,
        
        [string]$Content,
        
        [ValidateSet('active', 'superseded', 'rejected')]
        [string]$Status,
        
        [hashtable]$Metadata,
        
        [string]$ProjectRoot = "."
    )

    $lock = $null
    try {
        $lock = Lock-AnnotationFile -ProjectRoot $ProjectRoot -TimeoutSeconds 30

        $annotations = @(Read-GlobalAnnotations -ProjectRoot $ProjectRoot)
        $found = $false

        for ($i = 0; $i -lt $annotations.Count; $i++) {
            if ($annotations[$i]['annotationId'] -eq $AnnotationId) {
                if ($PSCmdlet.ShouldProcess("annotation $AnnotationId", "Update")) {
                    if (-not [string]::IsNullOrWhiteSpace($Content)) {
                        $annotations[$i]['content'] = $Content
                    }
                    if (-not [string]::IsNullOrWhiteSpace($Status)) {
                        $annotations[$i]['status'] = $Status
                    }
                    if ($Metadata) {
                        foreach ($key in $Metadata.Keys) {
                            $annotations[$i]['metadata'][$key] = $Metadata[$key]
                        }
                    }
                    $annotations[$i]['updatedAt'] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    $updated = $annotations[$i]
                    $found = $true
                }
                break
            }
        }

        if (-not $found) {
            return $null
        }

        Write-GlobalAnnotations -Annotations $annotations -ProjectRoot $ProjectRoot | Out-Null
        Write-Verbose "Updated annotation $AnnotationId"

        return [pscustomobject]$updated
    }
    finally {
        if ($lock) {
            Unlock-AnnotationFile -LockInfo $lock
        }
    }
}

<#
.SYNOPSIS
    Votes on an annotation.

.DESCRIPTION
    Casts an up or down vote on an annotation. Votes are used for
    ranking annotations in Get-EffectiveAnnotations.

.PARAMETER AnnotationId
    The ID of the annotation to vote on.

.PARAMETER Vote
    The vote type: 'up' or 'down'.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    PSObject. Vote result with new totals.

.EXAMPLE
    Vote-Annotation -AnnotationId "ann-20240101..." -Vote up
#>
function Vote-Annotation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AnnotationId,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('up', 'down')]
        [string]$Vote,
        
        [string]$ProjectRoot = "."
    )

    $lock = $null
    try {
        $lock = Lock-AnnotationFile -ProjectRoot $ProjectRoot -TimeoutSeconds 30

        $annotations = @(Read-GlobalAnnotations -ProjectRoot $ProjectRoot)
        $found = $false
        $currentVotes = $null

        for ($i = 0; $i -lt @($annotations).Count; $i++) {
            if ($annotations[$i].annotationId -eq $AnnotationId) {
                $found = $true
                if (-not $annotations[$i].ContainsKey('votes')) {
                    $annotations[$i]['votes'] = @{ up = 0; down = 0 }
                }
                $currentVotes = $annotations[$i]['votes']
                break
            }
        }

        if (-not $found) {
            # Check project overrides
            $overridesDir = Get-ProjectOverridesDirectory -ProjectRoot $ProjectRoot
            $overrideFiles = Get-ChildItem -Path $overridesDir -Filter "*.json" -ErrorAction SilentlyContinue
            
            foreach ($file in $overrideFiles) {
                $projectDataRaw = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
                $projectData = ConvertTo-Hashtable $projectDataRaw
                foreach ($override in $projectData['overrides']) {
                    if ($override.annotationId -eq $AnnotationId) {
                        if (-not $override.ContainsKey('votes')) {
                            $override['votes'] = @{ up = 0; down = 0 }
                        }
                        if ($PSCmdlet.ShouldProcess("annotation $AnnotationId", "Vote $Vote")) {
                            $override['votes'][$Vote]++
                            Write-ProjectOverrides -Data $projectData -ProjectRoot $ProjectRoot | Out-Null
                        }
                        return [pscustomobject]@{
                            AnnotationId = $AnnotationId
                            Vote = $Vote
                            TotalUp = $override['votes']['up']
                            TotalDown = $override['votes']['down']
                            Score = $override['votes']['up'] - $override['votes']['down']
                        }
                    }
                }
            }

            throw "Annotation not found: $AnnotationId"
        }

        if ($PSCmdlet.ShouldProcess("annotation $AnnotationId", "Vote $Vote")) {
            $currentVotes[$Vote]++
            Write-GlobalAnnotations -Annotations $annotations -ProjectRoot $ProjectRoot | Out-Null
        }

        return [pscustomobject]@{
            AnnotationId = $AnnotationId
            Vote = $Vote
            TotalUp = $currentVotes['up']
            TotalDown = $currentVotes['down']
            Score = $currentVotes['up'] - $currentVotes['down']
        }
    }
    finally {
        if ($lock) {
            Unlock-AnnotationFile -LockInfo $lock
        }
    }
}

<#
.SYNOPSIS
    Removes an annotation from the system.

.DESCRIPTION
    Permanently deletes an annotation. For reversible removal,
    consider using Update-Annotation to set status to 'rejected'.

.PARAMETER AnnotationId
    The ID of the annotation to remove.

.PARAMETER Force
    Skip confirmation prompt.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    System.Boolean. True if removed, false if not found.

.EXAMPLE
    Remove-Annotation -AnnotationId "ann-20240101..." -Force
#>
function Remove-Annotation {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AnnotationId,
        
        [switch]$Force,
        
        [string]$ProjectRoot = "."
    )

    $lock = $null
    try {
        $lock = Lock-AnnotationFile -ProjectRoot $ProjectRoot -TimeoutSeconds 30

        $annotations = @(Read-GlobalAnnotations -ProjectRoot $ProjectRoot)
        $originalCount = $annotations.Count

        $filtered = $annotations | Where-Object { $_['annotationId'] -ne $AnnotationId }

        if ($filtered.Count -eq $originalCount) {
            return $false
        }

        $target = "annotation $AnnotationId"
        if ($Force -or $PSCmdlet.ShouldProcess($target, "Remove")) {
            Write-GlobalAnnotations -Annotations $filtered -ProjectRoot $ProjectRoot | Out-Null
            Write-Verbose "Removed annotation $AnnotationId"
            return $true
        }

        return $false
    }
    finally {
        if ($lock) {
            Unlock-AnnotationFile -LockInfo $lock
        }
    }
}

# ============================================================================
# Export Module Members
# ============================================================================

Export-ModuleMember -Function @(
    'New-HumanAnnotation',
    'Get-EntityAnnotations',
    'Apply-Annotations',
    'New-ProjectOverride',
    'Get-EffectiveAnnotations',
    'Export-Annotations',
    'Import-Annotations',
    'Get-AnnotationRegistry',
    'Register-Annotation',
    'Update-Annotation',
    'Vote-Annotation',
    'Remove-Annotation'
)
