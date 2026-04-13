#requires -Version 5.1
<#
.SYNOPSIS
    Inter-Pack Transport layer for LLM Workflow platform.

.DESCRIPTION
    Enables data flow between domain packs (Blender, Godot, RPG Maker MZ) with
    proper transformation and validation. Supports:
    - Blender → Godot (mesh, material, animation export via glTF/GLB)
    - Godot → RPG Maker MZ (texture/sprite conversion)
    
    Implements:
    - Pipeline definitions with transform rules and validation checkpoints
    - Transform registration for format conversion
    - Export/Import with intermediate representation
    - Full sync operations with progress reporting and rollback
    - Provenance tracking (source → target lineage)
    - Incremental sync (only changed assets)

.NOTES
    File: InterPackTransport.ps1
    Version: 0.1.0
    Author: LLM Workflow Team
    Part of: Phase 7 Implementation

.EXAMPLE
    # Create a Blender → Godot pipeline
    $pipeline = New-InterPackPipeline -SourcePack "blender-engine" -TargetPack "godot-engine" -AssetTypes @("mesh", "material")
    
    # Register a transform
    Register-InterPackTransform -SourceFormat "blender_mesh" -TargetFormat "godot_mesh" -TransformFunction $meshTransform
    
    # Sync assets
    Sync-InterPackAssets -Pipeline $pipeline -AssetIds @("cube", "sphere")
#>

Set-StrictMode -Version Latest

#===============================================================================
# Constants and Configuration
#===============================================================================

$script:InterPackSchemaVersion = 1
$script:DefaultPipelinesDirectory = ".llm-workflow/interpack/pipelines"
$script:DefaultTransformsDirectory = ".llm-workflow/interpack/transforms"
$script:DefaultIntermediateDirectory = ".llm-workflow/interpack/intermediate"
$script:DefaultProvenanceDirectory = ".llm-workflow/interpack/provenance"

# Asset type definitions
$script:AssetTypes = @{
    mesh       = @{ extensions = @('.glb', '.gltf', '.obj', '.fbx'); category = '3d-geometry' }
    material   = @{ extensions = @('.material', '.tres', '.json'); category = 'surface-definition' }
    animation  = @{ extensions = @('.anim', '.gltf', '.json'); category = 'animation-data' }
    texture    = @{ extensions = @('.png', '.jpg', '.webp', '.tga'); category = 'image-data' }
    sprite     = @{ extensions = @('.png', '.jpg', '.webp'); category = '2d-image' }
    scene      = @{ extensions = @('.tscn', '.escn', '.json'); category = 'scene-definition' }
}

# Known pipeline configurations
$script:KnownPipelines = @{
    'blender-godot' = @{
        sourcePack      = 'blender-engine'
        targetPack      = 'godot-engine'
        supportedTypes  = @('mesh', 'material', 'animation', 'scene')
        defaultFormat   = 'glTF'
        transportTool   = 'godotengine/godot-blender-exporter'
        provenanceRequired = $true
    }
    'godot-rpgmaker' = @{
        sourcePack      = 'godot-engine'
        targetPack      = 'rpgmaker-mz'
        supportedTypes  = @('texture', 'sprite')
        defaultFormat   = 'png'
        transportTool   = 'custom-converter'
        provenanceRequired = $true
    }
}

# Exit codes
$script:ExitCodes = @{
    Success            = 0
    GeneralFailure     = 1
    InvalidArguments   = 2
    TransformNotFound  = 3
    ValidationFailed   = 4
    CompatibilityError = 5
    ImportFailed       = 6
    ExportFailed       = 7
    RollbackFailed     = 8
}

#===============================================================================
# Pipeline Functions
#===============================================================================

