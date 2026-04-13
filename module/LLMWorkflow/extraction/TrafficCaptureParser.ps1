#requires -Version 5.1
<#
.SYNOPSIS
    Traffic Capture Parser for LLM Workflow API Reverse Engineering.

.DESCRIPTION
    Parses HTTP traffic capture files (HAR, mitmproxy dumps) to extract structured
    request/response pairs and generate OpenAPI path definitions. This parser
    implements the traffic analysis pipeline for API reverse engineering including:
    
    - HAR (HTTP Archive) file parsing
    - mitmproxy flow dump parsing
    - Request/response pair extraction
    - Path template inference with parameter detection
    - OpenAPI path generation from captured traffic
    - Secret detection (API keys, tokens, credentials)
    - Schema inference from response bodies
    
    This parser follows the canonical architecture for API Reverse Tooling pack.

.NOTES
    File Name      : TrafficCaptureParser.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Pack           : api-reverse-tooling

.EXAMPLE
    # Parse a HAR file
    $capture = ConvertFrom-HARFile -Path "traffic.har"
    
    # Parse mitmproxy dump
    $flows = ConvertFrom-MitmproxyDump -Path "flows.flow"
    
    # Extract request/response pairs
    $pairs = Get-RequestResponsePairs -Capture $capture
    
    # Infer path templates
    $templates = Invoke-PathTemplateInference -Pairs $pairs
    
    # Generate OpenAPI paths
    $paths = New-OpenAPIPathFromCapture -Pairs $pairs -Templates $templates
#>

Set-StrictMode -Version Latest

#===============================================================================
# Script-level Constants and Patterns
#===============================================================================

$script:SecretPatterns = @{
    # API Keys
    ApiKey = @(
        "(?i)(?:api[_-]?key|apikey)\s*[=:]\s*[`"']?([a-zA-Z0-9_-]{16,})[`"']?",
        '(?i)(?:x-api-key|api-key)\s*:\s*([a-zA-Z0-9_-]{16,})'
    )
    
    # Bearer tokens
    BearerToken = @(
        '(?i)bearer\s+([a-zA-Z0-9_\-\.]{20,})',
        '(?i)authorization\s*:\s*bearer\s+([a-zA-Z0-9_\-\.]{20,})'
    )
    
    # Basic Auth
    BasicAuth = @(
        '(?i)authorization\s*:\s*basic\s+([a-zA-Z0-9+/=]{10,})'
    )
    
    # OAuth tokens
    OAuthToken = @(
        "(?i)(?:access_token|refresh_token)\s*[=:]\s*[`"']?([a-zA-Z0-9_\-\.]{20,})[`"']?"
    )
    
    # Common header patterns
    AuthHeader = @(
        '(?i)(?:x-auth-token|x-access-token|x-api-secret)\s*:\s*([a-zA-Z0-9_-]{8,})'
    )
    
    # Query parameter secrets
    QuerySecret = @(
        '(?i)[?&](?:token|key|secret|password|pwd)=([^&]{8,})'
    )
    
    # AWS credentials
    AWSKey = @(
        '(?i)AKIA[0-9A-Z]{16}',
        "(?i)(?:aws[_-]?secret[_-]?access[_-]?key)\s*[=:]\s*[`"']?([a-zA-Z0-9/+=]{40})[`"']?"
    )
    
    # JWT patterns
    JWT = @(
        'eyJ[a-zA-Z0-9_-]*\.eyJ[a-zA-Z0-9_-]*\.[a-zA-Z0-9_-]*'
    )
}

$script:ContentTypePatterns = @{
    JSON = 'application/(?:json|[^;]*\+json)'
    XML = 'application/(?:xml|[^;]*\+xml)'
    Form = 'application/x-www-form-urlencoded'
    Multipart = 'multipart/form-data'
    Text = 'text/\w+'
    Binary = 'application/octet-stream'
}

$script:PathPatterns = @{
    # UUIDs
    UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    
    # MongoDB ObjectId
    ObjectId = '[0-9a-f]{24}'
    
    # Numeric IDs
    NumericId = '\d+'
    
    # Common ID parameter names in paths
    IdPathSegment = '(?i)(?:id|uuid|key|token|slug|name)'
    
    # Date patterns
    DateISO = '\d{4}-\d{2}-\d{2}'
    DateTimeISO = '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
    
    # Email in path
    Email = '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
}

#===============================================================================
# Private Helper Functions
#===============================================================================

<#
.SYNOPSIS
    Detects and redacts secrets from content.

.DESCRIPTION
    Scans content for API keys, tokens, and credentials using pattern matching.
    Returns the content with secrets redacted and a list of found secrets.

