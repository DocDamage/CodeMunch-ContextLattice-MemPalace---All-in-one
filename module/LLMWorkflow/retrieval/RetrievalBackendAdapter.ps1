# Retrieval Backend Adapter
# Workstream 7: Retrieval Substrate and MCP Governance
# Abstracts Qdrant (HTTP REST) and LanceDB (file-based) retrieval backends.

Set-StrictMode -Version Latest

#===============================================================================
# Script-level Variables
#===============================================================================

$script:RetrievalAdapters = [hashtable]::Synchronized(@{})

#===============================================================================
# Adapter Factory
#===============================================================================

function New-RetrievalBackendAdapter {
    <#
    .SYNOPSIS
        Creates a retrieval backend adapter for Qdrant or LanceDB.

    .DESCRIPTION
        Initializes an adapter object that provides a unified surface for
        vector search, document indexing, and connection testing. Supports
        Qdrant via HTTP REST mocks and LanceDB via file-based mocks.

    .PARAMETER Backend
        The backend type: 'qdrant' or 'lancedb'.

    .PARAMETER Collection
        Collection name (Qdrant) or table name (LanceDB).

    .PARAMETER BaseUrl
        Qdrant base URL. Default: http://localhost:6333.

    .PARAMETER ApiKey
        Optional Qdrant API key.

    .PARAMETER DataPath
        LanceDB data directory path.

    .OUTPUTS
        System.Management.Automation.PSCustomObject representing the adapter.

    .EXAMPLE
        $adapter = New-RetrievalBackendAdapter -Backend "qdrant" -Collection "my-pack"
        $adapter = New-RetrievalBackendAdapter -Backend "lancedb" -Collection "my-pack" -DataPath "./lancedb"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('qdrant', 'lancedb')]
        [string]$Backend,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Collection,

        [Parameter()]
        [string]$BaseUrl = "http://localhost:6333",

        [Parameter()]
        [string]$ApiKey = "",

        [Parameter()]
        [string]$DataPath = ""
    )

    process {
        if ($Backend -eq 'lancedb' -and [string]::IsNullOrEmpty($DataPath)) {
            $DataPath = Join-Path $PWD "lancedb-data"
        }

        $adapterId = [Guid]::NewGuid().ToString('N')

        $adapter = [ordered]@{
            adapterId = $adapterId
            backend = $Backend
            collection = $Collection
            baseUrl = $BaseUrl.TrimEnd('/')
            apiKey = $ApiKey
            dataPath = $DataPath
            createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        }

        $adapterObject = [pscustomobject]$adapter
        $script:RetrievalAdapters[$adapterId] = $adapterObject

        Write-Verbose "[RetrievalBackendAdapter] Created $Backend adapter '$adapterId' for collection '$Collection'"
        return $adapterObject
    }
}

#===============================================================================
# Document Operations
#===============================================================================

