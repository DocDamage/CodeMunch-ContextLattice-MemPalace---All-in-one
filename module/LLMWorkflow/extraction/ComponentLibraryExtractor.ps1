#requires -Version 5.1
<#
.SYNOPSIS
    Component library extractor for LLM Workflow Structured Extraction Pipeline.

.DESCRIPTION
    Extracts structured metadata from UI component library source files including:
    - Component definitions and metadata
    - Props, types, and interfaces
    - Component composition patterns
    - Accessibility (A11y) patterns and ARIA implementations
    
    Supports multiple frontend frameworks: React (TSX/JSX), Vue, Svelte, and Mithril.
    
    This extractor implements the UI/Frontend Framework Pack specification
    for the LLM Workflow platform's structured extraction pipeline.

.NOTES
    File Name      : ComponentLibraryExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Frameworks     : React, Vue, Svelte, Mithril
#>

Set-StrictMode -Version Latest

# ============================================================================
# Script-level Constants and Patterns
# ============================================================================

# Supported component file extensions
$script:ComponentExtensions = @('.tsx', '.jsx', '.vue', '.svelte')

# Regex patterns for component extraction
$script:Patterns = @{
    # React/TypeScript patterns
    ReactComponent = '(?:export\s+(?:default\s+)?)?(?:function|const)\s+(?<name>[A-Z][a-zA-Z0-9_]*)\s*(?:<[^>]+>)?\s*\(|(?:class)\s+(?<name>[A-Z][a-zA-Z0-9_]*)\s+extends\s+(?:React\.)?Component'
    ReactArrowComponent = 'export\s+(?:default\s+)?const\s+(?<name>[A-Z][a-zA-Z0-9_]*)\s*[=:]\s*(?:<[^>]+>)?\s*\('
    ReactFC = '(?:export\s+(?:default\s+)?)?const\s+(?<name>[A-Z][a-zA-Z0-9_]*)\s*[=:]\s*React\.FC|FunctionComponent'
    Interface = '(?:export\s+)?interface\s+(?<name>[A-Z][a-zA-Z0-9_]*)\s*(?:extends\s+[^{]+)?\{'
    TypeAlias = '(?:export\s+)?type\s+(?<name>[A-Z][a-zA-Z0-9_]*)\s*=\s*\{'
    PropsType = 'type\s+(?<name>[A-Z][a-zA-Z0-9_]*Props)\s*=|interface\s+(?<name>[A-Z][a-zA-Z0-9_]*Props)\s*\{'
    PropField = '^\s*(?<name>[a-z][a-zA-Z0-9_]*)\??\s*:\s*(?<type>[^;]+)'
    JSDocComment = '/\*\*(?<content>[\s\S]*?)\*/'
    JSDocLine = '^\s*\*\s*(?<text>.*)$'
    
    # Vue patterns
    VueComponent = '<script[^>]*>.*?export\s+default\s*\{'
    VueDefineComponent = 'defineComponent\s*\(\s*\{'
    VueProps = 'props\s*:\s*\{'
    VueSetup = 'setup\s*\('
    VueTemplate = '<template[^>]*>(?<content>[\s\S]*?)</template>'
    
    # Svelte patterns  
    SvelteComponent = '<script[^>]*>(?<script>[\s\S]*?)</script>'
    SvelteProps = 'export\s+let\s+(?<name>[a-z][a-zA-Z0-9_]*)\s*(?::\s*(?<type>[^;=]+))?'
    
    # Mithril patterns
    MithrilComponent = '(?:const|var|let)\s+(?<name>[A-Z][a-zA-Z0-9_]*)\s*=\s*\{'
    MithrilView = 'view\s*:\s*function|view\s*\('
    MithrilAttrs = 'attrs\s*:\s*\{'
    
    # Accessibility patterns
    AriaAttribute = 'aria-(?<name>[a-z]+)={|"aria-(?<name>[a-z]+)"'
    RoleAttribute = 'role={|role="(?<value>[^"]*)"'
    TabIndex = 'tabIndex={|tabindex="'
    ScreenReaderOnly = 'sr-only|visually-hidden|screen-reader-only'
    KeyboardHandler = 'onKeyDown|onKeyUp|onKeyPress|@keydown|@keyup'
    FocusHandler = 'onFocus|onBlur|@focus|@blur'
    
    # Composition patterns
    ChildrenProp = 'children\??\s*:\s*(?:React\.)?Node|children\s*={'
    RenderProp = 'render\s*:\s*\(|render\??\s*:\s*\('
    SlotPattern = '<slot|v-slot|#default'
    HOC = '(?:with|enhance)[A-Z][a-zA-Z0-9_]*\(|function\s+(?:with|enhance)[A-Z]'
    ForwardRef = 'forwardRef|React\.forwardRef'
    
    # Documentation patterns
    StorybookStory = 'export\s+(?:const|let)\s+(?<name>[a-zA-Z][a-zA-Z0-9_]*)\s*:\s*Story'
    StoryMeta = 'const\s+meta\s*:\s*Meta'
    MDXDoc = '(?i)\.mdx$'
}

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Normalizes a type string by trimming whitespace and standardizing format.
.DESCRIPTION
    Internal helper to clean up type annotations extracted from component code.
