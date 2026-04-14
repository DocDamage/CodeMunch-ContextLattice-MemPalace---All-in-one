#requires -Version 5.1
<#
.SYNOPSIS
    Vector store integration extractor for LLM Workflow Structured Extraction Pipeline.

.DESCRIPTION
    Parses vector store and embedding-related source files to extract structured metadata:
    - Vector database operations (CRUD, indexing, querying)
    - Embedding workflows (generation, normalization, batching)
    - Retrieval patterns (similarity search, hybrid search, filtering)
    - RAG implementation patterns (context assembly, chunking, ranking)
    
    Supports extraction from configuration files, client code, and integration
    patterns for ChromaDB, Pinecone, Weaviate, and other vector stores.

.NOTES
    File Name      : VectorStoreExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Pack Support   : agent-simulation
#>

Set-StrictMode -Version Latest

# ============================================================================
# Script-level Constants and Patterns
# ============================================================================

# Vector store operation patterns
$script:VectorPatterns = @{
    # Vector DB operations
    CollectionCreate = '(?:createCollection|createIndex|create_collection|create_index)'
    CollectionDelete = '(?:deleteCollection|deleteIndex|delete_collection|delete_index)'
    DocumentAdd = '(?:add|upsert|insert|addDocuments|add_documents)'
    DocumentUpdate = '(?:update|modify|update_document)'
    DocumentDelete = '(?:delete|remove|deleteDocuments|delete_documents)'
    
    # Query operations
    SimilaritySearch = '(?:similaritySearch|query|search|similarity_search)'
    VectorQuery = '(?:query_by_vector|vectorSearch|vector_search)'
    HybridSearch = '(?:hybridSearch|hybrid_search|search_hybrid)'
    MetadataFilter = '(?:where|filter|metadata_filter|where_document)'
    
    # Embedding operations
    EmbeddingCreate = '(?:embed|createEmbedding|embedDocuments|embed_documents)'
    EmbeddingModel = '(?:embedding|embeddings|embeddingFunction|embedding_function)'
    BatchEmbedding = '(?:batch|batchEmbed|batch_embed)'
    
    # RAG patterns
    RAGPipeline = '(?:RAG|RetrievalQA|ConversationalRetrievalChain)'
    ContextAssembly = '(?:context|assembleContext|combineDocuments|combine_documents)'
    ChunkingStrategy = '(?:chunk|split|textSplitter|RecursiveCharacterTextSplitter)'
    Reranking = '(?:rerank|reranking|reRank|scoreRerank)'
}

# Vector store configuration schemas
$script:ConfigSchemas = @{
    ChromaDB = @{
        host = 'string'
        port = 'number'
        collection = 'string'
        embeddingFunction = 'string'
        distanceFunction = 'string'
    }
    Pinecone = @{
        apiKey = 'string'
        environment = 'string'
        indexName = 'string'
        projectName = 'string'
        namespace = 'string'
    }
    Weaviate = @{
        host = 'string'
        scheme = 'string'
        apiKey = 'string'
        className = 'string'
        batchSize = 'number'
    }
}

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Creates a structured vector store element object.
.DESCRIPTION
    Factory function to create standardized vector store element objects.
.PARAMETER ElementType
    The type of element (vectorOperation, embedding, retrieval, rag, config).
.PARAMETER Name
    The name of the element.
.PARAMETER OperationType
    The specific operation subtype.
.PARAMETER LineNumber
    The line number where the element is defined.
.PARAMETER Properties
    Hashtable of element properties.
.PARAMETER CodeSnippet
    Associated code snippet.
.PARAMETER SourceFile
    Path to the source file.
.OUTPUTS
    System.Collections.Hashtable. Structured element object.