.PARAMETER Content
    The content to scan for secrets.

.PARAMETER RedactionToken
    The token to replace secrets with (default: '[REDACTED]').

.OUTPUTS
    System.Collections.Hashtable with RedactedContent and Secrets array.
#>
function Protect-CapturedSecrets {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$RedactionToken = '[REDACTED]'
    )
    
    process {
        $redacted = $Content
        $foundSecrets = @()
        
        foreach ($category in $script:SecretPatterns.Keys) {
            $patterns = $script:SecretPatterns[$category]
            foreach ($pattern in $patterns) {
                $matches = [regex]::Matches($redacted, $pattern)
                foreach ($match in $matches) {
                    $secretValue = if ($match.Groups.Count -gt 1) { 
                        $match.Groups[1].Value 
                    } else { 
                        $match.Value 
                    }
                    
                    # Store secret info (without full value for security)
                    $foundSecrets += [PSCustomObject]@{
                        Category = $category
                        Pattern = $pattern
                        Position = $match.Index
                        Length = $match.Length
                        Preview = $secretValue.Substring(0, [Math]::Min(8, $secretValue.Length)) + '...'
                        Redacted = $true
                    }
                    
                    # Redact in content
                    $redacted = $redacted.Substring(0, $match.Index) + 
                                $RedactionToken + 
                                $redacted.Substring($match.Index + $match.Length)
                }
            }
        }
        
        return @{
            RedactedContent = $redacted
            Secrets = $foundSecrets
            SecretCount = $foundSecrets.Count
        }
    }
}

<#
.SYNOPSIS
    Parses HTTP headers from a header string or object.

.DESCRIPTION
    Converts HTTP headers from various formats into a normalized hashtable.

.PARAMETER Headers
    Headers as string, hashtable, or JSON object.

.OUTPUTS
    System.Collections.Hashtable. Normalized headers.
#>
function ConvertFrom-HTTPHeaders {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Headers
    )
    
    $result = @{}
    
    try {
        if ($Headers -is [hashtable] -or $Headers -is [System.Collections.IDictionary]) {
            foreach ($key in $Headers.Keys) {
                $result[$key.ToString().ToLower()] = $Headers[$key].ToString()
            }
        }
        elseif ($Headers -is [string]) {
            # Parse header string format "Header-Name: value"
            $lines = $Headers -split "`r?`n"
            foreach ($line in $lines) {
                if ($line -match '^([^:]+):\s*(.+)$') {
                    $result[$matches[1].Trim().ToLower()] = $matches[2].Trim()
                }
            }
        }
        elseif ($Headers -is [PSCustomObject] -or $Headers -is [System.Management.Automation.PSCustomObject]) {
            $Headers.PSObject.Properties | ForEach-Object {
                $result[$_.Name.ToLower()] = $_.Value.ToString()
            }
        }
    }
    catch {
        Write-Verbose "[TrafficCaptureParser] Failed to parse headers: $_"
    }
    
    return $result
}

<#
.SYNOPSIS
    Infers the type of a value for schema generation.

.DESCRIPTION
    Analyzes a value and returns the corresponding JSON Schema type.

.PARAMETER Value
    The value to analyze.

.OUTPUTS
    System.String. The inferred type (string, number, integer, boolean, object, array).
#>
function Get-InferredType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value
    )
    
    if ($null -eq $Value) {
        return 'null'
    }
    
    $type = $Value.GetType().Name
    
    switch -Regex ($type) {
        'Int\d+|UInt\d+|Byte|SByte' { return 'integer' }
        'Single|Double|Decimal' { return 'number' }
        'Boolean' { return 'boolean' }
        'String|Char' { return 'string' }
        'Array|List|Collection' { return 'array' }
        'Hashtable|Dictionary|PSCustomObject|JObject' { return 'object' }
        default { return 'string' }
    }
}

<#
.SYNOPSIS
    Generates a JSON Schema from sample data.

.DESCRIPTION
    Creates a JSON Schema object by analyzing sample data structure.

.PARAMETER Data
    The sample data to analyze.

.PARAMETER SchemaTitle
    Optional title for the schema.

.OUTPUTS
    System.Collections.Hashtable. JSON Schema object.