.PARAMETER TypeString
    The type string to normalize.
.OUTPUTS
    System.String. Normalized type string.
#>
function ConvertTo-NormalizedType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeString
    )
    
    return $TypeString.Trim() -replace '\s+', ' ' -replace '^\s*\?\s*', ''
}

<#
.SYNOPSIS
    Extracts JSDoc comments from source content.
.DESCRIPTION
    Parses JSDoc-style comments (/** ... */) and extracts their content.
.PARAMETER Content
    The source content to parse.
.OUTPUTS
    System.Array. Array of documentation block objects with lineNumber and text.
#>
function Get-JSDocComments {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    $docs = @()
    $lines = $Content -split "`r?`n"
    $inDocBlock = $false
    $currentDoc = @()
    $startLine = 0
    $lineNumber = 0
    
    foreach ($line in $lines) {
        $lineNumber++
        
        if ($line -match '^\s*/\*\*') {
            $inDocBlock = $true
            $startLine = $lineNumber
            $currentDoc = @()
            # Remove opening /**
            $lineText = $line -replace '^\s*/\*\*\s*', ''
            if ($lineText) { $currentDoc += $lineText }
        }
        elseif ($inDocBlock -and $line -match '\*/') {
            # Remove closing */
            $lineText = $line -replace '\*/.*$', ''
            if ($lineText -match '^\s*\*\s*(.*)$') {
                $currentDoc += $matches[1]
            }
            elseif ($lineText.Trim()) {
                $currentDoc += $lineText.Trim()
            }
            
            $docs += @{
                lineNumber = $startLine
                text = ($currentDoc -join "`n").Trim()
            }
            $inDocBlock = $false
            $currentDoc = @()
        }
        elseif ($inDocBlock) {
            # Remove leading * if present
            if ($line -match '^\s*\*\s?(.*)$') {
                $currentDoc += $matches[1]
            }
            else {
                $currentDoc += $line.Trim()
            }
        }
    }
    
    return ,$docs
}

<#
.SYNOPSIS
    Finds the JSDoc comment associated with a specific line.
.DESCRIPTION
    Searches through extracted documentation blocks to find the one
    that immediately precedes the given line number.
.PARAMETER LineNumber
    The line number to find documentation for.
.PARAMETER DocumentationBlocks
    Array of documentation block objects from Get-JSDocComments.
.OUTPUTS
    System.String. The documentation text or $null.
#>
function Get-DocCommentForLine {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$LineNumber,
        
        [Parameter()]
        [array]$DocumentationBlocks = @()
    )
    
    if ($null -eq $DocumentationBlocks -or $DocumentationBlocks.Count -eq 0) {
        return $null
    }
    
    $closestDoc = $null
    $closestDistance = [int]::MaxValue
    
    foreach ($doc in $DocumentationBlocks) {
        $distance = $LineNumber - $doc.lineNumber
        if ($distance -gt 0 -and $distance -lt $closestDistance -and $distance -lt 20) {
            $closestDistance = $distance
            $closestDoc = $doc.text
        }
    }
    
    return $closestDoc
}

<#
.SYNOPSIS
    Creates a structured component element object.
.DESCRIPTION
    Factory function to create standardized component element objects.
.PARAMETER ElementType
    The type of element (component, prop, interface, accessibility, composition).
.PARAMETER Name
    The name of the element.
.PARAMETER LineNumber
    The line number where the element is defined.
.PARAMETER Properties
    Additional properties for the element.
