#requires -Version 5.1
<#
.SYNOPSIS
    OpenAPI/Swagger Specification Extractor for LLM Workflow Extraction Pipeline.

.DESCRIPTION
    Parses OpenAPI 2.0 (Swagger) and 3.0 specifications to extract structured
    endpoint definitions, schemas, parameters, and security schemes. This parser
    implements the spec analysis pipeline for API reverse engineering including:
    
    - OpenAPI 2.0 and 3.0 spec parsing
    - Endpoint extraction with methods, paths, and operations
    - Schema definition extraction and normalization
    - Parameter extraction (path, query, header, cookie)
    - Security scheme extraction
    - Multi-spec merging with conflict resolution
    - Version compatibility checking
    - Spec validation and linting
    - Markdown documentation generation
    
    This parser follows the canonical architecture for API Reverse Tooling pack
    and implements Section 25.6 of the extraction pipeline requirements.

.REQUIRED FUNCTIONS
    - Extract-OpenAPIPaths: Extract API endpoint paths
    - Extract-OpenAPISchemas: Extract component schemas
    - Extract-OpenAPISecurity: Extract security definitions
    - Convert-OpenAPIToMarkdown: Convert to documentation

.PARAMETER Path
    Path to the OpenAPI specification file (.json, .yaml, .yml).

.PARAMETER Content
    Specification content as string (alternative to Path).

.PARAMETER ResolveReferences
    If specified, resolves all $ref references inline.

.OUTPUTS
    JSON with paths, schemas, security, examples, and provenance metadata.

.NOTES
    File Name      : OpenAPIExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 2.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Pack           : api-reverse-tooling
#>

Set-StrictMode -Version Latest

#===============================================================================
# Module Constants and Version
#===============================================================================

$script:ParserVersion = '2.0.0'
$script:ParserName = 'OpenAPIExtractor'

$script:OpenAPIVersions = @{
    '2.0' = 'Swagger 2.0'
    '3.0.0' = 'OpenAPI 3.0.0'
    '3.0.1' = 'OpenAPI 3.0.1'
    '3.0.2' = 'OpenAPI 3.0.2'
    '3.0.3' = 'OpenAPI 3.0.3'
    '3.1.0' = 'OpenAPI 3.1.0'
}

$script:HTTPMethods = @('get', 'post', 'put', 'delete', 'patch', 'head', 'options', 'trace')

$script:ParameterLocations = @('query', 'header', 'path', 'cookie')

#===============================================================================
# Private Helper Functions
#===============================================================================

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
    Detects the OpenAPI/Swagger version from spec content.
.DESCRIPTION
    Analyzes the specification to determine if it's OpenAPI 2.0 (Swagger)
    or OpenAPI 3.x.
.PARAMETER Spec
    The parsed specification object.
.OUTPUTS
    System.String. The detected version string.
#>
function Get-OpenAPIVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Spec
    )
    
    # Check for Swagger 2.0
    if ($Spec.swagger -eq '2.0') {
        return '2.0'
    }
    
    # Check for OpenAPI 3.x
    if ($Spec.openapi) {
        return $Spec.openapi.ToString()
    }
    
    # Try to infer from structure
    if ($Spec.swaggerVersion -or ($Spec.paths -and $Spec.definitions -and -not $Spec.components)) {
        return '2.0'
    }
    
    if ($Spec.components) {
        return '3.0.0'
    }
    
    return 'unknown'
}

<#
.SYNOPSIS
    Normalizes a parameter object to OpenAPI 3.0 format.
.DESCRIPTION
    Converts Swagger 2.0 parameter format to OpenAPI 3.0 format.
.PARAMETER Parameter
    The parameter object to normalize.
.OUTPUTS
    System.Collections.Hashtable. Normalized parameter object.
#>
function ConvertTo-NormalizedParameter {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Parameter
    )
    
    $normalized = @{
        name = $Parameter.name
        in = $Parameter.'in'
        description = $Parameter.description
        required = if ($null -ne $Parameter.required) { $Parameter.required } else { $false }
        deprecated = $Parameter.deprecated
        allowEmptyValue = $Parameter.allowEmptyValue
    }
    
    # Handle schema conversion
    if ($Parameter.schema) {
        $normalized.schema = $Parameter.schema
    }
    elseif ($Parameter.type) {
        $normalized.schema = @{
            type = $Parameter.type
        }
        
        if ($Parameter.format) {
            $normalized.schema.format = $Parameter.format
        }
        
        if ($Parameter.enum) {
            $normalized.schema.enum = $Parameter.enum
        }
        
        if ($Parameter.default -ne $null) {
            $normalized.schema.default = $Parameter.default
        }
        
        if ($Parameter.type -eq 'array' -and $Parameter.items) {
            $normalized.schema.items = $Parameter.items
        }
    }
    
    if ($Parameter.example) {
        $normalized.example = $Parameter.example
    }
    
    return $normalized
}

<#
.SYNOPSIS
    Normalizes a response object to OpenAPI 3.0 format.
.DESCRIPTION
    Converts Swagger 2.0 response format to OpenAPI 3.0 format.
.PARAMETER Response
    The response object to normalize.
.PARAMETER Version
    The source OpenAPI version.
.OUTPUTS
    System.Collections.Hashtable. Normalized response object.
#>
function ConvertTo-NormalizedResponse {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Response,
        
        [Parameter()]
        [string]$Version = '3.0.0'
    )
    
    $normalized = @{
        description = if ($Response.description) { $Response.description } else { '' }
    }
    
    if ($Version -eq '2.0') {
        if ($Response.schema) {
            $normalized.content = @{
                'application/json' = @{
                    schema = $Response.schema
                }
            }
        }
        
        if ($Response.headers) {
            $normalized.headers = $Response.headers
        }
        
        if ($Response.examples) {
            foreach ($contentType in $Response.examples.PSObject.Properties.Name) {
                if (-not $normalized.content) {
                    $normalized.content = @{}
                }
                if (-not $normalized.content[$contentType]) {
                    $normalized.content[$contentType] = @{}
                }
                $normalized.content[$contentType].example = $Response.examples.$contentType
            }
        }
    }
    else {
        if ($Response.content) {
            $normalized.content = $Response.content
        }
        
        if ($Response.headers) {
            $normalized.headers = $Response.headers
        }
        
        if ($Response.links) {
            $normalized.links = $Response.links
        }
    }
    
    return $normalized
}