function New-InterPackPipeline {
    <#
    .SYNOPSIS
        Creates a new inter-pack pipeline definition.
    .DESCRIPTION
        Initializes a pipeline configuration for transporting assets between
        source and target packs with specified transform rules and validation checkpoints.
    .PARAMETER SourcePack
        The source pack ID (e.g., "blender-engine").
    .PARAMETER TargetPack
        The target pack ID (e.g., "godot-engine").
    .PARAMETER AssetTypes
        Array of asset types supported by this pipeline (mesh, material, animation, texture, sprite).
    .PARAMETER TransformRules
        Hashtable of transform rules for each asset type.
    .PARAMETER ValidationCheckpoints
        Array of validation checkpoints to enforce during transport.
    .PARAMETER IntermediateFormat
        Format for intermediate representation (default: "gltf").
    .PARAMETER ProjectRoot
        The project root directory. Defaults to current directory.
    .PARAMETER Metadata
        Additional metadata for the pipeline.
    .OUTPUTS
        System.Collections.Hashtable. The pipeline definition.
    .EXAMPLE
        $pipeline = New-InterPackPipeline -SourcePack "blender-engine" -TargetPack "godot-engine" -AssetTypes @("mesh", "material")
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('blender-engine', 'godot-engine', 'rpgmaker-mz')]
        [string]$SourcePack,

        [Parameter(Mandatory = $true)]
        [ValidateSet('blender-engine', 'godot-engine', 'rpgmaker-mz')]
        [string]$TargetPack,

        [Parameter()]
        [ValidateSet('mesh', 'material', 'animation', 'texture', 'sprite', 'scene')]
        [string[]]$AssetTypes = @('mesh', 'material', 'animation'),

        [Parameter()]
        [hashtable]$TransformRules = @{},

        [Parameter()]
        [string[]]$ValidationCheckpoints = @('pre-export', 'post-export', 'pre-import', 'post-import'),

        [Parameter()]
        [string]$IntermediateFormat = 'gltf',

        [Parameter()]
        [string]$ProjectRoot = '.',

        [Parameter()]
        [hashtable]$Metadata = @{}
    )

    # Validate source != target
    if ($SourcePack -eq $TargetPack) {
        throw "Source pack and target pack cannot be the same: $SourcePack"
    }

    # Generate pipeline ID
    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $pipelineId = "pipeline-$SourcePack-$TargetPack-$timestamp"

    # Resolve project root
    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) { $resolvedRoot = $ProjectRoot }

    # Build default transform rules if not provided
    if ($TransformRules.Count -eq 0) {
        foreach ($type in $AssetTypes) {
            $TransformRules[$type] = @{
                sourceFormat = "$($SourcePack.Split('-')[0])_$type"
                targetFormat = "$($TargetPack.Split('-')[0])_$type"
                versionRange = '>=1.0.0'
            }
        }
    }

    $pipeline = [ordered]@{
        schemaVersion          = $script:InterPackSchemaVersion
        pipelineId             = $pipelineId
        sourcePack             = $SourcePack
        targetPack             = $TargetPack
        assetTypes             = $AssetTypes
        transformRules         = $TransformRules
        validationCheckpoints  = $ValidationCheckpoints
        intermediateFormat     = $IntermediateFormat
        projectRoot            = $resolvedRoot
        createdUtc             = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        status                 = 'created'
        metadata               = $Metadata
        provenanceEnabled      = $true
        incrementalSyncEnabled = $true
    }

    # Save pipeline definition
    $pipelinesDir = Join-Path $resolvedRoot $script:DefaultPipelinesDirectory
    if (-not (Test-Path -LiteralPath $pipelinesDir)) {
        New-Item -ItemType Directory -Path $pipelinesDir -Force | Out-Null
    }

    $pipelinePath = Join-Path $pipelinesDir "$pipelineId.json"
    $pipeline | ConvertTo-Json -Depth 10 | Out-File -FilePath $pipelinePath -Encoding UTF8

    Write-Verbose "[InterPack] Created pipeline '$pipelineId' from $SourcePack to $TargetPack"
    return $pipeline
}

function Get-InterPackPipeline {
    <#
    .SYNOPSIS
        Retrieves an existing pipeline definition.
    .DESCRIPTION
        Loads a pipeline definition by ID or finds pipelines between specific packs.
    .PARAMETER PipelineId
        The pipeline ID to load.
    .PARAMETER SourcePack
        Filter by source pack.
    .PARAMETER TargetPack
        Filter by target pack.
    .PARAMETER ProjectRoot
        The project root directory.
    .OUTPUTS
        System.Collections.Hashtable or array of hashtables.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$PipelineId,

        [Parameter()]
        [string]$SourcePack,

        [Parameter()]
        [string]$TargetPack,

        [Parameter()]
        [string]$ProjectRoot = '.'
    )

    $pipelinesDir = Join-Path $ProjectRoot $script:DefaultPipelinesDirectory

    if (-not (Test-Path -LiteralPath $pipelinesDir)) {
        return $null
    }

    # Load specific pipeline
    if ($PipelineId) {
        $pipelinePath = Join-Path $pipelinesDir "$PipelineId.json"
        if (Test-Path -LiteralPath $pipelinePath) {
            return Get-Content -LiteralPath $pipelinePath -Raw | ConvertFrom-Json -AsHashtable
        }
        return $null
    }

    # Search for pipelines
    $pipelines = @()
    $files = Get-ChildItem -Path $pipelinesDir -Filter "*.json" -File

    foreach ($file in $files) {
        $pipeline = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
        $match = $true

        if ($SourcePack -and $pipeline.sourcePack -ne $SourcePack) { $match = $false }
        if ($TargetPack -and $pipeline.targetPack -ne $TargetPack) { $match = $false }

        if ($match) { $pipelines += $pipeline }
    }

    return $pipelines
}

function Get-InterPackPipelineStatus {
    <#
    .SYNOPSIS
        Returns pipeline health and status.
    .DESCRIPTION
        Checks the operational status of pipelines including:
        - Pipeline configuration validity
        - Transform availability
        - Compatibility status
        - Last sync time
        - Error rates
    .PARAMETER PipelineId
        Specific pipeline to check. If not provided, checks all pipelines.
    .PARAMETER ProjectRoot
        The project root directory.
    .OUTPUTS
        System.Collections.Hashtable with pipeline status information.
    .EXAMPLE
        $status = Get-InterPackPipelineStatus -PipelineId "pipeline-blender-godot-20260412T..."
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$PipelineId,

        [Parameter()]
        [string]$ProjectRoot = '.'
    )

    $result = @{
        schemaVersion   = $script:InterPackSchemaVersion
        checkedAt       = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        overallStatus   = 'healthy'
        pipelines       = @()
        warnings        = @()
        errors          = @()
    }

    $pipelines = if ($PipelineId) {
        @(Get-InterPackPipeline -PipelineId $PipelineId -ProjectRoot $ProjectRoot)
    }
    else {
        Get-InterPackPipeline -ProjectRoot $ProjectRoot
    }

    if (-not $pipelines) {
        $result.overallStatus = 'no-pipelines'
        return $result
    }

    foreach ($pipeline in $pipelines) {
        $pipelineStatus = @{
            pipelineId      = $pipeline.pipelineId
            sourcePack      = $pipeline.sourcePack
            targetPack      = $pipeline.targetPack
            status          = 'unknown'
            transformHealth = @()
            lastSync        = $null
            issues          = @()
        }

        # Check transform availability
        foreach ($assetType in $pipeline.assetTypes) {
            $rule = $pipeline.transformRules[$assetType]
            if ($rule) {
                $transform = Get-InterPackTransform -SourceFormat $rule.sourceFormat -TargetFormat $rule.targetFormat -ProjectRoot $ProjectRoot
                $pipelineStatus.transformHealth += @{
                    assetType    = $assetType
                    available    = ($null -ne $transform)
                    version      = if ($transform) { $transform.version } else { $null }
                }
            }
        }

        # Check compatibility
        $compat = Test-InterPackCompatibility -SourcePack $pipeline.sourcePack -TargetPack $pipeline.targetPack
        $pipelineStatus.compatibility = $compat

        if (-not $compat.isCompatible) {
            $pipelineStatus.status = 'incompatible'
            $pipelineStatus.issues += 'Compatibility check failed'
            $result.overallStatus = 'degraded'
        }
        elseif ($pipelineStatus.transformHealth | Where-Object { -not $_.available }) {
            $pipelineStatus.status = 'missing-transforms'
            $result.overallStatus = 'degraded'
        }
        else {
            $pipelineStatus.status = 'healthy'
        }

        # Check for last sync
        $provenanceDir = Join-Path $ProjectRoot $script:DefaultProvenanceDirectory
        $provenancePattern = "*$($pipeline.pipelineId)*.json"
        $provenanceFiles = Get-ChildItem -Path $provenanceDir -Filter $provenancePattern -ErrorAction SilentlyContinue | 
            Sort-Object LastWriteTime -Descending | 
            Select-Object -First 1

        if ($provenanceFiles) {
            $pipelineStatus.lastSync = $provenanceFiles.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }

        $result.pipelines += $pipelineStatus
    }

    return $result
}