.PARAMETER DocComment
    Associated documentation comment.
.PARAMETER SourceFile
    Path to the source file.
.OUTPUTS
    System.Collections.Hashtable. Structured element object.
#>
function New-ComponentElement {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('component', 'prop', 'interface', 'accessibility', 'composition', 'slot')]
        [string]$ElementType,
        
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter()]
        [int]$LineNumber = 0,
        
        [Parameter()]
        [hashtable]$Properties = @{},
        
        [Parameter()]
        [string]$DocComment = $null,
        
        [Parameter()]
        [string]$SourceFile = ''
    )
    
    $element = @{
        elementType = $ElementType
        name = $Name
        lineNumber = $LineNumber
        sourceFile = $SourceFile
        docComment = $DocComment
    }
    
    # Merge additional properties
    foreach ($key in $Properties.Keys) {
        $element[$key] = $Properties[$key]
    }
    
    return $element
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Extracts component definitions from source files.

.DESCRIPTION
    Parses component source files and extracts structured metadata including:
    - Component names and types
    - Framework detection (React, Vue, Svelte, Mithril)
    - Component metadata and documentation

.PARAMETER Path
    Path to the source file to parse.

.PARAMETER Content
    Source content string (alternative to Path).

.PARAMETER Framework
    Optional framework hint (react, vue, svelte, mithril).

.OUTPUTS
    System.Array. Array of component definition objects.

.EXAMPLE
    $components = Get-ComponentDefinitions -Path "components/Button.tsx"

.EXAMPLE
    $content = Get-Content -Raw "Button.tsx"
    $components = Get-ComponentDefinitions -Content $content -Framework react