#>
function New-VectorStoreElement {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('vectorOperation', 'embedding', 'retrieval', 'rag', 'config')]
        [string]$ElementType,
        
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter()]
        [string]$OperationType = '',
        
        [Parameter()]
        [int]$LineNumber = 0,
        
        [Parameter()]
        [hashtable]$Properties = @{},
        
        [Parameter()]
        [string]$CodeSnippet = '',
        
        [Parameter()]
        [string]$SourceFile = ''
    )
    
    return @{
        elementType = $ElementType
        name = $Name
        operationType = $OperationType
        lineNumber = $LineNumber
        properties = $Properties
        codeSnippet = $CodeSnippet
        sourceFile = $SourceFile
        extractedAt = [DateTime]::UtcNow.ToString("o")
    }
}

<#
.SYNOPSIS
    Detects the vector store type from content.
.DESCRIPTION
    Analyzes import statements and class usage to identify which
    vector store implementation is being used.
.PARAMETER Content
    The source content to analyze.
.OUTPUTS
    System.String. Vector store identifier (chromadb, pinecone, weaviate, unknown).
#>
function Get-VectorStoreType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    # Check for ChromaDB
    if ($Content -match 'chromadb|Chroma|ChromaDB|chroma\s+import') {
        return 'chromadb'
    }
    
    # Check for Pinecone
    if ($Content -match 'pinecone|Pinecone|pinecone-client') {
        return 'pinecone'
    }
    
    # Check for Weaviate
    if ($Content -match 'weaviate|WeaviateClient|weaviate-client') {
        return 'weaviate'
    }
    
    # Check for other vector stores
    if ($Content -match 'faiss|FAISS') { return 'faiss' }
    if ($Content -match 'milvus|Milvus') { return 'milvus' }
    if ($Content -match 'qdrant|Qdrant') { return 'qdrant' }
    
    return 'unknown'
}

<#
.SYNOPSIS
    Parses embedding configuration parameters.
.DESCRIPTION
    Extracts embedding model configuration from source content.
.PARAMETER Content
    The source content.
.PARAMETER LineNumber
    Starting line number for context.
.OUTPUTS
    System.Collections.Hashtable. Embedding configuration object.
#>
function Get-EmbeddingConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter()]
        [int]$LineNumber = 0
    )
    
    $config = @{
        modelName = ''
        modelProvider = ''
        dimensions = 0
        batchSize = 0
        normalize = $false
    }
    
    # Detect model name
    if ($Content -match "(?:model|model_name)\s*[=:]\s*[`"''']?(?<model>[^`"''',}\s]+)") {
        $config.modelName = $matches['model']
    }
    
    # Detect provider
    if ($Content -match 'OpenAIEmbeddings|openai') { $config.modelProvider = 'openai' }
    elseif ($Content -match 'HuggingFaceEmbeddings|huggingface') { $config.modelProvider = 'huggingface' }
    elseif ($Content -match 'CohereEmbeddings|cohere') { $config.modelProvider = 'cohere' }
    elseif ($Content -match 'OllamaEmbeddings|ollama') { $config.modelProvider = 'ollama' }
    
    # Detect dimensions
    if ($Content -match '(?:dimensions?|dimension|vector_size)\s*[=:]\s*(?<dims>\d+)') {
        $config.dimensions = [int]$matches['dims']
    }
    
    # Detect batch size
    if ($Content -match '(?:batchSize|batch_size|batch)\s*[=:]\s*(?<batch>\d+)') {
        $config.batchSize = [int]$matches['batch']
    }
    
    # Detect normalization
    if ($Content -match 'normalize\s*[=:]\s*(?:True|true|1)') {
        $config.normalize = $true
    }
    
    return $config
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Extracts vector database operations from source content.

.DESCRIPTION
    Parses source code to identify vector database CRUD operations,
    collection management, and indexing patterns.

.PARAMETER Content
    The source content to parse.

.PARAMETER VectorStoreType
    The type of vector store (optional, auto-detected if not provided).

.OUTPUTS
    System.Array. Array of vector DB operation objects.

.EXAMPLE
    $operations = Get-VectorDBOperations -Content $pythonContent

.EXAMPLE
    $operations = Get-VectorDBOperations -Content $pythonContent -VectorStoreType 'chromadb'
