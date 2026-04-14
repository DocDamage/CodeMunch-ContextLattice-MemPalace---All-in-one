#requires -Version 5.1
<#
.SYNOPSIS
    Configuration Schema definitions for LLM Workflow platform.

.DESCRIPTION
    Provides the default configuration values, schema validation, and
    configuration structure definitions for the Effective Configuration System.

.NOTES
    Version: 1.0.0
    Compatible with: PowerShell 5.1+
    Environment variable prefix: LLMWF_
#>

# Define valid execution modes
$script:ValidExecutionModes = @(
    'interactive',
    'ci',
    'watch',
    'heal-watch',
    'scheduled',
    'mcp-readonly',
    'mcp-mutating'
)

# Define valid provider types
$script:ValidProviderTypes = @(
    'openai',
    'azure-openai',
    'anthropic',
    'local',
    'custom'
)

# Define valid log levels
$script:ValidLogLevels = @(
    'debug',
    'info',
    'warning',
    'error',
    'critical'
)

# Define secret key patterns for masking
$script:SecretPatterns = @(
    'apiKey',
    'apikey',
    'api_key',
    'secret',
    'token',
    'password',
    'key',
    'credential',
    'auth'
)

<#
.SYNOPSIS
    Gets the built-in default configuration values.

.DESCRIPTION
    Returns the base configuration with all default values.
    This is the lowest priority in the configuration hierarchy.

.OUTPUTS
    Hashtable containing default configuration values.

.EXAMPLE
    $defaults = Get-DefaultConfig
    PS> $defaults.provider.model
    gpt-4
#>
function Get-DefaultConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        schemaVersion = 1
        provider = @{
            type = 'openai'
            endpoint = 'https://api.openai.com/v1'
            model = 'gpt-4'
            apiKey = $null
            timeout = 60
            maxTokens = 4096
            temperature = 0.7
        }
        embedding = @{
            model = 'text-embedding-3-small'
            dimensions = 1536
            batchSize = 100
            timeout = 120
        }
        memory = @{
            palacePath = '.memorybridge/palace'
            maxContextTokens = 8000
            consolidationThreshold = 0.85
            autoSync = $true
            syncInterval = 300
        }
        sync = @{
            mode = 'bidirectional'
            conflictResolution = 'timestamp'
            retryAttempts = 3
            retryDelay = 5
        }
        logging = @{
            level = 'info'
            retentionDays = 30
            maxFileSize = '10MB'
            consoleOutput = $true
            structuredFormat = $true
        }
        execution = @{
            mode = 'interactive'
            timeout = 300
            maxRetries = 3
            budgetTokens = 100000
            budgetCost = 10.00
            parallelTasks = 5
        }
        security = @{
            enableSecretScanning = $true
            encryptionEnabled = $false
            allowedHosts = @()
            blockedHosts = @()
            requireApprovalFor = @('delete', 'modify', 'execute')
        }
    }
}

<#
.SYNOPSIS
    Gets the configuration schema definition.

.DESCRIPTION
    Returns the schema that defines valid configuration structure,
    types, constraints, and documentation for each setting.

.OUTPUTS
    Hashtable containing schema definitions by category.

.EXAMPLE
    $schema = Get-ConfigSchema
    PS> $schema.provider.model.type
    string