function Add-RetrievalDocument {
    <#
    .SYNOPSIS
        Indexes a document into the retrieval backend.

    .DESCRIPTION
        For Qdrant, sends an HTTP upsert request to the collection points
        endpoint. For LanceDB, appends the document to a local JSON mock
        table on disk.

    .PARAMETER Adapter
        Adapter object created by New-RetrievalBackendAdapter.

    .PARAMETER DocumentId
        Unique document identifier.

    .PARAMETER Vector
        Array of float values representing the embedding.

    .PARAMETER Payload
        Hashtable of metadata/payload fields.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with operation result.

    .EXAMPLE
        Add-RetrievalDocument -Adapter $adapter -DocumentId "doc-1" `
            -Vector @(0.1, 0.2, 0.3) -Payload @{ packId = "test"; text = "hello" }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Adapter,

        [Parameter(Mandatory = $true)]
        [string]$DocumentId,

        [Parameter(Mandatory = $true)]
        [double[]]$Vector,

        [Parameter()]
        [hashtable]$Payload = @{}
    )

    process {
        if (-not $Adapter -or -not $Adapter.adapterId) {
            throw "Invalid adapter object."
        }

        $result = [ordered]@{
            Success = $false
            DocumentId = $DocumentId
            Backend = $Adapter.backend
            Error = $null
        }

        try {
            switch ($Adapter.backend) {
                'qdrant' {
                    $body = @{
                        points = @(
                            @{
                                id = $DocumentId
                                vector = $Vector
                                payload = $Payload
                            }
                        )
                    } | ConvertTo-Json -Depth 10

                    $headers = @{ 'Content-Type' = 'application/json' }
                    if ($Adapter.apiKey) {
                        $headers['api-key'] = $Adapter.apiKey
                    }

                    $url = "$($Adapter.baseUrl)/collections/$($Adapter.collection)/points?wait=true"

                    # Mock implementation: simulate success without network
                    $result.Success = $true
                    $result['mockResponse'] = @{
                        status = 'ok'
                        operation = 'upsert'
                        url = $url
                        bodyLength = $body.Length
                    }
                }
                'lancedb' {
                    $tableDir = Join-Path $Adapter.dataPath $Adapter.collection
                    if (-not (Test-Path -LiteralPath $tableDir)) {
                        $null = New-Item -ItemType Directory -Path $tableDir -Force
                    }

                    $tableFile = Join-Path $tableDir "documents.json"
                    $documents = @()
                    if (Test-Path -LiteralPath $tableFile) {
                        $documents = Get-Content -LiteralPath $tableFile -Raw | ConvertFrom-Json
                        if ($documents -isnot [array]) {
                            $documents = @($documents)
                        }
                    }

                    # Remove existing document with same ID
                    $documents = @($documents | Where-Object { $_.id -ne $DocumentId })

                    $doc = [ordered]@{
                        id = $DocumentId
                        vector = @($Vector)
                        payload = $Payload
                        updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
                    }

                    $documents += [pscustomobject]$doc
                    $documents | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tableFile -Encoding UTF8

                    $result.Success = $true
                    $result['TableFile'] = $tableFile
                }
                default {
                    throw "Unsupported backend: $($Adapter.backend)"
                }
            }
        }
        catch {
            $result.Error = $_.Exception.Message
            Write-Warning "[RetrievalBackendAdapter] Failed to add document '$DocumentId': $_"
        }

        return [pscustomobject]$result
    }
}

function Remove-RetrievalDocument {
    <#
    .SYNOPSIS
        Removes a document from the retrieval backend.

    .PARAMETER Adapter
        Adapter object created by New-RetrievalBackendAdapter.

    .PARAMETER DocumentId
        Unique document identifier to remove.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with operation result.

    .EXAMPLE
        Remove-RetrievalDocument -Adapter $adapter -DocumentId "doc-1"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Adapter,

        [Parameter(Mandatory = $true)]
        [string]$DocumentId
    )

    process {
        if (-not $Adapter -or -not $Adapter.adapterId) {
            throw "Invalid adapter object."
        }

        $result = [ordered]@{
            Success = $false
            DocumentId = $DocumentId
            Backend = $Adapter.backend
            Error = $null
        }

        try {
            switch ($Adapter.backend) {
                'qdrant' {
                    $body = @{
                        points = @($DocumentId)
                    } | ConvertTo-Json -Depth 10

                    $headers = @{ 'Content-Type' = 'application/json' }
                    if ($Adapter.apiKey) {
                        $headers['api-key'] = $Adapter.apiKey
                    }

                    $url = "$($Adapter.baseUrl)/collections/$($Adapter.collection)/points/delete?wait=true"

                    # Mock implementation
                    $result.Success = $true
                    $result['mockResponse'] = @{
                        status = 'ok'
                        operation = 'delete'
                        url = $url
                    }
                }
                'lancedb' {
                    $tableDir = Join-Path $Adapter.dataPath $Adapter.collection
                    $tableFile = Join-Path $tableDir "documents.json"

                    if (Test-Path -LiteralPath $tableFile) {
                        $documents = Get-Content -LiteralPath $tableFile -Raw | ConvertFrom-Json
                        if ($documents -isnot [array]) {
                            $documents = @($documents)
                        }

                        $beforeCount = $documents.Count
                        $documents = @($documents | Where-Object { $_.id -ne $DocumentId })
                        $afterCount = $documents.Count

                        if ($documents.Count -eq 0) {
                            Remove-Item -LiteralPath $tableFile -Force
                        }
                        else {
                            $documents | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tableFile -Encoding UTF8
                        }

                        $result.Success = $true
                        $result['Removed'] = ($beforeCount - $afterCount) -gt 0
                    }
                    else {
                        $result.Success = $true
                        $result['Removed'] = $false
                    }
                }
                default {
                    throw "Unsupported backend: $($Adapter.backend)"
                }
            }
        }
        catch {
            $result.Error = $_.Exception.Message
            Write-Warning "[RetrievalBackendAdapter] Failed to remove document '$DocumentId': $_"
        }

        return [pscustomobject]$result
    }
}

function Search-RetrievalBackend {
    <#
    .SYNOPSIS
        Performs a vector search with optional payload filters.

    .DESCRIPTION
        For Qdrant, constructs a mock HTTP search request. For LanceDB,
        performs an in-memory cosine similarity search over the local
        mock table and applies payload filters.

    .PARAMETER Adapter
        Adapter object created by New-RetrievalBackendAdapter.

    .PARAMETER Vector
        Query embedding vector.

    .PARAMETER Filter
        Optional hashtable of payload filters (exact match only in mock).

    .PARAMETER Limit
        Maximum number of results. Default: 10.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with search results.

    .EXAMPLE
        Search-RetrievalBackend -Adapter $adapter -Vector @(0.1, 0.2, 0.3) `
            -Filter @{ packId = "test" } -Limit 5
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Adapter,

        [Parameter(Mandatory = $true)]
        [double[]]$Vector,

        [Parameter()]
        [hashtable]$Filter = @{},

        [Parameter()]
        [int]$Limit = 10
    )

    process {
        if (-not $Adapter -or -not $Adapter.adapterId) {
            throw "Invalid adapter object."
        }

        $result = [ordered]@{
            Success = $false
            Backend = $Adapter.backend
            Results = @()
            Error = $null
        }

        try {
            switch ($Adapter.backend) {
                'qdrant' {
                    $body = @{
                        vector = $Vector
                        limit = $Limit
                        with_payload = $true
                        with_vector = $false
                    }

                    if ($Filter -and $Filter.Count -gt 0) {
                        $body['filter'] = Convert-FilterToQdrant -Filter $Filter
                    }

                    $jsonBody = $body | ConvertTo-Json -Depth 10
                    $headers = @{ 'Content-Type' = 'application/json' }
                    if ($Adapter.apiKey) {
                        $headers['api-key'] = $Adapter.apiKey
                    }

                    $url = "$($Adapter.baseUrl)/collections/$($Adapter.collection)/points/search"

                    # Mock implementation: return empty but valid result structure
                    $result.Success = $true
                    $result['mockResponse'] = @{
                        status = 'ok'
                        operation = 'search'
                        url = $url
                        bodyLength = $jsonBody.Length
                    }
                    $result.Results = @()
                }
                'lancedb' {
                    $tableDir = Join-Path $Adapter.dataPath $Adapter.collection
                    $tableFile = Join-Path $tableDir "documents.json"

                    $documents = @()
                    if (Test-Path -LiteralPath $tableFile) {
                        $raw = Get-Content -LiteralPath $tableFile -Raw | ConvertFrom-Json
                        if ($raw -is [array]) {
                            $documents = $raw
                        }
                        else {
                            $documents = @($raw)
                        }
                    }

                    # Apply payload filters
                    $filtered = $documents
                    if ($Filter -and $Filter.Count -gt 0) {
                        foreach ($key in $Filter.Keys) {
                            $expected = $Filter[$key]
                            $filtered = @($filtered | Where-Object {
                                $payload = $_.payload
                                if ($payload -is [pscustomobject]) {
                                    $payload.$key -eq $expected
                                }
                                elseif ($payload -is [hashtable] -or $payload -is [System.Collections.IDictionary]) {
                                    $payload[$key] -eq $expected
                                }
                                else {
                                    $false
                                }
                            })
                        }
                    }

                    # Compute cosine similarity
                    $scored = [System.Collections.Generic.List[object]]::new()
                    $queryVector = @($Vector)
                    foreach ($doc in $filtered) {
                        $docVector = $doc.vector
                        $score = Get-CosineSimilarity -VectorA $queryVector -VectorB $docVector
                        $scored.Add([pscustomobject]@{
                            id = $doc.id
                            score = $score
                            payload = $doc.payload
                        })
                    }

                    $sorted = $scored | Sort-Object -Property score -Descending | Select-Object -First $Limit
                    $result.Success = $true
                    $result.Results = @($sorted)
                }
                default {
                    throw "Unsupported backend: $($Adapter.backend)"
                }
            }
        }
        catch {
            $result.Error = $_.Exception.Message
            Write-Warning "[RetrievalBackendAdapter] Search failed: $_"
        }

        return [pscustomobject]$result
    }
}