#>
function Get-VectorDBOperations {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$VectorStoreType = ''
    )
    
    process {
        $operations = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        # Auto-detect if not provided
        if ([string]::IsNullOrEmpty($VectorStoreType)) {
            $VectorStoreType = Get-VectorStoreType -Content $Content
        }
        
        foreach ($line in $lines) {
            $lineNumber++
            $lineTrimmed = $line.Trim()
            
            # Collection creation
            if ($line -match $script:VectorPatterns.CollectionCreate) {
                $operations += @{
                    name = 'CreateCollection'
                    operationType = 'collectionCreate'
                    vectorStore = $VectorStoreType
                    lineNumber = $lineNumber
                    properties = @{
                        operation = 'create'
                        target = 'collection/index'
                    }
                    codeSnippet = $lineTrimmed
                }
            }
            
            # Collection deletion
            if ($line -match $script:VectorPatterns.CollectionDelete) {
                $operations += @{
                    name = 'DeleteCollection'
                    operationType = 'collectionDelete'
                    vectorStore = $VectorStoreType
                    lineNumber = $lineNumber
                    properties = @{
                        operation = 'delete'
                        target = 'collection/index'
                    }
                    codeSnippet = $lineTrimmed
                }
            }
            
            # Document add/upsert
            if ($line -match $script:VectorPatterns.DocumentAdd) {
                $operations += @{
                    name = 'AddDocuments'
                    operationType = 'documentAdd'
                    vectorStore = $VectorStoreType
                    lineNumber = $lineNumber
                    properties = @{
                        operation = 'add'
                        target = 'documents'
                    }
                    codeSnippet = $lineTrimmed
                }
            }
            
            # Document update
            if ($line -match $script:VectorPatterns.DocumentUpdate) {
                $operations += @{
                    name = 'UpdateDocuments'
                    operationType = 'documentUpdate'
                    vectorStore = $VectorStoreType
                    lineNumber = $lineNumber
                    properties = @{
                        operation = 'update'
                        target = 'documents'
                    }
                    codeSnippet = $lineTrimmed
                }
            }
            
            # Document delete
            if ($line -match $script:VectorPatterns.DocumentDelete) {
                $operations += @{
                    name = 'DeleteDocuments'
                    operationType = 'documentDelete'
                    vectorStore = $VectorStoreType
                    lineNumber = $lineNumber
                    properties = @{
                        operation = 'delete'
                        target = 'documents'
                    }
                    codeSnippet = $lineTrimmed
                }
            }
        }
        
        Write-Verbose "[Get-VectorDBOperations] Found $($operations.Count) vector DB operations"
        return ,$operations
    }
}

<#
.SYNOPSIS
    Extracts embedding workflow patterns from source content.

.DESCRIPTION
    Parses source code to identify embedding generation workflows,
    model configurations, and batching strategies.

.PARAMETER Content
    The source content to parse.

.OUTPUTS
    System.Array. Array of embedding workflow objects.

.EXAMPLE
    $workflows = Get-EmbeddingWorkflows -Content $pythonContent