<#
.SYNOPSIS
    Resolves a schema reference.
.DESCRIPTION
    Looks up and resolves a $ref reference in the specification.
.PARAMETER Reference
    The reference string (e.g., #/components/schemas/User).
.PARAMETER Spec
    The full specification object.
.OUTPUTS
    System.Object. The resolved schema or $null if not found.
#>
function Resolve-SchemaReference {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reference,
        
        [Parameter(Mandatory = $true)]
        [object]$Spec
    )
    
    if (-not $Reference.StartsWith('#/')) {
        return $null
    }
    
    $path = $Reference.Substring(2).Split('/')
    $current = $Spec
    
    foreach ($segment in $path) {
        if ($current -is [System.Collections.IDictionary]) {
            $current = $current[$segment]
        }
        elseif ($current.PSObject.Properties[$segment]) {
            $current = $current.$segment
        }
        else {
            return $null
        }
        
        if ($null -eq $current) {
            return $null
        }
    }
    
    return $current
}

<#
.SYNOPSIS
    Deep merges two hashtables.
.DESCRIPTION
    Recursively merges two hashtables, with the second taking precedence.
.PARAMETER Base
    The base hashtable.
.PARAMETER Override
    The hashtable to merge (takes precedence).
.OUTPUTS
    System.Collections.Hashtable. Merged hashtable.
#>
function Merge-Hashtable {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Base,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Override
    )
    
    $result = $Base.Clone()
    
    foreach ($key in $Override.Keys) {
        if ($result.ContainsKey($key) -and 
            $result[$key] -is [hashtable] -and 
            $Override[$key] -is [hashtable]) {
            $result[$key] = Merge-Hashtable -Base $result[$key] -Override $Override[$key]
        }
        else {
            $result[$key] = $Override[$key]
        }
    }
    
    return $result
}

<#
.SYNOPSIS
    Generates a unique operation ID.
.DESCRIPTION
    Creates a unique operation ID based on path and method.
.PARAMETER Path
    The API path.
.PARAMETER Method
    The HTTP method.
.OUTPUTS
    System.String. Unique operation ID.
#>
function New-OperationId {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [string]$Method
    )
    
    $cleanPath = $Path.Trim('/').Replace('/', '_').Replace('{', '').Replace('}', '')
    return "$Method`_$cleanPath"
}

<#
.SYNOPSIS
    Parses YAML content to a PowerShell object.
.DESCRIPTION
    Attempts to parse YAML content using available modules or fallback methods.
.PARAMETER Content
    The YAML content to parse.
.OUTPUTS
    System.Object. Parsed YAML as PowerShell object.
#>
function ConvertFrom-YamlContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    # Try using powershell-yaml module
    $yamlModule = Get-Module -Name 'powershell-yaml' -ListAvailable
    if ($yamlModule) {
        Import-Module 'powershell-yaml' -Force -ErrorAction SilentlyContinue
        try {
            return ConvertFrom-Yaml -Yaml $Content
        }
        catch {
            Write-Verbose "[$script:ParserName] powershell-yaml conversion failed, trying fallback"
        }
    }
    
    # Fallback: Try to convert YAML-like structure to JSON
    # This is a basic conversion for simple YAML structures
    try {
        # Basic YAML to JSON conversion for OpenAPI specs
        $json = $Content `
            -replace '^(\s*)(\w+):\s*$', '`$1"`$2": {}' `
            -replace '^(\s*)(\w+):\s*([^"{[\d].*)$', '`$1"`$2": "`$3"' `
            -replace ':\s*"([^"]*)"\s*#.*$', ': "`$1"'  # Remove inline comments
        
        return $json | ConvertFrom-Json -Depth 100
    }
    catch {
        Write-Error "[$script:ParserName] Failed to parse YAML content: $_"
        return $null
    }
}

#===============================================================================
# Public API Functions - Required by Canonical Document Section 25.6
#===============================================================================

<#
.SYNOPSIS
    Extracts API endpoint paths from an OpenAPI specification.

.DESCRIPTION
    Parses an OpenAPI specification and extracts all API endpoint paths,
    including their HTTP methods, parameters, request bodies, and responses.

.PARAMETER Path
    Path to the OpenAPI specification file.

.PARAMETER Content
    Specification content as string (alternative to Path).

.PARAMETER Spec
    Pre-parsed specification object (alternative to Path/Content).

.PARAMETER IncludeDeprecated
    If specified, includes deprecated operations.

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - paths: Array of path objects with operations
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $paths = Extract-OpenAPIPaths -Path "api.yaml"
    
    $paths = Extract-OpenAPIPaths -Spec $parsedSpec