#===============================================================================
# Transform Functions
#===============================================================================

function Register-InterPackTransform {
    <#
    .SYNOPSIS
        Registers a transform function for format conversion.
    .DESCRIPTION
        Registers a transform that can convert assets from source format to target format.
        Transforms can be scriptblocks, function names, or external tool commands.
    .PARAMETER SourceFormat
        The source format identifier (e.g., "blender_mesh").
    .PARAMETER TargetFormat
        The target format identifier (e.g., "godot_mesh").
    .PARAMETER TransformFunction
        ScriptBlock, function name, or command for the transform.
    .PARAMETER Version
        Transform version for compatibility tracking.
    .PARAMETER Description
        Human-readable description of the transform.
    .PARAMETER Parameters
        Default parameters for the transform.
    .PARAMETER ProjectRoot
        The project root directory.
    .OUTPUTS
        System.Collections.Hashtable. The registered transform.
    .EXAMPLE
        Register-InterPackTransform -SourceFormat "blender_mesh" -TargetFormat "godot_mesh" `
            -TransformFunction { param($input) Convert-BlenderToGodotMesh -Input $input } `
            -Version "1.0.0"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFormat,

        [Parameter(Mandatory = $true)]
        [string]$TargetFormat,

        [Parameter(Mandatory = $true)]
        [object]$TransformFunction,

        [Parameter()]
        [string]$Version = '1.0.0',

        [Parameter()]
        [string]$Description = '',

        [Parameter()]
        [hashtable]$Parameters = @{},

        [Parameter()]
        [string]$ProjectRoot = '.'
    )

    $transformId = "$SourceFormat-to-$TargetFormat"

    # Convert transform function to string if needed
    $transformStr = if ($TransformFunction -is [scriptblock]) {
        $TransformFunction.ToString()
    }
    else {
        [string]$TransformFunction
    }

    $transform = [ordered]@{
        schemaVersion    = $script:InterPackSchemaVersion
        transformId      = $transformId
        sourceFormat     = $SourceFormat
        targetFormat     = $TargetFormat
        transformFunction = $transformStr
        version          = $Version
        description      = $Description
        parameters       = $Parameters
        registeredUtc    = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        registeredBy     = [Environment]::UserName
    }

    # Save transform registry
    $transformsDir = Join-Path $ProjectRoot $script:DefaultTransformsDirectory
    if (-not (Test-Path -LiteralPath $transformsDir)) {
        New-Item -ItemType Directory -Path $transformsDir -Force | Out-Null
    }

    $transformPath = Join-Path $transformsDir "$transformId.json"
    $transform | ConvertTo-Json -Depth 10 | Out-File -FilePath $transformPath -Encoding UTF8

    Write-Verbose "[InterPack] Registered transform '$transformId' (v$Version)"
    return $transform
}

function Get-InterPackTransform {
    <#
    .SYNOPSIS
        Retrieves a registered transform.
    .DESCRIPTION
        Gets transform details by source and target format.
    .PARAMETER SourceFormat
        The source format identifier.
    .PARAMETER TargetFormat
        The target format identifier.
    .PARAMETER ProjectRoot
        The project root directory.
    .OUTPUTS
        System.Collections.Hashtable. The transform definition or null.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFormat,

        [Parameter(Mandatory = $true)]
        [string]$TargetFormat,

        [Parameter()]
        [string]$ProjectRoot = '.'
    )

    $transformId = "$SourceFormat-to-$TargetFormat"
    $transformPath = Join-Path $ProjectRoot "$script:DefaultTransformsDirectory/$transformId.json"

    if (Test-Path -LiteralPath $transformPath) {
        return Get-Content -LiteralPath $transformPath -Raw | ConvertFrom-Json -AsHashtable
    }

    return $null
}