#>
function Get-EmbeddingWorkflows {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        $workflows = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        $inEmbeddingBlock = $false
        $blockStartLine = 0
        $blockContent = @()
        
        foreach ($line in $lines) {
            $lineNumber++
            $lineTrimmed = $line.Trim()
            
            # Detect embedding model instantiation
            if ($line -match $script:VectorPatterns.EmbeddingModel -or
                $line -match 'OpenAIEmbeddings|HuggingFaceEmbeddings|CohereEmbeddings') {
                
                if (-not $inEmbeddingBlock) {
                    $inEmbeddingBlock = $true
                    $blockStartLine = $lineNumber
                    $blockContent = @($lineTrimmed)
                } else {
                    $blockContent += $lineTrimmed
                }
            }
            # Continue capturing embedding block
            elseif ($inEmbeddingBlock) {
                if ($line -match '^\s*\)' -or $line -match '^\s*\}\s*$') {
                    # End of block
                    $blockContent += $lineTrimmed
                    
                    $config = Get-EmbeddingConfig -Content ($blockContent -join "`n")
                    
                    $workflows += @{
                        name = 'EmbeddingWorkflow'
                        operationType = 'embedding'
                        lineNumber = $blockStartLine
                        properties = $config
                        codeSnippet = ($blockContent -join "`n").Substring(0, [Math]::Min(200, ($blockContent -join "`n").Length))
                    }
                    
                    $inEmbeddingBlock = $false
                    $blockContent = @()
                }
                elseif ($line -match '^\s*$' -or $line -match '^\s*#') {
                    # Skip blank lines and comments within block
                    continue
                }
                else {
                    $blockContent += $lineTrimmed
                }
            }
            
            # Standalone embedding creation
            if ($line -match $script:VectorPatterns.EmbeddingCreate -and -not $inEmbeddingBlock) {
                $workflows += @{
                    name = 'CreateEmbeddings'
                    operationType = 'embeddingCreate'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'embeddingCall'
                    }
                    codeSnippet = $lineTrimmed
                }
            }
            
            # Batch embedding
            if ($line -match $script:VectorPatterns.BatchEmbedding) {
                $workflows += @{
                    name = 'BatchEmbedding'
                    operationType = 'batchEmbedding'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'batchProcessing'
                        batchEnabled = $true
                    }
                    codeSnippet = $lineTrimmed
                }
            }
        }
        
        Write-Verbose "[Get-EmbeddingWorkflows] Found $($workflows.Count) embedding workflows"
        return ,$workflows
    }
}

<#
.SYNOPSIS
    Extracts retrieval patterns from source content.

.DESCRIPTION
    Parses source code to identify similarity search, hybrid search,
    and metadata filtering patterns for vector retrieval.

.PARAMETER Content
    The source content to parse.

.PARAMETER VectorStoreType
    The type of vector store (optional, auto-detected if not provided).

.OUTPUTS
    System.Array. Array of retrieval pattern objects.

.EXAMPLE
    $patterns = Get-RetrievalPatterns -Content $pythonContent
#>
function Get-RetrievalPatterns {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$VectorStoreType = ''
    )
    
    process {
        $patterns = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        # Auto-detect if not provided
        if ([string]::IsNullOrEmpty($VectorStoreType)) {
            $VectorStoreType = Get-VectorStoreType -Content $Content
        }
        
        foreach ($line in $lines) {
            $lineNumber++
            $lineTrimmed = $line.Trim()
            
            # Similarity search
            if ($line -match $script:VectorPatterns.SimilaritySearch) {
                $patterns += @{
                    name = 'SimilaritySearch'
                    operationType = 'similaritySearch'
                    vectorStore = $VectorStoreType
                    lineNumber = $lineNumber
                    properties = @{
                        searchType = 'similarity'
                        vectorBased = $true
                    }
                    codeSnippet = $lineTrimmed
                }
            }
            
            # Vector query
            if ($line -match $script:VectorPatterns.VectorQuery) {
                $patterns += @{
                    name = 'VectorQuery'
                    operationType = 'vectorQuery'
                    vectorStore = $VectorStoreType
                    lineNumber = $lineNumber
                    properties = @{
                        searchType = 'vector'
                        vectorBased = $true
                    }
                    codeSnippet = $lineTrimmed
                }
            }
            
            # Hybrid search
            if ($line -match $script:VectorPatterns.HybridSearch) {
                $patterns += @{
                    name = 'HybridSearch'
                    operationType = 'hybridSearch'
                    vectorStore = $VectorStoreType
                    lineNumber = $lineNumber
                    properties = @{
                        searchType = 'hybrid'
                        vectorBased = $true
                        textBased = $true
                    }
                    codeSnippet = $lineTrimmed
                }
            }
            
            # Metadata filtering
            if ($line -match $script:VectorPatterns.MetadataFilter) {
                $patterns += @{
                    name = 'MetadataFilter'
                    operationType = 'metadataFilter'
                    vectorStore = $VectorStoreType
                    lineNumber = $lineNumber
                    properties = @{
                        filterType = 'metadata'
                        vectorBased = $false
                    }
                    codeSnippet = $lineTrimmed
                }
            }
        }
        
        Write-Verbose "[Get-RetrievalPatterns] Found $($patterns.Count) retrieval patterns"
        return ,$patterns
    }
}

