#requires -Version 5.1
<#
.SYNOPSIS
    Design system extractor for LLM Workflow Structured Extraction Pipeline.

.DESCRIPTION
    Extracts structured metadata from design system source files including:
    - Design tokens (colors, typography, spacing)
    - Theme configurations
    - Style utilities
    - Documentation patterns
    
    Supports CSS/SCSS/Less files and various theme config formats including
    Tailwind CSS, CSS-in-JS, and design token JSON files.
    
    This extractor implements the UI/Frontend Framework Pack specification
    for the LLM Workflow platform's structured extraction pipeline.

.NOTES
    File Name      : DesignSystemExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Supports       : CSS, SCSS, Less, Tailwind CSS, Design Tokens
#>

Set-StrictMode -Version Latest

# ============================================================================
# Script-level Constants and Patterns
# ============================================================================

# Supported design system file extensions
$script:DesignSystemExtensions = @('.css', '.scss', '.less', '.json', '.js', '.ts')

# Regex patterns for design system extraction
$script:Patterns = @{
    # CSS Custom Properties (Variables)
    CSSVariable = '--(?<name>[\w-]+)\s*:\s*(?<value>[^;]+)'
    CSSVariableRef = 'var\s*\(\s*--(?<name>[\w-]+)'
    
    # Color values
    HexColor = '#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\b'
    RGBColor = 'rgba?\s*\(\s*\d+\s*,\s*\d+\s*,\s*\d+(?:\s*,\s*[\d.]+)?\s*\)'
    HSLColor = 'hsla?\s*\(\s*\d+\s*,\s*\d+%?\s*,\s*\d+%?(?:\s*,\s*[\d.]+)?\s*\)'
    NamedColor = '\b(?<color>transparent|currentColor|inherit|black|white|red|green|blue|yellow|purple|orange|pink|gray|grey|cyan|magenta|lime|maroon|navy|olive|silver|teal|aqua|fuchsia)\b'
    
    # Typography
    FontFamily = '(?:font-family|fontFamily)\s*[:=]\s*["\']?(?<value>[^;}"]+)'
    FontSize = '(?:font-size|fontSize)\s*[:=]\s*(?<value>[^;}")]*)'
    FontWeight = '(?:font-weight|fontWeight)\s*[:=]\s*(?<value>[^;}")]*)'
    LineHeight = '(?:line-height|lineHeight)\s*[:=]\s*(?<value>[^;}")]*)'
    LetterSpacing = '(?:letter-spacing|letterSpacing)\s*[:=]\s*(?<value>[^;}")]*)'
    
    # Spacing/Sizing
    SpacingValue = '(?<value>\d+(?:\.\d+)?(?:px|rem|em|%|vh|vw|ch|ex|cm|mm|in|pt|pc))'
    SpacingScale = '(?<name>space|spacing|size|gap|padding|margin)-(?<scale>xs|sm|md|lg|xl|2xl|3xl|4xl|5xl|6xl|7xl|8xl|9xl|\d+)'
    
    # Shadows
    BoxShadow = '(?:box-shadow|boxShadow)\s*[:=]\s*(?<value>[^;}")]+)'
    ShadowToken = '(?:shadow|elevation)-(?<name>[\w-]+)'
    
    # Border & Radius
    BorderRadius = '(?:border-radius|borderRadius)\s*[:=]\s*(?<value>[^;}")]+)'
    BorderWidth = '(?:border-width|borderWidth)\s*[:=]\s*(?<value>[^;}")]+)'
    RadiusScale = '(?:rounded|radius)-(?<scale>[\w-]+)'
    
    # Breakpoints
    MediaQuery = '@media\s*\((?<feature>[^)]+)\)'
    BreakpointToken = '(?:breakpoint|screen)-(?<name>[\w-]+)'
    
    # Tailwind specific
    TailwindConfig = 'tailwind\.config\.(js|ts)|module\.exports\s*=\s*\{'
    TailwindTheme = 'theme\s*:\s*\{'
    TailwindExtend = 'extend\s*:\s*\{'
    TailwindPlugin = 'plugin\s*\(\s*function'
    
    # Theme modes
    DarkMode = '(?:dark|light)\s*:\s*\{|@media\s*\(\s*prefers-color-scheme\s*:\s*dark\s*\)'
    ThemeVariant = '(?:theme|mode)\s*:\s*["\']?(?<variant>dark|light|auto|system)'
    
    # Animation
    AnimationName = '(?:animation|animation-name)\s*[:=]\s*(?<value>[^;}")]+)'
    Transition = '(?:transition|transition-property)\s*[:=]\s*(?<value>[^;}")]+)'
    Duration = '(?:duration|transition-duration)\s*[:=]\s*(?<value>[^;}")]+)'
    Easing = '(?:ease|easing|transition-timing-function)\s*[:=]\s*(?<value>[^;}")]+)'
    
    # Z-Index
    ZIndex = '(?:z-index|zIndex)\s*[:=]\s*(?<value>[^;}")]+)'
    
    # Opacity
    Opacity = '(?:opacity)\s*[:=]\s*(?<value>[^;}")]+)'
    
    # Documentation comments
    CSSComment = '/\*(?<content>[\s\S]*?)\*/'
    SCSSComment = '//\s*(?<text>.*)$'
    JSDocComment = '/\*\*(?<content>[\s\S]*?)\*/'
}

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Normalizes a color value to standard format.
.DESCRIPTION
    Internal helper to standardize color representations.