#>
function New-InferredSchema {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Data,
        
        [Parameter()]
        [string]$SchemaTitle = 'InferredSchema'
    )
    
    $schema = @{
        title = $SchemaTitle
        type = Get-InferredType -Value $Data
    }
    
    if ($schema.type -eq 'object' -and $Data -ne $null) {
        $schema.properties = @{}
        $schema.required = @()
        
        $properties = if ($Data -is [System.Collections.IDictionary]) {
            $Data.GetEnumerator()
        } else {
            $Data.PSObject.Properties
        }
        
        foreach ($prop in $properties) {
            $propName = if ($prop -is [System.Collections.DictionaryEntry]) { $prop.Key } else { $prop.Name }
            $propValue = if ($prop -is [System.Collections.DictionaryEntry]) { $prop.Value } else { $prop.Value }
            
            $schema.properties[$propName] = New-InferredSchema -Data $propValue -SchemaTitle "$SchemaTitle.$propName"
            $schema.required += $propName
        }
    }
    elseif ($schema.type -eq 'array' -and $Data -ne $null -and $Data.Count -gt 0) {
        $schema.items = New-InferredSchema -Data $Data[0] -SchemaTitle "$SchemaTitle.Item"
    }
    
    return $schema
}

<#
.SYNOPSIS
    Checks if a path segment looks like an ID or parameter.

.DESCRIPTION
    Analyzes a path segment to determine if it's likely a dynamic value
    that should be parameterized in the path template.

.PARAMETER Segment
    The path segment to analyze.

.OUTPUTS
    System.Boolean. True if the segment appears to be an ID/parameter.
#>
function Test-IsPathParameter {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Segment
    )
    
    # Check UUID
    if ($Segment -match "^$($script:PathPatterns.UUID)$") {
        return $true
    }
    
    # Check ObjectId
    if ($Segment -match "^$($script:PathPatterns.ObjectId)$") {
        return $true
    }
    
    # Check numeric ID
    if ($Segment -match "^$($script:PathPatterns.NumericId)$") {
        return $true
    }
    
    # Check email
    if ($Segment -match "^$($script:PathPatterns.Email)$") {
        return $true
    }
    
    # Check ISO date
    if ($Segment -match "^$($script:PathPatterns.DateISO)$") {
        return $true
    }
    
    return $false
}

<#
.SYNOPSIS
    Generates a parameter name from a segment value.

.DESCRIPTION
    Creates a meaningful parameter name based on the segment content type.

.PARAMETER Segment
    The path segment value.

.PARAMETER Index
    The segment index for generating fallback names.

.OUTPUTS
    System.String. Suggested parameter name.
#>
function Get-ParameterNameFromSegment {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Segment,
        
        [Parameter()]
        [int]$Index = 0
    )
    
    if ($Segment -match "^$($script:PathPatterns.UUID)$") {
        return 'id'
    }
    
    if ($Segment -match "^$($script:PathPatterns.ObjectId)$") {
        return 'id'
    }
    
    if ($Segment -match "^$($script:PathPatterns.NumericId)$") {
        return 'id'
    }
    
    if ($Segment -match "^$($script:PathPatterns.Email)$") {
        return 'email'
    }
    
    if ($Segment -match "^$($script:PathPatterns.DateISO)$") {
        return 'date'
    }
    
    return "param$Index"
}

#===============================================================================
# Public API Functions
#===============================================================================

<#
.SYNOPSIS
    Parses a HAR (HTTP Archive) file and extracts traffic data.

.DESCRIPTION
    Loads and parses a HAR file, extracting all HTTP request/response pairs
    with full header and body information. Optionally redacts secrets.

.PARAMETER Path
    Path to the HAR file.

.PARAMETER RedactSecrets
    If specified, detects and redacts API keys and tokens from the output.

.PARAMETER IncludeBodies
    If specified, includes request and response bodies in the output.

.OUTPUTS
    System.Collections.Hashtable. Parsed HAR data with entries array.

.EXAMPLE
    $har = ConvertFrom-HARFile -Path "network.har"
    
    $har = ConvertFrom-HARFile -Path "network.har" -RedactSecrets -IncludeBodies