<#
.SYNOPSIS
    Extracts RAG (Retrieval-Augmented Generation) patterns from source content.

.DESCRIPTION
    Parses source code to identify RAG pipeline implementations,
    context assembly strategies, chunking patterns, and reranking.

.PARAMETER Content
    The source content to parse.

.OUTPUTS
    System.Array. Array of RAG pattern objects.

.EXAMPLE
    $patterns = Get-RAGPatterns -Content $pythonContent
#>
function Get-RAGPatterns {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        $patterns = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            $lineTrimmed = $line.Trim()
            
            # RAG pipeline
            if ($line -match $script:VectorPatterns.RAGPipeline) {
                $patterns += @{
                    name = 'RAGPipeline'
                    operationType = 'ragPipeline'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'rag'
                        hasRetrieval = $true
                        hasGeneration = $true
                    }
                    codeSnippet = $lineTrimmed
                }
            }
            
            # Context assembly
            if ($line -match $script:VectorPatterns.ContextAssembly) {
                $patterns += @{
                    name = 'ContextAssembly'
                    operationType = 'contextAssembly'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'contextCombining'
                        hasRetrieval = $true
                    }
                    codeSnippet = $lineTrimmed
                }
            }
            
            # Chunking strategy
            if ($line -match $script:VectorPatterns.ChunkingStrategy) {
                $chunkerType = 'unknown'
                if ($line -match 'RecursiveCharacter') { $chunkerType = 'recursive' }
                elseif ($line -match 'Character') { $chunkerType = 'character' }
                elseif ($line -match 'Token') { $chunkerType = 'token' }
                elseif ($line -match 'Markdown') { $chunkerType = 'markdown' }
                
                $patterns += @{
                    name = 'ChunkingStrategy'
                    operationType = 'chunking'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'documentSplitting'
                        chunkerType = $chunkerType
                    }
                    codeSnippet = $lineTrimmed
                }
            }
            
            # Reranking
            if ($line -match $script:VectorPatterns.Reranking) {
                $patterns += @{
                    name = 'Reranking'
                    operationType = 'reranking'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'resultReranking'
                        hasRerank = $true
                    }
                    codeSnippet = $lineTrimmed
                }
            }
        }
        
        Write-Verbose "[Get-RAGPatterns] Found $($patterns.Count) RAG patterns"
        return ,$patterns
    }
}

<#
.SYNOPSIS
    Validates vector store configuration.

.DESCRIPTION
    Tests a configuration file or object to validate it contains
    valid vector store configuration parameters.

.PARAMETER Path
    Path to the configuration file.

.PARAMETER Content
    Configuration content string.

.PARAMETER ConfigObject
    Configuration hashtable object.

.PARAMETER VectorStoreType
    Expected vector store type for validation.

.OUTPUTS
    System.Collections.Hashtable. Validation result with IsValid and Errors.

.EXAMPLE
    $result = Test-VectorStoreConfig -Path "./chroma_config.yaml"

.EXAMPLE
    $result = Test-VectorStoreConfig -Content $yamlContent -VectorStoreType 'chromadb'

.EXAMPLE
    $config = @{ host = 'localhost'; port = 8000 }
    $result = Test-VectorStoreConfig -ConfigObject $config -VectorStoreType 'chromadb'