#>
function Get-ConfigSchema {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        schemaVersion = @{
            description = 'Configuration schema version'
            type = 'integer'
            required = $true
            min = 1
            max = 1
            default = 1
        }
        provider = @{
            description = 'LLM provider settings'
            type = 'hashtable'
            required = $true
            properties = @{
                type = @{
                    description = 'Provider type'
                    type = 'string'
                    enum = $script:ValidProviderTypes
                    default = 'openai'
                    envVar = 'LLMWF_PROVIDER_TYPE'
                }
                endpoint = @{
                    description = 'API endpoint URL'
                    type = 'uri'
                    required = $true
                    default = 'https://api.openai.com/v1'
                    envVar = 'LLMWF_PROVIDER_ENDPOINT'
                }
                model = @{
                    description = 'Model identifier'
                    type = 'string'
                    required = $true
                    default = 'gpt-4'
                    envVar = 'LLMWF_PROVIDER_MODEL'
                }
                apiKey = @{
                    description = 'API authentication key'
                    type = 'securestring'
                    required = $false
                    secret = $true
                    envVar = 'LLMWF_PROVIDER_APIKEY'
                }
                timeout = @{
                    description = 'Request timeout in seconds'
                    type = 'integer'
                    min = 1
                    max = 3600
                    default = 60
                    envVar = 'LLMWF_PROVIDER_TIMEOUT'
                }
                maxTokens = @{
                    description = 'Maximum tokens per request'
                    type = 'integer'
                    min = 1
                    max = 128000
                    default = 4096
                    envVar = 'LLMWF_PROVIDER_MAXTOKENS'
                }
                temperature = @{
                    description = 'Sampling temperature'
                    type = 'double'
                    min = 0.0
                    max = 2.0
                    default = 0.7
                    envVar = 'LLMWF_PROVIDER_TEMPERATURE'
                }
            }
        }
        embedding = @{
            description = 'Embedding model settings'
            type = 'hashtable'
            required = $true
            properties = @{
                model = @{
                    description = 'Embedding model identifier'
                    type = 'string'
                    default = 'text-embedding-3-small'
                    envVar = 'LLMWF_EMBEDDING_MODEL'
                }
                dimensions = @{
                    description = 'Embedding vector dimensions'
                    type = 'integer'
                    min = 1
                    max = 3072
                    default = 1536
                    envVar = 'LLMWF_EMBEDDING_DIMENSIONS'
                }
                batchSize = @{
                    description = 'Batch processing size'
                    type = 'integer'
                    min = 1
                    max = 1000
                    default = 100
                    envVar = 'LLMWF_EMBEDDING_BATCHSIZE'
                }
                timeout = @{
                    description = 'Embedding request timeout'
                    type = 'integer'
                    min = 1
                    max = 3600
                    default = 120
                    envVar = 'LLMWF_EMBEDDING_TIMEOUT'
                }
            }
        }
        memory = @{
            description = 'Memory/palace settings'
            type = 'hashtable'
            required = $true
            properties = @{
                palacePath = @{
                    description = 'Path to memory palace storage'
                    type = 'string'
                    default = '.memorybridge/palace'
                    envVar = 'LLMWF_MEMORY_PALACEPATH'
                }
                maxContextTokens = @{
                    description = 'Maximum context window tokens'
                    type = 'integer'
                    min = 100
                    max = 128000
                    default = 8000
                    envVar = 'LLMWF_MEMORY_MAXCONTEXTTOKENS'
                }
                consolidationThreshold = @{
                    description = 'Similarity threshold for consolidation'
                    type = 'double'
                    min = 0.0
                    max = 1.0
                    default = 0.85
                    envVar = 'LLMWF_MEMORY_CONSOLIDATIONTHRESHOLD'
                }
                autoSync = @{
                    description = 'Enable automatic synchronization'
                    type = 'boolean'
                    default = $true
                    envVar = 'LLMWF_MEMORY_AUTOSYNC'
                }
                syncInterval = @{
                    description = 'Sync interval in seconds'
                    type = 'integer'
                    min = 10
                    max = 86400
                    default = 300
                    envVar = 'LLMWF_MEMORY_SYNCINTERVAL'
                }
            }
        }
        sync = @{
            description = 'Sync behavior settings'
            type = 'hashtable'
            required = $true
            properties = @{
                mode = @{
                    description = 'Synchronization mode'
                    type = 'string'
                    enum = @('bidirectional', 'upload-only', 'download-only', 'manual')
                    default = 'bidirectional'
                    envVar = 'LLMWF_SYNC_MODE'
                }
                conflictResolution = @{
                    description = 'Conflict resolution strategy'
                    type = 'string'
                    enum = @('timestamp', 'local-wins', 'remote-wins', 'manual')
                    default = 'timestamp'
                    envVar = 'LLMWF_SYNC_CONFLICTRESOLUTION'
                }
                retryAttempts = @{
                    description = 'Number of retry attempts'
                    type = 'integer'
                    min = 0
                    max = 10
                    default = 3
                    envVar = 'LLMWF_SYNC_RETRYATTEMPTS'
                }
                retryDelay = @{
                    description = 'Delay between retries in seconds'
                    type = 'integer'
                    min = 1
                    max = 300
                    default = 5
                    envVar = 'LLMWF_SYNC_RETRYDELAY'
                }
            }
        }
        logging = @{
            description = 'Logging configuration'
            type = 'hashtable'
            required = $true
            properties = @{
                level = @{
                    description = 'Minimum log level'
                    type = 'string'
                    enum = $script:ValidLogLevels
                    default = 'info'
                    envVar = 'LLMWF_LOGGING_LEVEL'
                }
                retentionDays = @{
                    description = 'Log retention period'
                    type = 'integer'
                    min = 1
                    max = 365
                    default = 30
                    envVar = 'LLMWF_LOGGING_RETENTIONDAYS'
                }
                maxFileSize = @{
                    description = 'Maximum log file size'
                    type = 'string'
                    pattern = '^\d+(KB|MB|GB)$'
                    default = '10MB'
                    envVar = 'LLMWF_LOGGING_MAXFILESIZE'
                }
                consoleOutput = @{
                    description = 'Enable console output'
                    type = 'boolean'
                    default = $true
                    envVar = 'LLMWF_LOGGING_CONSOLEOUTPUT'
                }
                structuredFormat = @{
                    description = 'Use structured logging format'
                    type = 'boolean'
                    default = $true
                    envVar = 'LLMWF_LOGGING_STRUCTUREDFORMAT'
                }
            }
        }
        execution = @{
            description = 'Execution mode settings'
            type = 'hashtable'
            required = $true
            properties = @{
                mode = @{
                    description = 'Current execution mode'
                    type = 'string'
                    enum = $script:ValidExecutionModes
                    default = 'interactive'
                    envVar = 'LLMWF_EXECUTION_MODE'
                }
                timeout = @{
                    description = 'Default operation timeout'
                    type = 'integer'
                    min = 1
                    max = 7200
                    default = 300
                    envVar = 'LLMWF_EXECUTION_TIMEOUT'
                }
                maxRetries = @{
                    description = 'Maximum retry attempts'
                    type = 'integer'
                    min = 0
                    max = 10
                    default = 3
                    envVar = 'LLMWF_EXECUTION_MAXRETRIES'
                }
                budgetTokens = @{
                    description = 'Token budget for operations'
                    type = 'integer'
                    min = 1000
                    max = 10000000
                    default = 100000
                    envVar = 'LLMWF_EXECUTION_BUDGETTOKENS'
                }
                budgetCost = @{
                    description = 'Cost budget in USD'
                    type = 'double'
                    min = 0.0
                    max = 1000.0
                    default = 10.00
                    envVar = 'LLMWF_EXECUTION_BUDGETCOST'
                }
                parallelTasks = @{
                    description = 'Maximum parallel tasks'
                    type = 'integer'
                    min = 1
                    max = 50
                    default = 5
                    envVar = 'LLMWF_EXECUTION_PARALLELTASKS'
                }
            }
        }
        security = @{
            description = 'Security settings'
            type = 'hashtable'
            required = $true
            properties = @{
                enableSecretScanning = @{
                    description = 'Enable secret scanning in inputs'
                    type = 'boolean'
                    default = $true
                    envVar = 'LLMWF_SECURITY_ENABLESECRETSCANNING'
                }
                encryptionEnabled = @{
                    description = 'Enable data encryption'
                    type = 'boolean'
                    default = $false
                    envVar = 'LLMWF_SECURITY_ENCRYPTIONENABLED'
                }
                allowedHosts = @{
                    description = 'List of allowed hosts'
                    type = 'array'
                    itemType = 'string'
                    default = @()
                    envVar = 'LLMWF_SECURITY_ALLOWEDHOSTS'
                }
                blockedHosts = @{
                    description = 'List of blocked hosts'
                    type = 'array'
                    itemType = 'string'
                    default = @()
                    envVar = 'LLMWF_SECURITY_BLOCKEDHOSTS'
                }
                requireApprovalFor = @{
                    description = 'Actions requiring approval'
                    type = 'array'
                    itemType = 'string'
                    default = @('delete', 'modify', 'execute')
                    envVar = 'LLMWF_SECURITY_REQUIREAPPROVALFOR'
                }
            }
        }
    }
}