#>
function ConvertFrom-HARFile {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({
            if (-not (Test-Path -LiteralPath $_)) { throw "File not found: $_" }
            return $true
        })]
        [string]$Path,
        
        [Parameter()]
        [switch]$RedactSecrets,
        
        [Parameter()]
        [switch]$IncludeBodies
    )
    
    try {
        Write-Verbose "[TrafficCaptureParser] Loading HAR file: $Path"
        
        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $har = $content | ConvertFrom-Json -Depth 100
        
        if (-not $har.log) {
            Write-Warning "[TrafficCaptureParser] Invalid HAR file: missing 'log' property"
            return $null
        }
        
        $entries = @()
        $secretScanStats = @{
            TotalScanned = 0
            SecretsFound = 0
        }
        
        foreach ($entry in $har.log.entries) {
            $request = $entry.request
            $response = $entry.response
            
            # Build request object
            $reqObj = @{
                method = $request.method
                url = $request.url
                headers = ConvertFrom-HTTPHeaders -Headers $request.headers
                queryString = @{}
            }
            
            # Parse query string
            if ($request.queryString) {
                foreach ($qs in $request.queryString) {
                    $reqObj.queryString[$qs.name] = $qs.value
                }
            }
            
            # Handle request body
            if ($IncludeBodies -and $request.postData) {
                $reqObj.body = $request.postData.text
                $reqObj.bodySize = $request.bodySize
            }
            
            # Build response object
            $respObj = @{
                status = $response.status
                statusText = $response.statusText
                headers = ConvertFrom-HTTPHeaders -Headers $response.headers
                contentType = $null
                contentSize = $response.content.size
            }
            
            # Extract content type
            if ($response.content.mimeType) {
                $respObj.contentType = $response.content.mimeType
            }
            elseif ($respObj.headers['content-type']) {
                $respObj.contentType = $respObj.headers['content-type']
            }
            
            # Handle response body
            if ($IncludeBodies -and $response.content.text) {
                $respObj.body = $response.content.text
            }
            
            # Redact secrets if requested
            if ($RedactSecrets) {
                $secretScanStats.TotalScanned++
                
                $reqRedaction = Protect-CapturedSecrets -Content ($reqObj | ConvertTo-Json -Depth 5)
                if ($reqRedaction.SecretCount -gt 0) {
                    $secretScanStats.SecretsFound += $reqRedaction.SecretCount
                }
                
                $respRedaction = Protect-CapturedSecrets -Content ($respObj | ConvertTo-Json -Depth 5)
                if ($respRedaction.SecretCount -gt 0) {
                    $secretScanStats.SecretsFound += $respRedaction.SecretCount
                }
            }
            
            $entries += [PSCustomObject]@{
                startedDateTime = $entry.startedDateTime
                time = $entry.time
                request = $reqObj
                response = $respObj
                serverIPAddress = $entry.serverIPAddress
                connection = $entry.connection
            }
        }
        
        $result = @{
            version = $har.log.version
            creator = $har.log.creator
            browser = $har.log.browser
            entries = $entries
            entryCount = $entries.Count
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        if ($RedactSecrets) {
            $result.secretScan = $secretScanStats
        }
        
        Write-Verbose "[TrafficCaptureParser] Parsed $($entries.Count) HAR entries"
        return $result
    }
    catch {
        Write-Error "[TrafficCaptureParser] Failed to parse HAR file: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Parses mitmproxy flow dump files.

.DESCRIPTION
    Loads and parses mitmproxy flow dumps (typically .flow files), extracting
    HTTP request/response pairs with full header and body information.

.PARAMETER Path
    Path to the mitmproxy flow file.

.PARAMETER RedactSecrets
    If specified, detects and redacts API keys and tokens from the output.

.PARAMETER IncludeBodies
    If specified, includes request and response bodies in the output.

.OUTPUTS
    System.Collections.Hashtable. Parsed flow data with flows array.

.EXAMPLE
    $flows = ConvertFrom-MitmproxyDump -Path "captures.flow"
    
    $flows = ConvertFrom-MitmproxyDump -Path "captures.flow" -RedactSecrets
#>
function ConvertFrom-MitmproxyDump {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({
            if (-not (Test-Path -LiteralPath $_)) { throw "File not found: $_" }
            return $true
        })]
        [string]$Path,
        
        [Parameter()]
        [switch]$RedactSecrets,
        
        [Parameter()]
        [switch]$IncludeBodies
    )
    
    try {
        Write-Verbose "[TrafficCaptureParser] Loading mitmproxy dump: $Path"
        
        # mitmproxy flows are typically stored as a stream of JSON objects
        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        
        $flows = @()
        $secretScanStats = @{
            TotalScanned = 0
            SecretsFound = 0
        }
        
        # Try to parse as JSON array first
        try {
            $flowArray = $content | ConvertFrom-Json -Depth 100
            if ($flowArray -is [array]) {
                $flowData = $flowArray
            } else {
                $flowData = @($flowArray)
            }
        }
        catch {
            # Try parsing as newline-delimited JSON (NDJSON)
            $flowData = @()
            $lines = $content -split "`r?`n" | Where-Object { $_.Trim() }
            foreach ($line in $lines) {
                try {
                    $flowData += $line | ConvertFrom-Json -Depth 100
                }
                catch {
                    Write-Verbose "[TrafficCaptureParser] Skipping invalid JSON line"
                }
            }
        }
        
        foreach ($flow in $flowData) {
            if (-not $flow.request) {
                continue
            }
            
            $request = $flow.request
            $response = $flow.response
            
            # Build request object
            $reqObj = @{
                method = $request.method
                url = $request.url
                headers = ConvertFrom-HTTPHeaders -Headers $request.headers
                host = $request.host
                port = $request.port
                scheme = $request.scheme
            }
            
            # Handle request body
            if ($IncludeBodies -and $request.content) {
                $reqObj.body = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($request.content))
            }
            
            # Build response object
            $respObj = $null
            if ($response) {
                $respObj = @{
                    statusCode = $response.status_code
                    reason = $response.reason
                    headers = ConvertFrom-HTTPHeaders -Headers $response.headers
                    contentType = $null
                }
                
                # Extract content type
                if ($response.headers -is [hashtable]) {
                    $respObj.contentType = $response.headers['content-type']
                }
                
                # Handle response body
                if ($IncludeBodies -and $response.content) {
                    $respObj.body = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($response.content))
                }
            }
            
            # Redact secrets if requested
            if ($RedactSecrets) {
                $secretScanStats.TotalScanned++
                
                $reqRedaction = Protect-CapturedSecrets -Content ($reqObj | ConvertTo-Json -Depth 5)
                if ($reqRedaction.SecretCount -gt 0) {
                    $secretScanStats.SecretsFound += $reqRedaction.SecretCount
                }
            }
            
            $flows += [PSCustomObject]@{
                id = $flow.id
                type = $flow.type
                timestamp = $flow.timestamp
                request = $reqObj
                response = $respObj
            }
        }
        
        $result = @{
            flowCount = $flows.Count
            flows = $flows
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        if ($RedactSecrets) {
            $result.secretScan = $secretScanStats
        }
        
        Write-Verbose "[TrafficCaptureParser] Parsed $($flows.Count) mitmproxy flows"
        return $result
    }
    catch {
        Write-Error "[TrafficCaptureParser] Failed to parse mitmproxy dump: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Extracts request/response pairs from captured traffic.

.DESCRIPTION
    Normalizes traffic from HAR or mitmproxy format into a unified
    request/response pair structure for further processing.

.PARAMETER Capture
    The capture object from ConvertFrom-HARFile or ConvertFrom-MitmproxyDump.

.PARAMETER FilterUrl
    Optional URL pattern to filter requests.

.PARAMETER FilterMethod
    Optional HTTP method to filter requests.

.OUTPUTS
    System.Array. Array of request/response pair objects.

.EXAMPLE
    $har = ConvertFrom-HARFile -Path "traffic.har"
    $pairs = Get-RequestResponsePairs -Capture $har
    
    $pairs = Get-RequestResponsePairs -Capture $har -FilterMethod GET
#>
function Get-RequestResponsePairs {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Capture,
        
        [Parameter()]
        [string]$FilterUrl,
        
        [Parameter()]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS')]
        [string]$FilterMethod
    )
    
    process {
        $pairs = @()
        
        # Determine source type
        $entries = if ($Capture.entries) { $Capture.entries } elseif ($Capture.flows) { $Capture.flows } else { @() }
        
        foreach ($entry in $entries) {
            $request = $entry.request
            $response = $entry.response
            
            # Apply filters
            if ($FilterUrl -and $request.url -notmatch $FilterUrl) {
                continue
            }
            
            if ($FilterMethod -and $request.method -ne $FilterMethod) {
                continue
            }
            
            # Parse URL
            $uri = $null
            try {
                $uri = [System.Uri]$request.url
            }
            catch {
                Write-Verbose "[TrafficCaptureParser] Invalid URL: $($request.url)"
                continue
            }
            
            $pair = [PSCustomObject]@{
                timestamp = if ($entry.startedDateTime) { $entry.startedDateTime } else { $entry.timestamp }
                method = $request.method
                url = $request.url
                scheme = if ($uri) { $uri.Scheme } else { $request.scheme }
                host = if ($uri) { $uri.Host } else { $request.host }
                port = if ($uri) { $uri.Port } else { $request.port }
                path = if ($uri) { $uri.AbsolutePath } else { '/' }
                query = if ($uri) { $uri.Query } else { '' }
                requestHeaders = $request.headers
                requestBody = $request.body
                responseStatus = if ($response.status) { $response.status } else { $response.statusCode }
                responseStatusText = $response.statusText
                responseReason = $response.reason
                responseHeaders = $response.headers
                responseBody = $response.body
                responseContentType = $response.contentType
                responseContentSize = $response.contentSize
                duration = $entry.time
            }
            
            $pairs += $pair
        }
        
        Write-Verbose "[TrafficCaptureParser] Extracted $($pairs.Count) request/response pairs"
        return $pairs
    }
}