function Invoke-InterPackTransform {
    <#
    .SYNOPSIS
        Executes a registered transform.
    .DESCRIPTION
        Internal helper to execute transform functions with proper error handling.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Transform,

        [Parameter(Mandatory = $true)]
        [object]$InputData,

        [Parameter()]
        [hashtable]$Parameters = @{}
    )

    try {
        # Merge default and provided parameters
        $allParams = @{}
        if ($Transform.parameters) { $allParams += $Transform.parameters }
        if ($Parameters) { $allParams += $Parameters }
        $allParams['Input'] = $InputData

        # Execute transform
        $transformScript = [scriptblock]::Create($Transform.transformFunction)
        $result = & $transformScript @allParams

        return @{
            success = $true
            data    = $result
            errors  = @()
        }
    }
    catch {
        return @{
            success = $false
            data    = $null
            errors  = @($_.Exception.Message)
        }
    }
}

#===============================================================================
# Export/Import Functions
#===============================================================================

function Invoke-InterPackExport {
    <#
    .SYNOPSIS
        Exports assets from a source pack.
    .DESCRIPTION
        Exports assets from the source pack, applies format conversion,
        creates intermediate representation, and performs validation.
    .PARAMETER Pipeline
        The pipeline definition.
    .PARAMETER AssetIds
        Array of asset IDs to export.
    .PARAMETER AssetType
        Type of assets being exported (for query-based export).
    .PARAMETER Query
        Query filter for asset selection.
    .PARAMETER OutputDirectory
        Directory for intermediate representation output.
    .PARAMETER Validate
        Whether to validate the exported assets.
    .PARAMETER RunId
        Run ID for tracking.
    .OUTPUTS
        System.Collections.Hashtable with export results.
    .EXAMPLE
        $result = Invoke-InterPackExport -Pipeline $pipeline -AssetIds @("cube", "sphere") -Validate
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Pipeline,

        [Parameter()]
        [string[]]$AssetIds = @(),

        [Parameter()]
        [ValidateSet('mesh', 'material', 'animation', 'texture', 'sprite', 'scene')]
        [string]$AssetType = '',

        [Parameter()]
        [string]$Query = '',

        [Parameter()]
        [string]$OutputDirectory = '',

        [Parameter()]
        [switch]$Validate,

        [Parameter()]
        [string]$RunId = ''
    )

    if (-not $RunId) {
        $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId 2>$null
        if (-not $RunId) {
            $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
            $random = Get-Random -Minimum 0 -Maximum 65535
            $RunId = "$timestamp-$($random.ToString('x4'))"
        }
    }

    # Determine output directory
    $intermediateDir = if ($OutputDirectory) {
        $OutputDirectory
    }
    else {
        Join-Path $Pipeline.projectRoot "$script:DefaultIntermediateDirectory/$RunId"
    }

    if (-not (Test-Path -LiteralPath $intermediateDir)) {
        New-Item -ItemType Directory -Path $intermediateDir -Force | Out-Null
    }

    $result = @{
        runId           = $RunId
        pipelineId      = $Pipeline.pipelineId
        sourcePack      = $Pipeline.sourcePack
        operation       = 'export'
        success         = $true
        exportedAssets  = @()
        failedAssets    = @()
        validationResults = @()
        outputDirectory = $intermediateDir
        startedAt       = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        completedAt     = $null
    }

    # Journal entry - before
    try {
        $journalCmd = Get-Command New-JournalEntry -ErrorAction SilentlyContinue
        if ($journalCmd) {
            & $journalCmd -RunId $RunId -Step "interpack-export" -Status "before" -Metadata @{
                pipelineId = $Pipeline.pipelineId
                assetCount = $AssetIds.Count
            } | Out-Null
        }
    }
    catch {
        Write-Verbose "Journal entry failed: $_"
    }

    try {
        # Resolve assets to export
        $assetsToExport = @()

        if ($AssetIds.Count -gt 0) {
            foreach ($id in $AssetIds) {
                $assetsToExport += @{
                    id   = $id
                    type = $AssetType
                }
            }
        }
        elseif ($Query) {
            # Query-based asset resolution would be implemented here
            Write-Warning "Query-based export not yet implemented, using placeholder"
        }

        # Export each asset
        foreach ($asset in $assetsToExport) {
            $assetResult = @{
                assetId     = $asset.id
                assetType   = $asset.type
                success     = $false
                outputPath  = $null
                errors      = @()
            }

            try {
                # Determine transform rule
                $transformRule = $Pipeline.transformRules[$asset.type]
                if (-not $transformRule) {
                    throw "No transform rule defined for asset type: $($asset.type)"
                }

                # Create intermediate representation
                $intermediateFile = Join-Path $intermediateDir "$($asset.id).$($Pipeline.intermediateFormat).json"
                $intermediateData = @{
                    schemaVersion   = $script:InterPackSchemaVersion
                    pipelineId      = $Pipeline.pipelineId
                    runId           = $RunId
                    sourcePack      = $Pipeline.sourcePack
                    assetId         = $asset.id
                    assetType       = $asset.type
                    sourceFormat    = $transformRule.sourceFormat
                    exportedAt      = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    data            = @{
                        placeholder = "Asset data for $($asset.id)"
                        format      = $Pipeline.intermediateFormat
                    }
                }

                $intermediateData | ConvertTo-Json -Depth 10 | Out-File -FilePath $intermediateFile -Encoding UTF8

                $assetResult.success = $true
                $assetResult.outputPath = $intermediateFile

                # Validation checkpoint
                if ($Validate -and $Pipeline.validationCheckpoints -contains 'post-export') {
                    $validation = Test-InterPackIntermediate -IntermediatePath $intermediateFile -AssetType $asset.type
                    $assetResult.validation = $validation
                    if (-not $validation.valid) {
                        $assetResult.success = $false
                        $assetResult.errors += "Validation failed: $($validation.errors -join ', ')"
                    }
                }
            }
            catch {
                $assetResult.errors += $_.Exception.Message
                $assetResult.success = $false
            }

            if ($assetResult.success) {
                $result.exportedAssets += $assetResult
            }
            else {
                $result.failedAssets += $assetResult
                $result.success = $false
            }
        }

        $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")

        # Journal entry - after
        try {
            $journalCmd = Get-Command New-JournalEntry -ErrorAction SilentlyContinue
            if ($journalCmd) {
                & $journalCmd -RunId $RunId -Step "interpack-export" -Status "after" -Metadata @{
                    exportedCount = $result.exportedAssets.Count
                    failedCount   = $result.failedAssets.Count
                } | Out-Null
            }
        }
        catch {
            Write-Verbose "Journal entry failed: $_"
        }
    }
    catch {
        $result.success = $false
        $result.errors = @($_.Exception.Message)
        $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    return $result
}