.PARAMETER ColorString
    The color string to normalize.
.OUTPUTS
    System.String. Normalized color string.
#>
function ConvertTo-NormalizedColor {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ColorString
    )
    
    $normalized = $ColorString.Trim().ToLower()
    
    # Expand shorthand hex
    if ($normalized -match '^#([0-9a-f])([0-9a-f])([0-9a-f])$') {
        return "#$($matches[1])$($matches[1])$($matches[2])$($matches[2])$($matches[3])$($matches[3])"
    }
    
    return $normalized
}

<#
.SYNOPSIS
    Categorizes a color by its hue/name.
.DESCRIPTION
    Internal helper to group colors into semantic categories.
.PARAMETER ColorString
    The color string to categorize.
.PARAMETER VariableName
    Optional CSS variable name for context.
.OUTPUTS
    System.String. Color category (primary, secondary, neutral, semantic, etc.).
#>
function Get-ColorCategory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ColorString,
        
        [Parameter()]
        [string]$VariableName = ''
    )
    
    # Check variable name hints
    if ($VariableName -match 'primary|brand|main') { return 'primary' }
    if ($VariableName -match 'secondary|accent') { return 'secondary' }
    if ($VariableName -match 'success|positive|green') { return 'success' }
    if ($VariableName -match 'error|danger|negative|red|alert') { return 'error' }
    if ($VariableName -match 'warning|warn|orange|amber|yellow') { return 'warning' }
    if ($VariableName -match 'info|blue|cyan') { return 'info' }
    if ($VariableName -match 'neutral|gray|grey|slate|zinc|stone') { return 'neutral' }
    if ($VariableName -match 'background|bg|surface') { return 'background' }
    if ($VariableName -match 'text|foreground|fg') { return 'text' }
    if ($VariableName -match 'border|divider|outline') { return 'border' }
    
    # Check color value hints
    $lower = $ColorString.ToLower()
    if ($lower -match 'red|rose|pink') { return 'warm' }
    if ($lower -match 'orange|amber|yellow') { return 'warm' }
    if ($lower -match 'green|emerald|teal|lime') { return 'cool' }
    if ($lower -match 'blue|indigo|cyan|sky') { return 'cool' }
    if ($lower -match 'purple|violet|fuchsia|magenta') { return 'cool' }
    
    return 'general'
}

<#
.SYNOPSIS
    Creates a structured design token element object.
.DESCRIPTION
    Factory function to create standardized design token objects.
.PARAMETER TokenType
    The type of token (color, typography, spacing, shadow, etc.).
.PARAMETER Name
    The name of the token.
.PARAMETER Value
    The token value.
.PARAMETER Category
    The semantic category.
.PARAMETER LineNumber
    The line number where the token is defined.
