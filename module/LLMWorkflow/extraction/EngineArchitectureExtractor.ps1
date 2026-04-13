#requires -Version 5.1
<#
.SYNOPSIS
    Engine architecture extractor for LLM Workflow Structured Extraction Pipeline.

.DESCRIPTION
    Parses game engine source files (C++, header files) and extracts structured metadata including:
    - Component system patterns (ECS, component-based architecture)
    - Scene graph structures (hierarchy, nodes, transforms)
    - Entity management (creation, destruction, pooling)
    - Engine service patterns (subsystems, managers, services)
    
    This extractor implements engine reference pack extraction for sources
    like Torque3D, Stingray, OGRE, and other game engine architectures.

.NOTES
    File Name      : EngineArchitectureExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Pack Support   : engine-reference
#>

Set-StrictMode -Version Latest

# ============================================================================
# Script-level Constants and Patterns
# ============================================================================

# Engine architecture pattern detection
$script:EnginePatterns = @{
    # Component system patterns
    ComponentClass = '(?:class|struct)\s+(?<name>\w+)(?:Component|Entity|Object)'
    ComponentRegistration = '(?:registerComponent|addComponent|REGISTER_COMPONENT)'
    ComponentQuery = '(?:getComponent|findComponent|hasComponent|query<)'
    ECSArchetype = '(?:Archetype|Chunk|EntityManager|World)'
    
    # Scene graph patterns
    SceneNode = '(?:class|struct)\s+(?<name>\w+)(?:Node|SceneNode|GraphNode)'
    TransformPattern = '(?:Transform|Position|Rotation|Scale|Matrix|LocalToWorld)'
    HierarchyPattern = '(?:parent|children|siblings|attachTo|detach)'
    SceneTraversal = '(?:traverse|visit|forEach|update|render)'
    
    # Entity management patterns
    EntityClass = '(?:class|struct)\s+(?<name>\w+)(?:Entity|GameObject|Actor)'
    EntityId = '(?:EntityId|EntityHandle|ObjectId|GameObjectID)'
    EntityPool = '(?:EntityPool|ObjectPool|createEntity|destroyEntity)'
    EntityFactory = '(?:EntityFactory|GameObjectFactory|createFromPrefab)'
    
    # Engine service patterns
    ServiceBase = '(?:class|struct)\s+(?<name>\w+)(?:Service|System|Manager|Subsystem)'
    ServiceRegistration = '(?:registerService|addSystem|getService|g[A-Z]\w+(?:Service|System|Manager))'
    ServiceInterface = '(?:IService|ISystem|IManager|ServiceInterface)'
    InitializePattern = '(?:initialize|startup|init|onInit|begin)'
    UpdatePattern = '(?:update|tick|step|onUpdate|process)\s*\('
    ShutdownPattern = '(?:shutdown|cleanup|destroy|onShutdown|end)'
}

# Language-specific patterns for C++
$script:CppPatterns = @{
    ClassDef = '^\s*(?:class|struct)\s+(?<name>\w+)(?:\s*:\s*(?<inheritance>(?:public|private|protected)\s+\w+(?:\s*,\s*(?:public|private|protected)\s+\w+)*))?'
    MethodDef = '^\s*(?:virtual\s+)?(?:static\s+)?(?:inline\s+)?(?:const\s+)?(?<ret>[\w:<>,\s*&*]+)?\s+(?<name>\w+)\s*\((?<params>[^)]*)\)(?:\s*const)?(?:\s*=\s*0)?\s*;?'
    TemplateClass = '^\s*template\s*<[^>]+>\s*(?:class|struct)\s+(?<name>\w+)'
    Namespace = '^\s*namespace\s+(?<name>\w+)\s*{'
    Include = '^\s*#include\s+["<](?<path>[^">]+)[">]'
    ForwardDecl = '^\s*(?:class|struct)\s+(?<name>\w+)\s*;'
    MacroDef = '^\s*#define\s+(?<name>\w+)(?:\((?<params>[^)]*)\))?'
    Typedef = '^\s*typedef\s+(?<type>[\w<>:,\s*&*]+)\s+(?<name>\w+)'
    UsingAlias = '^\s*using\s+(?<name>\w+)\s*=\s*(?<type>.+)'
}

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Detects the source language from file extension.
.DESCRIPTION
    Analyzes the file extension to determine if it's C++, header, or other
    engine source code.