#>
function Test-VectorStoreConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Object')]
        [hashtable]$ConfigObject,
        
        [Parameter()]
        [ValidateSet('chromadb', 'pinecone', 'weaviate', 'unknown')]
        [string]$VectorStoreType = 'unknown'
    )
    
    try {
        $config = @{}
        
        # Load config based on parameter set
        switch ($PSCmdlet.ParameterSetName) {
            'Path' {
                if (-not (Test-Path -LiteralPath $Path)) {
                    return @{
                        IsValid = $false
                        Errors = @("Configuration file not found: $Path")
                        Warnings = @()
                        Config = $null
                    }
                }
                
                $fileContent = Get-Content -LiteralPath $Path -Raw
                $extension = [System.IO.Path]::GetExtension($Path).ToLower()
                
                # Simple parsing for JSON and YAML
                if ($extension -eq '.json') {
                    $config = $fileContent | ConvertFrom-Json -AsHashtable
                }
                else {
                    # Basic YAML-like parsing
                    foreach ($line in ($fileContent -split "`r?`n")) {
                        if ($line -match '^(?<key>\w+)\s*:\s*(?<value>.+)$') {
                            $config[$matches['key']] = $matches['value'].Trim()
                        }
                    }
                }
            }
            'Content' {
                # Try JSON first
                try {
                    $config = $Content | ConvertFrom-Json -AsHashtable
                }
                catch {
                    # Basic YAML-like parsing
                    foreach ($line in ($Content -split "`r?`n")) {
                        if ($line -match '^(?<key>\w+)\s*:\s*(?<value>.+)$') {
                            $config[$matches['key']] = $matches['value'].Trim()
                        }
                    }
                }
            }
            'Object' {
                $config = $ConfigObject
            }
        }
        
        # Auto-detect if unknown
        if ($VectorStoreType -eq 'unknown') {
            if ($config.ContainsKey('collection') -or $config.ContainsKey('embeddingFunction')) {
                $VectorStoreType = 'chromadb'
            }
            elseif ($config.ContainsKey('indexName') -or $config.ContainsKey('environment')) {
                $VectorStoreType = 'pinecone'
            }
            elseif ($config.ContainsKey('className') -or $config.ContainsKey('scheme')) {
                $VectorStoreType = 'weaviate'
            }
        }
        
        # Validate based on schema
        $errors = @()
        $warnings = @()
        $schema = $script:ConfigSchemas[$VectorStoreType]
        
        if ($schema) {
            foreach ($requiredField in $schema.Keys) {
                if (-not $config.ContainsKey($requiredField)) {
                    $warnings += "Missing recommended field: $requiredField"
                }
            }
        }
        
        # Common validations
        if ($config.ContainsKey('port')) {
            $portVal = 0
            if (-not [int]::TryParse($config['port'], [ref]$portVal) -or $portVal -lt 1 -or $portVal -gt 65535) {
                $errors += "Invalid port number: $($config['port'])"
            }
        }
        
        if ($config.ContainsKey('host') -and [string]::IsNullOrWhiteSpace($config['host'])) {
            $errors += "Host cannot be empty"
        }
        
        return @{
            IsValid = ($errors.Count -eq 0)
            Errors = $errors
            Warnings = $warnings
            VectorStoreType = $VectorStoreType
            Config = $config
            ValidatedAt = [DateTime]::UtcNow.ToString("o")
        }
    }
    catch {
        Write-Error "[Test-VectorStoreConfig] Validation failed: $_"
        return @{
            IsValid = $false
            Errors = @("Validation error: $_")
            Warnings = @()
            Config = $null
        }
    }
}

<#
.SYNOPSIS
    Main entry point for vector store extraction.

.DESCRIPTION
    Parses a source file and returns structured extraction of vector store
    operations, embeddings, retrieval patterns, and RAG implementations.

.PARAMETER Path
    Path to the source file to parse.

.PARAMETER Content
    Source content string (alternative to Path).

.PARAMETER IncludeRawContent
    If specified, includes the raw file content in the output.

.OUTPUTS
    System.Collections.Hashtable. Complete extraction with elements array and metadata.

.EXAMPLE
    $result = Invoke-VectorStoreExtract -Path "./vector_store.py"