<#
.SYNOPSIS
    Validates a single configuration value against its schema.

.DESCRIPTION
    Tests if a configuration value meets schema requirements including
    type checking, range validation, and enum constraints.

.PARAMETER Path
    The configuration path (e.g., 'provider.model').

.PARAMETER Value
    The value to validate.

.PARAMETER Schema
    The schema definition for this value.

.OUTPUTS
    PSCustomObject with validation results.

.EXAMPLE
    $schema = Get-ConfigSchema
    Test-ConfigValue -Path 'provider.timeout' -Value 60 -Schema $schema.provider.properties.timeout
#>
function Test-ConfigValue {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value,

        [Parameter(Mandatory = $true)]
        [hashtable]$Schema
    )

    $errors = @()
    $warnings = @()

    # Check if value is null and required
    if ($null -eq $Value) {
        if ($Schema.required -eq $true) {
            $errors += "Required value at '$Path' is null"
        }
        return [PSCustomObject]@{
            IsValid = ($errors.Count -eq 0)
            Errors = $errors
            Warnings = $warnings
            Path = $Path
            Value = $Value
        }
    }

    # Type validation
    $actualType = $Value.GetType().Name.ToLower()
    $expectedType = $Schema.type

    switch ($expectedType) {
        'string' {
            if ($Value -isnot [string]) {
                $errors += "Value at '$Path' must be a string, got $actualType"
            }
            # Pattern validation
            if ($Schema.pattern -and ($Value -is [string])) {
                if (-not ($Value -match $Schema.pattern)) {
                    $errors += "Value at '$Path' does not match pattern '$($Schema.pattern)'"
                }
            }
            # Enum validation
            if ($Schema.enum -and ($Value -is [string])) {
                if ($Schema.enum -notcontains $Value) {
                    $errors += "Value at '$Path' must be one of: $($Schema.enum -join ', ')"
                }
            }
        }
        'integer' {
            if ($Value -isnot [int] -and $Value -isnot [long]) {
                # Try to parse if string
                $parsed = 0
                if (-not ([int]::TryParse([string]$Value, [ref]$parsed))) {
                    $errors += "Value at '$Path' must be an integer, got $actualType"
                } else {
                    $Value = $parsed
                }
            }
            if ($Value -is [int] -or $Value -is [long]) {
                # Range validation
                if ($Schema.min -ne $null -and $Value -lt $Schema.min) {
                    $errors += "Value at '$Path' ($Value) is below minimum ($($Schema.min))"
                }
                if ($Schema.max -ne $null -and $Value -gt $Schema.max) {
                    $errors += "Value at '$Path' ($Value) exceeds maximum ($($Schema.max))"
                }
            }
        }
        'double' {
            $parsed = 0.0
            $isDouble = $Value -is [double] -or $Value -is [float] -or $Value -is [decimal]
            if (-not $isDouble) {
                if (-not ([double]::TryParse([string]$Value, [ref]$parsed))) {
                    $errors += "Value at '$Path' must be a number, got $actualType"
                } else {
                    $Value = $parsed
                    $isDouble = $true
                }
            }
            if ($isDouble) {
                if ($Schema.min -ne $null -and [double]$Value -lt $Schema.min) {
                    $errors += "Value at '$Path' ($Value) is below minimum ($($Schema.min))"
                }
                if ($Schema.max -ne $null -and [double]$Value -gt $Schema.max) {
                    $errors += "Value at '$Path' ($Value) exceeds maximum ($($Schema.max))"
                }
            }
        }
        'boolean' {
            if ($Value -isnot [bool]) {
                # Try to parse common boolean representations
                $boolStr = [string]$Value.ToString().ToLower()
                if ($boolStr -notin @('true', 'false', '1', '0', 'yes', 'no', 'on', 'off')) {
                    $errors += "Value at '$Path' must be a boolean, got $actualType"
                }
            }
        }
        'uri' {
            $uri = $null
            if (-not ([uri]::TryCreate([string]$Value, [urikind]::Absolute, [ref]$uri))) {
                $errors += "Value at '$Path' must be a valid URI, got '$Value'"
            }
        }
        'array' {
            if ($Value -isnot [array]) {
                $errors += "Value at '$Path' must be an array, got $actualType"
            }
        }
        'hashtable' {
            if ($Value -isnot [hashtable] -and $Value -isnot [System.Collections.Specialized.OrderedDictionary]) {
                $errors += "Value at '$Path' must be a hashtable, got $actualType"
            }
        }
        'securestring' {
            # Secure strings are valid as strings or SecureString objects
            if ($Value -isnot [string] -and $Value -isnot [System.Security.SecureString]) {
                $errors += "Value at '$Path' must be a string or secure string, got $actualType"
            }
        }
    }

    return [PSCustomObject]@{
        IsValid = ($errors.Count -eq 0)
        Errors = $errors
        Warnings = $warnings
        Path = $Path
        Value = $Value
    }
}

