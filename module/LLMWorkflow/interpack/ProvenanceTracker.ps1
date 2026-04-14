#Requires -Version 7.0
<#
.SYNOPSIS
    Provenance Tracker - Cross-Pack Provenance Tracking System
    
.DESCRIPTION
    Provides comprehensive provenance tracking for assets across domain packs.
    Tracks asset origin, transformations, pack transfers, and maintains integrity
    through cryptographic checksums. Enables full audit trails for AI-generated
    and cross-domain workflows.
    
    Part of the LLM Workflow Platform - Inter-Pack Pipeline modules.
    Used by all pipelines for asset lineage tracking.
    
.NOTES
    File Name      : ProvenanceTracker.ps1
    Version        : 1.0.0
    Module         : LLMWorkflow
    Domain         : Inter-Pack Pipeline (Provenance)
    
.EXAMPLE
    # Create provenance record
    $record = New-ProvenanceRecord -AssetId "asset123" -Operation "Generate" -PackId "AIGenPack"
    
    # Build provenance chain
    $chain = Add-ProvenanceChain -ParentId $record.ProvenanceId -ChildAssetId "asset456"
    
    # Get full history
    $history = Get-ProvenanceHistory -AssetId "asset456"
    
    # Export manifest
    Export-ProvenanceManifest -AssetId "asset456" -OutputPath "provenance.json"
#>

#region Configuration Schema

<#
ProvenanceTracker Configuration Schema (JSON):
{
    "ProvenanceConfig": {
        "Version": "1.0.0",
        "Storage": {
            "Type": "File|Database|Cloud",
            "Path": "./provenance",
            "Database": "provenance.db",
            "Encryption": false
        },
        "Integrity": {
            "Algorithm": "SHA256|SHA512|MD5",
            "EnableSigning": false,
            "PrivateKeyPath": null
        },
        "Retention": {
            "MaxRecords": 1000000,
            "ArchiveAfterDays": 365,
            "AutoCleanup": false
        },
        "Export": {
            "DefaultFormat": "JSON|XML|C2PA",
            "IncludeMetadata": true,
            "Compress": false
        }
    }
}
#>

#endregion

#region Data Models

class ProvenanceRecord {
    [string]$ProvenanceId
    [string]$AssetId
    [string]$ParentProvenanceId
    [System.Collections.ArrayList]$ChildProvenanceIds
    [string]$RunId
    [string]$PackId
    [string]$Operation
    [string]$OperationVersion
    [datetime]$Timestamp
    [hashtable]$Parameters
    [hashtable]$Inputs
    [hashtable]$Outputs
    [string]$Checksum
    [string]$Algorithm
    [string]$AgentId
    [hashtable]$Metadata
    [string]$Status
    
    ProvenanceRecord([string]$assetId, [string]$operation, [string]$packId) {
        $this.ProvenanceId = [Guid]::NewGuid().ToString()
        $this.AssetId = $assetId
        $this.ChildProvenanceIds = @()
        $this.RunId = $env:LLM_WORKFLOW_RUN_ID
        if (-not $this.RunId) {
            $this.RunId = [Guid]::NewGuid().ToString()
            $env:LLM_WORKFLOW_RUN_ID = $this.RunId
        }
        $this.PackId = $packId
        $this.Operation = $operation
        $this.Timestamp = Get-Date
        $this.Parameters = @{}
        $this.Inputs = @{}
        $this.Outputs = @{}
        $this.Algorithm = "SHA256"
        $this.AgentId = $env:COMPUTERNAME
        $this.Metadata = @{}
        $this.Status = "Created"
    }
}

class ProvenanceChain {
    [string]$ChainId
    [string]$RootProvenanceId
    [System.Collections.ArrayList]$Records
    [hashtable]$AssetMap
    [hashtable]$PackTransitions
    [datetime]$CreatedAt
    [datetime]$LastUpdated
    