.PARAMETER Path
    The file path to analyze.
.OUTPUTS
    System.String. Language identifier (cpp, header, unknown).
#>
function Get-EngineSourceLanguage {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    $extension = [System.IO.Path]::GetExtension($Path).ToLower()
    
    switch ($extension) {
        '.cpp' { return 'cpp' }
        '.cc' { return 'cpp' }
        '.cxx' { return 'cpp' }
        '.h' { return 'header' }
        '.hpp' { return 'header' }
        '.hxx' { return 'header' }
        '.inl' { return 'header' }
        default { return 'unknown' }
    }
}

<#
.SYNOPSIS
    Creates a structured engine element object following the output schema.
.DESCRIPTION
    Factory function to create standardized engine architecture element objects.
.PARAMETER ElementType
    The type of element (component, sceneNode, entity, service).
.PARAMETER Name
    The name of the element.
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
function New-EngineElement {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('component', 'sceneNode', 'entity', 'service', 'system', 'manager')]
        [string]$ElementType,
        
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
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
        lineNumber = $LineNumber
        properties = $Properties
        codeSnippet = $CodeSnippet
        sourceFile = $SourceFile
        extractedAt = [DateTime]::UtcNow.ToString("o")
    }
}

<#
.SYNOPSIS
    Extracts C++ class definitions from content.
.DESCRIPTION
    Parses C++ source code and extracts class definitions including
    inheritance and template parameters.
.PARAMETER Content
    The C++ source content.
.OUTPUTS
    System.Array. Array of class definition objects.