.EXAMPLE
    $content = Get-Content -Raw "config.yaml"
    $result = Invoke-VectorStoreExtract -Content $content
#>
function Invoke-VectorStoreExtract {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [Alias('FilePath')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [switch]$IncludeRawContent
    )
    
    try {
        # Load content from file if path provided
        $filePath = ''
        $rawContent = ''
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Write-Verbose "[Invoke-VectorStoreExtract] Loading file: $Path"
            
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return $null
            }
            
            $filePath = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $rawContent = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
        }
        else {
            $filePath = ''
            $rawContent = $Content
        }
        
        if ([string]::IsNullOrWhiteSpace($rawContent)) {
            Write-Warning "Content is empty"
            return $null
        }
        
        Write-Verbose "[Invoke-VectorStoreExtract] Parsing vector store patterns ($($rawContent.Length) chars)"
        
        # Detect vector store type
        $vectorStoreType = Get-VectorStoreType -Content $rawContent
        
        # Build elements collection
        $elements = @()
        
        # Extract vector DB operations
        $dbOperations = Get-VectorDBOperations -Content $rawContent -VectorStoreType $vectorStoreType
        foreach ($op in $dbOperations) {
            $elements += New-VectorStoreElement `
                -ElementType 'vectorOperation' `
                -Name $op.name `
                -OperationType $op.operationType `
                -LineNumber $op.lineNumber `
                -Properties $op.properties `
                -CodeSnippet $op.codeSnippet `
                -SourceFile $filePath
        }
        
        # Extract embedding workflows
        $embeddingWorkflows = Get-EmbeddingWorkflows -Content $rawContent
        foreach ($workflow in $embeddingWorkflows) {
            $elements += New-VectorStoreElement `
                -ElementType 'embedding' `
                -Name $workflow.name `
                -OperationType $workflow.operationType `
                -LineNumber $workflow.lineNumber `
                -Properties $workflow.properties `
                -CodeSnippet $workflow.codeSnippet `
                -SourceFile $filePath
        }
        
        # Extract retrieval patterns
        $retrievalPatterns = Get-RetrievalPatterns -Content $rawContent -VectorStoreType $vectorStoreType
        foreach ($pattern in $retrievalPatterns) {
            $elements += New-VectorStoreElement `
                -ElementType 'retrieval' `
                -Name $pattern.name `
                -OperationType $pattern.operationType `
                -LineNumber $pattern.lineNumber `
                -Properties $pattern.properties `
                -CodeSnippet $pattern.codeSnippet `
                -SourceFile $filePath
        }
        
        # Extract RAG patterns
        $ragPatterns = Get-RAGPatterns -Content $rawContent
        foreach ($pattern in $ragPatterns) {
            $elements += New-VectorStoreElement `
                -ElementType 'rag' `
                -Name $pattern.name `
                -OperationType $pattern.operationType `
                -LineNumber $pattern.lineNumber `
                -Properties $pattern.properties `
                -CodeSnippet $pattern.codeSnippet `
                -SourceFile $filePath
        }
        
        # Build final result
        $result = @{
            fileType = 'vector-store'
            filePath = $filePath
            vectorStoreType = $vectorStoreType
            elements = $elements
            elementCounts = @{
                vectorOperation = ($elements | Where-Object { $_.elementType -eq 'vectorOperation' }).Count
                embedding = ($elements | Where-Object { $_.elementType -eq 'embedding' }).Count
                retrieval = ($elements | Where-Object { $_.elementType -eq 'retrieval' }).Count
                rag = ($elements | Where-Object { $_.elementType -eq 'rag' }).Count
            }
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        if ($IncludeRawContent) {
            $result.rawContent = $rawContent
        }
        
        Write-Verbose "[Invoke-VectorStoreExtract] Extraction complete: $($elements.Count) elements extracted"
        
        return $result
    }
    catch {
        Write-Error "[Invoke-VectorStoreExtract] Failed to extract vector store patterns: $_"
        return $null
    }
}
# Public functions exported via module wildcard