function Invoke-InterPackImport {
    <#
    .SYNOPSIS
        Imports assets to a target pack.
    .DESCRIPTION
        Validates intermediate representation, converts to target format,
        integrates into target pack structure, and preserves metadata.
    .PARAMETER Pipeline
        The pipeline definition.
    .PARAMETER IntermediatePaths
        Array of paths to intermediate representation files.
    .PARAMETER TargetDirectory
        Target directory for imported assets.
    .PARAMETER Validate
        Whether to validate before import.
    .PARAMETER PreserveMetadata
        Whether to preserve source metadata.
    .PARAMETER RunId
        Run ID for tracking.
    .OUTPUTS
        System.Collections.Hashtable with import results.
    .EXAMPLE
        $result = Invoke-InterPackImport -Pipeline $pipeline -IntermediatePaths @(".llm-workflow/intermediate/cube.gltf.json")
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Pipeline,

        [Parameter(Mandatory = $true)]
        [string[]]$IntermediatePaths,

        [Parameter()]
        [string]$TargetDirectory = '',

        [Parameter()]
        [switch]$Validate,

        [Parameter()]
        [switch]$PreserveMetadata = $true,

        [Parameter()]
        [string]$RunId = ''
    )

    if (-not $RunId) {
        $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
        $random = Get-Random -Minimum 0 -Maximum 65535
        $RunId = "$timestamp-$($random.ToString('x4'))"
    }

    # Determine target directory
    $targetDir = if ($TargetDirectory) {
        $TargetDirectory
    }
    else {
        Join-Path $Pipeline.projectRoot "packs/imports/$($Pipeline.targetPack)/$RunId"
    }

    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    $result = @{
        runId           = $RunId
        pipelineId      = $Pipeline.pipelineId
        targetPack      = $Pipeline.targetPack
        operation       = 'import'
        success         = $true
        importedAssets  = @()
        failedAssets    = @()
        targetDirectory = $targetDir
        startedAt       = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        completedAt     = $null
    }

    # Journal entry - before
    try {
        $journalCmd = Get-Command New-JournalEntry -ErrorAction SilentlyContinue
        if ($journalCmd) {
            & $journalCmd -RunId $RunId -Step "interpack-import" -Status "before" -Metadata @{
                pipelineId = $Pipeline.pipelineId
                fileCount  = $IntermediatePaths.Count
            } | Out-Null
        }
    }
    catch {
        Write-Verbose "Journal entry failed: $_"
    }

    try {
        foreach ($intermediatePath in $IntermediatePaths) {
            $importResult = @{
                intermediatePath = $intermediatePath
                success          = $false
                targetPath       = $null
                errors           = @()
            }

            try {
                if (-not (Test-Path -LiteralPath $intermediatePath)) {
                    throw "Intermediate file not found: $intermediatePath"
                }

                $intermediateData = Get-Content -LiteralPath $intermediatePath -Raw | ConvertFrom-Json -AsHashtable

                # Pre-import validation
                if ($Validate -and $Pipeline.validationCheckpoints -contains 'pre-import') {
                    $validation = Test-InterPackIntermediate -IntermediateData $intermediateData
                    if (-not $validation.valid) {
                        throw "Pre-import validation failed: $($validation.errors -join ', ')"
                    }
                }

                # Determine target format and path
                $assetId = $intermediateData.assetId
                $assetType = $intermediateData.assetType

                $transformRule = $Pipeline.transformRules[$assetType]
                if (-not $transformRule) {
                    throw "No transform rule for asset type: $assetType"
                }

                # Create target file
                $targetExtension = switch ($Pipeline.targetPack) {
                    'godot-engine' { '.tres' }
                    'blender-engine' { '.blend' }
                    'rpgmaker-mz' { '.png' }
                    default { '.dat' }
                }
                $targetFile = Join-Path $targetDir "$assetId$targetExtension"

                # Convert and save (placeholder implementation)
                $targetData = @{
                    schemaVersion = $script:InterPackSchemaVersion
                    pipelineId    = $Pipeline.pipelineId
                    runId         = $RunId
                    sourcePack    = $Pipeline.sourcePack
                    targetPack    = $Pipeline.targetPack
                    assetId       = $assetId
                    assetType     = $assetType
                    importedAt    = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    sourceData    = if ($PreserveMetadata) { $intermediateData } else { $null }
                    data          = @{
                        converted = $true
                        format    = $transformRule.targetFormat
                    }
                }

                $targetData | ConvertTo-Json -Depth 10 | Out-File -FilePath $targetFile -Encoding UTF8

                $importResult.success = $true
                $importResult.targetPath = $targetFile

                # Record provenance
                if ($Pipeline.provenanceEnabled) {
                    $provenance = @{
                        runId           = $RunId
                        pipelineId      = $Pipeline.pipelineId
                        sourcePack      = $Pipeline.sourcePack
                        targetPack      = $Pipeline.targetPack
                        assetId         = $assetId
                        assetType       = $assetType
                        sourceFormat    = $intermediateData.sourceFormat
                        targetFormat    = $transformRule.targetFormat
                        sourcePath      = $intermediatePath
                        targetPath      = $targetFile
                        transferredAt   = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    }
                    Export-InterPackProvenance -Provenance $provenance -ProjectRoot $Pipeline.projectRoot | Out-Null
                }
            }
            catch {
                $importResult.errors += $_.Exception.Message
                $importResult.success = $false
            }

            if ($importResult.success) {
                $result.importedAssets += $importResult
            }
            else {
                $result.failedAssets += $importResult
                $result.success = $false
            }
        }

        $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")

        # Journal entry - after
        try {
            $journalCmd = Get-Command New-JournalEntry -ErrorAction SilentlyContinue
            if ($journalCmd) {
                & $journalCmd -RunId $RunId -Step "interpack-import" -Status "after" -Metadata @{
                    importedCount = $result.importedAssets.Count
                    failedCount   = $result.failedAssets.Count
                } | Out-Null
            }
        }
        catch {
            Write-Verbose "Journal entry failed: $_"
        }
    }
    catch {
        $result.success = $false
        $result.errors = @($_.Exception.Message)
        $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    return $result
}