#>
function Get-CppClassDefinitions {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    $classes = @()
    $lines = $Content -split "`r?`n"
    $lineNumber = 0
    
    foreach ($line in $lines) {
        $lineNumber++
        
        # Check for template class
        if ($line -match $script:CppPatterns.TemplateClass) {
            $classes += @{
                name = $matches['name']
                isTemplate = $true
                lineNumber = $lineNumber
                inheritance = @()
                isStruct = $line -match '\bstruct\b'
            }
            continue
        }
        
        # Check for regular class
        if ($line -match $script:CppPatterns.ClassDef) {
            $className = $matches['name']
            $inheritance = @()
            
            if ($matches['inheritance']) {
                $inheritParts = $matches['inheritance'] -split '\s*,\s*'
                foreach ($part in $inheritParts) {
                    if ($part -match '(?:public|private|protected)\s+(\w+)') {
                        $inheritance += $matches[1]
                    }
                }
            }
            
            $classes += @{
                name = $className
                isTemplate = $false
                lineNumber = $lineNumber
                inheritance = $inheritance
                isStruct = $line -match '\bstruct\b'
            }
        }
    }
    
    return ,$classes
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Main entry point for engine architecture extraction.

.DESCRIPTION
    Parses an engine source file and returns structured extraction
    with all architecture patterns (components, scene graphs, entities, services).

.PARAMETER Path
    Path to the source file to parse.

.PARAMETER Content
    Source content string (alternative to Path).

.PARAMETER IncludeRawContent
    If specified, includes the raw file content in the output.

.OUTPUTS
    System.Collections.Hashtable. Complete extraction with elements array and metadata.

.EXAMPLE
    $result = Invoke-EngineArchitectureExtract -Path "./Engine/Entity.cpp"

.EXAMPLE
    $content = Get-Content -Raw "SceneManager.h"
    $result = Invoke-EngineArchitectureExtract -Content $content
#>
function Invoke-EngineArchitectureExtract {
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
            Write-Verbose "[Invoke-EngineArchitectureExtract] Loading file: $Path"
            
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
        
        Write-Verbose "[Invoke-EngineArchitectureExtract] Parsing engine patterns ($($rawContent.Length) chars)"
        
        # Detect language
        $language = Get-EngineSourceLanguage -Path $filePath
        
        # Build elements collection
        $elements = @()
        
        # Extract component system patterns
        $components = Get-ComponentSystemPatterns -Content $rawContent
        foreach ($component in $components) {
            $elements += New-EngineElement `
                -ElementType 'component' `
                -Name $component.name `
                -LineNumber $component.lineNumber `
                -Properties $component.properties `
                -CodeSnippet $component.codeSnippet `
                -SourceFile $filePath
        }
        
        # Extract scene graph structures
        $sceneNodes = Get-SceneGraphStructures -Content $rawContent
        foreach ($node in $sceneNodes) {
            $elements += New-EngineElement `
                -ElementType 'sceneNode' `
                -Name $node.name `
                -LineNumber $node.lineNumber `
                -Properties $node.properties `
                -CodeSnippet $node.codeSnippet `
                -SourceFile $filePath
        }
        
        # Extract entity management
        $entities = Get-EntityManagement -Content $rawContent
        foreach ($entity in $entities) {
            $elements += New-EngineElement `
                -ElementType 'entity' `
                -Name $entity.name `
                -LineNumber $entity.lineNumber `
                -Properties $entity.properties `
                -CodeSnippet $entity.codeSnippet `
                -SourceFile $filePath
        }
        
        # Extract engine service patterns
        $services = Get-EngineServicePatterns -Content $rawContent
        foreach ($service in $services) {
            $elements += New-EngineElement `
                -ElementType 'service' `
                -Name $service.name `
                -LineNumber $service.lineNumber `
                -Properties $service.properties `
                -CodeSnippet $service.codeSnippet `
                -SourceFile $filePath
        }
        
        # Build final result
        $result = @{
            fileType = 'engineArchitecture'
            filePath = $filePath
            language = $language
            elements = $elements
            elementCounts = @{
                component = ($elements | Where-Object { $_.elementType -eq 'component' }).Count
                sceneNode = ($elements | Where-Object { $_.elementType -eq 'sceneNode' }).Count
                entity = ($elements | Where-Object { $_.elementType -eq 'entity' }).Count
                service = ($elements | Where-Object { $_.elementType -eq 'service' }).Count
            }
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        if ($IncludeRawContent) {
            $result.rawContent = $rawContent
        }
        
        Write-Verbose "[Invoke-EngineArchitectureExtract] Extraction complete: $($elements.Count) elements extracted"
        
        return $result
    }
    catch {
        Write-Error "[Invoke-EngineArchitectureExtract] Failed to extract engine patterns: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Extracts component system patterns from source content.

.DESCRIPTION
    Parses source code to identify component system patterns including
    ECS (Entity Component System) implementations, component registration,
    and component query mechanisms.

.PARAMETER Content
    The source content to parse.

.OUTPUTS
    System.Array. Array of component pattern objects with name, subtype, properties, etc.

.EXAMPLE
    $components = Get-ComponentSystemPatterns -Content $cppContent
#>
function Get-ComponentSystemPatterns {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        $components = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Component class patterns
            if ($line -match $script:EnginePatterns.ComponentClass) {
                $components += @{
                    name = $matches['name']
                    subtype = 'componentClass'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'componentDefinition'
                        hasInheritance = $line -match ':'
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Component registration patterns
            if ($line -match $script:EnginePatterns.ComponentRegistration) {
                $components += @{
                    name = 'ComponentRegistration'
                    subtype = 'registration'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'componentRegistration'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Component query patterns
            if ($line -match $script:EnginePatterns.ComponentQuery) {
                $components += @{
                    name = 'ComponentQuery'
                    subtype = 'query'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'componentQuery'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # ECS archetype patterns
            if ($line -match $script:EnginePatterns.ECSArchetype) {
                $components += @{
                    name = 'ECSArchetype'
                    subtype = 'ecs'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'ecsPattern'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
        }
        
        Write-Verbose "[Get-ComponentSystemPatterns] Found $($components.Count) component patterns"
        return ,$components
    }
}

<#
.SYNOPSIS
    Extracts scene graph structures from source content.

.DESCRIPTION
    Parses source code to identify scene graph structures including
    node hierarchies, transform patterns, and traversal mechanisms.

.PARAMETER Content
    The source content to parse.

.OUTPUTS
    System.Array. Array of scene graph pattern objects.

.EXAMPLE
    $sceneNodes = Get-SceneGraphStructures -Content $cppContent
#>
function Get-SceneGraphStructures {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        $sceneNodes = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Scene node class patterns
            if ($line -match $script:EnginePatterns.SceneNode) {
                $sceneNodes += @{
                    name = $matches['name']
                    subtype = 'sceneNode'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'nodeDefinition'
                        isSceneNode = $true
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Transform patterns
            if ($line -match $script:EnginePatterns.TransformPattern) {
                $sceneNodes += @{
                    name = 'Transform'
                    subtype = 'transform'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'transformProperty'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Hierarchy patterns
            if ($line -match $script:EnginePatterns.HierarchyPattern) {
                $sceneNodes += @{
                    name = 'Hierarchy'
                    subtype = 'hierarchy'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'hierarchyRelation'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Scene traversal patterns
            if ($line -match $script:EnginePatterns.SceneTraversal) {
                $sceneNodes += @{
                    name = 'SceneTraversal'
                    subtype = 'traversal'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'traversalMethod'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
        }
        
        Write-Verbose "[Get-SceneGraphStructures] Found $($sceneNodes.Count) scene graph patterns"
        return ,$sceneNodes
    }
}

<#
.SYNOPSIS
    Extracts entity management patterns from source content.

.DESCRIPTION
    Parses source code to identify entity management patterns including
    entity creation/destruction, entity IDs/handles, and object pooling.

.PARAMETER Content
    The source content to parse.

.OUTPUTS
    System.Array. Array of entity management pattern objects.

.EXAMPLE
    $entities = Get-EntityManagement -Content $cppContent
#>
function Get-EntityManagement {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        $entities = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Entity class patterns
            if ($line -match $script:EnginePatterns.EntityClass) {
                $entities += @{
                    name = $matches['name']
                    subtype = 'entityClass'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'entityDefinition'
                        isEntity = $true
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Entity ID patterns
            if ($line -match $script:EnginePatterns.EntityId) {
                $entities += @{
                    name = 'EntityId'
                    subtype = 'identifier'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'entityIdentifier'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Entity pool patterns
            if ($line -match $script:EnginePatterns.EntityPool) {
                $entities += @{
                    name = 'EntityPool'
                    subtype = 'pooling'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'entityPooling'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Entity factory patterns
            if ($line -match $script:EnginePatterns.EntityFactory) {
                $entities += @{
                    name = 'EntityFactory'
                    subtype = 'factory'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'entityFactory'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
        }
        
        Write-Verbose "[Get-EntityManagement] Found $($entities.Count) entity management patterns"
        return ,$entities
    }
}

<#
.SYNOPSIS
    Extracts engine service patterns from source content.

.DESCRIPTION
    Parses source code to identify engine service patterns including
    service registration, subsystems, managers, and lifecycle hooks.

.PARAMETER Content
    The source content to parse.

.OUTPUTS
    System.Array. Array of engine service pattern objects.

.EXAMPLE
    $services = Get-EngineServicePatterns -Content $cppContent
#>
function Get-EngineServicePatterns {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        $services = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Service base class patterns
            if ($line -match $script:EnginePatterns.ServiceBase) {
                $services += @{
                    name = $matches['name']
                    subtype = 'serviceClass'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'serviceDefinition'
                        isService = $true
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Service registration patterns
            if ($line -match $script:EnginePatterns.ServiceRegistration) {
                $services += @{
                    name = 'ServiceRegistration'
                    subtype = 'registration'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'serviceRegistration'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Service interface patterns
            if ($line -match $script:EnginePatterns.ServiceInterface) {
                $services += @{
                    name = 'ServiceInterface'
                    subtype = 'interface'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'serviceInterface'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Initialize patterns
            if ($line -match $script:EnginePatterns.InitializePattern) {
                $services += @{
                    name = 'Initialize'
                    subtype = 'lifecycle'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'initializeHook'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Update patterns
            if ($line -match $script:EnginePatterns.UpdatePattern) {
                $services += @{
                    name = 'Update'
                    subtype = 'lifecycle'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'updateHook'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Shutdown patterns
            if ($line -match $script:EnginePatterns.ShutdownPattern) {
                $services += @{
                    name = 'Shutdown'
                    subtype = 'lifecycle'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'shutdownHook'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
        }
        
        Write-Verbose "[Get-EngineServicePatterns] Found $($services.Count) engine service patterns"
        return ,$services
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'Invoke-EngineArchitectureExtract',
    'Get-ComponentSystemPatterns',
    'Get-SceneGraphStructures',
    'Get-EntityManagement',
    'Get-EngineServicePatterns'
)