<#
.SYNOPSIS
    Infers parameterized path templates from request URLs.

.DESCRIPTION
    Analyzes a collection of request/response pairs to identify patterns
    in URLs and generate parameterized path templates (e.g., /users/{id})
    suitable for OpenAPI specifications.

.PARAMETER Pairs
    Array of request/response pairs from Get-RequestResponsePairs.

.PARAMETER MinOccurrences
    Minimum number of occurrences to consider a segment as a parameter (default: 2).

.OUTPUTS
    System.Array. Array of path template objects with template string and examples.

.EXAMPLE
    $pairs = Get-RequestResponsePairs -Capture $har
    $templates = Invoke-PathTemplateInference -Pairs $pairs
#>
function Invoke-PathTemplateInference {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [array]$Pairs,
        
        [Parameter()]
        [int]$MinOccurrences = 2
    )
    
    process {
        # Group by path structure
        $pathGroups = @{}
        
        foreach ($pair in $Pairs) {
            $path = $pair.path
            $segments = $path.Trim('/').Split('/')
            
            # Create a signature based on segment count and static patterns
            $signatureParts = @()
            foreach ($segment in $segments) {
                if (Test-IsPathParameter -Segment $segment) {
                    $signatureParts += '{param}'
                } else {
                    $signatureParts += $segment
                }
            }
            $signature = $signatureParts -join '/'
            
            if (-not $pathGroups.ContainsKey($signature)) {
                $pathGroups[$signature] = @{
                    Signature = $signature
                    Segments = $segments
                    Examples = @()
                    SegmentValues = @()
                }
                
                # Initialize segment value tracking
                for ($i = 0; $i -lt $segments.Count; $i++) {
                    $pathGroups[$signature].SegmentValues += @{
                        Index = $i
                        Values = @()
                        IsParameter = $false
                        ParameterName = $null
                    }
                }
            }
            
            $pathGroups[$signature].Examples += $path
            
            # Track segment values
            for ($i = 0; $i -lt $segments.Count; $i++) {
                $pathGroups[$signature].SegmentValues[$i].Values += $segments[$i]
            }
        }
        
        # Analyze each group for parameter patterns
        $templates = @()
        
        foreach ($signature in $pathGroups.Keys) {
            $group = $pathGroups[$signature]
            $templateSegments = @()
            $parameters = @()
            
            foreach ($segInfo in $group.SegmentValues) {
                $uniqueValues = $segInfo.Values | Select-Object -Unique
                
                # Determine if this segment should be a parameter
                $isParam = $false
                $paramName = $null
                
                if ($uniqueValues.Count -ge $MinOccurrences) {
                    # Check if values look like IDs
                    $idLikeCount = ($segInfo.Values | Where-Object { Test-IsPathParameter -Segment $_ }).Count
                    
                    if ($idLikeCount -eq $segInfo.Values.Count) {
                        $isParam = $true
                        $paramName = Get-ParameterNameFromSegment -Segment $segInfo.Values[0] -Index $segInfo.Index
                    }
                    elseif ($uniqueValues.Count -ge $MinOccurrences -and $idLikeCount -gt 0) {
                        # Mixed content - might be parameterized
                        $isParam = $true
                        $paramName = "param$($segInfo.Index)"
                    }
                }
                
                if ($isParam) {
                    $templateSegments += "{$paramName}"
                    $parameters += [PSCustomObject]@{
                        name = $paramName
                        in = 'path'
                        required = $true
                        schema = @{
                            type = Get-InferredType -Value $segInfo.Values[0]
                        }
                        examples = ($uniqueValues | Select-Object -First 3)
                    }
                } else {
                    $templateSegments += $segInfo.Values[0]
                }
            }
            
            $template = [PSCustomObject]@{
                template = '/' + ($templateSegments -join '/')
                signature = $signature
                methodExamples = @{}
                parameters = $parameters
                exampleCount = $group.Examples.Count
                examplePaths = ($group.Examples | Select-Object -Unique -First 5)
            }
            
            $templates += $template
        }
        
        Write-Verbose "[TrafficCaptureParser] Inferred $($templates.Count) path templates"
        return $templates
    }
}