.PARAMETER Properties
    Additional properties for the token.
.OUTPUTS
    System.Collections.Hashtable. Structured token object.
#>
function New-DesignToken {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('color', 'typography', 'spacing', 'shadow', 'border', 'breakpoint', 'zIndex', 'opacity', 'animation', 'general')]
        [string]$TokenType,
        
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter()]
        [string]$Value = '',
        
        [Parameter()]
        [string]$Category = '',
        
        [Parameter()]
        [int]$LineNumber = 0,
        
        [Parameter()]
        [hashtable]$Properties = @{}
    )
    
    $token = @{
        tokenType = $TokenType
        name = $Name
        value = $Value
        category = $Category
        lineNumber = $LineNumber
    }
    
    # Merge additional properties
    foreach ($key in $Properties.Keys) {
        $token[$key] = $Properties[$key]
    }
    
    return $token
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Extracts design tokens from CSS or configuration files.

.DESCRIPTION
    Parses design system source files and extracts:
    - Color tokens (hex, RGB, HSL, CSS variables)
    - Typography tokens (font families, sizes, weights, line heights)
    - Spacing tokens (margins, paddings, gaps)
    - Shadow tokens
    - Border and radius tokens
    - Animation tokens
    - Z-index and opacity tokens

.PARAMETER Path
    Path to the source file to parse.

.PARAMETER Content
    Source content string (alternative to Path).

.PARAMETER TokenType
    Optional filter for specific token types.

.OUTPUTS
    System.Array. Array of design token objects.

.EXAMPLE
    $tokens = Get-DesignTokens -Path "styles/variables.css"

.EXAMPLE
    $colors = Get-DesignTokens -Path "styles/theme.scss" -TokenType color