    ProvenanceChain([string]$rootId) {
        $this.ChainId = [Guid]::NewGuid().ToString()
        $this.RootProvenanceId = $rootId
        $this.Records = @()
        $this.AssetMap = @{}
        $this.PackTransitions = @{}
        $this.CreatedAt = Get-Date
        $this.LastUpdated = Get-Date
    }
}

class ProvenanceManifest {
    [string]$ManifestId
    [string]$AssetId
    [string]$RootAssetId
    [System.Collections.ArrayList]$Chain
    [hashtable]$Summary
    [hashtable]$Integrity
    [string]$SchemaVersion
    [datetime]$ExportedAt
    
    ProvenanceManifest([string]$assetId) {
        $this.ManifestId = [Guid]::NewGuid().ToString()
        $this.AssetId = $assetId
        $this.Chain = @()
        $this.Summary = @{}
        $this.Integrity = @{}
        $this.SchemaVersion = "1.0.0"
        $this.ExportedAt = Get-Date
    }
}

class IntegrityResult {
    [bool]$IsValid
    [System.Collections.ArrayList]$Violations
    [hashtable]$Checksums
    [string]$ChainId
    [datetime]$ValidatedAt
    
    IntegrityResult() {
        $this.IsValid = $true
        $this.Violations = @()
        $this.Checksums = @{}
        $this.ValidatedAt = Get-Date
    }
}

#endregion

#region Constants

$script:ProvenanceStorePath = Join-Path $PWD ".provenance"
$script:DefaultAlgorithm = "SHA256"
$script:SchemaVersion = "1.0.0"

$script:SupportedOperations = @(
    "Create",
    "Generate",
    "Transform",
    "Convert",
    "Import",
    "Export",
    "Modify",
    "Delete",
    "Sync",
    "Deploy",
    "TextToImageGeneration",
    "ImageTo3DConversion",
    "TextureGeneration",
    "MaterialGeneration",
    "VoiceToAnimationSync",
    "MLModelDeployment"
)

#endregion

#region Storage Functions

function Initialize-ProvenanceStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$StorePath = $script:ProvenanceStorePath
    )
    
    if (-not (Test-Path $StorePath)) {
        New-Item -ItemType Directory -Path $StorePath -Force | Out-Null
        Write-Verbose "Created provenance store: $StorePath"
    }
    
    $recordsPath = Join-Path $StorePath "records"
    $chainsPath = Join-Path $StorePath "chains"
    $manifestsPath = Join-Path $StorePath "manifests"
    
    foreach ($path in @($recordsPath, $chainsPath, $manifestsPath)) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
    
    return $StorePath
}

function Save-ProvenanceRecord {
    param(
        [ProvenanceRecord]$Record,
        [string]$StorePath = $script:ProvenanceStorePath
    )
    
    $Record.Status = "Saved"
    $recordPath = Join-Path $StorePath "records" "$($Record.ProvenanceId).json"
    
    $recordData = @{
        ProvenanceId = $Record.ProvenanceId
        AssetId = $Record.AssetId
        ParentProvenanceId = $Record.ParentProvenanceId
        ChildProvenanceIds = $Record.ChildProvenanceIds
        RunId = $Record.RunId
        PackId = $Record.PackId
        Operation = $Record.Operation
        OperationVersion = $Record.OperationVersion
        Timestamp = $Record.Timestamp.ToString("o")
        Parameters = $Record.Parameters
        Inputs = $Record.Inputs
        Outputs = $Record.Outputs
        Checksum = $Record.Checksum
        Algorithm = $Record.Algorithm
        AgentId = $Record.AgentId
        Metadata = $Record.Metadata
        Status = $Record.Status
    }
    
    $recordData | ConvertTo-Json -Depth 10 | Out-File -FilePath $recordPath -Encoding UTF8
    
    return $recordPath
}