<#
.SYNOPSIS
    Checks if a key represents a secret value.

.DESCRIPTION
    Determines if a configuration key should be treated as a secret
    based on naming patterns and schema definitions.

.PARAMETER Key
    The configuration key name.

.PARAMETER Schema
    Optional schema definition for the key.

.OUTPUTS
    Boolean indicating if the key represents a secret.

.EXAMPLE
    Test-SecretKey -Key 'apiKey'
    True
#>
function Test-SecretKey {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $false)]
        [hashtable]$Schema = $null
    )

    # Check schema first
    if ($Schema -and $Schema.ContainsKey('secret')) {
        return $Schema.secret -eq $true
    }

    # Check against secret patterns
    $keyLower = $Key.ToLower()
    foreach ($pattern in $script:SecretPatterns) {
        if ($keyLower -like "*$pattern*") {
            return $true
        }
    }

    return $false
}

<#
.SYNOPSIS
    Masks secret values in configuration output.

.DESCRIPTION
    Creates a copy of configuration data with secret values masked
    to prevent accidental exposure in logs or displays.

.PARAMETER Config
    The configuration hashtable to mask.

.PARAMETER Schema
    Optional schema for determining secret keys.

.OUTPUTS
    Hashtable with masked secret values.

.EXAMPLE
    $masked = Protect-ConfigSecrets -Config $config