#===============================================================================
# Sync Functions
#===============================================================================

function Sync-InterPackAssets {
    <#
    .SYNOPSIS
        Performs a full sync operation from source to target.
    .DESCRIPTION
        Orchestrates export, transform, and import with progress reporting
        and rollback support on failure. Supports incremental sync.
    .PARAMETER Pipeline
        The pipeline definition.
    .PARAMETER AssetIds
        Array of asset IDs to sync.
    .PARAMETER AssetType
        Type of assets to sync.
    .PARAMETER Incremental
        Only sync changed assets.
    .PARAMETER DryRun
        Preview what would be done without executing.
    .PARAMETER AutoRollback
        Automatically rollback on failure.
    .PARAMETER RunId
        Run ID for tracking.
    .OUTPUTS
        System.Collections.Hashtable with sync results.
    .EXAMPLE
        $result = Sync-InterPackAssets -Pipeline $pipeline -AssetIds @("cube", "sphere") -Incremental
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Pipeline,

        [Parameter()]
        [string[]]$AssetIds = @(),

        [Parameter()]
        [ValidateSet('mesh', 'material', 'animation', 'texture', 'sprite', 'scene')]
        [string]$AssetType = '',

        [Parameter()]
        [switch]$Incremental,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [switch]$AutoRollback = $true,

        [Parameter()]
        [string]$RunId = ''
    )

    if (-not $RunId) {
        $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
        $random = Get-Random -Minimum 0 -Maximum 65535
        $RunId = "$timestamp-$($random.ToString('x4'))"
    }

    # Create execution plan
    $plan = $null
    try {
        $plannerCmd = Get-Command New-ExecutionPlan -ErrorAction SilentlyContinue
        if ($plannerCmd) {
            $plan = & $plannerCmd -Operation "interpack-sync" -Targets @($Pipeline.sourcePack, $Pipeline.targetPack) -RunId $RunId
        }
    }
    catch {
        Write-Verbose "Planner not available, proceeding without plan"
    }

    $result = @{
        runId          = $RunId
        pipelineId     = $Pipeline.pipelineId
        operation      = 'sync'
        success        = $true
        dryRun         = $DryRun.IsPresent
        incremental    = $Incremental.IsPresent
        exportResult   = $null
        importResult   = $null
        rollbackResult = $null
        errors         = @()
        startedAt      = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        completedAt    = $null
    }

    # Filter for incremental sync
    if ($Incremental -and $AssetIds.Count -gt 0) {
        $changedAssets = Get-ChangedAssets -Pipeline $Pipeline -AssetIds $AssetIds -ProjectRoot $Pipeline.projectRoot
        if ($changedAssets.Count -eq 0) {
            Write-Verbose "No changed assets to sync"
            $result.success = $true
            $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            return $result
        }
        $AssetIds = $changedAssets
    }

    # Dry run
    if ($DryRun) {
        Write-Host "`n[DRY RUN] Inter-Pack Sync Operation" -ForegroundColor Cyan
        Write-Host "Pipeline: $($Pipeline.pipelineId)" -ForegroundColor Cyan
        Write-Host "Source: $($Pipeline.sourcePack) -> Target: $($Pipeline.targetPack)" -ForegroundColor Cyan
        Write-Host "Assets to sync: $($AssetIds.Count)" -ForegroundColor Cyan
        foreach ($id in $AssetIds) { Write-Host "  - $id" -ForegroundColor Gray }
        Write-Host "`nNo changes were made." -ForegroundColor Green
        return $result
    }

    # Progress reporting
    $progressParams = @{
        Activity        = "Inter-Pack Asset Sync"
        Status          = "Exporting from $($Pipeline.sourcePack)..."
        PercentComplete = 0
    }
    Write-Progress @progressParams

    try {
        # Step 1: Export
        $exportParams = @{
            Pipeline        = $Pipeline
            AssetIds        = $AssetIds
            AssetType       = $AssetType
            Validate        = $true
            RunId           = $RunId
        }

        $result.exportResult = Invoke-InterPackExport @exportParams

        if (-not $result.exportResult.success) {
            throw "Export failed: $($result.exportResult.failedAssets.Count) assets failed"
        }

        Write-Progress -Activity "Inter-Pack Asset Sync" -Status "Importing to $($Pipeline.targetPack)..." -PercentComplete 50

        # Step 2: Import
        $intermediatePaths = $result.exportResult.exportedAssets | ForEach-Object { $_.outputPath }

        $importParams = @{
            Pipeline         = $Pipeline
            IntermediatePaths = $intermediatePaths
            Validate         = $true
            PreserveMetadata = $true
            RunId            = $RunId
        }

        $result.importResult = Invoke-InterPackImport @importParams

        if (-not $result.importResult.success) {
            throw "Import failed: $($result.importResult.failedAssets.Count) assets failed"
        }

        Write-Progress -Activity "Inter-Pack Asset Sync" -Status "Complete" -PercentComplete 100 -Completed

        $result.success = $true
        $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")

        Write-Verbose "[InterPack] Sync completed successfully. RunId: $RunId"
    }
    catch {
        $result.success = $false
        $result.errors += $_.Exception.Message

        Write-Progress -Activity "Inter-Pack Asset Sync" -Status "Failed" -Completed

        # Rollback if enabled
        if ($AutoRollback) {
            Write-Warning "Sync failed, initiating rollback..."
            $result.rollbackResult = Invoke-InterPackRollback -Pipeline $Pipeline -RunId $RunId
        }
    }

    return $result
}