function Load-ProvenanceRecord {
    param(
        [string]$ProvenanceId,
        [string]$StorePath = $script:ProvenanceStorePath
    )
    
    $recordPath = Join-Path $StorePath "records" "$ProvenanceId.json"
    
    if (-not (Test-Path $recordPath)) {
        return $null
    }
    
    $data = Get-Content $recordPath -Raw | ConvertFrom-Json -AsHashtable
    
    $record = [ProvenanceRecord]::new($data.AssetId, $data.Operation, $data.PackId)
    $record.ProvenanceId = $data.ProvenanceId
    $record.ParentProvenanceId = $data.ParentProvenanceId
    $record.ChildProvenanceIds = $data.ChildProvenanceIds
    $record.RunId = $data.RunId
    $record.OperationVersion = $data.OperationVersion
    $record.Timestamp = [datetime]::Parse($data.Timestamp)
    $record.Parameters = $data.Parameters
    $record.Inputs = $data.Inputs
    $record.Outputs = $data.Outputs
    $record.Checksum = $data.Checksum
    $record.Algorithm = $data.Algorithm
    $record.AgentId = $data.AgentId
    $record.Metadata = $data.Metadata
    $record.Status = $data.Status
    
    return $record
}

#endregion

#region Main Functions

<#
.SYNOPSIS
    Creates a new provenance record.

.DESCRIPTION
    Creates a provenance entry tracking an asset's creation or transformation.
    Records all metadata including operation, parameters, checksums, and pack context.

.PARAMETER AssetId
    Unique identifier for the asset.

.PARAMETER Operation
    Type of operation performed on the asset.

.PARAMETER PackId
    Identifier of the pack where the operation occurred.

.PARAMETER Parameters
    Operation parameters and configuration.

.PARAMETER Inputs
    Input asset references.

.PARAMETER Outputs
    Output asset information.

.PARAMETER Checksum
    Asset file checksum for integrity.

.PARAMETER Algorithm
    Checksum algorithm used (default: SHA256).

.PARAMETER Metadata
    Additional metadata to store.

.PARAMETER StorePath
    Path to provenance storage.

.EXAMPLE
    $record = New-ProvenanceRecord -AssetId "img_001" -Operation "Generate" -PackId "AIGenPack"
    
    $record = New-ProvenanceRecord -AssetId "model_3d" -Operation "ImageTo3DConversion" `
        -PackId "BlenderPack" -Parameters @{ Quality = "High" } `
        -Inputs @{ SourceImage = "img_001" } -Checksum "a1b2c3..."
#>
function New-ProvenanceRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssetId,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Create", "Generate", "Transform", "Convert", "Import", "Export", 
                     "Modify", "Delete", "Sync", "Deploy", "TextToImageGeneration",
                     "ImageTo3DConversion", "TextureGeneration", "MaterialGeneration",
                     "VoiceToAnimationSync", "MLModelDeployment")]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [string]$PackId,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{},
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Inputs = @{},
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Outputs = @{},
        
        [Parameter(Mandatory = $false)]
        [string]$Checksum,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("SHA256", "SHA512", "MD5")]
        [string]$Algorithm = "SHA256",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Metadata = @{},
        
        [Parameter(Mandatory = $false)]
        [string]$StorePath = $script:ProvenanceStorePath
    )
    
    Write-Verbose "Creating provenance record..."
    Write-Verbose "Asset: $AssetId, Operation: $Operation, Pack: $PackId"
    
    # Initialize store
    Initialize-ProvenanceStore -StorePath $StorePath | Out-Null
    
    # Create record
    $record = [ProvenanceRecord]::new($AssetId, $Operation, $PackId)
    $record.Parameters = $Parameters.Clone()
    $record.Inputs = $Inputs.Clone()
    $record.Outputs = $Outputs.Clone()
    $record.Algorithm = $Algorithm
    $record.Metadata = $Metadata.Clone()
    $record.Metadata["PowerShellVersion"] = $PSVersionTable.PSVersion.ToString()
    $record.Metadata["Platform"] = $PSVersionTable.Platform
    
    # Compute checksum if not provided but file path is in outputs
    if (-not $Checksum -and $Outputs.ContainsKey("FilePath") -and (Test-Path $Outputs.FilePath)) {
        $record.Checksum = Get-FileChecksum -FilePath $Outputs.FilePath -Algorithm $Algorithm
    } else {
        $record.Checksum = $Checksum
    }
    
    # Save record
    $savedPath = Save-ProvenanceRecord -Record $record -StorePath $StorePath
    
    Write-Host "Provenance record created: $($record.ProvenanceId)" -ForegroundColor Green
    Write-Host "  Asset: $AssetId" -ForegroundColor Gray
    Write-Host "  Run: $($record.RunId)" -ForegroundColor Gray
    
    return $record
}