<#
.SYNOPSIS
    Generates OpenAPI path entries from captured traffic.

.DESCRIPTION
    Creates OpenAPI 3.0 path item objects from request/response pairs,
    including inferred schemas, parameters, and response definitions.

.PARAMETER Pairs
    Array of request/response pairs.

.PARAMETER Templates
    Optional pre-computed path templates from Invoke-PathTemplateInference.

.PARAMETER IncludeBodies
    If specified, includes example bodies in the output.

.OUTPUTS
    System.Collections.Hashtable. OpenAPI paths object ready for spec integration.

.EXAMPLE
    $pairs = Get-RequestResponsePairs -Capture $har
    $paths = New-OpenAPIPathFromCapture -Pairs $pairs
    
    $paths = New-OpenAPIPathFromCapture -Pairs $pairs -IncludeBodies
#>
function New-OpenAPIPathFromCapture {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Pairs,
        
        [Parameter()]
        [array]$Templates,
        
        [Parameter()]
        [switch]$IncludeBodies
    )
    
    try {
        Write-Verbose "[TrafficCaptureParser] Generating OpenAPI paths from $($Pairs.Count) pairs"
        
        # Get templates if not provided
        if (-not $Templates) {
            $Templates = Invoke-PathTemplateInference -Pairs $Pairs
        }
        
        $paths = @{}
        $schemas = @{}
        
        # Group pairs by template
        $templateGroups = @{}
        foreach ($pair in $Pairs) {
            $path = $pair.path
            $matchedTemplate = $null
            
            # Find matching template
            foreach ($template in $Templates) {
                if ($path -match $template.signature.Replace('{param}', '.*')) {
                    $matchedTemplate = $template.template
                    break
                }
            }
            
            if (-not $matchedTemplate) {
                $matchedTemplate = $path
            }
            
            if (-not $templateGroups.ContainsKey($matchedTemplate)) {
                $templateGroups[$matchedTemplate] = @()
            }
            $templateGroups[$matchedTemplate] += $pair
        }
        
        # Build path items for each template
        foreach ($templatePath in $templateGroups.Keys) {
            $groupPairs = $templateGroups[$templatePath]
            $pathItem = @{}
            
            # Group by method
            $methodGroups = $groupPairs | Group-Object -Property method
            
            foreach ($methodGroup in $methodGroups) {
                $method = $methodGroup.Name.ToLower()
                $methodPairs = $methodGroup.Group
                
                $operation = @{
                    summary = "$($method.ToUpper()) $templatePath"
                    description = "Generated from $($methodPairs.Count) captured requests"
                    parameters = @()
                    responses = @{}
                }
                
                # Get parameters from first pair with query string
                $samplePair = $methodPairs | Where-Object { $_.query } | Select-Object -First 1
                if ($samplePair) {
                    $queryParams = @()
                    $parsedQuery = [System.Web.HttpUtility]::ParseQueryString($samplePair.query)
                    foreach ($key in $parsedQuery.Keys) {
                        if ($key) {
                            $queryParams += @{
                                name = $key
                                in = 'query'
                                schema = @{
                                    type = 'string'
                                }
                            }
                        }
                    }
                    $operation.parameters += $queryParams
                }
                
                # Add path parameters from template
                if ($templatePath -match '\{(\w+)\}') {
                    $templateParams = [regex]::Matches($templatePath, '\{(\w+)\}') | ForEach-Object {
                        @{
                            name = $_.Groups[1].Value
                            in = 'path'
                            required = $true
                            schema = @{
                                type = 'string'
                            }
                        }
                    }
                    $operation.parameters += $templateParams
                }
                
                # Build responses
                $responseGroups = $methodPairs | Group-Object -Property responseStatus
                foreach ($respGroup in $responseGroups) {
                    $statusCode = if ($respGroup.Name) { $respGroup.Name.ToString() } else { 'default' }
                    $respPairs = $respGroup.Group
                    
                    $response = @{
                        description = if ($respPairs[0].responseStatusText) { 
                            $respPairs[0].responseStatusText 
                        } elseif ($respPairs[0].responseReason) { 
                            $respPairs[0].responseReason 
                        } else { 
                            "Status $statusCode" 
                        }
                    }
                    
                    # Infer content type and schema
                    $contentTypes = $respPairs | Where-Object { $_.responseContentType } | 
                        Group-Object -Property responseContentType
                    
                    if ($contentTypes) {
                        $response.content = @{}
                        foreach ($ct in $contentTypes) {
                            $ctName = $ct.Name
                            $ctPairs = $ct.Group | Where-Object { $_.responseBody }
                            
                            $contentItem = @{}
                            
                            # Try to infer schema from body
                            if ($ctPairs -and $IncludeBodies) {
                                $sampleBody = $ctPairs[0].responseBody
                                try {
                                    $parsedBody = $sampleBody | ConvertFrom-Json -Depth 50
                                    $schemaName = "Response_$($templatePath.Trim('/').Replace('/', '_'))_$method`_$statusCode"
                                    $schema = New-InferredSchema -Data $parsedBody -SchemaTitle $schemaName
                                    
                                    # Store schema for components
                                    $schemas[$schemaName] = $schema
                                    
                                    $contentItem.schema = @{
                                        '$ref' = "#/components/schemas/$schemaName"
                                    }
                                }
                                catch {
                                    $contentItem.schema = @{
                                        type = 'string'
                                    }
                                }
                                
                                # Add example
                                $contentItem.example = $sampleBody
                            }
                            else {
                                $contentItem.schema = @{
                                    type = 'object'
                                }
                            }
                            
                            $response.content[$ctName] = $contentItem
                        }
                    }
                    
                    $operation.responses[$statusCode] = $response
                }
                
                $pathItem[$method] = $operation
            }
            
            $paths[$templatePath] = $pathItem
        }
        
        $result = @{
            paths = $paths
            schemas = $schemas
            generatedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        Write-Verbose "[TrafficCaptureParser] Generated $($paths.Count) OpenAPI paths with $($schemas.Count) schemas"
        return $result
    }
    catch {
        Write-Error "[TrafficCaptureParser] Failed to generate OpenAPI paths: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Scans captured traffic for exposed secrets.

.DESCRIPTION
    Analyzes request/response pairs for API keys, tokens, and credentials
    that may have been inadvertently captured. Returns findings with
    severity levels and locations.

.PARAMETER Pairs
    Array of request/response pairs to scan.

.PARAMETER IncludePreviews
    If specified, includes truncated secret previews in output.

.OUTPUTS
    System.Array. Array of secret finding objects.

.EXAMPLE
    $pairs = Get-RequestResponsePairs -Capture $har
    $secrets = Find-CapturedSecrets -Pairs $pairs
#>
function Find-CapturedSecrets {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [array]$Pairs,
        
        [Parameter()]
        [switch]$IncludePreviews
    )
    
    process {
        $findings = @()
        
        foreach ($pair in $Pairs) {
            $contentToScan = @()
            
            # Scan request headers
            if ($pair.requestHeaders) {
                $contentToScan += @{
                    Source = 'request.headers'
                    Content = ($pair.requestHeaders.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join "`n"
                }
            }
            
            # Scan request body
            if ($pair.requestBody) {
                $contentToScan += @{
                    Source = 'request.body'
                    Content = $pair.requestBody.ToString()
                }
            }
            
            # Scan request URL
            if ($pair.url) {
                $contentToScan += @{
                    Source = 'request.url'
                    Content = $pair.url
                }
            }
            
            # Scan response body
            if ($pair.responseBody) {
                $contentToScan += @{
                    Source = 'response.body'
                    Content = $pair.responseBody.ToString()
                }
            }
            
            foreach ($scanItem in $contentToScan) {
                foreach ($category in $script:SecretPatterns.Keys) {
                    $patterns = $script:SecretPatterns[$category]
                    foreach ($pattern in $patterns) {
                        $matches = [regex]::Matches($scanItem.Content, $pattern)
                        foreach ($match in $matches) {
                            $secretValue = if ($match.Groups.Count -gt 1) { 
                                $match.Groups[1].Value 
                            } else { 
                                $match.Value 
                            }
                            
                            $finding = [PSCustomObject]@{
                                Category = $category
                                Location = $scanItem.Source
                                Url = $pair.url
                                Method = $pair.method
                                Position = $match.Index
                                Severity = switch ($category) {
                                    'BasicAuth' { 'Critical' }
                                    'AWSKey' { 'Critical' }
                                    'JWT' { 'High' }
                                    'BearerToken' { 'High' }
                                    'OAuthToken' { 'High' }
                                    'ApiKey' { 'Medium' }
                                    default { 'Medium' }
                                }
                                Recommendation = switch ($scanItem.Source) {
                                    'request.url' { 'Move credentials to headers or body' }
                                    'request.headers' { 'Use secure header transmission (HTTPS only)' }
                                    'request.body' { 'Ensure body is encrypted in transit' }
                                    'response.body' { 'Remove credentials from responses' }
                                    default { 'Review and secure credential handling' }
                                }
                            }
                            
                            if ($IncludePreviews) {
                                $finding | Add-Member -MemberType NoteProperty -Name Preview -Value ($secretValue.Substring(0, [Math]::Min(16, $secretValue.Length)) + '...')
                            }
                            
                            $findings += $finding
                        }
                    }
                }
            }
        }
        
        # Remove duplicates
        $uniqueFindings = $findings | Sort-Object -Property Url, Category, Location -Unique
        
        Write-Verbose "[TrafficCaptureParser] Found $($uniqueFindings.Count) potential secrets in traffic"
        return $uniqueFindings
    }
}

# Export module functions
# Public functions exported via module wildcard