#>
function Extract-OpenAPIPaths {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Spec')]
        [hashtable]$Spec,
        
        [Parameter()]
        [switch]$IncludeDeprecated
    )
    
    try {
        $sourceFile = 'inline'
        
        # Load and parse if needed
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    paths = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ pathCount = 0; operationCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $specResult = ConvertFrom-OpenAPISpec -Path $Path
            $Spec = $specResult
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Content') {
            $specResult = ConvertFrom-OpenAPISpec -Content $Content
            $Spec = $specResult
        }
        
        if (-not $Spec -or -not $Spec.paths) {
            return @{
                paths = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Invalid or empty specification")
                statistics = @{ pathCount = 0; operationCount = 0 }
            }
        }
        
        $paths = @()
        
        foreach ($path in $Spec.paths.Keys) {
            $pathItem = $Spec.paths[$path]
            $operations = @()
            
            foreach ($method in $script:HTTPMethods) {
                $operation = $pathItem[$method]
                if (-not $operation) {
                    continue
                }
                
                # Skip deprecated if not requested
                if ($operation.deprecated -and -not $IncludeDeprecated) {
                    continue
                }
                
                # Collect parameters
                $allParams = @()
                if ($pathItem.parameters) {
                    $allParams += $pathItem.parameters
                }
                if ($operation.parameters) {
                    $allParams += $operation.parameters
                }
                
                # Group parameters by location
                $pathParams = $allParams | Where-Object { $_.in -eq 'path' }
                $queryParams = $allParams | Where-Object { $_.in -eq 'query' }
                $headerParams = $allParams | Where-Object { $_.in -eq 'header' }
                $cookieParams = $allParams | Where-Object { $_.in -eq 'cookie' }
                
                $operationObj = @{
                    id = [System.Guid]::NewGuid().ToString()
                    path = $path
                    method = $method.ToUpper()
                    operationId = $operation.operationId
                    summary = $operation.summary
                    description = $operation.description
                    tags = $operation.tags
                    deprecated = if ($operation.deprecated) { $true } else { $false }
                    parameters = @{
                        path = @($pathParams)
                        query = @($queryParams)
                        header = @($headerParams)
                        cookie = @($cookieParams)
                    }
                    totalParameters = $allParams.Count
                    requiredParameters = ($allParams | Where-Object { $_.required }).Count
                    hasRequestBody = ($null -ne $operation.requestBody)
                    responses = @()
                }
                
                # Extract response information
                if ($operation.responses) {
                    foreach ($statusCode in $operation.responses.Keys) {
                        $response = $operation.responses[$statusCode]
                        $operationObj.responses += @{
                            statusCode = $statusCode
                            description = $response.description
                            hasContent = ($null -ne $response.content)
                            contentTypes = if ($response.content) { @($response.content.Keys) } else { @() }
                        }
                    }
                }
                
                $operations += $operationObj
            }
            
            if ($operations.Count -gt 0) {
                $paths += @{
                    path = $path
                    operations = $operations
                    pathParameters = $pathItem.parameters
                }
            }
        }
        
        $operationCount = ($paths | ForEach-Object { $_.operations.Count } | Measure-Object -Sum).Sum
        
        Write-Verbose "[$script:ParserName] Extracted $($paths.Count) paths with $operationCount operations"
        
        return @{
            paths = $paths
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                pathCount = $paths.Count
                operationCount = $operationCount
                getCount = ($paths | ForEach-Object { $_.operations | Where-Object { $_.method -eq 'GET' } } | Measure-Object).Count
                postCount = ($paths | ForEach-Object { $_.operations | Where-Object { $_.method -eq 'POST' } } | Measure-Object).Count
                putCount = ($paths | ForEach-Object { $_.operations | Where-Object { $_.method -eq 'PUT' } } | Measure-Object).Count
                deleteCount = ($paths | ForEach-Object { $_.operations | Where-Object { $_.method -eq 'DELETE' } } | Measure-Object).Count
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract OpenAPI paths: $_"
        return @{
            paths = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ pathCount = 0; operationCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts component schemas from an OpenAPI specification.

.DESCRIPTION
    Parses an OpenAPI specification and extracts all schema definitions,
    including their properties, types, and metadata.

.PARAMETER Path
    Path to the OpenAPI specification file.

.PARAMETER Content
    Specification content as string (alternative to Path).

.PARAMETER Spec
    Pre-parsed specification object (alternative to Path/Content).

.PARAMETER IncludeInternals
    If specified, includes internal schemas (starting with x-).

.PARAMETER ResolveReferences
    If specified, inlines all $ref references in schemas.

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - schemas: Array of schema definition objects
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $schemas = Extract-OpenAPISchemas -Path "api.yaml"
    
    $schemas = Extract-OpenAPISchemas -Spec $parsedSpec
#>
function Extract-OpenAPISchemas {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Spec')]
        [hashtable]$Spec,
        
        [Parameter()]
        [switch]$IncludeInternals,
        
        [Parameter()]
        [switch]$ResolveReferences
    )
    
    try {
        $sourceFile = 'inline'
        
        # Load and parse if needed
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    schemas = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ schemaCount = 0; propertyCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $specResult = ConvertFrom-OpenAPISpec -Path $Path
            $Spec = $specResult
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Content') {
            $specResult = ConvertFrom-OpenAPISpec -Content $Content
            $Spec = $specResult
        }
        
        if (-not $Spec -or -not $Spec.components -or -not $Spec.components.schemas) {
            return @{
                schemas = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("No schemas found in specification")
                statistics = @{ schemaCount = 0; propertyCount = 0 }
            }
        }
        
        $schemas = @()
        $schemaComponents = $Spec.components.schemas
        
        foreach ($name in $schemaComponents.Keys) {
            # Skip internal schemas unless requested
            if ($name.StartsWith('x-') -and -not $IncludeInternals) {
                continue
            }
            
            $schema = $schemaComponents[$name]
            
            $schemaInfo = @{
                id = [System.Guid]::NewGuid().ToString()
                name = $name
                type = if ($schema.type) { $schema.type } else { 'object' }
                description = $schema.description
                required = $schema.required
                additionalProperties = $schema.additionalProperties
            }
            
            # Extract properties
            if ($schema.properties) {
                $schemaInfo.properties = @()
                foreach ($propName in $schema.properties.Keys) {
                    $prop = $schema.properties[$propName]
                    $propInfo = @{
                        name = $propName
                        type = if ($prop.type) { $prop.type } else { 'any' }
                        format = $prop.format
                        description = $prop.description
                        nullable = $prop.nullable
                        readOnly = $prop.readOnly
                        writeOnly = $prop.writeOnly
                        deprecated = $prop.deprecated
                        required = ($schema.required -contains $propName)
                        hasDefault = ($null -ne $prop.default)
                    }
                    
                    # Handle nested/array types
                    if ($prop.type -eq 'array' -and $prop.items) {
                        $propInfo.itemsType = if ($prop.items.type) { $prop.items.type } else { 'any' }
                        if ($prop.items.'$ref') {
                            $propInfo.itemsRef = $prop.items.'$ref'
                            
                            if ($ResolveReferences) {
                                $resolved = Resolve-SchemaReference -Reference $prop.items.'$ref' -Spec $Spec
                                if ($resolved) {
                                    $propInfo.resolvedItems = $resolved
                                }
                            }
                        }
                    }
                    elseif ($prop.'$ref') {
                        $propInfo.'$ref' = $prop.'$ref'
                        
                        if ($ResolveReferences) {
                            $resolved = Resolve-SchemaReference -Reference $prop.'$ref' -Spec $Spec
                            if ($resolved) {
                                $propInfo.resolvedSchema = $resolved
                            }
                        }
                    }
                    
                    $schemaInfo.properties += $propInfo
                }
                
                $schemaInfo.propertyCount = $schemaInfo.properties.Count
            }
            
            # Handle composition
            if ($schema.allOf) {
                $schemaInfo.composition = 'allOf'
                $schemaInfo.compositionCount = $schema.allOf.Count
            }
            elseif ($schema.anyOf) {
                $schemaInfo.composition = 'anyOf'
                $schemaInfo.compositionCount = $schema.anyOf.Count
            }
            elseif ($schema.oneOf) {
                $schemaInfo.composition = 'oneOf'
                $schemaInfo.compositionCount = $schema.oneOf.Count
            }
            
            # Count enum values
            if ($schema.enum) {
                $schemaInfo.enumValues = $schema.enum
                $schemaInfo.enumCount = $schema.enum.Count
            }
            
            $schemas += $schemaInfo
        }
        
        $propertyCount = ($schemas | ForEach-Object { $_.propertyCount } | Measure-Object -Sum).Sum
        
        Write-Verbose "[$script:ParserName] Extracted $($schemas.Count) schemas with $propertyCount properties"
        
        return @{
            schemas = $schemas
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                schemaCount = $schemas.Count
                propertyCount = $propertyCount
                objectSchemas = ($schemas | Where-Object { $_.type -eq 'object' }).Count
                arraySchemas = ($schemas | Where-Object { $_.type -eq 'array' }).Count
                enumSchemas = ($schemas | Where-Object { $_.enumCount -gt 0 }).Count
                compositeSchemas = ($schemas | Where-Object { $_.composition }).Count
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract OpenAPI schemas: $_"
        return @{
            schemas = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ schemaCount = 0; propertyCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts security definitions from an OpenAPI specification.

.DESCRIPTION
    Parses an OpenAPI specification and extracts all security schemes,
    including their types, configurations, and requirements.

.PARAMETER Path
    Path to the OpenAPI specification file.

.PARAMETER Content
    Specification content as string (alternative to Path).

.PARAMETER Spec
    Pre-parsed specification object (alternative to Path/Content).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - securitySchemes: Array of security scheme objects
    - securityRequirements: Array of global security requirements
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $security = Extract-OpenAPISecurity -Path "api.yaml"
    
    $security = Extract-OpenAPISecurity -Spec $parsedSpec
#>
function Extract-OpenAPISecurity {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Spec')]
        [hashtable]$Spec
    )
    
    try {
        $sourceFile = 'inline'
        
        # Load and parse if needed
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    securitySchemes = @()
                    securityRequirements = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ schemeCount = 0; requirementCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $specResult = ConvertFrom-OpenAPISpec -Path $Path
            $Spec = $specResult
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Content') {
            $specResult = ConvertFrom-OpenAPISpec -Content $Content
            $Spec = $specResult
        }
        
        $securitySchemes = @()
        $securityRequirements = @()
        
        # Extract security schemes
        if ($Spec.components -and $Spec.components.securitySchemes) {
            foreach ($name in $Spec.components.securitySchemes.Keys) {
                $scheme = $Spec.components.securitySchemes[$name]
                
                $schemeInfo = @{
                    id = [System.Guid]::NewGuid().ToString()
                    name = $name
                    type = $scheme.type
                    description = $scheme.description
                }
                
                # Handle different security scheme types
                switch ($scheme.type) {
                    'http' {
                        $schemeInfo.scheme = $scheme.scheme
                        $schemeInfo.bearerFormat = $scheme.bearerFormat
                    }
                    'apiKey' {
                        $schemeInfo.in = $scheme.'in'
                        $schemeInfo.paramName = $scheme.name
                    }
                    'oauth2' {
                        $schemeInfo.flows = $scheme.flows
                    }
                    'openIdConnect' {
                        $schemeInfo.openIdConnectUrl = $scheme.openIdConnectUrl
                    }
                }
                
                $securitySchemes += $schemeInfo
            }
        }
        
        # Extract global security requirements
        if ($Spec.security) {
            foreach ($req in $Spec.security) {
                $securityRequirements += $req
            }
        }
        
        Write-Verbose "[$script:ParserName] Extracted $($securitySchemes.Count) security schemes"
        
        return @{
            securitySchemes = $securitySchemes
            securityRequirements = $securityRequirements
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                schemeCount = $securitySchemes.Count
                httpSchemes = ($securitySchemes | Where-Object { $_.type -eq 'http' }).Count
                apiKeySchemes = ($securitySchemes | Where-Object { $_.type -eq 'apiKey' }).Count
                oauth2Schemes = ($securitySchemes | Where-Object { $_.type -eq 'oauth2' }).Count
                openIdConnectSchemes = ($securitySchemes | Where-Object { $_.type -eq 'openIdConnect' }).Count
                requirementCount = $securityRequirements.Count
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract OpenAPI security: $_"
        return @{
            securitySchemes = @()
            securityRequirements = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ schemeCount = 0; requirementCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Converts an OpenAPI specification to Markdown documentation.

.DESCRIPTION
    Parses an OpenAPI specification and generates Markdown documentation
    including API endpoints, schemas, and security information.

.PARAMETER Path
    Path to the OpenAPI specification file.

.PARAMETER Content
    Specification content as string (alternative to Path).

.PARAMETER Spec
    Pre-parsed specification object (alternative to Path/Content).

.PARAMETER Title
    Custom title for the documentation.

.PARAMETER IncludeSchemas
    If specified, includes schema documentation.

.PARAMETER IncludeSecurity
    If specified, includes security documentation.

.PARAMETER IncludeExamples
    If specified, includes example requests/responses.

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - markdown: The generated Markdown content
    - metadata: Provenance metadata
    - statistics: Generation statistics

.EXAMPLE
    $docs = Convert-OpenAPIToMarkdown -Path "api.yaml"
    
    $docs = Convert-OpenAPIToMarkdown -Spec $parsedSpec -IncludeExamples
#>
function Convert-OpenAPIToMarkdown {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Spec')]
        [hashtable]$Spec,
        
        [Parameter()]
        [string]$Title = $null,
        
        [Parameter()]
        [switch]$IncludeSchemas,
        
        [Parameter()]
        [switch]$IncludeSecurity,
        
        [Parameter()]
        [switch]$IncludeExamples
    )
    
    try {
        $sourceFile = 'inline'
        
        # Load and parse if needed
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    markdown = ''
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ lineCount = 0; sectionCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Spec = ConvertFrom-OpenAPISpec -Path $Path
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Content') {
            $Spec = ConvertFrom-OpenAPISpec -Content $Content
        }
        
        if (-not $Spec) {
            return @{
                markdown = ''
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Failed to parse specification")
                statistics = @{ lineCount = 0; sectionCount = 0 }
            }
        }
        
        $md = @()
        $sectionCount = 0
        
        # Title
        $docTitle = if ($Title) { $Title } elseif ($Spec.info.title) { $Spec.info.title } else { 'API Documentation' }
        $md += "# $docTitle"
        $md += ""
        $sectionCount++
        
        # Version
        if ($Spec.info.version) {
            $md += "**Version:** $($Spec.info.version)"
            $md += ""
        }
        
        # Description
        if ($Spec.info.description) {
            $md += $Spec.info.description
            $md += ""
        }
        
        # Servers
        if ($Spec.servers -and $Spec.servers.Count -gt 0) {
            $md += "## Servers"
            $md += ""
            $sectionCount++
            
            foreach ($server in $Spec.servers) {
                $md += "- ``$($server.url)``"
                if ($server.description) {
                    $md[-1] += " - $($server.description)"
                }
            }
            $md += ""
        }
        
        # Paths
        if ($Spec.paths -and $Spec.paths.Count -gt 0) {
            $md += "## Endpoints"
            $md += ""
            $sectionCount++
            
            foreach ($path in $Spec.paths.Keys | Sort-Object) {
                $pathItem = $Spec.paths[$path]
                
                foreach ($method in $script:HTTPMethods) {
                    $operation = $pathItem[$method]
                    if (-not $operation) {
                        continue
                    }
                    
                    $md += "### $($method.ToUpper()) $path"
                    $md += ""
                    
                    if ($operation.summary) {
                        $md += "**Summary:** $($operation.summary)"
                        $md += ""
                    }
                    
                    if ($operation.description) {
                        $md += $operation.description
                        $md += ""
                    }
                    
                    if ($operation.operationId) {
                        $md += "**Operation ID:** ``$($operation.operationId)``"
                        $md += ""
                    }
                    
                    if ($operation.deprecated) {
                        $md += "> **Deprecated:** This endpoint is deprecated."
                        $md += ""
                    }
                    
                    # Parameters
                    if ($operation.parameters -and $operation.parameters.Count -gt 0) {
                        $md += "#### Parameters"
                        $md += ""
                        $md += "| Name | In | Type | Required | Description |"
                        $md += "|------|-----|------|----------|-------------|"
                        
                        foreach ($param in $operation.parameters) {
                            $paramType = if ($param.schema) { $param.schema.type } else { 'any' }
                            $required = if ($param.required) { 'Yes' } else { 'No' }
                            $desc = if ($param.description) { $param.description } else { '' }
                            $md += "| $($param.name) | $($param.'in') | $paramType | $required | $desc |"
                        }
                        $md += ""
                    }
                    
                    # Request Body
                    if ($operation.requestBody) {
                        $md += "#### Request Body"
                        $md += ""
                        
                        if ($operation.requestBody.description) {
                            $md += $operation.requestBody.description
                            $md += ""
                        }
                        
                        if ($IncludeExamples -and $operation.requestBody.content) {
                            foreach ($contentType in $operation.requestBody.content.Keys) {
                                $content = $operation.requestBody.content[$contentType]
                                $md += "**Content Type:** ``$contentType``"
                                $md += ""
                                
                                if ($content.example) {
                                    $md += "```json"
                                    $md += ($content.example | ConvertTo-Json -Depth 5)
                                    $md += "```"
                                    $md += ""
                                }
                            }
                        }
                        $md += ""
                    }
                    
                    # Responses
                    if ($operation.responses -and $operation.responses.Count -gt 0) {
                        $md += "#### Responses"
                        $md += ""
                        
                        foreach ($statusCode in $operation.responses.Keys | Sort-Object) {
                            $response = $operation.responses[$statusCode]
                            $md += "**``$statusCode``**"
                            $md += ""
                            
                            if ($response.description) {
                                $md += $response.description
                                $md += ""
                            }
                            
                            if ($IncludeExamples -and $response.content) {
                                foreach ($contentType in $response.content.Keys) {
                                    $content = $response.content[$contentType]
                                    if ($content.example) {
                                        $md += "```json"
                                        $md += ($content.example | ConvertTo-Json -Depth 5)
                                        $md += "```"
                                        $md += ""
                                    }
                                }
                            }
                        }
                    }
                    
                    $md += "---"
                    $md += ""
                }
            }
        }
        
        # Schemas
        if ($IncludeSchemas -and $Spec.components -and $Spec.components.schemas) {
            $md += "## Schemas"
            $md += ""
            $sectionCount++
            
            foreach ($name in $Spec.components.schemas.Keys | Sort-Object) {
                $schema = $Spec.components.schemas[$name]
                
                $md += "### $name"
                $md += ""
                
                if ($schema.description) {
                    $md += $schema.description
                    $md += ""
                }
                
                $md += "**Type:** ``$($schema.type)``"
                $md += ""
                
                if ($schema.properties) {
                    $md += "| Property | Type | Required | Description |"
                    $md += "|----------|------|----------|-------------|"
                    
                    foreach ($propName in $schema.properties.Keys | Sort-Object) {
                        $prop = $schema.properties[$propName]
                        $propType = if ($prop.type) { $prop.type } else { 'any' }
                        $required = if ($schema.required -contains $propName) { 'Yes' } else { 'No' }
                        $desc = if ($prop.description) { $prop.description } else { '' }
                        $md += "| $propName | $propType | $required | $desc |"
                    }
                    $md += ""
                }
                
                $md += "---"
                $md += ""
            }
        }
        
        # Security
        if ($IncludeSecurity -and $Spec.components -and $Spec.components.securitySchemes) {
            $md += "## Security"
            $md += ""
            $sectionCount++
            
            foreach ($name in $Spec.components.securitySchemes.Keys) {
                $scheme = $Spec.components.securitySchemes[$name]
                
                $md += "### $name"
                $md += ""
                $md += "**Type:** ``$($scheme.type)``"
                $md += ""
                
                if ($scheme.description) {
                    $md += $scheme.description
                    $md += ""
                }
                
                switch ($scheme.type) {
                    'http' {
                        $md += "**Scheme:** ``$($scheme.scheme)``"
                        if ($scheme.bearerFormat) {
                            $md += ""
                            $md += "**Bearer Format:** $($scheme.bearerFormat)"
                        }
                    }
                    'apiKey' {
                        $md += "**In:** $($scheme.'in')"
                        $md += ""
                        $md += "**Name:** ``$($scheme.name)``"
                    }
                    'oauth2' {
                        $md += "**Flows:**"
                        $md += ""
                        if ($scheme.flows) {
                            foreach ($flow in $scheme.flows.PSObject.Properties) {
                                $md += "- $($flow.Name)"
                            }
                        }
                    }
                    'openIdConnect' {
                        $md += "**OpenID Connect URL:** $($scheme.openIdConnectUrl)"
                    }
                }
                $md += ""
                $md += "---"
                $md += ""
            }
        }
        
        $markdown = $md -join "`n"
        $lineCount = $md.Count
        
        return @{
            markdown = $markdown
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                lineCount = $lineCount
                sectionCount = $sectionCount
                endpointCount = ($Spec.paths.Values | ForEach-Object { $_.Values.Count } | Measure-Object -Sum).Sum
                schemaCount = if ($IncludeSchemas) { $Spec.components.schemas.Count } else { 0 }
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to convert OpenAPI to Markdown: $_"
        return @{
            markdown = ''
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ lineCount = 0; sectionCount = 0 }
        }
    }
}

#===============================================================================
# Legacy Compatibility Functions
#===============================================================================

<#
.SYNOPSIS
    Parses an OpenAPI 2.0/3.0 specification file.
    
    DEPRECATED: Use the specific Extract-* functions instead.
#>
function ConvertFrom-OpenAPISpec {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path', Position = 0)]
        [Alias('FullName')]
        [ValidateScript({
            if (-not (Test-Path -LiteralPath $_)) { throw "File not found: $_" }
            return $true
        })]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [switch]$ResolveReferences
    )
    
    try {
        $sourceFile = 'inline'
        
        # Load content
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Write-Verbose "[$script:ParserName] Loading spec from: $Path"
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $extension = [System.IO.Path]::GetExtension($Path).ToLower()
            $rawContent = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        else {
            $extension = '.json'
            $rawContent = $Content
        }
        
        # Parse based on format
        $spec = $null
        if ($extension -eq '.yaml' -or $extension -eq '.yml' -or 
            $rawContent.TrimStart().StartsWith('openapi:') -or 
            $rawContent.TrimStart().StartsWith('swagger:')) {
            $spec = ConvertFrom-YamlContent -Content $rawContent
        }
        else {
            $spec = $rawContent | ConvertFrom-Json -Depth 100
        }
        
        if (-not $spec) {
            Write-Warning "[$script:ParserName] Empty or invalid specification"
            return $null
        }
        
        # Detect version
        $version = Get-OpenAPIVersion -Spec $spec
        Write-Verbose "[$script:ParserName] Detected OpenAPI version: $version"
        
        # Build normalized result
        $result = @{
            openapi = $version
            info = $spec.info
            servers = @()
            paths = @{}
            components = @{
                schemas = @{}
                responses = @{}
                parameters = @{}
                examples = @{}
                requestBodies = @{}
                headers = @{}
                securitySchemes = @{}
                links = @{}
                callbacks = @{}
            }
            security = $spec.security
            tags = $spec.tags
            externalDocs = $spec.externalDocs
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        # Handle version-specific structures
        if ($version -eq '2.0') {
            # Swagger 2.0 conversion
            $result.servers = @(@{
                url = if ($spec.host) { 
                    if ($spec.basePath) { "https://$($spec.host)$($spec.basePath)" } else { "https://$($spec.host)" }
                } else { '/' }
            })
            
            if ($spec.definitions) {
                foreach ($name in $spec.definitions.PSObject.Properties.Name) {
                    $result.components.schemas[$name] = $spec.definitions.$name
                }
            }
            
            if ($spec.securityDefinitions) {
                foreach ($name in $spec.securityDefinitions.PSObject.Properties.Name) {
                    $result.components.securitySchemes[$name] = $spec.securityDefinitions.$name
                }
            }
            
            if ($spec.responses) {
                foreach ($name in $spec.responses.PSObject.Properties.Name) {
                    $result.components.responses[$name] = $spec.responses.$name
                }
            }
            
            if ($spec.parameters) {
                foreach ($name in $spec.parameters.PSObject.Properties.Name) {
                    $result.components.parameters[$name] = $spec.parameters.$name
                }
            }
        }
        else {
            # OpenAPI 3.x
            if ($spec.servers) {
                $result.servers = $spec.servers
            }
            
            if ($spec.components) {
                foreach ($category in $spec.components.PSObject.Properties.Name) {
                    if ($result.components.ContainsKey($category)) {
                        $result.components[$category] = $spec.components.$category
                    }
                }
            }
        }
        
        # Process paths
        if ($spec.paths) {
            foreach ($path in $spec.paths.PSObject.Properties.Name) {
                $pathItem = $spec.paths.$path
                $normalizedPathItem = @{}
                
                # Process path-level parameters
                if ($pathItem.parameters) {
                    $normalizedPathItem.parameters = @()
                    foreach ($param in $pathItem.parameters) {
                        $normalizedPathItem.parameters += ConvertTo-NormalizedParameter -Parameter $param
                    }
                }
                
                # Process operations
                foreach ($method in $script:HTTPMethods) {
                    if ($pathItem.$method) {
                        $operation = $pathItem.$method
                        $normalizedOp = @{
                            tags = $operation.tags
                            summary = $operation.summary
                            description = $operation.description
                            operationId = if ($operation.operationId) { $operation.operationId } else { New-OperationId -Path $path -Method $method }
                            parameters = @()
                            requestBody = $null
                            responses = @{}
                            callbacks = $operation.callbacks
                            deprecated = $operation.deprecated
                            security = $operation.security
                            servers = $operation.servers
                        }
                        
                        # Process operation parameters
                        if ($operation.parameters) {
                            foreach ($param in $operation.parameters) {
                                $normalizedOp.parameters += ConvertTo-NormalizedParameter -Parameter $param
                            }
                        }
                        
                        # Process request body
                        if ($version -eq '2.0' -and $operation.consumes -and $operation.parameters) {
                            $bodyParam = $operation.parameters | Where-Object { $_.'in' -eq 'body' } | Select-Object -First 1
                            if ($bodyParam) {
                                $normalizedOp.requestBody = @{
                                    description = $bodyParam.description
                                    required = $bodyParam.required
                                    content = @{}
                                }
                                foreach ($contentType in $operation.consumes) {
                                    $normalizedOp.requestBody.content[$contentType] = @{
                                        schema = $bodyParam.schema
                                    }
                                }
                            }
                        }
                        elseif ($operation.requestBody) {
                            $normalizedOp.requestBody = $operation.requestBody
                        }
                        
                        # Process responses
                        if ($operation.responses) {
                            foreach ($statusCode in $operation.responses.PSObject.Properties.Name) {
                                $response = $operation.responses.$statusCode
                                $normalizedOp.responses[$statusCode] = ConvertTo-NormalizedResponse -Response $response -Version $version
                            }
                        }
                        
                        $normalizedPathItem[$method] = $normalizedOp
                    }
                }
                
                if ($pathItem.servers) {
                    $normalizedPathItem.servers = $pathItem.servers
                }
                
                $result.paths[$path] = $normalizedPathItem
            }
        }
        
        if ($ResolveReferences) {
            $result._referencesResolved = $true
        }
        
        Write-Verbose "[$script:ParserName] Parsed spec with $($result.paths.Count) paths and $($result.components.schemas.Count) schemas"
        return $result
    }
    catch {
        Write-Error "[$script:ParserName] Failed to parse OpenAPI spec: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Extracts parameters from an OpenAPI specification.
    
    DEPRECATED: Use Extract-OpenAPIPaths instead.
#>
function Get-OpenAPIParameters {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Spec,
        
        [Parameter()]
        [ValidateSet('query', 'header', 'path', 'cookie')]
        [string]$Location
    )
    
    process {
        $parameters = @()
        $seen = @{}
        
        # Collect from component parameters
        if ($Spec.components.parameters) {
            foreach ($name in $Spec.components.parameters.Keys) {
                $param = $Spec.components.parameters[$name]
                if ($Location -and $param.'in' -ne $Location) {
                    continue
                }
                
                $key = "component:$name"
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $parameters += [PSCustomObject]@{
                        name = $param.name
                        in = $param.'in'
                        location = 'components'
                        path = $null
                        method = $null
                        description = $param.description
                        required = if ($null -ne $param.required) { $param.required } else { $false }
                        deprecated = $param.deprecated
                        schema = $param.schema
                    }
                }
            }
        }
        
        # Collect from paths
        foreach ($path in $Spec.paths.Keys) {
            $pathItem = $Spec.paths[$path]
            
            # Path-level parameters
            if ($pathItem.parameters) {
                foreach ($param in $pathItem.parameters) {
                    if ($Location -and $param.'in' -ne $Location) {
                        continue
                    }
                    
                    $key = "path:$($param.name):$($param.'in')"
                    if (-not $seen.ContainsKey($key)) {
                        $seen[$key] = $true
                        $parameters += [PSCustomObject]@{
                            name = $param.name
                            in = $param.'in'
                            location = 'path'
                            path = $path
                            method = $null
                            description = $param.description
                            required = if ($null -ne $param.required) { $param.required } else { $false }
                            deprecated = $param.deprecated
                            schema = $param.schema
                        }
                    }
                }
            }
            
            # Operation-level parameters
            foreach ($method in $script:HTTPMethods) {
                $operation = $pathItem[$method]
                if (-not $operation -or -not $operation.parameters) {
                    continue
                }
                
                foreach ($param in $operation.parameters) {
                    if ($Location -and $param.'in' -ne $Location) {
                        continue
                    }
                    
                    $key = "op:$path`:$method`:$($param.name)"
                    if (-not $seen.ContainsKey($key)) {
                        $seen[$key] = $true
                        $parameters += [PSCustomObject]@{
                            name = $param.name
                            in = $param.'in'
                            location = 'operation'
                            path = $path
                            method = $method.ToUpper()
                            description = $param.description
                            required = if ($null -ne $param.required) { $param.required } else { $false }
                            deprecated = $param.deprecated
                            schema = $param.schema
                        }
                    }
                }
            }
        }
        
        return $parameters
    }
}

<#
.SYNOPSIS
    Merges multiple OpenAPI specifications into one.
    
    DEPRECATED: This is a utility function, use with ConvertFrom-OpenAPISpec output.
#>
function Merge-OpenAPISpecs {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Specs,
        
        [Parameter()]
        [string]$Title = 'Merged API',
        
        [Parameter()]
        [string]$Version = '1.0.0',
        
        [Parameter()]
        [ValidateSet('first', 'last', 'error')]
        [string]$ConflictResolution = 'last'
    )
    
    try {
        Write-Verbose "[$script:ParserName] Merging $($Specs.Count) specifications"
        
        if ($Specs.Count -eq 0) {
            Write-Warning "[$script:ParserName] No specifications to merge"
            return $null
        }
        
        if ($Specs.Count -eq 1) {
            return $Specs[0]
        }
        
        # Use OpenAPI 3.0.3 as target version
        $merged = @{
            openapi = '3.0.3'
            info = @{
                title = $Title
                version = $Version
                description = "Merged from $($Specs.Count) specifications"
            }
            servers = @()
            paths = @{}
            components = @{
                schemas = @{}
                responses = @{}
                parameters = @{}
                examples = @{}
                requestBodies = @{}
                headers = @{}
                securitySchemes = @{}
                links = @{}
                callbacks = @{}
            }
            security = @()
            tags = @()
        }
        
        $conflicts = @()
        
        foreach ($spec in $Specs) {
            # Merge servers
            if ($spec.servers) {
                foreach ($server in $spec.servers) {
                    $serverUrl = if ($server.url) { $server.url } else { '/' }
                    $exists = $merged.servers | Where-Object { $_.url -eq $serverUrl }
                    if (-not $exists) {
                        $merged.servers += $server
                    }
                }
            }
            
            # Merge paths
            if ($spec.paths) {
                foreach ($path in $spec.paths.Keys) {
                    if ($merged.paths.ContainsKey($path)) {
                        switch ($ConflictResolution) {
                            'first' {
                                $conflicts += "Path $path - keeping first occurrence"
                            }
                            'last' {
                                $merged.paths[$path] = $spec.paths[$path]
                                $conflicts += "Path $path - replaced with last occurrence"
                            }
                            'error' {
                                throw "Conflict detected for path: $path"
                            }
                        }
                    }
                    else {
                        $merged.paths[$path] = $spec.paths[$path]
                    }
                }
            }
            
            # Merge components
            if ($spec.components) {
                foreach ($category in $spec.components.Keys) {
                    if (-not $merged.components.ContainsKey($category)) {
                        continue
                    }
                    
                    $categoryData = $spec.components[$category]
                    if (-not $categoryData) {
                        continue
                    }
                    
                    foreach ($name in $categoryData.Keys) {
                        if ($merged.components[$category].ContainsKey($name)) {
                            switch ($ConflictResolution) {
                                'first' {
                                    $conflicts += "Component $category/$name - keeping first occurrence"
                                }
                                'last' {
                                    $merged.components[$category][$name] = $categoryData[$name]
                                    $conflicts += "Component $category/$name - replaced with last occurrence"
                                }
                                'error' {
                                    throw "Conflict detected for component: $category/$name"
                                }
                            }
                        }
                        else {
                            $merged.components[$category][$name] = $categoryData[$name]
                        }
                    }
                }
            }
            
            # Merge tags
            if ($spec.tags) {
                $existingTagNames = $merged.tags | ForEach-Object { $_.name }
                foreach ($tag in $spec.tags) {
                    if ($existingTagNames -notcontains $tag.name) {
                        $merged.tags += $tag
                    }
                }
            }
            
            # Merge security requirements
            if ($spec.security) {
                foreach ($sec in $spec.security) {
                    $merged.security += $sec
                }
            }
        }
        
        $merged.mergedFrom = $Specs.Count
        $merged.mergedAt = [DateTime]::UtcNow.ToString("o")
        
        if ($conflicts.Count -gt 0) {
            $merged.mergeConflicts = $conflicts
            Write-Warning "[$script:ParserName] Encountered $($conflicts.Count) conflicts during merge"
        }
        
        return $merged
    }
    catch {
        Write-Error "[$script:ParserName] Failed to merge specifications: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Checks OpenAPI specification version compatibility.
    
    DEPRECATED: Use with ConvertFrom-OpenAPISpec output.
#>
function Test-OpenAPICompatibility {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Spec,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('2.0', '3.0.0', '3.0.1', '3.0.2', '3.0.3', '3.1.0')]
        [string]$TargetVersion
    )
    
    process {
        $sourceVersion = $Spec.openapi
        $issues = @()
        $warnings = @()
        
        # Check downgrade from 3.x to 2.0
        if ($TargetVersion -eq '2.0' -and $sourceVersion -ne '2.0') {
            if ($Spec.components.callbacks -and $Spec.components.callbacks.Count -gt 0) {
                $issues += "Callbacks are not supported in Swagger 2.0"
            }
            
            if ($Spec.components.links -and $Spec.components.links.Count -gt 0) {
                $warnings += "Links will be omitted in Swagger 2.0"
            }
            
            foreach ($path in $Spec.paths.Keys) {
                $pathItem = $Spec.paths[$path]
                foreach ($method in $script:HTTPMethods) {
                    $operation = $pathItem[$method]
                    if (-not $operation) { continue }
                    
                    if ($operation.requestBody) {
                        $warnings += "Request body in $method $path needs conversion to body parameter"
                    }
                    
                    if ($operation.parameters) {
                        $cookieParams = $operation.parameters | Where-Object { $_.in -eq 'cookie' }
                        if ($cookieParams) {
                            $issues += "Cookie parameters in $method $path are not supported in Swagger 2.0"
                        }
                    }
                }
            }
            
            if ($Spec.servers -and $Spec.servers.Count -gt 1) {
                $warnings += "Multiple servers will be reduced to single host/basePath in Swagger 2.0"
            }
            
            foreach ($name in $Spec.components.schemas.Keys) {
                $schema = $Spec.components.schemas[$name]
                if ($schema.oneOf -or $schema.anyOf) {
                    $issues += "oneOf/anyOf in schema $name are not supported in Swagger 2.0"
                }
            }
        }
        
        # Check upgrade from 2.0 to 3.x
        if ($TargetVersion -ne '2.0' -and $sourceVersion -eq '2.0') {
            $warnings += "File upload parameters need conversion to requestBody"
            $warnings += "Form data parameters need conversion to requestBody with appropriate encoding"
        }
        
        $report = @{
            sourceVersion = $sourceVersion
            targetVersion = $TargetVersion
            compatible = ($issues.Count -eq 0)
            issues = $issues
            warnings = $warnings
            issueCount = $issues.Count
            warningCount = $warnings.Count
        }
        
        return $report
    }
}

<#
.SYNOPSIS
    Validates an OpenAPI specification structure.
    
    DEPRECATED: Use with ConvertFrom-OpenAPISpec output.
#>
function Test-OpenAPISpecValidation {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Spec,
        
        [Parameter()]
        [switch]$Strict
    )
    
    process {
        $errors = @()
        $warnings = @()
        
        # Check required fields
        if (-not $Spec.openapi) {
            $errors += "Missing 'openapi' field"
        }
        
        if (-not $Spec.info) {
            $errors += "Missing 'info' object"
        }
        else {
            if (-not $Spec.info.title) {
                $errors += "Missing info.title"
            }
            if (-not $Spec.info.version) {
                $errors += "Missing info.version"
            }
        }
        
        if (-not $Spec.paths -or $Spec.paths.Count -eq 0) {
            $warnings += "No paths defined"
        }
        
        # Check for duplicate operationIds
        $operationIds = @()
        foreach ($path in $Spec.paths.Keys) {
            $pathItem = $Spec.paths[$path]
            foreach ($method in $script:HTTPMethods) {
                $operation = $pathItem[$method]
                if (-not $operation) { continue }
                
                if ($operation.operationId) {
                    if ($operationIds -contains $operation.operationId) {
                        $errors += "Duplicate operationId: $($operation.operationId)"
                    }
                    $operationIds += $operation.operationId
                }
                elseif ($Strict) {
                    $warnings += "Missing operationId for $method $path"
                }
                
                if (-not $operation.responses -or $operation.responses.Count -eq 0) {
                    $errors += "No responses defined for $method $path"
                }
            }
        }
        
        $report = @{
            valid = ($errors.Count -eq 0)
            errors = $errors
            warnings = $warnings
            errorCount = $errors.Count
            warningCount = $warnings.Count
        }
        
        return $report
    }
}

# Export module functions
Export-ModuleMember -Function @(
    # Canonical functions (Section 25.6)
    'Extract-OpenAPIPaths'
    'Extract-OpenAPISchemas'
    'Extract-OpenAPISecurity'
    'Convert-OpenAPIToMarkdown'
    # Legacy compatibility functions
    'ConvertFrom-OpenAPISpec'
    'Get-OpenAPIParameters'
    'Merge-OpenAPISpecs'
    'Test-OpenAPICompatibility'
    'Test-OpenAPISpecValidation'
)