function Test-RetrievalBackendConnection {
    <#
    .SYNOPSIS
        Tests connectivity to the retrieval backend.

    .DESCRIPTION
        For Qdrant, performs a mock health check against the base URL.
        For LanceDB, verifies that the data path is writable.

    .PARAMETER Adapter
        Adapter object created by New-RetrievalBackendAdapter.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with connection status.

    .EXAMPLE
        Test-RetrievalBackendConnection -Adapter $adapter
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Adapter
    )

    process {
        if (-not $Adapter -or -not $Adapter.adapterId) {
            throw "Invalid adapter object."
        }

        $result = [ordered]@{
            Success = $false
            Backend = $Adapter.backend
            Reachable = $false
            Error = $null
        }

        try {
            switch ($Adapter.backend) {
                'qdrant' {
                    # Mock health check
                    $result.Success = $true
                    $result.Reachable = $true
                    $result['MockHealthCheck'] = @{
                        url = "$($Adapter.baseUrl)/healthz"
                        status = 'ok'
                    }
                }
                'lancedb' {
                    if (-not (Test-Path -LiteralPath $Adapter.dataPath)) {
                        $null = New-Item -ItemType Directory -Path $Adapter.dataPath -Force
                    }

                    $testFile = Join-Path $Adapter.dataPath ".connection-test"
                    'test' | Set-Content -LiteralPath $testFile -Encoding UTF8
                    Remove-Item -LiteralPath $testFile -Force

                    $result.Success = $true
                    $result.Reachable = $true
                }
                default {
                    throw "Unsupported backend: $($Adapter.backend)"
                }
            }
        }
        catch {
            $result.Error = $_.Exception.Message
            Write-Warning "[RetrievalBackendAdapter] Connection test failed: $_"
        }

        return [pscustomobject]$result
    }
}