<#
.SYNOPSIS
    Links provenance records in a chain.

.DESCRIPTION
    Establishes parent-child relationships between provenance records,
    creating a chain of asset transformations across packs.

.PARAMETER ParentProvenanceId
    The parent record's provenance ID.

.PARAMETER ChildAssetId
    The child asset's ID.

.PARAMETER ChildOperation
    Operation type for the child record.

.PARAMETER ChildPackId
    Pack ID for the child operation.

.PARAMETER Parameters
    Child operation parameters.

.PARAMETER StorePath
    Path to provenance storage.

.EXAMPLE
    $childRecord = Add-ProvenanceChain -ParentProvenanceId $parent.ProvenanceId `
        -ChildAssetId "asset_002" -ChildOperation "Transform" -ChildPackId "BlenderPack"
#>
function Add-ProvenanceChain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParentProvenanceId,
        
        [Parameter(Mandatory = $true)]
        [string]$ChildAssetId,
        
        [Parameter(Mandatory = $true)]
        [string]$ChildOperation,
        
        [Parameter(Mandatory = $true)]
        [string]$ChildPackId,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{},
        
        [Parameter(Mandatory = $false)]
        [string]$StorePath = $script:ProvenanceStorePath
    )
    
    Write-Verbose "Adding to provenance chain..."
    Write-Verbose "Parent: $ParentProvenanceId -> Child: $ChildAssetId"
    
    # Load parent record
    $parentRecord = Load-ProvenanceRecord -ProvenanceId $ParentProvenanceId -StorePath $StorePath
    
    if (-not $parentRecord) {
        throw "Parent provenance record not found: $ParentProvenanceId"
    }
    
    # Create child record
    $childRecord = [ProvenanceRecord]::new($ChildAssetId, $ChildOperation, $ChildPackId)
    $childRecord.ParentProvenanceId = $ParentProvenanceId
    $childRecord.Parameters = $Parameters.Clone()
    $childRecord.Inputs["ParentAssetId"] = $parentRecord.AssetId
    $childRecord.Inputs["ParentProvenanceId"] = $ParentProvenanceId
    $childRecord.RunId = $parentRecord.RunId  # Maintain same run ID
    
    # Update parent with child reference
    $parentRecord.ChildProvenanceIds.Add($childRecord.ProvenanceId) | Out-Null
    Save-ProvenanceRecord -Record $parentRecord -StorePath $StorePath | Out-Null
    
    # Save child record
    Save-ProvenanceRecord -Record $childRecord -StorePath $StorePath | Out-Null
    
    Write-Host "Provenance chain extended" -ForegroundColor Green
    Write-Host "  Parent: $ParentProvenanceId ($($parentRecord.Operation))" -ForegroundColor Gray
    Write-Host "  Child: $($childRecord.ProvenanceId) ($ChildOperation)" -ForegroundColor Gray
    
    return $childRecord
}

<#
.SYNOPSIS
    Gets the full provenance history for an asset.

.DESCRIPTION
    Retrieves the complete provenance chain for an asset, including all
    transformations, pack transfers, and operations.

.PARAMETER AssetId
    The asset ID to query.

.PARAMETER IncludeSiblings
    Include sibling assets in the same run.

.PARAMETER StorePath
    Path to provenance storage.

.EXAMPLE
    $history = Get-ProvenanceHistory -AssetId "asset_123"
    
    $history = Get-ProvenanceHistory -AssetId "asset_123" -IncludeSiblings
#>
function Get-ProvenanceHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssetId,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeSiblings,
        
        [Parameter(Mandatory = $false)]
        [string]$StorePath = $script:ProvenanceStorePath
    )
    
    Write-Verbose "Retrieving provenance history for asset: $AssetId"
    
    # Find the record for this asset
    $recordsPath = Join-Path $StorePath "records"
    $allRecords = Get-ChildItem -Path $recordsPath -Filter "*.json" -File | ForEach-Object {
        Get-Content $_.FullName -Raw | ConvertFrom-Json -AsHashtable
    }
    
    $targetRecord = $allRecords | Where-Object { $_.AssetId -eq $AssetId } | Select-Object -First 1
    
    if (-not $targetRecord) {
        Write-Warning "No provenance record found for asset: $AssetId"
        return $null
    }
    
    # Build the chain by traversing parents
    $chain = [System.Collections.ArrayList]::new()
    $currentId = $targetRecord.ProvenanceId
    $rootAssetId = $targetRecord.AssetId
    
    while ($currentId) {
        $record = Load-ProvenanceRecord -ProvenanceId $currentId -StorePath $StorePath
        if ($record) {
            $chain.Insert(0, $record)
            
            # Track root asset
            if (-not $record.ParentProvenanceId) {
                $rootAssetId = $record.AssetId
            }
            
            $currentId = $record.ParentProvenanceId
        } else {
            break
        }
    }
    
    # Build result
    $result = @{
        AssetId = $AssetId
        RootAssetId = $rootAssetId
        Chain = $chain
        ChainLength = $chain.Count
        Operations = $chain | ForEach-Object { $_.Operation }
        PackTransitions = @()
        RunId = $targetRecord.RunId
    }
    
    # Track pack transitions
    $prevPack = $null
    foreach ($record in $chain) {
        if ($prevPack -and $prevPack -ne $record.PackId) {
            $result.PackTransitions += @{
                From = $prevPack
                To = $record.PackId
                AtProvenanceId = $record.ProvenanceId
                Timestamp = $record.Timestamp
            }
        }
        $prevPack = $record.PackId
    }
    
    # Include siblings if requested
    if ($IncludeSiblings) {
        $siblings = $allRecords | Where-Object { 
            $_.RunId -eq $targetRecord.RunId -and 
            $_.AssetId -ne $AssetId 
        }
        $result.Siblings = $siblings
    }
    
    Write-Host "Provenance history retrieved: $($chain.Count) records" -ForegroundColor Green
    Write-Host "  Root: $rootAssetId" -ForegroundColor Gray
    Write-Host "  Packs: $(($chain | ForEach-Object { $_.PackId } | Select-Object -Unique) -join ' -> ')" -ForegroundColor Gray
    
    return $result
}

<#
.SYNOPSIS
    Exports provenance manifest for an asset.

.DESCRIPTION
    Exports the complete provenance chain as a manifest file in various formats
    (JSON, XML, or C2PA-compatible).

.PARAMETER AssetId
    The asset ID to export.

.PARAMETER OutputPath
    Path for the output manifest file.

.PARAMETER Format
    Export format (JSON, XML, C2PA).

.PARAMETER IncludeFullChain
    Include complete provenance chain (default) or just this asset.

.PARAMETER Compress
    Compress the output file.

.PARAMETER StorePath
    Path to provenance storage.

.EXAMPLE
    Export-ProvenanceManifest -AssetId "asset_123" -OutputPath "manifest.json"
    
    Export-ProvenanceManifest -AssetId "asset_123" -OutputPath "manifest.json" -Format "C2PA"
#>
function Export-ProvenanceManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssetId,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("JSON", "XML", "C2PA")]
        [string]$Format = "JSON",
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeFullChain = $true,
        
        [Parameter(Mandatory = $false)]
        [switch]$Compress,
        
        [Parameter(Mandatory = $false)]
        [string]$StorePath = $script:ProvenanceStorePath
    )
    
    Write-Verbose "Exporting provenance manifest..."
    Write-Verbose "Asset: $AssetId, Format: $Format"
    
    # Get provenance history
    $history = Get-ProvenanceHistory -AssetId $AssetId -StorePath $StorePath
    
    if (-not $history) {
        throw "No provenance history found for asset: $AssetId"
    }
    
    # Create manifest
    $manifest = [ProvenanceManifest]::new($AssetId)
    $manifest.RootAssetId = $history.RootAssetId
    
    foreach ($record in $history.Chain) {
        $manifest.Chain += @{
            ProvenanceId = $record.ProvenanceId
            AssetId = $record.AssetId
            ParentProvenanceId = $record.ParentProvenanceId
            Operation = $record.Operation
            PackId = $record.PackId
            Timestamp = $record.Timestamp.ToString("o")
            Checksum = $record.Checksum
            Algorithm = $record.Algorithm
            AgentId = $record.AgentId
            Parameters = $record.Parameters
            Inputs = $record.Inputs
            Outputs = $record.Outputs
            Metadata = $record.Metadata
        }
    }
    
    $manifest.Summary = @{
        TotalOperations = $history.Chain.Count
        Operations = $history.Operations | Group-Object | ForEach-Object { @{ $_.Name = $_.Count } }
        PackTransitions = $history.PackTransitions.Count
        SourcePack = $history.Chain[0].PackId
        TargetPack = $history.Chain[-1].PackId
        TimeSpan = ($history.Chain[-1].Timestamp - $history.Chain[0].Timestamp).ToString()
    }
    
    # Calculate manifest checksum
    $manifestJson = $manifest | ConvertTo-Json -Depth 10
    $manifest.Integrity = @{
        Algorithm = "SHA256"
        ManifestChecksum = (Get-StringHash -String $manifestJson -Algorithm "SHA256")
        RecordCount = $manifest.Chain.Count
        ValidatedAt = [datetime]::UtcNow.ToString("o")
    }
    
    # Export based on format
    $outputContent = switch ($Format) {
        "JSON" {
            $manifest | ConvertTo-Json -Depth 10
        }
        "XML" {
            ConvertTo-ProvenanceXml -Manifest $manifest
        }
        "C2PA" {
            ConvertTo-C2PAFormat -Manifest $manifest
        }
    }
    
    # Ensure output directory exists
    $outputDir = Split-Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    # Write output
    if ($Compress) {
        $outputContent | Compress-String | Set-Content -Path $OutputPath -Encoding UTF8
    } else {
        $outputContent | Out-File -FilePath $OutputPath -Encoding UTF8
    }
    
    Write-Host "Provenance manifest exported: $OutputPath" -ForegroundColor Green
    Write-Host "  Format: $Format" -ForegroundColor Gray
    Write-Host "  Records: $($manifest.Chain.Count)" -ForegroundColor Gray
    
    return @{
        OutputPath = $OutputPath
        Format = $Format
        RecordCount = $manifest.Chain.Count
        ManifestId = $manifest.ManifestId
    }
}

<#
.SYNOPSIS
    Validates provenance chain integrity.

.DESCRIPTION
    Verifies the integrity of a provenance chain by checking checksums,
    signatures, and chain continuity.

.PARAMETER AssetId
    The asset ID to validate.

.PARAMETER VerifyFileChecksums
    Verify actual file checksums against recorded values.

.PARAMETER StrictMode
    Fail on any validation warning.

.PARAMETER StorePath
    Path to provenance storage.

.EXAMPLE
    $result = Validate-ProvenanceIntegrity -AssetId "asset_123"
    
    $result = Validate-ProvenanceIntegrity -AssetId "asset_123" -VerifyFileChecksums -StrictMode
#>
function Validate-ProvenanceIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssetId,
        
        [Parameter(Mandatory = $false)]
        [switch]$VerifyFileChecksums,
        
        [Parameter(Mandatory = $false)]
        [switch]$StrictMode,
        
        [Parameter(Mandatory = $false)]
        [string]$StorePath = $script:ProvenanceStorePath
    )
    
    Write-Verbose "Validating provenance integrity for asset: $AssetId"
    
    $result = [IntegrityResult]::new()
    $result.ChainId = $AssetId
    
    # Get provenance history
    $history = Get-ProvenanceHistory -AssetId $AssetId -StorePath $StorePath
    
    if (-not $history) {
        $result.IsValid = $false
        $result.Violations.Add("No provenance history found for asset: $AssetId")
        return $result
    }
    
    # Validate chain continuity
    for ($i = 0; $i -lt $history.Chain.Count; $i++) {
        $record = $history.Chain[$i]
        
        # Check parent references
        if ($i -eq 0) {
            if ($record.ParentProvenanceId) {
                $violation = "Root record should not have parent: $($record.ProvenanceId)"
                $result.Violations.Add($violation)
                if ($StrictMode) { $result.IsValid = $false }
            }
        } else {
            $expectedParent = $history.Chain[$i - 1].ProvenanceId
            if ($record.ParentProvenanceId -ne $expectedParent) {
                $violation = "Chain break at $($record.ProvenanceId): expected parent $expectedParent, found $($record.ParentProvenanceId)"
                $result.Violations.Add($violation)
                $result.IsValid = $false
            }
        }
        
        # Verify file checksums if requested
        if ($VerifyFileChecksums -and $record.Outputs.ContainsKey("FilePath")) {
            $filePath = $record.Outputs.FilePath
            if (Test-Path $filePath) {
                $currentChecksum = Get-FileChecksum -FilePath $filePath -Algorithm $record.Algorithm
                $result.Checksums[$record.ProvenanceId] = $currentChecksum
                
                if ($currentChecksum -ne $record.Checksum) {
                    $violation = "Checksum mismatch for $($record.ProvenanceId): file may have been modified"
                    $result.Violations.Add($violation)
                    $result.IsValid = $false
                }
            } else {
                $violation = "File not found for checksum verification: $filePath"
                $result.Violations.Add($violation)
                if ($StrictMode) { $result.IsValid = $false }
            }
        }
        
        # Validate required fields
        if (-not $record.Timestamp) {
            $result.Violations.Add("Missing timestamp in record: $($record.ProvenanceId)")
        }
        if (-not $record.Operation) {
            $result.Violations.Add("Missing operation in record: $($record.ProvenanceId)")
            $result.IsValid = $false
        }
        if (-not $record.PackId) {
            $result.Violations.Add("Missing pack ID in record: $($record.ProvenanceId)")
            $result.IsValid = $false
        }
    }
    
    # Output results
    if ($result.IsValid -and $result.Violations.Count -eq 0) {
        Write-Host "Provenance integrity validated: PASSED" -ForegroundColor Green
    } elseif ($result.IsValid) {
        Write-Host "Provenance integrity validated: PASSED with warnings" -ForegroundColor Yellow
        foreach ($v in $result.Violations) {
            Write-Host "  Warning: $v" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Provenance integrity validated: FAILED" -ForegroundColor Red
        foreach ($v in $result.Violations) {
            Write-Host "  Violation: $v" -ForegroundColor Red
        }
    }
    
    return $result
}

#endregion

#region Helper Functions

function Get-FileChecksum {
    param(
        [string]$FilePath,
        [string]$Algorithm = "SHA256"
    )
    
    if (-not (Test-Path $FilePath)) {
        return $null
    }
    
    $hash = Get-FileHash -Path $FilePath -Algorithm $Algorithm
    return $hash.Hash
}

function Get-StringHash {
    param(
        [string]$String,
        [string]$Algorithm = "SHA256"
    )
    
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($String)
    $hashAlgorithm = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    $hash = $hashAlgorithm.ComputeHash($bytes)
    return [BitConverter]::ToString($hash) -replace '-', ''
}

function ConvertTo-ProvenanceXml {
    param([ProvenanceManifest]$Manifest)
    
    $sb = [System.Text.StringBuilder]::new()
    $sb.AppendLine("<?xml version=`"1.0`" encoding=`"UTF-8`"?>") | Out-Null
    $sb.AppendLine("<provenance-manifest version=`"$($Manifest.SchemaVersion)`">") | Out-Null
    $sb.AppendLine("  <manifest-id>$($Manifest.ManifestId)</manifest-id>") | Out-Null
    $sb.AppendLine("  <asset-id>$($Manifest.AssetId)</asset-id>") | Out-Null
    $sb.AppendLine("  <root-asset-id>$($Manifest.RootAssetId)</root-asset-id>") | Out-Null
    $sb.AppendLine("  <exported-at>$($Manifest.ExportedAt.ToString("o"))</exported-at>") | Out-Null
    
    $sb.AppendLine("  <chain>") | Out-Null
    foreach ($record in $Manifest.Chain) {
        $sb.AppendLine("    <record>") | Out-Null
        $sb.AppendLine("      <provenance-id>$($record.ProvenanceId)</provenance-id>") | Out-Null
        $sb.AppendLine("      <asset-id>$($record.AssetId)</asset-id>") | Out-Null
        $sb.AppendLine("      <operation>$($record.Operation)</operation>") | Out-Null
        $sb.AppendLine("      <pack-id>$($record.PackId)</pack-id>") | Out-Null
        $sb.AppendLine("      <timestamp>$($record.Timestamp)</timestamp>") | Out-Null
        if ($record.Checksum) {
            $sb.AppendLine("      <checksum algorithm=`"$($record.Algorithm)`">$($record.Checksum)</checksum>") | Out-Null
        }
        $sb.AppendLine("    </record>") | Out-Null
    }
    $sb.AppendLine("  </chain>") | Out-Null
    
    $sb.AppendLine("</provenance-manifest>") | Out-Null
    
    return $sb.ToString()
}