#>
function Protect-ConfigSecrets {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $false)]
        [hashtable]$Schema = $null
    )

    $masked = @{}
    $fullSchema = Get-ConfigSchema

    foreach ($key in $Config.Keys) {
        $value = $Config[$key]
        $keySchema = $null
        
        if ($Schema -and $Schema.ContainsKey($key)) {
            $keySchema = $Schema[$key]
        } elseif ($fullSchema.ContainsKey($key) -and $fullSchema[$key].ContainsKey('properties')) {
            $keySchema = $fullSchema[$key].properties
        }

        if ($value -is [hashtable]) {
            # Recursively mask nested hashtables
            $masked[$key] = Protect-ConfigSecrets -Config $value -Schema $keySchema
        } elseif (Test-SecretKey -Key $key -Schema $keySchema) {
            # Mask secret value
            if ($null -ne $value) {
                $masked[$key] = '***REDACTED***'
            } else {
                $masked[$key] = $null
            }
        } else {
            $masked[$key] = $value
        }
    }

    return $masked
}

<#
.SYNOPSIS
    Validates an execution mode.

.DESCRIPTION
    Checks if a given string is a valid execution mode.

.PARAMETER Mode
    The execution mode to validate.

.OUTPUTS
    Boolean indicating if the mode is valid.

.EXAMPLE
    Test-ExecutionMode -Mode 'interactive'
    True
#>
function Test-ExecutionMode {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    return $script:ValidExecutionModes -contains $Mode.ToLower()
}

# Export module members
Export-ModuleMember -Function @(
    'Get-DefaultConfig',
    'Get-ConfigSchema',
    'Test-ConfigValue',
    'Test-SecretKey',
    'Protect-ConfigSecrets',
    'Get-ValidExecutionModes',
    'Test-ExecutionMode'
)