#===============================================================================
# Internal Helpers
#===============================================================================

function Convert-FilterToQdrant {
    <#
    .SYNOPSIS
        Converts a simple hashtable filter to a Qdrant-like JSON filter structure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Filter
    )

    $conditions = @()
    foreach ($key in $Filter.Keys) {
        $conditions += @{
            key = $key
            match = @{
                value = $Filter[$key]
            }
        }
    }

    if ($conditions.Count -eq 1) {
        return @{
            must = $conditions
        }
    }

    return @{
        must = $conditions
    }
}

function Get-CosineSimilarity {
    <#
    .SYNOPSIS
        Computes cosine similarity between two vectors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [double[]]$VectorA,

        [Parameter(Mandatory = $true)]
        [double[]]$VectorB
    )

    if ($VectorA.Count -ne $VectorB.Count) {
        return 0.0
    }

    $dot = 0.0
    $normA = 0.0
    $normB = 0.0

    for ($i = 0; $i -lt $VectorA.Count; $i++) {
        $a = $VectorA[$i]
        $b = $VectorB[$i]
        $dot += $a * $b
        $normA += $a * $a
        $normB += $b * $b
    }

    if ($normA -eq 0.0 -or $normB -eq 0.0) {
        return 0.0
    }

    return $dot / [Math]::Sqrt($normA * $normB)
}

#===============================================================================
# Export Module Members
#===============================================================================

if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'New-RetrievalBackendAdapter',
        'Search-RetrievalBackend',
        'Add-RetrievalDocument',
        'Remove-RetrievalDocument',
        'Test-RetrievalBackendConnection'
    )
}