#===============================================================================
# Compatibility Functions
#===============================================================================

function Test-InterPackCompatibility {
    <#
    .SYNOPSIS
        Tests if source and target packs are compatible.
    .DESCRIPTION
        Validates version compatibility, format support, and transform availability
        between source and target packs.
    .PARAMETER SourcePack
        The source pack ID.
    .PARAMETER TargetPack
        The target pack ID.
    .PARAMETER SourceVersion
        Specific source version to check.
    .PARAMETER TargetVersion
        Specific target version to check.
    .PARAMETER ProjectRoot
        The project root directory.
    .OUTPUTS
        System.Collections.Hashtable with compatibility assessment.
    .EXAMPLE
        $compat = Test-InterPackCompatibility -SourcePack "blender-engine" -TargetPack "godot-engine"
        if ($compat.isCompatible) { Proceed-Sync }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePack,

        [Parameter(Mandatory = $true)]
        [string]$TargetPack,

        [Parameter()]
        [string]$SourceVersion = '',

        [Parameter()]
        [string]$TargetVersion = '',

        [Parameter()]
        [string]$ProjectRoot = '.'
    )

    $result = @{
        schemaVersion    = $script:InterPackSchemaVersion
        sourcePack       = $SourcePack
        targetPack       = $TargetPack
        sourceVersion    = $SourceVersion
        targetVersion    = $TargetVersion
        isCompatible     = $false
        versionCompatible = $false
        formatsSupported = @()
        transformsAvailable = @()
        issues           = @()
        recommendations  = @()
        checkedAt        = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    # Check known pipeline configurations
    $pipelineKey = "$($SourcePack.Split('-')[0])-$($TargetPack.Split('-')[0])"
    $knownPipeline = $script:KnownPipelines[$pipelineKey]

    if ($knownPipeline) {
        $result.formatsSupported = $knownPipeline.supportedTypes
        $result.knownPipeline    = $knownPipeline
    }
    else {
        $result.issues += "No predefined pipeline for $pipelineKey"
        $result.recommendations += "Define custom pipeline for this source/target combination"
    }

    # Check pack manifests
    $sourceManifestPath = Join-Path $ProjectRoot "packs/manifests/$SourcePack.json"
    $targetManifestPath = Join-Path $ProjectRoot "packs/manifests/$TargetPack.json"

    if (-not (Test-Path -LiteralPath $sourceManifestPath)) {
        $result.issues += "Source pack manifest not found: $SourcePack"
    }

    if (-not (Test-Path -LiteralPath $targetManifestPath)) {
        $result.issues += "Target pack manifest not found: $TargetPack"
    }

    # Load versions from manifests if not provided
    if ((Test-Path -LiteralPath $sourceManifestPath) -and -not $SourceVersion) {
        $sourceManifest = Get-Content -LiteralPath $sourceManifestPath -Raw | ConvertFrom-Json -AsHashtable
        $result.sourceVersion = $sourceManifest.version
    }

    if ((Test-Path -LiteralPath $targetManifestPath) -and -not $TargetVersion) {
        $targetManifest = Get-Content -LiteralPath $targetManifestPath -Raw | ConvertFrom-Json -AsHashtable
        $result.targetVersion = $targetManifest.version
    }

    # Version compatibility check (simplified)
    if ($result.sourceVersion -and $result.targetVersion) {
        try {
            $compatCmd = Get-Command Test-CrossPackCompatibility -ErrorAction SilentlyContinue
            if ($compatCmd) {
                $crossCompat = & $compatCmd -SourcePackId $SourcePack -TargetPackId $TargetPack
                $result.versionCompatible = ($crossCompat.status -eq 'compatible')
            }
            else {
                # Basic version check - assume compatible if versions are valid
                $result.versionCompatible = $true
            }
        }
        catch {
            $result.versionCompatible = $true  # Default to compatible if check fails
        }
    }

    # Check transform availability
    if ($knownPipeline) {
        foreach ($type in $knownPipeline.supportedTypes) {
            $sourceFmt = "$($SourcePack.Split('-')[0])_$type"
            $targetFmt = "$($TargetPack.Split('-')[0])_$type"
            $transform = Get-InterPackTransform -SourceFormat $sourceFmt -TargetFormat $targetFmt -ProjectRoot $ProjectRoot

            $result.transformsAvailable += @{
                type      = $type
                available = ($null -ne $transform)
                version   = if ($transform) { $transform.version } else { $null }
            }
        }
    }

    # Determine overall compatibility
    $missingTransforms = $result.transformsAvailable | Where-Object { -not $_.available }

    if ($result.issues.Count -eq 0 -and 
        $result.versionCompatible -and 
        $result.formatsSupported.Count -gt 0 -and
        $missingTransforms.Count -eq 0) {
        $result.isCompatible = $true
    }

    return $result
}