function ConvertTo-C2PAFormat {
    param([ProvenanceManifest]$Manifest)
    
    # C2PA (Coalition for Content Provenance and Authenticity) format
    $c2pa = @{
        "@context" = @("https://c2pa.org/1.0", "https://llmworkflow.org/provenance/1.0")
        "@type" = "ProvenanceManifest"
        "claim_generator" = "LLM Workflow Platform/$($Manifest.SchemaVersion)"
        "claim_generator_info" = @{
            name = "LLM Workflow Platform"
            version = $Manifest.SchemaVersion
        }
        "title" = "Provenance for $($Manifest.AssetId)"
        "format" = "application/json"
        "instance_id" = $Manifest.ManifestId
        "signature_info" = @{
            alg = "SHA256"
            issuer = "LLM Workflow Provenance Tracker"
        }
        "record_map" = @{}
    }
    
    foreach ($record in $Manifest.Chain) {
        $c2pa.record_map[$record.ProvenanceId] = @{
            "@type" = "c2pa.record"
            "recordType" = $record.Operation
            "description" = "Asset $($record.AssetId) processed via $($record.Operation) in $($record.PackId)"
            "softwareAgent" = @{
                name = $record.PackId
                version = $record.Metadata.OperationVersion
            }
            "when" = $record.Timestamp
            "documentID" = $record.AssetId
            "instanceID" = $record.ProvenanceId
        }
    }
    
    return $c2pa | ConvertTo-Json -Depth 10
}

function Compress-String {
    param([string]$String)
    
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($String)
    $memoryStream = [System.IO.MemoryStream]::new()
    $gzipStream = [System.IO.Compression.GZipStream]::new($memoryStream, [System.IO.Compression.CompressionMode]::Compress)
    $gzipStream.Write($bytes, 0, $bytes.Length)
    $gzipStream.Close()
    $compressed = $memoryStream.ToArray()
    return [Convert]::ToBase64String($compressed)
}

#endregion

#region Exports

Export-ModuleMember -Function @(
    'New-ProvenanceRecord',
    'Add-ProvenanceChain',
    'Get-ProvenanceHistory',
    'Export-ProvenanceManifest',
    'Validate-ProvenanceIntegrity'
)

#endregion