#>
function Get-ComponentDefinitions {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [Alias('FilePath')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('react', 'vue', 'svelte', 'mithril', 'auto')]
        [string]$Framework = 'auto'
    )
    
    try {
        # Load content from file if path provided
        $filePath = ''
        $rawContent = ''
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Write-Verbose "[Get-ComponentDefinitions] Loading file: $Path"
            
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return @()
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
            return @()
        }
        
        Write-Verbose "[Get-ComponentDefinitions] Parsing content ($($rawContent.Length) chars)"
        
        # Auto-detect framework if needed
        if ($Framework -eq 'auto') {
            if ($filePath -match '\.tsx?$|\.jsx?$') { $Framework = 'react' }
            elseif ($filePath -match '\.vue$') { $Framework = 'vue' }
            elseif ($filePath -match '\.svelte$') { $Framework = 'svelte' }
            else { $Framework = 'react' }  # Default fallback
        }
        
        $components = @()
        $lines = $rawContent -split "`r?`n"
        $lineNumber = 0
        $docBlocks = Get-JSDocComments -Content $rawContent
        
        switch ($Framework) {
            'react' {
                # Parse React function components
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    $line = $lines[$i]
                    $lineNumber = $i + 1
                    
                    # Match function components
                    if ($line -match $script:Patterns.ReactComponent -or 
                        $line -match $script:Patterns.ReactArrowComponent -or
                        $line -match $script:Patterns.ReactFC) {
                        
                        $componentName = $matches['name']
                        $docComment = Get-DocCommentForLine -LineNumber $lineNumber -DocumentationBlocks $docBlocks
                        
                        $components += New-ComponentElement `
                            -ElementType 'component' `
                            -Name $componentName `
                            -LineNumber $lineNumber `
                            -Properties @{
                                framework = 'react'
                                componentType = 'function'
                            } `
                            -DocComment $docComment `
                            -SourceFile $filePath
                        
                        Write-Verbose "[Get-ComponentDefinitions] Found React component: $componentName"
                    }
                }
            }
            
            'vue' {
                # Parse Vue components - look for component name in filename or default export
                $componentName = if ($filePath) { 
                    [System.IO.Path]::GetFileNameWithoutExtension($filePath) 
                } else { 'VueComponent' }
                
                if ($rawContent -match $script:Patterns.VueComponent -or
                    $rawContent -match $script:Patterns.VueDefineComponent) {
                    
                    $docComment = Get-DocCommentForLine -LineNumber 1 -DocumentationBlocks $docBlocks
                    
                    $components += New-ComponentElement `
                        -ElementType 'component' `
                        -Name $componentName `
                        -LineNumber 1 `
                        -Properties @{
                            framework = 'vue'
                            componentType = 'options-api'
                        } `
                        -DocComment $docComment `
                        -SourceFile $filePath
                    
                    Write-Verbose "[Get-ComponentDefinitions] Found Vue component: $componentName"
                }
            }
            
            'svelte' {
                # Parse Svelte components
                $componentName = if ($filePath) { 
                    [System.IO.Path]::GetFileNameWithoutExtension($filePath) 
                } else { 'SvelteComponent' }
                
                if ($rawContent -match $script:Patterns.SvelteComponent) {
                    $docComment = Get-DocCommentForLine -LineNumber 1 -DocumentationBlocks $docBlocks
                    
                    $components += New-ComponentElement `
                        -ElementType 'component' `
                        -Name $componentName `
                        -LineNumber 1 `
                        -Properties @{
                            framework = 'svelte'
                            componentType = 'svelte-component'
                        } `
                        -DocComment $docComment `
                        -SourceFile $filePath
                    
                    Write-Verbose "[Get-ComponentDefinitions] Found Svelte component: $componentName"
                }
            }
            
            'mithril' {
                # Parse Mithril components
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    $line = $lines[$i]
                    $lineNumber = $i + 1
                    
                    if ($line -match $script:Patterns.MithrilComponent -and 
                        ($rawContent -match $script:Patterns.MithrilView)) {
                        
                        $componentName = $matches['name']
                        $docComment = Get-DocCommentForLine -LineNumber $lineNumber -DocumentationBlocks $docBlocks
                        
                        $components += New-ComponentElement `
                            -ElementType 'component' `
                            -Name $componentName `
                            -LineNumber $lineNumber `
                            -Properties @{
                                framework = 'mithril'
                                componentType = 'object'
                            } `
                            -DocComment $docComment `
                            -SourceFile $filePath
                        
                        Write-Verbose "[Get-ComponentDefinitions] Found Mithril component: $componentName"
                    }
                }
            }
        }
        
        Write-Verbose "[Get-ComponentDefinitions] Found $($components.Count) components"
        return ,$components
    }
    catch {
        Write-Error "[Get-ComponentDefinitions] Failed to extract components: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts props and TypeScript interfaces from component files.

.DESCRIPTION
    Parses component source files and extracts:
    - Prop type definitions (TypeScript interfaces, type aliases)
    - Individual prop fields with their types
    - Optional/required status
    - Default values

.PARAMETER Path
    Path to the source file to parse.

.PARAMETER Content
    Source content string (alternative to Path).

.OUTPUTS
    System.Array. Array of prop definition objects.

.EXAMPLE
    $props = Get-ComponentProps -Path "components/Button.tsx"
#>
function Get-ComponentProps {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        $rawContent = if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return @()
            }
            Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        } else { $Content }
        
        if ([string]::IsNullOrWhiteSpace($rawContent)) {
            return @()
        }
        
        $props = @()
        $lines = $rawContent -split "`r?`n"
        $inInterface = $false
        $currentInterface = ''
        $braceDepth = 0
        $lineNumber = 0
        $interfaceStartLine = 0
        
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $lineNumber = $i + 1
            
            # Detect interface start
            if ($line -match $script:Patterns.Interface) {
                $inInterface = $true
                $currentInterface = $matches['name']
                $interfaceStartLine = $lineNumber
                $braceDepth = 1
                continue
            }
            
            # Detect type alias for props
            if ($line -match $script:Patterns.TypeAlias) {
                $typeName = $matches['name']
                $braceDepth = 1
                $inInterface = $true
                $currentInterface = $typeName
                $interfaceStartLine = $lineNumber
                continue
            }
            
            if ($inInterface) {
                # Track brace depth
                $braceDepth += ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
                $braceDepth -= ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count
                
                # Parse prop field
                if ($line -match $script:Patterns.PropField) {
                    $propName = $matches['name']
                    $propType = ConvertTo-NormalizedType -TypeString $matches['type']
                    $isOptional = $line -match '\?\s*:'
                    $hasDefault = $line -match '\?\s*:\s*[^;]+\s+//\s*default:'
                    
                    $defaultValue = $null
                    if ($line -match '//\s*default:\s*(.+)$') {
                        $defaultValue = $matches[1].Trim()
                    }
                    
                    $props += @{
                        name = $propName
                        type = $propType
                        interface = $currentInterface
                        isOptional = $isOptional
                        hasDefault = $hasDefault
                        defaultValue = $defaultValue
                        lineNumber = $lineNumber
                        interfaceStartLine = $interfaceStartLine
                    }
                    
                    Write-Verbose "[Get-ComponentProps] Found prop: $propName ($propType)"
                }
                
                # Exit interface when braces close
                if ($braceDepth -le 0) {
                    $inInterface = $false
                    $currentInterface = ''
                }
            }
        }
        
        # Also check for Svelte props
        if ($rawContent -match $script:Patterns.SvelteComponent) {
            $svelteMatches = [regex]::Matches($rawContent, $script:Patterns.SvelteProps)
            foreach ($match in $svelteMatches) {
                $props += @{
                    name = $match.Groups['name'].Value
                    type = if ($match.Groups['type'].Success) { 
                        ConvertTo-NormalizedType -TypeString $match.Groups['type'].Value 
                    } else { 'any' }
                    interface = 'SvelteProps'
                    isOptional = $true
                    lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
                }
            }
        }
        
        return ,$props
    }
    catch {
        Write-Error "[Get-ComponentProps] Failed to extract props: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts component composition patterns from source files.

.DESCRIPTION
    Identifies composition patterns such as:
    - Children prop usage
    - Render props
    - Slots (Vue/Svelte)
    - Higher-Order Components
    - Forward refs

.PARAMETER Path
    Path to the source file to parse.

.PARAMETER Content
    Source content string (alternative to Path).

.OUTPUTS
    System.Array. Array of composition pattern objects.

.EXAMPLE
    $patterns = Get-CompositionPatterns -Path "components/Modal.tsx"
#>
function Get-CompositionPatterns {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        $rawContent = if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return @()
            }
            Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        } else { $Content }
        
        if ([string]::IsNullOrWhiteSpace($rawContent)) {
            return @()
        }
        
        $patterns = @()
        $lines = $rawContent -split "`r?`n"
        
        # Check for children prop
        if ($rawContent -match $script:Patterns.ChildrenProp) {
            $patterns += @{
                patternType = 'children'
                name = 'children'
                description = 'Uses children prop for content composition'
                lineNumber = ($rawContent -split $script:Patterns.ChildrenProp)[0] -split "`r?`n" | Measure-Object | Select-Object -ExpandProperty Count
            }
        }
        
        # Check for render props
        if ($rawContent -match $script:Patterns.RenderProp) {
            $patterns += @{
                patternType = 'render-prop'
                name = 'render'
                description = 'Uses render prop pattern for dynamic content'
                lineNumber = 1
            }
        }
        
        # Check for slots (Vue/Svelte)
        if ($rawContent -match $script:Patterns.SlotPattern) {
            $slotMatches = [regex]::Matches($rawContent, '<slot\s+name=["\']([^"\']+)')
            if ($slotMatches.Count -eq 0) {
                $slotMatches = [regex]::Matches($rawContent, 'v-slot:(\w+)')
            }
            if ($slotMatches.Count -eq 0) {
                $slotMatches = [regex]::Matches($rawContent, '#(\w+)')
            }
            
            foreach ($match in $slotMatches) {
                $slotName = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { 'default' }
                $patterns += @{
                    patternType = 'slot'
                    name = $slotName
                    description = "Named slot: $slotName"
                    lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
                }
            }
            
            if ($slotMatches.Count -eq 0 -and $rawContent -match $script:Patterns.SlotPattern) {
                $patterns += @{
                    patternType = 'slot'
                    name = 'default'
                    description = 'Uses default slot for content projection'
                    lineNumber = 1
                }
            }
        }
        
        # Check for HOC
        if ($rawContent -match $script:Patterns.HOC) {
            $patterns += @{
                patternType = 'hoc'
                name = 'higher-order-component'
                description = 'Higher-Order Component pattern detected'
                lineNumber = 1
            }
        }
        
        # Check for forwardRef
        if ($rawContent -match $script:Patterns.ForwardRef) {
            $patterns += @{
                patternType = 'forward-ref'
                name = 'forwardRef'
                description = 'Uses React.forwardRef for ref forwarding'
                lineNumber = 1
            }
        }
        
        return ,$patterns
    }
    catch {
        Write-Error "[Get-CompositionPatterns] Failed to extract composition patterns: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts accessibility (A11y) patterns from component files.

.DESCRIPTION
    Identifies accessibility implementations including:
    - ARIA attributes
    - Role definitions
    - Keyboard event handlers
    - Focus management
    - Screen reader only content

.PARAMETER Path
    Path to the source file to parse.

.PARAMETER Content
    Source content string (alternative to Path).

.OUTPUTS
    System.Array. Array of accessibility pattern objects.

.EXAMPLE
    $a11y = Get-AccessibilityPatterns -Path "components/Button.tsx"
#>
function Get-AccessibilityPatterns {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        $rawContent = if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return @()
            }
            Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        } else { $Content }
        
        if ([string]::IsNullOrWhiteSpace($rawContent)) {
            return @()
        }
        
        $patterns = @()
        
        # Extract ARIA attributes
        $ariaMatches = [regex]::Matches($rawContent, 'aria-(\w+)={[^}]+}|aria-(\w+)="[^"]*"')
        foreach ($match in $ariaMatches) {
            $ariaName = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
            $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
            
            $patterns += @{
                patternType = 'aria-attribute'
                name = "aria-$ariaName"
                description = "ARIA attribute: aria-$ariaName"
                lineNumber = $lineNumber
            }
        }
        
        # Extract roles
        $roleMatches = [regex]::Matches($rawContent, 'role={["\'']?([^}"\'']+)["\'']?}|role="([^"]*)"')
        foreach ($match in $roleMatches) {
            $roleValue = if ($match.Groups[1].Success -and $match.Groups[1].Value) { 
                $match.Groups[1].Value 
            } else { 
                $match.Groups[2].Value 
            }
            if ($roleValue) {
                $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
                
                $patterns += @{
                    patternType = 'role'
                    name = $roleValue
                    description = "Semantic role: $roleValue"
                    lineNumber = $lineNumber
                }
            }
        }
        
        # Check for keyboard handlers
        $keyboardMatches = [regex]::Matches($rawContent, '(onKeyDown|onKeyUp|onKeyPress|@keydown|@keyup)\s*=\s*{?([^\s},]+)')
        foreach ($match in $keyboardMatches) {
            $eventName = $match.Groups[1].Value
            $handlerName = $match.Groups[2].Value
            $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
            
            $patterns += @{
                patternType = 'keyboard-handler'
                name = $eventName
                description = "Keyboard event handler: $handlerName"
                lineNumber = $lineNumber
            }
        }
        
        # Check for focus handlers
        $focusMatches = [regex]::Matches($rawContent, '(onFocus|onBlur|@focus|@blur)\s*=\s*{?([^\s},]+)')
        foreach ($match in $focusMatches) {
            $eventName = $match.Groups[1].Value
            $handlerName = $match.Groups[2].Value
            $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
            
            $patterns += @{
                patternType = 'focus-handler'
                name = $eventName
                description = "Focus management handler: $handlerName"
                lineNumber = $lineNumber
            }
        }
        
        # Check for screen reader only content
        if ($rawContent -match $script:Patterns.ScreenReaderOnly) {
            $srMatches = [regex]::Matches($rawContent, 'className=["\''][^"\'']*(sr-only|visually-hidden|screen-reader-only)')
            foreach ($match in $srMatches) {
                $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
                
                $patterns += @{
                    patternType = 'screen-reader'
                    name = 'screen-reader-only'
                    description = 'Screen reader only content'
                    lineNumber = $lineNumber
                }
            }
        }
        
        # Check for tabIndex
        $tabIndexMatches = [regex]::Matches($rawContent, 'tabIndex={(-?\d+)}|tabindex="(-?\d+)"')
        foreach ($match in $tabIndexMatches) {
            $tabValue = if ($match.Groups[1].Success -and $match.Groups[1].Value) { 
                $match.Groups[1].Value 
            } else { 
                $match.Groups[2].Value 
            }
            $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
            
            $patterns += @{
                patternType = 'tabindex'
                name = "tabindex-$tabValue"
                description = "Tab index: $tabValue"
                lineNumber = $lineNumber
            }
        }
        
        return ,$patterns
    }
    catch {
        Write-Error "[Get-AccessibilityPatterns] Failed to extract accessibility patterns: $_"
        return @()
    }
}

# Export functions
Export-ModuleMember -Function Get-ComponentDefinitions, Get-ComponentProps, Get-CompositionPatterns, Get-AccessibilityPatterns