#>
function Get-DesignTokens {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('color', 'typography', 'spacing', 'shadow', 'border', 'animation', 'all')]
        [string]$TokenType = 'all'
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
        
        $tokens = @()
        $lines = $rawContent -split "`r?`n"
        
        # Extract CSS variables
        if ($TokenType -in @('color', 'all', 'spacing', 'shadow', 'border', 'typography', 'animation')) {
            $varMatches = [regex]::Matches($rawContent, $script:Patterns.CSSVariable)
            foreach ($match in $varMatches) {
                $varName = $match.Groups['name'].Value
                $varValue = $match.Groups['value'].Value.Trim()
                $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
                
                $category = Get-ColorCategory -ColorString $varValue -VariableName $varName
                
                # Determine token type from name and value
                $detectedType = 'general'
                if ($varName -match 'color|bg|background|text|fill|stroke|border-color' -or
                    $varValue -match $script:Patterns.HexColor -or
                    $varValue -match $script:Patterns.RGBColor -or
                    $varValue -match $script:Patterns.HSLColor) {
                    $detectedType = 'color'
                }
                elseif ($varName -match 'font|text|typography') {
                    $detectedType = 'typography'
                }
                elseif ($varName -match 'space|spacing|gap|padding|margin') {
                    $detectedType = 'spacing'
                }
                elseif ($varName -match 'shadow|elevation') {
                    $detectedType = 'shadow'
                }
                elseif ($varName -match 'radius|border') {
                    $detectedType = 'border'
                }
                elseif ($varName -match 'z-index|zIndex|z') {
                    $detectedType = 'zIndex'
                }
                elseif ($varName -match 'opacity|alpha') {
                    $detectedType = 'opacity'
                }
                elseif ($varName -match 'animation|transition|duration|ease') {
                    $detectedType = 'animation'
                }
                
                if ($TokenType -eq 'all' -or $TokenType -eq $detectedType) {
                    $tokens += New-DesignToken `
                        -TokenType $detectedType `
                        -Name $varName `
                        -Value $varValue `
                        -Category $category `
                        -LineNumber $lineNumber
                }
            }
        }
        
        # Extract standalone colors (non-variable)
        if ($TokenType -in @('color', 'all')) {
            $colorMatches = [regex]::Matches($rawContent, $script:Patterns.HexColor)
            foreach ($match in $colorMatches) {
                $colorValue = $match.Value
                $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
                $normalized = ConvertTo-NormalizedColor -ColorString $colorValue
                
                # Skip if already captured as variable value
                $alreadyCaptured = $tokens | Where-Object { $_.value -eq $normalized }
                if (-not $alreadyCaptured) {
                    $tokens += New-DesignToken `
                        -TokenType 'color' `
                        -Name "color-$normalized" `
                        -Value $normalized `
                        -Category 'general' `
                        -LineNumber $lineNumber
                }
            }
        }
        
        # Extract typography
        if ($TokenType -in @('typography', 'all')) {
            $fontMatches = [regex]::Matches($rawContent, $script:Patterns.FontFamily)
            foreach ($match in $fontMatches) {
                $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
                $tokens += New-DesignToken `
                    -TokenType 'typography' `
                    -Name "font-family" `
                    -Value $match.Groups['value'].Value.Trim() `
                    -Category 'font-family' `
                    -LineNumber $lineNumber
            }
            
            $sizeMatches = [regex]::Matches($rawContent, $script:Patterns.FontSize)
            foreach ($match in $sizeMatches) {
                $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
                $tokens += New-DesignToken `
                    -TokenType 'typography' `
                    -Name "font-size" `
                    -Value $match.Groups['value'].Value.Trim() `
                    -Category 'font-size' `
                    -LineNumber $lineNumber
            }
        }
        
        # Extract shadows
        if ($TokenType -in @('shadow', 'all')) {
            $shadowMatches = [regex]::Matches($rawContent, $script:Patterns.BoxShadow)
            foreach ($match in $shadowMatches) {
                $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
                $tokens += New-DesignToken `
                    -TokenType 'shadow' `
                    -Name "box-shadow" `
                    -Value $match.Groups['value'].Value.Trim() `
                    -Category 'elevation' `
                    -LineNumber $lineNumber
            }
        }
        
        return ,$tokens
    }
    catch {
        Write-Error "[Get-DesignTokens] Failed to extract design tokens: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts theme configurations from config files.

.DESCRIPTION
    Parses theme configuration files and extracts:
    - Theme variants (light, dark, auto)
    - Color schemes
    - Typography scales
    - Spacing scales
    - Breakpoint definitions
    - Extended/custom theme properties

.PARAMETER Path
    Path to the config file to parse.

.PARAMETER Content
    Config content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Theme configuration object.

.EXAMPLE
    $theme = Get-ThemeConfigurations -Path "tailwind.config.js"
#>
function Get-ThemeConfigurations {
    [CmdletBinding()]
    [OutputType([hashtable])]
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
                return @{}
            }
            Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        } else { $Content }
        
        if ([string]::IsNullOrWhiteSpace($rawContent)) {
            return @{}
        }
        
        $theme = @{
            variants = @()
            colors = @{}
            typography = @{}
            spacing = @{}
            breakpoints = @{}
            shadows = @{}
            borderRadius = @{}
            extends = @()
            rawConfig = $rawContent
        }
        
        # Detect theme mode
        if ($rawContent -match $script:Patterns.DarkMode) {
            $theme.variants += 'dark'
        }
        if ($rawContent -notmatch 'darkOnly|forceDark') {
            $theme.variants += 'light'
        }
        
        # Check for explicit theme variant
        if ($rawContent -match $script:Patterns.ThemeVariant) {
            $variant = $matches['variant']
            if ($variant -notin $theme.variants) {
                $theme.variants += $variant
            }
        }
        
        # Extract Tailwind-style colors
        $colorSection = $false
        $lines = $rawContent -split "`r?`n"
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            
            # Detect colors section
            if ($line -match 'colors\s*:\s*\{') {
                $colorSection = $true
                continue
            }
            
            if ($colorSection) {
                # Check for section end
                if ($line -match '^\s*\},?\s*$' -and ($line -notmatch ':\s*\{' -or $line -match '^\s*\}\s*,?\s*$')) {
                    $depth = ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count - 
                             ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
                    if ($depth -gt 0) {
                        $colorSection = $false
                        continue
                    }
                }
                
                # Extract color definition
                if ($line -match "^\s*['\"]?(\w+)['\"]?\s*:\s*['\"]?([^'\"\n,]+)") {
                    $colorName = $matches[1]
                    $colorValue = $matches[2].Trim()
                    
                    if ($colorValue -match $script:Patterns.HexColor -or
                        $colorValue -match $script:Patterns.RGBColor -or
                        $colorValue -match $script:Patterns.HSLColor) {
                        $theme.colors[$colorName] = $colorValue
                    }
                }
            }
        }
        
        # Extract spacing scale
        $spacingMatches = [regex]::Matches($rawContent, $script:Patterns.SpacingScale)
        foreach ($match in $spacingMatches) {
            $name = $match.Groups['name'].Value
            $scale = $match.Groups['scale'].Value
            $theme.spacing["$name-$scale"] = $true
        }
        
        # Extract breakpoints
        $bpMatches = [regex]::Matches($rawContent, $script:Patterns.BreakpointToken)
        foreach ($match in $bpMatches) {
            $bpName = $match.Groups['name'].Value
            $theme.breakpoints[$bpName] = $true
        }
        
        # Check for media query breakpoints
        $mqMatches = [regex]::Matches($rawContent, $script:Patterns.MediaQuery)
        foreach ($match in $mqMatches) {
            $feature = $match.Groups['feature'].Value
            $theme.breakpoints[$feature] = $true
        }
        
        # Check for Tailwind extend
        if ($rawContent -match $script:Patterns.TailwindExtend) {
            $theme.extends += 'tailwind'
        }
        
        return $theme
    }
    catch {
        Write-Error "[Get-ThemeConfigurations] Failed to extract theme configuration: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Extracts style utilities from CSS/framework files.

.DESCRIPTION
    Parses style source files and extracts:
    - Utility class definitions
    - Helper functions/mixins
    - CSS-in-JS utility patterns
    - Tailwind-style utility classes

.PARAMETER Path
    Path to the source file to parse.

.PARAMETER Content
    Source content string (alternative to Path).

.OUTPUTS
    System.Array. Array of style utility objects.

.EXAMPLE
    $utilities = Get-StyleUtilities -Path "styles/utilities.css"
#>
function Get-StyleUtilities {
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
        
        $utilities = @()
        $lines = $rawContent -split "`r?`n"
        $inUtility = $false
        $currentUtility = ''
        $lineNumber = 0
        
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $lineNumber = $i + 1
            
            # Match utility class pattern (single property classes)
            if ($line -match '^\s*\.(?<name>[\w-]+)\s*\{\s*$') {
                $className = $matches['name']
                $inUtility = $true
                $currentUtility = $className
            }
            elseif ($inUtility -and $line -match '^\s*\}\s*$') {
                $inUtility = $false
                $currentUtility = ''
            }
            elseif ($inUtility -and $currentUtility) {
                # Extract property within utility
                if ($line -match '^\s*(?<prop>[\w-]+)\s*:\s*(?<val>[^;]+);') {
                    $utilities += @{
                        utilityClass = $currentUtility
                        property = $matches['prop']
                        value = $matches['val'].Trim()
                        lineNumber = $lineNumber
                        isSingleProperty = $true
                    }
                }
            }
        }
        
        # Extract Tailwind-style utilities from config
        if ($rawContent -match $script:Patterns.TailwindConfig) {
            # Look for utility definitions in theme.extend
            $extendMatches = [regex]::Matches($rawContent, '(\w+)\s*:\s*\{([^}]+)\}')
            foreach ($match in $extendMatches) {
                $category = $match.Groups[1].Value
                $content = $match.Groups[2].Value
                
                # Parse key-value pairs
                $kvMatches = [regex]::Matches($content, "['\"]?(\w+)['\"]?\s*:\s*['\"]?([^'\"\n,]+)")
                foreach ($kv in $kvMatches) {
                    $key = $kv.Groups[1].Value
                    $value = $kv.Groups[2].Value.Trim()
                    
                    $utilities += @{
                        utilityClass = "$category-$key"
                        category = $category
                        value = $value
                        source = 'tailwind-config'
                        isSingleProperty = $false
                    }
                }
            }
        }
        
        return ,$utilities
    }
    catch {
        Write-Error "[Get-StyleUtilities] Failed to extract style utilities: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts documentation patterns from Storybook and MDX files.

.DESCRIPTION
    Parses documentation files and extracts:
    - Storybook story definitions
    - Component documentation structure
    - Usage examples
    - Prop documentation tables

.PARAMETER Path
    Path to the documentation file to parse.

.PARAMETER Content
    Documentation content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Documentation patterns object.

.EXAMPLE
    $docs = Get-DocumentationPatterns -Path "Button.stories.tsx"
#>
function Get-DocumentationPatterns {
    [CmdletBinding()]
    [OutputType([hashtable])]
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
                return @{}
            }
            Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        } else { $Content }
        
        if ([string]::IsNullOrWhiteSpace($rawContent)) {
            return @{}
        }
        
        $docs = @{
            stories = @()
            meta = @{}
            examples = @()
            hasMDX = $false
            docType = 'unknown'
        }
        
        # Detect file type
        if ($Path -match '\.stories\.(tsx?|jsx?)$') {
            $docs.docType = 'storybook-csf'
        }
        elseif ($Path -match '\.mdx$') {
            $docs.docType = 'mdx'
            $docs.hasMDX = $true
        }
        
        # Extract Storybook meta
        if ($rawContent -match $script:Patterns.StoryMeta) {
            $docs.meta['hasMeta'] = $true
            
            # Try to extract component reference
            if ($rawContent -match 'component\s*:\s*(\w+)') {
                $docs.meta['component'] = $matches[1]
            }
            
            # Extract title
            if ($rawContent -match 'title\s*:\s*["\']([^"\']+)') {
                $docs.meta['title'] = $matches[1]
            }
        }
        
        # Extract stories
        $storyMatches = [regex]::Matches($rawContent, $script:Patterns.StorybookStory)
        foreach ($match in $storyMatches) {
            $storyName = $match.Groups['name'].Value
            $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
            
            $docs.stories += @{
                name = $storyName
                exportName = $storyName
                lineNumber = $lineNumber
            }
        }
        
        # Also match simpler story patterns
        $simpleStoryMatches = [regex]::Matches($rawContent, 'export\s+const\s+(\w+)\s*=\s*\(')
        foreach ($match in $simpleStoryMatches) {
            $storyName = $match.Groups[1].Value
            
            # Skip if already captured
            $existing = $docs.stories | Where-Object { $_.name -eq $storyName }
            if (-not $existing) {
                $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
                $docs.stories += @{
                    name = $storyName
                    exportName = $storyName
                    lineNumber = $lineNumber
                }
            }
        }
        
        # Extract MDX headings as documentation structure
        if ($docs.docType -eq 'mdx' -or $rawContent -match '^#+\s+\w+') {
            $headingMatches = [regex]::Matches($rawContent, '^(#{1,6})\s+(.+)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            foreach ($match in $headingMatches) {
                $level = $match.Groups[1].Value.Length
                $text = $match.Groups[2].Value.Trim()
                $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
                
                $docs.examples += @{
                    type = 'heading'
                    level = $level
                    text = $text
                    lineNumber = $lineNumber
                }
            }
        }
        
        # Extract code blocks as examples
        $codeBlockMatches = [regex]::Matches($rawContent, '```(\w+)?\s*\n([\s\S]*?)```')
        foreach ($match in $codeBlockMatches) {
            $lang = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { 'text' }
            $code = $match.Groups[2].Value.Trim()
            $lineNumber = ($rawContent.Substring(0, $match.Index) -split "`r?`n").Count
            
            $docs.examples += @{
                type = 'code-block'
                language = $lang
                code = $code
                lineNumber = $lineNumber
            }
        }
        
        return $docs
    }
    catch {
        Write-Error "[Get-DocumentationPatterns] Failed to extract documentation patterns: $_"
        return @{}
    }
}

# Export functions
Export-ModuleMember -Function Get-DesignTokens, Get-ThemeConfigurations, Get-StyleUtilities, Get-DocumentationPatterns