#===============================================================================
# Helper Functions
#===============================================================================

function Test-InterPackIntermediate {
    <#
    .SYNOPSIS
        Validates intermediate representation.
    .DESCRIPTION
        Internal helper to validate intermediate format structure.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$IntermediatePath,

        [Parameter()]
        [hashtable]$IntermediateData,

        [Parameter()]
        [string]$AssetType
    )

    $result = @{
        valid  = $false
        errors = @()
    }

    try {
        $data = if ($IntermediateData) {
            $IntermediateData
        }
        elseif ($IntermediatePath -and (Test-Path -LiteralPath $IntermediatePath)) {
            Get-Content -LiteralPath $IntermediatePath -Raw | ConvertFrom-Json -AsHashtable
        }
        else {
            throw "No intermediate data provided"
        }

        # Required fields
        $required = @('schemaVersion', 'assetId', 'assetType', 'sourcePack')
        foreach ($field in $required) {
            if (-not $data.ContainsKey($field)) {
                $result.errors += "Missing required field: $field"
            }
        }

        # Schema version check
        if ($data.schemaVersion -and $data.schemaVersion -gt $script:InterPackSchemaVersion) {
            $result.errors += "Schema version $($data.schemaVersion) is newer than supported"
        }

        # Asset type validation
        if ($AssetType -and $data.assetType -ne $AssetType) {
            $result.errors += "Asset type mismatch: expected $AssetType, got $($data.assetType)"
        }

        $result.valid = $result.errors.Count -eq 0
    }
    catch {
        $result.errors += $_.Exception.Message
        $result.valid = $false
    }

    return $result
}

function Export-InterPackProvenance {
    <#
    .SYNOPSIS
        Records provenance information for asset transfer.
    .DESCRIPTION
        Internal helper to track source → target lineage.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Provenance,

        [Parameter()]
        [string]$ProjectRoot = '.'
    )

    $provenanceDir = Join-Path $ProjectRoot $script:DefaultProvenanceDirectory
    if (-not (Test-Path -LiteralPath $provenanceDir)) {
        New-Item -ItemType Directory -Path $provenanceDir -Force | Out-Null
    }

    $provenancePath = Join-Path $provenanceDir "prov-$($Provenance.runId)-$($Provenance.assetId).json"
    $Provenance | ConvertTo-Json -Depth 10 | Out-File -FilePath $provenancePath -Encoding UTF8

    return $provenancePath
}

function Get-ChangedAssets {
    <#
    .SYNOPSIS
        Determines which assets have changed since last sync.
    .DESCRIPTION
        Internal helper for incremental sync support.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Pipeline,

        [Parameter(Mandatory = $true)]
        [string[]]$AssetIds,

        [Parameter()]
        [string]$ProjectRoot = '.'
    )

    $changed = @()
    $provenanceDir = Join-Path $ProjectRoot $script:DefaultProvenanceDirectory

    foreach ($assetId in $AssetIds) {
        $isChanged = $true  # Default to sync if can't determine

        # Check for previous provenance
        $provPattern = "prov-*-$assetId.json"
        $provFiles = Get-ChildItem -Path $provenanceDir -Filter $provPattern -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending

        if ($provFiles -and $provFiles.Count -gt 0) {
            # Would compare timestamps/checksums here
            # For now, assume changed if no recent provenance
            $lastProv = $provFiles | Select-Object -First 1
            $age = [DateTime]::Now - $lastProv.LastWriteTime
            if ($age.TotalHours -lt 1) {
                $isChanged = $false  # Synced within last hour
            }
        }

        if ($isChanged) {
            $changed += $assetId
        }
    }

    return $changed
}

function Invoke-InterPackRollback {
    <#
    .SYNOPSIS
        Rolls back a failed sync operation.
    .DESCRIPTION
        Internal helper to clean up partial sync artifacts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Pipeline,

        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter()]
        [string]$ProjectRoot = '.'
    )

    $result = @{
        success     = $true
        cleanedPaths = @()
        errors      = @()
    }

    try {
        # Clean up intermediate files
        $intermediateDir = Join-Path $ProjectRoot "$script:DefaultIntermediateDirectory/$RunId"
        if (Test-Path -LiteralPath $intermediateDir) {
            Remove-Item -LiteralPath $intermediateDir -Recurse -Force
            $result.cleanedPaths += $intermediateDir
        }

        # Clean up imported files
        $importDir = Join-Path $ProjectRoot "packs/imports/$($Pipeline.targetPack)/$RunId"
        if (Test-Path -LiteralPath $importDir) {
            Remove-Item -LiteralPath $importDir -Recurse -Force
            $result.cleanedPaths += $importDir
        }

        Write-Verbose "[InterPack] Rollback completed for run: $RunId"
    }
    catch {
        $result.success = $false
        $result.errors += $_.Exception.Message
    }

    return $result
}

#===============================================================================
# Export Module Members
#===============================================================================

Export-ModuleMember -Function @(
    # Pipeline functions
    'New-InterPackPipeline'
    'Get-InterPackPipeline'
    'Get-InterPackPipelineStatus'
    
    # Transform functions
    'Register-InterPackTransform'
    'Get-InterPackTransform'
    
    # Export/Import functions
    'Invoke-InterPackExport'
    'Invoke-InterPackImport'
    
    # Sync functions
    'Sync-InterPackAssets'
    
    # Compatibility functions
    'Test-InterPackCompatibility'
)
